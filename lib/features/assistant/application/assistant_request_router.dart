import '../domain/assistant_intent.dart';
import '../domain/assistant_execution_mode.dart';
import '../domain/assistant_slots.dart';

enum AssistantRequestRoute { publicResponses, localTools }

class AssistantRequestPlan {
  const AssistantRequestPlan({
    required this.route,
    required this.mode,
    required this.continuePublicContext,
    required this.intent,
    required this.slots,
  });

  final AssistantRequestRoute route;
  final AssistantExecutionMode mode;
  final bool continuePublicContext;

  /// W3a 加入的意图标签。当前阶段只用于 UX 提示和给 W3b 准备扩展点，
  /// **不参与 [route] 的判定**。
  final AssistantIntent intent;

  /// W3a 加入的槽位提取结果。识别失败时所有字段为 null（[AssistantSlots.empty]）。
  /// **不参与 [route] 的判定**。
  final AssistantSlots slots;
}

/// 把用户输入分流到「公网 Responses」或「本地 chat+tools」两条链路。
///
/// W3a 在保持原 route 判定不变的前提下，新增 [AssistantRequestPlan.intent]
/// 与 [AssistantRequestPlan.slots] 两个标签字段，作为下游 UX 提示和未来 W3b
/// 写入闭环的扩展点。
class AssistantRequestRouter {
  static AssistantRequestPlan planFor({
    required String text,
    required bool hasPublicContext,
    AssistantExecutionMode? lastPublicMode,
  }) {
    final String normalized = text.trim();
    if (normalized.isEmpty) {
      return const AssistantRequestPlan(
        route: AssistantRequestRoute.publicResponses,
        mode: AssistantExecutionMode.publicQuick,
        continuePublicContext: false,
        intent: AssistantIntent.unknown,
        slots: AssistantSlots.empty,
      );
    }

    final AssistantIntent intent = _classifyIntent(normalized);
    final AssistantRequestRoute route;
    final bool continuePublic;
    if (_looksLikeLocalIntent(normalized)) {
      route = AssistantRequestRoute.localTools;
      continuePublic = false;
    } else if (hasPublicContext && _looksLikePublicFollowUp(normalized)) {
      route = AssistantRequestRoute.publicResponses;
      continuePublic = true;
    } else {
      route = AssistantRequestRoute.publicResponses;
      continuePublic = false;
    }

    final AssistantExecutionMode mode =
        route == AssistantRequestRoute.localTools
        ? AssistantExecutionMode.local
        : _pickPublicMode(
            text: normalized,
            intent: intent,
            continuePublicContext: continuePublic,
            lastPublicMode: lastPublicMode,
          );

    return AssistantRequestPlan(
      route: route,
      mode: mode,
      continuePublicContext: continuePublic,
      intent: intent,
      slots: AssistantSlots.from(normalized),
    );
  }

  static AssistantExecutionMode _pickPublicMode({
    required String text,
    required AssistantIntent intent,
    required bool continuePublicContext,
    AssistantExecutionMode? lastPublicMode,
  }) {
    if (continuePublicContext && lastPublicMode != null) {
      return lastPublicMode;
    }
    if (intent == AssistantIntent.realtimeInfo ||
        intent == AssistantIntent.localSearch) {
      return AssistantExecutionMode.publicRealtime;
    }
    if (intent == AssistantIntent.tripPlanning) {
      return _tripToolingPattern.hasMatch(text)
          ? AssistantExecutionMode.publicRealtime
          : AssistantExecutionMode.publicDeep;
    }
    if (_looksLikeDeepPublicQuery(text)) {
      return AssistantExecutionMode.publicDeep;
    }
    return AssistantExecutionMode.publicQuick;
  }

  static bool _looksLikePublicFollowUp(String text) {
    return RegExp(
      r'^(那|那就|那明天|那今天|那现在|那晚上|那下午|那早上|那中午|那北京|那上海|那深圳|那广州|那杭州|那成都|那重庆|那港币|那美元|那欧元|那日元|那英镑|那100|那 100|还有|然后|接着|呢\??|那呢\??)',
    ).hasMatch(text);
  }

  static bool _looksLikeLocalIntent(String text) {
    if (_localUiKeywords.any(text.contains)) {
      return true;
    }
    if (_localUiActionPattern.hasMatch(text)) {
      return true;
    }
    if (_localActionPattern.hasMatch(text)) {
      return true;
    }
    if (_looksLikeImplicitTimedSchedule(text)) {
      return true;
    }
    if (_localCompleteActionPattern.hasMatch(text)) {
      return true;
    }
    if (_localDataPattern.hasMatch(text)) {
      return true;
    }
    return false;
  }

  static bool _looksLikeDeepPublicQuery(String text) {
    if (_deepPublicKeywords.any(text.contains)) {
      return true;
    }
    int matchedConstraints = 0;
    for (final RegExp pattern in _deepConstraintPatterns) {
      if (pattern.hasMatch(text)) {
        matchedConstraints += 1;
      }
      if (matchedConstraints >= 2) {
        return true;
      }
    }
    return false;
  }

  /// 意图分类。判定顺序按"具体 → 一般"：
  /// 写入类 → 控 App → 本地数据查询 → 行程规划 → 附近搜索 → 实时信息 → 兜底问答。
  ///
  /// 注意：写入类的判定与 [_looksLikeLocalIntent] 中的 [_localActionPattern]
  /// **共用同一组写入动作词 + 名词**，所以"被识别为写入意图"的输入一定也会
  /// 被路由到 [AssistantRequestRoute.localTools]，不会造成 route 与 intent 不一致。
  static AssistantIntent _classifyIntent(String text) {
    if (_reminderWritePattern.hasMatch(text)) {
      return AssistantIntent.reminderWrite;
    }
    if (_scheduleWritePattern.hasMatch(text)) {
      return AssistantIntent.scheduleWrite;
    }
    if (_looksLikeImplicitTimedSchedule(text)) {
      return AssistantIntent.scheduleWrite;
    }
    if (_localCompleteActionPattern.hasMatch(text)) {
      return AssistantIntent.scheduleWrite;
    }
    if (_localUiKeywords.any(text.contains) ||
        _localUiActionPattern.hasMatch(text)) {
      return AssistantIntent.localUiAction;
    }
    if (_localDataPattern.hasMatch(text)) {
      return AssistantIntent.localDataQuery;
    }
    if (_looksLikeTripPlanningIntent(text)) {
      return AssistantIntent.tripPlanning;
    }
    if (_localSearchPattern.hasMatch(text)) {
      return AssistantIntent.localSearch;
    }
    if (_realtimeInfoPattern.hasMatch(text)) {
      return AssistantIntent.realtimeInfo;
    }
    return AssistantIntent.generalQa;
  }
}

const List<String> _localUiKeywords = <String>[
  '工作台',
  '桌面',
  '设置',
  '音色',
  '播报',
  '麦克风',
  '抽屉',
  '悬浮球',
  '小治',
];

final RegExp _localActionPattern = RegExp(
  r'(帮我|给我|替我|把|新增|创建|新建|添加|修改|调整|推迟|提前|删除|取消|完成|标记).{0,24}(任务|待办|日程|提醒|会议|安排)',
);

final RegExp _localCompleteActionPattern = RegExp(
  r'^(把|将|帮我把|给我把|替我把).{1,24}(标记完成|标记为完成|设为完成|完成了|做完了|办完了)$',
);

final RegExp _localUiActionPattern = RegExp(
  r'(打开|关闭|展开|收起|显示|隐藏|切换|改成|换成|设置|重播|再播|播一下|停止).{0,12}(抽屉|悬浮球|卡片|音色|播报|语音|麦克风|工作台|设置|小治)',
);

final RegExp _localDataPattern = RegExp(
  r'(我的|我今天|我明天|我后天|今天|明天|后天).{0,8}(任务|待办|日程|提醒|会议|安排)',
);

// ------- 以下是 W3a 新增的意图分类专用 pattern（不参与 route 判定）-------

/// 提醒写入：必须含"提醒"，写入类动作词只是加分项。
/// 例："提醒我喝水" / "帮我加个 8 点的提醒" / "删掉那个吃药的提醒"
final RegExp _reminderWritePattern = RegExp(
  r'(?:提醒我|提醒一下我|定个提醒|加(?:个|一个|一条)?提醒|新增提醒|创建提醒|删(?:掉|除)?\s*[^，。]{0,12}提醒|取消提醒)',
);

/// 日程写入：写入类动作词 + 任务 / 日程 / 会议 / 待办 / 安排。
/// 与 [_localActionPattern] 同源，只是把"提醒"剔掉。
final RegExp _scheduleWritePattern = RegExp(
  r'(帮我|给我|替我|把|新增|创建|新建|添加|加|修改|调整|推迟|提前|删除|取消|完成|标记).{0,24}(任务|待办|日程|会议|安排)',
);

/// 无明确"创建日程"字样，但同时包含日期、时间和具体事项文本，也应视为本地日程写入。
/// 例："明天下午 5 点开会"、"明天早晨 9 点出差去石家庄"。
bool _looksLikeImplicitTimedSchedule(String text) {
  if (!_implicitScheduleDatePattern.hasMatch(text) ||
      !_implicitScheduleTimePattern.hasMatch(text)) {
    return false;
  }
  if (_nonScheduleQuestionPattern.hasMatch(text) ||
      _realtimeInfoPattern.hasMatch(text)) {
    return false;
  }
  String title = text
      .replaceAll(_implicitScheduleDatePattern, ' ')
      .replaceAll(_implicitScheduleWeekdayPattern, ' ')
      .replaceAll(_implicitScheduleTimePattern, ' ')
      .replaceAll(_implicitScheduleLeadPattern, ' ')
      .replaceAll(RegExp(r'[，。！？,.!?\s]+'), '')
      .trim();
  title = title.replaceAll(RegExp(r'^(和|跟|与)'), '').trim();
  if (title.length < 2) {
    return false;
  }
  if (_implicitScheduleStopWords.contains(title)) {
    return false;
  }
  return true;
}

final RegExp _implicitScheduleDatePattern = RegExp(
  r'(大后天|后天|明天|今天|今晚|明早|\d{1,2}\s*月\s*\d{1,2}\s*(?:日|号)|(?:周|星期)[一二三四五六日天])',
);
final RegExp _implicitScheduleWeekdayPattern = RegExp(r'(?:周|星期)[一二三四五六日天]');
final RegExp _implicitScheduleTimePattern = RegExp(
  r'(?:(凌晨|早晨|早上|上午|中午|下午|晚上|今晚|明早)\s*)?'
  r'(\d{1,2}[:：]\d{1,2}|\d{1,2}\s*点(?:\s*\d{1,2}\s*分?)?(?:半)?)',
);
final RegExp _implicitScheduleLeadPattern = RegExp(
  r'(请|麻烦|帮我|给我|替我|我想|想|加(?:个|一个|一条)?|安排|约|定|一个|一条|个|的)',
);
final RegExp _nonScheduleQuestionPattern = RegExp(
  r'(怎么样|如何|怎么|为什么|是什么|多少|哪里|查一下|查查|搜索|告诉我|看一下|看看|有啥|有什么)',
);
const Set<String> _implicitScheduleStopWords = <String>{
  '日程',
  '会议',
  '任务',
  '待办',
  '提醒',
  '安排',
};

/// 行程规划："出差 / 旅行 / 旅游 / 行程 / 明确交通路线"。
bool _looksLikeTripPlanningIntent(String text) {
  if (_tripPlanningPattern.hasMatch(text)) {
    return true;
  }
  return _explicitRoutePlanningPattern.hasMatch(text) ||
      _trafficRoutePattern.hasMatch(text);
}

final RegExp _tripPlanningPattern = RegExp(r'(出差|旅行|旅游|行程|度假|自驾游)');

final RegExp _explicitRoutePlanningPattern = RegExp(
  r'(路线规划|导航|怎么去|怎么走|怎么过去|规划.{0,12}路线|查.{0,8}路线)',
);

final RegExp _trafficRoutePattern = RegExp(
  r'(从.{1,18}到.{1,18}|(?:去|到|前往).{1,18}(?:路线|导航|怎么走|怎么去)|'
  r'(?:开车|驾车|自驾|打车|地铁|公交|公共交通|坐车|步行|骑车).{0,12}(?:去|到|路线|导航))',
);

final RegExp _tripToolingPattern = RegExp(
  r'(路线|导航|怎么去|航班|高铁|火车|地铁|打车|酒店|民宿|餐厅|营业时间|开门|关门)',
);

/// 附近搜索："附近 / 周边 / 一带 / 离我最近"
final RegExp _localSearchPattern = RegExp(r'(附近|周边|周围|一带|离我最近|哪里有|哪家)');

/// 实时信息：天气 / 汇率 / 新闻 / 股价 / 比赛 / 价格 / 营业时间
final RegExp _realtimeInfoPattern = RegExp(
  r'(天气|气温|下雨|降雨|温度|空气质量|空气|湿度|台风|紫外线|穿衣|新闻|热点|头条|汇率|换算|换成|股价|股票|比赛|赛事|比分|价格|多少钱|营业时间|开门|开店|关门|限行|尾号)',
);

const List<String> _deepPublicKeywords = <String>[
  '对比',
  '比较',
  '推荐',
  '更适合',
  '怎么安排',
  '方案',
  '综合分析',
  '利弊',
  '详细说',
  '系统梳理',
];

final List<RegExp> _deepConstraintPatterns = <RegExp>[
  RegExp(r'(预算|价位|人均)'),
  RegExp(r'(今天|明天|这周|下周|周末|月底|下个月|几点)'),
  RegExp(r'(附近|周边|在.*?附近|从.*?到.*?|去.*?怎么)'),
  RegExp(r'(带孩子|情侣|商务|出差|老人|朋友|一个人)'),
  RegExp(r'(安静|热闹|高端|便宜|方便|性价比|舒适|近地铁)'),
];
