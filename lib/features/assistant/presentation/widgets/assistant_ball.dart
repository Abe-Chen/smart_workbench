import 'package:flutter/material.dart';

import '../../application/assistant_state.dart';

class AssistantBall extends StatefulWidget {
  const AssistantBall({
    required this.stage,
    this.countdownProgress = 0,
    this.size = 48,
    super.key,
  });

  final AssistantStage stage;
  final double countdownProgress;
  final double size;

  @override
  State<AssistantBall> createState() => _AssistantBallState();
}

class _AssistantBallState extends State<AssistantBall>
    with TickerProviderStateMixin {
  late final AnimationController _idleCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  )..repeat();

  late final AnimationController _spinCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _idleCtrl.dispose();
    _spinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double s = widget.size;
    return SizedBox(
      width: s,
      height: s,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          if (widget.countdownProgress > 0 &&
              widget.stage == AssistantStage.idle)
            SizedBox(
              width: s,
              height: s,
              child: CircularProgressIndicator(
                value: widget.countdownProgress.clamp(0, 1),
                strokeWidth: 2.4,
                backgroundColor: const Color(0x22FFFFFF),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF8ED4FF),
                ),
              ),
            ),
          if (widget.stage == AssistantStage.listen ||
              widget.stage == AssistantStage.answer)
            _RippleHalo(controller: _idleCtrl, size: s),
          AnimatedScale(
            scale: widget.stage == AssistantStage.idle ? 1.0 : 1.1,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: Container(
              width: s * 0.78,
              height: s * 0.78,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: <Color>[Color(0xFF69C3FF), Color(0xFF545DFF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x334A5DFF),
                    blurRadius: 14,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: _BallInner(stage: widget.stage, spin: _spinCtrl),
            ),
          ),
        ],
      ),
    );
  }
}

class _BallInner extends StatelessWidget {
  const _BallInner({required this.stage, required this.spin});

  final AssistantStage stage;
  final AnimationController spin;

  @override
  Widget build(BuildContext context) {
    switch (stage) {
      case AssistantStage.think:
        return AnimatedBuilder(
          animation: spin,
          builder: (BuildContext context, _) {
            return Transform.rotate(
              angle: spin.value * 6.2832,
              child: const Icon(
                Icons.graphic_eq_rounded,
                color: Colors.white,
                size: 18,
              ),
            );
          },
        );
      case AssistantStage.answer:
        return _AnswerBars(controller: spin);
      case AssistantStage.error:
        return const Icon(
          Icons.error_outline_rounded,
          color: Colors.white,
          size: 20,
        );
      case AssistantStage.idle:
      case AssistantStage.listen:
      case AssistantStage.confirm:
        return const Icon(
          Icons.auto_awesome_rounded,
          color: Colors.white,
          size: 18,
        );
    }
  }
}

class _AnswerBars extends StatelessWidget {
  const _AnswerBars({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (int i = 0; i < 5; i++) ...<Widget>[
              _Bar(progress: controller.value, phase: i / 5),
              if (i < 4) const SizedBox(width: 2),
            ],
          ],
        );
      },
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.progress, required this.phase});

  final double progress;
  final double phase;

  @override
  Widget build(BuildContext context) {
    final double t = (progress + phase) % 1.0;
    final double height =
        4 + 12 * (0.5 + 0.5 * (t * 6.2832).clamp(-1, 1).abs());
    return Container(
      width: 2.5,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _RippleHalo extends StatelessWidget {
  const _RippleHalo({required this.controller, required this.size});

  final AnimationController controller;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, _) {
        return Stack(
          alignment: Alignment.center,
          children: <Widget>[
            for (int i = 0; i < 3; i++) _haloAt(controller.value, i, size),
          ],
        );
      },
    );
  }

  Widget _haloAt(double value, int index, double size) {
    final double t = (value + index / 3) % 1.0;
    final double scale = 0.85 + 0.5 * t;
    final double opacity = (1.0 - t).clamp(0.0, 1.0) * 0.45;
    return IgnorePointer(
      child: Container(
        width: size * scale,
        height: size * scale,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: const Color(0xFF545DFF).withValues(alpha: opacity),
            width: 1.6,
          ),
        ),
      ),
    );
  }
}
