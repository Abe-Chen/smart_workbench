import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/notifications/local_notification_service.dart';
import '../core/notifications/notification_providers.dart';
import '../core/utils/calendar_utils.dart';
import '../features/home/application/home_view_mode.dart';
import '../features/task/application/task_providers.dart';
import 'router.dart';
import 'theme.dart';

class SmartWorkbenchApp extends ConsumerStatefulWidget {
  const SmartWorkbenchApp({super.key});

  @override
  ConsumerState<SmartWorkbenchApp> createState() => _SmartWorkbenchAppState();
}

class _SmartWorkbenchAppState extends ConsumerState<SmartWorkbenchApp>
    with WidgetsBindingObserver {
  StreamSubscription<ReminderIntent>? _reminderSubscription;
  bool _bootstrapped = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_bootstrap());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reminderSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_bootstrapped) {
      return;
    }

    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(
          ref.read(foregroundReminderControllerProvider).enterForeground(),
        );
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        unawaited(
          ref.read(foregroundReminderControllerProvider).leaveForeground(),
        );
        break;
      case AppLifecycleState.inactive:
        break;
    }
  }

  Future<void> _bootstrap() async {
    await ref.read(appBootstrapProvider.future);

    final LocalNotificationService notificationService = ref.read(
      localNotificationServiceProvider,
    );
    _reminderSubscription = notificationService.reminderIntents.listen((
      ReminderIntent intent,
    ) {
      unawaited(_handleReminderIntent(intent));
    });

    for (final ReminderIntent intent
        in notificationService.consumePendingReminderIntents()) {
      unawaited(_handleReminderIntent(intent));
    }

    _bootstrapped = true;
    await ref.read(foregroundReminderControllerProvider).enterForeground();
  }

  Future<void> _handleReminderIntent(ReminderIntent intent) async {
    if (!mounted) {
      return;
    }

    switch (intent.action) {
      case ReminderIntentAction.openAlert:
        _openReminderAlert(intent.payload);
        break;
      case ReminderIntentAction.completeTask:
        await _completeReminderTask(intent.payload);
        break;
    }
  }

  Future<void> _completeReminderTask(ReminderPayload payload) async {
    _focusOccurrence(payload.occurrenceDate);
    await ref
        .read(taskMutationControllerProvider)
        .completeTaskById(
          taskId: payload.taskId,
          occurrenceDate: normalizeDate(payload.occurrenceDate),
        );
  }

  void _openReminderAlert(ReminderPayload payload) {
    _focusOccurrence(payload.occurrenceDate);
    final String route = Uri(
      path: '/reminder/${payload.taskId}',
      queryParameters: <String, String>{
        'date': normalizeDate(payload.occurrenceDate).toIso8601String(),
      },
    ).toString();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      appRouter.push(route);
    });
  }

  void _focusOccurrence(DateTime occurrenceDate) {
    ref.read(selectedDateProvider.notifier).state = normalizeDate(
      occurrenceDate,
    );
    ref.read(homeViewModeProvider.notifier).state = HomeViewMode.day;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '智办台',
      theme: buildScheduleBoardTheme(),
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
