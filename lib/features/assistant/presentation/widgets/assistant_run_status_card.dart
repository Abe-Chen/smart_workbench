import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/assistant_controller.dart';
import '../../application/assistant_state.dart';

class AssistantRunStatusCard extends ConsumerWidget {
  const AssistantRunStatusCard({
    required this.progress,
    this.compact = false,
    this.showExpandAction = false,
    super.key,
  });

  final AssistantProgressState progress;
  final bool compact;
  final bool showExpandAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AssistantController controller = ref.read(
      assistantControllerProvider.notifier,
    );
    final String status = progress.status?.trim() ?? '';
    if (status.isEmpty) {
      return const SizedBox.shrink();
    }
    final String elapsedLabel = progress.elapsedMs <= 0
        ? '刚开始'
        : '已等待 ${(progress.elapsedMs / 1000).floor()}s';

    return Container(
      constraints: compact ? const BoxConstraints(maxWidth: 420) : null,
      padding: EdgeInsets.fromLTRB(
        compact ? 14 : 12,
        compact ? 10 : 12,
        compact ? 14 : 12,
        compact ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(compact ? 18 : 16),
        border: Border.all(color: const Color(0xFFDDE7FF)),
        boxShadow: compact
            ? const <BoxShadow>[
                BoxShadow(
                  color: Color(0x140D47A1),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFF1F2A44),
                    fontSize: compact ? 13 : 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (showExpandAction)
                IconButton(
                  tooltip: '展开查看',
                  icon: const Icon(Icons.open_in_full_rounded, size: 18),
                  color: const Color(0xFF7A8798),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  onPressed: controller.openDrawer,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              if (progress.mode != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF2FF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    progress.mode!.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF2F6BFF),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              if (progress.mode != null) const SizedBox(width: 8),
              Expanded(
                child: Text(
                  elapsedLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF7A8798),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if ((progress.detail ?? '').trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              progress.detail!.trim(),
              maxLines: compact ? 2 : 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF60708A),
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (progress.canStop ||
              progress.canCancelTask ||
              progress.canAskForSummary)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  if (progress.canCancelTask)
                    _ActionChip(
                      label: '取消任务',
                      onTap: controller.cancelCurrentTask,
                    ),
                  if (progress.canStop)
                    _ActionChip(
                      label: '停止生成',
                      onTap: controller.stopCurrentGeneration,
                    ),
                  if (progress.canAskForSummary)
                    _ActionChip(
                      label: '先给我结论',
                      onTap: controller.requestConclusionNow,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F4FA),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFD6E0F5)),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF22324C),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
