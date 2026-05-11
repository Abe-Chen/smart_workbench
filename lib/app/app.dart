import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/database_providers.dart';
import '../core/notifications/local_notification_service.dart';
import '../core/notifications/notification_providers.dart';
import '../core/utils/calendar_utils.dart';
import '../features/assistant/application/assistant_controller.dart';
import '../features/assistant/application/assistant_wakeup_controller.dart';
import '../features/assistant/presentation/widgets/answer_cards/answer_card_models.dart';
import '../features/home/application/home_view_mode.dart';
import '../features/task/application/task_providers.dart';
import '../features/task/domain/task.dart';
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
        unawaited(ref.read(assistantWakeupControllerProvider).start());
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
    await ref.read(assistantWakeupControllerProvider).start();
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

  Future<void> _openReminderAlert(ReminderPayload payload) async {
    _focusOccurrence(payload.occurrenceDate);
    // Phase 7：把"路由 push 独立提醒页"改为"走 AssistantController.enqueueReminder
    // 弹大卡 3g（按助手像人原则，TTS 中收到的提醒等播完才弹）"
    final Task? task = await ref
        .read(taskRepositoryProvider)
        .getTaskById(payload.taskId);
    if (!mounted) {
      return;
    }
    final String title = task?.title.trim().isNotEmpty == true
        ? task!.title.trim()
        : '提醒';
    final String timeLabel = _formatReminderTimeLabel(
      task,
      payload.occurrenceDate,
    );
    ref
        .read(assistantControllerProvider.notifier)
        .enqueueReminder(
          payload: payload,
          data: ReminderCardData(title: title, timeLabel: timeLabel),
        );
  }

  String _formatReminderTimeLabel(Task? task, DateTime occurrenceDate) {
    final DateTime date = normalizeDate(occurrenceDate);
    final String dateStr = '${date.month}月${date.day}日';
    if (task == null || task.isAllDay || task.startTimeMinutes == null) {
      return '$dateStr 全天';
    }
    final int mins = task.startTimeMinutes!;
    final int hh = mins ~/ 60;
    final int mm = mins % 60;
    return '$dateStr ${hh.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
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
