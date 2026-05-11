import 'package:flutter/material.dart';

import 'answer_card_models.dart';

class ToolFeedbackLayout extends StatelessWidget {
  const ToolFeedbackLayout({required this.data, this.onUndo, super.key});

  final ToolFeedbackCardData data;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    final Color accent = const Color(0xFF16A078);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: accent.withValues(alpha: 0.18)),
              ),
              child: Icon(Icons.check_circle_rounded, color: accent, size: 30),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    data.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: const Color(0xFF1F2A44),
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                    ),
                  ),
                  if (data.subtitle?.trim().isNotEmpty == true) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      data.subtitle!.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF60708A),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (data.rows.isNotEmpty) ...<Widget>[
          const SizedBox(height: 22),
          DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFF7FAFF),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE1E8F5)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Column(
                children: <Widget>[
                  for (final ToolFeedbackRow row in data.rows)
                    _ToolFeedbackRowView(row: row),
                ],
              ),
            ),
          ),
        ],
        if (data.undoLabel?.trim().isNotEmpty == true) ...<Widget>[
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: onUndo,
            icon: const Icon(Icons.undo_rounded, size: 18),
            label: Text(
              data.undoLabel!.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}

class _ToolFeedbackRowView extends StatelessWidget {
  const _ToolFeedbackRowView({required this.row});

  final ToolFeedbackRow row;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (row.icon != null) ...<Widget>[
            Icon(row.icon, size: 18, color: const Color(0xFF2F6BFF)),
            const SizedBox(width: 8),
          ],
          SizedBox(
            width: 64,
            child: Text(
              row.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF7A8798),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              row.value,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: row.highlighted
                    ? const Color(0xFF2F6BFF)
                    : const Color(0xFF22324C),
                fontWeight: row.highlighted ? FontWeight.w900 : FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
