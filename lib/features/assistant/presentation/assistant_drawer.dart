import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/assistant_controller.dart';
import '../application/assistant_state.dart';
import '../domain/assistant_message.dart';
import '../domain/assistant_result_card.dart';
import 'widgets/assistant_ball.dart';
import 'widgets/assistant_result_card_view.dart';
import 'widgets/message_bubble.dart';

/// workbench_shell 底部导航栏总占用高度（圆角条 94 + SafeArea.minimum bottom 10）。
/// 抽屉要在这之上停住，否则输入框会被导航栏盖住。
const double _kBottomNavReserve = 104;
const double _kDrawerEdgeGap = 12;

class AssistantOverlay extends ConsumerWidget {
  const AssistantOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AssistantUiState state = ref.watch(assistantControllerProvider);
    final bool open = state.drawerOpen;
    final Size screen = MediaQuery.sizeOf(context);
    final EdgeInsets viewPadding = MediaQuery.viewPaddingOf(context);
    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final double drawerWidth = (screen.width * 0.4).clamp(360, 520);
    final double topInset = viewPadding.top + _kDrawerEdgeGap;
    final double bottomInset =
        (keyboard > 0 ? keyboard : _kBottomNavReserve) + _kDrawerEdgeGap;

    return Stack(
      children: <Widget>[
        if (!open)
          Positioned(
            left: 0,
            right: 0,
            bottom: _kBottomNavReserve + 22,
            child: Center(child: _FloatingAssistantSurface(state: state)),
          ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOutQuint,
          top: topInset,
          bottom: bottomInset,
          right: open ? _kDrawerEdgeGap : -drawerWidth - 24,
          width: drawerWidth,
          child: Material(
            elevation: 0,
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0xFFDDE7FF)),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x220D47A1),
                    blurRadius: 30,
                    offset: Offset(-4, 12),
                  ),
                ],
              ),
              child: const _AssistantDrawerBody(),
            ),
          ),
        ),
      ],
    );
  }
}

class _AssistantDrawerBody extends ConsumerStatefulWidget {
  const _AssistantDrawerBody();

  @override
  ConsumerState<_AssistantDrawerBody> createState() =>
      _AssistantDrawerBodyState();
}

class _AssistantDrawerBodyState extends ConsumerState<_AssistantDrawerBody> {
  final TextEditingController _textCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scrollCtrl.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _send() {
    final String text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    _textCtrl.clear();
    ref
        .read(assistantControllerProvider.notifier)
        .sendUserMessage(text, source: AssistantEntrySource.drawerText);
  }

  @override
  Widget build(BuildContext context) {
    final AssistantUiState state = ref.watch(assistantControllerProvider);
    ref.listen(assistantControllerProvider, (_, _) => _scrollToBottom());
    final bool sending =
        state.stage == AssistantStage.think ||
        state.stage == AssistantStage.answer;
    final bool listening = state.stage == AssistantStage.listen;
    final List<AssistantMessage> visibleMessages = state.messages
        .where((AssistantMessage m) => m.isVisibleInChat)
        .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        children: <Widget>[
          _Header(stage: state.stage),
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFE8EEFB)),
          Expanded(
            child: visibleMessages.isEmpty
                ? const _EmptyHint()
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: visibleMessages.length,
                    itemBuilder: (BuildContext context, int index) =>
                        MessageBubble(message: visibleMessages[index]),
                  ),
          ),
          if (state.listenError != null && !listening)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                state.listenError!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFE14D3A), fontSize: 12),
              ),
            ),
          if (state.ttsError != null && !listening)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      state.ttsError!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFE14D3A),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    icon: const Icon(Icons.close_rounded, size: 16),
                    color: const Color(0xFF7A8798),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                    onPressed: () => ref
                        .read(assistantControllerProvider.notifier)
                        .dismissTtsError(),
                  ),
                ],
              ),
            ),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                state.error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFE14D3A), fontSize: 12),
              ),
            ),
          if (listening)
            _ListenStrip(
              partialText: state.listenPartialText,
              listeningMode: state.listeningMode,
              remainingMs: state.listenWindowRemainingMs,
              onCancel: () => ref
                  .read(assistantControllerProvider.notifier)
                  .cancelListening(),
            ),
          if (listening) const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.only(top: 10),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFE8EEFB))),
            ),
            child: _InputBar(
              controller: _textCtrl,
              disabled: sending || listening,
              listening: listening,
              listeningMode: state.listeningMode,
              onSend: _send,
              onMicLongPressStart: () => ref
                  .read(assistantControllerProvider.notifier)
                  .startListening(
                    source: AssistantEntrySource.drawerVoice,
                    mode: AssistantListeningMode.pressToTalk,
                  ),
              onMicLongPressEnd: () => ref
                  .read(assistantControllerProvider.notifier)
                  .stopListening(),
              onMicLongPressCancel: () => ref
                  .read(assistantControllerProvider.notifier)
                  .cancelListening(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ListenStrip extends StatelessWidget {
  const _ListenStrip({
    required this.partialText,
    required this.listeningMode,
    required this.remainingMs,
    required this.onCancel,
  });

  final String partialText;
  final AssistantListeningMode listeningMode;
  final int remainingMs;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFCCDBFF)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.graphic_eq_rounded,
            color: Color(0xFF2F6BFF),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              partialText.isEmpty
                  ? _defaultHintFor(listeningMode, remainingMs)
                  : partialText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: partialText.isEmpty
                    ? const Color(0xFF7A8798)
                    : const Color(0xFF1F2A44),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
          if (listeningMode == AssistantListeningMode.openMic &&
              partialText.isEmpty &&
              remainingMs > 0)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: _CountdownBadge(label: '${(remainingMs / 1000).ceil()}s'),
            ),
          IconButton(
            tooltip: '取消',
            icon: const Icon(Icons.close_rounded, size: 18),
            color: const Color(0xFF7A8798),
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }

  String _defaultHintFor(AssistantListeningMode mode, int remainingMs) {
    switch (mode) {
      case AssistantListeningMode.openMic:
        return remainingMs > 0 ? '我在听，你可以直接说' : '我在听...';
      case AssistantListeningMode.pressToTalk:
        return '我在听，松开手就发出去';
    }
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.stage});
  final AssistantStage stage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AssistantSessionMute sessionMute = ref.watch(
      assistantControllerProvider.select(
        (AssistantUiState s) => s.sessionMute,
      ),
    );
    final bool isMuted = sessionMute == AssistantSessionMute.muted;
    return Row(
      children: <Widget>[
        AssistantBall(stage: stage, size: 44),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '小治',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF22324C),
                ),
              ),
              SizedBox(height: 2),
              Text(
                '在桌面贴着你工作',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFF7A8798),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: isMuted ? '本会话已静音，点击恢复跟随设置' : '本会话静音（不写入设置）',
          icon: Icon(
            isMuted
                ? Icons.notifications_off_rounded
                : Icons.notifications_active_outlined,
            size: 22,
          ),
          color: isMuted
              ? const Color(0xFFFF5252)
              : const Color(0xFF7A8798),
          onPressed: () => ref
              .read(assistantControllerProvider.notifier)
              .setSessionMute(!isMuted),
        ),
        IconButton(
          tooltip: '播报这条回答',
          icon: const Icon(Icons.volume_up_rounded, size: 22),
          color: const Color(0xFF7A8798),
          onPressed: () => ref
              .read(assistantControllerProvider.notifier)
              .replayLatestAssistantReply(),
        ),
        IconButton(
          tooltip: '清空对话',
          icon: const Icon(Icons.refresh_rounded, size: 22),
          color: const Color(0xFF7A8798),
          onPressed: () => ref
              .read(assistantControllerProvider.notifier)
              .clearConversation(),
        ),
        IconButton(
          tooltip: '关闭',
          icon: const Icon(Icons.close_rounded, size: 22),
          color: const Color(0xFF7A8798),
          onPressed: () =>
              ref.read(assistantControllerProvider.notifier).closeDrawer(),
        ),
      ],
    );
  }
}

class _FloatingAssistantSurface extends ConsumerWidget {
  const _FloatingAssistantSurface({required this.state});

  final AssistantUiState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.stage == AssistantStage.listen) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: _ListenStrip(
          partialText: state.listenPartialText,
          listeningMode: state.listeningMode,
          remainingMs: state.listenWindowRemainingMs,
          onCancel: () =>
              ref.read(assistantControllerProvider.notifier).cancelListening(),
        ),
      );
    }

    if (state.stage == AssistantStage.think) {
      return Container(
        constraints: const BoxConstraints(maxWidth: 360),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFDDE7FF)),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x140D47A1),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
            SizedBox(width: 10),
            Text(
              '小治正在想...',
              style: TextStyle(
                color: Color(0xFF1F2A44),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    if (state.replySurface == AssistantReplySurface.compactCard &&
        state.compactReplyText != null &&
        state.compactReplyText!.trim().isNotEmpty) {
      return _CompactReplyCard(
        text: state.compactReplyText!,
        resultCard: state.compactReplyCard,
        followUpRemainingMs: state.followUpRemainingMs,
      );
    }

    return const SizedBox.shrink();
  }
}

class _CompactReplyCard extends ConsumerWidget {
  const _CompactReplyCard({
    required this.text,
    required this.followUpRemainingMs,
    this.resultCard,
  });

  final String text;
  final AssistantResultCard? resultCard;
  final int followUpRemainingMs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool hideDuplicateSummary =
        resultCard != null && text.trim() == resultCard!.summary.trim();
    final double followUpProgress = followUpRemainingMs <= 0
        ? 0
        : (followUpRemainingMs / 5000).clamp(0, 1);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFDDE7FF)),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x180D47A1),
              blurRadius: 22,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(
                  Icons.auto_awesome_rounded,
                  color: Color(0xFF2F6BFF),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '小治',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: const Color(0xFF22324C),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '再播一遍',
                  icon: const Icon(Icons.volume_up_rounded, size: 20),
                  color: const Color(0xFF7A8798),
                  onPressed: () => ref
                      .read(assistantControllerProvider.notifier)
                      .replayLatestAssistantReply(),
                ),
                IconButton(
                  tooltip: '展开抽屉',
                  icon: const Icon(Icons.open_in_full_rounded, size: 20),
                  color: const Color(0xFF7A8798),
                  onPressed: () => ref
                      .read(assistantControllerProvider.notifier)
                      .openDrawer(),
                ),
                IconButton(
                  tooltip: '关闭',
                  icon: const Icon(Icons.close_rounded, size: 20),
                  color: const Color(0xFF7A8798),
                  onPressed: () => ref
                      .read(assistantControllerProvider.notifier)
                      .hideCompactReply(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (resultCard != null) ...<Widget>[
              AssistantResultCardView(card: resultCard!, compact: true),
              if (!hideDuplicateSummary) const SizedBox(height: 10),
            ],
            if (!hideDuplicateSummary)
              Text(
                text,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF1F2A44),
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (followUpRemainingMs > 0) ...<Widget>[
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Text(
                    '还需要什么？',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF60708A),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  _CountdownRing(progress: followUpProgress),
                  const SizedBox(width: 8),
                  Text(
                    '${(followUpRemainingMs / 1000).ceil()}s',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: const Color(0xFF60708A),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CountdownBadge extends StatelessWidget {
  const _CountdownBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD3E0FF)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF2F6BFF),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _CountdownRing extends StatelessWidget {
  const _CountdownRing({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          CircularProgressIndicator(
            value: progress,
            strokeWidth: 2.4,
            backgroundColor: const Color(0xFFDCE7FF),
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF2F6BFF)),
          ),
          const Center(
            child: Icon(
              Icons.mic_none_rounded,
              size: 10,
              color: Color(0xFF2F6BFF),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.auto_awesome_rounded,
              color: Color(0xFFB7C3D9),
              size: 28,
            ),
            SizedBox(height: 12),
            Text(
              '问问小治试试\n比如"今天天气怎么样"',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF7A8798),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InputBar extends StatefulWidget {
  const _InputBar({
    required this.controller,
    required this.disabled,
    required this.listening,
    required this.listeningMode,
    required this.onSend,
    required this.onMicLongPressStart,
    required this.onMicLongPressEnd,
    required this.onMicLongPressCancel,
  });

  final TextEditingController controller;
  final bool disabled;
  final bool listening;
  final AssistantListeningMode listeningMode;
  final VoidCallback onSend;
  final VoidCallback onMicLongPressStart;
  final VoidCallback onMicLongPressEnd;
  final VoidCallback onMicLongPressCancel;

  @override
  State<_InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<_InputBar> {
  late final FocusNode _focusNode = FocusNode()
    ..addListener(() {
      if (mounted) {
        setState(() {});
      }
    });

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool focused = _focusNode.hasFocus;
    final String hint = widget.listening
        ? (widget.listeningMode == AssistantListeningMode.pressToTalk
              ? '松开手发送'
              : '正在听，你可以直接说')
        : (widget.disabled ? '小治回答中...' : '输入问题，或长按麦克风说话');

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: focused ? const Color(0xFF2F6BFF) : const Color(0xFFD9E3F7),
          width: focused ? 1.4 : 1,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: focused ? const Color(0x1F2F6BFF) : const Color(0x120D47A1),
            blurRadius: focused ? 18 : 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPressStart: (_) => widget.onMicLongPressStart(),
            onLongPressEnd: (_) => widget.onMicLongPressEnd(),
            onLongPressCancel: widget.onMicLongPressCancel,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 42,
              height: 42,
              margin: const EdgeInsets.only(right: 10, bottom: 2),
              decoration: BoxDecoration(
                color: widget.listening
                    ? const Color(0xFF2F6BFF)
                    : const Color(0xFFF3F6FC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: widget.listening
                      ? const Color(0xFF2F6BFF)
                      : const Color(0xFFD9E3F7),
                ),
              ),
              alignment: Alignment.center,
              child: Icon(
                widget.listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                color: widget.listening
                    ? Colors.white
                    : const Color(0xFF60708A),
                size: 22,
              ),
            ),
          ),
          Expanded(
            child: TextField(
              focusNode: _focusNode,
              controller: widget.controller,
              enabled: !widget.disabled,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              scrollPadding: const EdgeInsets.only(bottom: 16),
              onTapOutside: (_) => _focusNode.unfocus(),
              onSubmitted: (_) => widget.onSend(),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF6F8FC),
                hintText: hint,
                hintStyle: const TextStyle(
                  color: Color(0xFF98A6BE),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                contentPadding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(
                    color: Color(0x332F6BFF),
                    width: 1,
                  ),
                ),
              ),
              style: const TextStyle(
                color: Color(0xFF1F2A44),
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 10),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: widget.disabled
                    ? const <Color>[Color(0xFFCFD8E8), Color(0xFFCFD8E8)]
                    : const <Color>[Color(0xFF3C7BFF), Color(0xFF225CFF)],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: widget.disabled
                  ? const <BoxShadow>[]
                  : const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x332F6BFF),
                        blurRadius: 12,
                        offset: Offset(0, 6),
                      ),
                    ],
            ),
            child: IconButton(
              tooltip: '发送',
              icon: const Icon(Icons.arrow_upward_rounded),
              color: Colors.white,
              onPressed: widget.disabled ? null : widget.onSend,
            ),
          ),
        ],
      ),
    );
  }
}
