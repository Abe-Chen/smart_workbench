import 'package:intl/intl.dart';

String formatStorageDate(DateTime date) {
  final DateTime normalized = DateTime(date.year, date.month, date.day);
  return DateFormat('yyyy-MM-dd').format(normalized);
}

DateTime parseStorageDate(String value) {
  return DateTime.parse(value);
}

String formatStorageDateTime(DateTime dateTime) {
  return dateTime.toIso8601String();
}

DateTime? parseStorageDateTime(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  return DateTime.parse(value);
}

String formatMinutesOfDay(int minutes) {
  final int hour = minutes ~/ 60;
  final int minute = minutes % 60;
  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

String formatTaskTimeLabel({
  required bool isAllDay,
  int? startTimeMinutes,
  int? endTimeMinutes,
}) {
  if (isAllDay) {
    return '全天';
  }

  final String start = formatMinutesOfDay(startTimeMinutes ?? 0);
  final String end = formatMinutesOfDay(
    endTimeMinutes ?? startTimeMinutes ?? 0,
  );
  return '$start-$end';
}

String formatHeadlineDate(DateTime date) {
  return DateFormat('yyyy年M月d日').format(date);
}

String formatMonthLabel(DateTime date) {
  return DateFormat('yyyy年M月').format(date);
}

String formatMonthDayLabel(DateTime date) {
  return DateFormat('M月d日').format(date);
}

String formatVoiceDuration(int millis) {
  final int totalSeconds = (millis / 1000).round();
  final int minutes = totalSeconds ~/ 60;
  final int seconds = totalSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

String formatWeekdayLabel(DateTime date) {
  const List<String> labels = <String>[
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ];
  return labels[date.weekday - 1];
}
