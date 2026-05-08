import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_providers.dart';
import '../../../core/identity/device_id.dart';
import '../../../core/location/location_repository.dart';
import '../../../core/utils/calendar_utils.dart';
import '../../../core/voice/pcm_stream_recorder.dart';
import '../../task/application/task_providers.dart';
import '../../task/domain/task.dart';
import '../data/doubao_chat_client.dart';
import '../data/doubao_responses_client.dart';
import '../data/xunfei_asr_client.dart';
import '../data/xunfei_tts_client.dart';
import '../domain/assistant_execution_mode.dart';
import '../../settings/application/app_settings_controller.dart';
import '../../settings/domain/app_settings.dart';
import '../domain/assistant_confirm_preview.dart';
import '../domain/assistant_intent.dart';
import '../domain/assistant_message.dart';
import '../domain/assistant_result_card.dart';
import '../domain/assistant_tool.dart';
import '../domain/tool_call.dart';
import '../prompts/system_prompt.dart';
import 'assistant_copywriter.dart';
import 'assistant_request_router.dart';
import 'assistant_state.dart';
import 'tool_registry.dart';

const int _kMaxToolRounds = 4;
const Duration _kOpenMicWait = Duration(seconds: 8);
const Duration _kFollowUpWindow = Duration(seconds: 5);
const Duration _kCompletionUndoWindow = Duration(seconds: 5);
const Duration _kRecentWriteContextWindow = Duration(minutes: 5);

enum AssistantEntrySource { drawerText, drawerVoice, quickVoice }

enum _PendingConfirmInputAction { confirm, cancel, unknown }

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
  Timer? _followUpExpireTimer;
  Timer? _followUpTicker;

  AssistantEntrySource _lastEntrySource = AssistantEntrySource.drawerText;
  String? _lastPublicResponseId;
  AssistantIntent? _activeLocalIntent;
  _RecentConfirmedTask? _lastConfirmedTask;
  _PendingTaskChoice? _pendingTaskChoice;

  @override
  AssistantUiState build() {
    ref.onDispose(() {
      _aborted = true;
      _streamSub?.cancel();
      _cancelActivePublicRequest();
      _stopPublicProgressTracking();
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
    if (state.pendingConfirm != null) {
      await _handlePendingConfirmInput(trimmed, source: source);
      return;
    }
    if (state.stage == AssistantStage.think ||
        state.stage == AssistantStage.answer) {
      return;
    }
    _cancelFollowUpWindow();
    _lastEntrySource = source;
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
      clearErrorState: true,
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
      state = state.copyWith(
        stage: AssistantStage.error,
        error: message,
        clearProgress: true,
      );
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
        await _tryUpdatePendingConfirmReminder(text, pending)) {
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
          state = state.copyWith(
            error: _copywriter.pendingConfirmUnknown(pending),
          );
        } else {
          _appendAssistantPlaceholder();
          _finishLocalWriteText(_copywriter.pendingConfirmUnknown(pending));
          state = state.copyWith(stage: AssistantStage.confirm);
        }
        break;
    }
  }

  Future<bool> _tryUpdatePendingConfirmReminder(
    String text,
    AssistantPendingConfirm pending,
  ) async {
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
    _replaceTrailingAssistant(
      content: reminderKey == TaskReminderKey.none
          ? '我改成不提醒了。你确认一下，没问题我再执行。'
          : '我加上${_reminderShortLabel(reminderKey)}了。你确认一下，没问题我再执行。',
      streaming: false,
    );
    state = state.copyWith(
      stage: AssistantStage.confirm,
      pendingConfirm: AssistantPendingConfirm(
        toolCall: nextCall,
        preview: preview,
        resumeConversationAfterConfirm: pending.resumeConversationAfterConfirm,
      ),
      progress: const AssistantProgressState(
        mode: AssistantExecutionMode.local,
        phase: AssistantProgressPhase.awaitingConfirm,
        status: '等你确认',
        statusOrigin: AssistantProgressOrigin.uxHint,
      ),
    );
    return true;
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

    final int? selectedIndex = _parseChoiceIndex(text);
    if (selectedIndex == null) {
      if (_looksLikeChoiceReply(text)) {
        _beginLocalTaskTurn(text, source: source, status: '正在确认选择');
        _finishLocalWriteText('我刚才列了几个候选项。你可以说“第一条”或“第二条”。');
        return true;
      }
      _pendingTaskChoice = null;
      return false;
    }

    if (selectedIndex < 0 || selectedIndex >= pending.candidates.length) {
      _beginLocalTaskTurn(text, source: source, status: '正在确认选择');
      _finishLocalWriteText(
        '刚才只有 ${pending.candidates.length} 条候选项。你可以重新说“第一条”或“第二条”。',
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
      );
      _finishLocalWriteText(_candidateSelectionMessage(selection, date));
      return;
    }
    if (!selection.hasSingleMatch) {
      _pendingTaskChoice = null;
      _finishLocalWriteText(_candidateSelectionMessage(selection, date));
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
      message: '我找到了「${candidate.title}」。确认后把时间改到${_timeLabel(newStart)}。',
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
      );
      _finishLocalWriteText(_candidateSelectionMessage(selection, date));
      return;
    }
    if (!selection.hasSingleMatch) {
      _pendingTaskChoice = null;
      _finishLocalWriteText(_candidateSelectionMessage(selection, date));
      return;
    }

    _pendingTaskChoice = null;
    final _TaskCommandCandidate candidate = selection.matches.single;
    await _enterConfirmForDeterministicTool(
      toolName: 'delete_task',
      args: <String, dynamic>{'task_id': candidate.id},
      message: '我找到了「${candidate.title}」。确认后我再删除。',
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
      message: reminderKey == TaskReminderKey.none
          ? '我准备把「${recent.title}」改成不提醒。'
          : '我准备给「${recent.title}」加上${_reminderShortLabel(reminderKey)}。',
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

  String _candidateSelectionMessage(
    _TaskCandidateSelection selection,
    DateTime date,
  ) {
    if (selection.queryError != null) {
      final String reason =
          (selection.queryError?['reason'] as Object?)?.toString() ?? '查询失败';
      return '这次没查到本地安排：$reason。你可以稍后再试。';
    }
    final String day = _dateLabel(date);
    if (selection.matches.length > 1) {
      return '我找到几条都像是你说的安排。你要操作哪一个？\n${_candidateListText(selection.matches)}';
    }
    if (selection.allCandidates.isEmpty) {
      return '我没找到$day的安排。你可以确认一下日期或时间。';
    }
    return '我没找到匹配的那条安排。$day已有：\n${_candidateListText(selection.allCandidates)}';
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
      _finishLocalWriteText('这次没法执行：本地工具不可用。');
      return;
    }
    final AssistantConfirmPreview? preview = await tool.buildConfirmPreview(
      args,
    );
    if (preview == null) {
      _finishLocalWriteText('这次没识别清楚，先不执行。你可以换个说法再试。');
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
          message:
              '好的，我选了「${candidate.title}」。确认后把时间改到${_timeLabel(newStart)}。',
        );
        break;
      case _PendingTaskChoiceKind.delete:
        await _enterConfirmForDeterministicTool(
          toolName: 'delete_task',
          args: <String, dynamic>{'task_id': candidate.id},
          message: '好的，我选了「${candidate.title}」。确认后我再删除。',
        );
        break;
    }
  }

  _PendingConfirmInputAction _parsePendingConfirmInput(String text) {
    final String normalized = text.trim().replaceAll(RegExp(r'[，。！？\s]'), '');
    if (normalized.isEmpty) {
      return _PendingConfirmInputAction.unknown;
    }
    if (_confirmInputPattern.hasMatch(normalized)) {
      return _PendingConfirmInputAction.confirm;
    }
    if (_cancelInputPattern.hasMatch(normalized)) {
      return _PendingConfirmInputAction.cancel;
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

  Future<void> _handlePendingWriteDraftInput(
    String text, {
    required AssistantEntrySource source,
  }) async {
    final AssistantPendingWriteDraft current = state.pendingWriteDraft!;
    if (_cancelInputPattern.hasMatch(text.trim())) {
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
      _finishLocalWriteText(_missingDraftPrompt(draft));
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
    state = state.copyWith(
      drawerOpen: true,
      stage: AssistantStage.think,
      messages: <AssistantMessage>[...state.messages, userMsg, placeholder],
      replySurface: AssistantReplySurface.drawer,
      clearCompactReply: true,
      clearError: true,
      clearErrorState: true,
      progress: AssistantProgressState(
        mode: AssistantExecutionMode.local,
        phase: AssistantProgressPhase.routing,
        status: status,
        statusOrigin: AssistantProgressOrigin.uxHint,
      ),
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

  void _finishLocalWriteText(String text) {
    _finishAssistantTurn(text);
    state = state.copyWith(
      drawerOpen: true,
      replySurface: AssistantReplySurface.drawer,
      clearCompactReply: true,
    );
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
      state = state.copyWith(
        stage: AssistantStage.error,
        error: errorState.message,
        errorState: errorState,
        clearProgress: true,
      );
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
      state = state.copyWith(
        stage: AssistantStage.error,
        error: errorState.message,
        errorState: errorState,
        clearProgress: true,
      );
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
      state = state.copyWith(
        stage: AssistantStage.error,
        error: errorState.message,
        errorState: errorState,
        clearProgress: true,
      );
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
          _finishAssistantTurn(
            '这次还没有真正执行。请重新说一遍要创建、修改或删除的内容，我会先给你确认卡，确认后才会写入。',
          );
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
            title: '准备执行 ${call.name}（预览失败）',
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
    state = state.copyWith(
      stage: AssistantStage.confirm,
      drawerOpen: true,
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
        clearProgress: true,
      );
      return;
    }
    state = state.copyWith(
      stage: AssistantStage.think,
      clearPendingConfirm: true,
      progress: const AssistantProgressState(
        mode: AssistantExecutionMode.local,
        phase: AssistantProgressPhase.executing,
        status: '正在执行',
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
      _rememberConfirmedTask(pending, _tryDecodeJsonMap(result));
      _appendAssistantPlaceholder();
      _finishLocalWriteText(
        _copywriter.confirmedWriteResult(
          pending: pending,
          result: _tryDecodeJsonMap(result),
        ),
      );
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
    );
    _appendAssistantPlaceholder();
    _finishLocalWriteText(message);
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
      state = state.copyWith(
        stage: AssistantStage.error,
        error: message,
        clearProgress: true,
      );
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
    _teardownVoice();
    _lastPublicResponseId = null;
    _lastPublicMode = null;
    _activeLocalIntent = null;
    _lastConfirmedTask = null;
    _pendingTaskChoice = null;
    // sessionMute / pendingWriteDraft / pendingConfirm / completionUndo 都跟随会话生命周期重置。
    state = AssistantUiState.initial().copyWith(
      drawerOpen: state.drawerOpen,
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
    final bool hasPendingConfirm = state.pendingConfirm != null;
    await ref.read(xunfeiTtsClientProvider).stop();
    _cancelFollowUpWindow();
    _cancelOpenMicWait();
    _listeningSource = source;
    state = state.copyWith(
      drawerOpen: hasPendingConfirm ? true : openDrawer,
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
        .speak(speakText, voice: voice, xunfeiSpeed: xunfeiSpeedForRate(rate))
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
      clearErrorState: true,
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
  if (minute == 0) return '$period$displayHour 点';
  if (minute == 30) return '$period$displayHour 点半';
  return '$period$displayHour 点 $minute 分';
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

final RegExp _confirmInputPattern = RegExp(
  r'^(确认|可以|好|好的|对|是|没错|执行|创建|确定|行|嗯|嗯嗯)$',
);
final RegExp _cancelInputPattern = RegExp(
  r'^(取消|不用|不用了|算了|先不|先不用|不要|别|撤销|放弃)$',
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
    this.newTime,
  }) : createdAt = DateTime.now();

  factory _PendingTaskChoice.updateTime({
    required List<_TaskCommandCandidate> candidates,
    required _TimeMention newTime,
  }) {
    return _PendingTaskChoice._(
      kind: _PendingTaskChoiceKind.updateTime,
      candidates: candidates,
      newTime: newTime,
    );
  }

  factory _PendingTaskChoice.delete({
    required List<_TaskCommandCandidate> candidates,
  }) {
    return _PendingTaskChoice._(
      kind: _PendingTaskChoiceKind.delete,
      candidates: candidates,
    );
  }

  final _PendingTaskChoiceKind kind;
  final List<_TaskCommandCandidate> candidates;
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
    case 'query_tasks':
      return '正在查本地任务';
    case 'create_task':
      return '正在准备创建任务';
    case 'update_task':
      return '正在准备修改任务';
    case 'delete_task':
      return '正在准备删除任务';
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
  return error.toString();
}
