import 'package:flutter/material.dart';

class ErrorLayout extends StatelessWidget {
  const ErrorLayout({
    required this.message,
    this.title = '没成功',
    this.onRetry,
    super.key,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFFE14D3A).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFE14D3A).withValues(alpha: 0.22),
            ),
          ),
          child: const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFE14D3A),
            size: 32,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: const Color(0xFF1F2A44),
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          message.trim().isEmpty ? '这次没有拿到稳定结果。' : message.trim(),
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: const Color(0xFF60708A),
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
        ),
        if (onRetry != null) ...<Widget>[
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text(
              '重试',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}
