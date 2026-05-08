import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/identity/device_id.dart';
import '../../../core/location/location_repository.dart';
import '../../../core/voice/pcm_stream_recorder.dart';
import '../data/doubao_chat_client.dart';
import '../data/doubao_responses_client.dart';
import '../data/xunfei_asr_client.dart';
import '../data/xunfei_tts_client.dart';
import '../../settings/application/app_settings_controller.dart';
import '../../settings/domain/app_settings.dart';
import '../domain/assistant_message.dart';
import '../domain/assistant_result_card.dart';
import '../domain/assistant_tool.dart';
import '../domain/tool_call.dart';
import '../prompts/system_prompt.dart';
import 'assistant_request_router.dart';
import 'assistant_state.dart';
import 'tool_registry.dart';

const int _kMaxToolRounds = 4;
const Duration _kOpenMicWait = Duration(seconds: 8);
const Duration _kFollowUpWindow = Duration(seconds: 5);

enum AssistantEntrySource { drawerText, drawerVoice, quickVoice }

class AssistantController extends Notifier<AssistantUiState> {
  StreamSubscription<ChatStreamEvent>? _streamSub;
  bool _aborted = false;

  PcmStreamRecorder? _recorder;
  XunfeiAsrClient? _asrClient;
  StreamSubscription<Uint8List>? _recorderSub;
  StreamSubscription<AsrEvent>? _asrSub;
  bool _autoSendOnFinal = true;
  AssistantEntrySource _listeningSource = AssistantEntrySource.drawerVoice;
  Timer? _openMicTimeoutTimer;
  Timer? _openMicTicker;
  bool _heardSpeechInCurrentOpenMic = false;
  Timer? _followUpExpireTimer;
  Timer? _followUpTicker;

  AssistantEntrySource _lastEntrySource = AssistantEntrySource.drawerText;
  String? _lastPublicResponseId;

  @override
  AssistantUiState build() {
    ref.onDispose(() {
      _aborted = true;
      _streamSub?.cancel();
      _cancelOpenMicWait();
      _cancelFollowUpWindow();
      _teardownVoice();
    });
    return AssistantUiState.initial();
  }

  void openDrawer() {
    _cancelFollowUpWindow();
    state = state.copyWith(
      drawerOpen: true,
      replySurface: AssistantReplySurface.drawer,
      clearError: true,
      clearCompactReply: true,
    );
  }

  void closeDrawer() {
    state = state.copyWith(drawerOpen: false);
  }

  void toggleDrawer() {
    if (state.drawerOpen) {
      closeDrawer();
    } else {
      openDrawer();
    }
  }

  Future<void> sendUserMessage(
    String text, {
    AssistantEntrySource source = AssistantEntrySource.drawerText,
  }) async {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (state.stage == AssistantStage.think ||
        state.stage == AssistantStage.answer) {
      return;
    }
    _cancelFollowUpWindow();
    _lastEntrySource = source;
    final AssistantRequestPlan requestPlan = AssistantRequestRouter.planFor(
      text: trimmed,
      hasPublicContext:
          _lastPublicResponseId != null &&
          _lastPublicResponseId!.trim().isNotEmpty,
    );

    final AssistantMessage userMsg = AssistantMessage(
      role: AssistantRole.user,
      content: trimmed,
    );
    final AssistantMessage placeholder = AssistantMessage(
      role: AssistantRole.assistant,
      content: '',
      streaming: true,
    );

    final List<String> initialSteps = <String>[
      '已识别：${requestPlan.intent.label}',
    ];
    if (requestPlan.intent.isLocalWrite &&
        !_hasLocalWriteTool(ref.read(toolRegistryProvider))) {
      initialSteps.add('写入能力还没接入，先用现有工具回答');
    }

    state = state.copyWith(
      stage: AssistantStage.think,
      messages: <AssistantMessage>[...state.messages, userMsg, placeholder],
      replySurface: AssistantReplySurface.none,
      clearCompactReply: true,
      clearError: true,
      progress: AssistantProgressState(
        status: '正在理解你的问题',
        steps: initialSteps,
      ),
    );

    _aborted = false;
    try {
      switch (requestPlan.route) {
        case AssistantRequestRoute.publicResponses:
          await _runPublicResponse(
            trimmed,
            continuePublicContext: requestPlan.continuePublicContext,
          );
          break;
        case AssistantRequestRoute.localTools:
          await _runConversationLoop();
          break;
      }
    } catch (e) {
      final String message = _userFacingErrorMessage(e);
      _replaceTrailingAssistant(content: '出错了：$message', streaming: false);
      state = state.copyWith(
        stage: AssistantStage.error,
        error: message,
        clearProgress: true,
      );
    }
  }

  Future<void> _runPublicResponse(
    String userText, {
    required bool continuePublicContext,
  }) async {
    final DoubaoResponsesClient client = ref.read(
      doubaoResponsesClientProvider,
    );
    final bool continuePublic =
        continuePublicContext &&
        _lastPublicResponseId != null &&
        _lastPublicResponseId!.trim().isNotEmpty;
    if (continuePublic) {
      _appendProgressStep('延续上一轮公开话题');
    }
    final String publicQuery = await _buildPublicQuery(
      userText,
      allowLocationContext: !continuePublic,
    );
    if (publicQuery != userText.trim()) {
      _appendProgressStep('已补充当前位置上下文');
    }
    _setProgressStatus('正在联网搜索公开信息');
    final DoubaoResponsesResult result = await client.createPublicResponse(
      userText: publicQuery,
      previousResponseId: continuePublic ? _lastPublicResponseId : null,
    );
    if (_aborted) return;
    _lastPublicResponseId = result.id;
    _appendProgressStep('已拿到联网结果');
    _setProgressStatus('正在整理回答');
    _finishAssistantTurn(result.text);
  }

  /// function calling 多轮循环：
  /// 1. 用当前消息列表调一次 chat
  /// 2. 收到 token 实时更新 UI
  /// 3. round 结束如果有 tool_calls，应用层执行所有 tool，把结果作为
  ///    role=tool 的消息塞回历史，再调一次 chat
  /// 4. 直到 round 没有 tool_calls 或达到上限
  Future<void> _runConversationLoop() async {
    final DoubaoChatClient client = ref.read(doubaoChatClientProvider);
    final ToolRegistry registry = ref.read(toolRegistryProvider);
    final String? userId = ref.read(deviceIdProvider).valueOrNull;
    final List<Map<String, dynamic>> toolsApi = registry.isEmpty
        ? <Map<String, dynamic>>[]
        : registry.toApiJson();
    _setProgressStatus('正在分析是否需要本地处理');

    int round = 0;
    while (round < _kMaxToolRounds && !_aborted) {
      round += 1;

      final List<AssistantMessage> apiMessages = <AssistantMessage>[
        AssistantMessage(
          role: AssistantRole.system,
          content: kAssistantSystemPrompt,
        ),
        ..._historyForApi(),
      ];

      final ChatRoundCompleteEvent roundResult = await _streamOneRound(
        client,
        apiMessages,
        userId,
        toolsApi,
      );

      if (_aborted) return;

      if (!roundResult.hasToolCalls) {
        _setProgressStatus('正在整理回答');
        _finishAssistantTurn(roundResult.content);
        return;
      }

      // 有 tool_calls：把当前 placeholder 升级为 assistant tool_calls 消息
      // （不展示给用户），再为每个 tool 执行结果追加 role=tool 消息，
      // 然后开新 placeholder 进入下一轮。
      _promoteAssistantToolCallMessage(
        content: roundResult.content,
        toolCalls: roundResult.toolCalls,
      );
      _appendProgressStep('已识别需要本地处理');

      for (final ToolCall call in roundResult.toolCalls) {
        _setProgressStatus('正在读取本地信息');
        _appendProgressStep(_labelForToolCall(call.name));
        final String result = await _executeTool(registry, call);
        if (_aborted) return;
        _appendToolResult(call: call, result: result);
      }

      _setProgressStatus('正在整理工具结果');
      _appendAssistantPlaceholder();
    }

    if (round >= _kMaxToolRounds) {
      _replaceTrailingAssistant(content: '工具调用太多次了，先停下。', streaming: false);
      state = state.copyWith(stage: AssistantStage.idle, clearProgress: true);
    }
  }

  Future<ChatRoundCompleteEvent> _streamOneRound(
    DoubaoChatClient client,
    List<AssistantMessage> apiMessages,
    String? userId,
    List<Map<String, dynamic>> tools,
  ) async {
    final Completer<ChatRoundCompleteEvent> completer =
        Completer<ChatRoundCompleteEvent>();
    bool sawFirstToken = false;
    final StringBuffer buffer = StringBuffer();

    await _streamSub?.cancel();
    _streamSub = client
        .streamCompletion(
          messages: apiMessages,
          userId: userId,
          tools: tools.isEmpty ? null : tools,
        )
        .listen(
          (ChatStreamEvent event) {
            if (event is ChatTokenEvent) {
              if (!sawFirstToken) {
                sawFirstToken = true;
                _setProgressStatus('正在生成回答');
                state = state.copyWith(stage: AssistantStage.answer);
              }
              buffer.write(event.token);
              _replaceTrailingAssistant(
                content: buffer.toString(),
                streaming: true,
              );
            } else if (event is ChatRoundCompleteEvent) {
              if (!completer.isCompleted) completer.complete(event);
            }
          },
          onError: (Object err, StackTrace _) {
            if (!completer.isCompleted) completer.completeError(err);
          },
          cancelOnError: true,
        );

    return completer.future;
  }

  Future<String> _executeTool(ToolRegistry registry, ToolCall call) async {
    final AssistantTool? tool = registry.find(call.name);
    if (tool == null) {
      return '{"ok": false, "reason": "未知工具：${call.name}"}';
    }
    state = state.copyWith(stage: AssistantStage.think);
    try {
      return await tool.call(call.argumentsAsMap());
    } catch (e) {
      return '{"ok": false, "reason": "$e"}';
    }
  }

  /// 取出非 streaming placeholder 的、要发给 API 的历史消息。
  List<AssistantMessage> _historyForApi() {
    return state.messages.where((AssistantMessage m) => !m.streaming).toList();
  }

  void _replaceTrailingAssistant({
    required String content,
    required bool streaming,
    AssistantResultCard? resultCard,
  }) {
    final List<AssistantMessage> messages = List<AssistantMessage>.from(
      state.messages,
    );
    if (messages.isEmpty || messages.last.role != AssistantRole.assistant) {
      return;
    }
    messages[messages.length - 1] = messages.last.copyWith(
      content: content,
      streaming: streaming,
      resultCard: resultCard,
    );
    state = state.copyWith(messages: messages);
  }

  void _promoteAssistantToolCallMessage({
    required String content,
    required List<ToolCall> toolCalls,
  }) {
    final List<AssistantMessage> messages = List<AssistantMessage>.from(
      state.messages,
    );
    if (messages.isEmpty) return;
    messages[messages.length - 1] = messages.last.copyWith(
      content: content,
      streaming: false,
      toolCalls: toolCalls,
    );
    state = state.copyWith(messages: messages);
  }

  void _appendToolResult({required ToolCall call, required String result}) {
    final AssistantMessage toolMsg = AssistantMessage(
      role: AssistantRole.tool,
      content: result,
      toolCallId: call.id,
      toolName: call.name,
    );
    state = state.copyWith(
      messages: <AssistantMessage>[...state.messages, toolMsg],
    );
  }

  void _appendAssistantPlaceholder() {
    final AssistantMessage placeholder = AssistantMessage(
      role: AssistantRole.assistant,
      content: '',
      streaming: true,
    );
    state = state.copyWith(
      messages: <AssistantMessage>[...state.messages, placeholder],
      stage: AssistantStage.think,
    );
  }

  void clearConversation() {
    _aborted = true;
    _streamSub?.cancel();
    _cancelOpenMicWait();
    _cancelFollowUpWindow();
    _teardownVoice();
    _lastPublicResponseId = null;
    // sessionMute 跟随会话生命周期重置。
    state = AssistantUiState.initial().copyWith(
      drawerOpen: state.drawerOpen,
      clearProgress: true,
      clearTtsError: true,
    );
  }

  /// 切换本会话的播报开关。仅本对话生效，不写入全局设置。
  /// 持续到 [clearConversation] 触发为止。
  void setSessionMute(bool muted) {
    state = state.copyWith(
      sessionMute: muted
          ? AssistantSessionMute.muted
          : AssistantSessionMute.followSettings,
    );
    if (muted) {
      // 立即停掉正在播的内容
      // ignore: discarded_futures
      ref.read(xunfeiTtsClientProvider).stop();
    }
  }

  void dismissTtsError() {
    if (state.ttsError == null) return;
    state = state.copyWith(clearTtsError: true);
  }

  // ---------------- 语音输入（讯飞 IAT） ----------------

  Future<void> startListening({
    AssistantEntrySource source = AssistantEntrySource.drawerVoice,
    bool openDrawer = true,
    AssistantListeningMode mode = AssistantListeningMode.openMic,
  }) async {
    if (state.stage == AssistantStage.listen) return;
    await ref.read(xunfeiTtsClientProvider).stop();
    _cancelFollowUpWindow();
    _cancelOpenMicWait();
    _listeningSource = source;
    state = state.copyWith(
      drawerOpen: openDrawer,
      stage: AssistantStage.listen,
      replySurface: AssistantReplySurface.none,
      clearCompactReply: true,
      listeningMode: mode,
      listenPartialText: '',
      listenWindowRemainingMs: 0,
      clearListenError: true,
      clearProgress: true,
    );

    final PcmStreamRecorder recorder = ref.read(
      pcmStreamRecorderFactoryProvider,
    )();
    _recorder = recorder;

    final bool granted = await recorder.hasPermission();
    if (!granted) {
      state = state.copyWith(
        stage: AssistantStage.idle,
        listenError: '没有麦克风权限',
      );
      _teardownVoice();
      return;
    }

    final XunfeiAsrClient client = ref.read(xunfeiAsrClientFactoryProvider)();
    _asrClient = client;
    _autoSendOnFinal = true;

    _asrSub = client.events.listen(_handleAsrEvent);

    try {
      await client.start();
    } catch (e) {
      state = state.copyWith(
        stage: AssistantStage.idle,
        listenError: '讯飞连接失败：$e',
      );
      _teardownVoice();
      return;
    }

    try {
      final Stream<Uint8List> frames = await recorder.start();
      _recorderSub = frames.listen(
        (Uint8List frame) => client.sendAudio(frame),
        onError: (Object err, StackTrace _) {
          state = state.copyWith(listenError: '录音异常：$err');
        },
      );
      if (mode == AssistantListeningMode.openMic) {
        _startOpenMicWait();
      }
    } catch (e) {
      state = state.copyWith(
        stage: AssistantStage.idle,
        listenError: '录音启动失败：$e',
      );
      _teardownVoice();
    }
  }

  /// 松手 / 自动停 → 推 end frame，等服务端 final。
  Future<void> stopListening() async {
    if (state.stage != AssistantStage.listen) return;
    _cancelOpenMicWait();
    await _recorderSub?.cancel();
    _recorderSub = null;
    await _recorder?.stop();
    await _asrClient?.stop();
    // 不立即 teardown，等 AsrFinalEvent 到达后再清。
  }

  /// 用户取消，不发送给豆包。
  Future<void> cancelListening() async {
    _autoSendOnFinal = false;
    _cancelOpenMicWait();
    await _recorderSub?.cancel();
    _recorderSub = null;
    await _recorder?.stop();
    await _asrClient?.stop();
    state = state.copyWith(
      stage: AssistantStage.idle,
      listenPartialText: '',
      listenWindowRemainingMs: 0,
    );
    _teardownVoice();
  }

  void _handleAsrEvent(AsrEvent event) {
    if (event is AsrPartialEvent) {
      if (event.text.trim().isNotEmpty) {
        _markSpeechDetectedInOpenMic();
      }
      state = state.copyWith(listenPartialText: event.text);
    } else if (event is AsrFinalEvent) {
      final String text = event.text.trim();
      if (text.isNotEmpty) {
        _markSpeechDetectedInOpenMic();
      }
      _cancelOpenMicWait();
      _teardownVoice();
      state = state.copyWith(
        stage: AssistantStage.idle,
        listenPartialText: '',
        listenWindowRemainingMs: 0,
      );
      if (_autoSendOnFinal && text.isNotEmpty) {
        sendUserMessage(text, source: _listeningSource);
      }
    } else if (event is AsrErrorEvent) {
      _cancelOpenMicWait();
      state = state.copyWith(
        stage: AssistantStage.idle,
        listenError: '识别异常 (${event.code}): ${event.message}',
        listenWindowRemainingMs: 0,
      );
      _teardownVoice();
    }
  }

  void _speakAsync(String text) {
    final XunfeiTtsClient tts = ref.read(xunfeiTtsClientProvider);
    final String voice = ref.read(currentTtsVoiceProvider);
    final double rate = ref.read(currentTtsSpeedProvider);
    final String speakText = _buildSpeechText(text);
    if (speakText.isEmpty) {
      return;
    }
    // ignore: discarded_futures
    tts
        .speak(
          speakText,
          voice: voice,
          xunfeiSpeed: xunfeiSpeedForRate(rate),
        )
        .catchError((Object err) {
          if (err is XunfeiTtsException && err.message == '被中断') {
            return;
          }
          // TTS 失败不影响对话流程，记到独立的 ttsError 通道。
          state = state.copyWith(ttsError: 'TTS 播报失败：$err');
        });
  }

  Future<void> _speakCompactReplyAndStartFollowUp(String text) async {
    final XunfeiTtsClient tts = ref.read(xunfeiTtsClientProvider);
    final String voice = ref.read(currentTtsVoiceProvider);
    final double rate = ref.read(currentTtsSpeedProvider);
    final String speakText = _buildSpeechText(text);
    if (speakText.isEmpty) {
      _startFollowUpWindow();
      return;
    }

    try {
      await tts.speakAndWaitComplete(
        speakText,
        voice: voice,
        xunfeiSpeed: xunfeiSpeedForRate(rate),
      );
    } catch (err) {
      if (err is XunfeiTtsException && err.message == '被中断') {
        return;
      }
      state = state.copyWith(ttsError: 'TTS 播报失败：$err');
    }

    if (state.replySurface == AssistantReplySurface.compactCard &&
        state.compactReplyText != null &&
        state.compactReplyText!.trim().isNotEmpty) {
      _startFollowUpWindow();
    }
  }

  Future<void> replayLatestAssistantReply() async {
    final AssistantMessage latest = state.messages.lastWhere(
      (AssistantMessage message) =>
          message.role == AssistantRole.assistant &&
          message.content.trim().isNotEmpty &&
          !message.streaming,
      orElse: () =>
          AssistantMessage(role: AssistantRole.assistant, content: ''),
    );
    if (latest.content.trim().isEmpty) {
      return;
    }
    _speakAsync(latest.content);
  }

  void hideCompactReply() {
    _cancelFollowUpWindow();
    state = state.copyWith(
      replySurface: AssistantReplySurface.none,
      clearCompactReply: true,
    );
  }

  void _setProgressStatus(String status) {
    state = state.copyWith(
      progress: AssistantProgressState(
        status: status,
        steps: state.progress.steps,
      ),
    );
  }

  void _appendProgressStep(String step) {
    final String normalized = step.trim();
    if (normalized.isEmpty) {
      return;
    }
    final List<String> nextSteps = List<String>.from(state.progress.steps);
    if (nextSteps.isNotEmpty && nextSteps.last == normalized) {
      return;
    }
    nextSteps.add(normalized);
    state = state.copyWith(
      progress: AssistantProgressState(
        status: state.progress.status,
        steps: nextSteps,
      ),
    );
  }

  Future<String> _buildPublicQuery(
    String userText, {
    required bool allowLocationContext,
  }) async {
    final String normalized = userText.trim();
    if (!allowLocationContext ||
        normalized.isEmpty ||
        !_publicLocationSensitivePattern.hasMatch(normalized) ||
        _explicitPlacePattern.hasMatch(normalized)) {
      return normalized;
    }

    try {
      final LocationRepository repo = await ref.read(
        locationRepositoryProvider.future,
      );
      final CitySnapshot? snapshot = await repo.resolveCurrentCity();
      final String cityName = snapshot?.city.displayName.trim() ?? '';
      if (cityName.isEmpty) {
        return normalized;
      }
      return '$normalized\n\n补充上下文：用户当前城市是$cityName。';
    } catch (_) {
      return normalized;
    }
  }

  void _finishAssistantTurn(String content) {
    final AssistantDisplayContent displayContent = parseAssistantDisplayContent(
      content,
    );
    final String finalContent = displayContent.text.trim().isEmpty
        ? '我这次没拿到有效结果。'
        : displayContent.text.trim();
    final AssistantReplySurface surface = _resolveReplySurface(finalContent);
    _replaceTrailingAssistant(
      content: finalContent,
      streaming: false,
      resultCard: displayContent.resultCard,
    );
    state = state.copyWith(
      stage: AssistantStage.idle,
      drawerOpen: surface == AssistantReplySurface.drawer,
      replySurface: surface,
      compactReplyText: surface == AssistantReplySurface.compactCard
          ? finalContent
          : null,
      compactReplyCard: surface == AssistantReplySurface.compactCard
          ? displayContent.resultCard
          : null,
      followUpRemainingMs: 0,
      clearCompactReply: surface != AssistantReplySurface.compactCard,
      clearProgress: true,
      clearTtsError: true,
    );
    _cancelFollowUpWindow();

    if (finalContent.trim().isEmpty) return;

    final TtsPlaybackMode mode = ref.read(currentTtsPlaybackModeProvider);
    final bool shouldSpeak = decideAutoSpeak(
      entrySource: _lastEntrySource,
      surface: surface,
      mode: mode,
      sessionMute: state.sessionMute,
    );
    if (!shouldSpeak) return;

    if (surface == AssistantReplySurface.compactCard) {
      // 短答卡片：播报 + 5 秒持续对话窗（行为同原版）。
      // ignore: discarded_futures
      _speakCompactReplyAndStartFollowUp(finalContent);
    } else if (surface == AssistantReplySurface.drawer) {
      // 抽屉播报：fire-and-forget，不启动持续对话窗（避免抽屉里听到声音
      // 后又要被 5 秒倒计时催着说话，与"深度阅读"姿势冲突）。
      _speakAsync(finalContent);
    }
  }

  AssistantReplySurface _resolveReplySurface(String text) {
    switch (_lastEntrySource) {
      case AssistantEntrySource.drawerText:
      case AssistantEntrySource.drawerVoice:
        return AssistantReplySurface.drawer;
      case AssistantEntrySource.quickVoice:
        return _shouldUseCompactCard(text)
            ? AssistantReplySurface.compactCard
            : AssistantReplySurface.drawer;
    }
  }

  bool _shouldUseCompactCard(String text) {
    final String normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) {
      return false;
    }

    final Iterable<RegExpMatch> punctuation = RegExp(
      r'[。！？!?\.]',
    ).allMatches(normalized);
    final int sentenceCount = punctuation.length;
    if (sentenceCount > 2) {
      return false;
    }
    if (normalized.length <= 72) {
      return true;
    }
    return sentenceCount > 0 && normalized.length <= 120;
  }

  String _buildSpeechText(String text) {
    final String normalized = text
        .replaceAll(RegExp(r'[`*_#>-]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) {
      return '';
    }

    final RegExp firstSentencePattern = RegExp(r'^.{1,120}?[。！？!?\.](?=\s|$)');
    final Match? match = firstSentencePattern.firstMatch(normalized);
    if (match != null) {
      return match.group(0)!.trim();
    }

    if (normalized.length <= 120) {
      return normalized;
    }
    return '${normalized.substring(0, 120).trim()}...';
  }

  void _teardownVoice() {
    _cancelOpenMicWait();
    _recorderSub?.cancel();
    _recorderSub = null;
    _asrSub?.cancel();
    _asrSub = null;
    _asrClient?.dispose();
    _asrClient = null;
    _recorder?.dispose();
    _recorder = null;
  }

  void _startOpenMicWait() {
    _cancelOpenMicWait();
    _heardSpeechInCurrentOpenMic = false;
    state = state.copyWith(
      listenWindowRemainingMs: _kOpenMicWait.inMilliseconds,
    );
    _openMicTicker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (state.stage != AssistantStage.listen ||
          state.listeningMode != AssistantListeningMode.openMic ||
          _heardSpeechInCurrentOpenMic) {
        _cancelOpenMicWait(resetState: false);
        return;
      }
      final int nextMs =
          state.listenWindowRemainingMs -
          const Duration(milliseconds: 200).inMilliseconds;
      state = state.copyWith(
        listenWindowRemainingMs: nextMs.clamp(0, _kOpenMicWait.inMilliseconds),
      );
    });
    _openMicTimeoutTimer = Timer(_kOpenMicWait, () async {
      if (state.stage != AssistantStage.listen ||
          state.listeningMode != AssistantListeningMode.openMic ||
          _heardSpeechInCurrentOpenMic) {
        return;
      }
      _autoSendOnFinal = false;
      await _recorderSub?.cancel();
      _recorderSub = null;
      await _recorder?.stop();
      await _asrClient?.stop();
      state = state.copyWith(
        stage: AssistantStage.idle,
        listenPartialText: '',
        listenError: '这次没听到你说话',
        listenWindowRemainingMs: 0,
      );
      _teardownVoice();
    });
  }

  void _markSpeechDetectedInOpenMic() {
    if (state.listeningMode != AssistantListeningMode.openMic) {
      return;
    }
    if (_heardSpeechInCurrentOpenMic) {
      return;
    }
    _heardSpeechInCurrentOpenMic = true;
    _cancelOpenMicWait();
  }

  void _cancelOpenMicWait({bool resetState = true}) {
    _openMicTimeoutTimer?.cancel();
    _openMicTimeoutTimer = null;
    _openMicTicker?.cancel();
    _openMicTicker = null;
    _heardSpeechInCurrentOpenMic = false;
    if (resetState && state.listenWindowRemainingMs != 0) {
      state = state.copyWith(listenWindowRemainingMs: 0);
    }
  }

  void _startFollowUpWindow() {
    _cancelFollowUpWindow();
    state = state.copyWith(
      followUpRemainingMs: _kFollowUpWindow.inMilliseconds,
    );
    _followUpTicker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (state.replySurface != AssistantReplySurface.compactCard ||
          state.compactReplyText == null ||
          state.compactReplyText!.trim().isEmpty) {
        _cancelFollowUpWindow();
        return;
      }
      final int nextMs =
          state.followUpRemainingMs -
          const Duration(milliseconds: 200).inMilliseconds;
      state = state.copyWith(
        followUpRemainingMs: nextMs.clamp(0, _kFollowUpWindow.inMilliseconds),
      );
    });
    _followUpExpireTimer = Timer(_kFollowUpWindow, () {
      state = state.copyWith(
        replySurface: AssistantReplySurface.none,
        clearCompactReply: true,
        followUpRemainingMs: 0,
      );
      _cancelFollowUpWindow(resetState: false);
    });
  }

  void _cancelFollowUpWindow({bool resetState = true}) {
    _followUpExpireTimer?.cancel();
    _followUpExpireTimer = null;
    _followUpTicker?.cancel();
    _followUpTicker = null;
    if (resetState && state.followUpRemainingMs != 0) {
      state = state.copyWith(followUpRemainingMs: 0);
    }
  }
}

final NotifierProvider<AssistantController, AssistantUiState>
assistantControllerProvider =
    NotifierProvider<AssistantController, AssistantUiState>(
      AssistantController.new,
    );

final RegExp _publicLocationSensitivePattern = RegExp(
  r'(天气|气温|下雨|降雨|温度|空气质量|空气|湿度|台风|紫外线|穿衣|附近|周边|离我最近|本地新闻|本地热点|哪里有|哪家)',
);

final RegExp _explicitPlacePattern = RegExp(
  r'(北京|上海|深圳|广州|杭州|成都|重庆|西安|苏州|南京|天津|武汉|长沙|郑州|青岛|宁波|无锡|厦门|福州|合肥|济南|沈阳|大连|昆明|南宁|贵阳|乌鲁木齐|哈尔滨|长春|石家庄|太原|南昌|海口|兰州|呼和浩特|银川|西宁|香港|澳门|台北|[\u4e00-\u9fa5]{2,12}(市|区|县|省))',
);

/// 播报决策。提到顶层 pure function 便于单测覆盖矩阵。
///
/// 优先级（高 → 低）：
/// 1. 会话级静音（`sessionMute == muted`）：永远不播
/// 2. 全局模式 `silent`：永远不播
/// 3. 全局模式 `always`：只要有承载面（compactCard / drawer）就播
/// 4. 全局模式 `shortOnly`：只在 compactCard 上播
/// 5. 全局模式 `auto`（默认）：
///    - compactCard → 播
///    - drawer → 看入口：drawerVoice / quickVoice 播；drawerText 不播
///    - none → 不播
bool decideAutoSpeak({
  required AssistantEntrySource entrySource,
  required AssistantReplySurface surface,
  required TtsPlaybackMode mode,
  required AssistantSessionMute sessionMute,
}) {
  if (sessionMute == AssistantSessionMute.muted) return false;
  switch (mode) {
    case TtsPlaybackMode.silent:
      return false;
    case TtsPlaybackMode.always:
      return surface != AssistantReplySurface.none;
    case TtsPlaybackMode.shortOnly:
      return surface == AssistantReplySurface.compactCard;
    case TtsPlaybackMode.auto:
      switch (surface) {
        case AssistantReplySurface.compactCard:
          return true;
        case AssistantReplySurface.drawer:
          return entrySource == AssistantEntrySource.drawerVoice ||
              entrySource == AssistantEntrySource.quickVoice;
        case AssistantReplySurface.none:
          return false;
      }
  }
}

String _labelForToolCall(String name) {
  switch (name) {
    case 'get_user_location':
      return '正在获取当前位置';
  }
  return '正在调用 $name';
}

/// 是否注册了本地写入类工具。W3b 接入写入工具时把工具名加进列表。
/// 当前阶段仅由 controller 用来判断「写入意图却没工具」时是否要在 progress 里
/// 给用户一句"写入能力还没接入"的提示，**不影响路由分支**。
const Set<String> _kLocalWriteToolNames = <String>{
  'create_task',
  'update_task',
  'delete_task',
  'create_schedule',
  'update_schedule',
  'delete_schedule',
  'create_reminder',
  'update_reminder',
  'delete_reminder',
};

bool _hasLocalWriteTool(ToolRegistry registry) {
  for (final String name in _kLocalWriteToolNames) {
    if (registry.find(name) != null) return true;
  }
  return false;
}

String _userFacingErrorMessage(Object error) {
  if (error is DoubaoResponsesException) {
    return error.message;
  }
  if (error is DoubaoChatException) {
    return error.message;
  }
  if (error is XunfeiTtsException) {
    return error.message;
  }
  return error.toString();
}
