import 'package:flutter/material.dart';

import '../../domain/assistant_message.dart';
import 'assistant_result_card_view.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({required this.message, super.key});

  final AssistantMessage message;

  @override
  Widget build(BuildContext context) {
    final bool isUser = message.role == AssistantRole.user;
    final Color fg = isUser ? Colors.white : const Color(0xFF1F2A44);
    final Alignment align = isUser
        ? Alignment.centerRight
        : Alignment.centerLeft;
    final BorderRadius radius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(isUser ? 16 : 4),
      bottomRight: Radius.circular(isUser ? 4 : 16),
    );

    final String content = message.content.isEmpty && message.streaming
        ? '...'
        : message.content;
    final bool showBubble = !(content.isEmpty && message.resultCard != null);
    final Widget bubble = Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: isUser ? null : Colors.white.withValues(alpha: 0.88),
        gradient: isUser
            ? const LinearGradient(
                colors: <Color>[Color(0xFF3C7BFF), Color(0xFF225CFF)],
              )
            : null,
        borderRadius: radius,
        border: isUser ? null : Border.all(color: const Color(0xFFE1E8F5)),
        boxShadow: isUser
            ? const <BoxShadow>[
                BoxShadow(
                  color: Color(0x1F2F6BFF),
                  blurRadius: 12,
                  offset: Offset(0, 6),
                ),
              ]
            : const <BoxShadow>[
                BoxShadow(
                  color: Color(0x0F0D47A1),
                  blurRadius: 12,
                  offset: Offset(0, 6),
                ),
              ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Flexible(
            child: Text(
              content,
              style: TextStyle(
                color: fg,
                fontSize: 14,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (message.streaming && message.content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: _BlinkingCursor(color: fg),
            ),
        ],
      ),
    );

    return Align(
      alignment: align,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: <Widget>[
            if (showBubble) bubble,
            if (message.resultCard != null && !isUser)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: AssistantResultCardView(card: message.resultCard!),
              ),
          ],
        ),
      ),
    );
  }
}

class _BlinkingCursor extends StatefulWidget {
  const _BlinkingCursor({required this.color});
  final Color color;
  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _ctrl,
      child: Container(
        width: 6,
        height: 14,
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
