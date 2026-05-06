import 'dart:async';
import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../utils/calendar_utils.dart';
import '../../features/task/domain/task.dart';

enum ReminderIntentAction { openAlert, completeTask }

class ReminderPayload {
  const ReminderPayload({required this.taskId, required this.occurrenceDate});

  final int taskId;
  final DateTime occurrenceDate;

  String toPayloadString() {
    return jsonEncode(<String, String>{
      'taskId': '$taskId',
      'occurrenceDate': normalizeDate(occurrenceDate).toIso8601String(),
    });
  }

  static ReminderPayload? tryParse(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }

    try {
      final Map<String, dynamic> map =
          jsonDecode(value) as Map<String, dynamic>;
      final int? taskId = int.tryParse(map['taskId']?.toString() ?? '');
      final DateTime? occurrenceDate = DateTime.tryParse(
        map['occurrenceDate']?.toString() ?? '',
      );
      if (taskId == null || occurrenceDate == null) {
        return null;
      }
      return ReminderPayload(
        taskId: taskId,
        occurrenceDate: normalizeDate(occurrenceDate),
      );
    } catch (_) {
      return null;
    }
  }
}

class ReminderIntent {
  const ReminderIntent({required this.action, required this.payload});

  const ReminderIntent.openAlert(this.payload)
    : action = ReminderIntentAction.openAlert;

  const ReminderIntent.completeTask(this.payload)
    : action = ReminderIntentAction.completeTask;

  final ReminderIntentAction action;
  final ReminderPayload payload;
}

class ReminderOccurrence {
  const ReminderOccurrence({required this.payload, required this.reminderAt});

  final ReminderPayload payload;
  final DateTime reminderAt;

  String get sessionKey =>
      '${payload.taskId}|${payload.occurrenceDate.toIso8601String()}|${reminderAt.toIso8601String()}';
}

class LocalNotificationService {
  LocalNotificationService();

  static const String completeActionId = 'complete_task';
  static const String viewActionId = 'view_task';

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'task_reminders',
    'Task Reminders',
    description: 'Schedule Board reminders for tasks',
    importance: Importance.max,
  );

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final StreamController<ReminderIntent> _reminderIntentController =
      StreamController<ReminderIntent>.broadcast();
  final List<ReminderIntent> _pendingReminderIntents = <ReminderIntent>[];

  bool _initialized = false;
  bool _permissionsRequested = false;

  Stream<ReminderIntent> get reminderIntents =>
      _reminderIntentController.stream;

  List<ReminderIntent> consumePendingReminderIntents() {
    final List<ReminderIntent> intents = List<ReminderIntent>.from(
      _pendingReminderIntents,
    );
    _pendingReminderIntents.clear();
    return intents;
  }

  Future<void> initialize({bool requestPermissions = false}) async {
    if (_initialized) {
      if (requestPermissions) {
        await _ensureAndroidPermissions();
      }
      return;
    }

    tz.initializeTimeZones();
    final TimezoneInfo timezone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timezone.identifier));

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings darwinSettings =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    await _plugin.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
      ),
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );

    final AndroidFlutterLocalNotificationsPlugin? androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(_channel);

    final NotificationAppLaunchDetails? launchDetails = await _plugin
        .getNotificationAppLaunchDetails();
    final NotificationResponse? launchResponse =
        launchDetails?.notificationResponse;
    if (launchDetails?.didNotificationLaunchApp == true &&
        launchResponse != null) {
      final ReminderIntent? launchIntent = _intentFromNotificationResponse(
        launchResponse,
      );
      if (launchIntent != null) {
        _dispatchReminderIntent(launchIntent);
      }
    }

    _initialized = true;
    if (requestPermissions) {
      await _ensureAndroidPermissions();
    }
  }

  Future<void> cancelAllNotifications() async {
    await initialize();
    await _plugin.cancelAll();
  }

  void emitInAppReminder(ReminderPayload payload) {
    _dispatchReminderIntent(ReminderIntent.openAlert(payload));
  }

  Future<void> syncTaskReminders({
    required List<Task> tasks,
    required bool remindersEnabled,
  }) async {
    await initialize(requestPermissions: true);

    await _plugin.cancelAllPendingNotifications();
    if (!remindersEnabled) {
      return;
    }

    final DateTime now = DateTime.now();
    for (final Task task in tasks) {
      if (task.id == null || task.reminderKey == TaskReminderKey.none) {
        continue;
      }

      for (final _TaskSchedule schedule in _buildSchedules(task, now)) {
        await _plugin.zonedSchedule(
          schedule.id,
          task.title,
          _buildBody(task),
          tz.TZDateTime.from(schedule.when, tz.local),
          _notificationDetails,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          payload: schedule.payload.toPayloadString(),
        );
      }
    }
  }

  List<ReminderOccurrence> dueRemindersForWindow({
    required List<Task> tasks,
    required DateTime from,
    required DateTime to,
  }) {
    final List<ReminderOccurrence> dueReminders = <ReminderOccurrence>[];

    for (final Task task in tasks) {
      if (task.id == null || task.reminderKey == TaskReminderKey.none) {
        continue;
      }

      DateTime cursor = normalizeDate(
        from.subtract(
          Duration(
            days: switch (task.repeatKey) {
              TaskRepeatKey.monthly => 35,
              TaskRepeatKey.weekly => 8,
              TaskRepeatKey.daily => 2,
              TaskRepeatKey.none => 1,
            },
          ),
        ),
      );
      final DateTime seed = normalizeDate(task.startDate);
      if (cursor.isBefore(seed)) {
        cursor = seed;
      }

      final DateTime end = normalizeDate(
        to.add(
          Duration(
            days:
                task.isAllDay &&
                    task.reminderKey == TaskReminderKey.dayBefore9am
                ? 1
                : 0,
          ),
        ),
      );

      while (!cursor.isAfter(end)) {
        if (task.occursOn(cursor)) {
          final DateTime? reminderAt = _reminderDateTimeForOccurrence(
            task,
            cursor,
          );
          if (reminderAt != null &&
              !reminderAt.isBefore(from) &&
              !reminderAt.isAfter(to)) {
            dueReminders.add(
              ReminderOccurrence(
                payload: ReminderPayload(
                  taskId: task.id!,
                  occurrenceDate: normalizeDate(cursor),
                ),
                reminderAt: reminderAt,
              ),
            );
          }
        }
        cursor = cursor.add(const Duration(days: 1));
      }
    }

    dueReminders.sort(
      (ReminderOccurrence left, ReminderOccurrence right) =>
          left.reminderAt.compareTo(right.reminderAt),
    );
    return dueReminders;
  }

  NotificationDetails get _notificationDetails {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        'task_reminders',
        'Task Reminders',
        channelDescription: 'Schedule Board reminders for tasks',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.reminder,
        visibility: NotificationVisibility.public,
        fullScreenIntent: true,
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction(
            completeActionId,
            '完成',
            showsUserInterface: true,
          ),
          AndroidNotificationAction(
            viewActionId,
            '查看',
            showsUserInterface: true,
          ),
        ],
      ),
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
    );
  }

  String _buildBody(Task task) {
    if (task.isAllDay) {
      return '今天有一项全天待办需要处理';
    }
    return '该处理 ${task.title} 了';
  }

  List<_TaskSchedule> _buildSchedules(Task task, DateTime now) {
    return switch (task.repeatKey) {
      TaskRepeatKey.none => _buildOneShotSchedules(task, now),
      TaskRepeatKey.daily => _buildDailySchedule(task, now),
      TaskRepeatKey.weekly => _buildWeeklySchedule(task, now),
      TaskRepeatKey.monthly => _buildMonthlySchedules(task, now),
    };
  }

  List<_TaskSchedule> _buildOneShotSchedules(Task task, DateTime now) {
    final DateTime? reminderAt = _reminderDateTimeForOccurrence(
      task,
      task.startDate,
    );
    if (reminderAt == null || !reminderAt.isAfter(now)) {
      return const <_TaskSchedule>[];
    }
    return <_TaskSchedule>[
      _TaskSchedule(
        id: _notificationBaseId(task.id!),
        when: reminderAt,
        payload: ReminderPayload(
          taskId: task.id!,
          occurrenceDate: normalizeDate(task.startDate),
        ),
      ),
    ];
  }

  List<_TaskSchedule> _buildDailySchedule(Task task, DateTime now) {
    return _buildConcreteRecurringSchedules(
      task,
      now,
      maxSchedules: 14,
      searchWindowDays: 20,
    );
  }

  List<_TaskSchedule> _buildWeeklySchedule(Task task, DateTime now) {
    return _buildConcreteRecurringSchedules(
      task,
      now,
      maxSchedules: 12,
      searchWindowDays: 112,
    );
  }

  List<_TaskSchedule> _buildMonthlySchedules(Task task, DateTime now) {
    final List<_TaskSchedule> schedules = <_TaskSchedule>[];
    DateTime occurrenceDate = normalizeDate(task.startDate);
    int offset = 0;

    while (offset < 12 && schedules.length < 6) {
      final DateTime? reminderAt = _reminderDateTimeForOccurrence(
        task,
        occurrenceDate,
      );
      if (reminderAt != null && reminderAt.isAfter(now)) {
        schedules.add(
          _TaskSchedule(
            id: _notificationBaseId(task.id!) + offset,
            when: reminderAt,
            payload: ReminderPayload(
              taskId: task.id!,
              occurrenceDate: normalizeDate(occurrenceDate),
            ),
          ),
        );
      }
      occurrenceDate = task.nextOccurrenceAfter(occurrenceDate);
      offset++;
    }

    return schedules;
  }

  List<_TaskSchedule> _buildConcreteRecurringSchedules(
    Task task,
    DateTime now, {
    required int maxSchedules,
    required int searchWindowDays,
  }) {
    final List<_TaskSchedule> schedules = <_TaskSchedule>[];
    DateTime occurrenceDate = normalizeDate(
      now.subtract(const Duration(days: 1)),
    );
    final DateTime seed = normalizeDate(task.startDate);
    if (occurrenceDate.isBefore(seed)) {
      occurrenceDate = seed;
    }

    final DateTime end = normalizeDate(
      occurrenceDate.add(Duration(days: searchWindowDays)),
    );

    while (!occurrenceDate.isAfter(end) && schedules.length < maxSchedules) {
      if (task.occursOn(occurrenceDate)) {
        final DateTime? reminderAt = _reminderDateTimeForOccurrence(
          task,
          occurrenceDate,
        );
        if (reminderAt != null && reminderAt.isAfter(now)) {
          schedules.add(
            _TaskSchedule(
              id: _notificationBaseId(task.id!) + schedules.length,
              when: reminderAt,
              payload: ReminderPayload(
                taskId: task.id!,
                occurrenceDate: normalizeDate(occurrenceDate),
              ),
            ),
          );
        }
      }
      occurrenceDate = occurrenceDate.add(const Duration(days: 1));
    }

    return schedules;
  }

  DateTime? _reminderDateTimeForOccurrence(Task task, DateTime occurrenceDate) {
    final DateTime date = DateTime(
      occurrenceDate.year,
      occurrenceDate.month,
      occurrenceDate.day,
    );

    if (task.isAllDay) {
      return switch (task.reminderKey) {
        TaskReminderKey.none => null,
        TaskReminderKey.day9am => DateTime(date.year, date.month, date.day, 9),
        TaskReminderKey.dayNoon => DateTime(
          date.year,
          date.month,
          date.day,
          12,
        ),
        TaskReminderKey.day6pm => DateTime(date.year, date.month, date.day, 18),
        TaskReminderKey.dayBefore9am => DateTime(
          date.year,
          date.month,
          date.day - 1,
          9,
        ),
        TaskReminderKey.custom => task.customReminderAt,
        _ => null,
      };
    }

    final int startMinutes = task.startTimeMinutes ?? 0;
    final DateTime startAt = DateTime(
      date.year,
      date.month,
      date.day,
      startMinutes ~/ 60,
      startMinutes % 60,
    );

    return switch (task.reminderKey) {
      TaskReminderKey.none => null,
      TaskReminderKey.atStart => startAt,
      TaskReminderKey.before5m => startAt.subtract(const Duration(minutes: 5)),
      TaskReminderKey.before10m => startAt.subtract(
        const Duration(minutes: 10),
      ),
      TaskReminderKey.before30m => startAt.subtract(
        const Duration(minutes: 30),
      ),
      TaskReminderKey.before1h => startAt.subtract(const Duration(hours: 1)),
      TaskReminderKey.custom => task.customReminderAt,
      _ => null,
    };
  }

  void _handleNotificationResponse(NotificationResponse response) {
    final ReminderIntent? intent = _intentFromNotificationResponse(response);
    if (intent == null) {
      return;
    }
    _dispatchReminderIntent(intent);
  }

  ReminderIntent? _intentFromNotificationResponse(
    NotificationResponse response,
  ) {
    final ReminderPayload? payload = ReminderPayload.tryParse(response.payload);
    if (payload == null) {
      return null;
    }

    return switch (response.actionId) {
      completeActionId => ReminderIntent.completeTask(payload),
      viewActionId => ReminderIntent.openAlert(payload),
      _ => ReminderIntent.openAlert(payload),
    };
  }

  void _dispatchReminderIntent(ReminderIntent intent) {
    if (_reminderIntentController.hasListener) {
      _reminderIntentController.add(intent);
      return;
    }
    _pendingReminderIntents.add(intent);
  }

  int _notificationBaseId(int taskId) => taskId * 100;

  Future<void> _ensureAndroidPermissions() async {
    if (_permissionsRequested) {
      return;
    }

    final AndroidFlutterLocalNotificationsPlugin? androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.requestExactAlarmsPermission();
    await androidPlugin?.requestFullScreenIntentPermission();
    _permissionsRequested = true;
  }
}

class _TaskSchedule {
  const _TaskSchedule({
    required this.id,
    required this.when,
    required this.payload,
  });

  final int id;
  final DateTime when;
  final ReminderPayload payload;
}
