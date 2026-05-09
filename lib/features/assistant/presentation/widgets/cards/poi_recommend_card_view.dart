import 'package:flutter/material.dart';

import '../../../domain/cards/poi_recommend_card.dart';
import 'base_assistant_card.dart';
import 'card_theme.dart';

class PoiRecommendCardView extends StatelessWidget {
  const PoiRecommendCardView({
    required this.card,
    this.compact = false,
    super.key,
  });

  final PoiRecommendCard card;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    const CardThemeToken theme = CardThemeToken.neutral;
    final int displayCount = compact ? 2 : 3;
    final List<PoiItem> visible = card.items.take(displayCount).toList();
    final int extra = card.items.length - visible.length;

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
      hero: _PoiHero(card: card, theme: theme, compact: compact),
      body: _PoiList(
        items: visible,
        extraCount: extra,
        subtype: card.subtype,
        theme: theme,
        compact: compact,
      ),
      footer: _PoiFooter(card: card, theme: theme, compact: compact),
    );
  }
}

class _PoiHero extends StatelessWidget {
  const _PoiHero({
    required this.card,
    required this.theme,
    required this.compact,
  });

  final PoiRecommendCard card;
  final CardThemeToken theme;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final double iconBoxSize = compact ? 40 : 48;
    final double iconSize = compact ? 22 : 26;

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
            _materialIconFor(card.subtype),
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
              if ((card.subtitle ?? '').isNotEmpty) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  card.subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.bodyTextColor,
                    fontSize: 12,
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

class _PoiList extends StatelessWidget {
  const _PoiList({
    required this.items,
    required this.extraCount,
    required this.subtype,
    required this.theme,
    required this.compact,
  });

  final List<PoiItem> items;
  final int extraCount;
  final PoiKind subtype;
  final CardThemeToken theme;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = <Widget>[];
    for (int i = 0; i < items.length; i++) {
      if (i > 0) children.add(SizedBox(height: compact ? 10 : 12));
      children.add(
        _PoiRow(
          item: items[i],
          subtype: subtype,
          theme: theme,
          compact: compact,
        ),
      );
    }
    if (extraCount > 0) {
      children
        ..add(SizedBox(height: compact ? 8 : 10))
        ..add(
          Text(
            '还有 $extraCount 项',
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

class _PoiRow extends StatelessWidget {
  const _PoiRow({
    required this.item,
    required this.subtype,
    required this.theme,
    required this.compact,
  });

  final PoiItem item;
  final PoiKind subtype;
  final CardThemeToken theme;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final bool emphasizePrice =
        subtype == PoiKind.hotel && (item.priceLabel ?? '').isNotEmpty;
    final List<String> subInfo = _composeSubInfo(
      item,
      emphasizePrice: emphasizePrice,
    );
    final String emoji = item.iconEmoji ?? _defaultEmojiFor(subtype);
    final Widget? primaryMetric = _buildPrimaryMetric(emphasizePrice);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: compact ? 28 : 32,
          child: Text(
            emoji,
            style: TextStyle(fontSize: compact ? 22 : 26),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.heroTextColor,
                        fontSize: compact ? 13 : 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (primaryMetric != null) ...<Widget>[
                    const SizedBox(width: 8),
                    primaryMetric,
                  ],
                ],
              ),
              if (subInfo.isNotEmpty) ...<Widget>[
                const SizedBox(height: 3),
                Text(
                  subInfo.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.bodyTextColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget? _buildPrimaryMetric(bool emphasizePrice) {
    if (emphasizePrice) {
      return _PriceTag(price: item.priceLabel!, theme: theme, compact: compact);
    }
    if (item.rating != null) {
      return _RatingBadge(rating: item.rating!, theme: theme);
    }
    return null;
  }
}

class _PriceTag extends StatelessWidget {
  const _PriceTag({
    required this.price,
    required this.theme,
    required this.compact,
  });

  final String price;
  final CardThemeToken theme;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Text(
      price,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: theme.accent,
        fontSize: compact ? 14 : 16,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _RatingBadge extends StatelessWidget {
  const _RatingBadge({required this.rating, required this.theme});

  final double rating;
  final CardThemeToken theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(Icons.star_rounded, color: theme.accent, size: 14),
        const SizedBox(width: 2),
        Text(
          rating.toStringAsFixed(1),
          style: TextStyle(
            color: theme.heroTextColor,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _PoiFooter extends StatelessWidget {
  const _PoiFooter({
    required this.card,
    required this.theme,
    required this.compact,
  });

  final PoiRecommendCard card;
  final CardThemeToken theme;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final String text = (card.sourceNote ?? '').isNotEmpty
        ? card.sourceNote!
        : '信息以实际为准';
    return Text(
      text,
      maxLines: compact ? 1 : 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: theme.bodyTextColor,
        fontSize: compact ? 12 : 13,
        fontWeight: FontWeight.w600,
        height: 1.4,
      ),
    );
  }
}

List<String> _composeSubInfo(PoiItem item, {required bool emphasizePrice}) {
  final List<String> parts = <String>[];
  // emphasizePrice 时价格已经被提到主行，副行改放评分
  if (!emphasizePrice && (item.priceLabel ?? '').isNotEmpty) {
    parts.add(item.priceLabel!);
  }
  if (emphasizePrice && item.rating != null) {
    parts.add('★ ${item.rating!.toStringAsFixed(1)}');
  }
  if ((item.distanceLabel ?? '').isNotEmpty) parts.add(item.distanceLabel!);
  if ((item.tag ?? '').isNotEmpty) parts.add(item.tag!);
  return parts;
}

IconData _materialIconFor(PoiKind kind) {
  switch (kind) {
    case PoiKind.attraction:
      return Icons.place_rounded;
    case PoiKind.hotel:
      return Icons.hotel_rounded;
    case PoiKind.restaurant:
      return Icons.restaurant_rounded;
  }
}

String _defaultEmojiFor(PoiKind kind) {
  switch (kind) {
    case PoiKind.attraction:
      return '🏛';
    case PoiKind.hotel:
      return '🏨';
    case PoiKind.restaurant:
      return '🍽';
  }
}
