import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../application/assistant_state.dart';

class AssistantBall extends StatefulWidget {
  const AssistantBall({
    required this.stage,
    this.countdownProgress = 0,
    this.size = 48,
    this.audioLevel,
    this.listenWindowRemainingMs = 0,
    super.key,
  });

  final AssistantStage stage;
  final double countdownProgress;
  final double size;

  /// 实时麦克风能量 0.0-1.0，用于在 listen 阶段驱动光环脉动；
  /// 非 listen 阶段忽略。
  final ValueListenable<double>? audioLevel;

  /// 开麦倒计时余量。只在 listen 且 0 < ms <= 3000 时触发"快超时"视觉档：
  /// 暖橙色调 + 呼吸节奏加快，给用户视觉暗示该开口。
  final int listenWindowRemainingMs;

  bool get _urgent =>
      stage == AssistantStage.listen &&
      listenWindowRemainingMs > 0 &&
      listenWindowRemainingMs <= 3000;

  @override
  State<AssistantBall> createState() => _AssistantBallState();
}

class _AssistantBallState extends State<AssistantBall>
    with TickerProviderStateMixin {
  static const Duration _kIdleNormal = Duration(milliseconds: 2000);
  static const Duration _kIdleUrgent = Duration(milliseconds: 600);

  late final AnimationController _idleCtrl = AnimationController(
    vsync: this,
    duration: _kIdleNormal,
  )..repeat();

  late final AnimationController _spinCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void didUpdateWidget(covariant AssistantBall oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget._urgent != oldWidget._urgent) {
      _idleCtrl.duration = widget._urgent ? _kIdleUrgent : _kIdleNormal;
      _idleCtrl
        ..stop()
        ..repeat();
    }
  }

  @override
  void dispose() {
    _idleCtrl.dispose();
    _spinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double s = widget.size;
    final _BallStageStyle style = _styleForStage(
      widget.stage,
      urgent: widget._urgent,
    );
    final ValueListenable<double>? level =
        widget.stage == AssistantStage.listen ? widget.audioLevel : null;
    return SizedBox(
      width: s,
      height: s,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          _AmbientGlow(
            controller: _idleCtrl,
            color: style.glowColor,
            size: s,
            active: widget.stage != AssistantStage.idle,
            audioLevel: level,
          ),
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
              widget.stage == AssistantStage.answer ||
              widget.stage == AssistantStage.confirm)
            _RippleHalo(controller: _idleCtrl, size: s, color: style.glowColor),
          AnimatedScale(
            scale: widget.stage == AssistantStage.idle ? 1.0 : 1.08,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              width: s * 0.78,
              height: s * 0.78,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: style.gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.88),
                  width: 3,
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: style.glowColor.withValues(alpha: 0.28),
                    blurRadius: widget.stage == AssistantStage.idle ? 16 : 24,
                    offset: Offset(0, 6),
                  ),
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.48),
                    blurRadius: 10,
                    offset: const Offset(-3, -3),
                  ),
                ],
              ),
              child: _BallInner(
                stage: widget.stage,
                spin: _spinCtrl,
                color: style.foregroundColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BallStageStyle {
  const _BallStageStyle({
    required this.gradient,
    required this.glowColor,
    required this.foregroundColor,
  });

  final List<Color> gradient;
  final Color glowColor;
  final Color foregroundColor;
}

_BallStageStyle _styleForStage(AssistantStage stage, {bool urgent = false}) {
  if (urgent && stage == AssistantStage.listen) {
    return const _BallStageStyle(
      gradient: <Color>[Color(0xFFFFB36C), Color(0xFFFFA374)],
      glowColor: Color(0xFFFFA374),
      foregroundColor: Colors.white,
    );
  }
  switch (stage) {
    case AssistantStage.listen:
      return const _BallStageStyle(
        gradient: <Color>[Color(0xFF28D8FF), Color(0xFF315CFF)],
        glowColor: Color(0xFF28D8FF),
        foregroundColor: Colors.white,
      );
    case AssistantStage.think:
      return const _BallStageStyle(
        gradient: <Color>[Color(0xFF7C68FF), Color(0xFF2F6BFF)],
        glowColor: Color(0xFF7C68FF),
        foregroundColor: Colors.white,
      );
    case AssistantStage.answer:
      return const _BallStageStyle(
        gradient: <Color>[Color(0xFF19C7BD), Color(0xFF2F6BFF)],
        glowColor: Color(0xFF19C7BD),
        foregroundColor: Colors.white,
      );
    case AssistantStage.confirm:
      return const _BallStageStyle(
        gradient: <Color>[Color(0xFFFFB36C), Color(0xFF2F6BFF)],
        glowColor: Color(0xFFFFA374),
        foregroundColor: Colors.white,
      );
    case AssistantStage.error:
      return const _BallStageStyle(
        gradient: <Color>[Color(0xFFFF7A6D), Color(0xFFE14D3A)],
        glowColor: Color(0xFFE14D3A),
        foregroundColor: Colors.white,
      );
    case AssistantStage.idle:
      return const _BallStageStyle(
        gradient: <Color>[Color(0xFF71C8FF), Color(0xFF5665FF)],
        glowColor: Color(0xFF5665FF),
        foregroundColor: Colors.white,
      );
  }
}

class _BallInner extends StatelessWidget {
  const _BallInner({
    required this.stage,
    required this.spin,
    required this.color,
  });

  final AssistantStage stage;
  final AnimationController spin;
  final Color color;

  @override
  Widget build(BuildContext context) {
    switch (stage) {
      case AssistantStage.think:
        return _ThinkingOrbit(controller: spin, color: color);
      case AssistantStage.answer:
        return _VoiceBars(controller: spin, color: color);
      case AssistantStage.error:
        return Icon(Icons.error_outline_rounded, color: color, size: 20);
      case AssistantStage.listen:
        return _ListeningGlyph(controller: spin, color: color);
      case AssistantStage.confirm:
        return Icon(Icons.task_alt_rounded, color: color, size: 20);
      case AssistantStage.idle:
        return Icon(Icons.auto_awesome_rounded, color: color, size: 18);
    }
  }
}

class _ThinkingOrbit extends StatelessWidget {
  const _ThinkingOrbit({required this.controller, required this.color});

  final AnimationController controller;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, _) {
        return Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Icon(Icons.auto_awesome_rounded, color: color, size: 12),
            for (int i = 0; i < 3; i++)
              Transform.translate(
                offset: Offset.fromDirection(
                  controller.value * math.pi * 2 + i * math.pi * 2 / 3,
                  10,
                ),
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.9),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ListeningGlyph extends StatelessWidget {
  const _ListeningGlyph({required this.controller, required this.color});

  final AnimationController controller;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.mic_rounded, color: color, size: 14),
            const SizedBox(width: 2),
            for (int i = 0; i < 3; i++) ...<Widget>[
              _Bar(
                progress: controller.value,
                phase: i / 3,
                color: color.withValues(alpha: 0.9),
                minHeight: 4,
                maxHeight: 13,
              ),
              if (i < 2) const SizedBox(width: 1.6),
            ],
          ],
        );
      },
    );
  }
}

class _VoiceBars extends StatelessWidget {
  const _VoiceBars({required this.controller, required this.color});

  final AnimationController controller;
  final Color color;

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
              _Bar(
                progress: controller.value,
                phase: i / 5,
                color: color,
                minHeight: 4,
                maxHeight: 16,
              ),
              if (i < 4) const SizedBox(width: 2),
            ],
          ],
        );
      },
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.progress,
    required this.phase,
    required this.color,
    required this.minHeight,
    required this.maxHeight,
  });

  final double progress;
  final double phase;
  final Color color;
  final double minHeight;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final double t = (progress + phase) % 1.0;
    final double wave = 0.5 + 0.5 * math.sin(t * math.pi * 2);
    final double height = minHeight + (maxHeight - minHeight) * wave;
    return Container(
      width: 2.5,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _AmbientGlow extends StatelessWidget {
  const _AmbientGlow({
    required this.controller,
    required this.color,
    required this.size,
    required this.active,
    this.audioLevel,
  });

  final AnimationController controller;
  final Color color;
  final double size;
  final bool active;
  final ValueListenable<double>? audioLevel;

  @override
  Widget build(BuildContext context) {
    final Listenable merged = audioLevel == null
        ? controller
        : Listenable.merge(<Listenable>[controller, audioLevel!]);
    return AnimatedBuilder(
      animation: merged,
      builder: (BuildContext context, _) {
        final double level = audioLevel?.value ?? 0.0;
        // 把 RMS（0.0-1.0，实际说话约 0.02-0.3）放大映射到 0-0.6 的脉动增益
        final double levelBoost = (level * 4.0).clamp(0.0, 0.6);
        final double basePulse = active
            ? 0.78 + 0.12 * math.sin(controller.value * math.pi * 2)
            : 0.7;
        final double pulse = (basePulse + levelBoost * 0.5).clamp(0.4, 1.6);
        final double baseOpacity = active
            ? 0.28 + 0.08 * math.sin(controller.value * math.pi * 2)
            : 0.16;
        final double opacity =
            (baseOpacity + levelBoost * 0.4).clamp(0.0, 0.85);
        return IgnorePointer(
          child: Container(
            width: size * pulse,
            height: size * pulse,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: color.withValues(alpha: opacity),
                  blurRadius: active ? 34 : 20,
                  spreadRadius: active ? 6 : 1,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RippleHalo extends StatelessWidget {
  const _RippleHalo({
    required this.controller,
    required this.size,
    required this.color,
  });

  final AnimationController controller;
  final double size;
  final Color color;

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
            color: color.withValues(alpha: opacity),
            width: 1.6,
          ),
        ),
      ),
    );
  }
}
