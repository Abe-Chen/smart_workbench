import 'package:flutter/material.dart';

class ClarificationLayout extends StatelessWidget {
  const ClarificationLayout({required this.question, super.key});

  final String question;

  @override
  Widget build(BuildContext context) {
    final String text = question.trim().isEmpty ? '你补充一下就行。' : question.trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          Icons.record_voice_over_rounded,
          color: const Color(0xFF2F6BFF).withValues(alpha: 0.92),
          size: 42,
        ),
        const SizedBox(height: 22),
        Text(
          text,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: const Color(0xFF1F2A44),
            fontWeight: FontWeight.w900,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 22),
        DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFEAF2FF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFD3E0FF)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.mic_none_rounded,
                  size: 18,
                  color: Color(0xFF2F6BFF),
                ),
                const SizedBox(width: 8),
                Text(
                  '我在听...',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF2F6BFF),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
