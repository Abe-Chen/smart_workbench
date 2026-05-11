import 'dart:async';
import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smart_workbench/core/config/env_config.dart';
import 'package:smart_workbench/features/assistant/application/assistant_controller.dart';
import 'package:smart_workbench/features/assistant/application/assistant_state.dart';
import 'package:smart_workbench/features/assistant/data/doubao_responses_client.dart';
import 'package:smart_workbench/features/assistant/domain/assistant_execution_mode.dart';
import 'package:smart_workbench/features/assistant/domain/assistant_message.dart';
import 'package:smart_workbench/features/settings/application/app_settings_controller.dart';
import 'package:smart_workbench/features/settings/domain/app_settings.dart';

void main() {
  group('public response flow', () {
    test('开始返回内容后可停止生成，并保留已生成文本', () async {
      final StreamController<PublicResponseEvent> stream =
          StreamController<PublicResponseEvent>();
      final _FakeDoubaoResponsesClient client = _FakeDoubaoResponsesClient(
        <StreamController<PublicResponseEvent>>[stream],
      );

      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          doubaoResponsesClientProvider.overrideWithValue(client),
          currentTtsPlaybackModeProvider.overrideWithValue(
            TtsPlaybackMode.auto,
          ),
        ],
      );
      addTearDown(container.dispose);

      final AssistantController controller = container.read(
        assistantControllerProvider.notifier,
      );
      final Future<void> future = controller.sendUserMessage(
        '今天美元汇率多少',
        source: AssistantEntrySource.drawerText,
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));
      stream.add(PublicResponseRequestAcceptedEvent('resp_1'));
      stream.add(PublicResponseTextDeltaEvent('先给你一句结论'));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      controller.stopCurrentGeneration();
      await future;

      final AssistantUiState state = container.read(
        assistantControllerProvider,
      );
      expect(state.stage, AssistantStage.idle);
      expect(state.progress.status, isNull);
      expect(
        state.messages
            .lastWhere(
              (AssistantMessage message) =>
                  message.role == AssistantRole.assistant && !message.streaming,
            )
            .content,
        contains('先给你一句结论'),
      );
      expect(
        client.requests.single.mode,
        AssistantExecutionMode.publicRealtime,
      );
    });

    test('先给我结论会取消原请求并重发 summaryOnly 请求', () async {
      final StreamController<PublicResponseEvent> first =
          StreamController<PublicResponseEvent>();
      final StreamController<PublicResponseEvent> second =
          StreamController<PublicResponseEvent>();
      final _FakeDoubaoResponsesClient client = _FakeDoubaoResponsesClient(
        <StreamController<PublicResponseEvent>>[first, second],
      );

      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          doubaoResponsesClientProvider.overrideWithValue(client),
          currentTtsPlaybackModeProvider.overrideWithValue(
            TtsPlaybackMode.auto,
          ),
        ],
      );
      addTearDown(container.dispose);

      final AssistantController controller = container.read(
        assistantControllerProvider.notifier,
      );
      final Future<void> future = controller.sendUserMessage(
        '上海附近有什么适合商务宴请的餐厅',
        source: AssistantEntrySource.drawerText,
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));
      first.add(PublicResponseRequestAcceptedEvent('resp_1'));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await controller.requestConclusionNow();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      second.add(PublicResponseRequestAcceptedEvent('resp_2'));
      second.add(PublicResponseTextDeltaEvent('先给结论：选安静、包间稳定的店。'));
      await second.close();

      await future;

      final AssistantUiState state = container.read(
        assistantControllerProvider,
      );
      expect(state.stage, AssistantStage.idle);
      expect(client.requests.length, 2);
      expect(client.requests[0].summaryOnly, false);
      expect(client.requests[1].summaryOnly, true);
      expect(client.requests[0].mode, AssistantExecutionMode.publicRealtime);
      expect(client.requests[1].mode, AssistantExecutionMode.publicRealtime);
      expect(
        state.messages
            .lastWhere(
              (AssistantMessage message) =>
                  message.role == AssistantRole.assistant && !message.streaming,
            )
            .content,
        contains('先给结论'),
      );
    });

    test('路线规划多轮补信息会保留上一轮出发地', () async {
      final StreamController<PublicResponseEvent> stream =
          StreamController<PublicResponseEvent>();
      final _FakeDoubaoResponsesClient client = _FakeDoubaoResponsesClient(
        <StreamController<PublicResponseEvent>>[stream],
      );

      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          doubaoResponsesClientProvider.overrideWithValue(client),
          currentTtsPlaybackModeProvider.overrideWithValue(
            TtsPlaybackMode.auto,
          ),
        ],
      );
      addTearDown(container.dispose);

      final AssistantController controller = container.read(
        assistantControllerProvider.notifier,
      );

      await controller.sendUserMessage(
        '帮我规划明天去客户现场的路线',
        source: AssistantEntrySource.drawerText,
      );
      expect(client.requests, isEmpty);
      expect(_latestAssistantText(container), contains('从哪里出发'));
      expect(_latestAssistantText(container), contains('客户现场具体到哪里'));

      await controller.sendUserMessage(
        '从北京市西二旗出发。',
        source: AssistantEntrySource.drawerText,
      );
      expect(client.requests, isEmpty);
      expect(_latestAssistantText(container), contains('北京市西二旗'));
      expect(_latestAssistantText(container), contains('客户现场具体到哪里'));

      final Future<void> future = controller.sendUserMessage(
        '到清河站开车去',
        source: AssistantEntrySource.drawerText,
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));
      stream.add(PublicResponseRequestAcceptedEvent('resp_route'));
      stream.add(PublicResponseTextDeltaEvent('明白，从西二旗到清河站，建议开车。'));
      await stream.close();
      await future;

      expect(client.requests.length, 1);
      expect(
        client.requests.single.mode,
        AssistantExecutionMode.publicRealtime,
      );
      expect(client.requests.single.userText, contains('日期：明天'));
      expect(client.requests.single.userText, contains('出发地：北京市西二旗'));
      expect(client.requests.single.userText, contains('目的地：清河站'));
      expect(client.requests.single.userText, contains('出行方式：开车'));
      expect(_latestAssistantText(container), contains('建议开车'));
    });

    test('模型先追问路线信息后，后续补充仍会被 App 接管合并', () async {
      final StreamController<PublicResponseEvent> first =
          StreamController<PublicResponseEvent>();
      final StreamController<PublicResponseEvent> second =
          StreamController<PublicResponseEvent>();
      final _FakeDoubaoResponsesClient client = _FakeDoubaoResponsesClient(
        <StreamController<PublicResponseEvent>>[first, second],
      );

      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          doubaoResponsesClientProvider.overrideWithValue(client),
          currentTtsPlaybackModeProvider.overrideWithValue(
            TtsPlaybackMode.auto,
          ),
        ],
      );
      addTearDown(container.dispose);

      final AssistantController controller = container.read(
        assistantControllerProvider.notifier,
      );
      final Future<void> firstFuture = controller.sendUserMessage(
        '帮我规划明天去客户现场',
        source: AssistantEntrySource.drawerText,
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));
      first.add(PublicResponseRequestAcceptedEvent('resp_ask'));
      first.add(
        PublicResponseTextDeltaEvent('麻烦你提供出发地点、客户现场具体地址和出行方式，我来帮你规划路线。'),
      );
      await first.close();
      await firstFuture;

      await controller.sendUserMessage(
        '从北京市西二旗出发。',
        source: AssistantEntrySource.drawerText,
      );
      expect(client.requests.length, 1);
      expect(_latestAssistantText(container), contains('北京市西二旗'));
      expect(_latestAssistantText(container), contains('客户现场具体到哪里'));

      final Future<void> secondFuture = controller.sendUserMessage(
        '到清河站开车去',
        source: AssistantEntrySource.drawerText,
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));
      second.add(PublicResponseRequestAcceptedEvent('resp_route'));
      second.add(PublicResponseTextDeltaEvent('已按西二旗到清河站开车规划。'));
      await second.close();
      await secondFuture;

      expect(client.requests.length, 2);
      expect(client.requests.last.userText, contains('日期：明天'));
      expect(client.requests.last.userText, contains('出发地：北京市西二旗'));
      expect(client.requests.last.userText, contains('目的地：清河站'));
      expect(client.requests.last.userText, contains('出行方式：开车'));
      expect(_latestAssistantText(container), contains('西二旗到清河站'));
    });

    test('路线补信息期间问产品路线图会切回普通回答', () async {
      final StreamController<PublicResponseEvent> stream =
          StreamController<PublicResponseEvent>();
      final _FakeDoubaoResponsesClient client = _FakeDoubaoResponsesClient(
        <StreamController<PublicResponseEvent>>[stream],
      );

      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          doubaoResponsesClientProvider.overrideWithValue(client),
          currentTtsPlaybackModeProvider.overrideWithValue(
            TtsPlaybackMode.auto,
          ),
        ],
      );
      addTearDown(container.dispose);

      final AssistantController controller = container.read(
        assistantControllerProvider.notifier,
      );

      await controller.sendUserMessage(
        '帮我规划明天去客户现场的路线',
        source: AssistantEntrySource.drawerText,
      );
      expect(client.requests, isEmpty);

      final Future<void> future = controller.sendUserMessage(
        '产品路线图怎么做',
        source: AssistantEntrySource.drawerText,
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));
      stream.add(PublicResponseRequestAcceptedEvent('resp_product_roadmap'));
      stream.add(PublicResponseTextDeltaEvent('产品路线图要先明确目标、阶段和优先级。'));
      await stream.close();
      await future;

      expect(client.requests.length, 1);
      expect(client.requests.single.userText, '产品路线图怎么做');
      expect(client.requests.single.mode, AssistantExecutionMode.publicQuick);
      expect(_latestAssistantText(container), contains('产品路线图'));
    });

    test('路线补信息期间说取消会结束当前路线规划', () async {
      final _FakeDoubaoResponsesClient client = _FakeDoubaoResponsesClient(
        <StreamController<PublicResponseEvent>>[],
      );

      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          doubaoResponsesClientProvider.overrideWithValue(client),
          currentTtsPlaybackModeProvider.overrideWithValue(
            TtsPlaybackMode.auto,
          ),
        ],
      );
      addTearDown(container.dispose);

      final AssistantController controller = container.read(
        assistantControllerProvider.notifier,
      );

      await controller.sendUserMessage(
        '帮我规划明天去客户现场的路线',
        source: AssistantEntrySource.drawerText,
      );
      await controller.sendUserMessage(
        '取消',
        source: AssistantEntrySource.drawerText,
      );

      expect(client.requests, isEmpty);
      expect(_latestAssistantText(container), contains('路线规划先不继续'));
      expect(_latestAssistantText(container), isNot(contains('去取消')));
    });

    test('模型追问路线信息后说取消不会被当成目的地', () async {
      final StreamController<PublicResponseEvent> first =
          StreamController<PublicResponseEvent>();
      final _FakeDoubaoResponsesClient client = _FakeDoubaoResponsesClient(
        <StreamController<PublicResponseEvent>>[first],
      );

      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          doubaoResponsesClientProvider.overrideWithValue(client),
          currentTtsPlaybackModeProvider.overrideWithValue(
            TtsPlaybackMode.auto,
          ),
        ],
      );
      addTearDown(container.dispose);

      final AssistantController controller = container.read(
        assistantControllerProvider.notifier,
      );
      final Future<void> firstFuture = controller.sendUserMessage(
        '帮我规划明天去客户现场',
        source: AssistantEntrySource.drawerText,
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));
      first.add(PublicResponseRequestAcceptedEvent('resp_ask'));
      first.add(PublicResponseTextDeltaEvent('麻烦你提供出发地点、客户现场具体地址和出行方式。'));
      await first.close();
      await firstFuture;

      await controller.sendUserMessage(
        '取消',
        source: AssistantEntrySource.drawerText,
      );

      expect(client.requests.length, 1);
      expect(_latestAssistantText(container), contains('路线规划先不继续'));
      expect(_latestAssistantText(container), isNot(contains('去取消')));
    });
  });
}

String _latestAssistantText(ProviderContainer container) {
  return container
      .read(assistantControllerProvider)
      .messages
      .lastWhere(
        (AssistantMessage message) =>
            message.role == AssistantRole.assistant && !message.streaming,
      )
      .content;
}

class _FakeDoubaoResponsesClient extends DoubaoResponsesClient {
  _FakeDoubaoResponsesClient(
    List<StreamController<PublicResponseEvent>> streams,
  ) : _streams = Queue<StreamController<PublicResponseEvent>>.from(streams),
      super(
        env: const EnvConfig(
          volcArkApiKey: 'test',
          doubaoEndpointId: 'test',
          xfAppId: '',
          xfApiKey: '',
          xfApiSecret: '',
          amapKey: '',
          volcTtsApiKey: '',
        ),
      );

  final Queue<StreamController<PublicResponseEvent>> _streams;
  final List<_RecordedRequest> requests = <_RecordedRequest>[];

  @override
  Stream<PublicResponseEvent> streamPublicResponse({
    required String userText,
    required AssistantExecutionMode mode,
    String? previousResponseId,
    bool summaryOnly = false,
    CancelToken? cancelToken,
  }) {
    requests.add(
      _RecordedRequest(
        userText: userText,
        mode: mode,
        previousResponseId: previousResponseId,
        summaryOnly: summaryOnly,
      ),
    );
    final StreamController<PublicResponseEvent> stream = _streams.removeFirst();
    cancelToken?.whenCancel.then((_) {
      if (!stream.isClosed) {
        stream.close();
      }
    });
    return stream.stream;
  }
}

class _RecordedRequest {
  const _RecordedRequest({
    required this.userText,
    required this.mode,
    required this.previousResponseId,
    required this.summaryOnly,
  });

  final String userText;
  final AssistantExecutionMode mode;
  final String? previousResponseId;
  final bool summaryOnly;
}
