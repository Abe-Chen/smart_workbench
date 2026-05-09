import '../assistant_result_card.dart';

typedef AssistantCardParser =
    AssistantResultCard? Function(Map<String, dynamic> json);

class AssistantCardRegistry {
  AssistantCardRegistry._();

  static final Map<String, AssistantCardParser> _parsers =
      <String, AssistantCardParser>{
        'weather': WeatherCard.tryParse,
        'exchange_rate': ExchangeRateCard.tryParse,
      };

  static AssistantResultCard? parse({
    required String type,
    required Map<String, dynamic> json,
  }) {
    final AssistantCardParser? parser = _parsers[type];
    return parser?.call(json);
  }
}
