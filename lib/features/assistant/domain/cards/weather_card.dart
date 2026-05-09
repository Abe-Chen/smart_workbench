import '../assistant_result_card.dart';

class AssistantResultMetric {
  const AssistantResultMetric({required this.label, required this.value});

  final String label;
  final String value;
}

class AssistantResultTimelinePoint {
  const AssistantResultTimelinePoint({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;
}

class WeatherCard extends AssistantResultCard {
  const WeatherCard({
    required this.title,
    required this.subtitle,
    required this.summary,
    required this.headline,
    this.secondaryHeadline,
    this.metrics = const <AssistantResultMetric>[],
    this.timeline = const <AssistantResultTimelinePoint>[],
  });

  @override
  String get type => 'weather';

  @override
  final String summary;

  final String title;
  final String subtitle;
  final String headline;
  final String? secondaryHeadline;
  final List<AssistantResultMetric> metrics;
  final List<AssistantResultTimelinePoint> timeline;

  static WeatherCard? tryParse(Map<String, dynamic> json) {
    final String city = _readString(json['city']);
    final String condition = _readString(json['condition']);
    final String summary = _readString(json['summary']);
    final String currentTemp = _readString(json['currentTemp']);
    if (city.isEmpty ||
        condition.isEmpty ||
        summary.isEmpty ||
        currentTemp.isEmpty) {
      return null;
    }

    final List<AssistantResultMetric> metrics = <AssistantResultMetric>[
      if (_readString(json['humidity']).isNotEmpty)
        AssistantResultMetric(
          label: '湿度',
          value: _readString(json['humidity']),
        ),
      if (_readString(json['airQuality']).isNotEmpty)
        AssistantResultMetric(
          label: '空气',
          value: _readString(json['airQuality']),
        ),
      if (_readString(json['wind']).isNotEmpty)
        AssistantResultMetric(label: '风力', value: _readString(json['wind'])),
    ];

    final List<AssistantResultTimelinePoint> timeline =
        <AssistantResultTimelinePoint>[];
    final List<dynamic> rawTimeline =
        json['timeline'] as List<dynamic>? ?? <dynamic>[];
    for (final dynamic item in rawTimeline.take(4)) {
      if (item is! Map<String, dynamic>) continue;
      final String label = _readString(item['label']);
      final String value = _readString(item['value']);
      if (label.isEmpty || value.isEmpty) continue;
      timeline.add(AssistantResultTimelinePoint(label: label, value: value));
    }

    return WeatherCard(
      title: city,
      subtitle: condition,
      summary: summary,
      headline: currentTemp,
      secondaryHeadline: _readString(json['tempRange']),
      metrics: metrics,
      timeline: timeline,
    );
  }
}

String _readString(Object? value) {
  if (value == null) {
    return '';
  }
  if (value is String) {
    return value.trim();
  }
  return value.toString().trim();
}
