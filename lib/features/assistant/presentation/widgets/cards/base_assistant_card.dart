import 'package:flutter/material.dart';

import 'card_theme.dart';

/// 信息卡通用骨架。子卡通过 hero / body / footer 三个 slot 填充内容，
/// 卡 padding、圆角、slot 间距由本骨架统一控制。
///
/// decoration 由子卡传入（gradient / border 等），骨架若发现 decoration
/// 未指定 borderRadius，会按 [compact] 自动套 [CardSpacingTokens.radiusFor]。
class BaseAssistantCard extends StatelessWidget {
  const BaseAssistantCard({
    required this.decoration,
    required this.compact,
    this.hero,
    this.body,
    this.footer,
    this.heroBodyGap,
    this.bodyFooterGap,
    super.key,
  });

  final BoxDecoration decoration;
  final bool compact;
  final Widget? hero;
  final Widget? body;
  final Widget? footer;

  /// hero 与 body 之间的间距，默认 [CardSpacingTokens.slotGap]
  final double? heroBodyGap;

  /// body 与 footer 之间的间距，默认 [CardSpacingTokens.slotGap]
  final double? bodyFooterGap;

  @override
  Widget build(BuildContext context) {
    final BoxDecoration finalDecoration = decoration.copyWith(
      borderRadius:
          decoration.borderRadius ??
          BorderRadius.circular(CardSpacingTokens.radiusFor(compact)),
    );

    final double topGap = heroBodyGap ?? CardSpacingTokens.slotGap;
    final double bottomGap = bodyFooterGap ?? CardSpacingTokens.slotGap;

    final List<Widget> children = <Widget>[];
    if (hero != null) {
      children.add(hero!);
    }
    if (body != null) {
      if (children.isNotEmpty) children.add(SizedBox(height: topGap));
      children.add(body!);
    }
    if (footer != null) {
      if (children.isNotEmpty) children.add(SizedBox(height: bottomGap));
      children.add(footer!);
    }

    return Container(
      width: double.infinity,
      padding: CardSpacingTokens.paddingFor(compact),
      decoration: finalDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}
