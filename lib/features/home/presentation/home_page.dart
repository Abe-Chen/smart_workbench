import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/task_formatters.dart';
import '../../task/application/task_providers.dart';
import '../application/home_view_mode.dart';
import 'widgets/day_board.dart';
import 'widgets/home_header.dart';
import 'widgets/month_board.dart';
import 'widgets/week_board.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HomeViewMode mode = ref.watch(homeViewModeProvider);
    final DateTime selectedDate = ref.watch(selectedDateProvider);
    final String dateLabel = switch (mode) {
      HomeViewMode.month => formatMonthLabel(selectedDate),
      HomeViewMode.day || HomeViewMode.week => formatHeadlineDate(selectedDate),
    };

    return Scaffold(
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool compact = constraints.maxWidth < 960;
          return Column(
            children: <Widget>[
              SafeArea(
                bottom: false,
                child: HomeHeader(
                  dateLabel: dateLabel,
                  mode: mode,
                  onCreateTask: () => context.push('/task/new'),
                  onJumpToToday: () {
                    final DateTime now = DateTime.now();
                    ref.read(selectedDateProvider.notifier).state = DateTime(
                      now.year,
                      now.month,
                      now.day,
                    );
                  },
                  onModeChanged: (HomeViewMode nextMode) {
                    ref.read(homeViewModeProvider.notifier).state = nextMode;
                  },
                  onPickDate: () async {
                    final DateTime initial = ref.read(selectedDateProvider);
                    final DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: initial,
                      firstDate: DateTime(2024),
                      lastDate: DateTime(2035),
                    );
                    if (picked == null) {
                      return;
                    }
                    ref.read(selectedDateProvider.notifier).state = DateTime(
                      picked.year,
                      picked.month,
                      picked.day,
                    );
                  },
                  onRefresh: () {
                    ref.read(taskRefreshTickProvider.notifier).state++;
                  },
                  onOpenSettings: () => context.push('/settings'),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 8 : 0,
                    compact ? 8 : 10,
                    compact ? 8 : 0,
                    compact ? 10 : 12,
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: switch (mode) {
                      HomeViewMode.day => DayBoard(
                        compact: compact,
                        selectedDate: selectedDate,
                      ),
                      HomeViewMode.week => WeekBoard(
                        compact: compact,
                        selectedDate: selectedDate,
                      ),
                      HomeViewMode.month => MonthBoard(
                        compact: compact,
                        selectedDate: selectedDate,
                      ),
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
