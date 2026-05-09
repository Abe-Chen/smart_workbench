/// 任务理解层提取出的槽位。所有字段都允许为 null：
/// 这一层做"能识别明显的就识别"，识别不出来交给下游模型自己处理，
/// 不强行猜。后续 W3b 接写入工具时再决定哪些槽位"必须有"。
class AssistantSlots {
  const AssistantSlots({
    this.title,
    this.time,
    this.origin,
    this.destination,
    this.date,
    this.duration,
    this.transport,
    this.content,
    this.location,
    this.category,
  });

  /// 日程 / 任务标题（"客户拜访" / "Q2 评审会"）
  final String? title;

  /// 时间（"下午 3 点" / "14:00"）
  final String? time;

  /// 出发地（trip_planning）
  final String? origin;

  /// 目的地（trip_planning / local_search）
  final String? destination;

  /// 日期（"明天" / "5月10日" / "周五"）
  final String? date;

  /// 行程时长（"两天一晚" / "3 天"）
  final String? duration;

  /// 出行方式（"开车" / "地铁" / "打车"）
  final String? transport;

  /// 提醒内容（"喝水" / "吃药"）
  final String? content;

  /// 搜索地点（"陆家嘴" / "上海"）
  final String? location;

  /// 搜索品类（"酒店" / "餐厅"）
  final String? category;

  static const AssistantSlots empty = AssistantSlots();

  bool get isEmpty =>
      title == null &&
      time == null &&
      origin == null &&
      destination == null &&
      date == null &&
      duration == null &&
      transport == null &&
      content == null &&
      location == null &&
      category == null;

  /// 用最朴素的正则做提取。
  ///
  /// **设计原则**：
  /// - 不识别就 null；不要为了"识别更多"而引入误判
  /// - 识别失败完全不影响下游路由分支（这是 W3a 纯增量版的承诺）
  static AssistantSlots from(String text) {
    final String t = text.trim();
    if (t.isEmpty) return empty;

    return AssistantSlots(
      time: _extractTime(t),
      date: _extractDate(t),
      duration: _extractDuration(t),
      transport: _extractTransport(t),
      origin: _extractOrigin(t),
      destination: _extractDestination(t),
      location: _extractLocation(t),
      category: _extractCategory(t),
      title: _extractScheduleTitle(t),
      content: _extractReminderContent(t),
    );
  }
}

// ---------------- 内部识别规则 ----------------

String? _extractTime(String text) {
  final RegExpMatch? clock = _clockPattern.firstMatch(text);
  if (clock != null) return clock.group(0)!.trim();
  final RegExpMatch? phase = _timePhasePattern.firstMatch(text);
  if (phase != null) return phase.group(0)!.trim();
  return null;
}

String? _extractDate(String text) {
  final RegExpMatch? rel = _dateRelativePattern.firstMatch(text);
  if (rel != null) return rel.group(0)!.trim();
  final RegExpMatch? abs = _dateAbsolutePattern.firstMatch(text);
  if (abs != null) return abs.group(0)!.trim();
  final RegExpMatch? week = _weekDayPattern.firstMatch(text);
  if (week != null) return week.group(0)!.trim();
  return null;
}

String? _extractDuration(String text) {
  final RegExpMatch? m = _durationPattern.firstMatch(text);
  return m?.group(0)?.trim();
}

String? _extractTransport(String text) {
  final RegExpMatch? m = _transportPattern.firstMatch(text);
  return m?.group(0)?.trim();
}

String? _extractOrigin(String text) {
  final RegExpMatch? m = _originPattern.firstMatch(text);
  final String? raw = m?.group(1)?.trim();
  if (raw == null || raw.isEmpty) return null;
  return _trimTrailingParticles(raw);
}

String? _extractDestination(String text) {
  final RegExpMatch? m = _destinationPattern.firstMatch(text);
  final String? raw = m?.group(1)?.trim();
  if (raw == null || raw.isEmpty) return null;
  return _trimTrailingParticles(raw);
}

String? _extractLocation(String text) {
  final RegExpMatch? m = _nearbyPattern.firstMatch(text);
  final String? raw = m?.group(1)?.trim();
  if (raw == null || raw.isEmpty) return null;
  return _trimTrailingParticles(raw);
}

String? _extractCategory(String text) {
  for (final String c in _categoryKeywords) {
    if (text.contains(c)) return c;
  }
  return null;
}

String? _extractScheduleTitle(String text) {
  final RegExpMatch? m = _scheduleTitlePattern.firstMatch(text);
  final String? raw = m?.group(1)?.trim();
  if (raw == null || raw.isEmpty) return null;
  final String trimmed = _trimTrailingParticles(raw);
  if (trimmed.isEmpty) return null;
  // raw 整体只是时间/日期词时不算 title（例："明天3点"）
  if (_isJustTimeOrDate(trimmed)) return null;
  return trimmed;
}

/// 把 [s] 里日期/时间相关字符全去掉，如果剩下空字符串，就认为它本身只是
/// 一个时间/日期表达式，不是合法的标题。
bool _isJustTimeOrDate(String s) {
  final String stripped = s
      .replaceAll(_clockPattern, '')
      .replaceAll(_timePhasePattern, '')
      .replaceAll(_dateAbsolutePattern, '')
      .replaceAll(_weekDayPattern, '')
      .replaceAll(_dateRelativePattern, '')
      .replaceAll(RegExp(r'[\s的]'), '')
      .trim();
  return stripped.isEmpty;
}

String? _extractReminderContent(String text) {
  final RegExpMatch? m = _reminderContentPattern.firstMatch(text);
  final String? raw = m?.group(1)?.trim();
  if (raw == null || raw.isEmpty) return null;
  return _trimTrailingParticles(raw);
}

String _trimTrailingParticles(String raw) {
  String s = raw;
  while (s.isNotEmpty &&
      (s.endsWith('的') ||
          s.endsWith('了') ||
          s.endsWith('，') ||
          s.endsWith('。'))) {
    s = s.substring(0, s.length - 1);
  }
  return s.trim();
}

// 时分：14:00 / 14：30 / 8 点 / 下午 3 点半
final RegExp _clockPattern = RegExp(
  r'(?:(?:凌晨|早晨|早上|上午|中午|下午|晚上|今晚|明早)\s*)?'
  r'(?:\d{1,2}[:：]\d{1,2}|\d{1,2}\s*点(?:\s*\d{1,2}\s*分)?(?:半)?)',
);

// 时段词：今天上午 / 明天下午
final RegExp _timePhasePattern = RegExp(
  r'(?:今天|明天|后天|大后天|今晚|明早)?\s*(?:凌晨|早晨|早上|上午|中午|下午|晚上)',
);

// 相对日期：今天 / 明天 / 后天 / 大后天
final RegExp _dateRelativePattern = RegExp(r'(今天|明天|后天|大后天|今晚|明早)');

// 绝对日期：5月10日 / 5月10号
final RegExp _dateAbsolutePattern = RegExp(r'\d{1,2}\s*月\s*\d{1,2}\s*[日号]');

// 周几：周五 / 星期五
final RegExp _weekDayPattern = RegExp(r'(?:周|星期)[一二三四五六日天]');

// 时长：3 天 / 两天一晚 / 一周 / 半个月
final RegExp _durationPattern = RegExp(
  r'(?:\d+|[一二两三四五六七八九十半]+)\s*(?:天|日|周末|周|个月|月|小时|分钟)'
  r'(?:\s*(?:\d+|[一二两三四五六七八九十]+)?\s*(?:晚|夜|宿))?',
);

// 出发地："从 X 到/去/飞/出发"
final RegExp _originPattern = RegExp(
  r'从\s*([一-龥A-Za-z0-9]{1,18}?)\s*(?:到|去|飞|出发|开车|坐车|打车|驾车|$)',
);

// 目的地："去/到/飞 X 出差/玩/旅行/开会/见面"
final RegExp _destinationPattern = RegExp(
  r'(?:去往|开车去|驾车去|打车去|出差去|去|到|飞)\s*'
  r'([一-龥A-Za-z0-9]{1,18}?)\s*'
  r'(?:出差|玩|旅行|度假|开会|见客户|考察|看望|探亲|路线|导航|怎么走|怎么去|'
  r'开车去|驾车去|打车去|坐车去|过去|的|$)',
);

final RegExp _transportPattern = RegExp(
  r'(开车|驾车|自驾|打车|出租车|网约车|地铁|公交|公共交通|步行|骑车|高铁|火车|飞机)',
);

// 附近搜索锚点："陆家嘴附近 / 浦东周边"
final RegExp _nearbyPattern = RegExp(r'([一-龥A-Za-z]{2,12}?)\s*(?:附近|周边|周围|一带)');

// 简单品类词典（命中即返回）
const List<String> _categoryKeywords = <String>[
  '酒店',
  '宾馆',
  '民宿',
  '餐厅',
  '美食',
  '咖啡',
  '咖啡馆',
  '奶茶',
  '加油站',
  '充电站',
  '停车场',
  '健身房',
  '医院',
  '药店',
  '便利店',
  '超市',
  '银行',
  'ATM',
];

// 日程标题："帮我加个明天 3 点的客户拜访"
//   → group(1) = "客户拜访"
final RegExp _scheduleTitlePattern = RegExp(
  r'(?:帮我|给我|替我)?\s*(?:创建|新建|新增|添加|加(?:个|一个|一条)?|安排|约|订)\s*'
  r'(?:[^的，。]{0,20}?的)?'
  r'([一-龥A-Za-z0-9]{2,16}?)'
  r'(?:这个|那个)?\s*(?:任务|待办|日程|会议|安排|约会)',
);

// 提醒内容："提醒我喝水" / "提醒我 8 点喝水"
//   → group(1) = "喝水"
final RegExp _reminderContentPattern = RegExp(
  r'提醒我\s*(?:[^一-龥A-Za-z]*?)'
  r'(?:[^，。]{0,20}?(?:点|分|时|前|后)\s*)?'
  r'([一-龥A-Za-z]{1,20})\s*(?:[，。]|$)',
);
