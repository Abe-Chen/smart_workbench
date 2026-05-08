import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_providers.dart';
import '../../../core/notifications/notification_providers.dart';
import '../domain/app_settings.dart';

final appSettingsControllerProvider =
    AsyncNotifierProvider<AppSettingsController, AppSettings>(
      AppSettingsController.new,
    );

class AppSettingsController extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() {
    return ref.read(settingsRepositoryProvider).loadSettings();
  }

  Future<void> setRemindersEnabled(bool value) async {
    await _save(
      state.valueOrNull?.copyWith(remindersEnabled: value) ??
          AppSettings(remindersEnabled: value),
    );
  }

  Future<void> setShowCompleted(bool value) async {
    await _save(
      state.valueOrNull?.copyWith(showCompleted: value) ??
          AppSettings(showCompleted: value),
    );
  }

  Future<void> setShowLunar(bool value) async {
    await _save(
      state.valueOrNull?.copyWith(showLunar: value) ??
          AppSettings(showLunar: value),
    );
  }

  Future<void> setTtsVoice(String value) async {
    final String normalized = normalizeTtsVoiceCode(value);
    await _save(
      state.valueOrNull?.copyWith(ttsVoice: normalized) ??
          AppSettings(ttsVoice: normalized),
    );
  }

  Future<void> setTtsPlaybackMode(TtsPlaybackMode value) async {
    await _save(
      state.valueOrNull?.copyWith(ttsPlaybackMode: value) ??
          AppSettings(ttsPlaybackMode: value),
    );
  }

  Future<void> setTtsSpeed(double value) async {
    final double normalized = normalizeTtsSpeed(value);
    await _save(
      state.valueOrNull?.copyWith(ttsSpeed: normalized) ??
          AppSettings(ttsSpeed: normalized),
    );
  }

  Future<void> _save(AppSettings next) async {
    state = AsyncData(next);
    final AppSettings saved = await ref
        .read(settingsRepositoryProvider)
        .saveSettings(next);
    await ref.read(reminderSyncControllerProvider).syncNow();
    state = AsyncData(saved);
  }
}

final Provider<String> currentTtsVoiceProvider = Provider<String>((Ref ref) {
  return ref.watch(appSettingsControllerProvider).valueOrNull?.ttsVoice ??
      kDefaultTtsVoice;
});

final Provider<TtsPlaybackMode> currentTtsPlaybackModeProvider =
    Provider<TtsPlaybackMode>((Ref ref) {
      return ref
              .watch(appSettingsControllerProvider)
              .valueOrNull
              ?.ttsPlaybackMode ??
          kDefaultTtsPlaybackMode;
    });

final Provider<double> currentTtsSpeedProvider = Provider<double>((Ref ref) {
  return ref.watch(appSettingsControllerProvider).valueOrNull?.ttsSpeed ??
      kDefaultTtsSpeed;
});
