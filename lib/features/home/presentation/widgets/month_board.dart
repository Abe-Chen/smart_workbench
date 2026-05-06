import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme.dart';
import '../../../../core/models/task_preview.dart';
import '../../../../core/utils/calendar_utils.dart';
import '../../../../core/utils/lunar_utils.dart';
import '../../../settings/application/app_settings_controller.dart';
import '../../../task/application/task_providers.dart';
import '../../application/home_view_mode.dart';

class MonthBoard extends ConsumerWidget {
  const MonthBoard({
    required this.compact,
    required this.selectedDate,
    super.key,
  });

  final bool compact;
  final DateTime selectedDate;

  static const List<String> _weekLabels = <String>[
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DateTime currentMonth = DateTime(
      selectedDate.year,
      selectedDate.month,
    );
    final List<DateTime> gridDates = monthGridDates(selectedDate);
    final AsyncValue<List<DailyTaskPreviewBucket>> bucketsAsync = ref.watch(
      taskPreviewBucketsProvider(
        TaskDateWindow(startDate: gridDates.first, dayCount: gridDates.length),
      ),
    );
    final bool showLunar =
        ref.watch(appSettingsControllerProvider).valueOrNull?.showLunar ?? true;

    return bucketsAsync.when(
      data: (List<DailyTaskPreviewBucket> buckets) {
        final Map<DateTime, List<TaskPreview>> bucketMap =
            <DateTime, List<TaskPreview>>{
              for (final DailyTaskPreviewBucket bucket in buckets)
                normalizeDate(bucket.date): bucket.tasks,
            };

        return Card(
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              const int rowCount = 6;
              const int colCount = 7;
              final double totalHeight = constraints.maxHeight;
              // 屏幕高度紧凑时（如 PZ200 1097×685 logical）压缩 weekLabel
              final bool tight = totalHeight < 600;
              final double weekLabelHeight = tight ? 36 : 64;
              final double gridHeight = totalHeight - weekLabelHeight;
              final double rowHeight = gridHeight / rowCount;
              // chip 高度约 38，加间距 10，至少需要 ~110 才能容纳 1 条 chip
              final int maxChips = rowHeight >= 150
                  ? 2
                  : rowHeight >= 110
                  ? 1
                  : 0;

              return Column(
                children: <Widget>[
                  Container(
                    height: weekLabelHeight,
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: ScheduleBoardPalette.boardBorder,
                        ),
                      ),
                    ),
                    child: Row(
                      children: _weekLabels
                          .map(
                            (String label) => Expanded(
                              child: Center(
                                child: Text(
                                  label,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        fontSize: tight ? 14 : null,
                                      ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  SizedBox(
                    height: gridHeight,
                    child: GridView.builder(
                      padding: EdgeInsets.zero,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: colCount,
                        mainAxisExtent: rowHeight,
                      ),
                      itemCount: gridDates.length,
                      itemBuilder: (BuildContext context, int index) {
                        final DateTime date = gridDates[index];
                        final List<TaskPreview> tasks = _sortForMonth(
                          bucketMap[normalizeDate(date)] ??
                              const <TaskPreview>[],
                        );
                        final bool selected = isSameDate(date, selectedDate);
                        final bool inCurrentMonth =
                            date.month == currentMonth.month;
                        return _MonthCell(
                          date: date,
                          selected: selected,
                          inCurrentMonth: inCurrentMonth,
                          tasks: tasks,
                          showLunar: showLunar,
                          tight: tight,
                          maxChips: maxChips,
                          onTaskTap: (TaskPreview task) {
                            context.push('/task/${task.id}');
                          },
                          onTap: () {
                            ref.read(selectedDateProvider.notifier).state =
                                normalizeDate(date);
                          },
                          onShowAll: () {
                            _showDayTasksSheet(context, ref, date, tasks);
                          },
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, StackTrace stackTrace) => Center(
        child: Text(
          '月视图加载失败，请稍后重试',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}

class _MonthCell extends StatelessWidget {
  const _MonthCell({
    required this.date,
    required this.selected,
    required this.inCurrentMonth,
    required this.tasks,
    required this.showLunar,
    required this.tight,
    required this.maxChips,
    required this.onTap,
    required this.onTaskTap,
    required this.onShowAll,
  });

  final DateTime date;
  final bool selected;
  final bool inCurrentMonth;
  final List<TaskPreview> tasks;
  final bool showLunar;
  final bool tight;
  final int maxChips;
  final VoidCallback onTap;
  final ValueChanged<TaskPreview> onTaskTap;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    final List<TaskPreview> visibleTasks = tasks.take(maxChips).toList();
    final int hiddenCount = tasks.length - visibleTasks.length;
    final LunarLabel? lunar = showLunar ? lunarLabelFor(date) : null;

    final EdgeInsets cellPadding = tight
        ? const EdgeInsets.fromLTRB(8, 6, 8, 6)
        : const EdgeInsets.fromLTRB(12, 10, 12, 10);
    final TextStyle? dayStyle =
        (tight
                ? Theme.of(context).textTheme.titleLarge
                : Theme.of(context).textTheme.headlineMedium)
            ?.copyWith(
              fontWeight: FontWeight.w800,
              color: !inCurrentMonth
                  ? const Color(0xFFC2C8D2)
                  : selected
                  ? ScheduleBoardPalette.blueAccent
                  : null,
            );

    return Material(
      color: selected ? const Color(0xFFF3F6FF) : Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: cellPadding,
          decoration: const BoxDecoration(
            border: Border(
              right: BorderSide(color: ScheduleBoardPalette.boardBorder),
              bottom: BorderSide(color: ScheduleBoardPalette.boardBorder),
            ),
          ),
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              maxHeight: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: <Widget>[
                      Text(
                        '${date.day}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: dayStyle,
                      ),
                      if (lunar != null) ...<Widget>[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            lunar.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: !inCurrentMonth
                                      ? const Color(0xFFC2C8D2)
                                      : lunar.isFestival
                                      ? const Color(0xFFB44C22)
                                      : ScheduleBoardPalette.mutedText,
                                  fontWeight: lunar.isFestival
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (visibleTasks.isNotEmpty) SizedBox(height: tight ? 4 : 8),
                  ...visibleTasks.map(
                    (TaskPreview task) => _MonthTaskChip(
                      task: task,
                      onTap: () => onTaskTap(task),
                      tight: tight,
                    ),
                  ),
                  if (hiddenCount > 0) ...<Widget>[
                    SizedBox(height: visibleTasks.isEmpty ? 4 : 4),
                    _MoreChip(
                      count: hiddenCount,
                      onTap: onShowAll,
                      tight: tight,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MoreChip extends StatelessWidget {
  const _MoreChip({
    required this.count,
    required this.onTap,
    required this.tight,
  });

  final int count;
  final VoidCallback onTap;
  final bool tight;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: tight
              ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2)
              : const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF33445C),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            tight ? '+$count' : '还有$count项',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                (tight
                        ? Theme.of(context).textTheme.bodySmall
                        : Theme.of(context).textTheme.bodyMedium)
                    ?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
          ),
        ),
      ),
    );
  }
}

List<TaskPreview> _sortForMonth(List<TaskPreview> source) {
  // PRD 22.3 月视图排序：
  // 1. 未完成有时间任务（按开始时间升序）
  // 2. 未完成全天任务
  // 3. 已完成任务
  int rank(TaskPreview task) {
    if (task.state == TaskVisualState.completed) {
      return 2;
    }
    if (task.isAllDay) {
      return 1;
    }
    return 0;
  }

  final List<TaskPreview> sorted = List<TaskPreview>.of(source);
  sorted.sort((TaskPreview a, TaskPreview b) {
    final int rankCompare = rank(a).compareTo(rank(b));
    if (rankCompare != 0) {
      return rankCompare;
    }
    return a.timeLabel.compareTo(b.timeLabel);
  });
  return sorted;
}

void _showDayTasksSheet(
  BuildContext context,
  WidgetRef ref,
  DateTime date,
  List<TaskPreview> tasks,
) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (BuildContext sheetContext) {
      return SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '${date.month}月${date.day}日 全部待办',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: ScheduleBoardPalette.blueAccent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${tasks.length}',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '点击任意待办进入详情',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: ScheduleBoardPalette.mutedText,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: tasks.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (BuildContext context, int index) {
                      final TaskPreview task = tasks[index];
                      return _MonthTaskChip(
                        task: task,
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          context.push('/task/${task.id}');
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _MonthTaskChip extends StatelessWidget {
  const _MonthTaskChip({
    required this.task,
    required this.onTap,
    this.tight = false,
  });

  final TaskPreview task;
  final VoidCallback onTap;
  final bool tight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: tight ? 4 : 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(tight ? 10 : 18),
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: tight
                ? const EdgeInsets.fromLTRB(8, 4, 8, 4)
                : const EdgeInsets.fromLTRB(12, 10, 10, 10),
            decoration: BoxDecoration(
              color: task.state == TaskVisualState.completed
                  ? const Color(0xFFF3F4F6)
                  : Colors.white,
              borderRadius: BorderRadius.circular(tight ? 10 : 18),
              border: Border.all(color: ScheduleBoardPalette.boardBorder),
              boxShadow: tight
                  ? const <BoxShadow>[]
                  : const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x100E1F36),
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        (tight
                                ? Theme.of(context).textTheme.bodyMedium
                                : Theme.of(context).textTheme.titleMedium)
                            ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (!tight) ...<Widget>[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.workspace_premium_rounded,
                    size: 26,
                    color: task.state == TaskVisualState.completed
                        ? ScheduleBoardPalette.warmAccent
                        : const Color(0xFFBFBFBF),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
