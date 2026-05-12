enum AssistantSpeechMode { digest, full }

const int _kDigestMaxChars = 220;

String buildAssistantSpeechText(
  String text, {
  AssistantSpeechMode mode = AssistantSpeechMode.digest,
}) {
  final String normalized = normalizeAssistantSpeechText(text);
  if (normalized.isEmpty || mode == AssistantSpeechMode.full) {
    return normalized;
  }

  final int? firstSentenceEnd = _findSentenceEnd(
    normalized,
    maxIndex: _kDigestMaxChars,
  );
  if (firstSentenceEnd != null && firstSentenceEnd >= 12) {
    return normalized.substring(0, firstSentenceEnd).trim();
  }

  if (normalized.length <= _kDigestMaxChars) {
    return normalized;
  }
  return '${_clipAtNaturalBoundary(normalized, _kDigestMaxChars)}...';
}

String normalizeAssistantSpeechText(String text) {
  String normalized = text
      .replaceAll(_assistantCardBlockPattern, ' ')
      .replaceAll(_fencedCodeBlockPattern, ' ');
  normalized = normalized.replaceAllMapped(_numberedListPattern, (Match match) {
    return '${match.group(1) ?? ''}第${match.group(2) ?? ''}条，';
  });
  normalized = normalized
      .replaceAll(_markdownBulletPattern, '')
      .replaceAll(RegExp(r'[`*_#>]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return normalized;
}

bool isAssistantFullReadoutRequest(String text) {
  final String normalized = text.replaceAll(RegExp(r'\s+'), '');
  if (normalized.isEmpty) {
    return false;
  }
  return RegExp(r'(全部|完整|全文|全量|从头|详细).*(播报|朗读|读|念)').hasMatch(normalized) ||
      RegExp(r'(播报|朗读|读|念).*(全部|完整|全文|全量|一遍)').hasMatch(normalized) ||
      RegExp(r'(继续|接着).*(播报|朗读|读|念)').hasMatch(normalized) ||
      RegExp(r'(读完|播完|念完)').hasMatch(normalized) ||
      RegExp(r'(再|重新).*(播报|朗读|读|念).*一遍').hasMatch(normalized);
}

final RegExp _assistantCardBlockPattern = RegExp(
  r'<assistant-card\s+type="[^"]+">[\s\S]*?</assistant-card>',
);

final RegExp _fencedCodeBlockPattern = RegExp(r'```[\s\S]*?```');

final RegExp _numberedListPattern = RegExp(
  r'(^|[\s\r\n:：;；。！？!?])(\d{1,2})[\.．、)]\s*(?=\S)',
);

final RegExp _markdownBulletPattern = RegExp(r'^\s*[-*+]\s+', multiLine: true);

int? _findSentenceEnd(String text, {required int maxIndex}) {
  final int end = maxIndex.clamp(0, text.length);
  for (int i = 0; i < end; i++) {
    final String ch = text[i];
    if (ch == '。' || ch == '！' || ch == '？' || ch == '!' || ch == '?') {
      return i + 1;
    }
    if (ch == '.') {
      final String previous = i == 0 ? '' : text[i - 1];
      final String next = i + 1 >= text.length ? '' : text[i + 1];
      if (!_isAsciiDigit(previous) && (next.isEmpty || next.trim().isEmpty)) {
        return i + 1;
      }
    }
  }
  return null;
}

String _clipAtNaturalBoundary(String text, int maxChars) {
  if (text.length <= maxChars) {
    return text.trim();
  }
  final int lowerBound = (maxChars - 80).clamp(0, maxChars);
  for (int i = maxChars; i > lowerBound; i--) {
    final String ch = text[i - 1];
    if ('。！？!?；;，,、'.contains(ch)) {
      return text.substring(0, i).trim();
    }
  }
  return text.substring(0, maxChars).trim();
}

bool _isAsciiDigit(String ch) {
  if (ch.isEmpty) {
    return false;
  }
  final int code = ch.codeUnitAt(0);
  return code >= 0x30 && code <= 0x39;
}
