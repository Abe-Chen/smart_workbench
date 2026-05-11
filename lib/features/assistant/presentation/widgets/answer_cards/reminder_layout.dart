import 'package:flutter/material.dart';

import 'answer_card_models.dart';

class ReminderLayout extends StatelessWidget {
  const ReminderLayout({
    required this.data,
    this.onRead,
    this.onSnooze,
    this.onClose,
    super.key,
  });

  final ReminderCardData data;
  final VoidCallback? onRead;
  final VoidCallback? onSnooze;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    const Color accent = Color(0xFFFF8A3D);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(21),
            border: Border.all(color: accent.withValues(alpha: 0.24)),
          ),
          child: const Icon(
            Icons.notifications_active_rounded,
            color: accent,
            size: 32,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          data.title.trim().isEmpty ? '提醒' : data.title.trim(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: const Color(0xFF1F2A44),
            fontWeight: FontWeight.w900,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          data.timeLabel.trim().isEmpty ? '现在需要处理' : data.timeLabel.trim(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: accent,
            fontWeight: FontWeight.w900,
            height: 1.28,
          ),
        ),
        if (data.subtitle?.trim().isNotEmpty == true) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            data.subtitle!.trim(),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: const Color(0xFF60708A),
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        ],
        const SizedBox(height: 26),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 10,
          children: <Widget>[
            _ReminderActionButton(
              label: '已读',
              icon: Icons.check_rounded,
              filled: true,
              onPressed: onRead,
            ),
            _ReminderActionButton(
              label: '稍后',
              icon: Icons.schedule_rounded,
              onPressed: onSnooze,
            ),
            _ReminderActionButton(
              label: '关闭',
              icon: Icons.close_rounded,
              onPressed: onClose,
            ),
          ],
        ),
      ],
    );
  }
}

class _ReminderActionButton extends StatelessWidget {
  const _ReminderActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.filled = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final Widget child = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    if (filled) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: child,
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: child,
    );
  }
}
