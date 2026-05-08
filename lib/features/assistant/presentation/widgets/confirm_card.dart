import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/assistant_controller.dart';
import '../../application/assistant_state.dart';
import '../../domain/assistant_confirm_preview.dart';

/// 操作确认卡。
///
/// - 抽屉模式下嵌在消息流之后、输入框之前
/// - 三按钮：取消（次要）/ 编辑（暂时灰）/ 确认（主要）
/// - severity = warning 时整体红色边框 + 红色确认按钮（适用于 delete）
class ConfirmCard extends ConsumerWidget {
  const ConfirmCard({super.key, required this.pending});

  final AssistantPendingConfirm pending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AssistantConfirmPreview preview = pending.preview;
    final bool warning = preview.severity == ConfirmSeverity.warning;
    final Color accent = warning
        ? const Color(0xFFE14D3A)
        : const Color(0xFF2F6BFF);
    final Color borderColor = warning
        ? const Color(0xFFE14D3A).withValues(alpha: 0.32)
        : const Color(0xFFBFD2FF);
    final List<Color> bgColors = warning
        ? const <Color>[Color(0xFFFFFBFA), Color(0xFFFFF1EF)]
        : const <Color>[Color(0xFFFFFFFF), Color(0xFFEFF6FF)];
    final String confirmLabel = warning
        ? '确认删除'
        : _confirmLabelForTool(pending.toolCall.name);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: bgColors,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: accent.withValues(alpha: warning ? 0.12 : 0.16),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: accent.withValues(alpha: 0.18)),
                ),
                child: Icon(
                  warning
                      ? Icons.warning_amber_rounded
                      : Icons.fact_check_outlined,
                  color: accent,
                  size: 21,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      preview.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: warning ? accent : const Color(0xFF22324C),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      warning ? '这一步会影响已有数据' : '确认后会立即写入看板',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF7A8798),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (preview.subtitle != null &&
              preview.subtitle!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              preview.subtitle!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Color(0xFF7A8798)),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE1E8F5)),
            ),
            child: Column(
              children: preview.rows
                  .map((ConfirmRow row) => _ConfirmRowView(row: row))
                  .toList(),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: TextButton(
                  onPressed: () => ref
                      .read(assistantControllerProvider.notifier)
                      .cancelPendingTool(),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF7A8798),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: const BorderSide(color: Color(0xFFD3DCEE)),
                    ),
                  ),
                  child: const Text(
                    '取消',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Tooltip(
                  message: '编辑功能下一版上线',
                  child: TextButton(
                    onPressed: null,
                    style: TextButton.styleFrom(
                      disabledForegroundColor: const Color(0xFFB7C0D0),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: const BorderSide(color: Color(0xFFE0E6F2)),
                      ),
                    ),
                    child: const Text(
                      '编辑',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: () => ref
                      .read(assistantControllerProvider.notifier)
                      .confirmPendingTool(),
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    confirmLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _confirmLabelForTool(String toolName) {
  switch (toolName) {
    case 'create_task':
      return '创建日程';
    case 'update_task':
      return '确认修改';
    case 'complete_task':
      return '标记完成';
    default:
      return '确认执行';
  }
}

class _ConfirmRowView extends StatelessWidget {
  const _ConfirmRowView({required this.row});

  final ConfirmRow row;

  @override
  Widget build(BuildContext context) {
    final TextStyle valueStyle = TextStyle(
      fontSize: 13,
      fontWeight: row.highlighted ? FontWeight.w800 : FontWeight.w600,
      color: row.highlighted
          ? const Color(0xFF2F6BFF)
          : const Color(0xFF22324C),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (row.icon != null) ...<Widget>[
            Text(row.icon!, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
          ],
          SizedBox(
            width: 48,
            child: Text(
              row.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF7A8798),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              row.value,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: valueStyle,
            ),
          ),
        ],
      ),
    );
  }
}
