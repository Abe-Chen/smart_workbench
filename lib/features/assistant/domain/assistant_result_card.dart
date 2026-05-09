import 'dart:convert';

import 'cards/assistant_card_registry.dart';

export 'cards/weather_card.dart'
    show WeatherCard, AssistantResultMetric, AssistantResultTimelinePoint;
export 'cards/exchange_rate_card.dart' show ExchangeRateCard;
export 'cards/world_clock_card.dart' show WorldClockCard, WorldClockEntry;

abstract class AssistantResultCard {
  const AssistantResultCard();

  String get type;
  String get summary;
}

class AssistantDisplayContent {
  const AssistantDisplayContent({required this.text, this.resultCard});

  final String text;
  final AssistantResultCard? resultCard;
}

AssistantDisplayContent parseAssistantDisplayContent(String rawText) {
  final String normalized = rawText.trim();
  if (normalized.isEmpty) {
    return const AssistantDisplayContent(text: '');
  }

  final RegExpMatch? blockMatch = _assistantCardBlockPattern.firstMatch(
    normalized,
  );
  if (blockMatch == null) {
    return AssistantDisplayContent(text: normalized);
  }

  final String cardType = (blockMatch.group(1) ?? '').trim();
  final String cardJson = (blockMatch.group(2) ?? '').trim();
  final String visibleText = normalized
      .replaceRange(blockMatch.start, blockMatch.end, '')
      .trim();

  final AssistantResultCard? resultCard = _decodeAssistantCard(
    type: cardType,
    rawJson: cardJson,
  );
  if (resultCard == null) {
    return AssistantDisplayContent(
      text: visibleText.isEmpty ? normalized : visibleText,
    );
  }

  return AssistantDisplayContent(
    text: visibleText.isEmpty ? resultCard.summary : visibleText,
    resultCard: resultCard,
  );
}

final RegExp _assistantCardBlockPattern = RegExp(
  r'<assistant-card\s+type="([^"]+)">([\s\S]*?)</assistant-card>',
);

AssistantResultCard? _decodeAssistantCard({
  required String type,
  required String rawJson,
}) {
  if (type.isEmpty || rawJson.isEmpty) {
    return null;
  }
  try {
    final Object? decoded = jsonDecode(rawJson);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    return AssistantCardRegistry.parse(type: type, json: decoded);
  } catch (_) {
    return null;
  }
}
