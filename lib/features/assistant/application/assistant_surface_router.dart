import 'assistant_state.dart';

enum AssistantEntrySource { drawerText, drawerVoice, quickVoice }

enum AssistantSurfaceState {
  none,
  topBannerListen,
  topBannerPush,
  fullscreenAnswer,
  drawerOpen,
}

enum AnswerCardKind {
  infoCard,
  toolFeedback,
  plainText,
  clarification,
  confirm,
  error,
  reminder,
}

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
}
