import 'package:flutter/material.dart';

import '../../../application/assistant_state.dart';
import '../confirm_card.dart';

class ConfirmLayout extends StatelessWidget {
  const ConfirmLayout({required this.pending, super.key});

  final AssistantPendingConfirm? pending;

  @override
  Widget build(BuildContext context) {
    final AssistantPendingConfirm? value = pending;
    if (value == null) {
      return const _MissingConfirmLayout();
    }
    return ConfirmCard(pending: value);
  }
}

class _MissingConfirmLayout extends StatelessWidget {
  const _MissingConfirmLayout();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(
          Icons.fact_check_outlined,
          size: 42,
          color: Color(0xFF2F6BFF),
        ),
        const SizedBox(height: 16),
        Text(
          '等你确认',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: const Color(0xFF1F2A44),
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}
