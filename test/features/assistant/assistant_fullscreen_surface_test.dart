import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smart_workbench/features/assistant/application/assistant_controller.dart';
import 'package:smart_workbench/features/assistant/application/assistant_state.dart';
import 'package:smart_workbench/features/assistant/application/tool_registry.dart';
import 'package:smart_workbench/features/assistant/domain/assistant_confirm_preview.dart';
import 'package:smart_workbench/features/assistant/domain/assistant_tool.dart';
import 'package:smart_workbench/features/settings/application/app_settings_controller.dart';
import 'package:smart_workbench/features/settings/domain/app_settings.dart';

void main() {
  group('assistant fullscreen surface', () {
    test('quickVoice 缺字段追问走全屏大卡，不打开抽屉', () async {
      final ProviderContainer container = _containerWithCreateTool();
      addTearDown(container.dispose);

      await container
          .read(assistantControllerProvider.notifier)
          .sendUserMessage('创建一个日程', source: AssistantEntrySource.quickVoice);

      final AssistantUiState state = container.read(
        assistantControllerProvider,
      );
      expect(state.drawerOpen, isFalse);
      expect(state.surfaceState, AssistantSurfaceState.fullscreenAnswer);
      expect(state.answerCardKind, AnswerCardKind.clarification);
      expect(state.answerCardText, contains('安排在什么时候'));
      expect(state.pendingWriteDraft, isNotNull);
    });

    test('quickVoice 补全日程后确认卡走全屏大卡', () async {
      final ProviderContainer container = _containerWithCreateTool();
      addTearDown(container.dispose);
      final AssistantController controller = container.read(
        assistantControllerProvider.notifier,
      );

      await controller.sendUserMessage(
        '创建一个日程',
        source: AssistantEntrySource.quickVoice,
      );
      await controller.sendUserMessage(
        '明天下午 3 点需求讨论会',
        source: AssistantEntrySource.quickVoice,
      );

      final AssistantUiState state = container.read(
        assistantControllerProvider,
      );
      expect(state.drawerOpen, isFalse);
      expect(state.surfaceState, AssistantSurfaceState.fullscreenAnswer);
      expect(state.answerCardKind, AnswerCardKind.confirm);
      expect(state.pendingConfirm, isNotNull);
    });

    test('quickVoice 确认态补充提醒后仍停留在全屏大卡', () async {
      final ProviderContainer container = _containerWithCreateTool();
      addTearDown(container.dispose);
      final AssistantController controller = container.read(
        assistantControllerProvider.notifier,
      );

      await controller.sendUserMessage(
        '帮我创建一个明天下午 3 点的需求讨论会的日程',
        source: AssistantEntrySource.quickVoice,
      );
      controller.hideAnswerCard(stopSpeaking: false);

      await controller.sendUserMessage(
        '提前 10 分钟提醒我',
        source: AssistantEntrySource.quickVoice,
      );

      final AssistantUiState state = container.read(
        assistantControllerProvider,
      );
      expect(state.drawerOpen, isFalse);
      expect(state.surfaceState, AssistantSurfaceState.fullscreenAnswer);
      expect(state.answerCardKind, AnswerCardKind.confirm);
      expect(state.pendingConfirm, isNotNull);
      expect(
        state.pendingConfirm!.toolCall.argumentsAsMap()['reminder_key'],
        'before10m',
      );
    });

    test('大卡展开抽屉时会请求定位到最新消息', () async {
      final ProviderContainer container = _containerWithCreateTool();
      addTearDown(container.dispose);
      final AssistantController controller = container.read(
        assistantControllerProvider.notifier,
      );

      await controller.sendUserMessage(
        '创建一个日程',
        source: AssistantEntrySource.quickVoice,
      );
      final int before = container
          .read(assistantControllerProvider)
          .drawerOpenRequestId;

      controller.expandAnswerCardToDrawer();

      final AssistantUiState state = container.read(
        assistantControllerProvider,
      );
      expect(state.drawerOpen, isTrue);
      expect(state.surfaceState, AssistantSurfaceState.drawerOpen);
      expect(state.answerCardKind, isNull);
      expect(state.drawerOpenRequestId, before + 1);
      expect(
        state.drawerScrollTarget,
        AssistantDrawerScrollTarget.latestMessage,
      );
    });

    test('drawerText 仍然走抽屉，不弹全屏大卡', () async {
      final ProviderContainer container = _containerWithCreateTool();
      addTearDown(container.dispose);

      await container
          .read(assistantControllerProvider.notifier)
          .sendUserMessage('创建一个日程', source: AssistantEntrySource.drawerText);

      final AssistantUiState state = container.read(
        assistantControllerProvider,
      );
      expect(state.drawerOpen, isTrue);
      expect(state.surfaceState, AssistantSurfaceState.drawerOpen);
      expect(state.replySurface, AssistantReplySurface.drawer);
      expect(state.answerCardKind, isNull);
    });

    test('抽屉已打开时 quickVoice 也留在抽屉，不弹全屏大卡', () async {
      final ProviderContainer container = _containerWithCreateTool();
      addTearDown(container.dispose);
      final AssistantController controller = container.read(
        assistantControllerProvider.notifier,
      );

      controller.openDrawer();
      await controller.sendUserMessage(
        '创建一个日程',
        source: AssistantEntrySource.quickVoice,
      );

      final AssistantUiState state = container.read(
        assistantControllerProvider,
      );
      expect(state.drawerOpen, isTrue);
      expect(state.surfaceState, AssistantSurfaceState.drawerOpen);
      expect(state.replySurface, AssistantReplySurface.drawer);
      expect(state.answerCardKind, isNull);
    });

    test('drawerText 进入确认态时会请求定位确认区域', () async {
      final ProviderContainer container = _containerWithCreateTool();
      addTearDown(container.dispose);

      await container
          .read(assistantControllerProvider.notifier)
          .sendUserMessage(
            '明天下午3点需求讨论会',
            source: AssistantEntrySource.drawerText,
          );

      final AssistantUiState state = container.read(
        assistantControllerProvider,
      );
      expect(state.drawerOpen, isTrue);
      expect(state.surfaceState, AssistantSurfaceState.drawerOpen);
      expect(state.pendingConfirm, isNotNull);
      expect(state.drawerOpenRequestId, greaterThan(0));
      expect(
        state.drawerScrollTarget,
        AssistantDrawerScrollTarget.pendingConfirm,
      );
    });
  });
}

ProviderContainer _containerWithCreateTool() {
  return ProviderContainer(
    overrides: <Override>[
      toolRegistryProvider.overrideWithValue(
        ToolRegistry(<AssistantTool>[_FakeCreateTaskTool()]),
      ),
      currentTtsPlaybackModeProvider.overrideWithValue(TtsPlaybackMode.silent),
    ],
  );
}

class _FakeCreateTaskTool extends AssistantTool {
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
    return jsonEncode(<String, Object?>{
      'ok': true,
      'id': 1,
      'title': args['title'] ?? '未命名',
    });
  }
}
