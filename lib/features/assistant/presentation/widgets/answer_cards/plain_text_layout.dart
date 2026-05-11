import 'package:flutter/material.dart';

class PlainTextLayout extends StatelessWidget {
  const PlainTextLayout({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final String text = message.trim().isEmpty ? '我这次没拿到有效结果。' : message.trim();
    final bool hero = text.length <= 12 && !text.contains('\n');
    return Center(
      child: Text(
        text,
        maxLines: hero ? 2 : 8,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style:
            (hero
                    ? Theme.of(context).textTheme.displayMedium
                    : Theme.of(context).textTheme.headlineSmall)
                ?.copyWith(
                  color: const Color(0xFF1F2A44),
                  fontWeight: FontWeight.w900,
                  height: hero ? 1.12 : 1.35,
                ),
      ),
    );
  }
}
