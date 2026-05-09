import 'package:flutter/material.dart';

import '../../../domain/assistant_result_card.dart';
import 'base_assistant_card.dart';
import 'card_theme.dart';

class WeatherCardView extends StatelessWidget {
  const WeatherCardView({required this.card, this.compact = false, super.key});

  final WeatherCard card;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final CardThemeToken theme = _themeFromCondition(card.subtitle);
    final List<AssistantResultMetric> displayMetrics =
        compact ? const <AssistantResultMetric>[] : _filterMetrics(card.metrics);
    final bool showTimeline = !compact && card.timeline.isNotEmpty;
    final Widget? body = (displayMetrics.isNotEmpty || showTimeline)
        ? _WeatherBody(
            theme: theme,
            metrics: displayMetrics,
            timeline: showTimeline
                ? card.timeline
                : const <AssistantResultTimelinePoint>[],
          )
        : null;

    return BaseAssistantCard(
      compact: compact,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: theme.gradient,
        ),
        border: Border.all(color: theme.borderColor),
      ),
      hero: _WeatherHero(card: card, theme: theme, compact: compact),
      body: body,
      footer: _WeatherFooter(card: card, theme: theme, compact: compact),
    );
  }
}

class _WeatherHero extends StatelessWidget {
  const _WeatherHero({
    required this.card,
    required this.theme,
    required this.compact,
  });

  final WeatherCard card;
  final CardThemeToken theme;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final double iconBoxSize = compact ? 44 : 56;
    final double iconSize = compact ? 24 : 32;
    final double tempFontSize = compact ? 36 : 56;
    final double rangeFontSize = compact ? 14 : 18;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: iconBoxSize,
              height: iconBoxSize,
              decoration: BoxDecoration(
                color: theme.iconBackgroundColor,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Icon(
                _iconForWeather(card.subtitle),
                color: theme.iconForegroundColor,
                size: iconSize,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    card.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.heroTextColor,
                      fontSize: compact ? 15 : 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    card.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.bodyTextColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? 10 : 14),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 12,
          runSpacing: 6,
          children: <Widget>[
            Text(
              card.headline,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.heroTextColor,
                fontSize: tempFontSize,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
            if ((card.secondaryHeadline ?? '').trim().isNotEmpty)
              Padding(
                padding: EdgeInsets.only(bottom: compact ? 4 : 6),
                child: Text(
                  card.secondaryHeadline!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.bodyTextColor,
                    fontSize: rangeFontSize,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _WeatherBody extends StatelessWidget {
  const _WeatherBody({
    required this.theme,
    required this.metrics,
    required this.timeline,
  });

  final CardThemeToken theme;
  final List<AssistantResultMetric> metrics;
  final List<AssistantResultTimelinePoint> timeline;

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = <Widget>[];
    if (metrics.isNotEmpty) {
      children.add(
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: metrics
              .map(
                (AssistantResultMetric metric) =>
                    _MetricChip(metric: metric, theme: theme),
              )
              .toList(),
        ),
      );
    }
    if (timeline.isNotEmpty) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: 12));
      }
      children
        ..add(
          Text(
            '接下来',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: theme.bodyTextColor,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        )
        ..add(const SizedBox(height: 8))
        ..add(
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: timeline
                .map(
                  (AssistantResultTimelinePoint point) =>
                      _TimelineChip(point: point, theme: theme),
                )
                .toList(),
          ),
        );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _WeatherFooter extends StatelessWidget {
  const _WeatherFooter({
    required this.card,
    required this.theme,
    required this.compact,
  });

  final WeatherCard card;
  final CardThemeToken theme;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Text(
      card.summary,
      maxLines: compact ? 2 : 3,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: theme.bodyTextColor,
        fontSize: compact ? 13 : 14,
        fontWeight: FontWeight.w600,
        height: 1.45,
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.metric, required this.theme});

  final AssistantResultMetric metric;
  final CardThemeToken theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      decoration: BoxDecoration(
        color: theme.chipBackgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: RichText(
        text: TextSpan(
          children: <InlineSpan>[
            TextSpan(
              text: '${metric.label} ',
              style: TextStyle(
                color: theme.bodyTextColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: metric.value,
              style: TextStyle(
                color: theme.heroTextColor,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _TimelineChip extends StatelessWidget {
  const _TimelineChip({required this.point, required this.theme});

  final AssistantResultTimelinePoint point;
  final CardThemeToken theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: theme.chipBackgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.chipBorderColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            point.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: theme.bodyTextColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            point.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: theme.heroTextColor,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

CardThemeToken _themeFromCondition(String condition) {
  if (condition.contains('雨') || condition.contains('雷')) {
    return CardThemeToken.rainy;
  }
  if (condition.contains('雪')) {
    return CardThemeToken.snowy;
  }
  if (condition.contains('晴')) {
    return CardThemeToken.sunny;
  }
  return CardThemeToken.cloudy;
}

/// 按需触发：天气正常时不显示湿度/空气/风力，避免信息冗余。
List<AssistantResultMetric> _filterMetrics(List<AssistantResultMetric> raw) {
  return raw.where(_shouldShowMetric).toList();
}

bool _shouldShowMetric(AssistantResultMetric m) {
  switch (m.label) {
    case '湿度':
      final int? n = _extractInt(m.value);
      if (n == null) return false;
      return n > 70 || n < 30;
    case '空气':
      final int? aqi = _extractInt(m.value);
      if (aqi == null) return false;
      return aqi > 100;
    case '风力':
      final int? lvl = _extractInt(m.value);
      if (lvl == null) return false;
      return lvl >= 4;
    default:
      return true;
  }
}

int? _extractInt(String s) {
  final RegExpMatch? m = RegExp(r'\d+').firstMatch(s);
  if (m == null) return null;
  return int.tryParse(m.group(0)!);
}

IconData _iconForWeather(String subtitle) {
  if (subtitle.contains('雷')) {
    return Icons.thunderstorm_rounded;
  }
  if (subtitle.contains('雪')) {
    return Icons.ac_unit_rounded;
  }
  if (subtitle.contains('雨')) {
    return Icons.umbrella_rounded;
  }
  if (subtitle.contains('晴')) {
    return Icons.wb_sunny_rounded;
  }
  if (subtitle.contains('云') || subtitle.contains('阴')) {
    return Icons.cloud_rounded;
  }
  return Icons.wb_cloudy_rounded;
}
