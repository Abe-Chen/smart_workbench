import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env_config.dart';
import 'ark_network_probe.dart';
import '../prompts/system_prompt.dart';

const String _arkBaseUrl = 'https://$kArkHost/api/v3';

class DoubaoResponsesException implements Exception {
  DoubaoResponsesException(this.message);

  final String message;

  @override
  String toString() => 'DoubaoResponsesException: $message';
}

class DoubaoResponsesResult {
  const DoubaoResponsesResult({required this.id, required this.text});

  final String id;
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
               receiveTimeout: const Duration(seconds: 25),
             ),
           );

  final EnvConfig _env;
  final ArkNetworkProbe _probe;
  final Dio _dio;

  Future<DoubaoResponsesResult> createPublicResponse({
    required String userText,
    String? previousResponseId,
  }) async {
    if (!_env.hasDoubaoCredentials) {
      throw DoubaoResponsesException(
        '豆包凭据未配置：检查 .env 中 VOLC_ARK_API_KEY / DOUBAO_ENDPOINT_ID',
      );
    }

    try {
      await _probe.ensureReachable();
    } on ArkNetworkUnavailableException {
      throw DoubaoResponsesException('当前网络不可用，请检查网络后重试');
    }

    final bool continued =
        previousResponseId != null && previousResponseId.trim().isNotEmpty;
    final List<Map<String, dynamic>> input = <Map<String, dynamic>>[
      if (!continued)
        _textInputMessage('system', kAssistantPublicResponsesPrompt),
      _textInputMessage('user', userText),
    ];

    final Map<String, dynamic> body = <String, dynamic>{
      'model': _env.doubaoEndpointId,
      'input': input,
      'tools': const <Map<String, dynamic>>[
        <String, dynamic>{'type': 'web_search'},
      ],
      if (continued) 'previous_response_id': previousResponseId,
    };

    late final Response<Map<String, dynamic>> response;
    try {
      response = await _dio.post<Map<String, dynamic>>(
        '$_arkBaseUrl/responses',
        options: Options(
          headers: <String, String>{
            'Authorization': 'Bearer ${_env.volcArkApiKey}',
            'Content-Type': 'application/json',
          },
        ),
        data: body,
      );
    } on DioException catch (e) {
      throw DoubaoResponsesException(_buildDioMessage(e));
    }

    final Map<String, dynamic>? data = response.data;
    if (data == null) {
      throw DoubaoResponsesException('Responses API 返回空');
    }

    final Map<String, dynamic>? error = data['error'] as Map<String, dynamic>?;
    if (error != null) {
      final String message = _readString(error['message']);
      throw DoubaoResponsesException(
        message.isEmpty ? 'Responses API 调用失败' : message,
      );
    }

    final String id = _readString(data['id']);
    final String text = _extractOutputText(data).trim();
    if (id.isEmpty) {
      throw DoubaoResponsesException('Responses API 返回缺少 response id');
    }
    if (text.isEmpty) {
      throw DoubaoResponsesException('Responses API 未返回可展示的文本');
    }

    return DoubaoResponsesResult(id: id, text: text);
  }

  static String _extractOutputText(Map<String, dynamic> data) {
    final String direct = _readString(data['output_text']);
    if (direct.isNotEmpty) {
      return direct;
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

String _buildDioMessage(DioException error) {
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
      return '豆包连接超时：当前网络可能不可用，请检查网络后重试';
    case DioExceptionType.sendTimeout:
      return '豆包发送超时：当前网络不稳定，请稍后重试';
    case DioExceptionType.receiveTimeout:
      return '豆包响应超时：25 秒内没有拿到结果，通常是当前网络断开或不稳定';
    case DioExceptionType.connectionError:
      return '豆包连接失败：当前网络可能不可用，请检查网络后重试';
    case DioExceptionType.badCertificate:
      return '豆包证书校验失败：当前网络环境可能异常';
    case DioExceptionType.cancel:
      return '豆包请求已取消';
    case DioExceptionType.badResponse:
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
  if (detail.isNotEmpty && statusCode != null) {
    return 'Responses API 失败（$statusCode）：$detail';
  }
  if (detail.isNotEmpty) {
    return 'Responses API 失败：$detail';
  }
  if (statusCode != null) {
    return 'Responses API 失败（$statusCode）';
  }
  return 'Responses API 网络异常：${error.message}';
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
