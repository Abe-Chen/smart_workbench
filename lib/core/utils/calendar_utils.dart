DateTime normalizeDate(DateTime date) {
  return DateTime(date.year, date.month, date.day);
}

bool isSameDate(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

DateTime startOfWeek(DateTime date) {
  final DateTime normalized = normalizeDate(date);
  return normalized.subtract(Duration(days: normalized.weekday - 1));
}

List<DateTime> weekDates(DateTime selectedDate) {
  final DateTime first = startOfWeek(selectedDate);
  return List<DateTime>.generate(
    7,
    (int index) => first.add(Duration(days: index)),
  );
}

List<DateTime> monthGridDates(DateTime selectedDate) {
  final DateTime firstOfMonth = DateTime(selectedDate.year, selectedDate.month);
  final DateTime gridStart = startOfWeek(firstOfMonth);
  return List<DateTime>.generate(
    42,
    (int index) => gridStart.add(Duration(days: index)),
  );
}
