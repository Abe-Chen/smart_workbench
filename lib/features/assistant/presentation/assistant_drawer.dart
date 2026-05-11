import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/voice/voice_providers.dart';
import '../application/assistant_controller.dart';
import '../application/assistant_state.dart';
import '../domain/assistant_message.dart';
import '../domain/assistant_proactive_suggestion.dart';
import '../domain/assistant_result_card.dart';
import 'widgets/assistant_ball.dart';
import 'widgets/assistant_run_status_card.dart';
import 'widgets/completion_undo_listener.dart';
import 'widgets/confirm_card.dart';
import 'widgets/full_screen_answer_card.dart';
import 'widgets/assistant_result_card_view.dart';
import 'widgets/message_bubble.dart';

/// workbench_shell 底部导航栏总占用高度（圆角条 94 + SafeArea.minimum bottom 10）。
/// 抽屉要在这之上停住，否则输入框会被导航栏盖住。
const double _kBottomNavReserve = 104;
const double _kDrawerEdgeGap = 12;
const double _kDrawerPeekSize = 0.15;
const double _kDrawerHalfSize = 0.6;
const double _kDrawerFullSize = 0.9;
const double _kDrawerMaxWidth = 980;
const double _kDrawerCompactHeight = 260;

class AssistantOverlay extends ConsumerWidget {
  const AssistantOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AssistantUiState state = ref.watch(assistantControllerProvider);
    final bool open = state.drawerOpen;
    final AnswerCardKind? answerKind = state.answerCardKind;
    final bool showFullscreenAnswer =
        !open &&
        state.surfaceState == AssistantSurfaceState.fullscreenAnswer &&
        answerKind != null;
    final EdgeInsets viewPadding = MediaQuery.viewPaddingOf(context);
    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final double topInset = viewPadding.top + _kDrawerEdgeGap;
    final double bottomInset =
        (keyboard > 0 ? keyboard : _kBottomNavReserve) + _kDrawerEdgeGap;

    return Stack(
      children: <Widget>[
        _AssistantEdgeGlow(
          stage: state.stage,
          visible:
              state.stage != AssistantStage.idle ||
              state.followUpRemainingMs > 0,
        ),
        if (showFullscreenAnswer)
          Positioned.fill(
            child: _FullscreenAnswerLayer(state: state, kind: answerKind),
          ),
        if (!open && !showFullscreenAnswer)
          Positioned(
            left: 0,
            right: 0,
            bottom: _kBottomNavReserve + 22,
            child: Center(child: _FloatingAssistantSurface(state: state)),
          ),
        Positioned(
          top: topInset,
          bottom: bottomInset,
          left: _kDrawerEdgeGap,
          right: _kDrawerEdgeGap,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (Widget child, Animation<double> animation) {
              final Animation<Offset> slide = Tween<Offset>(
                begin: const Offset(0, 1.08),
                end: Offset.zero,
              ).animate(animation);
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(position: slide, child: child),
              );
            },
            child: open
                ? const _AssistantDrawerSheet(key: ValueKey<String>('open'))
                : const SizedBox.shrink(key: ValueKey<String>('closed')),
          ),
        ),
      ],
    );
  }
}

class _FullscreenAnswerLayer extends ConsumerWidget {
  const _FullscreenAnswerLayer({required this.state, required this.kind});

  final AssistantUiState state;
  final AnswerCardKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AssistantController controller = ref.read(
      assistantControllerProvider.notifier,
    );
    final bool canClose = switch (kind) {
      AnswerCardKind.infoCard ||
      AnswerCardKind.toolFeedback ||
      AnswerCardKind.plainText ||
      AnswerCardKind.error => true,
      AnswerCardKind.clarification ||
      AnswerCardKind.confirm ||
      AnswerCardKind.reminder => false,
    };
    final bool canResetTimer = canClose;
    return FullScreenAnswerCard(
      kind: kind,
      message: state.answerCardText ?? '',
      resultCard: state.answerCardResultCard,
      pendingConfirm: kind == AnswerCardKind.confirm
          ? state.pendingConfirm
          : null,
      onClose: canClose ? () => controller.hideAnswerCard() : null,
      onExpand: controller.expandAnswerCardToDrawer,
      onInteract: canResetTimer ? controller.extendAnswerCardDisplay : null,
    );
  }
}

class _AssistantDrawerSheet extends StatefulWidget {
  const _AssistantDrawerSheet({super.key});

  @override
  State<_AssistantDrawerSheet> createState() => _AssistantDrawerSheetState();
}

class _AssistantDrawerSheetState extends State<_AssistantDrawerSheet> {
  final DraggableScrollableController _controller =
      DraggableScrollableController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleGrabberDragUpdate(
    DragUpdateDetails details,
    double availableHeight,
  ) {
    if (!_controller.isAttached || availableHeight <= 0) {
      return;
    }
    final double delta = details.primaryDelta ?? 0;
    final double nextSize = (_controller.size - delta / availableHeight).clamp(
      _kDrawerPeekSize,
      _kDrawerFullSize,
    );
    _controller.jumpTo(nextSize);
  }

  void _handleGrabberDragEnd(DragEndDetails details) {
    if (!_controller.isAttached) {
      return;
    }
    final double current = _controller.size;
    const List<double> snapSizes = <double>[
      _kDrawerPeekSize,
      _kDrawerHalfSize,
      _kDrawerFullSize,
    ];
    final double target = snapSizes.reduce((double a, double b) {
      return (current - a).abs() <= (current - b).abs() ? a : b;
    });
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kDrawerMaxWidth),
            child: DraggableScrollableSheet(
              controller: _controller,
              expand: false,
              minChildSize: _kDrawerPeekSize,
              initialChildSize: _kDrawerHalfSize,
              maxChildSize: _kDrawerFullSize,
              snap: true,
              snapSizes: const <double>[
                _kDrawerPeekSize,
                _kDrawerHalfSize,
                _kDrawerFullSize,
              ],
              builder:
                  (BuildContext context, ScrollController scrollController) {
                    return Material(
                      elevation: 0,
                      color: Colors.transparent,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: <Color>[
                                  Color(0xF8FFFFFF),
                                  Color(0xF1F6FAFF),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.72),
                              ),
                              boxShadow: const <BoxShadow>[
                                BoxShadow(
                                  color: Color(0x1F0D47A1),
                                  blurRadius: 34,
                                  offset: Offset(0, 14),
                                ),
                                BoxShadow(
                                  color: Color(0x18FFFFFF),
                                  blurRadius: 10,
                                  offset: Offset(-3, -3),
                                ),
                              ],
                            ),
                            child: _AssistantDrawerBody(
                              scrollController: scrollController,
                              onGrabberDragUpdate: (DragUpdateDetails details) {
                                _handleGrabberDragUpdate(
                                  details,
                                  constraints.maxHeight,
                                );
                              },
                              onGrabberDragEnd: _handleGrabberDragEnd,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
            ),
          ),
        );
      },
    );
  }
}

class _AssistantEdgeGlow extends StatefulWidget {
  const _AssistantEdgeGlow({required this.stage, required this.visible});

  final AssistantStage stage;
  final bool visible;

  @override
  State<_AssistantEdgeGlow> createState() => _AssistantEdgeGlowState();
}

class _AssistantEdgeGlowState extends State<_AssistantEdgeGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.visible) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _AssistantEdgeGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.visible && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final _EdgeGlowStyle style = _edgeGlowStyleFor(widget.stage);
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: widget.visible ? style.opacity : 0,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (BuildContext context, _) {
              return CustomPaint(
                painter: _EdgeGlowPainter(
                  progress: _controller.value,
                  primary: style.primary,
                  secondary: style.secondary,
                  strokeWidth: style.strokeWidth,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _EdgeGlowStyle {
  const _EdgeGlowStyle({
    required this.primary,
    required this.secondary,
    required this.opacity,
    required this.strokeWidth,
  });

  final Color primary;
  final Color secondary;
  final double opacity;
  final double strokeWidth;
}

_EdgeGlowStyle _edgeGlowStyleFor(AssistantStage stage) {
  switch (stage) {
    case AssistantStage.listen:
      return const _EdgeGlowStyle(
        primary: Color(0xFF28D8FF),
        secondary: Color(0xFF6A7BFF),
        opacity: 0.9,
        strokeWidth: 5.5,
      );
    case AssistantStage.think:
      return const _EdgeGlowStyle(
        primary: Color(0xFF7C68FF),
        secondary: Color(0xFF2F6BFF),
        opacity: 0.74,
        strokeWidth: 5,
      );
    case AssistantStage.answer:
      return const _EdgeGlowStyle(
        primary: Color(0xFF19C7BD),
        secondary: Color(0xFF2F6BFF),
        opacity: 0.62,
        strokeWidth: 4.5,
      );
    case AssistantStage.confirm:
      return const _EdgeGlowStyle(
        primary: Color(0xFFFFA374),
        secondary: Color(0xFF2F6BFF),
        opacity: 0.86,
        strokeWidth: 5.5,
      );
    case AssistantStage.error:
      return const _EdgeGlowStyle(
        primary: Color(0xFFE14D3A),
        secondary: Color(0xFFFFB1A8),
        opacity: 0.8,
        strokeWidth: 5.5,
      );
    case AssistantStage.idle:
      return const _EdgeGlowStyle(
        primary: Color(0xFF2F6BFF),
        secondary: Color(0xFF19C7BD),
        opacity: 0.24,
        strokeWidth: 4,
      );
  }
}

class _EdgeGlowPainter extends CustomPainter {
  const _EdgeGlowPainter({
    required this.progress,
    required this.primary,
    required this.secondary,
    required this.strokeWidth,
  });

  final double progress;
  final Color primary;
  final Color secondary;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }

    final Rect rect =
        Offset(strokeWidth + 2, strokeWidth + 2) &
        Size(
          size.width - (strokeWidth + 2) * 2,
          size.height - (strokeWidth + 2) * 2,
        );
    final RRect rrect = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(34),
    );
    final SweepGradient sweep = SweepGradient(
      transform: GradientRotation(progress * math.pi * 2),
      colors: <Color>[
        Colors.transparent,
        primary.withValues(alpha: 0.16),
        secondary.withValues(alpha: 0.95),
        primary.withValues(alpha: 0.72),
        Colors.transparent,
      ],
      stops: const <double>[0, 0.24, 0.48, 0.7, 1],
    );

    final Paint glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 6
      ..shader = sweep.createShader(rect)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawRRect(rrect, glowPaint);

    final Paint corePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = sweep.createShader(rect);
    canvas.drawRRect(rrect, corePaint);
  }

  @override
  bool shouldRepaint(covariant _EdgeGlowPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.primary != primary ||
        oldDelegate.secondary != secondary ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

class _AssistantDrawerBody extends ConsumerStatefulWidget {
  const _AssistantDrawerBody({
    required this.scrollController,
    required this.onGrabberDragUpdate,
    required this.onGrabberDragEnd,
  });

  final ScrollController scrollController;
  final GestureDragUpdateCallback onGrabberDragUpdate;
  final GestureDragEndCallback onGrabberDragEnd;

  @override
  ConsumerState<_AssistantDrawerBody> createState() =>
      _AssistantDrawerBodyState();
}

class _AssistantDrawerBodyState extends ConsumerState<_AssistantDrawerBody> {
  final TextEditingController _textCtrl = TextEditingController();

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!widget.scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!widget.scrollController.hasClients) return;
      widget.scrollController.animateTo(
        widget.scrollController.position.maxScrollExtent,
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
    final bool confirming = state.pendingConfirm != null;
    final bool inputBlocked = sending || listening || confirming;
    final bool micBlocked = sending;
    final bool showRunStatus =
        (state.stage == AssistantStage.think ||
            state.stage == AssistantStage.answer) &&
        (state.progress.status?.trim().isNotEmpty ?? false);
    final List<AssistantMessage> visibleMessages = state.messages
        .where((AssistantMessage m) => m.isVisibleInChat)
        .toList();

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxHeight < _kDrawerCompactHeight) {
          return _DrawerPeekBody(
            scrollController: widget.scrollController,
            stage: state.stage,
            onGrabberDragUpdate: widget.onGrabberDragUpdate,
            onGrabberDragEnd: widget.onGrabberDragEnd,
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: Column(
            children: <Widget>[
              const CompletionUndoListener(),
              _DrawerGrabber(
                onVerticalDragUpdate: widget.onGrabberDragUpdate,
                onVerticalDragEnd: widget.onGrabberDragEnd,
              ),
              const SizedBox(height: 10),
              _Header(stage: state.stage),
              const SizedBox(height: 10),
              const Divider(height: 1, color: Color(0xFFE8EEFB)),
              if (showRunStatus) ...<Widget>[
                const SizedBox(height: 10),
                AssistantRunStatusCard(progress: state.progress),
              ],
              Expanded(
                child: visibleMessages.isEmpty
                    ? ListView(
                        controller: widget.scrollController,
                        padding: EdgeInsets.zero,
                        children: const <Widget>[
                          SizedBox(height: 220, child: _EmptyHint()),
                        ],
                      )
                    : ListView.builder(
                        controller: widget.scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        itemCount: visibleMessages.length,
                        itemBuilder: (BuildContext context, int index) =>
                            MessageBubble(message: visibleMessages[index]),
                      ),
              ),
              if (state.pendingConfirm != null) ...<Widget>[
                ConfirmCard(pending: state.pendingConfirm!),
                const SizedBox(height: 8),
              ],
              if (state.proactiveSuggestion != null &&
                  state.pendingConfirm == null) ...<Widget>[
                _ProactiveSuggestionCard(
                  suggestion: state.proactiveSuggestion!,
                ),
                const SizedBox(height: 8),
              ],
              if (state.listenError != null && !listening)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    state.listenError!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFE14D3A),
                      fontSize: 12,
                    ),
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
                    style: const TextStyle(
                      color: Color(0xFFE14D3A),
                      fontSize: 12,
                    ),
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
                  disabled: inputBlocked,
                  disabledHint: confirming ? '先确认或取消这一步' : null,
                  listening: listening,
                  listeningMode: state.listeningMode,
                  micBlocked: micBlocked,
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
      },
    );
  }
}

class _DrawerPeekBody extends StatelessWidget {
  const _DrawerPeekBody({
    required this.scrollController,
    required this.stage,
    required this.onGrabberDragUpdate,
    required this.onGrabberDragEnd,
  });

  final ScrollController scrollController;
  final AssistantStage stage;
  final GestureDragUpdateCallback onGrabberDragUpdate;
  final GestureDragEndCallback onGrabberDragEnd;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      children: <Widget>[
        const CompletionUndoListener(),
        _DrawerGrabber(
          onVerticalDragUpdate: onGrabberDragUpdate,
          onVerticalDragEnd: onGrabberDragEnd,
        ),
        const SizedBox(height: 10),
        _Header(stage: stage),
        const SizedBox(height: 8),
        Center(
          child: Text(
            '上滑展开对话',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF7A8798),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _DrawerGrabber extends StatelessWidget {
  const _DrawerGrabber({
    required this.onVerticalDragUpdate,
    required this.onVerticalDragEnd,
  });

  final GestureDragUpdateCallback onVerticalDragUpdate;
  final GestureDragEndCallback onVerticalDragEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: onVerticalDragUpdate,
      onVerticalDragEnd: onVerticalDragEnd,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF9AA8BD).withValues(alpha: 0.58),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
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
    final bool hasSpeech = partialText.trim().isNotEmpty;
    final String hint = hasSpeech
        ? partialText.trim()
        : _defaultHintFor(listeningMode, remainingMs);
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFAFFFFFF), Color(0xF0EEF6FF)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x1F2F6BFF),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: <Color>[Color(0xFF28D8FF), Color(0xFF2F6BFF)],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x332F6BFF),
                  blurRadius: 14,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(Icons.mic_rounded, color: Colors.white, size: 21),
          ),
          const SizedBox(width: 10),
          const _MiniVoiceWave(),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hint,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: hasSpeech
                    ? const Color(0xFF1F2A44)
                    : const Color(0xFF60708A),
                fontSize: hasSpeech ? 14 : 13,
                fontWeight: hasSpeech ? FontWeight.w800 : FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
          if (listeningMode == AssistantListeningMode.openMic &&
              remainingMs > 0)
            Padding(
              padding: const EdgeInsets.only(left: 8, right: 2),
              child: _CountdownBadge(label: '${(remainingMs / 1000).ceil()}s'),
            ),
          IconButton(
            tooltip: '取消',
            icon: const Icon(Icons.close_rounded, size: 20),
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

class _ProactiveSuggestionCard extends ConsumerWidget {
  const _ProactiveSuggestionCard({required this.suggestion});

  final AssistantProactiveSuggestion suggestion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
      decoration: BoxDecoration(
        color: const Color(0xFFF6FAFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDCE7F8)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x100D47A1),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: <Color>[Color(0xFF71C8FF), Color(0xFF5665FF)],
                  ),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  suggestion.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF22324C),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                tooltip: '关闭建议',
                icon: const Icon(Icons.close_rounded, size: 18),
                color: const Color(0xFF7A8798),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () => ref
                    .read(assistantControllerProvider.notifier)
                    .dismissProactiveSuggestion(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            suggestion.message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF4F6078),
              fontSize: 12.5,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final AssistantProactiveAction action in suggestion.actions)
                _SuggestionActionChip(action: action),
            ],
          ),
        ],
      ),
    );
  }
}

class _SuggestionActionChip extends ConsumerWidget {
  const _SuggestionActionChip({required this.action});

  final AssistantProactiveAction action;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool dismiss = action.dismissOnly;
    final Color color = dismiss
        ? const Color(0xFF7A8798)
        : const Color(0xFF2F6BFF);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 142),
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(
            color: dismiss ? const Color(0xFFD5DEEA) : const Color(0xFFBFD0FF),
          ),
          backgroundColor: dismiss ? Colors.white : const Color(0xFFEAF2FF),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          minimumSize: const Size(0, 36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: Icon(_suggestionActionIcon(action.kind), size: 16),
        label: Text(
          action.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
        ),
        onPressed: () => ref
            .read(assistantControllerProvider.notifier)
            .submitProactiveSuggestionAction(action.id),
      ),
    );
  }
}

IconData _suggestionActionIcon(AssistantProactiveActionKind kind) {
  switch (kind) {
    case AssistantProactiveActionKind.weather:
      return Icons.wb_sunny_outlined;
    case AssistantProactiveActionKind.tripPlan:
      return Icons.map_outlined;
    case AssistantProactiveActionKind.route:
      return Icons.near_me_outlined;
    case AssistantProactiveActionKind.checklist:
      return Icons.checklist_rounded;
    case AssistantProactiveActionKind.agenda:
      return Icons.format_list_bulleted_rounded;
    case AssistantProactiveActionKind.reminder:
      return Icons.notifications_active_outlined;
    case AssistantProactiveActionKind.dismiss:
      return Icons.close_rounded;
  }
}

class _MiniVoiceWave extends StatelessWidget {
  const _MiniVoiceWave();

  @override
  Widget build(BuildContext context) {
    const List<double> heights = <double>[10, 18, 13, 22, 12];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < heights.length; i++) ...<Widget>[
          Container(
            width: 3,
            height: heights[i],
            decoration: BoxDecoration(
              color: const Color(
                0xFF2F6BFF,
              ).withValues(alpha: i.isEven ? 0.72 : 0.42),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          if (i < heights.length - 1) const SizedBox(width: 3),
        ],
      ],
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.stage});
  final AssistantStage stage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AssistantSessionMute sessionMute = ref.watch(
      assistantControllerProvider.select((AssistantUiState s) => s.sessionMute),
    );
    final bool hasPendingConfirm = ref.watch(
      assistantControllerProvider.select(
        (AssistantUiState s) => s.pendingConfirm != null,
      ),
    );
    final bool isMuted = sessionMute == AssistantSessionMute.muted;
    final int remainingMs = ref.watch(
      assistantControllerProvider.select(
        (AssistantUiState s) => s.listenWindowRemainingMs,
      ),
    );
    final String statusLabel = hasPendingConfirm
        ? '等你确认一下'
        : _stageStatusLabel(stage);
    final Color statusColor = _stageAccentColor(stage);
    return Row(
      children: <Widget>[
        AssistantBall(
          stage: stage,
          size: 44,
          audioLevel: ref.read(liveAudioLevelProvider),
          listenWindowRemainingMs: remainingMs,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                '小治',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF22324C),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: <Widget>[
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: statusColor.withValues(alpha: 0.28),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      statusLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF7A8798),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: statusColor.withValues(alpha: 0.16)),
          ),
          child: Text(
            _stageShortLabel(stage, hasPendingConfirm),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: statusColor,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: isMuted ? '本会话已静音，点击恢复跟随设置' : '本会话静音（不写入设置）',
          icon: Icon(
            isMuted
                ? Icons.notifications_off_rounded
                : Icons.notifications_active_outlined,
            size: 22,
          ),
          color: isMuted ? const Color(0xFFFF5252) : const Color(0xFF7A8798),
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
          onPressed: hasPendingConfirm
              ? null
              : () => ref
                    .read(assistantControllerProvider.notifier)
                    .closeDrawer(),
        ),
      ],
    );
  }
}

String _stageStatusLabel(AssistantStage stage) {
  switch (stage) {
    case AssistantStage.listen:
      return '正在听你说话';
    case AssistantStage.think:
      return '正在整理上下文';
    case AssistantStage.answer:
      return '正在回答';
    case AssistantStage.confirm:
      return '等你确认一下';
    case AssistantStage.error:
      return '遇到问题，需要处理';
    case AssistantStage.idle:
      return '随时可以唤醒';
  }
}

String _stageShortLabel(AssistantStage stage, bool hasPendingConfirm) {
  if (hasPendingConfirm) {
    return '待确认';
  }
  switch (stage) {
    case AssistantStage.listen:
      return '听音中';
    case AssistantStage.think:
      return '处理中';
    case AssistantStage.answer:
      return '回答中';
    case AssistantStage.confirm:
      return '待确认';
    case AssistantStage.error:
      return '异常';
    case AssistantStage.idle:
      return '待命';
  }
}

Color _stageAccentColor(AssistantStage stage) {
  switch (stage) {
    case AssistantStage.listen:
      return const Color(0xFF0EA5E9);
    case AssistantStage.think:
      return const Color(0xFF6B5CFF);
    case AssistantStage.answer:
      return const Color(0xFF19AFA7);
    case AssistantStage.confirm:
      return const Color(0xFFFF8A3D);
    case AssistantStage.error:
      return const Color(0xFFE14D3A);
    case AssistantStage.idle:
      return const Color(0xFF2F6BFF);
  }
}

class _FloatingAssistantSurface extends ConsumerWidget {
  const _FloatingAssistantSurface({required this.state});

  final AssistantUiState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool showRunStatus =
        (state.stage == AssistantStage.think ||
            state.stage == AssistantStage.answer) &&
        (state.progress.status?.trim().isNotEmpty ?? false);
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

    if (showRunStatus) {
      return AssistantRunStatusCard(
        progress: state.progress,
        compact: true,
        showExpandAction: true,
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
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFFFFFFFF), Color(0xFFF3F8FF)],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x1F0D47A1),
              blurRadius: 28,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: <Color>[Color(0xFF71C8FF), Color(0xFF5665FF)],
                    ),
                    borderRadius: BorderRadius.circular(13),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x2F2F6BFF),
                        blurRadius: 12,
                        offset: Offset(0, 5),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: Colors.white,
                    size: 17,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '小治',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: const Color(0xFF22324C),
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      Text(
                        followUpRemainingMs > 0 ? '可以继续追问' : '结果已整理',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: const Color(0xFF7A8798),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                _CardIconButton(
                  tooltip: '再播一遍',
                  icon: Icons.volume_up_rounded,
                  onPressed: () => ref
                      .read(assistantControllerProvider.notifier)
                      .replayLatestAssistantReply(),
                ),
                _CardIconButton(
                  tooltip: '展开抽屉',
                  icon: Icons.open_in_full_rounded,
                  onPressed: () => ref
                      .read(assistantControllerProvider.notifier)
                      .openDrawer(),
                ),
                _CardIconButton(
                  tooltip: '关闭',
                  icon: Icons.close_rounded,
                  onPressed: () => ref
                      .read(assistantControllerProvider.notifier)
                      .hideCompactReply(),
                ),
              ],
            ),
            const SizedBox(height: 10),
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
                  fontWeight: FontWeight.w700,
                ),
              ),
            if (followUpRemainingMs > 0) ...<Widget>[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2FF),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFD3E0FF)),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(
                      Icons.mic_none_rounded,
                      size: 17,
                      color: Color(0xFF2F6BFF),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '还需要什么？',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF60708A),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    _CountdownRing(progress: followUpProgress),
                    const SizedBox(width: 8),
                    Text(
                      '${(followUpRemainingMs / 1000).ceil()}s',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: const Color(0xFF60708A),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CardIconButton extends StatelessWidget {
  const _CardIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 19),
      color: const Color(0xFF60708A),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      style: IconButton.styleFrom(
        backgroundColor: const Color(0xFFF4F7FC),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: onPressed,
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
    required this.micBlocked,
    required this.listening,
    required this.listeningMode,
    required this.onSend,
    required this.onMicLongPressStart,
    required this.onMicLongPressEnd,
    required this.onMicLongPressCancel,
    this.disabledHint,
  });

  final TextEditingController controller;
  final bool disabled;
  final bool micBlocked;
  final bool listening;
  final AssistantListeningMode listeningMode;
  final VoidCallback onSend;
  final VoidCallback onMicLongPressStart;
  final VoidCallback onMicLongPressEnd;
  final VoidCallback onMicLongPressCancel;
  final String? disabledHint;

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
        : (widget.disabled
              ? (widget.disabledHint ?? '小治回答中...')
              : '输入问题，或长按麦克风说话');
    final bool canUseMic = widget.listening || !widget.micBlocked;

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
            onLongPressStart: canUseMic
                ? (_) => widget.onMicLongPressStart()
                : null,
            onLongPressEnd: canUseMic
                ? (_) => widget.onMicLongPressEnd()
                : null,
            onLongPressCancel: canUseMic ? widget.onMicLongPressCancel : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 42,
              height: 42,
              margin: const EdgeInsets.only(right: 10, bottom: 2),
              decoration: BoxDecoration(
                color: widget.listening
                    ? const Color(0xFF2F6BFF)
                    : (widget.micBlocked
                          ? const Color(0xFFF6F8FC)
                          : const Color(0xFFF3F6FC)),
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
                    : (widget.micBlocked
                          ? const Color(0xFFB7C3D9)
                          : const Color(0xFF60708A)),
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
