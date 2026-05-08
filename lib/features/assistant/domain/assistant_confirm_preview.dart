/// 操作确认卡片的渲染数据。
///
/// 由写入类 [AssistantTool.buildConfirmPreview] 产生，给 ConfirmCard widget
/// 用来展示给用户。controller 在用户确认前**不会**调用工具的 `call(...)`。
class AssistantConfirmPreview {
  const AssistantConfirmPreview({
    required this.title,
    required this.rows,
    this.severity = ConfirmSeverity.normal,
    this.subtitle,
  });

  /// 头部标题，例："准备创建日程" / "准备删除任务"
  final String title;

  /// 可选副标题，例：原始用户语句的精简引用
  final String? subtitle;

  /// 字段预览行
  final List<ConfirmRow> rows;

  /// 视觉严重度。delete 用 warning（红色）；create / update / complete 用 normal。
  final ConfirmSeverity severity;
}

/// 一行字段预览。
class ConfirmRow {
  const ConfirmRow({
    required this.label,
    required this.value,
    this.highlighted = false,
    this.icon,
  });

  /// 字段名，例："标题" / "时间" / "重复"
  final String label;

  /// 字段值的文字呈现，例："明天 15:00 - 16:00"
  final String value;

  /// 是否高亮（如时间被改动 / 关键字段）
  final bool highlighted;

  /// 可选 emoji / 图标字符
  final String? icon;
}

enum ConfirmSeverity { normal, warning }
