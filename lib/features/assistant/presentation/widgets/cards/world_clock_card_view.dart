import 'package:flutter/material.dart';

import '../../../domain/cards/world_clock_card.dart';
import 'base_assistant_card.dart';
import 'card_theme.dart';

class WorldClockCardView extends StatelessWidget {
  const WorldClockCardView({
    required this.card,
    this.compact = false,
    super.key,
  });

  final WorldClockCard card;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    const CardThemeToken theme = CardThemeToken.night;
    final BoxDecoration decoration = BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: theme.gradient,
      ),
      border: Border.all(color: theme.borderColor),
    );

    if (card.cities.length == 1) {
      return BaseAssistantCard(
        compact: compact,
        decoration: decoration,
        hero: _SingleCityHero(
          entry: card.cities.first,
          theme: theme,
          compact: compact,
        ),
      );
    }

    final int displayCount = compact ? 2 : 3;
    final List<WorldClockEntry> visible = card.cities.take(displayCount).toList();
    final int extra = card.cities.length - visible.length;

    return BaseAssistantCard(
      compact: compact,
      decoration: decoration,
      hero: _MultiCityHero(card: card, theme: theme, compact: compact),
      body: _MultiCityList(
        entries: visible,
        extraCount: extra,
        theme: theme,
        compact: compact,
      ),
    );
  }
}

class _SingleCityHero extends StatelessWidget {
  const _SingleCityHero({
    required this.entry,
    required this.theme,
    required this.compact,
  });

  final WorldClockEntry entry;
  final CardThemeToken theme;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final double iconBoxSize = compact ? 44 : 56;
    final double iconSize = compact ? 24 : 32;
    final double timeFontSize = compact ? 36 : 56;

    final List<String> subtitleParts = <String>[];
    if (entry.weekday != null) subtitleParts.add(entry.weekday!);
    if (entry.timezone != null) subtitleParts.add(entry.timezone!);
    final String subtitle = subtitleParts.isEmpty
        ? '当前时间'
        : subtitleParts.join(' · ');

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
                Icons.access_time_rounded,
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
                    entry.cityName,
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
                    subtitle,
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
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            entry.localTime,
            style: TextStyle(
              color: theme.heroTextColor,
              fontSize: timeFontSize,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ),
        if (!compact && _hasInfoChip(entry)) ...<Widget>[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              if ((entry.offsetHint ?? '').isNotEmpty)
                _InfoChip(text: entry.offsetHint!, theme: theme),
              if (entry.isDst == true)
                _InfoChip(text: '夏令时已切换', theme: theme),
            ],
          ),
        ],
      ],
    );
  }
}

class _MultiCityHero extends StatelessWidget {
  const _MultiCityHero({
    required this.card,
    required this.theme,
    required this.compact,
  });

  final WorldClockCard card;
  final CardThemeToken theme;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final double iconBoxSize = compact ? 40 : 48;
    final double iconSize = compact ? 22 : 26;
    final String subtitle = card.referenceCityName == null
        ? '${card.cities.length} 个城市'
        : '基准 ${card.referenceCityName}';

    return Row(
      children: <Widget>[
        Container(
          width: iconBoxSize,
          height: iconBoxSize,
          decoration: BoxDecoration(
            color: theme.iconBackgroundColor,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.public_rounded,
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
                '世界时间',
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
                subtitle,
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
    );
  }
}

class _MultiCityList extends StatelessWidget {
  const _MultiCityList({
    required this.entries,
    required this.extraCount,
    required this.theme,
    required this.compact,
  });

  final List<WorldClockEntry> entries;
  final int extraCount;
  final CardThemeToken theme;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = <Widget>[];
    for (int i = 0; i < entries.length; i++) {
      if (i > 0) children.add(SizedBox(height: compact ? 8 : 10));
      children.add(_CityRow(entry: entries[i], theme: theme, compact: compact));
    }
    if (extraCount > 0) {
      children
        ..add(SizedBox(height: compact ? 8 : 10))
        ..add(
          Text(
            '还有 $extraCount 个城市',
            style: TextStyle(
              color: theme.bodyTextColor,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _CityRow extends StatelessWidget {
  const _CityRow({
    required this.entry,
    required this.theme,
    required this.compact,
  });

  final WorldClockEntry entry;
  final CardThemeToken theme;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                entry.cityName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.heroTextColor,
                  fontSize: compact ? 13 : 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if ((entry.offsetHint ?? '').isNotEmpty) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  entry.offsetHint!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.bodyTextColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          entry.localTime,
          style: TextStyle(
            color: theme.heroTextColor,
            fontSize: compact ? 18 : 22,
            fontWeight: FontWeight.w900,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.text, required this.theme});

  final String text;
  final CardThemeToken theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: theme.chipBackgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: theme.heroTextColor,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

bool _hasInfoChip(WorldClockEntry entry) {
  return (entry.offsetHint ?? '').isNotEmpty || entry.isDst == true;
}
