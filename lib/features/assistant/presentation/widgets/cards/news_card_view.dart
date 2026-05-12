import 'package:flutter/material.dart';

import '../../../domain/cards/news_card.dart';
import 'base_assistant_card.dart';
import 'card_theme.dart';

class NewsCardView extends StatelessWidget {
  const NewsCardView({required this.card, this.compact = false, super.key});

  final NewsCard card;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    const CardThemeToken theme = CardThemeToken.neutral;
    final int displayCount = compact ? 2 : 3;
    final List<NewsItem> visible = card.items.take(displayCount).toList();
    final int extraCount = card.items.length - visible.length;

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
      hero: _NewsHero(card: card, theme: theme, compact: compact),
      body: _NewsList(
        items: visible,
        extraCount: extraCount,
        theme: theme,
        compact: compact,
      ),
      footer: _NewsFooter(card: card, theme: theme, compact: compact),
    );
  }
}

class _NewsHero extends StatelessWidget {
  const _NewsHero({
    required this.card,
    required this.theme,
    required this.compact,
  });

  final NewsCard card;
  final CardThemeToken theme;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final double iconBoxSize = compact ? 40 : 48;
    final double iconSize = compact ? 22 : 26;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
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
            Icons.newspaper_rounded,
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
              const SizedBox(height: 3),
              Text(
                card.summary,
                maxLines: compact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.bodyTextColor,
                  fontSize: compact ? 12 : 13,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NewsList extends StatelessWidget {
  const _NewsList({
    required this.items,
    required this.extraCount,
    required this.theme,
    required this.compact,
  });

  final List<NewsItem> items;
  final int extraCount;
  final CardThemeToken theme;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = <Widget>[];
    for (int i = 0; i < items.length; i++) {
      if (i > 0) children.add(SizedBox(height: compact ? 10 : 12));
      children.add(
        _NewsRow(index: i + 1, item: items[i], theme: theme, compact: compact),
      );
    }
    if (extraCount > 0) {
      children
        ..add(SizedBox(height: compact ? 8 : 10))
        ..add(
          Text(
            '还有 $extraCount 条',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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

class _NewsRow extends StatelessWidget {
  const _NewsRow({
    required this.index,
    required this.item,
    required this.theme,
    required this.compact,
  });

  final int index;
  final NewsItem item;
  final CardThemeToken theme;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final String meta = <String>[
      if ((item.source ?? '').isNotEmpty) item.source!,
      if ((item.timeLabel ?? '').isNotEmpty) item.timeLabel!,
    ].join(' · ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: theme.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            '$index',
            style: TextStyle(
              color: theme.accent,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.heroTextColor,
                  fontSize: compact ? 13 : 14,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
              if ((item.summary ?? '').isNotEmpty && !compact) ...<Widget>[
                const SizedBox(height: 3),
                Text(
                  item.summary!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.bodyTextColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ],
              if (meta.isNotEmpty) ...<Widget>[
                const SizedBox(height: 3),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.bodyTextColor.withValues(alpha: 0.78),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _NewsFooter extends StatelessWidget {
  const _NewsFooter({
    required this.card,
    required this.theme,
    required this.compact,
  });

  final NewsCard card;
  final CardThemeToken theme;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final String text = <String>[
      if ((card.updatedAt ?? '').isNotEmpty) card.updatedAt!,
      if ((card.sourceNote ?? '').isNotEmpty) card.sourceNote!,
    ].join(' · ');
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: theme.bodyTextColor.withValues(alpha: 0.72),
        fontSize: compact ? 10 : 11,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
