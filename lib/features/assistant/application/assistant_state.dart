import '../domain/assistant_message.dart';
import '../domain/assistant_result_card.dart';

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

class AssistantProgressState {
  const AssistantProgressState({this.status, this.steps = const <String>[]});

  final String? status;
  final List<String> steps;
}

class AssistantUiState {
  const AssistantUiState({
    required this.drawerOpen,
    required this.stage,
    required this.messages,
    required this.replySurface,
    this.error,
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

  AssistantUiState copyWith({
    bool? drawerOpen,
    AssistantStage? stage,
    List<AssistantMessage>? messages,
    AssistantReplySurface? replySurface,
    String? error,
    bool clearError = false,
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
  }) {
    return AssistantUiState(
      drawerOpen: drawerOpen ?? this.drawerOpen,
      stage: stage ?? this.stage,
      messages: messages ?? this.messages,
      replySurface: replySurface ?? this.replySurface,
      error: clearError ? null : (error ?? this.error),
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
    );
  }
}
