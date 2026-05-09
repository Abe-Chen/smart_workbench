import 'package:flutter/material.dart';

import '../../../domain/cards/exchange_rate_card.dart';
import 'base_assistant_card.dart';
import 'card_theme.dart';

class ExchangeRateCardView extends StatelessWidget {
  const ExchangeRateCardView({
    required this.card,
    this.compact = false,
    super.key,
  });

  final ExchangeRateCard card;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    const CardThemeToken theme = CardThemeToken.gold;

    final Widget? body = (compact || (card.change24h ?? '').isEmpty)
        ? null
        : _ChangeBody(card: card, theme: theme);

    final String? footerText = _composeFooterText(card);
    final Widget? footer = footerText == null
        ? null
        : _FooterText(text: footerText, theme: theme, compact: compact);

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
      hero: _ExchangeRateHero(card: card, theme: theme, compact: compact),
      body: body,
      footer: footer,
    );
  }
}

class _ExchangeRateHero extends StatelessWidget {
  const _ExchangeRateHero({
    required this.card,
    required this.theme,
    required this.compact,
  });

  final ExchangeRateCard card;
  final CardThemeToken theme;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final double iconBoxSize = compact ? 44 : 56;
    final double iconSize = compact ? 24 : 32;
    final double mainFontSize = compact ? 28 : 44;
    final double unitFontSize = compact ? 14 : 20;

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
                Icons.currency_exchange_rounded,
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
                    '${card.fromCurrencyName} → ${card.toCurrencyName}',
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
                    '实时汇率',
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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                _formatAmount(card.toAmount),
                style: TextStyle(
                  color: theme.heroTextColor,
                  fontSize: mainFontSize,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: EdgeInsets.only(bottom: compact ? 3 : 5),
                child: Text(
                  card.toCurrency,
                  style: TextStyle(
                    color: theme.heroTextColor,
                    fontSize: unitFontSize,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '= ${_formatAmount(card.fromAmount)} ${card.fromCurrency}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: theme.bodyTextColor,
            fontSize: compact ? 12 : 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ChangeBody extends StatelessWidget {
  const _ChangeBody({required this.card, required this.theme});

  final ExchangeRateCard card;
  final CardThemeToken theme;

  @override
  Widget build(BuildContext context) {
    final String change = card.change24h ?? '';
    if (change.isEmpty) {
      return const SizedBox.shrink();
    }
    final String arrow = card.isUp == null ? '' : (card.isUp! ? ' ↑' : ' ↓');
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
          decoration: BoxDecoration(
            color: theme.chipBackgroundColor,
            borderRadius: BorderRadius.circular(999),
          ),
          child: RichText(
            text: TextSpan(
              children: <InlineSpan>[
                TextSpan(
                  text: '24h ',
                  style: TextStyle(
                    color: theme.bodyTextColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(
                  text: '$change$arrow',
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
        ),
      ],
    );
  }
}

class _FooterText extends StatelessWidget {
  const _FooterText({
    required this.text,
    required this.theme,
    required this.compact,
  });

  final String text;
  final CardThemeToken theme;
  final bool compact;

  @override
  Widget build(BuildContext context) {
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

String? _composeFooterText(ExchangeRateCard card) {
  final List<String> parts = <String>[];
  if ((card.updatedAt ?? '').isNotEmpty) {
    parts.add('数据${card.updatedAt}更新');
  }
  final String note = (card.note ?? '').isNotEmpty ? card.note! : '仅供参考';
  parts.add(note);
  return parts.join(' · ');
}

String _formatAmount(double v) {
  if (v == v.truncateToDouble()) {
    return v.toInt().toString();
  }
  String s = v.toStringAsFixed(2);
  if (s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}
