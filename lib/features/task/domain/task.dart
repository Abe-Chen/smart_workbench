import '../../../core/utils/task_formatters.dart';

enum TaskStatus { pending, completed, deleted }

enum TaskReminderKey {
  none,
  day9am,
  dayNoon,
  day6pm,
  dayBefore9am,
  atStart,
  before5m,
  before10m,
  before30m,
  before1h,
  custom,
}

enum TaskRepeatKey { none, daily, weekly, monthly }

class Task {
  const Task({
    this.id,
    required this.title,
    required this.startDate,
    required this.isAllDay,
    this.startTimeMinutes,
    this.endTimeMinutes,
    this.reminderKey = TaskReminderKey.none,
    this.customReminderAt,
    this.repeatKey = TaskRepeatKey.none,
    this.status = TaskStatus.pending,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
    this.deletedAt,
  });

  factory Task.fromMap(Map<String, Object?> map) {
    return Task(
      id: map['id'] as int?,
      title: map['title'] as String? ?? '',
      startDate: parseStorageDate(map['start_date'] as String? ?? ''),
      isAllDay: (map['is_all_day'] as int? ?? 1) == 1,
      startTimeMinutes: map['start_time_minutes'] as int?,
      endTimeMinutes: map['end_time_minutes'] as int?,
      reminderKey: TaskReminderKey.values.byName(
        map['reminder_key'] as String? ?? TaskReminderKey.none.name,
      ),
      customReminderAt: parseStorageDateTime(
        map['custom_reminder_at'] as String?,
      ),
      repeatKey: TaskRepeatKey.values.byName(
        map['repeat_key'] as String? ?? TaskRepeatKey.none.name,
      ),
      status: TaskStatus.values.byName(
        map['status'] as String? ?? TaskStatus.pending.name,
      ),
      createdAt:
          parseStorageDateTime(map['created_at'] as String?) ?? DateTime.now(),
      updatedAt:
          parseStorageDateTime(map['updated_at'] as String?) ?? DateTime.now(),
      completedAt: parseStorageDateTime(map['completed_at'] as String?),
      deletedAt: parseStorageDateTime(map['deleted_at'] as String?),
    );
  }

  final int? id;
  final String title;
  final DateTime startDate;
  final bool isAllDay;
  final int? startTimeMinutes;
  final int? endTimeMinutes;
  final TaskReminderKey reminderKey;
  final DateTime? customReminderAt;
  final TaskRepeatKey repeatKey;
  final TaskStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;
  final DateTime? deletedAt;

  Task copyWith({
    int? id,
    String? title,
    DateTime? startDate,
    bool? isAllDay,
    int? startTimeMinutes,
    int? endTimeMinutes,
    TaskReminderKey? reminderKey,
    DateTime? customReminderAt,
    TaskRepeatKey? repeatKey,
    TaskStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? completedAt,
    DateTime? deletedAt,
    bool clearCustomReminderAt = false,
    bool clearCompletedAt = false,
    bool clearDeletedAt = false,
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      startDate: startDate ?? this.startDate,
      isAllDay: isAllDay ?? this.isAllDay,
      startTimeMinutes: isAllDay == true
          ? null
          : startTimeMinutes ?? this.startTimeMinutes,
      endTimeMinutes: isAllDay == true
          ? null
          : endTimeMinutes ?? this.endTimeMinutes,
      reminderKey: reminderKey ?? this.reminderKey,
      customReminderAt: clearCustomReminderAt
          ? null
          : customReminderAt ?? this.customReminderAt,
      repeatKey: repeatKey ?? this.repeatKey,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: clearCompletedAt ? null : completedAt ?? this.completedAt,
      deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'title': title,
      'start_date': formatStorageDate(startDate),
      'is_all_day': isAllDay ? 1 : 0,
      'start_time_minutes': startTimeMinutes,
      'end_time_minutes': endTimeMinutes,
      'reminder_key': reminderKey.name,
      'custom_reminder_at': customReminderAt == null
          ? null
          : formatStorageDateTime(customReminderAt!),
      'repeat_key': repeatKey.name,
      'status': status.name,
      'created_at': formatStorageDateTime(createdAt),
      'updated_at': formatStorageDateTime(updatedAt),
      'completed_at': completedAt == null
          ? null
          : formatStorageDateTime(completedAt!),
      'deleted_at': deletedAt == null
          ? null
          : formatStorageDateTime(deletedAt!),
    };
  }

  bool occursOn(DateTime day) {
    final DateTime target = DateTime(day.year, day.month, day.day);
    final DateTime seed = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
    );

    if (target.isBefore(seed)) {
      return false;
    }

    switch (repeatKey) {
      case TaskRepeatKey.none:
        return _isSameDate(target, seed);
      case TaskRepeatKey.daily:
        return true;
      case TaskRepeatKey.weekly:
        return target.difference(seed).inDays % 7 == 0;
      case TaskRepeatKey.monthly:
        final int monthsBetween =
            (target.year - seed.year) * 12 + target.month - seed.month;
        if (monthsBetween < 0) {
          return false;
        }
        final DateTime expected = _addMonths(seed, monthsBetween);
        return _isSameDate(expected, target);
    }
  }

  DateTime nextOccurrenceAfter(DateTime occurrenceDate) {
    final DateTime current = DateTime(
      occurrenceDate.year,
      occurrenceDate.month,
      occurrenceDate.day,
    );

    switch (repeatKey) {
      case TaskRepeatKey.none:
        return current;
      case TaskRepeatKey.daily:
        return current.add(const Duration(days: 1));
      case TaskRepeatKey.weekly:
        return current.add(const Duration(days: 7));
      case TaskRepeatKey.monthly:
        return _addMonths(current, 1);
    }
  }

  static DateTime _addMonths(DateTime date, int monthDelta) {
    final int rawMonth = date.month + monthDelta;
    final int year = date.year + ((rawMonth - 1) ~/ 12);
    final int month = ((rawMonth - 1) % 12) + 1;
    final int maxDay = _daysInMonth(year, month);
    final int day = date.day > maxDay ? maxDay : date.day;
    return DateTime(year, month, day);
  }

  static int _daysInMonth(int year, int month) {
    if (month == 12) {
      return DateTime(year + 1, 1, 0).day;
    }
    return DateTime(year, month + 1, 0).day;
  }

  static bool _isSameDate(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }
}

class TaskOccurrence {
  const TaskOccurrence({
    required this.task,
    required this.occurrenceDate,
    DateTime? sourceDate,
  }) : sourceDate = sourceDate ?? occurrenceDate;

  final Task task;
  final DateTime occurrenceDate;
  final DateTime sourceDate;
}
