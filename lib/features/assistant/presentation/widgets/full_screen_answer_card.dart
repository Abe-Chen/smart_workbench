import 'dart:ui';

import 'package:flutter/material.dart';

import '../../application/assistant_state.dart';
import '../../domain/assistant_result_card.dart';
import 'answer_cards/answer_card_models.dart';
import 'answer_cards/clarification_layout.dart';
import 'answer_cards/confirm_layout.dart';
import 'answer_cards/error_layout.dart';
import 'answer_cards/info_card_layout.dart';
import 'answer_cards/plain_text_layout.dart';
import 'answer_cards/reminder_layout.dart';
import 'answer_cards/tool_feedback_layout.dart';

class FullScreenAnswerCard extends StatelessWidget {
  const FullScreenAnswerCard({
    required this.kind,
    this.message = '',
    this.resultCard,
    this.toolFeedback,
    this.pendingConfirm,
    this.reminder,
    this.bottomReservedSpace = 0,
    this.onClose,
    this.onExpand,
    this.onInteract,
    this.onRetry,
    this.onUndo,
    this.onReminderRead,
    this.onReminderSnooze,
    this.onReminderClose,
    super.key,
  });

  final AnswerCardKind kind;
  final String message;
  final AssistantResultCard? resultCard;
  final ToolFeedbackCardData? toolFeedback;
  final AssistantPendingConfirm? pendingConfirm;
  final ReminderCardData? reminder;
  final double bottomReservedSpace;
  final VoidCallback? onClose;
  final VoidCallback? onExpand;
  final VoidCallback? onInteract;
  final VoidCallback? onRetry;
  final VoidCallback? onUndo;
  final VoidCallback? onReminderRead;
  final VoidCallback? onReminderSnooze;
  final VoidCallback? onReminderClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF101828).withValues(alpha: 0.18),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double maxWidth = constraints.maxWidth >= 900
                    ? 760
                    : constraints.maxWidth * 0.88;
                final double maxHeight = constraints.maxHeight >= 680
                    ? constraints.maxHeight * 0.76
                    : constraints.maxHeight * 0.82;
                return Center(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onInteract,
                    onVerticalDragEnd: (DragEndDetails details) {
                      final double velocity = details.primaryVelocity ?? 0;
                      if (velocity < -360) {
                        onExpand?.call();
                      }
                    },
                    child: Padding(
                      padding: EdgeInsets.only(bottom: bottomReservedSpace),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: maxWidth,
                          maxHeight: (maxHeight - bottomReservedSpace * 0.5)
                              .clamp(320.0, maxHeight),
                        ),
                        child: _AnswerCardShell(
                          kind: kind,
                          onClose: onClose,
                          onExpand: onExpand,
                          child: _buildContent(),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (kind) {
      case AnswerCardKind.infoCard:
        final AssistantResultCard? card = resultCard;
        if (card == null) {
          return PlainTextLayout(message: message);
        }
        return InfoCardLayout(card: card, message: message);
      case AnswerCardKind.toolFeedback:
        return ToolFeedbackLayout(
          data: toolFeedback ?? const ToolFeedbackCardData(title: '已经处理好了'),
          onUndo: onUndo,
        );
      case AnswerCardKind.plainText:
        return PlainTextLayout(message: message);
      case AnswerCardKind.clarification:
        return ClarificationLayout(question: message);
      case AnswerCardKind.confirm:
        return ConfirmLayout(pending: pendingConfirm);
      case AnswerCardKind.error:
        return ErrorLayout(message: message, onRetry: onRetry);
      case AnswerCardKind.reminder:
        return ReminderLayout(
          data:
              reminder ??
              const ReminderCardData(title: '提醒', timeLabel: '现在需要处理'),
          onRead: onReminderRead,
          onSnooze: onReminderSnooze,
          onClose: onReminderClose,
        );
    }
  }
}

class _AnswerCardShell extends StatelessWidget {
  const _AnswerCardShell({
    required this.kind,
    required this.child,
    this.onClose,
    this.onExpand,
  });

  final AnswerCardKind kind;
  final Widget child;
  final VoidCallback? onClose;
  final VoidCallback? onExpand;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFFFFFFFF), Color(0xFFF3F8FF)],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white, width: 1.2),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x2B0D47A1),
            blurRadius: 42,
            offset: Offset(0, 20),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _AnswerCardHeader(
              title: _titleForKind(kind),
              icon: _iconForKind(kind),
              accent: _accentForKind(kind),
              onClose: onClose,
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 8, 28, 28),
                child: child,
              ),
            ),
            if (onExpand != null) _ExpandHint(onExpand: onExpand),
          ],
        ),
      ),
    );
  }
}

class _AnswerCardHeader extends StatelessWidget {
  const _AnswerCardHeader({
    required this.title,
    required this.icon,
    required this.accent,
    this.onClose,
  });

  final String title;
  final IconData icon;
  final Color accent;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 14, 8),
      child: Row(
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: const Color(0xFF22324C),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          IconButton(
            tooltip: '关闭',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
            color: const Color(0xFF7A8798),
          ),
        ],
      ),
    );
  }
}

class _ExpandHint extends StatelessWidget {
  const _ExpandHint({required this.onExpand});

  final VoidCallback? onExpand;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onExpand,
      icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 20),
      label: const Text('完整查看', maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

String _titleForKind(AnswerCardKind kind) {
  switch (kind) {
    case AnswerCardKind.infoCard:
      return '小治整理好了';
    case AnswerCardKind.toolFeedback:
      return '操作完成';
    case AnswerCardKind.plainText:
      return '小治回答';
    case AnswerCardKind.clarification:
      return '需要补充';
    case AnswerCardKind.confirm:
      return '等你确认';
    case AnswerCardKind.error:
      return '遇到问题';
    case AnswerCardKind.reminder:
      return '提醒';
  }
}

IconData _iconForKind(AnswerCardKind kind) {
  switch (kind) {
    case AnswerCardKind.infoCard:
      return Icons.auto_awesome_rounded;
    case AnswerCardKind.toolFeedback:
      return Icons.check_circle_rounded;
    case AnswerCardKind.plainText:
      return Icons.chat_bubble_rounded;
    case AnswerCardKind.clarification:
      return Icons.record_voice_over_rounded;
    case AnswerCardKind.confirm:
      return Icons.fact_check_outlined;
    case AnswerCardKind.error:
      return Icons.error_outline_rounded;
    case AnswerCardKind.reminder:
      return Icons.notifications_active_rounded;
  }
}

Color _accentForKind(AnswerCardKind kind) {
  switch (kind) {
    case AnswerCardKind.infoCard:
    case AnswerCardKind.plainText:
      return const Color(0xFF2F6BFF);
    case AnswerCardKind.toolFeedback:
      return const Color(0xFF16A078);
    case AnswerCardKind.clarification:
    case AnswerCardKind.confirm:
    case AnswerCardKind.reminder:
      return const Color(0xFFFF8A3D);
    case AnswerCardKind.error:
      return const Color(0xFFE14D3A);
  }
}
