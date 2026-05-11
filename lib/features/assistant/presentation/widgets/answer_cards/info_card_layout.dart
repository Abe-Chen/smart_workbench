import 'package:flutter/material.dart';

import '../../../domain/assistant_result_card.dart';
import '../assistant_result_card_view.dart';

class InfoCardLayout extends StatelessWidget {
  const InfoCardLayout({required this.card, required this.message, super.key});

  final AssistantResultCard card;
  final String message;

  @override
  Widget build(BuildContext context) {
    final bool hideSummary = message.trim() == card.summary.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AssistantResultCardView(card: card),
        if (!hideSummary && message.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: 18),
          Text(
            message.trim(),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: const Color(0xFF1F2A44),
              height: 1.45,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ],
    );
  }
}
