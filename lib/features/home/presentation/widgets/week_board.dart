import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme.dart';
import '../../../../core/models/task_preview.dart';
import '../../../../core/utils/calendar_utils.dart';
import '../../../task/application/task_providers.dart';
import '../../application/home_view_mode.dart';
import 'date_timeline_strip.dart';

class WeekBoard extends ConsumerWidget {
  const WeekBoard({
    required this.compact,
    required this.selectedDate,
    super.key,
  });

  final bool compact;
  final DateTime selectedDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<DateTime> dates = weekDates(selectedDate);
    final AsyncValue<List<DailyTaskPreviewBucket>> bucketsAsync = ref.watch(
      taskPreviewBucketsProvider(
        TaskDateWindow(startDate: dates.first, dayCount: dates.length),
      ),
    );

    return bucketsAsync.when(
      data: (List<DailyTaskPreviewBucket> buckets) {
        final Map<DateTime, int> taskCounts = <DateTime, int>{
          for (final DailyTaskPreviewBucket bucket in buckets)
            normalizeDate(bucket.date): bucket.tasks.length,
        };

        final Widget content = compact
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: 1180,
                  child: _WeekColumns(
                    buckets: buckets,
                    selectedDate: selectedDate,
                    onTaskTap: (TaskPreview task) {
                      context.push('/task/${task.id}');
                    },
                    onSelectDate: (DateTime date) {
                      ref.read(selectedDateProvider.notifier).state = date;
                    },
                  ),
                ),
              )
            : _WeekColumns(
                buckets: buckets,
                selectedDate: selectedDate,
                onTaskTap: (TaskPreview task) {
                  context.push('/task/${task.id}');
                },
                onSelectDate: (DateTime date) {
                  ref.read(selectedDateProvider.notifier).state = date;
                },
              );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            DateTimelineStrip(
              dates: dates,
              selectedDate: selectedDate,
              taskCounts: taskCounts,
              onSelectDate: (DateTime date) {
                ref.read(selectedDateProvider.notifier).state = normalizeDate(
                  date,
                );
              },
            ),
            const SizedBox(height: 18),
            Expanded(child: content),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, StackTrace stackTrace) => Center(
        child: Text(
          '周视图加载失败，请稍后重试',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}

class _WeekColumns extends StatelessWidget {
  const _WeekColumns({
    required this.buckets,
    required this.selectedDate,
    required this.onSelectDate,
    required this.onTaskTap,
  });

  final List<DailyTaskPreviewBucket> buckets;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onSelectDate;
  final ValueChanged<TaskPreview> onTaskTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: buckets.map((DailyTaskPreviewBucket bucket) {
          final bool selected = isSameDate(bucket.date, selectedDate);
          return Expanded(
            child: Material(
              color: selected ? const Color(0xFFF7F9FF) : Colors.white,
              child: InkWell(
                onTap: () => onSelectDate(normalizeDate(bucket.date)),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(
                        color: bucket == buckets.last
                            ? Colors.transparent
                            : ScheduleBoardPalette.boardBorder,
                      ),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(10, 18, 10, 18),
                  child: ListView.separated(
                    itemCount: bucket.tasks.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 12),
                    itemBuilder: (BuildContext context, int index) {
                      final TaskPreview task = bucket.tasks[index];
                      return _WeekTaskCard(
                        task: task,
                        onTap: () => onTaskTap(task),
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _WeekTaskCard extends StatelessWidget {
  const _WeekTaskCard({required this.task, required this.onTap});

  final TaskPreview task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: task.state == TaskVisualState.completed
                ? const Color(0xFFF3F4F6)
                : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: task.state == TaskVisualState.overdue
                  ? const Color(0xFFF5C7B1)
                  : ScheduleBoardPalette.boardBorder,
            ),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x100E1F36),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        task.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.workspace_premium_rounded,
                      size: 28,
                      color: task.state == TaskVisualState.completed
                          ? ScheduleBoardPalette.warmAccent
                          : const Color(0xFFBFBFBF),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    const Icon(Icons.access_time_rounded, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          Text(
                            task.timeLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: task.state == TaskVisualState.overdue
                                      ? const Color(0xFFB44C22)
                                      : ScheduleBoardPalette.mutedText,
                                ),
                          ),
                          if (task.delayDays > 0)
                            Text(
                              '顺延${task.delayDays}天',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: const Color(0xFFE14D3A),
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                        ],
                      ),
                    ),
                    if (task.hasVoiceNote)
                      const Icon(
                        Icons.play_circle_fill_rounded,
                        size: 20,
                        color: ScheduleBoardPalette.tealAccent,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
