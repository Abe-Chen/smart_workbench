import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../application/assistant_state.dart';

class VoiceEchoBar extends StatelessWidget {
  const VoiceEchoBar({
    required this.voiceEcho,
    this.compact = false,
    this.embedded = false,
    this.onCancel,
    super.key,
  });

  final AssistantVoiceEchoState voiceEcho;
  final bool compact;
  final bool embedded;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    if (!voiceEcho.isVisible) {
      return const SizedBox.shrink();
    }
    final _VoiceEchoStyle style = _styleFor(voiceEcho.phase);
    final String label = _labelFor(voiceEcho);
    final String text = _contentTextFor(voiceEcho);
    final bool showCountdown =
        voiceEcho.phase == AssistantVoiceEchoPhase.listening &&
        voiceEcho.partialText.trim().isEmpty &&
        voiceEcho.remainingMs > 0;
    final BorderRadius borderRadius = BorderRadius.circular(
      compact || embedded ? 18 : 22,
    );
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          constraints: BoxConstraints(minHeight: compact ? 48 : 60),
          decoration: BoxDecoration(
            color: (embedded ? Colors.white : const Color(0xFFFDFEFF))
                .withValues(alpha: embedded ? 0.86 : 0.9),
            borderRadius: borderRadius,
            border: Border.all(
              color: style.borderColor.withValues(alpha: embedded ? 0.72 : 1),
            ),
            boxShadow: embedded
                ? const <BoxShadow>[]
                : const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x180D47A1),
                      blurRadius: 22,
                      offset: Offset(0, 10),
                    ),
                  ],
          ),
          padding: EdgeInsets.fromLTRB(
            compact ? 10 : 12,
            compact ? 8 : 10,
            onCancel == null ? (compact ? 10 : 12) : 6,
            compact ? 8 : 10,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _StatusGlyph(style: style, compact: compact),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: style.accent,
                        fontSize: compact ? 10.5 : 11,
                        fontWeight: FontWeight.w800,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      text,
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: style.textColor,
                        fontSize: compact ? 12.5 : 13.5,
                        fontWeight: FontWeight.w700,
                        height: 1.28,
                      ),
                    ),
                  ],
                ),
              ),
              if (voiceEcho.phase == AssistantVoiceEchoPhase.listening &&
                  !compact) ...<Widget>[
                const SizedBox(width: 10),
                _MiniVoiceWave(accent: style.accent),
              ],
              if (voiceEcho.phase == AssistantVoiceEchoPhase.processing)
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: SizedBox(
                    width: compact ? 14 : 16,
                    height: compact ? 14 : 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(style.accent),
                    ),
                  ),
                ),
              if (showCountdown)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _CountdownBadge(
                    label: '${(voiceEcho.remainingMs / 1000).ceil()}s',
                    accent: style.accent,
                  ),
                ),
              if (onCancel != null)
                IconButton(
                  tooltip: '取消',
                  icon: const Icon(Icons.close_rounded, size: 19),
                  color: const Color(0xFF7A8798),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 34,
                    minHeight: 34,
                  ),
                  onPressed: onCancel,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _labelFor(AssistantVoiceEchoState state) {
    switch (state.phase) {
      case AssistantVoiceEchoPhase.listening:
        return state.partialText.trim().isEmpty ? '正在听' : '正在识别';
      case AssistantVoiceEchoPhase.finalText:
        return state.cleaned ? '已理解' : '已识别';
      case AssistantVoiceEchoPhase.processing:
        return '处理中';
      case AssistantVoiceEchoPhase.error:
        return '识别异常';
      case AssistantVoiceEchoPhase.hidden:
        return '';
    }
  }

  String _contentTextFor(AssistantVoiceEchoState state) {
    final String displayText = state.displayText.trim();
    if (displayText.isNotEmpty) {
      return _stripKnownPrefix(displayText);
    }
    switch (state.phase) {
      case AssistantVoiceEchoPhase.listening:
        final String partial = state.partialText.trim();
        return partial.isEmpty ? '我在听，你可以直接说' : partial;
      case AssistantVoiceEchoPhase.finalText:
      case AssistantVoiceEchoPhase.processing:
        final String finalText = state.finalText.trim();
        return finalText.isEmpty ? '我在处理你刚说的内容' : finalText;
      case AssistantVoiceEchoPhase.error:
        return '这次没听清';
      case AssistantVoiceEchoPhase.hidden:
        return '';
    }
  }

  String _stripKnownPrefix(String text) {
    return text.replaceFirst(RegExp(r'^(识别中|听到|我理解为|正在处理)[：:]'), '').trim();
  }
}

class _StatusGlyph extends StatelessWidget {
  const _StatusGlyph({required this.style, required this.compact});

  final _VoiceEchoStyle style;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final double size = compact ? 30 : 34;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: style.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(compact ? 12 : 14),
                border: Border.all(color: style.accent.withValues(alpha: 0.16)),
              ),
            ),
          ),
          Center(child: Icon(style.icon, color: style.accent, size: 17)),
          if (style.live)
            Positioned(
              right: 4,
              top: 4,
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: style.accent,
                  shape: BoxShape.circle,
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: style.accent.withValues(alpha: 0.36),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _VoiceEchoStyle {
  const _VoiceEchoStyle({
    required this.accent,
    required this.borderColor,
    required this.textColor,
    required this.icon,
    this.live = false,
  });

  final Color accent;
  final Color borderColor;
  final Color textColor;
  final IconData icon;
  final bool live;
}

_VoiceEchoStyle _styleFor(AssistantVoiceEchoPhase phase) {
  switch (phase) {
    case AssistantVoiceEchoPhase.listening:
      return const _VoiceEchoStyle(
        accent: Color(0xFF2F6BFF),
        borderColor: Color(0xFFDDE6F5),
        textColor: Color(0xFF273449),
        icon: Icons.mic_rounded,
        live: true,
      );
    case AssistantVoiceEchoPhase.finalText:
      return const _VoiceEchoStyle(
        accent: Color(0xFF16A078),
        borderColor: Color(0xFFDDEBE8),
        textColor: Color(0xFF273449),
        icon: Icons.check_rounded,
      );
    case AssistantVoiceEchoPhase.processing:
      return const _VoiceEchoStyle(
        accent: Color(0xFF5B6B8A),
        borderColor: Color(0xFFE0E6EF),
        textColor: Color(0xFF273449),
        icon: Icons.auto_awesome_rounded,
      );
    case AssistantVoiceEchoPhase.error:
      return const _VoiceEchoStyle(
        accent: Color(0xFFE14D3A),
        borderColor: Color(0xFFF1D8D3),
        textColor: Color(0xFF7A241A),
        icon: Icons.error_outline_rounded,
      );
    case AssistantVoiceEchoPhase.hidden:
      return const _VoiceEchoStyle(
        accent: Color(0xFF7A8798),
        borderColor: Color(0xFFE4EAF2),
        textColor: Color(0xFF4F6078),
        icon: Icons.mic_none_rounded,
      );
  }
}

class _MiniVoiceWave extends StatelessWidget {
  const _MiniVoiceWave({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    const List<double> heights = <double>[8, 14, 10, 17];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < heights.length; i++) ...<Widget>[
          Container(
            width: 2.5,
            height: heights[i],
            decoration: BoxDecoration(
              color: accent.withValues(alpha: i.isEven ? 0.48 : 0.28),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          if (i < heights.length - 1) const SizedBox(width: 3),
        ],
      ],
    );
  }
}

class _CountdownBadge extends StatelessWidget {
  const _CountdownBadge({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.16)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: accent,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
