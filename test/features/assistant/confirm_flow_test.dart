import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smart_workbench/core/config/env_config.dart';
import 'package:smart_workbench/features/assistant/application/assistant_controller.dart';
import 'package:smart_workbench/features/assistant/application/assistant_state.dart';
import 'package:smart_workbench/features/assistant/application/tool_registry.dart';
import 'package:smart_workbench/features/assistant/data/doubao_chat_client.dart';
import 'package:smart_workbench/features/assistant/data/doubao_responses_client.dart';
import 'package:smart_workbench/features/assistant/domain/assistant_confirm_preview.dart';
import 'package:smart_workbench/features/assistant/domain/assistant_execution_mode.dart';
import 'package:smart_workbench/features/assistant/domain/assistant_message.dart';
import 'package:smart_workbench/features/assistant/domain/assistant_tool.dart';
import 'package:smart_workbench/features/assistant/domain/tool_call.dart';
import 'package:smart_workbench/features/settings/application/app_settings_controller.dart';
import 'package:smart_workbench/features/settings/domain/app_settings.dart';

void main() {
  group('confirm flow', () {
    test('写入工具先进入 confirm，确认后才真正执行', () async {
      final _FakeWriteTool tool = _FakeWriteTool();
      final _FakeDoubaoChatClient chat = _FakeDoubaoChatClient(
        <ChatRoundCompleteEvent>[
          ChatRoundCompleteEvent(
            content: '',
            toolCalls: <ToolCall>[
              ToolCall(
                id: 'call_1',
                name: tool.name,
                argumentsJson: '{"title":"客户拜访"}',
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatRoundCompleteEvent(
            content: '已为你准备好了。',
            toolCalls: const <ToolCall>[],
            finishReason: 'stop',
          ),
        ],
      );

      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          doubaoChatClientProvider.overrideWithValue(chat),
          toolRegistryProvider.overrideWithValue(
            ToolRegistry(<AssistantTool>[tool]),
          ),
          currentTtsPlaybackModeProvider.overrideWithValue(
            TtsPlaybackMode.silent,
          ),
        ],
      );
      addTearDown(container.dispose);

      final AssistantController controller = container.read(
        assistantControllerProvider.notifier,
      );
      await controller.sendUserMessage(
        '我今天的任务',
        source: AssistantEntrySource.drawerText,
      );

      AssistantUiState state = container.read(assistantControllerProvider);
      expect(state.stage, AssistantStage.confirm);
      expect(state.pendingConfirm, isNotNull);
      expect(state.pendingConfirm!.preview.title, '准备创建');
      expect(tool.callCount, 0);

      await controller.confirmPendingTool();

      state = container.read(assistantControllerProvider);
      expect(state.stage, AssistantStage.idle);
      expect(state.pendingConfirm, isNull);
      expect(tool.callCount, 1);
      expect(chat.streamCount, 2);
      expect(
        state.messages
            .lastWhere(
              (AssistantMessage message) =>
                  message.role == AssistantRole.assistant && !message.streaming,
            )
            .content,
        '已为你准备好了。',
      );
    });

    test('取消确认后不会执行写入工具，但会继续收尾回答', () async {
      final _FakeWriteTool tool = _FakeWriteTool();
      final _FakeDoubaoChatClient chat = _FakeDoubaoChatClient(
        <ChatRoundCompleteEvent>[
          ChatRoundCompleteEvent(
            content: '',
            toolCalls: <ToolCall>[
              ToolCall(
                id: 'call_2',
                name: tool.name,
                argumentsJson: '{"title":"吃药提醒"}',
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatRoundCompleteEvent(
            content: '好，先不改。',
            toolCalls: const <ToolCall>[],
            finishReason: 'stop',
          ),
        ],
      );

      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          doubaoChatClientProvider.overrideWithValue(chat),
          toolRegistryProvider.overrideWithValue(
            ToolRegistry(<AssistantTool>[tool]),
          ),
          currentTtsPlaybackModeProvider.overrideWithValue(
            TtsPlaybackMode.silent,
          ),
        ],
      );
      addTearDown(container.dispose);

      final AssistantController controller = container.read(
        assistantControllerProvider.notifier,
      );
      await controller.sendUserMessage(
        '我今天的任务',
        source: AssistantEntrySource.drawerText,
      );

      expect(
        container.read(assistantControllerProvider).stage,
        AssistantStage.confirm,
      );

      await controller.cancelPendingTool();

      final AssistantUiState state = container.read(
        assistantControllerProvider,
      );
      expect(state.stage, AssistantStage.idle);
      expect(state.pendingConfirm, isNull);
      expect(tool.callCount, 0);
      expect(chat.streamCount, 2);
      expect(
        state.messages.where((AssistantMessage message) {
          return message.role == AssistantRole.tool &&
              message.content.contains('用户取消');
        }).length,
        1,
      );
    });

    test('创建日程缺字段时进入草稿，后续补全后弹确认卡', () async {
      final _FakeCreateTaskTool tool = _FakeCreateTaskTool();
      final _FakeDoubaoChatClient chat = _FakeDoubaoChatClient(
        <ChatRoundCompleteEvent>[],
      );
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          doubaoChatClientProvider.overrideWithValue(chat),
          toolRegistryProvider.overrideWithValue(
            ToolRegistry(<AssistantTool>[tool]),
          ),
          currentTtsPlaybackModeProvider.overrideWithValue(
            TtsPlaybackMode.silent,
          ),
        ],
      );
      addTearDown(container.dispose);

      final AssistantController controller = container.read(
        assistantControllerProvider.notifier,
      );
      await controller.sendUserMessage(
        '创建一个日程',
        source: AssistantEntrySource.drawerText,
      );

      AssistantUiState state = container.read(assistantControllerProvider);
      expect(state.pendingWriteDraft, isNotNull);
      expect(state.pendingConfirm, isNull);
      expect(chat.streamCount, 0);

      await controller.sendUserMessage(
        '明天下午 3 点需求讨论会',
        source: AssistantEntrySource.drawerText,
      );

      state = container.read(assistantControllerProvider);
      expect(state.pendingWriteDraft, isNull);
      expect(state.pendingConfirm, isNotNull);
      expect(state.pendingConfirm!.preview.rows.first.value, '需求讨论会');
      expect(tool.callCount, 0);
      expect(chat.streamCount, 0);
    });

    test('草稿生成的确认支持语音/文字确认，并由工具结果直接渲染成功', () async {
      final _FakeCreateTaskTool tool = _FakeCreateTaskTool();
      final _FakeDoubaoChatClient chat = _FakeDoubaoChatClient(
        <ChatRoundCompleteEvent>[],
      );
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          doubaoChatClientProvider.overrideWithValue(chat),
          toolRegistryProvider.overrideWithValue(
            ToolRegistry(<AssistantTool>[tool]),
          ),
          currentTtsPlaybackModeProvider.overrideWithValue(
            TtsPlaybackMode.silent,
          ),
        ],
      );
      addTearDown(container.dispose);

      final AssistantController controller = container.read(
        assistantControllerProvider.notifier,
      );
      await controller.sendUserMessage(
        '创建一个明天下午 3 点需求讨论会的日程',
        source: AssistantEntrySource.drawerVoice,
      );
      expect(
        container.read(assistantControllerProvider).pendingConfirm,
        isNotNull,
      );

      await controller.sendUserMessage(
        '确认',
        source: AssistantEntrySource.drawerVoice,
      );

      final AssistantUiState state = container.read(
        assistantControllerProvider,
      );
      expect(state.pendingConfirm, isNull);
      expect(tool.callCount, 1);
      expect(chat.streamCount, 0);
      expect(
        state.messages
            .lastWhere(
              (AssistantMessage message) =>
                  message.role == AssistantRole.assistant && !message.streaming,
            )
            .content,
        contains('「需求讨论会」已经放到日程里'),
      );
    });

    test('草稿确认后工具失败时不能显示创建成功', () async {
      final _FakeCreateTaskTool tool = _FakeCreateTaskTool(
        result: jsonEncode(<String, Object?>{'ok': false, 'reason': '缺少必要字段'}),
      );
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          toolRegistryProvider.overrideWithValue(
            ToolRegistry(<AssistantTool>[tool]),
          ),
          currentTtsPlaybackModeProvider.overrideWithValue(
            TtsPlaybackMode.silent,
          ),
        ],
      );
      addTearDown(container.dispose);

      final AssistantController controller = container.read(
        assistantControllerProvider.notifier,
      );
      await controller.sendUserMessage(
        '创建一个明天下午 3 点需求讨论会的日程',
        source: AssistantEntrySource.drawerText,
      );
      await controller.sendUserMessage(
        '确认',
        source: AssistantEntrySource.drawerText,
      );

      final AssistantUiState state = container.read(
        assistantControllerProvider,
      );
      final String latest = state.messages
          .lastWhere(
            (AssistantMessage message) =>
                message.role == AssistantRole.assistant && !message.streaming,
          )
          .content;
      expect(latest, contains('这次没创建成功：缺少必要字段'));
      expect(latest, isNot(contains('已创建')));
    });

    test('本地查询结果由 App 直接组织自然文案', () async {
      final _FakeQueryTasksTool tool = _FakeQueryTasksTool();
      final _FakeDoubaoChatClient chat = _FakeDoubaoChatClient(
        <ChatRoundCompleteEvent>[
          ChatRoundCompleteEvent(
            content: '',
            toolCalls: <ToolCall>[
              ToolCall(
                id: 'call_query',
                name: tool.name,
                argumentsJson: '{"start_date":"2026-05-09"}',
              ),
            ],
            finishReason: 'tool_calls',
          ),
        ],
      );
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          doubaoChatClientProvider.overrideWithValue(chat),
          toolRegistryProvider.overrideWithValue(
            ToolRegistry(<AssistantTool>[tool]),
          ),
          currentTtsPlaybackModeProvider.overrideWithValue(
            TtsPlaybackMode.silent,
          ),
        ],
      );
      addTearDown(container.dispose);

      final AssistantController controller = container.read(
        assistantControllerProvider.notifier,
      );
      await controller.sendUserMessage(
        '我今天的任务',
        source: AssistantEntrySource.drawerText,
      );

      final AssistantUiState state = container.read(
        assistantControllerProvider,
      );
      final String latest = state.messages
          .lastWhere(
            (AssistantMessage message) =>
                message.role == AssistantRole.assistant && !message.streaming,
          )
          .content;
      expect(chat.streamCount, 1);
      expect(latest, contains('有 1 个安排'));
      expect(latest, contains('15:00 - 16:00 需求讨论会'));
      expect(latest, isNot(contains('查到 1 条')));
    });

    test('创建草稿期间遇到天气查询，不会把天气问题当成日程标题', () async {
      final _FakeCreateTaskTool createTool = _FakeCreateTaskTool();
      final _FakeImmediateResponsesClient responses =
          _FakeImmediateResponsesClient('明天天气多云。');
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          doubaoResponsesClientProvider.overrideWithValue(responses),
          toolRegistryProvider.overrideWithValue(
            ToolRegistry(<AssistantTool>[createTool]),
          ),
          currentTtsPlaybackModeProvider.overrideWithValue(
            TtsPlaybackMode.silent,
          ),
        ],
      );
      addTearDown(container.dispose);

      final AssistantController controller = container.read(
        assistantControllerProvider.notifier,
      );
      await controller.sendUserMessage(
        '创建一个明天下午 5 点的日程',
        source: AssistantEntrySource.drawerText,
      );
      expect(
        container.read(assistantControllerProvider).pendingWriteDraft,
        isNotNull,
      );

      await controller.sendUserMessage(
        '查一下明天的天气',
        source: AssistantEntrySource.drawerText,
      );

      final AssistantUiState state = container.read(
        assistantControllerProvider,
      );
      expect(state.pendingWriteDraft, isNull);
      expect(state.pendingConfirm, isNull);
      expect(createTool.callCount, 0);
      expect(responses.streamCount, 1);
      expect(
        state.messages
            .lastWhere(
              (AssistantMessage message) =>
                  message.role == AssistantRole.assistant && !message.streaming,
            )
            .content,
        contains('明天天气'),
      );
    });

    test('自然表达“明天下午5点开会”会进入创建确认，不直接写入', () async {
      final _FakeCreateTaskTool tool = _FakeCreateTaskTool();
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          toolRegistryProvider.overrideWithValue(
            ToolRegistry(<AssistantTool>[tool]),
          ),
          currentTtsPlaybackModeProvider.overrideWithValue(
            TtsPlaybackMode.silent,
          ),
        ],
      );
      addTearDown(container.dispose);

      final AssistantController controller = container.read(
        assistantControllerProvider.notifier,
      );
      await controller.sendUserMessage(
        '明天下午5点开会',
        source: AssistantEntrySource.drawerText,
      );

      final AssistantUiState state = container.read(
        assistantControllerProvider,
      );
      expect(state.pendingConfirm, isNotNull);
      expect(state.pendingConfirm!.toolCall.name, 'create_task');
      expect(state.pendingConfirm!.toolCall.argumentsAsMap()['title'], '开会');
      expect(tool.callCount, 0);
    });

    test('自然表达“明天早晨9点出差去石家庄”会进入日程确认', () async {
      final _FakeCreateTaskTool tool = _FakeCreateTaskTool();
      final _FakeDoubaoChatClient chat = _FakeDoubaoChatClient(
        <ChatRoundCompleteEvent>[],
      );
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          doubaoChatClientProvider.overrideWithValue(chat),
          toolRegistryProvider.overrideWithValue(
            ToolRegistry(<AssistantTool>[tool]),
          ),
          currentTtsPlaybackModeProvider.overrideWithValue(
            TtsPlaybackMode.silent,
          ),
        ],
      );
      addTearDown(container.dispose);

      final AssistantController controller = container.read(
        assistantControllerProvider.notifier,
      );
      await controller.sendUserMessage(
        '明天早晨 9 点出差去石家庄。',
        source: AssistantEntrySource.drawerText,
      );

      final AssistantUiState state = container.read(
        assistantControllerProvider,
      );
      final Map<String, dynamic> args = state.pendingConfirm!.toolCall
          .argumentsAsMap();
      expect(chat.streamCount, 0);
      expect(state.pendingConfirm!.toolCall.name, 'create_task');
      expect(args['title'], '出差去石家庄');
      expect(args['start_time_minutes'], 9 * 60);
      expect(tool.callCount, 0);
    });

    test('更多自然日程表达都会先进入创建确认', () async {
      final List<({String input, String title, int minutes})> cases =
          <({String input, String title, int minutes})>[
            (input: '明天9点去客户现场沟通', title: '去客户现场沟通', minutes: 9 * 60),
            (input: '后天上午10点到公司培训', title: '到公司培训', minutes: 10 * 60),
            (input: '周五下午2点跟张总电话', title: '张总电话', minutes: 14 * 60),
          ];

      for (final ({String input, String title, int minutes}) item in cases) {
        final _FakeCreateTaskTool tool = _FakeCreateTaskTool();
        final _FakeDoubaoChatClient chat = _FakeDoubaoChatClient(
          <ChatRoundCompleteEvent>[],
        );
        final ProviderContainer container = ProviderContainer(
          overrides: <Override>[
            doubaoChatClientProvider.overrideWithValue(chat),
            toolRegistryProvider.overrideWithValue(
              ToolRegistry(<AssistantTool>[tool]),
            ),
            currentTtsPlaybackModeProvider.overrideWithValue(
              TtsPlaybackMode.silent,
            ),
          ],
        );
        addTearDown(container.dispose);

        final AssistantController controller = container.read(
          assistantControllerProvider.notifier,
        );
        await controller.sendUserMessage(
          item.input,
          source: AssistantEntrySource.drawerText,
        );

        final AssistantUiState state = container.read(
          assistantControllerProvider,
        );
        final Map<String, dynamic> args = state.pendingConfirm!.toolCall
            .argumentsAsMap();
        expect(chat.streamCount, 0, reason: item.input);
        expect(state.pendingConfirm!.toolCall.name, 'create_task');
        expect(args['title'], item.title, reason: item.input);
        expect(args['start_time_minutes'], item.minutes, reason: item.input);
        expect(tool.callCount, 0, reason: item.input);
      }
    });

    test('带日期时间的天气问题不会误进创建确认', () async {
      final _FakeCreateTaskTool createTool = _FakeCreateTaskTool();
      final _FakeImmediateResponsesClient responses =
          _FakeImmediateResponsesClient('明天石家庄天气晴。');
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          doubaoResponsesClientProvider.overrideWithValue(responses),
          toolRegistryProvider.overrideWithValue(
            ToolRegistry(<AssistantTool>[createTool]),
          ),
          currentTtsPlaybackModeProvider.overrideWithValue(
            TtsPlaybackMode.silent,
          ),
        ],
      );
      addTearDown(container.dispose);

      final AssistantController controller = container.read(
        assistantControllerProvider.notifier,
      );
      await controller.sendUserMessage(
        '明天9点石家庄天气',
        source: AssistantEntrySource.drawerText,
      );

      final AssistantUiState state = container.read(
        assistantControllerProvider,
      );
      expect(state.pendingConfirm, isNull);
      expect(createTool.callCount, 0);
      expect(responses.streamCount, 1);
      expect(
        state.messages
            .lastWhere(
              (AssistantMessage message) =>
                  message.role == AssistantRole.assistant && !message.streaming,
            )
            .content,
        contains('天气'),
      );
    });

    test('自然表达“明天上午9点和客户交流产品对接的问题”必须确认后才创建', () async {
      final _FakeCreateTaskTool tool = _FakeCreateTaskTool();
      final _FakeDoubaoChatClient chat = _FakeDoubaoChatClient(
        <ChatRoundCompleteEvent>[],
      );
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          doubaoChatClientProvider.overrideWithValue(chat),
          toolRegistryProvider.overrideWithValue(
            ToolRegistry(<AssistantTool>[tool]),
          ),
          currentTtsPlaybackModeProvider.overrideWithValue(
            TtsPlaybackMode.silent,
          ),
        ],
      );
      addTearDown(container.dispose);

      final AssistantController controller = container.read(
        assistantControllerProvider.notifier,
      );
      await controller.sendUserMessage(
        '明天上午 9 点和客户交流产品对接的问题在客户现场。',
        source: AssistantEntrySource.drawerText,
      );

      AssistantUiState state = container.read(assistantControllerProvider);
      final Map<String, dynamic> args = state.pendingConfirm!.toolCall
          .argumentsAsMap();
      expect(chat.streamCount, 0);
      expect(state.pendingConfirm!.toolCall.name, 'create_task');
      expect(args['title'], '客户交流产品对接的问题在客户现场');
      expect(args['start_time_minutes'], 9 * 60);
      expect(tool.callCount, 0);

      await controller.confirmPendingTool();

      state = container.read(assistantControllerProvider);
      expect(state.pendingConfirm, isNull);
      expect(tool.callCount, 1);
    });

    test('“明天有什么日程安排”直接查本地工具，不依赖模型自由回答', () async {
      final _FakeQueryTasksTool queryTool = _FakeQueryTasksTool();
      final _FakeDoubaoChatClient chat = _FakeDoubaoChatClient(
        <ChatRoundCompleteEvent>[],
      );
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          doubaoChatClientProvider.overrideWithValue(chat),
          toolRegistryProvider.overrideWithValue(
            ToolRegistry(<AssistantTool>[queryTool]),
          ),
          currentTtsPlaybackModeProvider.overrideWithValue(
            TtsPlaybackMode.silent,
          ),
        ],
      );
      addTearDown(container.dispose);

      final AssistantController controller = container.read(
        assistantControllerProvider.notifier,
      );
      await controller.sendUserMessage(
        '明天有什么日程安排',
        source: AssistantEntrySource.drawerText,
      );

      final AssistantUiState state = container.read(
        assistantControllerProvider,
      );
      expect(queryTool.callCount, 1);
      expect(chat.streamCount, 0);
      expect(
        state.messages
            .lastWhere(
              (AssistantMessage message) =>
                  message.role == AssistantRole.assistant && !message.streaming,
            )
            .content,
        contains('需求讨论会'),
      );
    });

    test('“把明天3点的会议改成4点”按时间和会议泛称匹配并进入修改确认', () async {
      final _FakeQueryTasksTool queryTool = _FakeQueryTasksTool();
      final _FakeUpdateTaskTool updateTool = _FakeUpdateTaskTool();
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          toolRegistryProvider.overrideWithValue(
            ToolRegistry(<AssistantTool>[queryTool, updateTool]),
          ),
          currentTtsPlaybackModeProvider.overrideWithValue(
            TtsPlaybackMode.silent,
          ),
        ],
      );
      addTearDown(container.dispose);

      final AssistantController controller = container.read(
        assistantControllerProvider.notifier,
      );
      await controller.sendUserMessage(
        '把明天3点的会议改成4点',
        source: AssistantEntrySource.drawerText,
      );

      final AssistantUiState state = container.read(
        assistantControllerProvider,
      );
      final Map<String, dynamic> args = state.pendingConfirm!.toolCall
          .argumentsAsMap();
      expect(state.pendingConfirm!.toolCall.name, 'update_task');
      expect(args['task_id'], 1);
      expect(args['start_time_minutes'], 16 * 60);
      expect(updateTool.callCount, 0);
    });

    test('多条候选时，用户说“第一条”会延续上一步并进入修改确认', () async {
      final _FakeQueryTasksTool queryTool = _FakeQueryTasksTool(
        tasks: <Map<String, Object?>>[
          <String, Object?>{
            'id': 1,
            'title': '需求讨论会',
            'date': '2026-05-09',
            'time': '15:00 - 16:00',
          },
          <String, Object?>{
            'id': 2,
            'title': '方案评审会',
            'date': '2026-05-09',
            'time': '15:00 - 15:30',
          },
        ],
      );
      final _FakeUpdateTaskTool updateTool = _FakeUpdateTaskTool();
      final _FakeDoubaoChatClient chat = _FakeDoubaoChatClient(
        <ChatRoundCompleteEvent>[],
      );
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          doubaoChatClientProvider.overrideWithValue(chat),
          toolRegistryProvider.overrideWithValue(
            ToolRegistry(<AssistantTool>[queryTool, updateTool]),
          ),
          currentTtsPlaybackModeProvider.overrideWithValue(
            TtsPlaybackMode.silent,
          ),
        ],
      );
      addTearDown(container.dispose);

      final AssistantController controller = container.read(
        assistantControllerProvider.notifier,
      );
      await controller.sendUserMessage(
        '把明天3点的会议改成4点',
        source: AssistantEntrySource.drawerText,
      );

      AssistantUiState state = container.read(assistantControllerProvider);
      expect(state.pendingConfirm, isNull);
      expect(
        state.messages
            .lastWhere(
              (AssistantMessage message) =>
                  message.role == AssistantRole.assistant && !message.streaming,
            )
            .content,
        contains('你要操作哪一个'),
      );

      await controller.sendUserMessage(
        '第一条',
        source: AssistantEntrySource.drawerText,
      );

      state = container.read(assistantControllerProvider);
      final Map<String, dynamic> args = state.pendingConfirm!.toolCall
          .argumentsAsMap();
      expect(chat.streamCount, 0);
      expect(state.pendingConfirm!.toolCall.name, 'update_task');
      expect(args['task_id'], 1);
      expect(args['start_time_minutes'], 16 * 60);
      expect(updateTool.callCount, 0);
    });

    test('删除明天下午3点需求讨论会先进入删除确认，确认后才调用工具', () async {
      final _FakeQueryTasksTool queryTool = _FakeQueryTasksTool();
      final _FakeDeleteTaskTool deleteTool = _FakeDeleteTaskTool();
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          toolRegistryProvider.overrideWithValue(
            ToolRegistry(<AssistantTool>[queryTool, deleteTool]),
          ),
          currentTtsPlaybackModeProvider.overrideWithValue(
            TtsPlaybackMode.silent,
          ),
        ],
      );
      addTearDown(container.dispose);

      final AssistantController controller = container.read(
        assistantControllerProvider.notifier,
      );
      await controller.sendUserMessage(
        '删除明天下午3点的需求讨论会',
        source: AssistantEntrySource.drawerText,
      );

      AssistantUiState state = container.read(assistantControllerProvider);
      expect(state.pendingConfirm!.toolCall.name, 'delete_task');
      expect(deleteTool.callCount, 0);

      await controller.confirmPendingTool();

      state = container.read(assistantControllerProvider);
      expect(state.pendingConfirm, isNull);
      expect(deleteTool.callCount, 1);
    });

    test('创建确认态说“需要提醒”会补上提醒，不会中断多轮流程', () async {
      final _FakeCreateTaskTool tool = _FakeCreateTaskTool();
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          toolRegistryProvider.overrideWithValue(
            ToolRegistry(<AssistantTool>[tool]),
          ),
          currentTtsPlaybackModeProvider.overrideWithValue(
            TtsPlaybackMode.silent,
          ),
        ],
      );
      addTearDown(container.dispose);

      final AssistantController controller = container.read(
        assistantControllerProvider.notifier,
      );
      await controller.sendUserMessage(
        '明天下午5点开会',
        source: AssistantEntrySource.drawerText,
      );
      await controller.sendUserMessage(
        '需要提醒',
        source: AssistantEntrySource.drawerText,
      );

      AssistantUiState state = container.read(assistantControllerProvider);
      expect(state.pendingConfirm, isNotNull);
      expect(
        state.pendingConfirm!.toolCall.argumentsAsMap()['reminder_key'],
        'before10m',
      );
      expect(tool.callCount, 0);

      await controller.confirmPendingTool();
      state = container.read(assistantControllerProvider);
      expect(state.pendingConfirm, isNull);
      expect(tool.callCount, 1);
    });

    test('标记完成工具执行后由 App 直接收尾并提示可撤销', () async {
      final _FakeCompleteTaskTool tool = _FakeCompleteTaskTool();
      final _FakeDoubaoChatClient chat = _FakeDoubaoChatClient(
        <ChatRoundCompleteEvent>[
          ChatRoundCompleteEvent(
            content: '',
            toolCalls: <ToolCall>[
              ToolCall(
                id: 'call_complete',
                name: tool.name,
                argumentsJson: '{"task_id":1}',
              ),
            ],
            finishReason: 'tool_calls',
          ),
        ],
      );
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          doubaoChatClientProvider.overrideWithValue(chat),
          toolRegistryProvider.overrideWithValue(
            ToolRegistry(<AssistantTool>[tool]),
          ),
          currentTtsPlaybackModeProvider.overrideWithValue(
            TtsPlaybackMode.silent,
          ),
        ],
      );
      addTearDown(container.dispose);

      final AssistantController controller = container.read(
        assistantControllerProvider.notifier,
      );
      await controller.sendUserMessage(
        '把写周报标记完成',
        source: AssistantEntrySource.drawerText,
      );

      final AssistantUiState state = container.read(
        assistantControllerProvider,
      );
      final String latest = state.messages
          .lastWhere(
            (AssistantMessage message) =>
                message.role == AssistantRole.assistant && !message.streaming,
          )
          .content;
      expect(chat.streamCount, 1);
      expect(latest, '已把「写周报」标记完成。刚才这一步可以撤销。');
    });
  });
}

class _FakeWriteTool extends AssistantTool {
  int callCount = 0;

  @override
  String get name => 'fake_write_task';

  @override
  String get description => '测试用写入工具';

  @override
  Map<String, dynamic> get parametersSchema => <String, dynamic>{
    'type': 'object',
    'properties': <String, dynamic>{
      'title': <String, dynamic>{'type': 'string'},
    },
  };

  @override
  Future<AssistantConfirmPreview?> buildConfirmPreview(
    Map<String, dynamic> args,
  ) async {
    return AssistantConfirmPreview(
      title: '准备创建',
      rows: <ConfirmRow>[
        ConfirmRow(
          label: '标题',
          value: (args['title'] as String?) ?? '未命名',
          icon: '📌',
        ),
      ],
    );
  }

  @override
  Future<String> call(Map<String, dynamic> args) async {
    callCount += 1;
    return jsonEncode(<String, Object?>{
      'ok': true,
      'title': args['title'] ?? '未命名',
    });
  }
}

class _FakeCreateTaskTool extends AssistantTool {
  _FakeCreateTaskTool({this.result});

  final String? result;
  int callCount = 0;

  @override
  String get name => 'create_task';

  @override
  String get description => '测试用创建任务工具';

  @override
  Map<String, dynamic> get parametersSchema => <String, dynamic>{
    'type': 'object',
    'properties': <String, dynamic>{
      'title': <String, dynamic>{'type': 'string'},
      'start_date': <String, dynamic>{'type': 'string'},
      'start_time_minutes': <String, dynamic>{'type': 'integer'},
    },
  };

  @override
  Future<AssistantConfirmPreview?> buildConfirmPreview(
    Map<String, dynamic> args,
  ) async {
    return AssistantConfirmPreview(
      title: '准备创建',
      rows: <ConfirmRow>[
        ConfirmRow(label: '标题', value: (args['title'] as String?) ?? '未命名'),
        ConfirmRow(
          label: '时间',
          value:
              '${args['start_date'] ?? ''} · ${args['start_time_minutes'] ?? ''}',
          highlighted: true,
        ),
      ],
    );
  }

  @override
  Future<String> call(Map<String, dynamic> args) async {
    callCount += 1;
    return result ??
        jsonEncode(<String, Object?>{
          'ok': true,
          'id': 1,
          'title': args['title'] ?? '未命名',
        });
  }
}

class _FakeQueryTasksTool extends AssistantTool {
  _FakeQueryTasksTool({this.tasks});

  final List<Map<String, Object?>>? tasks;
  int callCount = 0;

  @override
  String get name => 'query_tasks';

  @override
  String get description => '测试用查询任务工具';

  @override
  Map<String, dynamic> get parametersSchema => <String, dynamic>{
    'type': 'object',
    'properties': <String, dynamic>{},
  };

  @override
  Future<String> call(Map<String, dynamic> args) async {
    callCount += 1;
    return jsonEncode(<String, Object?>{
      'ok': true,
      'count': tasks?.length ?? 1,
      'tasks':
          tasks ??
          <Map<String, Object?>>[
            <String, Object?>{
              'id': 1,
              'title': '需求讨论会',
              'date': '2026-05-09',
              'time': '15:00 - 16:00',
            },
          ],
    });
  }
}

class _FakeUpdateTaskTool extends AssistantTool {
  int callCount = 0;

  @override
  String get name => 'update_task';

  @override
  String get description => '测试用修改任务工具';

  @override
  Map<String, dynamic> get parametersSchema => <String, dynamic>{
    'type': 'object',
    'properties': <String, dynamic>{},
  };

  @override
  Future<AssistantConfirmPreview?> buildConfirmPreview(
    Map<String, dynamic> args,
  ) async {
    return AssistantConfirmPreview(
      title: '准备修改',
      rows: <ConfirmRow>[
        const ConfirmRow(label: '标题', value: '需求讨论会'),
        ConfirmRow(
          label: '时间',
          value: '15:00-16:00 → ${args['start_time_minutes']}',
        ),
      ],
    );
  }

  @override
  Future<String> call(Map<String, dynamic> args) async {
    callCount += 1;
    return jsonEncode(<String, Object?>{
      'ok': true,
      'id': args['task_id'] ?? 1,
      'title': '需求讨论会',
    });
  }
}

class _FakeDeleteTaskTool extends AssistantTool {
  int callCount = 0;

  @override
  String get name => 'delete_task';

  @override
  String get description => '测试用删除任务工具';

  @override
  Map<String, dynamic> get parametersSchema => <String, dynamic>{
    'type': 'object',
    'properties': <String, dynamic>{},
  };

  @override
  Future<AssistantConfirmPreview?> buildConfirmPreview(
    Map<String, dynamic> args,
  ) async {
    return const AssistantConfirmPreview(
      title: '准备删除',
      severity: ConfirmSeverity.warning,
      rows: <ConfirmRow>[
        ConfirmRow(label: '标题', value: '需求讨论会'),
        ConfirmRow(label: '时间', value: '明天 · 15:00-16:00'),
      ],
    );
  }

  @override
  Future<String> call(Map<String, dynamic> args) async {
    callCount += 1;
    return jsonEncode(<String, Object?>{
      'ok': true,
      'id': args['task_id'] ?? 1,
    });
  }
}

class _FakeCompleteTaskTool extends AssistantTool {
  int callCount = 0;

  @override
  String get name => 'complete_task';

  @override
  String get description => '测试用完成任务工具';

  @override
  Map<String, dynamic> get parametersSchema => <String, dynamic>{
    'type': 'object',
    'properties': <String, dynamic>{},
  };

  @override
  Future<String> call(Map<String, dynamic> args) async {
    callCount += 1;
    return jsonEncode(<String, Object?>{'ok': true, 'id': 1, 'title': '写周报'});
  }
}

class _FakeImmediateResponsesClient extends DoubaoResponsesClient {
  _FakeImmediateResponsesClient(this.text)
    : super(
        env: const EnvConfig(
          volcArkApiKey: 'test',
          doubaoEndpointId: 'test',
          xfAppId: '',
          xfApiKey: '',
          xfApiSecret: '',
          amapKey: '',
        ),
      );

  final String text;
  int streamCount = 0;

  @override
  Stream<PublicResponseEvent> streamPublicResponse({
    required String userText,
    required AssistantExecutionMode mode,
    String? previousResponseId,
    bool summaryOnly = false,
    CancelToken? cancelToken,
  }) async* {
    streamCount += 1;
    yield PublicResponseRequestAcceptedEvent('resp_weather');
    yield PublicResponseTextDeltaEvent(text);
    yield PublicResponseCompletedEvent(responseId: 'resp_weather', text: text);
  }
}

class _FakeDoubaoChatClient extends DoubaoChatClient {
  _FakeDoubaoChatClient(List<ChatRoundCompleteEvent> rounds)
    : _rounds = List<ChatRoundCompleteEvent>.from(rounds),
      super(
        env: const EnvConfig(
          volcArkApiKey: 'test',
          doubaoEndpointId: 'test',
          xfAppId: '',
          xfApiKey: '',
          xfApiSecret: '',
          amapKey: '',
        ),
      );

  final List<ChatRoundCompleteEvent> _rounds;
  int streamCount = 0;

  @override
  Stream<ChatStreamEvent> streamCompletion({
    required List<AssistantMessage> messages,
    String? userId,
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
  }) async* {
    streamCount += 1;
    if (_rounds.isEmpty) {
      throw StateError('no fake rounds left');
    }
    yield _rounds.removeAt(0);
  }
}
