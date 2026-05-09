import 'package:flutter/material.dart';

/// 信息卡主题 token。每张卡按场景选一个 [CardThemeToken]，
/// 通过 [BaseAssistantCard] 注入实际渲染。
class CardThemeToken {
  const CardThemeToken({
    required this.gradient,
    required this.accent,
    required this.heroTextColor,
    required this.bodyTextColor,
    required this.borderColor,
  });

  final List<Color> gradient;
  final Color accent;
  final Color heroTextColor;
  final Color bodyTextColor;
  final Color borderColor;

  /// 深色背景主题（heroText 接近白色）。用于决定 icon/chip 的二级配色。
  bool get isDarkBackground => heroTextColor.computeLuminance() > 0.7;

  Color get iconBackgroundColor => isDarkBackground
      ? Colors.white.withValues(alpha: 0.22)
      : Colors.white.withValues(alpha: 0.78);

  Color get iconForegroundColor => isDarkBackground ? Colors.white : accent;

  Color get chipBackgroundColor => isDarkBackground
      ? Colors.white.withValues(alpha: 0.20)
      : Colors.white.withValues(alpha: 0.84);

  Color get chipBorderColor => isDarkBackground
      ? Colors.white.withValues(alpha: 0.30)
      : borderColor;

  static const CardThemeToken sunny = CardThemeToken(
    gradient: <Color>[Color(0xFFFFD194), Color(0xFFFFA374)],
    accent: Color(0xFFFF8A4C),
    heroTextColor: Color(0xFF3A2410),
    bodyTextColor: Color(0xFF5A3D20),
    borderColor: Color(0xFFFFC890),
  );

  static const CardThemeToken rainy = CardThemeToken(
    gradient: <Color>[Color(0xFF6FA8DC), Color(0xFF3D5A80)],
    accent: Color(0xFFA8D8FF),
    heroTextColor: Color(0xFFFFFFFF),
    bodyTextColor: Color(0xFFE0EAF5),
    borderColor: Color(0xFF5B82B5),
  );

  static const CardThemeToken snowy = CardThemeToken(
    gradient: <Color>[Color(0xFFE0F2FF), Color(0xFFB8D6F0)],
    accent: Color(0xFF5B82B5),
    heroTextColor: Color(0xFF1F2A44),
    bodyTextColor: Color(0xFF3D4A6B),
    borderColor: Color(0xFFA8C8E5),
  );

  static const CardThemeToken cloudy = CardThemeToken(
    gradient: <Color>[Color(0xFFA8B5C8), Color(0xFF6E7E96)],
    accent: Color(0xFFD0DAE8),
    heroTextColor: Color(0xFFFFFFFF),
    bodyTextColor: Color(0xFFE5EBF2),
    borderColor: Color(0xFF5B6A82),
  );

  static const CardThemeToken gold = CardThemeToken(
    gradient: <Color>[Color(0xFFFFE9A8), Color(0xFFF2C94C)],
    accent: Color(0xFFD69E00),
    heroTextColor: Color(0xFF4A3500),
    bodyTextColor: Color(0xFF6E5200),
    borderColor: Color(0xFFE5BC4A),
  );

  static const CardThemeToken night = CardThemeToken(
    gradient: <Color>[Color(0xFF2A3D6F), Color(0xFF0F1A3B)],
    accent: Color(0xFF7090E0),
    heroTextColor: Color(0xFFFFFFFF),
    bodyTextColor: Color(0xFFC8D2E8),
    borderColor: Color(0xFF1F2D5C),
  );

  static const CardThemeToken neutral = CardThemeToken(
    gradient: <Color>[Color(0xFFFFFFFF), Color(0xFFF4F8FF)],
    accent: Color(0xFF3C7BFF),
    heroTextColor: Color(0xFF1F2A44),
    bodyTextColor: Color(0xFF60708A),
    borderColor: Color(0xFFE1E8F5),
  );
}

/// 卡片几何参数。
class CardSpacingTokens {
  CardSpacingTokens._();

  static const EdgeInsets paddingFull = EdgeInsets.fromLTRB(14, 14, 14, 14);
  static const EdgeInsets paddingCompact = EdgeInsets.fromLTRB(14, 12, 14, 12);

  static EdgeInsets paddingFor(bool compact) =>
      compact ? paddingCompact : paddingFull;

  static const double radiusFull = 20;
  static const double radiusCompact = 18;

  static double radiusFor(bool compact) =>
      compact ? radiusCompact : radiusFull;

  /// hero / body / footer 三段之间的默认垂直间距
  static const double slotGap = 12;
}
