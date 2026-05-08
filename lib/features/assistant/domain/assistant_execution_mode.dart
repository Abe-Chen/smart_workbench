enum AssistantExecutionMode {
  local,
  publicQuick,
  publicRealtime,
  publicDeep;

  bool get isPublic => this != AssistantExecutionMode.local;

  bool get supportsCancelTask =>
      this == AssistantExecutionMode.publicRealtime ||
      this == AssistantExecutionMode.publicDeep;

  String get label {
    switch (this) {
      case AssistantExecutionMode.local:
        return '本地处理';
      case AssistantExecutionMode.publicQuick:
        return '快速问答';
      case AssistantExecutionMode.publicRealtime:
        return '实时查询';
      case AssistantExecutionMode.publicDeep:
        return '深入分析';
    }
  }
}
