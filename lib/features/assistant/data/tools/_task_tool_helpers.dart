import '../../../../core/utils/task_formatters.dart';
import '../../../task/domain/task.dart';

/// 解析 AI 给的日期字符串。允许 YYYY-MM-DD / YYYY/MM/DD。失败返 null。
DateTime? parseTaskDate(Object? raw) {
  if (raw == null) return null;
  final String text = raw.toString().trim();
  if (text.isEmpty) return null;
  final String normalized = text.replaceAll('/', '-');
  try {
    return DateTime.parse(normalized);
  } catch (_) {
    return null;
  }
}

/// 解析时间到当日分钟数（0-1440）。允许 int / "HH:MM" / 整数字符串。失败返 null。
int? parseTaskTimeMinutes(Object? raw) {
  if (raw == null) return null;
  if (raw is int) return raw.clamp(0, 1440);
  if (raw is num) return raw.toInt().clamp(0, 1440);
  final String text = raw.toString().trim();
  if (text.isEmpty) return null;
  final RegExpMatch? hm = RegExp(r'^(\d{1,2})[:：](\d{1,2})$').firstMatch(text);
  if (hm != null) {
    final int h = int.parse(hm.group(1)!);
    final int min = int.parse(hm.group(2)!);
    return (h * 60 + min).clamp(0, 1440);
  }
  final int? n = int.tryParse(text);
  if (n != null) return n.clamp(0, 1440);
  return null;
}

bool? parseBool(Object? raw) {
  if (raw == null) return null;
  if (raw is bool) return raw;
  final String text = raw.toString().toLowerCase().trim();
  if (text == 'true' || text == '1' || text == 'yes') return true;
  if (text == 'false' || text == '0' || text == 'no') return false;
  return null;
}

TaskReminderKey parseReminderKey(
  Object? raw, {
  TaskReminderKey defaultValue = TaskReminderKey.none,
}) {
  if (raw == null) return defaultValue;
  final String text = raw.toString().trim();
  for (final TaskReminderKey k in TaskReminderKey.values) {
    if (k.name == text) return k;
  }
  return defaultValue;
}

TaskRepeatKey parseRepeatKey(
  Object? raw, {
  TaskRepeatKey defaultValue = TaskRepeatKey.none,
}) {
  if (raw == null) return defaultValue;
  final String text = raw.toString().trim();
  for (final TaskRepeatKey k in TaskRepeatKey.values) {
    if (k.name == text) return k;
  }
  return defaultValue;
}

String reminderLabel(TaskReminderKey key) {
  switch (key) {
    case TaskReminderKey.none:
      return '不提醒';
    case TaskReminderKey.day9am:
      return '当天 09:00 提醒';
    case TaskReminderKey.dayNoon:
      return '当天 12:00 提醒';
    case TaskReminderKey.day6pm:
      return '当天 18:00 提醒';
    case TaskReminderKey.dayBefore9am:
      return '前一天 09:00 提醒';
    case TaskReminderKey.atStart:
      return '开始时提醒';
    case TaskReminderKey.before5m:
      return '提前 5 分钟';
    case TaskReminderKey.before10m:
      return '提前 10 分钟';
    case TaskReminderKey.before30m:
      return '提前 30 分钟';
    case TaskReminderKey.before1h:
      return '提前 1 小时';
    case TaskReminderKey.custom:
      return '自定义提醒';
  }
}

String repeatLabel(TaskRepeatKey key) {
  switch (key) {
    case TaskRepeatKey.none:
      return '不重复';
    case TaskRepeatKey.daily:
      return '每天';
    case TaskRepeatKey.weekly:
      return '每周';
    case TaskRepeatKey.monthly:
      return '每月';
  }
}

String taskTimeLabel(Task task) {
  return formatTaskTimeLabel(
    isAllDay: task.isAllDay,
    startTimeMinutes: task.startTimeMinutes,
    endTimeMinutes: task.endTimeMinutes,
  );
}

/// 给确认卡用的"日期 + 时间"组合文案，例：
/// "明天 (5月9日) 15:00-16:00" 或 "5月9日 全天"
String taskWhenLabel({
  required DateTime date,
  required bool isAllDay,
  int? startTimeMinutes,
  int? endTimeMinutes,
}) {
  final DateTime today = DateTime.now();
  final DateTime targetDay = DateTime(date.year, date.month, date.day);
  final DateTime todayDay = DateTime(today.year, today.month, today.day);
  final int diff = targetDay.difference(todayDay).inDays;
  final String dayPart;
  if (diff == 0) {
    dayPart = '今天';
  } else if (diff == 1) {
    dayPart = '明天';
  } else if (diff == 2) {
    dayPart = '后天';
  } else if (diff == -1) {
    dayPart = '昨天';
  } else {
    dayPart = formatMonthDayLabel(date);
  }
  final String timePart = formatTaskTimeLabel(
    isAllDay: isAllDay,
    startTimeMinutes: startTimeMinutes,
    endTimeMinutes: endTimeMinutes,
  );
  if (isAllDay) {
    return '$dayPart · 全天';
  }
  return '$dayPart · $timePart';
}
