import 'assistant_state.dart';
import '../domain/assistant_result_card.dart';

export 'assistant_state.dart' show AnswerCardKind, AssistantSurfaceState;

enum AssistantEntrySource { drawerText, drawerVoice, quickVoice }

class LegacySurfaceRouter {
  const LegacySurfaceRouter();

  AssistantReplySurface resolve({
    required String text,
    required AssistantEntrySource entrySource,
  }) {
    switch (entrySource) {
      case AssistantEntrySource.drawerText:
      case AssistantEntrySource.drawerVoice:
        return AssistantReplySurface.drawer;
      case AssistantEntrySource.quickVoice:
        return shouldUseCompactCard(text)
            ? AssistantReplySurface.compactCard
            : AssistantReplySurface.drawer;
    }
  }

  bool shouldUseCompactCard(String text) {
    final String normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) {
      return false;
    }

    final int sentenceCount = RegExp(
      r'[。！？!?\.]',
    ).allMatches(normalized).length;
    if (sentenceCount > 2) {
      return false;
    }
    if (normalized.length <= 72) {
      return true;
    }
    return sentenceCount > 0 && normalized.length <= 120;
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

  bool shouldUseFullscreenAnswer(AssistantEntrySource entrySource) {
    return entrySource == AssistantEntrySource.quickVoice;
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
