import 'dart:convert';

class ToolCall {
  ToolCall({
    required this.id,
    required this.name,
    required this.argumentsJson,
  });

  /// API 返回的 call id，回传 tool result 时必填。
  final String id;
  final String name;

  /// 流式时模型可能分多次给 arguments，最终拼成完整 JSON。
  final String argumentsJson;

  Map<String, dynamic> argumentsAsMap() {
    if (argumentsJson.isEmpty) return const <String, dynamic>{};
    try {
      final Object? decoded = jsonDecode(argumentsJson);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return const <String, dynamic>{};
  }

  ToolCall copyWith({String? argumentsJson}) {
    return ToolCall(
      id: id,
      name: name,
      argumentsJson: argumentsJson ?? this.argumentsJson,
    );
  }

  Map<String, dynamic> toApiJson() => <String, dynamic>{
    'id': id,
    'type': 'function',
    'function': <String, dynamic>{
      'name': name,
      'arguments': argumentsJson.isEmpty ? '{}' : argumentsJson,
    },
  };
}
