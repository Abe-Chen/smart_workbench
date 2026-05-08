import '../domain/assistant_execution_mode.dart';
import '../domain/assistant_confirm_preview.dart';
import '../domain/assistant_message.dart';
import '../domain/assistant_result_card.dart';
import '../domain/tool_call.dart';

/// 小治状态机。W1 暂时只用 idle / think / answer / error；
/// listen 留给 W2 接 ASR；confirm 留给 W3 接日程操作。
enum AssistantStage { idle, listen, think, answer, confirm, error }

enum AssistantReplySurface { none, compactCard, drawer }

enum AssistantListeningMode { openMic, pressToTalk }

/// 当前对话会话级的播报覆盖。
/// - [followSettings]：默认。按全局 `TtsPlaybackMode` 决策。
/// - [muted]：本会话内强制静音，但**不写入** [AppSettings]，仅本对话生效。
///
/// 抽屉头部有 toggle 按钮切换。clearConversation 会重置回 followSettings。
enum AssistantSessionMute { followSettings, muted }

enum AssistantWriteDraftKind { schedule, reminder }

/// 创建类写入的多轮草稿。
///
/// 用户只说“创建一个日程”时先保存草稿，后续“明天下午 3 点需求讨论会”
/// 会继续补齐这个对象，字段完整后再进入 confirm。
class AssistantPendingWriteDraft {
  const AssistantPendingWriteDraft({
    required this.kind,
    this.title,
    this.startDate,
    this.startTimeMinutes,
  });

  final AssistantWriteDraftKind kind;
  final String? title;
  final DateTime? startDate;
  final int? startTimeMinutes;

  bool get isComplete =>
      title != null &&
      title!.trim().isNotEmpty &&
      startDate != null &&
      startTimeMinutes != null;

  AssistantPendingWriteDraft copyWith({
    String? title,
    bool clearTitle = false,
    DateTime? startDate,
    bool clearStartDate = false,
    int? startTimeMinutes,
    bool clearStartTimeMinutes = false,
  }) {
    return AssistantPendingWriteDraft(
      kind: kind,
      title: clearTitle ? null : (title ?? this.title),
      startDate: clearStartDate ? null : (startDate ?? this.startDate),
      startTimeMinutes: clearStartTimeMinutes
          ? null
          : (startTimeMinutes ?? this.startTimeMinutes),
    );
  }
}

/// 写入工具触发 confirm 时暂存的待执行 tool_call。
class AssistantPendingConfirm {
  const AssistantPendingConfirm({
    required this.toolCall,
    required this.preview,
    this.resumeConversationAfterConfirm = true,
  });

  /// 模型生成的待执行 tool_call（含 id / name / args）。
  final ToolCall toolCall;

  /// 由 [AssistantTool.buildConfirmPreview] 构造的渲染数据。
  final AssistantConfirmPreview preview;

  /// true：模型发起的 tool_call，确认后必须回填 tool result 并继续模型循环。
  /// false：App 草稿生成的确定性 tool_call，确认后由 App 直接渲染结果。
  final bool resumeConversationAfterConfirm;
}

/// complete_task 执行后的撤销提示数据。
/// UI 端 watch 这个字段变化弹 SnackBar，5 秒倒计时。
class AssistantCompletionUndo {
  const AssistantCompletionUndo({
    required this.taskId,
    required this.occurrenceDate,
    required this.title,
    required this.expireAtMillis,
  });

  final int taskId;
  final DateTime occurrenceDate;
  final String title;

  /// 撤销窗口截止时间戳（毫秒）。UI 端用 (expireAtMillis - now).clamp(0, 5000) 算倒计时。
  final int expireAtMillis;
}

class AssistantProgressState {
  const AssistantProgressState({
    this.mode,
    this.phase,
    this.status,
    this.statusOrigin = AssistantProgressOrigin.uxHint,
    this.detail,
    this.detailOrigin,
    this.steps = const <String>[],
    this.requestId,
    this.startedAtMillis,
    this.elapsedMs = 0,
    this.hasStartedOutput = false,
    this.canStop = false,
    this.canCancelTask = false,
    this.canAskForSummary = false,
  });

  final AssistantExecutionMode? mode;
  final AssistantProgressPhase? phase;
  final String? status;
  final AssistantProgressOrigin statusOrigin;
  final String? detail;
  final AssistantProgressOrigin? detailOrigin;
  final List<String> steps;
  final String? requestId;
  final int? startedAtMillis;
  final int elapsedMs;
  final bool hasStartedOutput;
  final bool canStop;
  final bool canCancelTask;
  final bool canAskForSummary;
}

enum AssistantProgressOrigin { realEvent, uxHint }

enum AssistantProgressPhase {
  routing,
  preparingContext,
  requestAccepted,
  searching,
  receiving,
  summarizing,
  awaitingConfirm,
  executing,
  completed,
  cancelled,
  failed,
}

enum AssistantErrorType {
  configMissing,
  networkUnavailable,
  connectionTimeout,
  sendTimeout,
  firstEventTimeout,
  streamStalled,
  unauthorized,
  rateLimited,
  serverRejected,
  cancelledByUser,
  emptyResponse,
  parseError,
  unknown,
}

class AssistantErrorState {
  const AssistantErrorState({
    required this.type,
    required this.message,
    this.retryable = true,
  });

  final AssistantErrorType type;
  final String message;
  final bool retryable;
}

class AssistantUiState {
  const AssistantUiState({
    required this.drawerOpen,
    required this.stage,
    required this.messages,
    required this.replySurface,
    this.error,
    this.errorState,
    this.listenPartialText = '',
    this.listenError,
    this.ttsError,
    this.compactReplyText,
    this.compactReplyCard,
    this.listeningMode = AssistantListeningMode.openMic,
    this.listenWindowRemainingMs = 0,
    this.followUpRemainingMs = 0,
    this.progress = const AssistantProgressState(),
    this.sessionMute = AssistantSessionMute.followSettings,
    this.pendingWriteDraft,
    this.pendingConfirm,
    this.completionUndo,
  });

  factory AssistantUiState.initial() => const AssistantUiState(
    drawerOpen: false,
    stage: AssistantStage.idle,
    messages: <AssistantMessage>[],
    replySurface: AssistantReplySurface.none,
  );

  final bool drawerOpen;
  final AssistantStage stage;
  final List<AssistantMessage> messages;
  final AssistantReplySurface replySurface;
  final String? error;
  final AssistantErrorState? errorState;

  /// 听音态下的实时转写文字（给屏幕底部胶囊条显示）。
  final String listenPartialText;

  /// 听音态下的错误信息（如权限拒绝、网络错）。
  final String? listenError;

  /// TTS 播报错误。与 [listenError] 分离，避免 UX 文案混淆。
  final String? ttsError;

  final String? compactReplyText;

  final AssistantResultCard? compactReplyCard;

  final AssistantListeningMode listeningMode;

  final int listenWindowRemainingMs;

  final int followUpRemainingMs;

  final AssistantProgressState progress;

  /// 本会话级的播报覆盖。clearConversation 重置。
  final AssistantSessionMute sessionMute;

  /// 创建类写入的多轮草稿。
  final AssistantPendingWriteDraft? pendingWriteDraft;

  /// 写入工具等待确认时暂存的 tool_call 与渲染预览。
  /// 非 null 时进入 [AssistantStage.confirm]，UI 渲染 ConfirmCard。
  final AssistantPendingConfirm? pendingConfirm;

  /// complete_task 执行后的撤销提示数据。
  /// 非 null 时 UI 弹 SnackBar，撤销窗口过期或用户主动 dismiss 后置 null。
  final AssistantCompletionUndo? completionUndo;

  AssistantUiState copyWith({
    bool? drawerOpen,
    AssistantStage? stage,
    List<AssistantMessage>? messages,
    AssistantReplySurface? replySurface,
    String? error,
    bool clearError = false,
    AssistantErrorState? errorState,
    bool clearErrorState = false,
    String? listenPartialText,
    String? listenError,
    bool clearListenError = false,
    String? ttsError,
    bool clearTtsError = false,
    String? compactReplyText,
    AssistantResultCard? compactReplyCard,
    bool clearCompactReply = false,
    AssistantListeningMode? listeningMode,
    int? listenWindowRemainingMs,
    int? followUpRemainingMs,
    AssistantProgressState? progress,
    bool clearProgress = false,
    AssistantSessionMute? sessionMute,
    AssistantPendingWriteDraft? pendingWriteDraft,
    bool clearPendingWriteDraft = false,
    AssistantPendingConfirm? pendingConfirm,
    bool clearPendingConfirm = false,
    AssistantCompletionUndo? completionUndo,
    bool clearCompletionUndo = false,
  }) {
    return AssistantUiState(
      drawerOpen: drawerOpen ?? this.drawerOpen,
      stage: stage ?? this.stage,
      messages: messages ?? this.messages,
      replySurface: replySurface ?? this.replySurface,
      error: clearError ? null : (error ?? this.error),
      errorState: clearErrorState ? null : (errorState ?? this.errorState),
      listenPartialText: listenPartialText ?? this.listenPartialText,
      listenError: clearListenError ? null : (listenError ?? this.listenError),
      ttsError: clearTtsError ? null : (ttsError ?? this.ttsError),
      compactReplyText: clearCompactReply
          ? null
          : (compactReplyText ?? this.compactReplyText),
      compactReplyCard: clearCompactReply
          ? null
          : (compactReplyCard ?? this.compactReplyCard),
      listeningMode: listeningMode ?? this.listeningMode,
      listenWindowRemainingMs:
          listenWindowRemainingMs ?? this.listenWindowRemainingMs,
      followUpRemainingMs: followUpRemainingMs ?? this.followUpRemainingMs,
      progress: clearProgress
          ? const AssistantProgressState()
          : (progress ?? this.progress),
      sessionMute: sessionMute ?? this.sessionMute,
      pendingWriteDraft: clearPendingWriteDraft
          ? null
          : (pendingWriteDraft ?? this.pendingWriteDraft),
      pendingConfirm: clearPendingConfirm
          ? null
          : (pendingConfirm ?? this.pendingConfirm),
      completionUndo: clearCompletionUndo
          ? null
          : (completionUndo ?? this.completionUndo),
    );
  }
}
