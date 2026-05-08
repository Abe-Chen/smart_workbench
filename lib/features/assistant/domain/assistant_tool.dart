import 'assistant_confirm_preview.dart';

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

  /// 写入类工具实现此方法，给 ConfirmCard 渲染预览数据。
  /// 返回 null（默认）= 该 tool_call 直接执行，不进 confirm。
  ///
  /// 调用时机：controller 收到模型返回的 tool_call，**还未** invoke `call()`，
  /// 用 args 调本方法判断是否需要确认。
  ///
  /// 实现侧注意：本方法可以读 repository 做必要的字段补全（例如根据 task_id
  /// 拿现有 title 用于 update 卡片），但**不能**触发任何写操作。
  Future<AssistantConfirmPreview?> buildConfirmPreview(
    Map<String, dynamic> args,
  ) async => null;

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
