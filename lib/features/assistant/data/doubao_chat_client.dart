import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env_config.dart';
import 'ark_network_probe.dart';
import '../domain/assistant_message.dart';
import '../domain/tool_call.dart';

const String _arkBaseUrl = 'https://$kArkHost/api/v3';

class DoubaoChatException implements Exception {
  DoubaoChatException(this.message);
  final String message;
  @override
  String toString() => 'DoubaoChatException: $message';
}

/// 流式事件：每个 token 一个 [ChatTokenEvent]，每轮结束（无论有无 tool_calls）
/// 一个 [ChatRoundCompleteEvent]。controller 据此决定是否进入下一轮 function call。
sealed class ChatStreamEvent {}

class ChatTokenEvent extends ChatStreamEvent {
  ChatTokenEvent(this.token);
  final String token;
}

class ChatRoundCompleteEvent extends ChatStreamEvent {
  ChatRoundCompleteEvent({
    required this.content,
    required this.toolCalls,
    required this.finishReason,
  });

  /// 本轮累计的 assistant 文本（流式拼好的完整内容）。
  final String content;

  /// 本轮模型请求调用的工具列表（空表示纯文本回答）。
  final List<ToolCall> toolCalls;

  final String finishReason;

  bool get hasToolCalls => toolCalls.isNotEmpty;
}

class DoubaoChatClient {
  DoubaoChatClient({required EnvConfig env, Dio? dio, ArkNetworkProbe? probe})
    : _env = env,
      _probe = probe ?? ArkNetworkProbe(),
      _dio =
          dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));

  final EnvConfig _env;
  final ArkNetworkProbe _probe;
  final Dio _dio;

  Stream<ChatStreamEvent> streamCompletion({
    required List<AssistantMessage> messages,
    String? userId,
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
  }) async* {
    if (!_env.hasDoubaoCredentials) {
      throw DoubaoChatException(
        '豆包凭据未配置：检查 .env 中 VOLC_ARK_API_KEY / DOUBAO_ENDPOINT_ID',
      );
    }

    try {
      await _probe.ensureReachable();
    } on ArkNetworkUnavailableException {
      throw DoubaoChatException('当前网络不可用，请检查网络后重试');
    }

    final Map<String, dynamic> body = <String, dynamic>{
      'model': _env.doubaoEndpointId,
      'stream': true,
      'temperature': temperature,
      if (userId != null && userId.isNotEmpty) 'user': userId,
      'messages': messages.map((AssistantMessage m) => m.toApiJson()).toList(),
    };
    if (tools != null && tools.isNotEmpty) {
      body['tools'] = tools;
    }

    _doubaoChatDebugLog(
      'request stream=true messages=${messages.length} '
      'tools=${_toolNamesForLog(tools)} lastUser="${_lastUserForLog(messages)}"',
    );
    _doubaoChatDebugLog('request body=${_jsonForLog(body)}');

    late final Response<ResponseBody> response;
    try {
      response = await _dio.post<ResponseBody>(
        '$_arkBaseUrl/chat/completions',
        options: Options(
          responseType: ResponseType.stream,
          headers: <String, String>{
            'Authorization': 'Bearer ${_env.volcArkApiKey}',
            'Content-Type': 'application/json',
            'Accept': 'text/event-stream',
          },
        ),
        data: body,
      );
      _doubaoChatDebugLog('response status=${response.statusCode}');
    } on DioException catch (e) {
      _doubaoChatDebugLog(
        'dio error type=${e.type} status=${e.response?.statusCode} '
        'message=${e.message} data=${_jsonForLog(e.response?.data)}',
      );
      rethrow;
    } catch (e) {
      _doubaoChatDebugLog('request error=$e');
      rethrow;
    }

    final ResponseBody? respBody = response.data;
    if (respBody == null) {
      _doubaoChatDebugLog('empty response body');
      throw DoubaoChatException('空响应');
    }

    final Stream<String> lines = respBody.stream
        .map<List<int>>((List<int> bytes) => bytes)
        .transform<String>(utf8.decoder)
        .transform<String>(const LineSplitter());

    final StringBuffer contentBuffer = StringBuffer();
    final Map<int, _ToolCallBuilder> toolBuilders = <int, _ToolCallBuilder>{};
    String finishReason = 'stop';

    await for (final String rawLine in lines) {
      final String line = rawLine.trim();
      if (line.isEmpty) continue;
      if (!line.startsWith('data:')) continue;

      final String payload = line.substring(5).trim();
      if (payload == '[DONE]') break;

      Map<String, dynamic>? json;
      try {
        json = jsonDecode(payload) as Map<String, dynamic>;
      } catch (e) {
        _doubaoChatDebugLog('sse json parse ignored error=$e payload=$payload');
        continue;
      }

      final List<dynamic>? choices = json['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) continue;
      final Map<String, dynamic> first = choices.first as Map<String, dynamic>;
      final Map<String, dynamic>? delta =
          first['delta'] as Map<String, dynamic>?;
      final String? finish = first['finish_reason'] as String?;

      if (delta != null) {
        final String? deltaContent = delta['content'] as String?;
        if (deltaContent != null && deltaContent.isNotEmpty) {
          contentBuffer.write(deltaContent);
          _doubaoChatDebugLog('delta content="${_clipLog(deltaContent)}"');
          yield ChatTokenEvent(deltaContent);
        }
        final List<dynamic>? toolDeltas = delta['tool_calls'] as List<dynamic>?;
        if (toolDeltas != null) {
          for (final dynamic raw in toolDeltas) {
            if (raw is! Map<String, dynamic>) continue;
            final int index = (raw['index'] as int?) ?? 0;
            final _ToolCallBuilder b = toolBuilders.putIfAbsent(
              index,
              _ToolCallBuilder.new,
            );
            final String? id = raw['id'] as String?;
            if (id != null) b.id = id;
            final Map<String, dynamic>? fn =
                raw['function'] as Map<String, dynamic>?;
            if (fn != null) {
              final String? n = fn['name'] as String?;
              if (n != null) b.name = n;
              final String? a = fn['arguments'] as String?;
              if (a != null) b.arguments.write(a);
            }
            _doubaoChatDebugLog('delta tool_call=${_jsonForLog(raw)}');
          }
        }
      }

      if (finish != null) {
        finishReason = finish;
        _doubaoChatDebugLog('finish_reason=$finishReason');
      }
    }

    final List<ToolCall> toolCalls = toolBuilders.values
        .where((_ToolCallBuilder b) => b.isValid)
        .map((_ToolCallBuilder b) => b.build())
        .toList();

    yield ChatRoundCompleteEvent(
      content: contentBuffer.toString(),
      toolCalls: toolCalls,
      finishReason: finishReason,
    );
    _doubaoChatDebugLog(
      'complete finish_reason=$finishReason '
      'content="${_clipLog(contentBuffer.toString(), max: 1200)}" '
      'toolCalls=${toolCalls.map((ToolCall call) => '${call.name}:${_clipLog(call.argumentsJson)}').toList()}',
    );
  }
}

class _ToolCallBuilder {
  String? id;
  String? name;
  final StringBuffer arguments = StringBuffer();

  bool get isValid => id != null && name != null;

  ToolCall build() =>
      ToolCall(id: id!, name: name!, argumentsJson: arguments.toString());
}

final Provider<DoubaoChatClient> doubaoChatClientProvider =
    Provider<DoubaoChatClient>((Ref ref) {
      final EnvConfig env = ref.watch(envConfigProvider);
      final ArkNetworkProbe probe = ref.watch(arkNetworkProbeProvider);
      return DoubaoChatClient(env: env, probe: probe);
    });

void _doubaoChatDebugLog(String message) {
  if (!kDebugMode) return;
  debugPrint('[DoubaoChat] $message');
}

String _toolNamesForLog(List<Map<String, dynamic>>? tools) {
  if (tools == null || tools.isEmpty) return '[]';
  final List<String> names = <String>[];
  for (final Map<String, dynamic> tool in tools) {
    final Object? function = tool['function'];
    if (function is Map<String, dynamic>) {
      names.add((function['name'] as Object?)?.toString() ?? 'unknown');
    } else {
      names.add((tool['name'] as Object?)?.toString() ?? 'unknown');
    }
  }
  return names.toString();
}

String _lastUserForLog(List<AssistantMessage> messages) {
  for (final AssistantMessage message in messages.reversed) {
    if (message.role == AssistantRole.user) {
      return _clipLog(message.content, max: 500);
    }
  }
  return '';
}

String _jsonForLog(Object? value, {int max = 1600}) {
  try {
    return _clipLog(jsonEncode(value), max: max);
  } catch (_) {
    return _clipLog(value, max: max);
  }
}

String _clipLog(Object? value, {int max = 800}) {
  final String text = value?.toString() ?? '';
  if (text.length <= max) return text;
  return '${text.substring(0, max)}...(${text.length} chars)';
}
