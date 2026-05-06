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
