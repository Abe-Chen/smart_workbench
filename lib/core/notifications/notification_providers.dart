import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/application/app_settings_controller.dart';
import '../../features/task/domain/task.dart';
import '../database/database_providers.dart';
import 'local_notification_service.dart';

final appInForegroundProvider = StateProvider<bool>((Ref ref) => true);

final localNotificationServiceProvider = Provider<LocalNotificationService>((
  Ref ref,
) {
  return LocalNotificationService();
});

final reminderSyncControllerProvider = Provider<ReminderSyncController>((
  Ref ref,
) {
  return ReminderSyncController(ref);
});

final foregroundReminderControllerProvider =
    Provider<ForegroundReminderController>((Ref ref) {
      final ForegroundReminderController controller =
          ForegroundReminderController(ref);
      ref.onDispose(controller.dispose);
      return controller;
    });

final appBootstrapProvider = FutureProvider<void>((Ref ref) async {
  await ref.read(localNotificationServiceProvider).initialize();
});

class ReminderSyncController {
  const ReminderSyncController(this._ref);

  final Ref _ref;

  Future<void> syncNow() async {
    final LocalNotificationService notificationService = _ref.read(
      localNotificationServiceProvider,
    );
    if (_ref.read(appInForegroundProvider)) {
      await notificationService.cancelAllNotifications();
      return;
    }

    final List<Task> tasks = await _ref
        .read(taskRepositoryProvider)
        .listReminderEligibleTasks();
    final bool remindersEnabled = (await _ref.read(
      appSettingsControllerProvider.future,
    )).remindersEnabled;

    await notificationService.syncTaskReminders(
      tasks: tasks,
      remindersEnabled: remindersEnabled,
    );
  }
}

class ForegroundReminderController {
  ForegroundReminderController(this._ref);

  static const Duration _pollInterval = Duration(seconds: 15);
  static const Duration _pollLookback = Duration(seconds: 20);
  static const Duration _shownKeepAlive = Duration(days: 3);

  final Ref _ref;
  final Map<String, DateTime> _shownReminderKeys = <String, DateTime>{};

  Timer? _pollTimer;
  bool _running = false;

  Future<void> enterForeground() async {
    _ref.read(appInForegroundProvider.notifier).state = true;
    await _ref.read(localNotificationServiceProvider).cancelAllNotifications();

    if (_running) {
      return;
    }

    _running = true;
    await _checkDueReminders();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      unawaited(_checkDueReminders());
    });
  }

  Future<void> leaveForeground() async {
    _ref.read(appInForegroundProvider.notifier).state = false;
    _pollTimer?.cancel();
    _pollTimer = null;

    if (!_running) {
      await _ref.read(reminderSyncControllerProvider).syncNow();
      return;
    }

    _running = false;
    await _ref.read(reminderSyncControllerProvider).syncNow();
  }

  void dispose() {
    _pollTimer?.cancel();
  }

  Future<void> _checkDueReminders() async {
    if (!_running) {
      return;
    }

    final bool remindersEnabled = (await _ref.read(
      appSettingsControllerProvider.future,
    )).remindersEnabled;
    if (!_running || !remindersEnabled) {
      return;
    }

    final DateTime now = DateTime.now();
    _pruneShownReminderKeys(now);

    final List<Task> tasks = await _ref
        .read(taskRepositoryProvider)
        .listReminderEligibleTasks();
    if (!_running) {
      return;
    }
    final List<ReminderOccurrence> dueReminders = _ref
        .read(localNotificationServiceProvider)
        .dueRemindersForWindow(
          tasks: tasks,
          from: now.subtract(_pollLookback),
          to: now.add(const Duration(seconds: 1)),
        );

    for (final ReminderOccurrence reminder in dueReminders) {
      if (_shownReminderKeys.containsKey(reminder.sessionKey)) {
        continue;
      }
      _shownReminderKeys[reminder.sessionKey] = now;
      _ref
          .read(localNotificationServiceProvider)
          .emitInAppReminder(reminder.payload);
    }
  }

  void _pruneShownReminderKeys(DateTime now) {
    _shownReminderKeys.removeWhere(
      (_, DateTime shownAt) => now.difference(shownAt) > _shownKeepAlive,
    );
  }
}
