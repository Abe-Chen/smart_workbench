import 'package:flutter_test/flutter_test.dart';

import 'package:smart_workbench/features/assistant/application/assistant_request_router.dart';
import 'package:smart_workbench/features/assistant/domain/assistant_execution_mode.dart';
import 'package:smart_workbench/features/assistant/domain/assistant_intent.dart';
import 'package:smart_workbench/features/assistant/domain/assistant_slots.dart';

/// W3a 纯增量改动的回归 + 新意图 + 槽位测试。
///
/// 核心承诺：route / continuePublicContext 字段判定逻辑**完全不变**。
/// 所有现有路由分流 case 在这里固化为回归测试，意图和槽位作为新增能力测试。
void main() {
  group('AssistantRequestRouter · route 回归', () {
    test('空字符串 → publicResponses, no follow up, intent unknown', () {
      final AssistantRequestPlan plan = AssistantRequestRouter.planFor(
        text: '',
        hasPublicContext: false,
      );
      expect(plan.route, AssistantRequestRoute.publicResponses);
      expect(plan.continuePublicContext, false);
      expect(plan.intent, AssistantIntent.unknown);
      expect(plan.slots.isEmpty, true);
    });

    test('普通问答 → publicResponses', () {
      final AssistantRequestPlan plan = AssistantRequestRouter.planFor(
        text: 'iPhone 16 评测',
        hasPublicContext: false,
      );
      expect(plan.route, AssistantRequestRoute.publicResponses);
      expect(plan.continuePublicContext, false);
      expect(plan.mode, AssistantExecutionMode.publicQuick);
    });

    test('公网话题延续 + 有上下文 → continuePublicContext=true', () {
      final AssistantRequestPlan plan = AssistantRequestRouter.planFor(
        text: '那北京呢',
        hasPublicContext: true,
        lastPublicMode: AssistantExecutionMode.publicRealtime,
      );
      expect(plan.route, AssistantRequestRoute.publicResponses);
      expect(plan.continuePublicContext, true);
      expect(plan.mode, AssistantExecutionMode.publicRealtime);
    });

    test('公网话题延续 + 无上下文 → continuePublicContext=false', () {
      final AssistantRequestPlan plan = AssistantRequestRouter.planFor(
        text: '那北京呢',
        hasPublicContext: false,
      );
      expect(plan.route, AssistantRequestRoute.publicResponses);
      expect(plan.continuePublicContext, false);
    });

    test('问天气 → publicResponses（不会被错分到 localTools）', () {
      final AssistantRequestPlan plan = AssistantRequestRouter.planFor(
        text: '今天天气怎么样',
        hasPublicContext: false,
      );
      expect(plan.route, AssistantRequestRoute.publicResponses);
      expect(plan.mode, AssistantExecutionMode.publicRealtime);
    });

    test('本地 UI 关键词 "打开抽屉" → localTools', () {
      final AssistantRequestPlan plan = AssistantRequestRouter.planFor(
        text: '打开抽屉',
        hasPublicContext: false,
      );
      expect(plan.route, AssistantRequestRoute.localTools);
      expect(plan.continuePublicContext, false);
    });

    test('本地动作 "帮我创建一个任务" → localTools', () {
      final AssistantRequestPlan plan = AssistantRequestRouter.planFor(
        text: '帮我创建一个任务',
        hasPublicContext: false,
      );
      expect(plan.route, AssistantRequestRoute.localTools);
    });

    test('本地数据查询 "我今天的任务" → localTools', () {
      final AssistantRequestPlan plan = AssistantRequestRouter.planFor(
        text: '我今天的任务',
        hasPublicContext: false,
      );
      expect(plan.route, AssistantRequestRoute.localTools);
    });

    test('本地命中即使 hasPublicContext=true 也不算 follow up', () {
      final AssistantRequestPlan plan = AssistantRequestRouter.planFor(
        text: '打开抽屉',
        hasPublicContext: true,
      );
      expect(plan.route, AssistantRequestRoute.localTools);
      expect(plan.continuePublicContext, false);
    });
  });

  group('AssistantRequestRouter · 意图分类', () {
    test('普通问答兜底 → generalQa', () {
      final AssistantRequestPlan plan = AssistantRequestRouter.planFor(
        text: 'iPhone 16 怎么评价',
        hasPublicContext: false,
      );
      expect(plan.intent, AssistantIntent.generalQa);
    });

    test('天气 → realtimeInfo', () {
      final AssistantRequestPlan plan = AssistantRequestRouter.planFor(
        text: '今天天气怎么样',
        hasPublicContext: false,
      );
      expect(plan.intent, AssistantIntent.realtimeInfo);
    });

    test('汇率 → realtimeInfo', () {
      final AssistantRequestPlan plan = AssistantRequestRouter.planFor(
        text: '今天人民币兑美元汇率多少',
        hasPublicContext: false,
      );
      expect(plan.intent, AssistantIntent.realtimeInfo);
    });

    test('附近搜索 → localSearch', () {
      final AssistantRequestPlan plan = AssistantRequestRouter.planFor(
        text: '陆家嘴附近有什么好吃的',
        hasPublicContext: false,
      );
      expect(plan.intent, AssistantIntent.localSearch);
    });

    test('行程规划 → tripPlanning', () {
      final AssistantRequestPlan plan = AssistantRequestRouter.planFor(
        text: '下个月去成都出差怎么安排',
        hasPublicContext: false,
      );
      expect(plan.intent, AssistantIntent.tripPlanning);
    });

    test('日程写入 → scheduleWrite', () {
      final AssistantRequestPlan plan = AssistantRequestRouter.planFor(
        text: '帮我加个客户拜访的会议',
        hasPublicContext: false,
      );
      expect(plan.intent, AssistantIntent.scheduleWrite);
    });

    test('带完整时间和标题的日程写入 → localTools', () {
      final AssistantRequestPlan plan = AssistantRequestRouter.planFor(
        text: '创建一个明天下午 3 点需求讨论会的日程',
        hasPublicContext: false,
      );
      expect(plan.route, AssistantRequestRoute.localTools);
      expect(plan.intent, AssistantIntent.scheduleWrite);
      expect(plan.slots.date, '明天');
      expect(plan.slots.time, contains('3'));
    });

    test('出差类明确时间表达 → scheduleWrite，而不是只当行程规划', () {
      final AssistantRequestPlan plan = AssistantRequestRouter.planFor(
        text: '明天早晨 9 点出差去石家庄。',
        hasPublicContext: false,
      );
      expect(plan.route, AssistantRequestRoute.localTools);
      expect(plan.intent, AssistantIntent.scheduleWrite);
      expect(plan.slots.date, '明天');
      expect(plan.slots.time, contains('9'));
    });

    test('客户交流类明确时间表达 → scheduleWrite', () {
      final AssistantRequestPlan plan = AssistantRequestRouter.planFor(
        text: '明天上午 9 点和客户交流产品对接的问题在客户现场。',
        hasPublicContext: false,
      );
      expect(plan.route, AssistantRequestRoute.localTools);
      expect(plan.intent, AssistantIntent.scheduleWrite);
    });

    test('常见自然日程表达 → scheduleWrite', () {
      const List<String> inputs = <String>[
        '明天9点去客户现场沟通',
        '后天上午10点到公司培训',
        '周五下午2点跟张总电话',
      ];

      for (final String input in inputs) {
        final AssistantRequestPlan plan = AssistantRequestRouter.planFor(
          text: input,
          hasPublicContext: false,
        );
        expect(plan.route, AssistantRequestRoute.localTools, reason: input);
        expect(plan.intent, AssistantIntent.scheduleWrite, reason: input);
      }
    });

    test('明确天气问题仍然走 realtimeInfo', () {
      final AssistantRequestPlan plan = AssistantRequestRouter.planFor(
        text: '明天早晨 9 点石家庄天气怎么样',
        hasPublicContext: false,
      );
      expect(plan.route, AssistantRequestRoute.publicResponses);
      expect(plan.intent, AssistantIntent.realtimeInfo);
    });

    test('没有具体时间的出差安排不直接创建日程', () {
      final AssistantRequestPlan plan = AssistantRequestRouter.planFor(
        text: '明天去石家庄出差',
        hasPublicContext: false,
      );
      expect(plan.route, AssistantRequestRoute.publicResponses);
      expect(plan.intent, AssistantIntent.tripPlanning);
    });

    test('自然完成表达 → localTools', () {
      final AssistantRequestPlan plan = AssistantRequestRouter.planFor(
        text: '把写周报标记完成',
        hasPublicContext: false,
      );
      expect(plan.route, AssistantRequestRoute.localTools);
      expect(plan.intent, AssistantIntent.scheduleWrite);
    });

    test('提醒写入 → reminderWrite', () {
      final AssistantRequestPlan plan = AssistantRequestRouter.planFor(
        text: '提醒我喝水',
        hasPublicContext: false,
      );
      expect(plan.intent, AssistantIntent.reminderWrite);
    });

    test('删除提醒 → reminderWrite（不被错分到 schedule）', () {
      final AssistantRequestPlan plan = AssistantRequestRouter.planFor(
        text: '删掉吃药提醒',
        hasPublicContext: false,
      );
      expect(plan.intent, AssistantIntent.reminderWrite);
    });

    test('控 App → localUiAction', () {
      final AssistantRequestPlan plan = AssistantRequestRouter.planFor(
        text: '打开抽屉',
        hasPublicContext: false,
      );
      expect(plan.intent, AssistantIntent.localUiAction);
    });

    test('本地数据查询 → localDataQuery', () {
      final AssistantRequestPlan plan = AssistantRequestRouter.planFor(
        text: '我今天的任务',
        hasPublicContext: false,
      );
      expect(plan.intent, AssistantIntent.localDataQuery);
    });

    test('意图判定不影响 follow-up 标识', () {
      final AssistantRequestPlan plan = AssistantRequestRouter.planFor(
        text: '那北京呢',
        hasPublicContext: true,
      );
      // 兜底 generalQa，但 follow up 标识独立保留
      expect(plan.intent, AssistantIntent.generalQa);
      expect(plan.continuePublicContext, true);
    });
  });

  group('AssistantRequestRouter · 模式分流', () {
    test('天气 / 汇率 / 新闻等实时问题 → publicRealtime', () {
      final AssistantRequestPlan plan = AssistantRequestRouter.planFor(
        text: '今天美元汇率多少',
        hasPublicContext: false,
      );
      expect(plan.mode, AssistantExecutionMode.publicRealtime);
    });

    test('附近搜索 → publicRealtime', () {
      final AssistantRequestPlan plan = AssistantRequestRouter.planFor(
        text: '徐家汇附近有什么酒店',
        hasPublicContext: false,
      );
      expect(plan.mode, AssistantExecutionMode.publicRealtime);
    });

    test('路线 / 酒店类 tripPlanning → publicRealtime', () {
      final AssistantRequestPlan plan = AssistantRequestRouter.planFor(
        text: '去杭州出差住哪家酒店方便',
        hasPublicContext: false,
      );
      expect(plan.intent, AssistantIntent.tripPlanning);
      expect(plan.mode, AssistantExecutionMode.publicRealtime);
    });

    test('复杂方案型 tripPlanning → publicDeep', () {
      final AssistantRequestPlan plan = AssistantRequestRouter.planFor(
        text: '下个月去成都出差三天怎么安排更合理',
        hasPublicContext: false,
      );
      expect(plan.intent, AssistantIntent.tripPlanning);
      expect(plan.mode, AssistantExecutionMode.publicDeep);
    });

    test('普通问答默认 → publicQuick', () {
      final AssistantRequestPlan plan = AssistantRequestRouter.planFor(
        text: '什么是 MCP',
        hasPublicContext: false,
      );
      expect(plan.mode, AssistantExecutionMode.publicQuick);
    });

    test('复杂对比问答 → publicDeep', () {
      final AssistantRequestPlan plan = AssistantRequestRouter.planFor(
        text: '帮我对比一下小米和华为，哪个更适合商务出差',
        hasPublicContext: false,
      );
      expect(plan.mode, AssistantExecutionMode.publicDeep);
    });
  });

  group('AssistantSlots · 提取', () {
    test('空字符串 → empty', () {
      final AssistantSlots s = AssistantSlots.from('');
      expect(s.isEmpty, true);
    });

    test('提醒喝水 → content="喝水"', () {
      final AssistantSlots s = AssistantSlots.from('提醒我喝水');
      expect(s.content, '喝水');
    });

    test('明天下午3点 → date="明天" + time 含 "3"', () {
      final AssistantSlots s = AssistantSlots.from('明天下午3点开会');
      expect(s.date, '明天');
      expect(s.time, isNotNull);
      expect(s.time, contains('3'));
    });

    test('附近搜索抽 location 与 category', () {
      final AssistantSlots s = AssistantSlots.from('陆家嘴附近有什么酒店');
      expect(s.location, '陆家嘴');
      expect(s.category, '酒店');
    });

    test('行程：origin / destination / duration', () {
      final AssistantSlots s = AssistantSlots.from('从上海到成都出差3天');
      expect(s.origin, '上海');
      expect(s.destination, '成都');
      expect(s.duration, contains('3'));
    });

    test('日程标题：含锚点词 → 命中', () {
      final AssistantSlots s = AssistantSlots.from('帮我加个客户拜访的会议');
      expect(s.title, '客户拜访');
    });

    test('日程标题：仅时间无名词 → null', () {
      final AssistantSlots s = AssistantSlots.from('帮我加个明天3点的会议');
      expect(s.title, isNull);
    });
  });
}
