import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env_config.dart';
import '../../../core/voice/voice_wakeup_service.dart';
import 'assistant_controller.dart';
import 'assistant_state.dart';

final Provider<AssistantWakeupController> assistantWakeupControllerProvider =
    Provider<AssistantWakeupController>((Ref ref) {
      final AssistantWakeupController controller = AssistantWakeupController(
        ref,
      );
      ref.onDispose(controller.dispose);
      return controller;
    });

class AssistantWakeupController {
  AssistantWakeupController(this._ref);

  final Ref _ref;
  StreamSubscription<VoiceWakeupEvent>? _subscription;

  Future<VoiceWakeupStatus> start() async {
    final EnvConfig env = _ref.read(envConfigProvider);
    final VoiceWakeupConfig config = VoiceWakeupConfig.fromEnv(env);
    if (!config.hasCredentials) {
      return VoiceWakeupStatus.unsupported();
    }

    final VoiceWakeupService service = _ref.read(voiceWakeupServiceProvider);
    _subscription ??= service.events.listen(_handleEvent, onError: (_) {});
    final VoiceWakeupStatus current = await service.getStatus();
    if (current.running) {
      return current;
    }
    return service.start(config);
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    await _ref.read(voiceWakeupServiceProvider).stop();
  }

  void dispose() {
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  void _handleEvent(VoiceWakeupEvent event) {
    if (event.type != VoiceWakeupEventType.wake) {
      return;
    }
    final AssistantUiState state = _ref.read(assistantControllerProvider);
    if (state.stage == AssistantStage.listen ||
        state.stage == AssistantStage.think) {
      return;
    }
    unawaited(
      _ref
          .read(assistantControllerProvider.notifier)
          .startListening(
            source: AssistantEntrySource.quickVoice,
            openDrawer: false,
            mode: AssistantListeningMode.openMic,
          ),
    );
  }
}
