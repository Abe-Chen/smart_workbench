import 'assistant_state.dart';
import '../domain/assistant_result_card.dart';

export 'assistant_state.dart' show AnswerCardKind, AssistantSurfaceState;

enum AssistantEntrySource { drawerText, drawerVoice, quickVoice }

class AssistantSurfaceRouter {
  const AssistantSurfaceRouter();

  AssistantReplySurface resolve({
    required AssistantEntrySource entrySource,
    required bool drawerOpen,
  }) {
    return shouldUseDrawer(entrySource: entrySource, drawerOpen: drawerOpen)
        ? AssistantReplySurface.drawer
        : AssistantReplySurface.none;
  }

  bool shouldUseDrawer({
    required AssistantEntrySource entrySource,
    required bool drawerOpen,
  }) {
    if (drawerOpen) {
      return true;
    }
    return entrySource == AssistantEntrySource.drawerText ||
        entrySource == AssistantEntrySource.drawerVoice;
  }

  bool shouldUseFullscreenAnswer({
    required AssistantEntrySource entrySource,
    required bool drawerOpen,
  }) {
    return !shouldUseDrawer(entrySource: entrySource, drawerOpen: drawerOpen);
  }

  AnswerCardKind classifyAnswer({
    required AssistantUiState state,
    required AssistantDisplayContent content,
    required String text,
  }) {
    if (state.pendingConfirm != null) {
      return AnswerCardKind.confirm;
    }
    if (state.ttsError != null ||
        state.error != null ||
        state.errorState != null ||
        state.stage == AssistantStage.error) {
      return AnswerCardKind.error;
    }
    if (state.pendingWriteDraft != null && _looksLikeQuestion(text)) {
      return AnswerCardKind.clarification;
    }
    if (content.resultCard != null) {
      return AnswerCardKind.infoCard;
    }
    return AnswerCardKind.plainText;
  }
}

bool _looksLikeQuestion(String text) {
  final String normalized = text.trim();
  if (normalized.isEmpty) {
    return false;
  }
  return normalized.contains('?') ||
      normalized.contains('？') ||
      normalized.endsWith('吗') ||
      normalized.endsWith('呢');
}
