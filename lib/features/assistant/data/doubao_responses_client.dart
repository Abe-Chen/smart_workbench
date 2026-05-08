import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env_config.dart';
import '../application/assistant_state.dart';
import '../domain/assistant_execution_mode.dart';
import 'ark_network_probe.dart';
import '../prompts/system_prompt.dart';

const String _arkBaseUrl = 'https://$kArkHost/api/v3';

class DoubaoResponsesException implements Exception {
  DoubaoResponsesException({
    required this.type,
    required this.message,
    this.retryable = true,
  });

  final AssistantErrorType type;
  final String message;
  final bool retryable;

  AssistantErrorState toErrorState() =>
      AssistantErrorState(type: type, message: message, retryable: retryable);

  @override
  String toString() => 'DoubaoResponsesException($type): $message';
}

class DoubaoResponsesResult {
  const DoubaoResponsesResult({required this.id, required this.text});

  final String id;
  final String text;
}

sealed class PublicResponseEvent {}

class PublicResponseRequestAcceptedEvent extends PublicResponseEvent {
  PublicResponseRequestAcceptedEvent(this.responseId);
  final String? responseId;
}

class PublicResponseSearchStartedEvent extends PublicResponseEvent {}

class PublicResponseSearchCompletedEvent extends PublicResponseEvent {}

class PublicResponseTextDeltaEvent extends PublicResponseEvent {
  PublicResponseTextDeltaEvent(this.delta);
  final String delta;
}

class PublicResponseCompletedEvent extends PublicResponseEvent {
  PublicResponseCompletedEvent({required this.responseId, required this.text});

  final String responseId;
  final String text;
}

class DoubaoResponsesClient {
  DoubaoResponsesClient({
    required EnvConfig env,
    Dio? dio,
    ArkNetworkProbe? probe,
  }) : _env = env,
       _probe = probe ?? ArkNetworkProbe(),
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 10),
               sendTimeout: const Duration(seconds: 15),
             ),
           );

  final EnvConfig _env;
  final ArkNetworkProbe _probe;
  final Dio _dio;

  Future<DoubaoResponsesResult> createPublicResponse({
    required String userText,
    required AssistantExecutionMode mode,
    String? previousResponseId,
    bool summaryOnly = false,
  }) async {
    if (!_env.hasDoubaoCredentials) {
      throw DoubaoResponsesException(
        type: AssistantErrorType.configMissing,
        retryable: false,
        message: '豆包凭据未配置：检查 .env 中 VOLC_ARK_API_KEY / DOUBAO_ENDPOINT_ID',
      );
    }

    await _ensureReachable();

    late final Response<Map<String, dynamic>> response;
    try {
      response = await _dio.post<Map<String, dynamic>>(
        '$_arkBaseUrl/responses',
        options: Options(headers: _headers(acceptStream: false)),
        data: _buildRequestBody(
          userText: userText,
          previousResponseId: previousResponseId,
          mode: mode,
          summaryOnly: summaryOnly,
          stream: false,
        ),
      );
    } on DioException catch (e) {
      throw _buildDioException(e);
    }

    final Map<String, dynamic>? data = response.data;
    if (data == null) {
      throw DoubaoResponsesException(
        type: AssistantErrorType.emptyResponse,
        message: 'Responses API 返回空',
      );
    }

    final String id = _readResponseId(data);
    final String text = _extractOutputText(data).trim();
    if (id.isEmpty) {
      throw DoubaoResponsesException(
        type: AssistantErrorType.parseError,
        message: 'Responses API 返回缺少 response id',
      );
    }
    if (text.isEmpty) {
      throw DoubaoResponsesException(
        type: AssistantErrorType.emptyResponse,
        message: 'Responses API 未返回可展示的文本',
      );
    }

    return DoubaoResponsesResult(id: id, text: text);
  }

  Stream<PublicResponseEvent> streamPublicResponse({
    required String userText,
    required AssistantExecutionMode mode,
    String? previousResponseId,
    bool summaryOnly = false,
    CancelToken? cancelToken,
  }) {
    final StreamController<PublicResponseEvent> controller =
        StreamController<PublicResponseEvent>();
    _startStreamPublicResponse(
      controller: controller,
      userText: userText,
      mode: mode,
      previousResponseId: previousResponseId,
      summaryOnly: summaryOnly,
      cancelToken: cancelToken,
    );
    return controller.stream;
  }

  Future<void> _startStreamPublicResponse({
    required StreamController<PublicResponseEvent> controller,
    required String userText,
    required AssistantExecutionMode mode,
    String? previousResponseId,
    required bool summaryOnly,
    CancelToken? cancelToken,
  }) async {
    if (!_env.hasDoubaoCredentials) {
      controller.addError(
        DoubaoResponsesException(
          type: AssistantErrorType.configMissing,
          retryable: false,
          message: '豆包凭据未配置：检查 .env 中 VOLC_ARK_API_KEY / DOUBAO_ENDPOINT_ID',
        ),
      );
      await controller.close();
      return;
    }

    try {
      await _ensureReachable();
    } catch (e) {
      controller.addError(e);
      await controller.close();
      return;
    }

    final CancelToken token = cancelToken ?? CancelToken();
    late final Response<ResponseBody> response;
    try {
      response = await _dio.post<ResponseBody>(
        '$_arkBaseUrl/responses',
        cancelToken: token,
        options: Options(
          responseType: ResponseType.stream,
          headers: _headers(acceptStream: true),
        ),
        data: _buildRequestBody(
          userText: userText,
          previousResponseId: previousResponseId,
          mode: mode,
          summaryOnly: summaryOnly,
          stream: true,
        ),
      );
    } on DioException catch (e) {
      controller.addError(_buildDioException(e));
      await controller.close();
      return;
    } catch (e) {
      controller.addError(e);
      await controller.close();
      return;
    }

    final ResponseBody? respBody = response.data;
    if (respBody == null) {
      controller.addError(
        DoubaoResponsesException(
          type: AssistantErrorType.emptyResponse,
          message: 'Responses API 返回空流',
        ),
      );
      await controller.close();
      return;
    }

    final Stream<String> lines = respBody.stream
        .map<List<int>>((List<int> bytes) => bytes)
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    final StringBuffer contentBuffer = StringBuffer();
    String? latestResponseId;
    String? eventName;
    final List<String> dataLines = <String>[];

    Future<void> flushEvent() async {
      if (dataLines.isEmpty) {
        eventName = null;
        return;
      }
      final String payload = dataLines.join('\n').trim();
      dataLines.clear();
      if (payload == '[DONE]') {
        eventName = null;
        return;
      }

      Map<String, dynamic>? json;
      try {
        json = jsonDecode(payload) as Map<String, dynamic>;
      } catch (_) {
        eventName = null;
        return;
      }
      final String type = eventName ?? _readString(json['type']);
      final Iterable<PublicResponseEvent> events = _mapEventsFromJson(
        type: type,
        json: json,
        contentBuffer: contentBuffer,
      );
      for (final PublicResponseEvent event in events) {
        if (event is PublicResponseRequestAcceptedEvent &&
            event.responseId != null &&
            event.responseId!.isNotEmpty) {
          latestResponseId = event.responseId;
        } else if (event is PublicResponseCompletedEvent) {
          latestResponseId = event.responseId;
        }
        controller.add(event);
      }
      eventName = null;
    }

    try {
      await for (final String rawLine in lines) {
        if (token.isCancelled) {
          throw DoubaoResponsesException(
            type: AssistantErrorType.cancelledByUser,
            retryable: false,
            message: '豆包请求已取消',
          );
        }
        final String line = rawLine.trimRight();
        if (line.isEmpty) {
          await flushEvent();
          continue;
        }
        if (line.startsWith('event:')) {
          eventName = line.substring(6).trim();
          continue;
        }
        if (line.startsWith('data:')) {
          dataLines.add(line.substring(5).trimLeft());
        }
      }
      await flushEvent();

      final String finalText = contentBuffer.toString().trim();
      if (finalText.isEmpty) {
        throw DoubaoResponsesException(
          type: AssistantErrorType.emptyResponse,
          message: 'Responses API 未返回可展示的文本',
        );
      }

      controller.add(
        PublicResponseCompletedEvent(
          responseId: latestResponseId ?? '',
          text: finalText,
        ),
      );
    } catch (e) {
      controller.addError(e);
    } finally {
      await controller.close();
    }
  }

  Future<void> _ensureReachable() async {
    try {
      await _probe.ensureReachable();
    } on ArkNetworkUnavailableException {
      throw DoubaoResponsesException(
        type: AssistantErrorType.networkUnavailable,
        message: '当前网络不可用，请检查网络后重试',
      );
    }
  }

  Map<String, String> _headers({required bool acceptStream}) {
    return <String, String>{
      'Authorization': 'Bearer ${_env.volcArkApiKey}',
      'Content-Type': 'application/json',
      if (acceptStream) 'Accept': 'text/event-stream',
    };
  }

  Map<String, dynamic> _buildRequestBody({
    required String userText,
    required AssistantExecutionMode mode,
    required bool summaryOnly,
    required bool stream,
    String? previousResponseId,
  }) {
    final bool continued =
        previousResponseId != null && previousResponseId.trim().isNotEmpty;
    final List<Map<String, dynamic>> input = <Map<String, dynamic>>[
      if (!continued)
        _textInputMessage('system', kAssistantPublicResponsesPrompt),
      _textInputMessage(
        'system',
        buildAssistantPublicModePrompt(mode, summaryOnly: summaryOnly),
      ),
      _textInputMessage('user', userText),
    ];

    return <String, dynamic>{
      'model': _env.doubaoEndpointId,
      'stream': stream,
      'input': input,
      if (_shouldUseWebSearch(mode))
        'tools': const <Map<String, dynamic>>[
          <String, dynamic>{'type': 'web_search'},
        ],
      if (continued) 'previous_response_id': previousResponseId,
    };
  }

  bool _shouldUseWebSearch(AssistantExecutionMode mode) {
    return mode == AssistantExecutionMode.publicRealtime ||
        mode == AssistantExecutionMode.publicDeep;
  }

  Iterable<PublicResponseEvent> _mapEventsFromJson({
    required String type,
    required Map<String, dynamic> json,
    required StringBuffer contentBuffer,
  }) sync* {
    final String normalizedType = type.trim();
    final String responseId = _readResponseId(json);

    if (normalizedType == 'response.created' ||
        normalizedType == 'response.in_progress') {
      yield PublicResponseRequestAcceptedEvent(
        responseId.isEmpty ? null : responseId,
      );
    }

    if (normalizedType == 'response.web_search_call.in_progress') {
      yield PublicResponseSearchStartedEvent();
    }
    if (normalizedType == 'response.web_search_call.completed') {
      yield PublicResponseSearchCompletedEvent();
    }

    if (normalizedType == 'response.output_text.delta') {
      final String delta = _readString(json['delta']);
      if (delta.isNotEmpty) {
        contentBuffer.write(delta);
        yield PublicResponseTextDeltaEvent(delta);
      }
      return;
    }

    if (normalizedType == 'response.output_text.done') {
      final String text = _readString(json['text']).isNotEmpty
          ? _readString(json['text'])
          : _readString(json['delta']);
      if (text.isNotEmpty && contentBuffer.isEmpty) {
        contentBuffer.write(text);
        yield PublicResponseTextDeltaEvent(text);
      }
      return;
    }

    if (normalizedType == 'response.failed' ||
        normalizedType == 'response.error') {
      final Map<String, dynamic>? error =
          json['error'] as Map<String, dynamic>?;
      throw DoubaoResponsesException(
        type: AssistantErrorType.serverRejected,
        message: _readString(error?['message']).isEmpty
            ? 'Responses API 调用失败'
            : _readString(error?['message']),
      );
    }

    if (normalizedType == 'response.completed') {
      final String text = _extractOutputText(json).trim();
      if (text.isNotEmpty && contentBuffer.isEmpty) {
        contentBuffer.write(text);
        yield PublicResponseTextDeltaEvent(text);
      }
      return;
    }

    if (normalizedType.isEmpty) {
      final String delta = _readString(json['delta']);
      if (delta.isNotEmpty) {
        contentBuffer.write(delta);
        yield PublicResponseTextDeltaEvent(delta);
        return;
      }
      final String text = _extractOutputText(json).trim();
      if (text.isNotEmpty && contentBuffer.isEmpty) {
        contentBuffer.write(text);
        yield PublicResponseTextDeltaEvent(text);
      }
    }
  }

  static String _readResponseId(Map<String, dynamic> data) {
    final String direct = _readString(data['id']);
    if (direct.isNotEmpty) {
      return direct;
    }
    final Map<String, dynamic>? response =
        data['response'] as Map<String, dynamic>?;
    return _readString(response?['id']);
  }

  static String _extractOutputText(Map<String, dynamic> data) {
    final String direct = _readString(data['output_text']);
    if (direct.isNotEmpty) {
      return direct;
    }
    final Map<String, dynamic>? response =
        data['response'] as Map<String, dynamic>?;
    final String nested = response == null ? '' : _extractOutputText(response);
    if (nested.isNotEmpty) {
      return nested;
    }

    final List<dynamic> output =
        data['output'] as List<dynamic>? ?? <dynamic>[];
    final StringBuffer buffer = StringBuffer();
    for (final dynamic item in output) {
      if (item is! Map<String, dynamic>) continue;
      final List<dynamic> contents =
          item['content'] as List<dynamic>? ?? <dynamic>[];
      for (final dynamic rawContent in contents) {
        if (rawContent is! Map<String, dynamic>) continue;
        final String type = _readString(rawContent['type']);
        if (type == 'output_text' || type == 'text') {
          final String text = _readString(rawContent['text']);
          if (text.isNotEmpty) {
            if (buffer.isNotEmpty) {
              buffer.write('\n');
            }
            buffer.write(text);
          }
        }
      }
    }
    if (buffer.isNotEmpty) {
      return buffer.toString();
    }

    return _extractTextRecursively(data);
  }

  static String _extractTextRecursively(Object? node) {
    if (node == null) {
      return '';
    }
    if (node is String) {
      return node;
    }
    if (node is List<dynamic>) {
      final StringBuffer buffer = StringBuffer();
      for (final dynamic item in node) {
        final String text = _extractTextRecursively(item);
        if (text.isEmpty) continue;
        if (buffer.isNotEmpty) {
          buffer.write('\n');
        }
        buffer.write(text);
      }
      return buffer.toString();
    }
    if (node is Map<String, dynamic>) {
      final String type = _readString(node['type']);
      if (type == 'output_text' || type == 'text') {
        final String text = _readString(node['text']);
        if (text.isNotEmpty) {
          return text;
        }
      }
      final StringBuffer buffer = StringBuffer();
      for (final MapEntry<String, dynamic> entry in node.entries) {
        if (entry.key == 'text') continue;
        final String text = _extractTextRecursively(entry.value);
        if (text.isEmpty) continue;
        if (buffer.isNotEmpty) {
          buffer.write('\n');
        }
        buffer.write(text);
      }
      return buffer.toString();
    }
    return '';
  }
}

Map<String, dynamic> _textInputMessage(String role, String text) {
  return <String, dynamic>{
    'role': role,
    'content': <Map<String, dynamic>>[
      <String, dynamic>{'type': 'input_text', 'text': text},
    ],
  };
}

DoubaoResponsesException _buildDioException(DioException error) {
  if (CancelToken.isCancel(error)) {
    return DoubaoResponsesException(
      type: AssistantErrorType.cancelledByUser,
      retryable: false,
      message: '豆包请求已取消',
    );
  }
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
      return DoubaoResponsesException(
        type: AssistantErrorType.connectionTimeout,
        message: '连接豆包超时，网络可能较慢，请稍后重试',
      );
    case DioExceptionType.sendTimeout:
      return DoubaoResponsesException(
        type: AssistantErrorType.sendTimeout,
        message: '请求发送超时，请稍后重试',
      );
    case DioExceptionType.connectionError:
      return DoubaoResponsesException(
        type: AssistantErrorType.networkUnavailable,
        message: '豆包连接失败：当前网络可能不可用，请检查网络后重试',
      );
    case DioExceptionType.badCertificate:
      return DoubaoResponsesException(
        type: AssistantErrorType.networkUnavailable,
        message: '豆包证书校验失败：当前网络环境可能异常',
      );
    case DioExceptionType.badResponse:
    case DioExceptionType.cancel:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.unknown:
      break;
  }

  final Object? data = error.response?.data;
  String detail = '';
  if (data is Map<String, dynamic>) {
    final Map<String, dynamic>? innerError =
        data['error'] as Map<String, dynamic>?;
    detail = _readString(innerError?['message']);
    detail = detail.isEmpty ? _readString(data['message']) : detail;
  } else if (data != null) {
    detail = data.toString();
  }

  final int? statusCode = error.response?.statusCode;
  if (statusCode == 401 || statusCode == 403) {
    return DoubaoResponsesException(
      type: AssistantErrorType.unauthorized,
      retryable: false,
      message: detail.isEmpty ? '豆包鉴权失败，请检查密钥或 endpoint' : detail,
    );
  }
  if (statusCode == 429) {
    return DoubaoResponsesException(
      type: AssistantErrorType.rateLimited,
      message: detail.isEmpty ? '当前请求较多，请稍后再试' : detail,
    );
  }
  if (statusCode != null && statusCode >= 500) {
    return DoubaoResponsesException(
      type: AssistantErrorType.serverRejected,
      message: detail.isEmpty ? '豆包服务暂时不可用，请稍后重试' : detail,
    );
  }
  if (detail.isNotEmpty) {
    return DoubaoResponsesException(
      type: AssistantErrorType.serverRejected,
      message: detail,
    );
  }
  return DoubaoResponsesException(
    type: AssistantErrorType.unknown,
    message: 'Responses API 网络异常：${error.message}',
  );
}

String _readString(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  return value.toString();
}

final Provider<DoubaoResponsesClient> doubaoResponsesClientProvider =
    Provider<DoubaoResponsesClient>((Ref ref) {
      final EnvConfig env = ref.watch(envConfigProvider);
      final ArkNetworkProbe probe = ref.watch(arkNetworkProbeProvider);
      return DoubaoResponsesClient(env: env, probe: probe);
    });
