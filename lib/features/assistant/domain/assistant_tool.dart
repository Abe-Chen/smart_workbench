/// 应用层定义的可被豆包模型 function call 调用的工具。
abstract class AssistantTool {
  String get name;
  String get description;

  /// JSON Schema，描述参数，例：
  /// {"type": "object", "properties": {...}, "required": [...]}
  Map<String, dynamic> get parametersSchema;

  /// 模型决定调用此工具时执行。返回的字符串作为 tool message 的 content
  /// 喂回模型继续生成最终回答。
  Future<String> call(Map<String, dynamic> args);

  /// 转成 chat completions API 的 tools 数组成员。
  Map<String, dynamic> toApiJson() => <String, dynamic>{
    'type': 'function',
    'function': <String, dynamic>{
      'name': name,
      'description': description,
      'parameters': parametersSchema,
    },
  };
}
