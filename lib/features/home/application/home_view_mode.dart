import 'package:flutter_riverpod/flutter_riverpod.dart';

enum HomeViewMode {
  day('日'),
  week('周'),
  month('月');

  const HomeViewMode(this.label);

  final String label;
}

final StateProvider<HomeViewMode> homeViewModeProvider =
    StateProvider<HomeViewMode>((_) => HomeViewMode.day);

final StateProvider<DateTime> selectedDateProvider = StateProvider<DateTime>((
  _,
) {
  final DateTime now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});
