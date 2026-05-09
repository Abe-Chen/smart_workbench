import 'package:flutter/material.dart';

import '../../domain/assistant_result_card.dart';
import 'cards/exchange_rate_card_view.dart';
import 'cards/weather_card_view.dart';
import 'cards/world_clock_card_view.dart';

class AssistantResultCardView extends StatelessWidget {
  const AssistantResultCardView({
    required this.card,
    this.compact = false,
    super.key,
  });

  final AssistantResultCard card;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AssistantResultCard c = card;
    if (c is WeatherCard) {
      return WeatherCardView(card: c, compact: compact);
    }
    if (c is ExchangeRateCard) {
      return ExchangeRateCardView(card: c, compact: compact);
    }
    if (c is WorldClockCard) {
      return WorldClockCardView(card: c, compact: compact);
    }
    return const SizedBox.shrink();
  }
}
