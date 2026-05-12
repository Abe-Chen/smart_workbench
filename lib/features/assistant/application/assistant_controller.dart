import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_providers.dart';
import '../../../core/identity/device_id.dart';
import '../../../core/location/location_repository.dart';
import '../../../core/notifications/local_notification_service.dart';
import '../../../core/utils/calendar_utils.dart';
import '../../../core/voice/pcm_stream_recorder.dart';
import '../../../core/voice/voice_providers.dart';
import '../../task/application/task_providers.dart';
import '../../task/domain/task.dart';
import '../data/doubao_chat_client.dart';
import '../data/doubao_responses_client.dart';
import '../data/xunfei_asr_client.dart';
import '../data/tts_facade.dart';
import '../data/volc_tts_client.dart';
import '../data/xunfei_tts_client.dart';
import '../domain/chinese_filler_stripper.dart';
import '../presentation/widgets/answer_cards/answer_card_models.dart';
import '../domain/assistant_execution_mode.dart';
import '../../settings/application/app_settings_controller.dart';
import '../../settings/domain/app_settings.dart';
import '../domain/assistant_confirm_preview.dart';
import '../domain/assistant_intent.dart';
import '../domain/assistant_message.dart';
import '../domain/assistant_proactive_suggestion.dart';
import '../domain/assistant_result_card.dart';
import '../domain/assistant_slots.dart';
import '../domain/assistant_speech_text.dart';
import '../domain/assistant_tool.dart';
import '../domain/tool_call.dart';
import '../prompts/system_prompt.dart';
import 'assistant_copywriter.dart';
import 'assistant_request_router.dart';
import 'assistant_state.dart';
import 'assistant_surface_router.dart';
import 'tool_registry.dart';

export 'assistant_surface_router.dart' show AssistantEntrySource;

const int _kMaxToolRounds = 4;
const Duration _kFollowUpWindow = Duration(seconds: 5);
const Duration _kCompletionUndoWindow = Duration(seconds: 5);
const Duration _kRecentWriteContextWindow = Duration(minutes: 5);

/// 本地音频能量探测阈值（PCM16 RMS 归一化值）。
/// 只用于判断“用户已开口，等待倒计时可以停止”，不直接提交业务指令。
const double _kSpeechRmsThreshold = 0.004;

/// 连续 ≥ 此帧数（每帧 40ms）能量超阈值，才判定"用户开口"。
/// 防抖：避免一次环境噪声尖峰误触发。
const int _kSpeechHoldFrames = 2;

/// 长按持续录音模式下用更宽松的 vad_eos，避免用户停顿想词被讯飞截断。
const int _kPressToTalkVadEosMs = 8000;

/// 不同对话上下文下的开麦等待时长 + 讯飞 vad_eos。
/// 详见 docs/voice_endpointing_strategy.md。
class _ListenTiming {
  const _ListenTiming({required this.openMicWait, required this.vadEosMs});
  final Duration openMicWait;
  final int vadEosMs;
}

_ListenTiming _listenTimingFor(_VoiceContinuationTrigger trigger) {
  switch (trigger) {
    case _VoiceContinuationTrigger.missingWriteSlots:
    case _VoiceContinuationTrigger.tripPlanning:
      return const _ListenTiming(
        openMicWait: Duration(seconds: 18),
        vadEosMs: 5000,
      );
    case _VoiceContinuationTrigger.confirm:
    case _VoiceContinuationTrigger.pendingTaskChoice:
      return const _ListenTiming(
        openMicWait: Duration(seconds: 10),
        vadEosMs: 2500,
      );
    case _VoiceContinuationTrigger.proactiveSuggestion:
      return const _ListenTiming(
        openMicWait: Duration(seconds: 12),
        vadEosMs: 3000,
      );
    case _VoiceContinuationTrigger.none:
      return const _ListenTiming(
        openMicWait: Duration(seconds: 12),
        vadEosMs: 2800,
      );
  }
}

enum _PendingConfirmInputAction { confirm, cancel, unknown }

enum _VoiceContinuationTrigger {
  none,
  confirm,
  missingWriteSlots,
  pendingTaskChoice,
  tripPlanning,
  proactiveSuggestion,
}

class AssistantController extends Notifier<AssistantUiState> {
  static const AssistantCopywriter _copywriter = AssistantCopywriter();

  StreamSubscription<dynamic>? _streamSub;
  bool _aborted = false;
  CancelToken? _publicCancelToken;
  Completer<void>? _publicRunCompleter;
  Timer? _publicElapsedTicker;
  Timer? _publicFirstEventTimer;
  Timer? _publicStallTimer;
  Timer? _publicHardTimeoutTimer;
  bool _publicReceivedFirstEvent = false;
  bool _publicStartedOutput = false;
  AssistantExecutionMode? _lastPublicMode;
  AssistantExecutionMode? _activePublicMode;
  String? _activePublicUserText;
  bool _activePublicContinuePublicContext = false;
  bool _activePublicSummaryOnly = false;

  PcmStreamRecorder? _recorder;
  XunfeiAsrClient? _asrClient;
  StreamSubscription<Uint8List>? _recorderSub;
  StreamSubscription<AsrEvent>? _asrSub;
  bool _autoSendOnFinal = true;
  AssistantEntrySource _listeningSource = AssistantEntrySource.drawerVoice;
  Timer? _openMicTimeoutTimer;
  Timer? _openMicTicker;
  bool _heardSpeechInCurrentOpenMic = false;
  ValueListenable<double>? _audioLevelListenable;
  VoidCallback? _audioLevelListener;
  int _consecutiveLoudFrames = 0;
  Timer? _voiceEchoHideTimer;
  _VoiceContinuationTrigger _nextStartListeningTrigger =
      _VoiceContinuationTrigger.none;
  Timer? _followUpExpireTimer;
  Timer? _followUpTicker;
  int _voiceContinuationGeneration = 0;

  AssistantEntrySource _lastEntrySource = AssistantEntrySource.drawerText;
  String? _lastPublicResponseId;
  AssistantIntent? _activeLocalIntent;
  _RecentConfirmedTask? _lastConfirmedTask;
  _PendingTaskChoice? _pendingTaskChoice;
  _TripPlanningFrame? _pendingTripPlanningFrame;
  bool _voiceContinuationAllowedForCurrentTurn = false;

  @override
  AssistantUiState build() {
    ref.onDispose(() {
      _aborted = true;
      _streamSub?.cancel();
      _cancelActivePublicRequest();
      _stopPublicProgressTracking();
      _cancelOpenMicWait();
      _cancelFollowUpWindow();
      _cancelVoiceContinuation();
      _cancelVoiceEchoHide();
      _teardownVoice();
    });
    return AssistantUiState.initial();
  }

  void openDrawer({AssistantDrawerScrollTarget? scrollTarget}) {
    _cancelFollowUpWindow();
    final AssistantDrawerScrollTarget target =
        scrollTarget ??
        (state.pendingConfirm != null
            ? AssistantDrawerScrollTarget.pendingConfirm
            : AssistantDrawerScrollTarget.latestMessage);
    state = state.copyWith(
      drawerOpen: true,
      replySurface: AssistantReplySurface.drawer,
      surfaceState: AssistantSurfaceState.drawerOpen,
      drawerOpenRequestId: state.drawerOpenRequestId + 1,
      drawerScrollTarget: target,
      clearError: true,
      clearAnswerCard: true,
    );
  }

  void closeDrawer() {
    state = state.copyWith(
      drawerOpen: false,
      surfaceState: AssistantSurfaceState.none,
      drawerScrollTarget: AssistantDrawerScrollTarget.none,
    );
  }

  void toggleDrawer() {
    if (state.drawerOpen) {
      closeDrawer();
    } else {
      openDrawer();
    }
  }

  bool _shouldUseDrawerSurface(AssistantEntrySource source) {
    return const AssistantSurfaceRouter().shouldUseDrawer(
      entrySource: source,
      drawerOpen: state.drawerOpen,
    );
  }

  Future<void> sendUserMessage(
    String text, {
    AssistantEntrySource source = AssistantEntrySource.drawerText,
    bool allowVoiceContinuation = false,
  }) async {
    // 入口统一剥离前导/后置语气词（"嗯，明天 3 点开会" → "明天 3 点开会"），
    // 让所有下游消费（历史展示、router 判断、模型输入）都拿到干净文本。
    // 全是 filler 时（如用户只说"嗯"）保留原文，让上层判定为单字 confirm 等。
    final String original = text.trim();
    if (original.isEmpty) return;
    final String stripped = stripChineseFillers(original).trim();
    final String trimmed = stripped.isEmpty ? original : stripped;
    _cancelVoiceContinuation();
    _voiceContinuationAllowedForCurrentTurn =
        allowVoiceContinuation && source != AssistantEntrySource.drawerText;
    if (state.stage == AssistantStage.think ||
        state.stage == AssistantStage.answer) {
      return;
    }
    _markVoiceEchoProcessingFor(trimmed);
    if (isAssistantFullReadoutRequest(trimmed)) {
      await replayLatestAssistantReply(full: true);
      return;
    }
    if (state.pendingConfirm != null) {
      await _handlePendingConfirmInput(trimmed, source: source);
      return;
    }
    _cancelFollowUpWindow();
    _lastEntrySource = source;
    if (state.proactiveSuggestion != null) {
      final AssistantProactiveSuggestion suggestion =
          state.proactiveSuggestion!;
      if (_isProactiveSuggestionDismissInput(trimmed)) {
        _beginLocalTaskTurn(trimmed, source: source, status: '正在收起建议');
        state = state.copyWith(clearProactiveSuggestion: true);
        _finishLocalWriteText('好，有需要再叫我。');
        return;
      }
      final AssistantProactiveAction? action = _matchProactiveSuggestionAction(
        suggestion,
        trimmed,
      );
      if (action != null) {
        state = state.copyWith(clearProactiveSuggestion: true);
        if (action.dismissOnly) {
          _beginLocalTaskTurn(trimmed, source: source, status: '正在收起建议');
          _finishLocalWriteText('好，有需要再叫我。');
          return;
        }
        final String prompt = action.prompt?.trim() ?? '';
        if (prompt.isNotEmpty) {
          await sendUserMessage(
            prompt,
            source: source,
            allowVoiceContinuation: allowVoiceContinuation,
          );
          return;
        }
      }
      state = state.copyWith(clearProactiveSuggestion: true);
    }
    if (_isConversationCloseInput(trimmed) &&
        state.pendingWriteDraft == null &&
        _pendingTaskChoice == null &&
        _pendingTripPlanningFrame == null) {
      _beginLocalTaskTurn(trimmed, source: source, status: '正在结束对话');
      _finishLocalWriteText('好，有需要再叫我。');
      return;
    }
    if (state.pendingWriteDraft != null) {
      await _handlePendingWriteDraftInput(trimmed, source: source);
      return;
    }
    if (await _tryHandlePendingTaskChoiceInput(trimmed, source: source)) {
      return;
    }
    final AssistantRequestPlan requestPlan = AssistantRequestRouter.planFor(
      text: trimmed,
      hasPublicContext:
          _lastPublicResponseId != null &&
          _lastPublicResponseId!.trim().isNotEmpty,
      lastPublicMode: _lastPublicMode,
    );
    if (await _tryHandlePendingTripPlanningInput(
      trimmed,
      requestPlan: requestPlan,
      source: source,
    )) {
      return;
    }
    if (await _tryHandleContextualTripPlanningInput(
      trimmed,
      requestPlan: requestPlan,
      source: source,
    )) {
      return;
    }
    _activeLocalIntent = requestPlan.route == AssistantRequestRoute.localTools
        ? requestPlan.intent
        : null;

    if (await _tryHandleDeterministicTaskCommand(
      trimmed,
      requestPlan: requestPlan,
      source: source,
    )) {
      return;
    }

    if (_shouldHandleCreateWriteDraft(requestPlan, trimmed)) {
      await _handleNewWriteDraftInput(
        trimmed,
        requestPlan: requestPlan,
        source: source,
      );
      return;
    }

    if (await _tryStartTripPlanningFrame(
      trimmed,
      requestPlan: requestPlan,
      source: source,
    )) {
      return;
    }

    final AssistantMessage userMsg = AssistantMessage(
      role: AssistantRole.user,
      content: trimmed,
    );
    final AssistantMessage placeholder = AssistantMessage(
      role: AssistantRole.assistant,
      content: '',
      streaming: true,
    );
    final AssistantVoiceEchoState? voiceEcho = _voiceEchoForTaskStart(
      trimmed,
      status: '正在理解',
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
      surfaceState: state.drawerOpen
          ? AssistantSurfaceState.drawerOpen
          : AssistantSurfaceState.none,
      clearAnswerCard: true,
      clearError: true,
      clearErrorState: true,
      voiceEcho: voiceEcho,
      progress: AssistantProgressState(
        mode: requestPlan.mode,
        phase: AssistantProgressPhase.routing,
        status: '正在理解你的问题',
        statusOrigin: AssistantProgressOrigin.uxHint,
        steps: initialSteps,
        startedAtMillis: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    _aborted = false;
    try {
      switch (requestPlan.route) {
        case AssistantRequestRoute.publicResponses:
          await _runPublicResponse(
            trimmed,
            continuePublicContext: requestPlan.continuePublicContext,
            mode: requestPlan.mode,
          );
          break;
        case AssistantRequestRoute.localTools:
          await _runConversationLoop();
          break;
      }
    } catch (e) {
      final String message = _userFacingErrorMessage(e);
      _replaceTrailingAssistant(content: '出错了：$message', streaming: false);
      _showAssistantError(message);
    }
  }

  Future<void> _handlePendingConfirmInput(
    String text, {
    required AssistantEntrySource source,
  }) async {
    _lastEntrySource = source;
    final AssistantPendingConfirm? pending = state.pendingConfirm;
    if (pending == null) {
      return;
    }
    final _PendingConfirmInputAction action = _parsePendingConfirmInput(text);
    if (action == _PendingConfirmInputAction.unknown &&
        await _tryUpdatePendingConfirmReminder(text, pending, source: source)) {
      return;
    }
    if (!pending.resumeConversationAfterConfirm) {
      _appendUserMessage(text);
    }
    switch (action) {
      case _PendingConfirmInputAction.confirm:
        await confirmPendingTool();
        break;
      case _PendingConfirmInputAction.cancel:
        await cancelPendingTool();
        break;
      case _PendingConfirmInputAction.unknown:
        if (pending.resumeConversationAfterConfirm) {
          _restorePendingConfirmSurface(
            pending: pending,
            source: source,
            error: _copywriter.pendingConfirmUnknown(pending),
          );
        } else {
          _appendAssistantPlaceholder();
          _finishLocalWriteText(
            _copywriter.pendingConfirmUnknown(pending),
            voiceContinuation: _VoiceContinuationTrigger.confirm,
          );
          state = state.copyWith(stage: AssistantStage.confirm);
        }
        break;
    }
  }

  Future<bool> _tryUpdatePendingConfirmReminder(
    String text,
    AssistantPendingConfirm pending, {
    required AssistantEntrySource source,
  }) async {
    if (pending.toolCall.name != 'create_task' &&
        pending.toolCall.name != 'update_task') {
      return false;
    }
    final TaskReminderKey? reminderKey = _parseReminderFollowUp(text);
    if (reminderKey == null) {
      return false;
    }

    final ToolRegistry registry = ref.read(toolRegistryProvider);
    final AssistantTool? tool = registry.find(pending.toolCall.name);
    if (tool == null) {
      return false;
    }

    final Map<String, dynamic> args = Map<String, dynamic>.from(
      pending.toolCall.argumentsAsMap(),
    );
    args['reminder_key'] = reminderKey.name;
    final ToolCall nextCall = pending.toolCall.copyWith(
      argumentsJson: jsonEncode(args),
    );
    final AssistantConfirmPreview? preview = await tool.buildConfirmPreview(
      args,
    );
    if (preview == null) {
      return false;
    }

    if (!pending.resumeConversationAfterConfirm) {
      _appendUserMessage(text);
    }
    _appendAssistantPlaceholder();
    final String title =
        _rowValueFromPreview(preview, '标题') ??
        _rowValueFromPreview(pending.preview, '标题') ??
        '这项安排';
    _replaceTrailingAssistant(
      content: _copywriter.readyToChangeReminder(
        title: title,
        reminderLabel: _reminderShortLabel(reminderKey),
        removeReminder: reminderKey == TaskReminderKey.none,
      ),
      streaming: false,
    );
    _restorePendingConfirmSurface(
      pending: AssistantPendingConfirm(
        toolCall: nextCall,
        preview: preview,
        resumeConversationAfterConfirm: pending.resumeConversationAfterConfirm,
      ),
      source: source,
      progress: const AssistantProgressState(
        mode: AssistantExecutionMode.local,
        phase: AssistantProgressPhase.awaitingConfirm,
        status: '等你确认',
        statusOrigin: AssistantProgressOrigin.uxHint,
      ),
    );
    _maybeStartVoiceContinuation(
      _latestAssistantPrompt(fallback: preview.title),
      trigger: _VoiceContinuationTrigger.confirm,
    );
    return true;
  }

  void _restorePendingConfirmSurface({
    required AssistantPendingConfirm pending,
    required AssistantEntrySource source,
    AssistantProgressState? progress,
    String? error,
  }) {
    final bool useDrawer = _shouldUseDrawerSurface(source);
    final bool useFullscreenAnswer = !useDrawer;
    final bool openingDrawer = useDrawer && !state.drawerOpen;
    state = state.copyWith(
      stage: AssistantStage.confirm,
      drawerOpen: useDrawer,
      replySurface: useDrawer
          ? AssistantReplySurface.drawer
          : AssistantReplySurface.none,
      surfaceState: useFullscreenAnswer
          ? AssistantSurfaceState.fullscreenAnswer
          : AssistantSurfaceState.drawerOpen,
      drawerOpenRequestId: openingDrawer
          ? state.drawerOpenRequestId + 1
          : state.drawerOpenRequestId,
      drawerScrollTarget: useDrawer
          ? AssistantDrawerScrollTarget.pendingConfirm
          : state.drawerScrollTarget,
      answerCardKind: useFullscreenAnswer ? AnswerCardKind.confirm : null,
      answerCardText: useFullscreenAnswer ? pending.preview.title : null,
      clearAnswerCard: !useFullscreenAnswer,
      pendingConfirm: pending,
      progress: progress,
      error: error,
      listenPartialText: '',
      listenWindowRemainingMs: 0,
      clearListenError: true,
    );
  }

  Future<bool> _tryHandleDeterministicTaskCommand(
    String text, {
    required AssistantRequestPlan requestPlan,
    required AssistantEntrySource source,
  }) async {
    _pendingTaskChoice = null;
    final TaskReminderKey? reminderFollowUp = _parseReminderFollowUp(text);
    if (reminderFollowUp != null &&
        await _tryHandleRecentTaskReminderFollowUp(
          text,
          reminderKey: reminderFollowUp,
          source: source,
        )) {
      return true;
    }

    if (_isTaskDeleteRequest(text)) {
      await _handleDeterministicTaskDelete(text, source: source);
      return true;
    }
    if (_isTaskTimeUpdateRequest(text)) {
      await _handleDeterministicTaskTimeUpdate(text, source: source);
      return true;
    }
    if (requestPlan.intent == AssistantIntent.localDataQuery &&
        _isTaskQueryRequest(text)) {
      await _handleDeterministicTaskQuery(text, source: source);
      return true;
    }
    if (!_nonCreateWritePattern.hasMatch(text) &&
        _looksLikeImplicitTimedScheduleCreate(text)) {
      await _handleNewWriteDraftInput(
        text,
        requestPlan: requestPlan,
        source: source,
      );
      return true;
    }
    return false;
  }

  Future<bool> _tryHandlePendingTaskChoiceInput(
    String text, {
    required AssistantEntrySource source,
  }) async {
    final _PendingTaskChoice? pending = _pendingTaskChoice;
    if (pending == null || !pending.isFresh) {
      _pendingTaskChoice = null;
      return false;
    }

    if (_isCancelOrCloseInput(text)) {
      _pendingTaskChoice = null;
      _beginLocalTaskTurn(text, source: source, status: '正在结束选择');
      _finishLocalWriteText('好，这次先不处理。');
      return true;
    }

    final int? selectedIndex = _parseChoiceIndex(text);
    if (selectedIndex == null) {
      if (_looksLikeChoiceReply(text)) {
        _beginLocalTaskTurn(text, source: source, status: '正在确认选择');
        _finishLocalWriteText(
          _copywriter.choiceReplyHint(),
          voiceContinuation: _VoiceContinuationTrigger.pendingTaskChoice,
        );
        return true;
      }
      _pendingTaskChoice = null;
      return false;
    }

    if (selectedIndex < 0 || selectedIndex >= pending.candidates.length) {
      _beginLocalTaskTurn(text, source: source, status: '正在确认选择');
      _finishLocalWriteText(
        _copywriter.choiceOutOfRange(pending.candidates.length),
        voiceContinuation: _VoiceContinuationTrigger.pendingTaskChoice,
      );
      return true;
    }

    _pendingTaskChoice = null;
    final _TaskCommandCandidate candidate = pending.candidates[selectedIndex];
    _beginLocalTaskTurn(text, source: source, status: '正在整理确认信息');
    await _enterConfirmForPendingTaskChoice(pending, candidate);
    return true;
  }

  Future<void> _handleDeterministicTaskQuery(
    String text, {
    required AssistantEntrySource source,
  }) async {
    _beginLocalTaskTurn(text, source: source, status: '正在查询本地安排');
    final Map<String, dynamic>? result = await _queryTasksForText(text);
    _finishLocalWriteText(_copywriter.queryTasksResult(result));
  }

  Future<void> _handleDeterministicTaskTimeUpdate(
    String text, {
    required AssistantEntrySource source,
  }) async {
    _beginLocalTaskTurn(text, source: source, status: '正在查找要修改的安排');
    final DateTime date = _extractWriteDate(text) ?? _todayDate();
    final List<_TimeMention> times = _extractTimeMentions(text);
    if (times.isEmpty) {
      _finishLocalWriteText('你想把它改到几点？可以说“改成明天下午 4 点”。');
      return;
    }

    final _TimeMention? oldTime = times.length >= 2 ? times.first : null;
    final _TimeMention newTime = times.last;
    final _TaskCandidateSelection selection = await _selectTaskCandidate(
      text: text,
      date: date,
      timeCandidates: oldTime?.candidates,
    );
    if (selection.matches.length > 1) {
      _pendingTaskChoice = _PendingTaskChoice.updateTime(
        candidates: selection.matches,
        newTime: newTime,
        date: date,
      );
      _finishLocalWriteText(
        _candidateSelectionMessage(
          selection,
          date,
          actionText: '改哪一条',
          timeCandidates: oldTime?.candidates,
        ),
        voiceContinuation: _VoiceContinuationTrigger.pendingTaskChoice,
      );
      return;
    }
    if (!selection.hasSingleMatch) {
      final List<_TaskCommandCandidate> fallbackCandidates =
          _fallbackChoiceCandidates(selection);
      _pendingTaskChoice = fallbackCandidates.isEmpty
          ? null
          : _PendingTaskChoice.updateTime(
              candidates: fallbackCandidates,
              newTime: newTime,
              date: date,
            );
      _finishLocalWriteText(
        _candidateSelectionMessage(
          selection,
          date,
          actionText: '改哪一条',
          timeCandidates: oldTime?.candidates,
        ),
        voiceContinuation: fallbackCandidates.isEmpty
            ? _VoiceContinuationTrigger.none
            : _VoiceContinuationTrigger.pendingTaskChoice,
      );
      return;
    }

    _pendingTaskChoice = null;
    final _TaskCommandCandidate candidate = selection.matches.single;
    final int newStart = _resolveNewTimeMinutes(
      newTime,
      candidate.startMinutes,
    );
    final int duration = candidate.durationMinutes ?? 60;
    final Map<String, dynamic> args = <String, dynamic>{
      'task_id': candidate.id,
      'is_all_day': false,
      'start_time_minutes': newStart,
      'end_time_minutes': (newStart + duration).clamp(0, 1440),
    };
    await _enterConfirmForDeterministicTool(
      toolName: 'update_task',
      args: args,
      message: _copywriter.readyToUpdateTime(
        title: candidate.title,
        date: date,
        currentStartMinutes: candidate.startMinutes,
        currentTimeLabel: candidate.timeLabel,
        newStartMinutes: newStart,
      ),
    );
  }

  Future<void> _handleDeterministicTaskDelete(
    String text, {
    required AssistantEntrySource source,
  }) async {
    _beginLocalTaskTurn(text, source: source, status: '正在查找要删除的安排');
    final DateTime date = _extractWriteDate(text) ?? _todayDate();
    final List<_TimeMention> times = _extractTimeMentions(text);
    final _TaskCandidateSelection selection = await _selectTaskCandidate(
      text: text,
      date: date,
      timeCandidates: times.isEmpty ? null : times.first.candidates,
    );
    if (selection.matches.length > 1) {
      _pendingTaskChoice = _PendingTaskChoice.delete(
        candidates: selection.matches,
        date: date,
      );
      _finishLocalWriteText(
        _candidateSelectionMessage(
          selection,
          date,
          actionText: '删哪一条',
          timeCandidates: times.isEmpty ? null : times.first.candidates,
        ),
        voiceContinuation: _VoiceContinuationTrigger.pendingTaskChoice,
      );
      return;
    }
    if (!selection.hasSingleMatch) {
      final List<_TaskCommandCandidate> fallbackCandidates =
          _fallbackChoiceCandidates(selection);
      _pendingTaskChoice = fallbackCandidates.isEmpty
          ? null
          : _PendingTaskChoice.delete(
              candidates: fallbackCandidates,
              date: date,
            );
      _finishLocalWriteText(
        _candidateSelectionMessage(
          selection,
          date,
          actionText: '删哪一条',
          timeCandidates: times.isEmpty ? null : times.first.candidates,
        ),
        voiceContinuation: fallbackCandidates.isEmpty
            ? _VoiceContinuationTrigger.none
            : _VoiceContinuationTrigger.pendingTaskChoice,
      );
      return;
    }

    _pendingTaskChoice = null;
    final _TaskCommandCandidate candidate = selection.matches.single;
    await _enterConfirmForDeterministicTool(
      toolName: 'delete_task',
      args: <String, dynamic>{'task_id': candidate.id},
      message: _copywriter.readyToDelete(
        title: candidate.title,
        date: date,
        currentStartMinutes: candidate.startMinutes,
        currentTimeLabel: candidate.timeLabel,
      ),
    );
  }

  Future<bool> _tryHandleRecentTaskReminderFollowUp(
    String text, {
    required TaskReminderKey reminderKey,
    required AssistantEntrySource source,
  }) async {
    final _RecentConfirmedTask? recent = _lastConfirmedTask;
    if (recent == null || !recent.isFresh) {
      return false;
    }
    _beginLocalTaskTurn(text, source: source, status: '正在整理提醒设置');
    await _enterConfirmForDeterministicTool(
      toolName: 'update_task',
      args: <String, dynamic>{
        'task_id': recent.id,
        'reminder_key': reminderKey.name,
      },
      message: _copywriter.readyToChangeReminder(
        title: recent.title,
        reminderLabel: _reminderShortLabel(reminderKey),
        removeReminder: reminderKey == TaskReminderKey.none,
      ),
    );
    return true;
  }

  Future<Map<String, dynamic>?> _queryTasksForText(String text) async {
    final DateTime date = _extractWriteDate(text) ?? _todayDate();
    return _queryTasksForDate(date);
  }

  Future<Map<String, dynamic>?> _queryTasksForDate(DateTime date) async {
    final AssistantTool? tool = ref
        .read(toolRegistryProvider)
        .find('query_tasks');
    if (tool == null) {
      return <String, dynamic>{'ok': false, 'reason': '本地查询工具不可用'};
    }
    final String result = await tool.call(<String, dynamic>{
      'start_date': _formatToolDate(date),
      'end_date': _formatToolDate(date),
    });
    return _tryDecodeJsonMap(result);
  }

  Future<_TaskCandidateSelection> _selectTaskCandidate({
    required String text,
    required DateTime date,
    required List<int>? timeCandidates,
  }) async {
    final Map<String, dynamic>? result = await _queryTasksForDate(date);
    if (result?['ok'] != true) {
      return _TaskCandidateSelection.queryFailed(result);
    }
    final List<_TaskCommandCandidate> candidates = _taskCandidatesFromResult(
      result,
    );
    final String titleHint = _extractTaskReferenceHint(text);
    final List<_ScoredTaskCandidate> scored = <_ScoredTaskCandidate>[];
    for (final _TaskCommandCandidate candidate in candidates) {
      final int score = _scoreTaskCandidate(
        candidate,
        titleHint: titleHint,
        text: text,
        timeCandidates: timeCandidates,
      );
      if (score > 0) {
        scored.add(_ScoredTaskCandidate(candidate, score));
      }
    }
    scored.sort(
      (_ScoredTaskCandidate a, _ScoredTaskCandidate b) =>
          b.score.compareTo(a.score),
    );
    if (scored.isEmpty) {
      return _TaskCandidateSelection.noMatch(candidates);
    }
    final int topScore = scored.first.score;
    final List<_TaskCommandCandidate> matches = scored
        .where((_ScoredTaskCandidate item) => item.score == topScore)
        .map((_ScoredTaskCandidate item) => item.candidate)
        .toList();
    return _TaskCandidateSelection.matches(matches, candidates);
  }

  int _scoreTaskCandidate(
    _TaskCommandCandidate candidate, {
    required String titleHint,
    required String text,
    required List<int>? timeCandidates,
  }) {
    int score = 0;
    if (timeCandidates != null && timeCandidates.isNotEmpty) {
      if (!_matchesAnyCandidateTime(candidate, timeCandidates)) {
        return -1;
      }
      score += 8;
    }
    if (titleHint.isNotEmpty) {
      final String normalizedTitle = _normalizeTaskText(candidate.title);
      final String normalizedHint = _normalizeTaskText(titleHint);
      if (normalizedTitle == normalizedHint) {
        score += 8;
      } else if (normalizedTitle.contains(normalizedHint) ||
          normalizedHint.contains(normalizedTitle)) {
        score += 5;
      } else if (_isGenericMeetingHint(normalizedHint) &&
          _looksLikeMeetingTitle(normalizedTitle)) {
        score += 3;
      }
    } else if (timeCandidates != null && timeCandidates.isNotEmpty) {
      score += 1;
    }
    if (text.contains('会议') && _looksLikeMeetingTitle(candidate.title)) {
      score += 1;
    }
    return score;
  }

  bool _matchesAnyCandidateTime(
    _TaskCommandCandidate candidate,
    List<int> timeCandidates,
  ) {
    final int? start = candidate.startMinutes;
    if (start == null) {
      return false;
    }
    for (final int target in timeCandidates) {
      if ((start - target).abs() <= 15) {
        return true;
      }
    }
    return false;
  }

  List<_TaskCommandCandidate> _taskCandidatesFromResult(
    Map<String, dynamic>? result,
  ) {
    final Object? raw = result?['tasks'];
    if (raw is! List) {
      return const <_TaskCommandCandidate>[];
    }
    final List<_TaskCommandCandidate> candidates = <_TaskCommandCandidate>[];
    for (final Object? item in raw) {
      if (item is! Map) continue;
      final Map<String, dynamic> map = item.map<String, dynamic>(
        (dynamic key, dynamic value) =>
            MapEntry<String, dynamic>(key.toString(), value),
      );
      final int? id = _parseInt(map['id']);
      final String title = (map['title'] as Object?)?.toString().trim() ?? '';
      if (id == null || title.isEmpty) continue;
      final String timeLabel = (map['time'] as Object?)?.toString() ?? '';
      final (int?, int?) minutes = _parseCandidateTimeRange(timeLabel);
      candidates.add(
        _TaskCommandCandidate(
          id: id,
          title: title,
          timeLabel: timeLabel,
          startMinutes: minutes.$1,
          endMinutes: minutes.$2,
        ),
      );
    }
    return candidates;
  }

  List<_TaskCommandCandidate> _fallbackChoiceCandidates(
    _TaskCandidateSelection selection,
  ) {
    if (selection.queryError != null || selection.allCandidates.isEmpty) {
      return const <_TaskCommandCandidate>[];
    }
    return selection.allCandidates.take(5).toList(growable: false);
  }

  String _candidateSelectionMessage(
    _TaskCandidateSelection selection,
    DateTime date, {
    required String actionText,
    required List<int>? timeCandidates,
  }) {
    if (selection.queryError != null) {
      final String reason =
          (selection.queryError?['reason'] as Object?)?.toString() ?? '查询失败';
      return '这次没查到本地安排：$reason。你可以稍后再试。';
    }
    final String day = _dateLabel(date);
    if (selection.matches.length > 1) {
      final String when = _selectionWhenLabel(date, timeCandidates);
      return '$when有几条都像你说的日程，你要$actionText？\n${_candidateListText(selection.matches)}';
    }
    if (selection.allCandidates.isEmpty) {
      return '我没看到$day有安排。你可以确认一下日期或时间。';
    }
    return '我没看到完全匹配的那条。$day已有这些安排，你看是哪一条？\n${_candidateListText(selection.allCandidates)}';
  }

  String _selectionWhenLabel(DateTime date, List<int>? timeCandidates) {
    final String day = _dateLabel(date);
    if (timeCandidates == null || timeCandidates.isEmpty) {
      return day;
    }
    final int minutes = timeCandidates.length == 1
        ? timeCandidates.single
        : timeCandidates.last;
    return '$day${_timeLabel(minutes)}附近';
  }

  String _candidateListText(List<_TaskCommandCandidate> candidates) {
    final Iterable<String>
    rows = candidates.take(5).toList().asMap().entries.map((
      MapEntry<int, _TaskCommandCandidate> entry,
    ) {
      final _TaskCommandCandidate candidate = entry.value;
      final String time = candidate.timeLabel.trim();
      return '${entry.key + 1}. ${time.isEmpty || time == '无时间' ? '' : '$time '}${candidate.title}';
    });
    return rows.join('\n');
  }

  Future<void> _enterConfirmForDeterministicTool({
    required String toolName,
    required Map<String, dynamic> args,
    required String message,
  }) async {
    final AssistantTool? tool = ref.read(toolRegistryProvider).find(toolName);
    if (tool == null) {
      _finishLocalWriteText('这次没法处理：本地能力暂时不可用。');
      return;
    }
    final AssistantConfirmPreview? preview = await tool.buildConfirmPreview(
      args,
    );
    if (preview == null) {
      _finishLocalWriteText('这次没识别清楚，我先不做。你可以换个说法再试。');
      return;
    }
    final ToolCall call = ToolCall(
      id: 'app_${toolName}_${DateTime.now().microsecondsSinceEpoch}',
      name: toolName,
      argumentsJson: jsonEncode(args),
    );
    _replaceTrailingAssistant(content: message, streaming: false);
    _enterConfirmMode(call, preview, resumeConversationAfterConfirm: false);
  }

  Future<void> _enterConfirmForPendingTaskChoice(
    _PendingTaskChoice pending,
    _TaskCommandCandidate candidate,
  ) async {
    switch (pending.kind) {
      case _PendingTaskChoiceKind.updateTime:
        final _TimeMention newTime = pending.newTime!;
        final int newStart = _resolveNewTimeMinutes(
          newTime,
          candidate.startMinutes,
        );
        final int duration = candidate.durationMinutes ?? 60;
        await _enterConfirmForDeterministicTool(
          toolName: 'update_task',
          args: <String, dynamic>{
            'task_id': candidate.id,
            'is_all_day': false,
            'start_time_minutes': newStart,
            'end_time_minutes': (newStart + duration).clamp(0, 1440),
          },
          message: _copywriter.readyToUpdateTime(
            title: candidate.title,
            date: pending.date,
            currentStartMinutes: candidate.startMinutes,
            currentTimeLabel: candidate.timeLabel,
            newStartMinutes: newStart,
          ),
        );
        break;
      case _PendingTaskChoiceKind.delete:
        await _enterConfirmForDeterministicTool(
          toolName: 'delete_task',
          args: <String, dynamic>{'task_id': candidate.id},
          message: _copywriter.readyToDelete(
            title: candidate.title,
            date: pending.date,
            currentStartMinutes: candidate.startMinutes,
            currentTimeLabel: candidate.timeLabel,
          ),
        );
        break;
    }
  }

  _PendingConfirmInputAction _parsePendingConfirmInput(String text) {
    final String s = _normalizeForIntentMatch(text);
    if (s.isEmpty) {
      return _PendingConfirmInputAction.unknown;
    }
    // 1. 显式否定 + confirm 词（"不确认" / "不可以" / "不行"），算 cancel
    if (_negatedConfirmPattern.hasMatch(s)) {
      return _PendingConfirmInputAction.cancel;
    }
    // 2. cancel / close 优先（"算了吧" / "就这样" / "不用了"）
    if (_cancelInputPattern.hasMatch(s) ||
        _conversationCloseInputPattern.hasMatch(s)) {
      return _PendingConfirmInputAction.cancel;
    }
    // 3. confirm 单字白名单（完全相等才算，避免"好烦"误判）
    if (_singleConfirmPattern.hasMatch(s)) {
      return _PendingConfirmInputAction.confirm;
    }
    // 4. confirm 多字 contains（"嗯，确认" → strip → "确认" → 命中）
    if (_multiConfirmPattern.hasMatch(s)) {
      return _PendingConfirmInputAction.confirm;
    }
    return _PendingConfirmInputAction.unknown;
  }

  Future<void> _handleNewWriteDraftInput(
    String text, {
    required AssistantRequestPlan requestPlan,
    required AssistantEntrySource source,
  }) async {
    _beginLocalWriteTurn(text, source: source);
    final AssistantPendingWriteDraft draft = _draftFromText(
      text,
      kind: requestPlan.intent == AssistantIntent.reminderWrite
          ? AssistantWriteDraftKind.reminder
          : AssistantWriteDraftKind.schedule,
    );
    await _finishDraftOrAskForMore(draft);
  }

  Future<bool> _tryStartTripPlanningFrame(
    String text, {
    required AssistantRequestPlan requestPlan,
    required AssistantEntrySource source,
  }) async {
    if (!_shouldUseTripPlanningFrame(text, requestPlan)) {
      return false;
    }
    final _TripPlanningFrame frame = _tripFrameFromSlots(
      requestPlan.slots,
      originalText: text,
    );
    await _continueTripPlanningFrame(
      frame,
      text: text,
      source: source,
      justMerged: false,
    );
    return true;
  }

  Future<bool> _tryHandlePendingTripPlanningInput(
    String text, {
    required AssistantRequestPlan requestPlan,
    required AssistantEntrySource source,
  }) async {
    final _TripPlanningFrame? current = _pendingTripPlanningFrame;
    if (current == null) {
      return false;
    }
    if (_isTripPlanningFrameExpired(current)) {
      _pendingTripPlanningFrame = null;
      return false;
    }

    final String normalized = text.trim();
    if (_isTripPlanningCancelInput(normalized)) {
      _pendingTripPlanningFrame = null;
      _beginLocalTaskTurn(text, source: source, status: '正在取消路线规划');
      _finishLocalWriteText('好，刚才的路线规划先不继续了。');
      return true;
    }

    final _TripPlanningFrame currentTurn = current.nextFollowUpTurn();
    if (_resumeTripPlanningPattern.hasMatch(normalized)) {
      _pendingTripPlanningFrame = currentTurn;
      _beginLocalTaskTurn(text, source: source, status: '正在继续路线规划');
      _finishLocalWriteText(
        _missingTripPlanningPrompt(currentTurn),
        voiceContinuation: _VoiceContinuationTrigger.tripPlanning,
      );
      return true;
    }

    if (_shouldInterruptTripPlanningFrame(text, requestPlan)) {
      return false;
    }

    final _TripPlanningFrame incoming = _tripFrameFromSlots(
      requestPlan.slots,
      originalText: text,
    );
    final _TripPlanningFrame merged = _mergeTripPlanningFrame(
      currentTurn,
      incoming,
      rawText: text,
    );
    if (merged.sameSlotsAs(currentTurn)) {
      if (_shouldInterruptTripPlanningFrame(text, requestPlan)) {
        return false;
      }
      _pendingTripPlanningFrame = currentTurn;
      _beginLocalTaskTurn(text, source: source, status: '正在补充路线信息');
      _finishLocalWriteText(
        _missingTripPlanningPrompt(currentTurn),
        voiceContinuation: _VoiceContinuationTrigger.tripPlanning,
      );
      return true;
    }

    await _continueTripPlanningFrame(
      merged,
      text: text,
      source: source,
      justMerged: true,
    );
    return true;
  }

  Future<bool> _tryHandleContextualTripPlanningInput(
    String text, {
    required AssistantRequestPlan requestPlan,
    required AssistantEntrySource source,
  }) async {
    if (_pendingTripPlanningFrame != null) {
      return false;
    }
    final _TripPlanningFrame? base = _recentTripPlanningFrameFromMessages();
    if (base == null) {
      return false;
    }
    if (_isTripPlanningCancelInput(text)) {
      _pendingTripPlanningFrame = null;
      _beginLocalTaskTurn(text, source: source, status: '正在取消路线规划');
      _finishLocalWriteText('好，刚才的路线规划先不继续了。');
      return true;
    }
    final _TripPlanningFrame incoming = _tripFrameFromSlots(
      requestPlan.slots,
      originalText: text,
    );
    if (!_shouldTreatAsTripPlanningSupplement(text, requestPlan, incoming)) {
      return false;
    }
    final _TripPlanningFrame merged = _mergeTripPlanningFrame(
      base,
      incoming,
      rawText: text,
    );
    if (merged.sameSlotsAs(base)) {
      return false;
    }
    await _continueTripPlanningFrame(
      merged,
      text: text,
      source: source,
      justMerged: true,
    );
    return true;
  }

  bool _shouldUseTripPlanningFrame(
    String text,
    AssistantRequestPlan requestPlan,
  ) {
    return requestPlan.intent == AssistantIntent.tripPlanning &&
        _routePlanningFramePattern.hasMatch(text);
  }

  bool _shouldInterruptTripPlanningFrame(
    String text,
    AssistantRequestPlan requestPlan,
  ) {
    if (requestPlan.intent.isLocalWrite ||
        requestPlan.intent == AssistantIntent.localDataQuery ||
        requestPlan.intent == AssistantIntent.localUiAction) {
      _pendingTripPlanningFrame = null;
      return true;
    }
    if (requestPlan.intent == AssistantIntent.realtimeInfo ||
        requestPlan.intent == AssistantIntent.localSearch) {
      _pendingTripPlanningFrame = null;
      return true;
    }
    if (requestPlan.intent == AssistantIntent.tripPlanning ||
        _routePlanningFramePattern.hasMatch(text)) {
      return false;
    }
    final bool interrupted =
        _explicitQuestionPattern.hasMatch(text) ||
        _publicInterruptionPattern.hasMatch(text);
    if (interrupted) {
      _pendingTripPlanningFrame = null;
    }
    return interrupted;
  }

  bool _shouldTreatAsTripPlanningSupplement(
    String text,
    AssistantRequestPlan requestPlan,
    _TripPlanningFrame incoming,
  ) {
    if (requestPlan.intent.isLocalWrite ||
        requestPlan.intent == AssistantIntent.localDataQuery ||
        requestPlan.intent == AssistantIntent.localUiAction ||
        requestPlan.intent == AssistantIntent.realtimeInfo ||
        requestPlan.intent == AssistantIntent.localSearch) {
      return false;
    }
    if (_explicitQuestionPattern.hasMatch(text) &&
        !_routePlanningFramePattern.hasMatch(text)) {
      return false;
    }
    return incoming.origin != null ||
        incoming.destination != null ||
        incoming.transport != null ||
        _extractLooseTripPlace(text) != null;
  }

  _TripPlanningFrame _tripFrameFromSlots(
    AssistantSlots slots, {
    required String originalText,
  }) {
    return _TripPlanningFrame(
      date: _cleanTripSlot(slots.date),
      origin: _cleanTripSlot(slots.origin),
      destination: _cleanTripSlot(slots.destination),
      duration: _cleanTripSlot(slots.duration),
      transport: _normalizeTransport(_cleanTripSlot(slots.transport)),
      destinationHint: _extractDestinationHint(originalText),
    );
  }

  _TripPlanningFrame? _recentTripPlanningFrameFromMessages() {
    AssistantMessage? lastAssistant;
    AssistantMessage? lastUser;
    for (final AssistantMessage message in state.messages.reversed) {
      if (lastAssistant == null &&
          message.role == AssistantRole.assistant &&
          !message.streaming &&
          message.content.trim().isNotEmpty) {
        lastAssistant = message;
        continue;
      }
      if (lastAssistant != null &&
          message.role == AssistantRole.user &&
          message.content.trim().isNotEmpty) {
        lastUser = message;
        break;
      }
    }
    if (lastAssistant == null || lastUser == null) {
      return null;
    }
    if (DateTime.now().difference(lastAssistant.createdAt) >
        _tripPlanningFrameTtl) {
      return null;
    }
    if (!_assistantAskedForTripPlanningSlots(lastAssistant.content)) {
      return null;
    }
    final String lastUserText = lastUser.content.trim();
    final AssistantSlots slots = AssistantSlots.from(lastUserText);
    final _TripPlanningFrame frame = _tripFrameFromSlots(
      slots,
      originalText: lastUserText,
    );
    if (frame.date == null &&
        frame.origin == null &&
        frame.destination == null &&
        frame.transport == null &&
        frame.destinationHint == null) {
      return null;
    }
    return frame;
  }

  bool _assistantAskedForTripPlanningSlots(String text) {
    final bool asksForInfo = RegExp(
      r'(提供|告诉|补充|确认|需要|方便说|请说|麻烦|还差|还需要|说一下|填一下|给我)',
    ).hasMatch(text);
    if (!asksForInfo && !RegExp(r'[？?]').hasMatch(text)) {
      return false;
    }
    int slotGroups = 0;
    if (RegExp(r'(出发地|出发地点|从哪里出发|从哪儿出发)').hasMatch(text)) {
      slotGroups += 1;
    }
    if (RegExp(r'(目的地|具体地址|客户现场|到哪里|去哪|去哪里)').hasMatch(text)) {
      slotGroups += 1;
    }
    if (RegExp(r'(出行方式|怎么过去|怎么去|怎么走|导航|自驾|公共交通|打车|地铁|公交)').hasMatch(text)) {
      slotGroups += 1;
    }
    return slotGroups >= 2;
  }

  _TripPlanningFrame _mergeTripPlanningFrame(
    _TripPlanningFrame current,
    _TripPlanningFrame incoming, {
    required String rawText,
  }) {
    final String? loosePlace = _extractLooseTripPlace(rawText);
    String? origin = incoming.origin ?? current.origin;
    String? destination = incoming.destination ?? current.destination;
    final bool hasConcreteDestination = !_isGenericTripDestination(
      current.destination,
    );

    if (incoming.destination != null &&
        !_isGenericTripDestination(incoming.destination)) {
      destination = incoming.destination;
    } else if (loosePlace != null) {
      if (current.needsDestination) {
        destination = loosePlace;
      } else if (current.origin == null && hasConcreteDestination) {
        origin = loosePlace;
      }
    }

    if (incoming.origin != null) {
      origin = incoming.origin;
    }

    return current.copyWith(
      date: incoming.date,
      origin: origin,
      destination: destination,
      duration: incoming.duration,
      transport: incoming.transport,
      destinationHint: incoming.destinationHint,
    );
  }

  Future<void> _continueTripPlanningFrame(
    _TripPlanningFrame frame, {
    required String text,
    required AssistantEntrySource source,
    required bool justMerged,
  }) async {
    if (!frame.isReady) {
      _pendingTripPlanningFrame = frame;
      _beginLocalTaskTurn(text, source: source, status: '正在补充路线信息');
      _finishLocalWriteText(
        _missingTripPlanningPrompt(frame),
        voiceContinuation: _VoiceContinuationTrigger.tripPlanning,
      );
      return;
    }

    _pendingTripPlanningFrame = null;
    await _runPublicTaskFrameTurn(
      displayText: text,
      publicQuery: _tripPlanningPublicQuery(frame),
      source: source,
      mode: AssistantExecutionMode.publicRealtime,
    );
  }

  Future<void> _runPublicTaskFrameTurn({
    required String displayText,
    required String publicQuery,
    required AssistantEntrySource source,
    required AssistantExecutionMode mode,
  }) async {
    _cancelFollowUpWindow();
    _lastEntrySource = source;
    _aborted = false;
    final bool useDrawer = _shouldUseDrawerSurface(source);
    final AssistantMessage userMsg = AssistantMessage(
      role: AssistantRole.user,
      content: displayText,
    );
    final AssistantMessage placeholder = AssistantMessage(
      role: AssistantRole.assistant,
      content: '',
      streaming: true,
    );
    state = state.copyWith(
      drawerOpen: useDrawer,
      stage: AssistantStage.think,
      messages: <AssistantMessage>[...state.messages, userMsg, placeholder],
      replySurface: useDrawer
          ? AssistantReplySurface.drawer
          : AssistantReplySurface.none,
      surfaceState: useDrawer
          ? AssistantSurfaceState.drawerOpen
          : AssistantSurfaceState.none,
      drawerOpenRequestId: useDrawer && !state.drawerOpen
          ? state.drawerOpenRequestId + 1
          : state.drawerOpenRequestId,
      drawerScrollTarget: useDrawer && !state.drawerOpen
          ? AssistantDrawerScrollTarget.latestMessage
          : state.drawerScrollTarget,
      clearAnswerCard: true,
      clearError: true,
      clearErrorState: true,
      progress: AssistantProgressState(
        mode: mode,
        phase: AssistantProgressPhase.preparingContext,
        status: '正在整理路线信息',
        statusOrigin: AssistantProgressOrigin.uxHint,
        steps: const <String>['已补全路线信息'],
        startedAtMillis: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    await _runPublicResponse(
      publicQuery,
      continuePublicContext: false,
      mode: mode,
    );
  }

  String _missingTripPlanningPrompt(_TripPlanningFrame frame) {
    final List<String> missing = <String>[];
    if (frame.origin == null) {
      missing.add('从哪里出发');
    }
    if (frame.needsDestination) {
      final String target = frame.destinationHint ?? frame.destination ?? '目的地';
      missing.add(target == '目的地' ? '要去哪里' : '$target具体到哪里');
    }
    if (frame.transport == null) {
      missing.add('打算怎么过去');
    }

    final String known = _tripPlanningKnownPrefix(frame);
    if (missing.isEmpty) {
      return '$known我来给你规划路线。';
    }
    if (known.isNotEmpty) {
      return '$known${_joinChineseQuestions(missing)}？';
    }
    return '可以，我先帮你规划。${_joinChineseQuestions(missing)}？';
  }

  String _tripPlanningKnownPrefix(_TripPlanningFrame frame) {
    final List<String> parts = <String>[];
    if (frame.date != null) {
      parts.add(frame.date!);
    }
    if (frame.origin != null) {
      parts.add('从${frame.origin}出发');
    }
    if (frame.destination != null) {
      parts.add('去${frame.destination}');
    } else if (frame.destinationHint != null) {
      parts.add('去${frame.destinationHint}');
    }
    if (frame.transport != null) {
      parts.add(frame.transport!);
    }
    if (parts.isEmpty) {
      return '';
    }
    return '好，我记下${parts.join('，')}。';
  }

  String _joinChineseQuestions(List<String> items) {
    if (items.length == 1) {
      return items.single;
    }
    if (items.length == 2) {
      return '${items.first}，以及${items.last}';
    }
    return '${items.sublist(0, items.length - 1).join('，')}，以及${items.last}';
  }

  String _tripPlanningPublicQuery(_TripPlanningFrame frame) {
    final String date = frame.date ?? '用户未指定';
    final String duration = frame.duration ?? '用户未指定';
    return '请帮用户规划路线。\n'
        '日期：$date\n'
        '出发地：${frame.origin}\n'
        '目的地：${frame.destination}\n'
        '出行方式：${frame.transport}\n'
        '行程时长：$duration\n'
        '要求：先给结论，再给关键路线、预计耗时、注意事项；如果实时路况或班次无法确认，要明确说明。';
  }

  bool _isTripPlanningFrameExpired(_TripPlanningFrame frame) {
    if (DateTime.now().millisecondsSinceEpoch - frame.createdAtMillis >
        _tripPlanningFrameTtl.inMilliseconds) {
      return true;
    }
    return frame.followUpTurns >= _tripPlanningFrameMaxFollowUps;
  }

  bool _isTripPlanningCancelInput(String text) {
    final String compact = text.replaceAll(RegExp(r'[，。！？,.!?\s]+'), '');
    return _isCancelOrCloseInput(compact) ||
        _tripPlanningCancelPattern.hasMatch(compact);
  }

  String? _cleanTripSlot(String? value) {
    final String cleaned =
        value
            ?.replaceAll(RegExp(r'[，。！？,.!?\s]+$'), '')
            .replaceAll(RegExp(r'^到\s*'), '')
            .trim() ??
        '';
    return cleaned.isEmpty ? null : cleaned;
  }

  String? _normalizeTransport(String? value) {
    if (value == null) {
      return null;
    }
    return switch (value) {
      '驾车' || '自驾' => '开车',
      '出租车' || '网约车' => '打车',
      _ => value,
    };
  }

  String? _extractDestinationHint(String text) {
    if (text.contains('客户现场')) {
      return '客户现场';
    }
    if (text.contains('公司')) {
      return '公司';
    }
    return null;
  }

  String? _extractLooseTripPlace(String text) {
    final String normalized = text.trim();
    if (_isTripPlanningCancelInput(normalized)) {
      return null;
    }
    if (RegExp(r'^从').hasMatch(normalized)) {
      return null;
    }
    final RegExpMatch? explicit = RegExp(
      r'(?:目的地是|客户现场在|地址是|到|去)\s*([一-龥A-Za-z0-9]{2,18})',
    ).firstMatch(normalized);
    if (explicit != null) {
      final String? raw = explicit.group(1);
      final String cleaned = _cleanLooseTripPlace(raw);
      return cleaned.isEmpty ? null : cleaned;
    }
    if (_looksLikeShortTripPlace(normalized)) {
      return _cleanLooseTripPlace(normalized);
    }
    return null;
  }

  String _cleanLooseTripPlace(String? raw) {
    if (raw == null) {
      return '';
    }
    return raw
        .replaceAll(RegExp(r'(开车|驾车|自驾|打车|坐车|地铁|公交|公共交通|步行|骑车).*'), '')
        .replaceAll(RegExp(r'[，。！？,.!?\s]+'), '')
        .trim();
  }

  bool _looksLikeShortTripPlace(String text) {
    final String compact = text.replaceAll(RegExp(r'[，。！？,.!?\s]+'), '');
    if (compact.length < 2 || compact.length > 18) {
      return false;
    }
    if (_tripPlanningControlReplyPattern.hasMatch(compact)) {
      return false;
    }
    if (_routePlanningFramePattern.hasMatch(compact) ||
        _explicitQuestionPattern.hasMatch(compact) ||
        _publicInterruptionPattern.hasMatch(compact)) {
      return false;
    }
    return RegExp(r'^[一-龥A-Za-z0-9]+$').hasMatch(compact);
  }

  Future<void> _handlePendingWriteDraftInput(
    String text, {
    required AssistantEntrySource source,
  }) async {
    final AssistantPendingWriteDraft current = state.pendingWriteDraft!;
    if (_isCancelOrCloseInput(text)) {
      _beginLocalWriteTurn(text, source: source);
      state = state.copyWith(clearPendingWriteDraft: true);
      _finishLocalWriteText(_copywriter.createCancelled(current.kind));
      return;
    }
    if (_shouldInterruptPendingWriteDraft(text, current)) {
      state = state.copyWith(clearPendingWriteDraft: true);
      await sendUserMessage(text, source: source);
      return;
    }
    _beginLocalWriteTurn(text, source: source);
    final AssistantPendingWriteDraft incoming = _draftFromText(
      text,
      kind: current.kind,
    );
    final AssistantPendingWriteDraft merged = _mergeDraft(current, incoming);
    await _finishDraftOrAskForMore(merged);
  }

  bool _shouldHandleCreateWriteDraft(
    AssistantRequestPlan requestPlan,
    String text,
  ) {
    if (!requestPlan.intent.isLocalWrite) {
      return false;
    }
    if (_nonCreateWritePattern.hasMatch(text)) {
      return false;
    }
    if (requestPlan.intent == AssistantIntent.reminderWrite) {
      return _reminderCreatePattern.hasMatch(text);
    }
    return _scheduleCreatePattern.hasMatch(text) ||
        _looksLikeImplicitTimedScheduleCreate(text);
  }

  AssistantPendingWriteDraft _draftFromText(
    String text, {
    required AssistantWriteDraftKind kind,
  }) {
    return AssistantPendingWriteDraft(
      kind: kind,
      title: _extractWriteTitle(text, kind: kind),
      startDate: _extractWriteDate(text),
      startTimeMinutes: _extractWriteTimeMinutes(text),
    );
  }

  AssistantPendingWriteDraft _mergeDraft(
    AssistantPendingWriteDraft current,
    AssistantPendingWriteDraft incoming,
  ) {
    return current.copyWith(
      title: incoming.title,
      startDate: incoming.startDate,
      startTimeMinutes: incoming.startTimeMinutes,
    );
  }

  bool _shouldInterruptPendingWriteDraft(
    String text,
    AssistantPendingWriteDraft current,
  ) {
    final AssistantPendingWriteDraft incoming = _draftFromText(
      text,
      kind: current.kind,
    );
    final bool suppliesMissingField =
        (current.title == null &&
            incoming.title != null &&
            incoming.title!.trim().isNotEmpty) ||
        (current.startDate == null && incoming.startDate != null) ||
        (current.startTimeMinutes == null && incoming.startTimeMinutes != null);
    final AssistantRequestPlan plan = AssistantRequestRouter.planFor(
      text: text,
      hasPublicContext:
          _lastPublicResponseId != null &&
          _lastPublicResponseId!.trim().isNotEmpty,
      lastPublicMode: _lastPublicMode,
    );
    if (plan.intent == AssistantIntent.realtimeInfo ||
        plan.intent == AssistantIntent.localSearch ||
        plan.intent == AssistantIntent.tripPlanning ||
        plan.intent == AssistantIntent.localDataQuery ||
        plan.intent == AssistantIntent.localUiAction) {
      return true;
    }
    if (plan.intent.isLocalWrite &&
        ((current.kind == AssistantWriteDraftKind.schedule &&
                plan.intent != AssistantIntent.scheduleWrite) ||
            (current.kind == AssistantWriteDraftKind.reminder &&
                plan.intent != AssistantIntent.reminderWrite))) {
      return true;
    }
    if (_explicitQuestionPattern.hasMatch(text) && !suppliesMissingField) {
      return true;
    }
    if (_publicInterruptionPattern.hasMatch(text)) {
      return true;
    }
    return false;
  }

  Future<void> _finishDraftOrAskForMore(
    AssistantPendingWriteDraft draft,
  ) async {
    if (!draft.isComplete) {
      state = state.copyWith(pendingWriteDraft: draft);
      _finishLocalWriteText(
        _missingDraftPrompt(draft),
        voiceContinuation: _VoiceContinuationTrigger.missingWriteSlots,
      );
      return;
    }

    state = state.copyWith(clearPendingWriteDraft: true);
    await _enterConfirmForDraft(draft);
  }

  String _missingDraftPrompt(AssistantPendingWriteDraft draft) {
    return _copywriter.missingWriteDraft(draft);
  }

  Future<void> _enterConfirmForDraft(AssistantPendingWriteDraft draft) async {
    final ToolRegistry registry = ref.read(toolRegistryProvider);
    final AssistantTool? tool = registry.find('create_task');
    if (tool == null) {
      _finishLocalWriteText(_copywriter.cannotCreate(draft.kind));
      return;
    }

    final Map<String, dynamic> args = _toolArgsFromDraft(draft);
    final ToolCall call = ToolCall(
      id: 'app_create_${DateTime.now().microsecondsSinceEpoch}',
      name: 'create_task',
      argumentsJson: jsonEncode(args),
    );
    final AssistantConfirmPreview? preview = await tool.buildConfirmPreview(
      args,
    );
    if (preview == null) {
      _finishLocalWriteText(_copywriter.unclearCreate(draft.kind));
      return;
    }
    _replaceTrailingAssistant(
      content: _copywriter.readyToConfirm(draft),
      streaming: false,
    );
    _enterConfirmMode(call, preview, resumeConversationAfterConfirm: false);
  }

  Map<String, dynamic> _toolArgsFromDraft(AssistantPendingWriteDraft draft) {
    final int startTimeMinutes = draft.startTimeMinutes!;
    return <String, dynamic>{
      'title': draft.title!.trim(),
      'start_date': _formatToolDate(draft.startDate!),
      'is_all_day': false,
      'start_time_minutes': startTimeMinutes,
      'end_time_minutes': (startTimeMinutes + 60).clamp(0, 1440),
      'reminder_key': draft.kind == AssistantWriteDraftKind.reminder
          ? 'atStart'
          : 'none',
      'repeat_key': 'none',
    };
  }

  void _beginLocalWriteTurn(
    String text, {
    required AssistantEntrySource source,
  }) {
    _beginLocalTaskTurn(text, source: source, status: '正在整理创建信息');
  }

  void _beginLocalTaskTurn(
    String text, {
    required AssistantEntrySource source,
    required String status,
  }) {
    _cancelFollowUpWindow();
    _lastEntrySource = source;
    _aborted = false;
    final AssistantMessage userMsg = AssistantMessage(
      role: AssistantRole.user,
      content: text,
    );
    final AssistantMessage placeholder = AssistantMessage(
      role: AssistantRole.assistant,
      content: '',
      streaming: true,
    );
    final bool useDrawer = _shouldUseDrawerSurface(source);
    state = state.copyWith(
      drawerOpen: useDrawer,
      stage: AssistantStage.think,
      messages: <AssistantMessage>[...state.messages, userMsg, placeholder],
      replySurface: useDrawer
          ? AssistantReplySurface.drawer
          : AssistantReplySurface.none,
      surfaceState: useDrawer
          ? AssistantSurfaceState.drawerOpen
          : AssistantSurfaceState.none,
      drawerOpenRequestId: useDrawer && !state.drawerOpen
          ? state.drawerOpenRequestId + 1
          : state.drawerOpenRequestId,
      drawerScrollTarget: useDrawer && !state.drawerOpen
          ? AssistantDrawerScrollTarget.latestMessage
          : state.drawerScrollTarget,
      clearAnswerCard: true,
      clearError: true,
      clearErrorState: true,
      voiceEcho: _voiceEchoForTaskStart(text, status: status),
      progress: AssistantProgressState(
        mode: AssistantExecutionMode.local,
        phase: AssistantProgressPhase.routing,
        status: status,
        statusOrigin: AssistantProgressOrigin.uxHint,
      ),
    );
  }

  AssistantVoiceEchoState? _voiceEchoForTaskStart(
    String text, {
    required String status,
  }) {
    final String normalized = text.trim();
    if (normalized.isEmpty) {
      return null;
    }
    final AssistantVoiceEchoState current = state.voiceEcho;
    final bool fromVoice =
        current.phase == AssistantVoiceEchoPhase.finalText ||
        current.phase == AssistantVoiceEchoPhase.listening ||
        current.phase == AssistantVoiceEchoPhase.processing;
    if (!fromVoice) {
      return null;
    }
    final String raw = current.rawFinalText.trim().isEmpty
        ? normalized
        : current.rawFinalText.trim();
    final bool cleaned = current.cleaned || raw != normalized;
    return AssistantVoiceEchoState.processing(
      rawFinalText: raw,
      finalText: normalized,
      cleaned: cleaned,
      displayText: '$status：$normalized',
    );
  }

  void _appendUserMessage(String text) {
    state = state.copyWith(
      messages: <AssistantMessage>[
        ...state.messages,
        AssistantMessage(role: AssistantRole.user, content: text),
      ],
    );
  }

  void _finishLocalWriteText(
    String text, {
    _VoiceContinuationTrigger voiceContinuation =
        _VoiceContinuationTrigger.none,
  }) {
    _finishAssistantTurn(text, voiceContinuation: voiceContinuation);
    if (_lastEntrySource != AssistantEntrySource.quickVoice) {
      state = state.copyWith(
        drawerOpen: true,
        replySurface: AssistantReplySurface.drawer,
        surfaceState: AssistantSurfaceState.drawerOpen,
        drawerOpenRequestId: state.drawerOpenRequestId + 1,
        drawerScrollTarget: AssistantDrawerScrollTarget.latestMessage,
        clearAnswerCard: true,
      );
    }
  }

  Future<void> _runPublicResponse(
    String userText, {
    required bool continuePublicContext,
    required AssistantExecutionMode mode,
    bool summaryOnly = false,
  }) async {
    final DoubaoResponsesClient client = ref.read(
      doubaoResponsesClientProvider,
    );
    final bool continuePublic =
        continuePublicContext &&
        _lastPublicResponseId != null &&
        _lastPublicResponseId!.trim().isNotEmpty;
    _activePublicUserText = userText;
    _activePublicContinuePublicContext = continuePublicContext;
    _activePublicMode = mode;
    _activePublicSummaryOnly = summaryOnly;
    _publicReceivedFirstEvent = false;
    _publicStartedOutput = false;
    _publicCancelToken = CancelToken();
    _publicRunCompleter = Completer<void>();
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
    _setProgressState(
      mode: mode,
      phase: AssistantProgressPhase.preparingContext,
      status: '正在准备查询',
      statusOrigin: AssistantProgressOrigin.uxHint,
      detail: null,
      detailOrigin: null,
    );
    _startPublicProgressTracking(mode: mode, summaryOnly: summaryOnly);

    await _streamSub?.cancel();
    final StringBuffer outputBuffer = StringBuffer();
    _streamSub = client
        .streamPublicResponse(
          userText: publicQuery,
          previousResponseId: continuePublic ? _lastPublicResponseId : null,
          mode: mode,
          summaryOnly: summaryOnly,
          cancelToken: _publicCancelToken,
        )
        .listen(
          (PublicResponseEvent event) {
            _handlePublicResponseEvent(
              event,
              mode: mode,
              outputBuffer: outputBuffer,
            );
          },
          onError: (Object err, StackTrace _) {
            if (!_publicRunCompleter!.isCompleted) {
              _publicRunCompleter!.completeError(err);
            }
          },
          onDone: () {
            if (!_publicRunCompleter!.isCompleted) {
              _publicRunCompleter!.complete();
            }
          },
          cancelOnError: true,
        );

    try {
      await _publicRunCompleter!.future;
    } catch (e) {
      if (e is _PublicRunInterruption) {
        _applyPublicRunInterruption(e);
        if (e.restartAsSummary) {
          _appendAssistantPlaceholder();
          await _runPublicResponse(
            _activePublicUserText ?? userText,
            continuePublicContext: _activePublicContinuePublicContext,
            mode: _activePublicMode ?? mode,
            summaryOnly: true,
          );
        }
        return;
      }
      final AssistantErrorState errorState = _publicErrorStateFor(e);
      _replaceTrailingAssistant(
        content: '出错了：${errorState.message}',
        streaming: false,
      );
      _showAssistantError(errorState.message, errorState: errorState);
      return;
    } finally {
      _stopPublicProgressTracking();
      _publicCancelToken = null;
      _publicRunCompleter = null;
      _publicReceivedFirstEvent = false;
      _publicStartedOutput = false;
      _activePublicMode = null;
      _activePublicUserText = null;
      _activePublicContinuePublicContext = false;
      _activePublicSummaryOnly = false;
    }

    if (_aborted) return;
    final String finalText = outputBuffer.toString().trim();
    if (finalText.isEmpty) {
      final AssistantErrorState errorState = _publicErrorStateFor(
        DoubaoResponsesException(
          type: AssistantErrorType.emptyResponse,
          message: '这次没有拿到可展示的结果',
        ),
      );
      _replaceTrailingAssistant(
        content: '出错了：${errorState.message}',
        streaming: false,
      );
      _showAssistantError(errorState.message, errorState: errorState);
      return;
    }
    _lastPublicMode = mode;
    _finishAssistantTurn(finalText);
  }

  void _handlePublicResponseEvent(
    PublicResponseEvent event, {
    required AssistantExecutionMode mode,
    required StringBuffer outputBuffer,
  }) {
    _onPublicProgressEvent();
    if (event is PublicResponseRequestAcceptedEvent) {
      _setProgressState(
        mode: mode,
        phase: AssistantProgressPhase.requestAccepted,
        status: '请求已发出',
        statusOrigin: AssistantProgressOrigin.realEvent,
        requestId: event.responseId,
      );
      return;
    }
    if (event is PublicResponseSearchStartedEvent) {
      _setProgressState(
        mode: mode,
        phase: AssistantProgressPhase.searching,
        status: '正在联网搜索',
        statusOrigin: AssistantProgressOrigin.realEvent,
      );
      return;
    }
    if (event is PublicResponseSearchCompletedEvent) {
      _setProgressState(
        mode: mode,
        phase: AssistantProgressPhase.summarizing,
        status: '已拿到联网结果',
        statusOrigin: AssistantProgressOrigin.realEvent,
        detail: '正在整理回答',
        detailOrigin: AssistantProgressOrigin.uxHint,
      );
      return;
    }
    if (event is PublicResponseTextDeltaEvent) {
      if (!_publicStartedOutput) {
        _publicStartedOutput = true;
        state = state.copyWith(stage: AssistantStage.answer);
        _setProgressState(
          mode: mode,
          phase: AssistantProgressPhase.receiving,
          status: '已开始返回内容',
          statusOrigin: AssistantProgressOrigin.realEvent,
        );
      }
      outputBuffer.write(event.delta);
      _replaceTrailingAssistant(
        content: outputBuffer.toString(),
        streaming: true,
      );
      _refreshPublicProgressHints(mode: mode);
      return;
    }
    if (event is PublicResponseCompletedEvent) {
      if (event.responseId.trim().isNotEmpty) {
        _lastPublicResponseId = event.responseId;
      }
      if (!_publicStartedOutput && event.text.trim().isNotEmpty) {
        _publicStartedOutput = true;
        state = state.copyWith(stage: AssistantStage.answer);
        if (outputBuffer.isEmpty) {
          outputBuffer.write(event.text);
        }
        _replaceTrailingAssistant(content: event.text, streaming: false);
      }
      _setProgressState(
        mode: mode,
        phase: AssistantProgressPhase.completed,
        status: '回答已生成',
        statusOrigin: AssistantProgressOrigin.realEvent,
      );
    }
  }

  void _startPublicProgressTracking({
    required AssistantExecutionMode mode,
    required bool summaryOnly,
  }) {
    _stopPublicProgressTracking();
    final int startedAtMillis = DateTime.now().millisecondsSinceEpoch;
    state = state.copyWith(
      progress: AssistantProgressState(
        mode: mode,
        phase: AssistantProgressPhase.preparingContext,
        status: '正在准备查询',
        statusOrigin: AssistantProgressOrigin.uxHint,
        steps: state.progress.steps,
        startedAtMillis: startedAtMillis,
        elapsedMs: 0,
        hasStartedOutput: false,
      ),
    );
    _publicElapsedTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      _refreshPublicProgressHints(mode: mode, summaryOnly: summaryOnly);
    });
    _publicFirstEventTimer = Timer(_firstEventTimeoutFor(mode), () {
      _interruptPublicRun(
        _PublicRunInterruption.error(
          AssistantErrorState(
            type: AssistantErrorType.firstEventTimeout,
            message: '请求已发出，但还没有开始返回内容',
          ),
        ),
      );
    });
    _publicHardTimeoutTimer = Timer(_hardTimeoutFor(mode), () {
      _interruptPublicRun(
        _PublicRunInterruption.error(
          AssistantErrorState(
            type: AssistantErrorType.streamStalled,
            message: '这次处理时间过长，请稍后再试',
          ),
        ),
      );
    });
  }

  void _onPublicProgressEvent() {
    if (!_publicReceivedFirstEvent) {
      _publicReceivedFirstEvent = true;
      _publicFirstEventTimer?.cancel();
    }
    _publicStallTimer?.cancel();
    _publicStallTimer = Timer(_stallTimeoutFor(_activePublicMode), () {
      _interruptPublicRun(
        _PublicRunInterruption.error(
          AssistantErrorState(
            type: AssistantErrorType.streamStalled,
            message: _publicStartedOutput
                ? '刚才已经开始返回内容，但中途停住了'
                : '查询中途停住了，请稍后再试',
          ),
        ),
      );
    });
  }

  void _refreshPublicProgressHints({
    required AssistantExecutionMode mode,
    bool summaryOnly = false,
  }) {
    final int startedAtMillis =
        state.progress.startedAtMillis ?? DateTime.now().millisecondsSinceEpoch;
    final int elapsedMs =
        DateTime.now().millisecondsSinceEpoch - startedAtMillis;
    String? detail;
    AssistantProgressOrigin? detailOrigin;
    if (!_publicStartedOutput) {
      if (elapsedMs >= _summarySuggestionThresholdFor(mode).inMilliseconds) {
        detail = summaryOnly ? '正在压缩成短结论' : '如果赶时间，可以先要结论';
        detailOrigin = AssistantProgressOrigin.uxHint;
      } else if (elapsedMs >= _softLongWaitHintFor(mode).inMilliseconds) {
        detail = '这类问题通常会慢一些';
        detailOrigin = AssistantProgressOrigin.uxHint;
      }
    }
    state = state.copyWith(
      progress: AssistantProgressState(
        mode: mode,
        phase: state.progress.phase,
        status: state.progress.status,
        statusOrigin: state.progress.statusOrigin,
        detail: detail,
        detailOrigin: detailOrigin,
        steps: state.progress.steps,
        requestId: state.progress.requestId,
        startedAtMillis: startedAtMillis,
        elapsedMs: elapsedMs,
        hasStartedOutput: _publicStartedOutput,
        canStop: _publicStartedOutput,
        canCancelTask: !_publicStartedOutput && mode.supportsCancelTask,
        canAskForSummary:
            !_publicStartedOutput &&
            !summaryOnly &&
            mode.supportsCancelTask &&
            elapsedMs >= _summarySuggestionThresholdFor(mode).inMilliseconds,
      ),
    );
  }

  void _stopPublicProgressTracking() {
    _publicElapsedTicker?.cancel();
    _publicElapsedTicker = null;
    _publicFirstEventTimer?.cancel();
    _publicFirstEventTimer = null;
    _publicStallTimer?.cancel();
    _publicStallTimer = null;
    _publicHardTimeoutTimer?.cancel();
    _publicHardTimeoutTimer = null;
  }

  void _interruptPublicRun(_PublicRunInterruption interruption) {
    if (_publicRunCompleter == null || _publicRunCompleter!.isCompleted) {
      return;
    }
    _publicCancelToken?.cancel(interruption.errorState?.message ?? 'cancelled');
    _streamSub?.cancel();
    _publicRunCompleter!.completeError(interruption);
  }

  void _cancelActivePublicRequest() {
    _publicCancelToken?.cancel('cancelled');
    _streamSub?.cancel();
  }

  void _applyPublicRunInterruption(_PublicRunInterruption interruption) {
    final String currentContent = state.messages.isNotEmpty
        ? state.messages.last.content.trim()
        : '';
    if (interruption.errorState != null) {
      final AssistantErrorState errorState = interruption.errorState!;
      _replaceTrailingAssistant(
        content: '出错了：${errorState.message}',
        streaming: false,
      );
      _showAssistantError(errorState.message, errorState: errorState);
      return;
    }
    if (interruption.keepPartialOutput && currentContent.isNotEmpty) {
      _replaceTrailingAssistant(content: currentContent, streaming: false);
    } else if (interruption.message != null &&
        interruption.message!.isNotEmpty) {
      _replaceTrailingAssistant(
        content: interruption.message!,
        streaming: false,
      );
    } else {
      _removeTrailingAssistantPlaceholder();
    }
    state = state.copyWith(
      stage: AssistantStage.idle,
      clearProgress: true,
      clearError: true,
      clearErrorState: true,
    );
  }

  AssistantErrorState _publicErrorStateFor(Object error) {
    if (error is DoubaoResponsesException) {
      return error.toErrorState();
    }
    if (error is AssistantErrorState) {
      return error;
    }
    return AssistantErrorState(
      type: AssistantErrorType.unknown,
      message: _userFacingErrorMessage(error),
    );
  }

  Duration _firstEventTimeoutFor(AssistantExecutionMode mode) {
    switch (mode) {
      case AssistantExecutionMode.local:
      case AssistantExecutionMode.publicQuick:
        return const Duration(seconds: 8);
      case AssistantExecutionMode.publicRealtime:
        return const Duration(seconds: 12);
      case AssistantExecutionMode.publicDeep:
        return const Duration(seconds: 18);
    }
  }

  Duration _stallTimeoutFor(AssistantExecutionMode? mode) {
    switch (mode) {
      case AssistantExecutionMode.publicDeep:
        return const Duration(seconds: 30);
      case AssistantExecutionMode.publicRealtime:
        return const Duration(seconds: 20);
      case AssistantExecutionMode.local:
      case AssistantExecutionMode.publicQuick:
      case null:
        return const Duration(seconds: 15);
    }
  }

  Duration _softLongWaitHintFor(AssistantExecutionMode mode) {
    switch (mode) {
      case AssistantExecutionMode.local:
      case AssistantExecutionMode.publicQuick:
        return const Duration(seconds: 6);
      case AssistantExecutionMode.publicRealtime:
        return const Duration(seconds: 10);
      case AssistantExecutionMode.publicDeep:
        return const Duration(seconds: 15);
    }
  }

  Duration _summarySuggestionThresholdFor(AssistantExecutionMode mode) {
    switch (mode) {
      case AssistantExecutionMode.local:
      case AssistantExecutionMode.publicQuick:
        return const Duration(days: 1);
      case AssistantExecutionMode.publicRealtime:
        return const Duration(seconds: 10);
      case AssistantExecutionMode.publicDeep:
        return const Duration(seconds: 12);
    }
  }

  Duration _hardTimeoutFor(AssistantExecutionMode mode) {
    switch (mode) {
      case AssistantExecutionMode.local:
      case AssistantExecutionMode.publicQuick:
        return const Duration(seconds: 45);
      case AssistantExecutionMode.publicRealtime:
        return const Duration(seconds: 75);
      case AssistantExecutionMode.publicDeep:
        return const Duration(seconds: 120);
    }
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
        if (_activeLocalIntent?.isLocalWrite == true &&
            _looksLikeLocalWriteSuccessClaim(roundResult.content)) {
          _finishAssistantTurn('我还没真的写进去。你重新说一遍要创建、修改或删除的内容，我会先给你确认卡，确认后再写入。');
          return;
        }
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

      bool enteredConfirm = false;
      for (final ToolCall call in roundResult.toolCalls) {
        if (_aborted) return;
        _setProgressStatus('正在读取本地信息');
        _appendProgressStep(_labelForToolCall(call.name));

        final AssistantTool? tool = registry.find(call.name);
        if (tool == null) {
          _appendToolResult(
            call: call,
            result: '{"ok": false, "reason": "未知工具：${call.name}"}',
          );
          continue;
        }

        if (enteredConfirm) {
          // 已有写入工具进 confirm，后续 calls 全部排队报错（result 仍要写回，
          // 否则下一 round chat 会因 tool_calls 与 tool result 不匹配而报错）。
          _appendToolResult(
            call: call,
            result: '{"ok": false, "reason": "请等当前确认操作完成后再继续"}',
          );
          continue;
        }

        final Map<String, dynamic> args = call.argumentsAsMap();
        AssistantConfirmPreview? preview;
        try {
          preview = await tool.buildConfirmPreview(args);
        } catch (e) {
          preview = AssistantConfirmPreview(
            title: '准备处理 ${call.name}（预览失败）',
            rows: <ConfirmRow>[ConfirmRow(label: '错误', value: '$e')],
          );
        }
        if (_aborted) return;

        if (preview == null) {
          // 非写入或不需要 confirm，直接执行。
          state = state.copyWith(stage: AssistantStage.think);
          String result;
          try {
            result = await tool.call(args);
          } catch (e) {
            result = '{"ok": false, "reason": "$e"}';
          }
          if (_aborted) return;
          _appendToolResult(call: call, result: result);
          if (_shouldFinishReadToolLocally(call.name)) {
            _appendAssistantPlaceholder();
            _finishLocalWriteText(
              _copywriter.queryTasksResult(_tryDecodeJsonMap(result)),
            );
            return;
          }
          if (call.name == 'complete_task') {
            _maybeShowCompletionUndo(call, result);
            _appendAssistantPlaceholder();
            _finishLocalWriteText(
              _copywriter.completedTaskResult(_tryDecodeJsonMap(result)),
            );
            return;
          }
          continue;
        }

        // 写入工具：进 confirm，暂停 loop。
        _enterConfirmMode(call, preview);
        enteredConfirm = true;
      }

      if (enteredConfirm) {
        // 退出 loop，等用户操作。confirmPendingTool / cancelPendingTool 会
        // 触发 _resumeConversationLoop 继续。
        return;
      }

      _setProgressStatus('正在整理工具结果');
      _appendAssistantPlaceholder();
    }

    if (round >= _kMaxToolRounds) {
      _replaceTrailingAssistant(content: '工具调用太多次了，先停下。', streaming: false);
      state = state.copyWith(stage: AssistantStage.idle, clearProgress: true);
    }
  }

  bool _shouldFinishReadToolLocally(String toolName) {
    return toolName == 'query_tasks' &&
        _activeLocalIntent == AssistantIntent.localDataQuery;
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

  // ---------------- 操作确认（写入类工具）----------------

  void _enterConfirmMode(
    ToolCall call,
    AssistantConfirmPreview preview, {
    bool resumeConversationAfterConfirm = true,
  }) {
    final bool useDrawer = _shouldUseDrawerSurface(_lastEntrySource);
    final bool useFullscreenAnswer = !useDrawer;
    state = state.copyWith(
      stage: AssistantStage.confirm,
      drawerOpen: useDrawer,
      replySurface: useFullscreenAnswer
          ? AssistantReplySurface.none
          : AssistantReplySurface.drawer,
      surfaceState: useFullscreenAnswer
          ? AssistantSurfaceState.fullscreenAnswer
          : AssistantSurfaceState.drawerOpen,
      drawerOpenRequestId: useDrawer && !state.drawerOpen
          ? state.drawerOpenRequestId + 1
          : state.drawerOpenRequestId,
      drawerScrollTarget: useFullscreenAnswer
          ? state.drawerScrollTarget
          : AssistantDrawerScrollTarget.pendingConfirm,
      answerCardKind: useFullscreenAnswer ? AnswerCardKind.confirm : null,
      answerCardText: useFullscreenAnswer ? preview.title : null,
      clearAnswerCard: !useFullscreenAnswer,
      pendingConfirm: AssistantPendingConfirm(
        toolCall: call,
        preview: preview,
        resumeConversationAfterConfirm: resumeConversationAfterConfirm,
      ),
      progress: const AssistantProgressState(
        mode: AssistantExecutionMode.local,
        phase: AssistantProgressPhase.awaitingConfirm,
        status: '等你确认',
        statusOrigin: AssistantProgressOrigin.uxHint,
      ),
    );
    _maybeStartVoiceContinuation(
      _latestAssistantPrompt(fallback: preview.title),
      trigger: _VoiceContinuationTrigger.confirm,
    );
  }

  /// 用户在 ConfirmCard 上点"确认"。
  Future<void> confirmPendingTool() async {
    final AssistantPendingConfirm? pending = state.pendingConfirm;
    if (pending == null) return;
    final ToolRegistry registry = ref.read(toolRegistryProvider);
    final AssistantTool? tool = registry.find(pending.toolCall.name);
    if (tool == null) {
      _appendToolResult(
        call: pending.toolCall,
        result: '{"ok": false, "reason": "工具已不可用"}',
      );
      state = state.copyWith(
        clearPendingConfirm: true,
        stage: AssistantStage.idle,
        surfaceState: AssistantSurfaceState.none,
        clearAnswerCard: true,
        clearProgress: true,
        clearVoiceEcho: true,
      );
      return;
    }
    state = state.copyWith(
      stage: AssistantStage.think,
      clearPendingConfirm: true,
      surfaceState: state.drawerOpen
          ? AssistantSurfaceState.drawerOpen
          : AssistantSurfaceState.none,
      clearAnswerCard: true,
      clearVoiceEcho: true,
      progress: const AssistantProgressState(
        mode: AssistantExecutionMode.local,
        phase: AssistantProgressPhase.executing,
        status: '正在处理',
        statusOrigin: AssistantProgressOrigin.uxHint,
      ),
    );
    String result;
    try {
      result = await tool.call(pending.toolCall.argumentsAsMap());
    } catch (e) {
      result = '{"ok": false, "reason": "$e"}';
    }
    if (_aborted) return;
    if (!pending.resumeConversationAfterConfirm) {
      _finishConfirmedDraftResult(pending, result);
      return;
    }
    _appendToolResult(call: pending.toolCall, result: result);
    if (_shouldFinishWriteToolLocally(pending.toolCall.name)) {
      final Map<String, dynamic>? decoded = _tryDecodeJsonMap(result);
      _rememberConfirmedTask(pending, decoded);
      _appendAssistantPlaceholder();
      _finishLocalWriteText(
        _copywriter.confirmedWriteResult(pending: pending, result: decoded),
      );
      _maybeShowProactiveSuggestion(pending, decoded);
      return;
    }
    _appendAssistantPlaceholder();
    await _resumeConversationLoop();
  }

  /// 用户在 ConfirmCard 上点"取消"。
  Future<void> cancelPendingTool() async {
    final AssistantPendingConfirm? pending = state.pendingConfirm;
    if (pending == null) return;
    if (!pending.resumeConversationAfterConfirm) {
      state = state.copyWith(
        stage: AssistantStage.think,
        clearPendingConfirm: true,
        clearPendingWriteDraft: true,
        surfaceState: state.drawerOpen
            ? AssistantSurfaceState.drawerOpen
            : AssistantSurfaceState.none,
        clearAnswerCard: true,
        clearVoiceEcho: true,
        progress: const AssistantProgressState(
          mode: AssistantExecutionMode.local,
          phase: AssistantProgressPhase.cancelled,
          status: '已取消',
          statusOrigin: AssistantProgressOrigin.uxHint,
        ),
      );
      _appendAssistantPlaceholder();
      _finishLocalWriteText(_copywriter.confirmCancelled(pending));
      return;
    }
    _appendToolResult(
      call: pending.toolCall,
      result: '{"ok": false, "reason": "用户取消"}',
    );
    if (_shouldFinishWriteToolLocally(pending.toolCall.name)) {
      state = state.copyWith(
        stage: AssistantStage.think,
        clearPendingConfirm: true,
        surfaceState: state.drawerOpen
            ? AssistantSurfaceState.drawerOpen
            : AssistantSurfaceState.none,
        clearAnswerCard: true,
        clearVoiceEcho: true,
        progress: const AssistantProgressState(
          mode: AssistantExecutionMode.local,
          phase: AssistantProgressPhase.cancelled,
          status: '已取消',
          statusOrigin: AssistantProgressOrigin.uxHint,
        ),
      );
      _appendAssistantPlaceholder();
      _finishLocalWriteText(_copywriter.confirmCancelled(pending));
      return;
    }
    state = state.copyWith(
      stage: AssistantStage.think,
      clearPendingConfirm: true,
      surfaceState: state.drawerOpen
          ? AssistantSurfaceState.drawerOpen
          : AssistantSurfaceState.none,
      clearAnswerCard: true,
      clearVoiceEcho: true,
      progress: const AssistantProgressState(
        mode: AssistantExecutionMode.local,
        phase: AssistantProgressPhase.cancelled,
        status: '已取消，整理回答',
        statusOrigin: AssistantProgressOrigin.uxHint,
      ),
    );
    _appendAssistantPlaceholder();
    await _resumeConversationLoop();
  }

  void _finishConfirmedDraftResult(
    AssistantPendingConfirm pending,
    String result,
  ) {
    final Map<String, dynamic>? decoded = _tryDecodeJsonMap(result);
    _rememberConfirmedTask(pending, decoded);
    final String message = _copywriter.confirmedCreateResult(
      pending: pending,
      result: decoded,
    );
    state = state.copyWith(
      clearPendingConfirm: true,
      clearPendingWriteDraft: true,
      clearVoiceEcho: true,
    );
    _appendAssistantPlaceholder();
    _finishLocalWriteText(message);
    _maybeShowProactiveSuggestion(pending, decoded);
  }

  void _rememberConfirmedTask(
    AssistantPendingConfirm pending,
    Map<String, dynamic>? result,
  ) {
    if (result?['ok'] != true) {
      return;
    }
    if (pending.toolCall.name != 'create_task' &&
        pending.toolCall.name != 'update_task') {
      return;
    }
    final int? id = _parseInt(result?['id']);
    if (id == null) {
      return;
    }
    final String title =
        (result?['title'] as Object?)?.toString().trim() ??
        _rowValueFromPreview(pending.preview, '标题') ??
        '这项安排';
    _lastConfirmedTask = _RecentConfirmedTask(
      id: id,
      title: title,
      updatedAt: DateTime.now(),
    );
  }

  void _maybeShowProactiveSuggestion(
    AssistantPendingConfirm pending,
    Map<String, dynamic>? result,
  ) {
    if (result?['ok'] != true || pending.toolCall.name != 'create_task') {
      state = state.copyWith(clearProactiveSuggestion: true);
      return;
    }

    final Map<String, dynamic> args = pending.toolCall.argumentsAsMap();
    final String title =
        (result?['title'] as Object?)?.toString().trim() ??
        (args['title'] as Object?)?.toString().trim() ??
        _rowValueFromPreview(pending.preview, '标题') ??
        '';
    if (title.isEmpty) {
      state = state.copyWith(clearProactiveSuggestion: true);
      return;
    }

    final DateTime? date = _parseToolDateValue(args['start_date']);
    final String dayLabel = date == null ? '这天' : _dateLabel(date);
    final String reminderKey =
        (args['reminder_key'] as Object?)?.toString().trim() ?? 'none';
    final bool hasReminder =
        reminderKey.isNotEmpty &&
        reminderKey != 'none' &&
        reminderKey != TaskReminderKey.none.name;
    final AssistantProactiveSuggestion? suggestion =
        _buildCreatedTaskSuggestion(
          title: title,
          dayLabel: dayLabel,
          hasReminder: hasReminder,
        );
    // 主动建议触发时，如果抽屉关闭就走顶部 banner（推送形态）；
    // 抽屉打开仍在抽屉内 _ProactiveSuggestionCard 显示（沉浸模式）
    final AssistantSurfaceState? newSurface =
        suggestion != null && !state.drawerOpen
        ? AssistantSurfaceState.topBannerPush
        : null;
    state = state.copyWith(
      proactiveSuggestion: suggestion,
      clearProactiveSuggestion: suggestion == null,
      surfaceState: newSurface,
    );
    if (suggestion != null) {
      final String latest = _latestAssistantPrompt();
      final String prompt = latest.isEmpty
          ? suggestion.message
          : '$latest ${suggestion.message}';
      _maybeStartVoiceContinuation(
        prompt,
        trigger: _VoiceContinuationTrigger.proactiveSuggestion,
      );
    }
  }

  DateTime? _parseToolDateValue(Object? raw) {
    if (raw == null) {
      return null;
    }
    return DateTime.tryParse(raw.toString().trim().replaceAll('/', '-'));
  }

  AssistantProactiveSuggestion? _buildCreatedTaskSuggestion({
    required String title,
    required String dayLabel,
    required bool hasReminder,
  }) {
    final String normalized = _normalizeTaskText(title);
    if (_looksLikeTravelSchedule(normalized)) {
      return _travelSuggestion(
        title: title,
        dayLabel: dayLabel,
        hasReminder: hasReminder,
      );
    }
    if (_looksLikeClientVisitSchedule(normalized)) {
      return _clientVisitSuggestion(
        title: title,
        dayLabel: dayLabel,
        hasReminder: hasReminder,
      );
    }
    if (_looksLikeMedicalSchedule(normalized)) {
      return _checklistSuggestion(
        id: 'medical',
        title: '还可以继续帮你',
        message: '这是就医相关安排，要不要我帮你整理证件和材料清单？',
        actionLabel: '准备清单',
        prompt: '帮我整理$dayLabel「$title」需要带的证件和材料清单',
        hasReminder: hasReminder,
      );
    }
    if (_looksLikeInterviewOrExamSchedule(normalized)) {
      return _checklistSuggestion(
        id: 'prep',
        title: '还可以继续帮你',
        message: '这看起来需要提前准备，要不要我帮你列一份准备清单？',
        actionLabel: '准备清单',
        prompt: '帮我整理$dayLabel「$title」的准备清单',
        hasReminder: hasReminder,
      );
    }
    if (_looksLikeMeetingTitle(title)) {
      return _meetingSuggestion(
        title: title,
        dayLabel: dayLabel,
        hasReminder: hasReminder,
      );
    }
    return null;
  }

  AssistantProactiveSuggestion _travelSuggestion({
    required String title,
    required String dayLabel,
    required bool hasReminder,
  }) {
    final String? destination = _extractDestinationFromScheduleTitle(title);
    final List<AssistantProactiveAction> actions = <AssistantProactiveAction>[
      AssistantProactiveAction(
        id: 'weather',
        kind: AssistantProactiveActionKind.weather,
        label: '查天气',
        prompt: destination == null
            ? '查一下$dayLabel出差目的地天气'
            : '查一下$dayLabel$destination天气',
      ),
      AssistantProactiveAction(
        id: 'trip_plan',
        kind: AssistantProactiveActionKind.tripPlan,
        label: '规划行程',
        prompt: destination == null
            ? '帮我规划一下$dayLabel「$title」的出差行程'
            : '帮我规划一下$dayLabel去$destination的出差行程',
      ),
      if (!hasReminder) _reminderSuggestionAction(),
      _dismissSuggestionAction(),
    ];
    final String target = destination ?? '目的地';
    return AssistantProactiveSuggestion(
      id: 'travel',
      title: '还可以继续帮你',
      message: '这是出差安排，要不要我查一下$target$dayLabel的天气，或者做个简单行程规划？',
      actions: actions,
    );
  }

  AssistantProactiveSuggestion _clientVisitSuggestion({
    required String title,
    required String dayLabel,
    required bool hasReminder,
  }) {
    return AssistantProactiveSuggestion(
      id: 'client_visit',
      title: '还可以继续帮你',
      message: '这是客户相关安排，要不要我顺手整理一份拜访准备清单？',
      actions: <AssistantProactiveAction>[
        AssistantProactiveAction(
          id: 'checklist',
          kind: AssistantProactiveActionKind.checklist,
          label: '准备清单',
          prompt: '帮我整理$dayLabel「$title」的客户拜访准备清单',
        ),
        AssistantProactiveAction(
          id: 'route',
          kind: AssistantProactiveActionKind.route,
          label: '查路线',
          prompt: '帮我规划$dayLabel去客户现场的路线',
        ),
        if (!hasReminder) _reminderSuggestionAction(),
        _dismissSuggestionAction(),
      ],
    );
  }

  AssistantProactiveSuggestion _meetingSuggestion({
    required String title,
    required String dayLabel,
    required bool hasReminder,
  }) {
    return AssistantProactiveSuggestion(
      id: 'meeting',
      title: '还可以继续帮你',
      message: '这是会议安排，要不要我帮你整理一个简短议程？',
      actions: <AssistantProactiveAction>[
        AssistantProactiveAction(
          id: 'agenda',
          kind: AssistantProactiveActionKind.agenda,
          label: '整理议程',
          prompt: '帮我整理$dayLabel「$title」的会议议程',
        ),
        if (!hasReminder) _reminderSuggestionAction(),
        _dismissSuggestionAction(),
      ],
    );
  }

  AssistantProactiveSuggestion _checklistSuggestion({
    required String id,
    required String title,
    required String message,
    required String actionLabel,
    required String prompt,
    required bool hasReminder,
  }) {
    return AssistantProactiveSuggestion(
      id: id,
      title: title,
      message: message,
      actions: <AssistantProactiveAction>[
        AssistantProactiveAction(
          id: 'checklist',
          kind: AssistantProactiveActionKind.checklist,
          label: actionLabel,
          prompt: prompt,
        ),
        if (!hasReminder) _reminderSuggestionAction(),
        _dismissSuggestionAction(),
      ],
    );
  }

  AssistantProactiveAction _reminderSuggestionAction() {
    return const AssistantProactiveAction(
      id: 'reminder',
      kind: AssistantProactiveActionKind.reminder,
      label: '加提醒',
      prompt: '需要提醒',
    );
  }

  AssistantProactiveAction _dismissSuggestionAction() {
    return const AssistantProactiveAction(
      id: 'dismiss',
      kind: AssistantProactiveActionKind.dismiss,
      label: '不用了',
      dismissOnly: true,
    );
  }

  String? _rowValueFromPreview(AssistantConfirmPreview preview, String label) {
    for (final ConfirmRow row in preview.rows) {
      if (row.label == label) {
        return row.value;
      }
    }
    return null;
  }

  bool _shouldFinishWriteToolLocally(String toolName) {
    return toolName == 'create_task' ||
        toolName == 'update_task' ||
        toolName == 'delete_task';
  }

  Map<String, dynamic>? _tryDecodeJsonMap(String text) {
    try {
      final Object? decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {}
    return null;
  }

  /// 由 confirm/cancel 后触发，沿用当前历史继续 chat 循环。
  Future<void> _resumeConversationLoop() async {
    _aborted = false;
    try {
      await _runConversationLoop();
    } catch (e) {
      final String message = _userFacingErrorMessage(e);
      _replaceTrailingAssistant(content: '出错了：$message', streaming: false);
      _showAssistantError(message);
    }
  }

  /// complete_task 成功执行后弹撤销 SnackBar。result 是工具返回的 JSON 字符串。
  void _maybeShowCompletionUndo(ToolCall call, String result) {
    try {
      final Map<String, dynamic> map =
          jsonDecode(result) as Map<String, dynamic>;
      if (map['ok'] != true) return;
      final int? taskId = (map['id'] as num?)?.toInt();
      if (taskId == null) return;
      final String title = (map['title'] as String?) ?? '任务';
      final Object? rawDate = call.argumentsAsMap()['occurrence_date'];
      DateTime occurrence;
      if (rawDate is String && rawDate.isNotEmpty) {
        try {
          occurrence = DateTime.parse(rawDate.replaceAll('/', '-'));
        } catch (_) {
          occurrence = normalizeDate(DateTime.now());
        }
      } else {
        occurrence = normalizeDate(DateTime.now());
      }
      state = state.copyWith(
        completionUndo: AssistantCompletionUndo(
          taskId: taskId,
          occurrenceDate: occurrence,
          title: title,
          expireAtMillis: DateTime.now()
              .add(_kCompletionUndoWindow)
              .millisecondsSinceEpoch,
        ),
      );
    } catch (_) {
      // 解析失败就不弹撤销提示，不影响主流程
    }
  }

  /// 撤销最近一次 complete_task。仅在 [AssistantUiState.completionUndo] 还在
  /// 窗口期内有效。
  Future<void> undoLastCompletion() async {
    final AssistantCompletionUndo? undo = state.completionUndo;
    if (undo == null) return;
    state = state.copyWith(clearCompletionUndo: true);
    try {
      await ref
          .read(taskRepositoryProvider)
          .toggleCompletion(
            taskId: undo.taskId,
            occurrenceDate: undo.occurrenceDate,
            completed: false,
          );
      // 触发看板刷新（所有 task FutureProvider 都 watch 这个 tick）。
      ref.read(taskRefreshTickProvider.notifier).state++;
    } catch (e) {
      state = state.copyWith(ttsError: '撤销失败：$e');
    }
  }

  /// 撤销窗口过期或用户主动 dismiss。
  void dismissCompletionUndo() {
    if (state.completionUndo == null) return;
    state = state.copyWith(clearCompletionUndo: true);
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

  void _removeTrailingAssistantPlaceholder() {
    final List<AssistantMessage> messages = List<AssistantMessage>.from(
      state.messages,
    );
    if (messages.isEmpty) return;
    final AssistantMessage last = messages.last;
    if (last.role != AssistantRole.assistant) return;
    if (!last.streaming && last.content.trim().isNotEmpty) return;
    messages.removeLast();
    state = state.copyWith(messages: messages);
  }

  void clearConversation() {
    _aborted = true;
    if (_activePublicMode != null) {
      _interruptPublicRun(const _PublicRunInterruption.silent());
    } else {
      _streamSub?.cancel();
    }
    _cancelActivePublicRequest();
    _stopPublicProgressTracking();
    _cancelOpenMicWait();
    _cancelFollowUpWindow();
    _cancelVoiceContinuation();
    _cancelVoiceEchoHide();
    _teardownVoice();
    _lastPublicResponseId = null;
    _lastPublicMode = null;
    _activeLocalIntent = null;
    _lastConfirmedTask = null;
    _pendingTaskChoice = null;
    _pendingTripPlanningFrame = null;
    _voiceContinuationAllowedForCurrentTurn = false;
    // sessionMute / pendingWriteDraft / pendingConfirm / completionUndo 都跟随会话生命周期重置。
    final bool keepDrawerOpen = state.drawerOpen;
    state = AssistantUiState.initial().copyWith(
      drawerOpen: keepDrawerOpen,
      surfaceState: keepDrawerOpen
          ? AssistantSurfaceState.drawerOpen
          : AssistantSurfaceState.none,
      clearProgress: true,
      clearTtsError: true,
      clearPendingWriteDraft: true,
      clearPendingConfirm: true,
      clearCompletionUndo: true,
      clearErrorState: true,
    );
  }

  void stopCurrentGeneration() {
    if (_activePublicMode == null || !state.progress.hasStartedOutput) {
      return;
    }
    _interruptPublicRun(
      const _PublicRunInterruption.message('已停止本次回答', keepPartialOutput: true),
    );
  }

  void cancelCurrentTask() {
    if (_activePublicMode == null || !state.progress.canCancelTask) {
      return;
    }
    _interruptPublicRun(const _PublicRunInterruption.message('已取消本次查询'));
  }

  Future<void> requestConclusionNow() async {
    if (_activePublicMode == null || _activePublicSummaryOnly) {
      return;
    }
    _interruptPublicRun(const _PublicRunInterruption.restartSummary());
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
      ref.read(ttsFacadeProvider).stop();
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
    _cancelVoiceEchoHide();
    final _VoiceContinuationTrigger trigger = _nextStartListeningTrigger;
    _nextStartListeningTrigger = _VoiceContinuationTrigger.none;
    if (state.stage == AssistantStage.listen) return;
    _cancelVoiceContinuation();
    final bool hasPendingConfirm = state.pendingConfirm != null;
    await ref.read(ttsFacadeProvider).stop();
    _cancelFollowUpWindow();
    _cancelOpenMicWait();
    _listeningSource = source;
    final bool forceDrawerForConfirm =
        hasPendingConfirm &&
        state.surfaceState != AssistantSurfaceState.fullscreenAnswer;
    final bool willOpenDrawer = forceDrawerForConfirm ? true : openDrawer;
    final bool openingDrawer = willOpenDrawer && !state.drawerOpen;
    final bool preserveFullscreenAnswer =
        !willOpenDrawer &&
        state.surfaceState == AssistantSurfaceState.fullscreenAnswer;
    state = state.copyWith(
      drawerOpen: willOpenDrawer,
      stage: AssistantStage.listen,
      replySurface: AssistantReplySurface.none,
      // 抽屉打开走"沉浸模式"（partial 显示在抽屉内 _ListenStrip）；
      // 抽屉关闭：partial 由球周围的 _ListenStrip 显示（不走顶部浮窗——
      // _ListenStrip 视觉更精致+功能更全：音波/mode 区分/秒倒数/紧贴球的视觉焦点）。
      surfaceState: willOpenDrawer
          ? AssistantSurfaceState.drawerOpen
          : (preserveFullscreenAnswer
                ? AssistantSurfaceState.fullscreenAnswer
                : AssistantSurfaceState.none),
      drawerOpenRequestId: openingDrawer
          ? state.drawerOpenRequestId + 1
          : state.drawerOpenRequestId,
      drawerScrollTarget: openingDrawer
          ? (hasPendingConfirm
                ? AssistantDrawerScrollTarget.pendingConfirm
                : AssistantDrawerScrollTarget.latestMessage)
          : state.drawerScrollTarget,
      clearAnswerCard: !preserveFullscreenAnswer,
      listeningMode: mode,
      listenPartialText: '',
      listenWindowRemainingMs: 0,
      clearListenError: true,
      voiceEcho: AssistantVoiceEchoState.listening(
        displayText: mode == AssistantListeningMode.pressToTalk
            ? '我在听，松开手就发出去'
            : '我在听，你可以直接说',
      ),
      clearProgress: true,
    );

    final _ListenTiming timing = _listenTimingFor(trigger);
    final int vadEosMs = mode == AssistantListeningMode.pressToTalk
        ? _kPressToTalkVadEosMs
        : timing.vadEosMs;

    final PcmStreamRecorder recorder = ref.read(
      pcmStreamRecorderFactoryProvider,
    )();
    _recorder = recorder;

    final bool granted = await recorder.hasPermission();
    if (!granted) {
      state = state.copyWith(
        stage: AssistantStage.idle,
        listenError: '没有麦克风权限',
        voiceEcho: const AssistantVoiceEchoState.error(displayText: '没有麦克风权限'),
      );
      _scheduleVoiceEchoHide();
      _teardownVoice();
      return;
    }

    final XunfeiAsrClient client = ref.read(xunfeiAsrClientFactoryProvider)(
      vadEosMs: vadEosMs,
    );
    _asrClient = client;
    _autoSendOnFinal = true;

    _asrSub = client.events.listen(_handleAsrEvent);

    try {
      await client.start();
    } catch (e) {
      state = state.copyWith(
        stage: AssistantStage.idle,
        listenError: '讯飞连接失败：$e',
        voiceEcho: const AssistantVoiceEchoState.error(displayText: '识别服务连接失败'),
      );
      _scheduleVoiceEchoHide();
      _teardownVoice();
      return;
    }

    try {
      final Stream<Uint8List> frames = await recorder.start();
      _recorderSub = frames.listen(
        (Uint8List frame) {
          client.sendAudio(frame);
          _handleOutgoingPcmFrameForSpeech(frame);
        },
        onError: (Object err, StackTrace _) {
          state = state.copyWith(listenError: '录音异常：$err');
        },
      );
      _attachAudioLevelListener(recorder);
      if (mode == AssistantListeningMode.openMic) {
        _startOpenMicWait(timing.openMicWait);
      }
    } catch (e) {
      state = state.copyWith(
        stage: AssistantStage.idle,
        listenError: '录音启动失败：$e',
        voiceEcho: const AssistantVoiceEchoState.error(displayText: '录音启动失败'),
      );
      _scheduleVoiceEchoHide();
      _teardownVoice();
    }
  }

  /// 把 recorder 的本地音频能量转发到全局 ValueNotifier（供 UI 动画订阅）。
  /// 开口检测走实际送给讯飞的 PCM 帧，避免 UI 监听链路异常影响端点判断。
  void _attachAudioLevelListener(PcmStreamRecorder recorder) {
    _detachAudioLevelListener();
    _consecutiveLoudFrames = 0;
    final ValueListenable<double> listenable = recorder.audioLevel;
    final ValueNotifier<double> publish = ref.read(liveAudioLevelProvider);
    void onLevel() {
      publish.value = listenable.value;
    }

    listenable.addListener(onLevel);
    _audioLevelListenable = listenable;
    _audioLevelListener = onLevel;
  }

  void _detachAudioLevelListener() {
    if (_audioLevelListenable != null && _audioLevelListener != null) {
      _audioLevelListenable!.removeListener(_audioLevelListener!);
    }
    _audioLevelListenable = null;
    _audioLevelListener = null;
    _consecutiveLoudFrames = 0;
    try {
      ref.read(liveAudioLevelProvider).value = 0.0;
    } catch (_) {
      // container 销毁中（_teardownVoice 经 onDispose 触发时）read 会抛，
      // 此场景归零无意义，安全忽略。
    }
  }

  void _handleOutgoingPcmFrameForSpeech(Uint8List frame) {
    if (state.listeningMode != AssistantListeningMode.openMic ||
        _heardSpeechInCurrentOpenMic) {
      return;
    }
    final double level = _computePcmRms(frame);
    if (level >= _kSpeechRmsThreshold) {
      _consecutiveLoudFrames += 1;
      if (_consecutiveLoudFrames >= _kSpeechHoldFrames) {
        _markSpeechDetectedInOpenMic();
      }
    } else {
      _consecutiveLoudFrames = 0;
    }
  }

  double _computePcmRms(Uint8List frame) {
    final ByteData view = ByteData.sublistView(frame);
    final int sampleCount = frame.lengthInBytes ~/ 2;
    if (sampleCount == 0) {
      return 0;
    }
    double sumSquare = 0;
    for (int i = 0; i < sampleCount; i++) {
      final int sample = view.getInt16(i * 2, Endian.little);
      final double normalized = sample / 32768.0;
      sumSquare += normalized * normalized;
    }
    return math.sqrt(sumSquare / sampleCount).clamp(0.0, 1.0);
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
    final AssistantSurfaceState? clearedTopBanner =
        state.surfaceState == AssistantSurfaceState.topBannerListen
        ? AssistantSurfaceState.none
        : null;
    state = state.copyWith(
      stage: AssistantStage.idle,
      listenPartialText: '',
      listenWindowRemainingMs: 0,
      surfaceState: clearedTopBanner,
      clearVoiceEcho: true,
    );
    _teardownVoice();
  }

  AssistantVoiceEchoState _voiceEchoFinalState({
    required String rawFinalText,
    required String finalText,
    required bool wakeWordOnly,
  }) {
    final String raw = rawFinalText.trim();
    final String normalized = finalText.trim();
    if (wakeWordOnly) {
      return const AssistantVoiceEchoState.finalized(
        rawFinalText: '',
        finalText: '小治',
        displayText: '我在，你继续说',
      );
    }
    if (normalized.isEmpty && raw.isEmpty) {
      return const AssistantVoiceEchoState.error(displayText: '这次没听清');
    }
    if (normalized.isEmpty) {
      return AssistantVoiceEchoState.finalized(
        rawFinalText: raw,
        finalText: raw,
        displayText: '听到：$raw',
      );
    }
    final bool cleaned = raw.isNotEmpty && raw != normalized;
    return AssistantVoiceEchoState.finalized(
      rawFinalText: raw,
      finalText: normalized,
      cleaned: cleaned,
      displayText: cleaned ? '我理解为：$normalized' : '听到：$normalized',
    );
  }

  void _markVoiceEchoProcessingFor(String text) {
    final String normalized = text.trim();
    if (normalized.isEmpty) {
      return;
    }
    _cancelVoiceEchoHide();
    final AssistantVoiceEchoState current = state.voiceEcho;
    final bool fromVoice =
        current.phase == AssistantVoiceEchoPhase.finalText ||
        current.phase == AssistantVoiceEchoPhase.listening;
    if (!fromVoice) {
      return;
    }
    final String raw = current.rawFinalText.trim().isEmpty
        ? normalized
        : current.rawFinalText.trim();
    final bool cleaned = current.cleaned || raw != normalized;
    state = state.copyWith(
      voiceEcho: AssistantVoiceEchoState.processing(
        rawFinalText: raw,
        finalText: normalized,
        cleaned: cleaned,
        displayText: cleaned ? '正在处理：$normalized' : '正在处理你刚说的内容',
      ),
    );
  }

  void _scheduleVoiceEchoHide({
    Duration delay = const Duration(milliseconds: 1800),
  }) {
    _cancelVoiceEchoHide();
    _voiceEchoHideTimer = Timer(delay, () {
      _voiceEchoHideTimer = null;
      if (state.voiceEcho.isVisible) {
        state = state.copyWith(clearVoiceEcho: true);
      }
    });
  }

  void _cancelVoiceEchoHide() {
    _voiceEchoHideTimer?.cancel();
    _voiceEchoHideTimer = null;
  }

  void _handleAsrEvent(AsrEvent event) {
    if (event is AsrPartialEvent) {
      final String partial = event.text.trim();
      if (partial.isNotEmpty) {
        _markSpeechDetectedInOpenMic();
      }
      state = state.copyWith(
        listenPartialText: event.text,
        voiceEcho: AssistantVoiceEchoState.listening(
          partialText: partial,
          displayText: partial.isEmpty ? '' : '识别中：$partial',
          remainingMs: state.listenWindowRemainingMs,
        ),
      );
    } else if (event is AsrFinalEvent) {
      final String rawFinalText = event.text.trim();
      final _VoiceCommandText voiceText = _normalizeVoiceCommandText(
        event.text,
      );
      final String text = voiceText.text;
      if (text.isNotEmpty || voiceText.wakeWordOnly) {
        _markSpeechDetectedInOpenMic();
      }
      _cancelOpenMicWait();
      _teardownVoice();
      // ASR 收到 final 后顶部 banner 立刻淡出，让球切"在想"+ 大卡接管
      final AssistantSurfaceState? clearedTopBanner =
          state.surfaceState == AssistantSurfaceState.topBannerListen
          ? AssistantSurfaceState.none
          : null;
      state = state.copyWith(
        stage: AssistantStage.idle,
        listenPartialText: '',
        listenWindowRemainingMs: 0,
        surfaceState: clearedTopBanner,
        voiceEcho: _voiceEchoFinalState(
          rawFinalText: rawFinalText,
          finalText: text,
          wakeWordOnly: voiceText.wakeWordOnly,
        ),
      );
      if (_autoSendOnFinal && voiceText.wakeWordOnly) {
        unawaited(
          startListening(
            source: _listeningSource,
            openDrawer: state.drawerOpen,
            mode: AssistantListeningMode.openMic,
          ),
        );
        return;
      }
      if (_autoSendOnFinal && text.isNotEmpty) {
        sendUserMessage(
          text,
          source: _listeningSource,
          allowVoiceContinuation: true,
        );
      } else {
        _scheduleVoiceEchoHide();
      }
    } else if (event is AsrErrorEvent) {
      _cancelOpenMicWait();
      state = state.copyWith(
        stage: AssistantStage.idle,
        listenError: '识别异常 (${event.code}): ${event.message}',
        listenWindowRemainingMs: 0,
        voiceEcho: AssistantVoiceEchoState.error(
          displayText: '识别异常：${event.message}',
        ),
      );
      _scheduleVoiceEchoHide();
      _teardownVoice();
    }
  }

  void _speakAsync(
    String text, {
    AssistantSpeechMode speechMode = AssistantSpeechMode.digest,
  }) {
    final TtsFacade tts = ref.read(ttsFacadeProvider);
    final String voice = ref.read(currentTtsVoiceProvider);
    final double rate = ref.read(currentTtsSpeedProvider);
    final String speakText = _buildSpeechText(text, mode: speechMode);
    if (speakText.isEmpty) {
      return;
    }
    // ignore: discarded_futures
    tts.speak(speakText, voice: voice, rate: rate).catchError((Object err) {
      if (isTtsInterrupted(err)) {
        return;
      }
      // TTS 失败不影响对话流程，记到独立的 ttsError 通道。
      state = state.copyWith(ttsError: 'TTS 播报失败：$err');
    });
  }

  Future<void> _speakFullscreenAnswerAndStartDismiss(String text) async {
    final TtsFacade tts = ref.read(ttsFacadeProvider);
    final String voice = ref.read(currentTtsVoiceProvider);
    final double rate = ref.read(currentTtsSpeedProvider);
    final String speakText = _buildSpeechText(text);
    if (speakText.isEmpty) {
      if (_isFullscreenAnswerActive && _answerCardAutoDismisses()) {
        _startFollowUpWindow();
      }
      // 即使不需要播报也要 flush（pending reminder 不能因为这次没 TTS 就一直挂着）
      _flushPendingReminderIfAny();
      return;
    }

    try {
      await tts.speakAndWaitComplete(speakText, voice: voice, rate: rate);
    } catch (err) {
      if (isTtsInterrupted(err)) {
        return;
      }
      state = state.copyWith(ttsError: 'TTS 播报失败：$err');
    }

    if (_isFullscreenAnswerActive && _answerCardAutoDismisses()) {
      _startFollowUpWindow();
    }
    // 决策 #4「助手像人」：TTS 自然完成后才 flush 待处理提醒，
    // 不在 TTS 中间打断当前回答
    _flushPendingReminderIfAny();
  }

  Future<bool> replayLatestAssistantReply({bool full = false}) async {
    final AssistantMessage latest = state.messages.lastWhere(
      (AssistantMessage message) =>
          message.role == AssistantRole.assistant &&
          message.content.trim().isNotEmpty &&
          !message.streaming,
      orElse: () =>
          AssistantMessage(role: AssistantRole.assistant, content: ''),
    );
    if (latest.content.trim().isEmpty) {
      _speakAsync('我还没有可以播报的内容。');
      return false;
    }
    _speakAsync(
      _speechSourceForMessage(latest, full: full),
      speechMode: full ? AssistantSpeechMode.full : AssistantSpeechMode.digest,
    );
    return true;
  }

  String _speechSourceForMessage(
    AssistantMessage message, {
    required bool full,
  }) {
    final AssistantResultCard? card = message.resultCard;
    if (full && card is NewsCard) {
      return _fullNewsSpeechText(message.content, card);
    }
    return message.content;
  }

  String _fullNewsSpeechText(String visibleText, NewsCard card) {
    final List<String> parts = <String>[];
    final String lead = visibleText.trim();
    if (lead.isNotEmpty) {
      parts.add(lead);
    } else {
      parts.add('${card.title}。${card.summary}');
    }
    for (int i = 0; i < card.items.length; i++) {
      final NewsItem item = card.items[i];
      final List<String> itemParts = <String>['第${i + 1}条，${item.title}'];
      if ((item.summary ?? '').isNotEmpty) {
        itemParts.add(item.summary!);
      }
      final String meta = <String>[
        if ((item.source ?? '').isNotEmpty) item.source!,
        if ((item.timeLabel ?? '').isNotEmpty) item.timeLabel!,
      ].join('，');
      if (meta.isNotEmpty) {
        itemParts.add(meta);
      }
      parts.add('${itemParts.join('。')}。');
    }
    return parts.join('\n');
  }

  void hideAnswerCard({bool stopSpeaking = true}) {
    _cancelFollowUpWindow();
    _cancelVoiceEchoHide();
    if (stopSpeaking) {
      // ignore: discarded_futures
      ref.read(ttsFacadeProvider).stop();
    }
    state = state.copyWith(
      replySurface: AssistantReplySurface.none,
      surfaceState: state.drawerOpen
          ? AssistantSurfaceState.drawerOpen
          : AssistantSurfaceState.none,
      clearAnswerCard: true,
      clearReminder: true,
      clearVoiceEcho: true,
    );
  }

  // ---------------- 提醒（Reminder）接入 ----------------

  /// 等 TTS 自然播完才弹的待处理提醒（"助手像人"原则——不打断当前回答）。
  /// 单值：多个提醒到达时最新的覆盖旧的（不堆叠）。
  ReminderPayload? _pendingReminderPayloadQueue;
  ReminderCardData? _pendingReminderDataQueue;

  /// 由 [ForegroundReminderController] 检测到提醒到点时调用。
  /// 决策 #4：当前正在播 TTS（fullscreenAnswer + answer/think 阶段）时**不打断**，
  /// 等 TTS 自然完成后由 [_flushPendingReminderIfAny] 接管。
  void enqueueReminder({
    required ReminderPayload payload,
    required ReminderCardData data,
  }) {
    final bool ttsBusy =
        state.surfaceState == AssistantSurfaceState.fullscreenAnswer &&
        (state.stage == AssistantStage.answer ||
            state.stage == AssistantStage.think);
    if (ttsBusy) {
      _pendingReminderPayloadQueue = payload;
      _pendingReminderDataQueue = data;
      return;
    }
    _showReminderCard(payload: payload, data: data);
  }

  void _showReminderCard({
    required ReminderPayload payload,
    required ReminderCardData data,
  }) {
    _cancelFollowUpWindow();
    _pendingReminderPayloadQueue = null;
    _pendingReminderDataQueue = null;
    state = state.copyWith(
      drawerOpen: false,
      surfaceState: AssistantSurfaceState.fullscreenAnswer,
      answerCardKind: AnswerCardKind.reminder,
      answerCardText: data.title,
      reminderCardData: data,
      reminderPayload: payload,
    );
    // 异步播报"提醒：xxx"。reminder 类型的大卡不自动消散，等用户操作。
    unawaited(_speakReminderTts(data));
  }

  Future<void> _speakReminderTts(ReminderCardData data) async {
    final TtsFacade tts = ref.read(ttsFacadeProvider);
    final String voice = ref.read(currentTtsVoiceProvider);
    final double rate = ref.read(currentTtsSpeedProvider);
    final String text = '${data.timeLabel}，${data.title}';
    try {
      await tts.speakAndWaitComplete(text, voice: voice, rate: rate);
    } catch (err) {
      if (isTtsInterrupted(err)) return;
      state = state.copyWith(ttsError: 'TTS 播报失败：$err');
    }
  }

  void _flushPendingReminderIfAny() {
    final ReminderPayload? p = _pendingReminderPayloadQueue;
    final ReminderCardData? d = _pendingReminderDataQueue;
    if (p == null || d == null) return;
    _showReminderCard(payload: p, data: d);
  }

  void extendAnswerCardDisplay() {
    if (!_isFullscreenAnswerActive || !_answerCardAutoDismisses()) {
      return;
    }
    _startFollowUpWindow();
  }

  void expandAnswerCardToDrawer() {
    _cancelFollowUpWindow();
    state = state.copyWith(
      drawerOpen: true,
      replySurface: AssistantReplySurface.drawer,
      surfaceState: AssistantSurfaceState.drawerOpen,
      drawerOpenRequestId: state.drawerOpenRequestId + 1,
      drawerScrollTarget: AssistantDrawerScrollTarget.latestMessage,
      clearAnswerCard: true,
    );
  }

  Future<void> submitProactiveSuggestionAction(String actionId) async {
    final AssistantProactiveSuggestion? suggestion = state.proactiveSuggestion;
    if (suggestion == null) {
      return;
    }
    AssistantProactiveAction? selected;
    for (final AssistantProactiveAction action in suggestion.actions) {
      if (action.id == actionId) {
        selected = action;
        break;
      }
    }
    if (selected == null) {
      return;
    }
    state = state.copyWith(clearProactiveSuggestion: true);
    if (selected.dismissOnly) {
      return;
    }
    final String prompt = selected.prompt?.trim() ?? '';
    if (prompt.isEmpty) {
      return;
    }
    await sendUserMessage(prompt, source: AssistantEntrySource.drawerText);
  }

  void dismissProactiveSuggestion() {
    if (state.proactiveSuggestion == null) {
      return;
    }
    state = state.copyWith(clearProactiveSuggestion: true);
  }

  AssistantProactiveAction? _matchProactiveSuggestionAction(
    AssistantProactiveSuggestion suggestion,
    String text,
  ) {
    final String normalized = _compactVoiceText(text);
    if (normalized.isEmpty) {
      return null;
    }
    for (final AssistantProactiveAction action in suggestion.actions) {
      final String label = _compactVoiceText(action.label);
      if (normalized == label ||
          normalized == '帮我$label' ||
          normalized == '需要$label' ||
          normalized == '要$label' ||
          (normalized.endsWith(label) &&
              normalized.length <= label.length + 4)) {
        return action;
      }
    }
    return null;
  }

  void _setProgressStatus(String status) {
    _setProgressState(
      mode: state.progress.mode,
      phase: state.progress.phase,
      status: status,
      statusOrigin: state.progress.statusOrigin,
      detail: state.progress.detail,
      detailOrigin: state.progress.detailOrigin,
    );
  }

  void _setProgressState({
    required AssistantExecutionMode? mode,
    required AssistantProgressPhase? phase,
    required String? status,
    required AssistantProgressOrigin statusOrigin,
    String? detail,
    AssistantProgressOrigin? detailOrigin,
    String? requestId,
  }) {
    state = state.copyWith(
      progress: AssistantProgressState(
        mode: mode,
        phase: phase,
        status: status,
        statusOrigin: statusOrigin,
        detail: detail,
        detailOrigin: detailOrigin,
        steps: state.progress.steps,
        requestId: requestId ?? state.progress.requestId,
        startedAtMillis: state.progress.startedAtMillis,
        elapsedMs: state.progress.elapsedMs,
        hasStartedOutput: state.progress.hasStartedOutput,
        canStop: state.progress.canStop,
        canCancelTask: state.progress.canCancelTask,
        canAskForSummary: state.progress.canAskForSummary,
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

  void _finishAssistantTurn(
    String content, {
    _VoiceContinuationTrigger voiceContinuation =
        _VoiceContinuationTrigger.none,
  }) {
    final AssistantDisplayContent displayContent = parseAssistantDisplayContent(
      content,
    );
    final String finalContent = displayContent.text.trim().isEmpty
        ? '我这次没拿到有效结果。'
        : displayContent.text.trim();
    const AssistantSurfaceRouter router = AssistantSurfaceRouter();
    final AssistantReplySurface surface = router.resolve(
      entrySource: _lastEntrySource,
      drawerOpen: state.drawerOpen,
    );
    final bool useFullscreenAnswer = router.shouldUseFullscreenAnswer(
      entrySource: _lastEntrySource,
      drawerOpen: state.drawerOpen,
    );
    final AnswerCardKind answerKind = router.classifyAnswer(
      state: state,
      content: displayContent,
      text: finalContent,
    );
    _replaceTrailingAssistant(
      content: finalContent,
      streaming: false,
      resultCard: displayContent.resultCard,
    );
    final bool opensDrawer =
        surface == AssistantReplySurface.drawer && !state.drawerOpen;
    state = state.copyWith(
      stage: AssistantStage.idle,
      drawerOpen: surface == AssistantReplySurface.drawer,
      replySurface: useFullscreenAnswer ? AssistantReplySurface.none : surface,
      surfaceState: useFullscreenAnswer
          ? AssistantSurfaceState.fullscreenAnswer
          : (surface == AssistantReplySurface.drawer
                ? AssistantSurfaceState.drawerOpen
                : AssistantSurfaceState.none),
      drawerOpenRequestId: opensDrawer
          ? state.drawerOpenRequestId + 1
          : state.drawerOpenRequestId,
      drawerScrollTarget: opensDrawer
          ? AssistantDrawerScrollTarget.latestMessage
          : state.drawerScrollTarget,
      answerCardKind: useFullscreenAnswer ? answerKind : null,
      answerCardText: useFullscreenAnswer ? finalContent : null,
      answerCardResultCard: useFullscreenAnswer
          ? displayContent.resultCard
          : null,
      clearAnswerCard: !useFullscreenAnswer,
      followUpRemainingMs: 0,
      clearProgress: true,
      clearErrorState: true,
      clearTtsError: true,
    );
    _cancelFollowUpWindow();
    _scheduleVoiceEchoHide();

    if (finalContent.trim().isEmpty) return;

    final TtsPlaybackMode mode = ref.read(currentTtsPlaybackModeProvider);
    final bool shouldSpeak = decideAutoSpeak(
      entrySource: _lastEntrySource,
      surface: surface,
      fullscreenAnswer: useFullscreenAnswer,
      mode: mode,
      sessionMute: state.sessionMute,
    );

    if (voiceContinuation != _VoiceContinuationTrigger.none) {
      if (_maybeStartVoiceContinuation(
        finalContent,
        trigger: voiceContinuation,
      )) {
        return;
      }
    }

    if (!shouldSpeak) {
      if (useFullscreenAnswer && _answerCardAutoDismisses()) {
        _startFollowUpWindow();
      }
      return;
    }

    if (useFullscreenAnswer) {
      // 全屏大卡：播报完成后再启动 5 秒消散计时。
      // ignore: discarded_futures
      _speakFullscreenAnswerAndStartDismiss(finalContent);
    } else if (surface == AssistantReplySurface.drawer) {
      // 抽屉播报：fire-and-forget，不启动持续对话窗（避免抽屉里听到声音
      // 后又要被 5 秒倒计时催着说话，与"深度阅读"姿势冲突）。
      _speakAsync(finalContent);
    }
  }

  void _showAssistantError(String message, {AssistantErrorState? errorState}) {
    final bool useFullscreenAnswer = !_shouldUseDrawerSurface(_lastEntrySource);
    state = state.copyWith(
      stage: AssistantStage.error,
      drawerOpen: useFullscreenAnswer ? false : state.drawerOpen,
      replySurface: useFullscreenAnswer
          ? AssistantReplySurface.none
          : (state.drawerOpen
                ? AssistantReplySurface.drawer
                : AssistantReplySurface.none),
      surfaceState: useFullscreenAnswer
          ? AssistantSurfaceState.fullscreenAnswer
          : (state.drawerOpen
                ? AssistantSurfaceState.drawerOpen
                : AssistantSurfaceState.none),
      answerCardKind: useFullscreenAnswer ? AnswerCardKind.error : null,
      answerCardText: useFullscreenAnswer ? message : null,
      clearAnswerCard: !useFullscreenAnswer,
      error: message,
      errorState: errorState,
      clearErrorState: errorState == null,
      clearProgress: true,
      voiceEcho: state.voiceEcho.isVisible
          ? state.voiceEcho.copyWith(phase: AssistantVoiceEchoPhase.error)
          : null,
    );
    _scheduleVoiceEchoHide();
    if (useFullscreenAnswer) {
      _startFollowUpWindow();
    }
  }

  String _buildSpeechText(
    String text, {
    AssistantSpeechMode mode = AssistantSpeechMode.digest,
  }) => buildAssistantSpeechText(text, mode: mode);

  void _teardownVoice() {
    _cancelOpenMicWait();
    _detachAudioLevelListener();
    _recorderSub?.cancel();
    _recorderSub = null;
    _asrSub?.cancel();
    _asrSub = null;
    _asrClient?.dispose();
    _asrClient = null;
    _recorder?.dispose();
    _recorder = null;
  }

  bool _maybeStartVoiceContinuation(
    String prompt, {
    required _VoiceContinuationTrigger trigger,
  }) {
    if (trigger == _VoiceContinuationTrigger.none ||
        !_shouldAutoContinueListeningFromVoice()) {
      return false;
    }
    final int generation = ++_voiceContinuationGeneration;
    unawaited(
      _speakPromptThenContinueListening(
        prompt,
        trigger: trigger,
        generation: generation,
      ),
    );
    return true;
  }

  bool _shouldAutoContinueListeningFromVoice() {
    return _voiceContinuationAllowedForCurrentTurn &&
        (_lastEntrySource == AssistantEntrySource.drawerVoice ||
            _lastEntrySource == AssistantEntrySource.quickVoice);
  }

  Future<void> _speakPromptThenContinueListening(
    String prompt, {
    required _VoiceContinuationTrigger trigger,
    required int generation,
  }) async {
    final String speakText = _buildSpeechText(prompt);
    final TtsPlaybackMode mode = ref.read(currentTtsPlaybackModeProvider);
    final bool shouldSpeak = decideAutoSpeak(
      entrySource: _lastEntrySource,
      surface: state.drawerOpen
          ? AssistantReplySurface.drawer
          : AssistantReplySurface.none,
      fullscreenAnswer: !state.drawerOpen,
      mode: mode,
      sessionMute: state.sessionMute,
    );
    if (shouldSpeak && speakText.isNotEmpty) {
      final TtsFacade tts = ref.read(ttsFacadeProvider);
      final String voice = ref.read(currentTtsVoiceProvider);
      final double rate = ref.read(currentTtsSpeedProvider);
      try {
        await tts.speakAndWaitComplete(speakText, voice: voice, rate: rate);
      } catch (err) {
        if (isTtsInterrupted(err)) {
          return;
        }
        state = state.copyWith(ttsError: 'TTS 播报失败：$err');
      }
    }
    if (generation != _voiceContinuationGeneration ||
        !_shouldStillAwaitVoiceContinuation(trigger)) {
      return;
    }
    _nextStartListeningTrigger = trigger;
    final bool keepDrawerForContinuation =
        state.drawerOpen ||
        (state.pendingConfirm != null &&
            state.surfaceState != AssistantSurfaceState.fullscreenAnswer);
    await startListening(
      source: _lastEntrySource,
      openDrawer: keepDrawerForContinuation,
      mode: AssistantListeningMode.openMic,
    );
  }

  bool _shouldStillAwaitVoiceContinuation(_VoiceContinuationTrigger trigger) {
    if (state.stage == AssistantStage.listen ||
        state.stage == AssistantStage.think ||
        state.stage == AssistantStage.answer) {
      return false;
    }
    switch (trigger) {
      case _VoiceContinuationTrigger.none:
        return false;
      case _VoiceContinuationTrigger.confirm:
        return state.pendingConfirm != null;
      case _VoiceContinuationTrigger.missingWriteSlots:
        return state.pendingWriteDraft != null;
      case _VoiceContinuationTrigger.pendingTaskChoice:
        return _pendingTaskChoice?.isFresh == true;
      case _VoiceContinuationTrigger.tripPlanning:
        return _pendingTripPlanningFrame != null;
      case _VoiceContinuationTrigger.proactiveSuggestion:
        return state.proactiveSuggestion != null &&
            state.pendingConfirm == null;
    }
  }

  void _cancelVoiceContinuation() {
    _voiceContinuationGeneration += 1;
  }

  String _latestAssistantPrompt({String fallback = ''}) {
    for (final AssistantMessage message in state.messages.reversed) {
      if (message.role == AssistantRole.assistant &&
          message.content.trim().isNotEmpty) {
        return message.content.trim();
      }
    }
    return fallback.trim();
  }

  void _startOpenMicWait(Duration wait) {
    _cancelOpenMicWait();
    _heardSpeechInCurrentOpenMic = false;
    final int totalMs = wait.inMilliseconds;
    state = state.copyWith(
      listenWindowRemainingMs: totalMs,
      voiceEcho: state.voiceEcho.copyWith(remainingMs: totalMs),
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
      final int clamped = nextMs.clamp(0, totalMs);
      state = state.copyWith(
        listenWindowRemainingMs: clamped,
        voiceEcho: state.voiceEcho.copyWith(remainingMs: clamped),
      );
    });
    _openMicTimeoutTimer = Timer(wait, () async {
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
        voiceEcho: const AssistantVoiceEchoState.error(displayText: '这次没听到你说话'),
      );
      _scheduleVoiceEchoHide();
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
    _cancelOpenMicWait(keepSpeechDetected: true);
    if (state.voiceEcho.phase == AssistantVoiceEchoPhase.listening &&
        state.voiceEcho.partialText.trim().isEmpty) {
      state = state.copyWith(
        voiceEcho: state.voiceEcho.copyWith(
          displayText: '我在听，你继续说',
          remainingMs: 0,
        ),
      );
    }
  }

  void _cancelOpenMicWait({
    bool resetState = true,
    bool keepSpeechDetected = false,
  }) {
    _openMicTimeoutTimer?.cancel();
    _openMicTimeoutTimer = null;
    _openMicTicker?.cancel();
    _openMicTicker = null;
    if (!keepSpeechDetected) {
      _heardSpeechInCurrentOpenMic = false;
    }
    if (resetState && state.listenWindowRemainingMs != 0) {
      state = state.copyWith(
        listenWindowRemainingMs: 0,
        voiceEcho: state.voiceEcho.copyWith(remainingMs: 0),
      );
    }
  }

  bool get _isFullscreenAnswerActive {
    return state.surfaceState == AssistantSurfaceState.fullscreenAnswer &&
        state.answerCardKind != null &&
        (state.answerCardText?.trim().isNotEmpty == true ||
            state.answerCardResultCard != null ||
            state.answerCardKind == AnswerCardKind.confirm);
  }

  bool _answerCardAutoDismisses() {
    switch (state.answerCardKind) {
      case AnswerCardKind.infoCard:
      case AnswerCardKind.toolFeedback:
      case AnswerCardKind.plainText:
      case AnswerCardKind.error:
        return true;
      case AnswerCardKind.clarification:
      case AnswerCardKind.confirm:
      case AnswerCardKind.reminder:
      case null:
        return false;
    }
  }

  bool get _hasTimedAnswerSurface {
    return _isFullscreenAnswerActive && _answerCardAutoDismisses();
  }

  void _startFollowUpWindow() {
    _cancelFollowUpWindow();
    state = state.copyWith(
      followUpRemainingMs: _kFollowUpWindow.inMilliseconds,
    );
    _followUpTicker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!_hasTimedAnswerSurface) {
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
      if (_isFullscreenAnswerActive) {
        state = state.copyWith(
          surfaceState: AssistantSurfaceState.none,
          clearAnswerCard: true,
          followUpRemainingMs: 0,
        );
      }
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

String? _extractWriteTitle(
  String text, {
  required AssistantWriteDraftKind kind,
}) {
  String normalized = text.trim();
  if (normalized.isEmpty) {
    return null;
  }
  normalized = normalized
      .replaceAll(_writeDatePattern, ' ')
      .replaceAll(_writeWeekdayPattern, ' ')
      .replaceAll(_writeTimePattern, ' ')
      .replaceAll(_writeVerbPattern, ' ')
      .replaceAll(
        kind == AssistantWriteDraftKind.reminder
            ? _reminderObjectPattern
            : _scheduleObjectPattern,
        ' ',
      )
      .replaceAll(RegExp(r'[，。！？,.!?]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  normalized = normalized
      .replaceAll(RegExp(r'^(请|麻烦|帮我|给我|替我|我想|想|一个|一条|个|的)+'), '')
      .replaceAll(RegExp(r'^(和|跟|与)'), '')
      .replaceAll(RegExp(r'(一下|这个|那个|的)$'), '')
      .trim();
  if (normalized.length < 2) {
    return null;
  }
  if (_titleStopWords.contains(normalized)) {
    return null;
  }
  return normalized;
}

DateTime? _extractWriteDate(String text) {
  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day);
  if (text.contains('大后天')) {
    return today.add(const Duration(days: 3));
  }
  if (text.contains('后天')) {
    return today.add(const Duration(days: 2));
  }
  if (text.contains('明天') || text.contains('明早')) {
    return today.add(const Duration(days: 1));
  }
  if (text.contains('今天') || text.contains('今晚')) {
    return today;
  }

  final RegExpMatch? absolute = RegExp(
    r'(\d{1,2})\s*月\s*(\d{1,2})\s*(?:日|号)',
  ).firstMatch(text);
  if (absolute != null) {
    final int month = int.parse(absolute.group(1)!);
    final int day = int.parse(absolute.group(2)!);
    DateTime candidate = DateTime(now.year, month, day);
    if (candidate.isBefore(today)) {
      candidate = DateTime(now.year + 1, month, day);
    }
    return candidate;
  }

  final RegExpMatch? weekday = _writeWeekdayPattern.firstMatch(text);
  if (weekday != null) {
    final int? target = _weekdayNumber(weekday.group(1)!);
    if (target == null) {
      return null;
    }
    final int todayWeekday = today.weekday;
    int diff = target - todayWeekday;
    if (diff <= 0) {
      diff += 7;
    }
    return today.add(Duration(days: diff));
  }

  return null;
}

int? _extractWriteTimeMinutes(String text) {
  final RegExpMatch? match = _writeTimePattern.firstMatch(text);
  if (match == null) {
    return null;
  }
  return _minutesFromTimeMatch(match).minutes;
}

List<_TimeMention> _extractTimeMentions(String text) {
  return _writeTimePattern.allMatches(text).map(_minutesFromTimeMatch).toList();
}

_TimeMention _minutesFromTimeMatch(RegExpMatch match) {
  final String rawPeriod = match.group(1) ?? '';
  final String timeText = match.group(2)!;
  int hour;
  int minute = 0;

  if (timeText.contains(':') || timeText.contains('：')) {
    final List<String> parts = timeText.split(RegExp(r'[:：]'));
    hour = int.parse(parts[0]);
    minute = int.parse(parts[1]);
  } else {
    final RegExpMatch? hourMatch = RegExp(r'(\d{1,2})').firstMatch(timeText);
    if (hourMatch == null) {
      throw StateError('Invalid time expression: $timeText');
    }
    hour = int.parse(hourMatch.group(1)!);
    final RegExpMatch? minuteMatch = RegExp(
      r'点\s*(\d{1,2})\s*分?',
    ).firstMatch(timeText);
    if (minuteMatch != null) {
      minute = int.parse(minuteMatch.group(1)!);
    } else if (timeText.contains('半')) {
      minute = 30;
    }
  }

  final String period = rawPeriod.trim();
  final List<int> candidates = <int>[];
  if ((period.contains('下午') ||
          period.contains('晚上') ||
          period.contains('今晚')) &&
      hour < 12) {
    hour += 12;
  }
  if (period.contains('中午') && hour < 11) {
    hour += 12;
  }
  if ((period.contains('凌晨') ||
          period.contains('早上') ||
          period.contains('上午')) &&
      hour == 12) {
    hour = 0;
  }

  final int minutes = (hour * 60 + minute).clamp(0, 1440);
  candidates.add(minutes);
  if (period.isEmpty && hour > 0 && hour < 12) {
    candidates.add(((hour + 12) * 60 + minute).clamp(0, 1440));
  }
  return _TimeMention(
    raw: match.group(0) ?? '',
    period: period,
    minutes: minutes,
    candidates: candidates.toSet().toList(),
  );
}

int? _weekdayNumber(String text) {
  switch (text) {
    case '一':
      return DateTime.monday;
    case '二':
      return DateTime.tuesday;
    case '三':
      return DateTime.wednesday;
    case '四':
      return DateTime.thursday;
    case '五':
      return DateTime.friday;
    case '六':
      return DateTime.saturday;
    case '日':
    case '天':
      return DateTime.sunday;
  }
  return null;
}

String _formatToolDate(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

DateTime _todayDate() {
  final DateTime now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

String _dateLabel(DateTime date) {
  final DateTime today = _todayDate();
  final DateTime target = DateTime(date.year, date.month, date.day);
  final int diff = target.difference(today).inDays;
  if (diff == 0) return '今天';
  if (diff == 1) return '明天';
  if (diff == 2) return '后天';
  return '${target.month} 月 ${target.day} 日';
}

String _timeLabel(int minutes) {
  final int hour = minutes ~/ 60;
  final int minute = minutes % 60;
  final String period;
  final int displayHour;
  if (hour == 0) {
    period = '凌晨';
    displayHour = 12;
  } else if (hour < 6) {
    period = '凌晨';
    displayHour = hour;
  } else if (hour < 12) {
    period = '上午';
    displayHour = hour;
  } else if (hour == 12) {
    period = '中午';
    displayHour = 12;
  } else if (hour < 18) {
    period = '下午';
    displayHour = hour - 12;
  } else {
    period = '晚上';
    displayHour = hour - 12;
  }
  if (minute == 0) return '$period $displayHour 点';
  if (minute == 30) return '$period $displayHour 点半';
  return '$period $displayHour 点 $minute 分';
}

TaskReminderKey? _parseReminderFollowUp(String text) {
  final String normalized = text.trim().replaceAll(RegExp(r'[，。！？\s]'), '');
  if (normalized.isEmpty) {
    return null;
  }
  if (RegExp(r'(不用|不要|无需|不需要|取消).*提醒').hasMatch(normalized) ||
      normalized == '不用提醒' ||
      normalized == '不提醒') {
    return TaskReminderKey.none;
  }
  if (!normalized.contains('提醒')) {
    return null;
  }
  if (normalized.contains('提前一小时') || normalized.contains('提前1小时')) {
    return TaskReminderKey.before1h;
  }
  if (normalized.contains('提前半小时') ||
      normalized.contains('提前30分钟') ||
      normalized.contains('提前三十分钟')) {
    return TaskReminderKey.before30m;
  }
  if (normalized.contains('提前5分钟') || normalized.contains('提前五分钟')) {
    return TaskReminderKey.before5m;
  }
  if (normalized.contains('开始时') || normalized.contains('准点')) {
    return TaskReminderKey.atStart;
  }
  if (normalized.contains('需要提醒') ||
      normalized.contains('要提醒') ||
      normalized.contains('提醒我') ||
      normalized.contains('加提醒') ||
      normalized == '提醒') {
    return TaskReminderKey.before10m;
  }
  if (normalized.contains('提前10分钟') || normalized.contains('提前十分钟')) {
    return TaskReminderKey.before10m;
  }
  return null;
}

String _reminderShortLabel(TaskReminderKey key) {
  switch (key) {
    case TaskReminderKey.none:
      return '不提醒';
    case TaskReminderKey.atStart:
      return '开始时提醒';
    case TaskReminderKey.before5m:
      return '提前 5 分钟提醒';
    case TaskReminderKey.before10m:
      return '提前 10 分钟提醒';
    case TaskReminderKey.before30m:
      return '提前 30 分钟提醒';
    case TaskReminderKey.before1h:
      return '提前 1 小时提醒';
    case TaskReminderKey.day9am:
      return '当天 9 点提醒';
    case TaskReminderKey.dayNoon:
      return '当天中午提醒';
    case TaskReminderKey.day6pm:
      return '当天 18 点提醒';
    case TaskReminderKey.dayBefore9am:
      return '前一天 9 点提醒';
    case TaskReminderKey.custom:
      return '自定义提醒';
  }
}

bool _isTaskQueryRequest(String text) {
  return RegExp(r'(任务|待办|日程|提醒|会议|安排)').hasMatch(text) &&
      RegExp(r'(什么|哪些|查|看看|看一下|有没有|有啥|有什么|安排)').hasMatch(text);
}

bool _isTaskDeleteRequest(String text) {
  return RegExp(r'(删除|删掉|取消)').hasMatch(text) &&
      RegExp(r'(任务|待办|日程|提醒|会议|安排|会|拜访|讨论)').hasMatch(text);
}

bool _isTaskTimeUpdateRequest(String text) {
  return RegExp(r'(修改|调整|推迟|提前|改到|改成|挪到)').hasMatch(text) &&
      RegExp(r'(任务|待办|日程|提醒|会议|安排|会|拜访|讨论)').hasMatch(text);
}

bool _looksLikeChoiceReply(String text) {
  final String normalized = text.trim().replaceAll(RegExp(r'[，。！？\s]'), '');
  return RegExp(
    r'^(第?[一二两三四五六七八九十\d]+条|第?[一二两三四五六七八九十\d]+个|选第?[一二两三四五六七八九十\d]+|就第?[一二两三四五六七八九十\d]+|前一个|后一个)$',
  ).hasMatch(normalized);
}

bool _isProactiveSuggestionDismissInput(String text) {
  return _isCancelOrCloseInput(text);
}

bool _isCancelOrCloseInput(String text) {
  final String s = _normalizeForIntentMatch(text);
  if (s.isEmpty) return false;
  return _cancelInputPattern.hasMatch(s) ||
      _conversationCloseInputPattern.hasMatch(s);
}

bool _isConversationCloseInput(String text) {
  final String s = _normalizeForIntentMatch(text);
  if (s.isEmpty) return false;
  return _conversationCloseInputPattern.hasMatch(s);
}

/// 给 confirm/cancel/close 三类意图识别共用的文本规整：
/// 1) [stripChineseFillers] 剥前后语气词 + 礼貌前缀
/// 2) 去标点空白
String _normalizeForIntentMatch(String text) {
  final String stripped = stripChineseFillers(text);
  return stripped.replaceAll(RegExp(r'[，。！？,.!?\s、；;:：]'), '');
}

_VoiceCommandText _normalizeVoiceCommandText(String raw) {
  String text = raw.trim();
  if (text.isEmpty) {
    return const _VoiceCommandText('');
  }
  final String compact = _compactVoiceText(text);
  if (_wakeWordOnlyPattern.hasMatch(compact)) {
    return const _VoiceCommandText('', wakeWordOnly: true);
  }
  text = stripChineseFillers(text).trim();
  while (true) {
    final RegExpMatch? match = _leadingWakeWordPattern.firstMatch(text);
    if (match == null || match.start != 0) {
      break;
    }
    text = text.substring(match.end).trimLeft();
  }
  text = text.replaceFirst(RegExp(r'^[，。！？,.!?\s]+'), '').trim();
  if (text.isEmpty && _wakeWordOnlyPattern.hasMatch(compact)) {
    return const _VoiceCommandText('', wakeWordOnly: true);
  }
  return _VoiceCommandText(text);
}

String _compactVoiceText(String text) {
  return text.replaceAll(RegExp(r'[，。！？,.!?\s]+'), '');
}

int? _parseChoiceIndex(String text) {
  final String normalized = text.trim().replaceAll(RegExp(r'[，。！？\s]'), '');
  if (normalized.isEmpty) return null;
  if (normalized == '前一个') return 0;
  if (normalized == '后一个') return 1;
  final RegExpMatch? match = RegExp(
    r'(?:选|就)?(?:第)?([一二两三四五六七八九十\d]+)(?:条|个)?$',
  ).firstMatch(normalized);
  if (match == null) {
    return null;
  }
  final int? number = _parseChineseOrdinal(match.group(1)!);
  if (number == null || number <= 0) {
    return null;
  }
  return number - 1;
}

int? _parseChineseOrdinal(String raw) {
  final int? numeric = int.tryParse(raw);
  if (numeric != null) return numeric;
  const Map<String, int> digits = <String, int>{
    '一': 1,
    '二': 2,
    '两': 2,
    '三': 3,
    '四': 4,
    '五': 5,
    '六': 6,
    '七': 7,
    '八': 8,
    '九': 9,
    '十': 10,
  };
  if (digits.containsKey(raw)) {
    return digits[raw];
  }
  if (raw.startsWith('十') && raw.length == 2) {
    return 10 + (digits[raw.substring(1)] ?? 0);
  }
  if (raw.endsWith('十') && raw.length == 2) {
    return (digits[raw.substring(0, 1)] ?? 0) * 10;
  }
  if (raw.length == 3 && raw.substring(1, 2) == '十') {
    return (digits[raw.substring(0, 1)] ?? 0) * 10 +
        (digits[raw.substring(2)] ?? 0);
  }
  return null;
}

bool _looksLikeLocalWriteSuccessClaim(String text) {
  return RegExp(
        r'(已|已经|帮你|为你).{0,8}(创建|新增|添加|记录|安排|修改|删除|取消|设置)',
      ).hasMatch(text) ||
      RegExp(r'(创建|新增|添加|记录|安排|修改|删除|取消|设置).{0,8}(成功|好了|完成)').hasMatch(text);
}

String _extractTaskReferenceHint(String text) {
  String s = text;
  s = s.replaceAll(RegExp(r'(改成|改到|调整到|推迟到|提前到|挪到).*$'), ' ');
  s = s
      .replaceAll(_writeDatePattern, ' ')
      .replaceAll(_writeWeekdayPattern, ' ')
      .replaceAll(_writeTimePattern, ' ')
      .replaceAll(
        RegExp(r'(请|麻烦|帮我|给我|替我|把|将|删除|删掉|取消|修改|调整|推迟|提前|这个|那个|一条|一个|个|的)'),
        ' ',
      )
      .replaceAll(RegExp(r'[，。！？,.!?\s]+'), ' ')
      .trim();
  while (s.startsWith('的')) {
    s = s.substring(1).trim();
  }
  while (s.endsWith('的')) {
    s = s.substring(0, s.length - 1).trim();
  }
  return s;
}

String _normalizeTaskText(String text) {
  return text
      .replaceAll(RegExp(r'[，。！？,.!?\s]'), '')
      .replaceAll('开会', '会议')
      .trim();
}

bool _isGenericMeetingHint(String text) {
  return text == '会议' || text == '会' || text == '安排';
}

bool _looksLikeMeetingTitle(String text) {
  final String normalized = _normalizeTaskText(text);
  return normalized.contains('会') ||
      normalized.contains('讨论') ||
      normalized.contains('评审') ||
      normalized.contains('沟通') ||
      normalized.contains('复盘') ||
      normalized.contains('汇报');
}

bool _looksLikeTravelSchedule(String text) {
  return RegExp(r'(出差|差旅|高铁|火车|飞机|航班|机场|车站)').hasMatch(text) ||
      RegExp(r'(去|到|前往|飞往).{1,12}(出差|开会|培训|面试)').hasMatch(text);
}

bool _looksLikeClientVisitSchedule(String text) {
  return RegExp(r'(客户|客户现场|拜访|对接|商务沟通|商务交流)').hasMatch(text);
}

bool _looksLikeMedicalSchedule(String text) {
  return RegExp(r'(医院|体检|看病|复诊|门诊|挂号|就诊)').hasMatch(text);
}

bool _looksLikeInterviewOrExamSchedule(String text) {
  return RegExp(r'(面试|考试|笔试|培训|答辩|路演)').hasMatch(text);
}

String? _extractDestinationFromScheduleTitle(String title) {
  final String compact = title.replaceAll(RegExp(r'[，。！？,.!?\s]'), '');
  final RegExpMatch? withVerb = RegExp(
    r'(?:出差去|前往|去|到|飞往|飞)([\u4e00-\u9fa5A-Za-z]{2,12}?)(?:出差|开会|拜访|客户|现场|培训|$)',
  ).firstMatch(compact);
  if (withVerb != null) {
    return _cleanDestinationName(withVerb.group(1));
  }
  final RegExpMatch? beforeTravel = RegExp(
    r'([\u4e00-\u9fa5A-Za-z]{2,12}?)(?:出差|差旅)',
  ).firstMatch(compact);
  if (beforeTravel != null) {
    return _cleanDestinationName(beforeTravel.group(1));
  }
  return null;
}

String? _cleanDestinationName(String? raw) {
  if (raw == null) {
    return null;
  }
  String value = raw.trim();
  value = value
      .replaceAll(RegExp(r'^(去|到|飞|前往|出差去)'), '')
      .replaceAll(RegExp(r'(的|现场|客户)$'), '')
      .trim();
  if (value.length < 2 || _titleStopWords.contains(value)) {
    return null;
  }
  return value;
}

int _resolveNewTimeMinutes(_TimeMention newTime, int? oldStartMinutes) {
  if (oldStartMinutes == null ||
      newTime.period.isNotEmpty ||
      newTime.candidates.length == 1) {
    return newTime.minutes;
  }
  final bool oldIsPm = oldStartMinutes >= 12 * 60;
  if (oldIsPm) {
    return newTime.candidates.last;
  }
  return newTime.candidates.first;
}

(int?, int?) _parseCandidateTimeRange(String label) {
  final Iterable<RegExpMatch> matches = RegExp(
    r'(\d{1,2}):(\d{2})',
  ).allMatches(label);
  final List<int> minutes = matches.map((RegExpMatch match) {
    final int hour = int.parse(match.group(1)!);
    final int minute = int.parse(match.group(2)!);
    return (hour * 60 + minute).clamp(0, 1440);
  }).toList();
  if (minutes.isEmpty) {
    return (null, null);
  }
  return (minutes.first, minutes.length > 1 ? minutes[1] : null);
}

int? _parseInt(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw);
  return null;
}

/// confirm 单字白名单：剥语气词与标点后**完全等于**这些 token 才算 confirm。
/// 避免"好烦"中的"好"被 contains 模式误判。
final RegExp _singleConfirmPattern = RegExp(r'^(对|是|好|行|嗯|嗯嗯|嗯啊|嗯哼)$');

/// confirm 多字关键词：剥语气词与标点后**包含**这些子串就算 confirm。
/// 必须 ≥ 2 字，避免单字误判。
final RegExp _multiConfirmPattern = RegExp(
  r'(确认|确定|可以|好的|没错|是的|对的|执行|创建|建立|添加|加上|安排)',
);

/// 显式否定 + confirm 关键词，识别为 cancel。
/// 锚定开头（^），避免"我不行"这种被误匹配——后者由其他逻辑兜底。
final RegExp _negatedConfirmPattern = RegExp(
  r'^(不|别|不要|不想)(确认|确定|可以|好|好的|执行|创建|行|是|对|要)',
);

/// cancel 关键词 contains 模式（必须 ≥ 2 字，避免"不"单字误判其它正常表达）。
final RegExp _cancelInputPattern = RegExp(r'(取消|不用|算了|撤销|放弃|不要|先不)');

/// close 关键词 contains 模式（"好了/就这样/可以了"等收尾表达）。
final RegExp _conversationCloseInputPattern = RegExp(
  r'(好了|好啦|就这样|先这样|没事了|结束|可以了)',
);
final RegExp _wakeWordOnlyPattern = RegExp(r'^(小治小治|小智小智|小治|小智)+$');
final RegExp _leadingWakeWordPattern = RegExp(
  r'^(?:小治小治|小智小智|小治|小智)[，。！？,.!?\s]*',
);
final RegExp _tripPlanningCancelPattern = RegExp(
  r'^(不规划了|不用规划了|先不规划|别规划了|不查了|不用查了|先不查|别查了|'
  r'路线先不用|先不用路线|不用路线了|不用查路线|别查路线)$',
);
final RegExp _tripPlanningControlReplyPattern = RegExp(
  r'^(取消|不用|不用了|算了|先不|先不用|不要|别|撤销|放弃|'
  r'不规划了|不用规划了|先不规划|别规划了|不查了|不用查了|先不查|别查了|'
  r'路线先不用|先不用路线|不用路线了|不用查路线|别查路线)$',
);
final RegExp _nonCreateWritePattern = RegExp(
  r'(修改|调整|推迟|提前|删除|删掉|取消|完成|标记|改到|改成|挪到)',
);
final RegExp _reminderCreatePattern = RegExp(
  r'(提醒我|定个提醒|加(?:个|一个|一条)?提醒|新增提醒|创建提醒)',
);
final RegExp _scheduleCreatePattern = RegExp(
  r'(创建|新建|新增|添加|加(?:个|一个|一条)?|安排|约|定).{0,24}'
  r'(任务|待办|日程|会议|安排|约会|会)',
);
bool _looksLikeImplicitTimedScheduleCreate(String text) {
  if (_nonCreateWritePattern.hasMatch(text)) {
    return false;
  }
  if (_explicitQuestionPattern.hasMatch(text) ||
      _publicInterruptionPattern.hasMatch(text)) {
    return false;
  }
  final AssistantPendingWriteDraft draft = AssistantPendingWriteDraft(
    kind: AssistantWriteDraftKind.schedule,
    title: _extractWriteTitle(text, kind: AssistantWriteDraftKind.schedule),
    startDate: _extractWriteDate(text),
    startTimeMinutes: _extractWriteTimeMinutes(text),
  );
  return draft.isComplete;
}

final RegExp _writeDatePattern = RegExp(
  r'(大后天|后天|明天|今天|今晚|明早|\d{1,2}\s*月\s*\d{1,2}\s*(?:日|号))',
);
final RegExp _writeWeekdayPattern = RegExp(r'(?:周|星期)([一二三四五六日天])');
final RegExp _writeTimePattern = RegExp(
  r'(?:(凌晨|早晨|早上|上午|中午|下午|晚上|今晚|明早)\s*)?'
  r'(\d{1,2}[:：]\d{1,2}|\d{1,2}\s*点(?:\s*\d{1,2}\s*分?)?(?:半)?)',
);
final RegExp _writeVerbPattern = RegExp(
  r'(请|麻烦|帮我|给我|替我|我想|想|创建|新建|新增|添加|加|安排|约|定|定个|一个|一条|个)',
);
final RegExp _scheduleObjectPattern = RegExp(r'(任务|待办|日程|会议|安排|约会)');
final RegExp _reminderObjectPattern = RegExp(r'(提醒|提醒我)');
const Set<String> _titleStopWords = <String>{
  '日程',
  '会议',
  '任务',
  '待办',
  '提醒',
  '安排',
};

final RegExp _explicitQuestionPattern = RegExp(
  r'(查一下|查查|搜索|问一下|看一下|看看|告诉我|怎么样|是什么|为什么|怎么|多少|哪里|天气|新闻|汇率|股价|价格)',
);
final RegExp _publicInterruptionPattern = RegExp(
  r'(天气|气温|下雨|新闻|汇率|股价|价格|附近|路线|酒店|餐厅|搜索)',
);
final RegExp _routePlanningFramePattern = RegExp(
  r'(路线规划|规划.{0,12}路线|导航|怎么去|怎么走|怎么过去|'
  r'从.{1,18}到.{1,18}|(?:去|到|前往).{1,18}(?:路线|导航|怎么走|怎么去)|'
  r'开车|驾车|自驾|打车|地铁|公交|公共交通|坐车|步行|骑车)',
);
final RegExp _resumeTripPlanningPattern = RegExp(
  r'^(继续|接着|刚才|上一条)$|(?:继续|接着|刚才|上一条).{0,8}(路线|行程)',
);

const Duration _tripPlanningFrameTtl = Duration(minutes: 10);
const int _tripPlanningFrameMaxFollowUps = 4;

bool _isGenericTripDestination(String? value) {
  if (value == null) {
    return true;
  }
  final String compact = value.replaceAll(RegExp(r'[，。！？,.!?\s]+'), '');
  return compact.isEmpty ||
      compact == '目的地' ||
      compact == '客户现场' ||
      compact == '客户那里' ||
      compact == '公司' ||
      compact == '那里';
}

class _TripPlanningFrame {
  _TripPlanningFrame({
    this.date,
    this.origin,
    this.destination,
    this.duration,
    this.transport,
    this.destinationHint,
    int? createdAtMillis,
    this.followUpTurns = 0,
  }) : createdAtMillis =
           createdAtMillis ?? DateTime.now().millisecondsSinceEpoch;

  final String? date;
  final String? origin;
  final String? destination;
  final String? duration;
  final String? transport;
  final String? destinationHint;
  final int createdAtMillis;
  final int followUpTurns;

  bool get needsDestination => _isGenericTripDestination(destination);

  bool get isReady =>
      origin != null &&
      origin!.trim().isNotEmpty &&
      !needsDestination &&
      transport != null &&
      transport!.trim().isNotEmpty;

  _TripPlanningFrame copyWith({
    String? date,
    String? origin,
    String? destination,
    String? duration,
    String? transport,
    String? destinationHint,
    int? createdAtMillis,
    int? followUpTurns,
  }) {
    return _TripPlanningFrame(
      date: date ?? this.date,
      origin: origin ?? this.origin,
      destination: destination ?? this.destination,
      duration: duration ?? this.duration,
      transport: transport ?? this.transport,
      destinationHint: destinationHint ?? this.destinationHint,
      createdAtMillis: createdAtMillis,
      followUpTurns: followUpTurns ?? this.followUpTurns,
    );
  }

  _TripPlanningFrame nextFollowUpTurn() {
    return copyWith(followUpTurns: followUpTurns + 1);
  }

  bool sameSlotsAs(_TripPlanningFrame other) {
    return date == other.date &&
        origin == other.origin &&
        destination == other.destination &&
        duration == other.duration &&
        transport == other.transport &&
        destinationHint == other.destinationHint;
  }
}

class _TimeMention {
  const _TimeMention({
    required this.raw,
    required this.period,
    required this.minutes,
    required this.candidates,
  });

  final String raw;
  final String period;
  final int minutes;
  final List<int> candidates;
}

class _TaskCommandCandidate {
  const _TaskCommandCandidate({
    required this.id,
    required this.title,
    required this.timeLabel,
    required this.startMinutes,
    required this.endMinutes,
  });

  final int id;
  final String title;
  final String timeLabel;
  final int? startMinutes;
  final int? endMinutes;

  int? get durationMinutes {
    final int? start = startMinutes;
    final int? end = endMinutes;
    if (start == null || end == null || end <= start) {
      return null;
    }
    return end - start;
  }
}

class _ScoredTaskCandidate {
  const _ScoredTaskCandidate(this.candidate, this.score);

  final _TaskCommandCandidate candidate;
  final int score;
}

class _TaskCandidateSelection {
  const _TaskCandidateSelection({
    required this.matches,
    required this.allCandidates,
    this.queryError,
  });

  factory _TaskCandidateSelection.matches(
    List<_TaskCommandCandidate> matches,
    List<_TaskCommandCandidate> allCandidates,
  ) {
    return _TaskCandidateSelection(
      matches: matches,
      allCandidates: allCandidates,
    );
  }

  factory _TaskCandidateSelection.noMatch(
    List<_TaskCommandCandidate> allCandidates,
  ) {
    return _TaskCandidateSelection(
      matches: const <_TaskCommandCandidate>[],
      allCandidates: allCandidates,
    );
  }

  factory _TaskCandidateSelection.queryFailed(Map<String, dynamic>? error) {
    return _TaskCandidateSelection(
      matches: const <_TaskCommandCandidate>[],
      allCandidates: const <_TaskCommandCandidate>[],
      queryError: error,
    );
  }

  final List<_TaskCommandCandidate> matches;
  final List<_TaskCommandCandidate> allCandidates;
  final Map<String, dynamic>? queryError;

  bool get hasSingleMatch => matches.length == 1 && queryError == null;
}

enum _PendingTaskChoiceKind { updateTime, delete }

class _PendingTaskChoice {
  _PendingTaskChoice._({
    required this.kind,
    required this.candidates,
    required this.date,
    this.newTime,
  }) : createdAt = DateTime.now();

  factory _PendingTaskChoice.updateTime({
    required List<_TaskCommandCandidate> candidates,
    required _TimeMention newTime,
    required DateTime date,
  }) {
    return _PendingTaskChoice._(
      kind: _PendingTaskChoiceKind.updateTime,
      candidates: candidates,
      date: date,
      newTime: newTime,
    );
  }

  factory _PendingTaskChoice.delete({
    required List<_TaskCommandCandidate> candidates,
    required DateTime date,
  }) {
    return _PendingTaskChoice._(
      kind: _PendingTaskChoiceKind.delete,
      candidates: candidates,
      date: date,
    );
  }

  final _PendingTaskChoiceKind kind;
  final List<_TaskCommandCandidate> candidates;
  final DateTime date;
  final _TimeMention? newTime;
  final DateTime createdAt;

  bool get isFresh =>
      DateTime.now().difference(createdAt) <= _kRecentWriteContextWindow;
}

class _RecentConfirmedTask {
  const _RecentConfirmedTask({
    required this.id,
    required this.title,
    required this.updatedAt,
  });

  final int id;
  final String title;
  final DateTime updatedAt;

  bool get isFresh =>
      DateTime.now().difference(updatedAt) <= _kRecentWriteContextWindow;
}

class _VoiceCommandText {
  const _VoiceCommandText(this.text, {this.wakeWordOnly = false});

  final String text;
  final bool wakeWordOnly;
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
/// 3. 全局模式 `always`：只要有承载面（fullscreenAnswer / drawer）就播
/// 4. 全局模式 `shortOnly`：只在 fullscreenAnswer 上播
/// 5. 全局模式 `auto`（默认）：
///    - fullscreenAnswer → 播
///    - drawer → 看入口：drawerVoice / quickVoice 播；drawerText 不播
///    - none → 不播
bool decideAutoSpeak({
  required AssistantEntrySource entrySource,
  required AssistantReplySurface surface,
  required bool fullscreenAnswer,
  required TtsPlaybackMode mode,
  required AssistantSessionMute sessionMute,
}) {
  if (sessionMute == AssistantSessionMute.muted) return false;
  switch (mode) {
    case TtsPlaybackMode.silent:
      return false;
    case TtsPlaybackMode.always:
      return fullscreenAnswer || surface != AssistantReplySurface.none;
    case TtsPlaybackMode.shortOnly:
      return fullscreenAnswer;
    case TtsPlaybackMode.auto:
      if (fullscreenAnswer) {
        return true;
      }
      switch (surface) {
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
    case 'query_tasks':
      return '正在看你的日程';
    case 'create_task':
      return '正在整理日程';
    case 'update_task':
      return '正在准备调整日程';
    case 'delete_task':
      return '正在准备删除日程';
    case 'complete_task':
      return '正在标记完成';
  }
  return '正在调用 $name';
}

class _PublicRunInterruption implements Exception {
  const _PublicRunInterruption({
    this.message,
    this.keepPartialOutput = false,
    this.restartAsSummary = false,
    this.errorState,
  });

  const _PublicRunInterruption.message(
    String message, {
    bool keepPartialOutput = false,
  }) : this(message: message, keepPartialOutput: keepPartialOutput);

  const _PublicRunInterruption.restartSummary() : this(restartAsSummary: true);

  const _PublicRunInterruption.silent() : this();

  const _PublicRunInterruption.error(AssistantErrorState errorState)
    : this(errorState: errorState);

  final String? message;
  final bool keepPartialOutput;
  final bool restartAsSummary;
  final AssistantErrorState? errorState;
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
  if (error is VolcTtsException) {
    return error.message;
  }
  return error.toString();
}
