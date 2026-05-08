import 'package:flutter/material.dart';

import '../../domain/assistant_result_card.dart';

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
    switch (card.kind) {
      case AssistantResultCardKind.weather:
        return _WeatherResultCard(card: card, compact: compact);
    }
  }
}

class _WeatherResultCard extends StatelessWidget {
  const _WeatherResultCard({required this.card, required this.compact});

  final AssistantResultCard card;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final EdgeInsets padding = compact
        ? const EdgeInsets.fromLTRB(14, 12, 14, 12)
        : const EdgeInsets.fromLTRB(14, 14, 14, 14);
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(compact ? 18 : 20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFFF4F8FF), Color(0xFFE8F0FF)],
        ),
        border: Border.all(color: const Color(0xFFD4E1FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: compact ? 36 : 40,
                height: compact ? 36 : 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(
                  _iconForWeather(card.subtitle),
                  color: const Color(0xFF2F6BFF),
                  size: compact ? 20 : 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      card.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF22324C),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      card.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF60708A),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 10,
            runSpacing: 6,
            children: <Widget>[
              Text(
                card.headline,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.headlineMedium?.copyWith(
                  color: const Color(0xFF1F2A44),
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              if ((card.secondaryHeadline ?? '').trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    card.secondaryHeadline!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF60708A),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          if (card.metrics.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: card.metrics
                  .map(
                    (AssistantResultMetric metric) =>
                        _MetricChip(metric: metric),
                  )
                  .toList(),
            ),
          ],
          if (card.timeline.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              '接下来',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelMedium?.copyWith(
                color: const Color(0xFF60708A),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: card.timeline
                  .map(
                    (AssistantResultTimelinePoint point) =>
                        _TimelineChip(point: point),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            card.summary,
            maxLines: compact ? 3 : 4,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF1F2A44),
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.metric});

  final AssistantResultMetric metric;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(999),
      ),
      child: RichText(
        text: TextSpan(
          children: <InlineSpan>[
            TextSpan(
              text: '${metric.label} ',
              style: const TextStyle(
                color: Color(0xFF60708A),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: metric.value,
              style: const TextStyle(
                color: Color(0xFF22324C),
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
  const _TimelineChip({required this.point});

  final AssistantResultTimelinePoint point;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD6E3FF)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            point.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF60708A),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            point.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF22324C),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
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
