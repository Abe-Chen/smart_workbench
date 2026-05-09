import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'voice_player_service.dart';
import 'voice_recorder_service.dart';

final voiceRecorderServiceProvider = Provider<VoiceRecorderService>((Ref ref) {
  final VoiceRecorderService service = VoiceRecorderService();
  ref.onDispose(service.dispose);
  return service;
});

final voicePlayerServiceProvider = Provider<VoicePlayerService>((Ref ref) {
  final VoicePlayerService service = VoicePlayerService();
  ref.onDispose(service.dispose);
  return service;
});

/// 当前麦克风的实时归一化 RMS 能量（0.0-1.0）。
/// 仅在 listen 阶段有有效值，停麦后归零。
/// 用 ValueNotifier 而非 StateProvider，方便 UI 通过 AnimatedBuilder
/// 直接监听，避免 25Hz 高频更新触发 widget tree rebuild。
final Provider<ValueNotifier<double>> liveAudioLevelProvider =
    Provider<ValueNotifier<double>>((Ref ref) {
      final ValueNotifier<double> notifier = ValueNotifier<double>(0.0);
      ref.onDispose(notifier.dispose);
      return notifier;
    });
