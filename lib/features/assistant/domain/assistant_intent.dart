/// 小治的请求意图标签。
///
/// 设计原则：
/// - 六个产品意图（generalQa / realtimeInfo / localSearch / tripPlanning /
///   scheduleWrite / reminderWrite）来自 docs/ai_assistant_xiaozhi.md §1.2
/// - 三个辅助意图（localUiAction / localDataQuery / unknown）对应
///   AssistantRequestRouter 现有的"控 App / 查本地数据 / 兜底"分流
///
/// 当前阶段意图只用于 UX 提示和给 W3b 写入闭环准备扩展点，
/// 不参与 [AssistantRequestRoute] 的判定。
enum AssistantIntent {
  /// 普通常识问答 / 解释 / 建议
  generalQa,

  /// 天气、汇率、新闻、价格、营业时间等实时信息
  realtimeInfo,

  /// 附近、周边、本地餐饮 / 酒店 / 通勤
  localSearch,

  /// 出差、旅行、路线、行程规划
  tripPlanning,

  /// 创建 / 修改 / 删除日程、会议、待办
  scheduleWrite,

  /// 创建 / 修改 / 删除提醒
  reminderWrite,

  /// 控制 App 自身（打开抽屉 / 切音色 / 收起卡片）
  localUiAction,

  /// 查询本地数据（"我今天的任务" / "我明天有什么会"）
  localDataQuery,

  /// 兜底
  unknown;

  /// 给 progress 步骤展示用的中文标签。
  String get label {
    switch (this) {
      case AssistantIntent.generalQa:
        return '常识问答';
      case AssistantIntent.realtimeInfo:
        return '实时信息';
      case AssistantIntent.localSearch:
        return '附近搜索';
      case AssistantIntent.tripPlanning:
        return '行程规划';
      case AssistantIntent.scheduleWrite:
        return '日程操作';
      case AssistantIntent.reminderWrite:
        return '提醒操作';
      case AssistantIntent.localUiAction:
        return '应用操作';
      case AssistantIntent.localDataQuery:
        return '本地数据';
      case AssistantIntent.unknown:
        return '常规请求';
    }
  }

  /// 是否为本地写入类意图。当 tool_registry 还没注册写入工具时，
  /// controller 用它来给 progress 加"写入能力还没接入"提示。
  bool get isLocalWrite =>
      this == AssistantIntent.scheduleWrite ||
      this == AssistantIntent.reminderWrite;
}
