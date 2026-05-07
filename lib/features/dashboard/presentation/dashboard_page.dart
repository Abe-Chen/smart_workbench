import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/models/task_preview.dart';
import '../../../core/time/now_provider.dart';
import '../../../core/utils/calendar_utils.dart';
import '../../../core/utils/task_formatters.dart';
import '../../task/application/task_providers.dart';
import '../../workbench/application/workbench_tab_provider.dart';
import 'dashboard_metrics.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DateTime now =
        ref.watch(nowProvider).valueOrNull ?? DateTime.now();
    final DateTime today = normalizeDate(now);
    final DateTime tomorrow = today.add(const Duration(days: 1));
    final AsyncValue<List<TaskPreview>> todayTasksAsync = ref.watch(
      taskPreviewsForDateProvider(today),
    );
    final AsyncValue<List<TaskPreview>> tomorrowTasksAsync = ref.watch(
      taskPreviewsForDateProvider(tomorrow),
    );
    final DashboardMetrics metrics = DashboardMetrics.of(context);

    void goToScheduleTab() {
      ref.read(workbenchTabIndexProvider.notifier).state =
          WorkbenchTab.schedule.index;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F8FF),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[Color(0xFFF7FBFF), Color(0xFFF1F6FF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Stack(
          children: <Widget>[
            const Positioned(
              top: -120,
              left: -40,
              child: _AmbientGlow(size: 280, color: Color(0x224B76FF)),
            ),
            const Positioned(
              top: 80,
              right: -100,
              child: _AmbientGlow(size: 320, color: Color(0x1414D2C8)),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  metrics.outerPadding,
                  metrics.outerVerticalPadding,
                  metrics.outerPadding,
                  metrics.outerVerticalPadding - 2,
                ),
                child: Column(
                  children: <Widget>[
                    _DashboardStatusBar(now: now, metrics: metrics),
                    SizedBox(height: metrics.cardGap),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Expanded(
                            flex: 5,
                            child: _TodayTomorrowBoard(
                              now: now,
                              today: today,
                              tomorrow: tomorrow,
                              todayTasksAsync: todayTasksAsync,
                              tomorrowTasksAsync: tomorrowTasksAsync,
                              metrics: metrics,
                              onSeeAll: goToScheduleTab,
                            ),
                          ),
                          SizedBox(width: metrics.cardGap),
                          Expanded(
                            flex: 3,
                            child: Column(
                              children: <Widget>[
                                Expanded(
                                  flex: metrics.rightColumnGoalsFlex,
                                  child: _GoalsCard(
                                    todayTasksAsync: todayTasksAsync,
                                    metrics: metrics,
                                  ),
                                ),
                                SizedBox(height: metrics.cardGap),
                                Expanded(
                                  flex: metrics.rightColumnNextTaskFlex,
                                  child: _NextTaskCard(
                                    now: now,
                                    todayTasksAsync: todayTasksAsync,
                                    tomorrowTasksAsync: tomorrowTasksAsync,
                                    metrics: metrics,
                                  ),
                                ),
                                SizedBox(height: metrics.cardGap),
                                Expanded(
                                  flex: metrics.rightColumnWeatherFlex,
                                  child: _WeatherPreviewCard(metrics: metrics),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardStatusBar extends StatelessWidget {
  const _DashboardStatusBar({required this.now, required this.metrics});

  final DateTime now;
  final DashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final String timeLabel =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final String dateLabel =
        '${formatMonthDayLabel(now)}   ${formatWeekdayLabel(now)}';

    return Row(
      children: <Widget>[
        Text(
          timeLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: metrics.statusBarTimeFontSize,
            color: const Color(0xFF1C2F50),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            dateLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: metrics.statusBarDateFontSize,
              color: const Color(0xFF1C2F50),
            ),
          ),
        ),
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.wifi_rounded, color: Color(0xFF1C2F50), size: 20),
            SizedBox(width: 10),
            _BatteryGlyph(),
          ],
        ),
      ],
    );
  }
}

class _BatteryGlyph extends StatelessWidget {
  const _BatteryGlyph();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 14,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF1C2F50), width: 1.4),
              ),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: 16,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C2F50),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: -3,
            top: 4,
            child: Container(
              width: 2,
              height: 6,
              decoration: BoxDecoration(
                color: const Color(0xFF1C2F50),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayTomorrowBoard extends StatelessWidget {
  const _TodayTomorrowBoard({
    required this.now,
    required this.today,
    required this.tomorrow,
    required this.todayTasksAsync,
    required this.tomorrowTasksAsync,
    required this.metrics,
    required this.onSeeAll,
  });

  final DateTime now;
  final DateTime today;
  final DateTime tomorrow;
  final AsyncValue<List<TaskPreview>> todayTasksAsync;
  final AsyncValue<List<TaskPreview>> tomorrowTasksAsync;
  final DashboardMetrics metrics;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final double iconSize = metrics.isCompact ? 36 : 40;
    return _DashboardCard(
      metrics: metrics,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: iconSize,
                height: iconSize,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2FF),
                  borderRadius: BorderRadius.circular(metrics.isCompact ? 10 : 12),
                ),
                child: Icon(
                  Icons.calendar_month_rounded,
                  color: ScheduleBoardPalette.blueAccent,
                  size: metrics.isCompact ? 20 : 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '今日 + 明日日程',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    fontSize: metrics.boardTitle,
                    color: const Color(0xFF22324C),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: metrics.cardGap),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(metrics.cardRadius - 4),
                border: Border.all(color: const Color(0xFFE5EEFF)),
                color: Colors.white.withValues(alpha: 0.76),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x10A9C7FF),
                    blurRadius: 28,
                    offset: Offset(0, 14),
                  ),
                ],
              ),
              padding: EdgeInsets.all(metrics.isCompact ? 10 : 12),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: _SchedulePreviewColumn(
                      now: now,
                      title: '今日日程',
                      summaryPrefix: '今日',
                      date: today,
                      tasksAsync: todayTasksAsync,
                      metrics: metrics,
                      onSeeAll: onSeeAll,
                    ),
                  ),
                  Container(
                    width: 1,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    color: const Color(0xFFE4ECFF),
                  ),
                  Expanded(
                    child: _SchedulePreviewColumn(
                      now: now,
                      title: '明日日程',
                      summaryPrefix: '明日',
                      date: tomorrow,
                      tasksAsync: tomorrowTasksAsync,
                      metrics: metrics,
                      onSeeAll: onSeeAll,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SchedulePreviewColumn extends StatelessWidget {
  const _SchedulePreviewColumn({
    required this.now,
    required this.title,
    required this.summaryPrefix,
    required this.date,
    required this.tasksAsync,
    required this.metrics,
    required this.onSeeAll,
  });

  final DateTime now;
  final String title;
  final String summaryPrefix;
  final DateTime date;
  final AsyncValue<List<TaskPreview>> tasksAsync;
  final DashboardMetrics metrics;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _SectionTitle(title: title, metrics: metrics),
        SizedBox(height: metrics.cardGap),
        Expanded(
          child: tasksAsync.when(
            data: (List<TaskPreview> tasks) {
              if (tasks.isEmpty) {
                return _EmptyCard(message: '${formatMonthDayLabel(date)}暂无日程');
              }
              return _TimelineList(
                tasks: tasks,
                now: now,
                metrics: metrics,
              );
            },
            loading: () => _ScheduleLoadingPlaceholder(metrics: metrics),
            error: (_, _) => const _EmptyCard(message: '日程加载失败'),
          ),
        ),
        SizedBox(height: metrics.cardGap - 2),
        _SummaryPill(
          icon: Icons.calendar_today_rounded,
          message: tasksAsync.maybeWhen(
            data: (List<TaskPreview> tasks) =>
                '$summaryPrefix共 ${tasks.length} 项安排',
            orElse: () => '$summaryPrefix安排',
          ),
          metrics: metrics,
          onTap: onSeeAll,
        ),
      ],
    );
  }
}

class _TimelineList extends StatelessWidget {
  const _TimelineList({
    required this.tasks,
    required this.now,
    required this.metrics,
  });

  final List<TaskPreview> tasks;
  final DateTime now;
  final DashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const ClampingScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: tasks.length,
      itemBuilder: (BuildContext context, int index) {
        return _TimelineTaskTile(
          task: tasks[index],
          now: now,
          isLast: index == tasks.length - 1,
          metrics: metrics,
        );
      },
    );
  }
}

class _TimelineTaskTile extends StatelessWidget {
  const _TimelineTaskTile({
    required this.task,
    required this.now,
    required this.isLast,
    required this.metrics,
  });

  final TaskPreview task;
  final DateTime now;
  final bool isLast;
  final DashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final _TaskMoment moment = _resolveTaskMoment(task, now);
    final _TaskBadge? badge = _resolveTaskBadge(task, moment);
    final bool emphasized =
        moment == _TaskMoment.active || moment == _TaskMoment.upcoming;
    final bool dimmed = task.state == TaskVisualState.completed;
    final Color cardColor = emphasized
        ? const Color(0xFFF2F7FF)
        : dimmed
        ? const Color(0xFFF8FAFD)
        : Colors.white;
    final Color borderColor = emphasized
        ? const Color(0xFFCCDBFF)
        : const Color(0xFFE7EEFB);
    final Color dotColor = switch (moment) {
      _TaskMoment.active => ScheduleBoardPalette.blueAccent,
      _TaskMoment.upcoming => const Color(0xFF4D8EFF),
      _TaskMoment.overdue => const Color(0xFFFF8E6A),
      _TaskMoment.completed => const Color(0xFFB7C3D9),
      _TaskMoment.tomorrow => const Color(0xFF19C7BD),
      _TaskMoment.allDay => const Color(0xFF8C7DFF),
      _TaskMoment.later => const Color(0xFF5C8FFF),
    };

    return SizedBox(
      height: metrics.taskRowHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: metrics.taskTimeColWidth,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _startTimeLabel(task),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: const Color(0xFF1E3152),
                  fontWeight: FontWeight.w700,
                  fontSize: metrics.taskTimeFontSize,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 14,
            child: Column(
              children: <Widget>[
                SizedBox(height: metrics.isCompact ? 8 : 10),
                Container(
                  width: metrics.timelineDotSize,
                  height: metrics.timelineDotSize,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: dotColor.withValues(alpha: 0.24),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                ),
                if (!isLast)
                  Container(
                    width: 2,
                    height: metrics.timelineLineHeight,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD8E4FF),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => context.push('/task/${task.id}'),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: metrics.isCompact ? 7 : 9,
                  ),
                  decoration: BoxDecoration(
                    color: emphasized ? cardColor : const Color(0xFFFDFEFF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: emphasized ? borderColor : const Color(0xFFEFF4FF),
                    ),
                    boxShadow: emphasized
                        ? const <BoxShadow>[
                            BoxShadow(
                              color: Color(0x122F6BFF),
                              blurRadius: 18,
                              offset: Offset(0, 8),
                            ),
                          ]
                        : const <BoxShadow>[],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              task.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    fontSize: metrics.taskTitleFontSize,
                                    color: const Color(0xFF22324C),
                                  ),
                            ),
                          ),
                          if (badge != null)
                            _StatusBadge(badge: badge, metrics: metrics),
                        ],
                      ),
                      SizedBox(height: metrics.isCompact ? 2 : 3),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              _buildTaskMetaLine(task),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: const Color(0xFF51637E),
                                    fontWeight: FontWeight.w600,
                                    fontSize: metrics.taskMetaFontSize,
                                  ),
                            ),
                          ),
                          if (task.hasVoiceNote) ...<Widget>[
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.graphic_eq_rounded,
                              color: ScheduleBoardPalette.tealAccent,
                              size: 14,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _buildTaskMetaLine(TaskPreview task) {
  final List<String> parts = <String>[task.timeLabel];
  if (task.hasVoiceNote) {
    parts.add('语音备注');
  }
  if (task.delayDays > 0) {
    parts.add('顺延${task.delayDays}天');
  }
  return parts.join('  ·  ');
}

class _GoalsCard extends StatelessWidget {
  const _GoalsCard({required this.todayTasksAsync, required this.metrics});

  final AsyncValue<List<TaskPreview>> todayTasksAsync;
  final DashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return _DashboardCard(
      metrics: metrics,
      child: todayTasksAsync.when(
        data: (List<TaskPreview> tasks) {
          if (tasks.isEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _GoalsHeader(metrics: metrics, completed: 0, total: 0),
                const SizedBox(height: 12),
                const Expanded(child: _EmptyCard(message: '今天还没有待办')),
              ],
            );
          }
          final int completed = tasks
              .where(
                (TaskPreview task) => task.state == TaskVisualState.completed,
              )
              .length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _GoalsHeader(
                metrics: metrics,
                completed: completed,
                total: tasks.length,
              ),
              SizedBox(height: metrics.cardGap),
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  physics: const ClampingScrollPhysics(),
                  itemCount: tasks.length,
                  separatorBuilder: (_, _) => Divider(
                    height: metrics.goalsRowDividerHeight,
                    color: const Color(0xFFE8EEFB),
                  ),
                  itemBuilder: (BuildContext context, int index) {
                    final TaskPreview task = tasks[index];
                    final bool done = task.state == TaskVisualState.completed;
                    return SizedBox(
                      height: metrics.goalsRowHeight,
                      child: Row(
                        children: <Widget>[
                          Icon(
                            done
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                            size: 20,
                            color: done
                                ? ScheduleBoardPalette.blueAccent
                                : const Color(0xFF97A5BC),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              task.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    fontSize: metrics.goalsItemFontSize,
                                    color: const Color(0xFF22324C),
                                  ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          _StatusBadge(
                            badge: _TaskBadge(
                              label: done ? '已完成' : '未完成',
                              backgroundColor: done
                                  ? const Color(0xFFEAF3FF)
                                  : const Color(0xFFFFEAEA),
                              textColor: done
                                  ? ScheduleBoardPalette.blueAccent
                                  : const Color(0xFFE14D3A),
                            ),
                            metrics: metrics,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
        loading: () => _GoalsLoadingPlaceholder(metrics: metrics),
        error: (_, _) => const _EmptyCard(message: '目标加载失败'),
      ),
    );
  }
}

class _GoalsHeader extends StatelessWidget {
  const _GoalsHeader({
    required this.metrics,
    required this.completed,
    required this.total,
  });

  final DashboardMetrics metrics;
  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(
          Icons.track_changes_rounded,
          color: ScheduleBoardPalette.blueAccent,
          size: metrics.goalsTitleFontSize + 4,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '今日目标',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              fontSize: metrics.goalsTitleFontSize,
              color: const Color(0xFF22324C),
            ),
          ),
        ),
        Text(
          '$completed/$total',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: ScheduleBoardPalette.blueAccent,
            fontWeight: FontWeight.w900,
            fontSize: metrics.goalsTitleFontSize,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '已完成',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: const Color(0xFF73819B),
            fontWeight: FontWeight.w700,
            fontSize: metrics.goalsTitleFontSize - 3,
          ),
        ),
      ],
    );
  }
}

class _NextTaskCard extends StatelessWidget {
  const _NextTaskCard({
    required this.now,
    required this.todayTasksAsync,
    required this.tomorrowTasksAsync,
    required this.metrics,
  });

  final DateTime now;
  final AsyncValue<List<TaskPreview>> todayTasksAsync;
  final AsyncValue<List<TaskPreview>> tomorrowTasksAsync;
  final DashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final List<TaskPreview> todayTasks =
        todayTasksAsync.valueOrNull ?? const <TaskPreview>[];
    final List<TaskPreview> tomorrowTasks =
        tomorrowTasksAsync.valueOrNull ?? const <TaskPreview>[];
    final TaskPreview? nextTask = _findNextTask(now, todayTasks, tomorrowTasks);
    final bool loading =
        todayTasksAsync.isLoading || tomorrowTasksAsync.isLoading;

    return _DashboardCard(
      metrics: metrics,
      child: nextTask == null
          ? loading
                ? _NextTaskLoadingPlaceholder(metrics: metrics)
                : const _EmptyCard(message: '下一项日程会显示在这里')
          : _NextTaskContent(task: nextTask, now: now, metrics: metrics),
    );
  }

  TaskPreview? _findNextTask(
    DateTime now,
    List<TaskPreview> todayTasks,
    List<TaskPreview> tomorrowTasks,
  ) {
    for (final TaskPreview task in todayTasks) {
      if (task.state == TaskVisualState.completed) {
        continue;
      }
      if (_resolveTaskMoment(task, now) != _TaskMoment.overdue) {
        return task;
      }
    }
    for (final TaskPreview task in tomorrowTasks) {
      if (task.state != TaskVisualState.completed) {
        return task;
      }
    }
    for (final TaskPreview task in todayTasks) {
      if (task.state != TaskVisualState.completed) {
        return task;
      }
    }
    return null;
  }
}

class _NextTaskContent extends StatelessWidget {
  const _NextTaskContent({
    required this.task,
    required this.now,
    required this.metrics,
  });

  final TaskPreview task;
  final DateTime now;
  final DashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final _TaskMoment moment = _resolveTaskMoment(task, now);
    final _TaskBadge? badge = _resolveTaskBadge(task, moment);
    final int? minutesUntil = _minutesUntilTask(task, now);
    final bool isTomorrow = task.occurrenceDate.isAfter(normalizeDate(now));
    final String headlineTime = task.isAllDay
        ? (isTomorrow ? '明日全天' : '今日全天')
        : _startTimeLabel(task);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('/task/${task.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.upcoming_rounded,
                color: ScheduleBoardPalette.blueAccent,
                size: metrics.goalsTitleFontSize + 4,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '下一项日程',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    fontSize: metrics.goalsTitleFontSize,
                    color: const Color(0xFF22324C),
                  ),
                ),
              ),
              if (!metrics.showNextTaskButton)
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: Color(0xFF98A6BE),
                ),
            ],
          ),
          SizedBox(height: metrics.isCompact ? 4 : 8),
          Expanded(
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: metrics.isCompact ? 10 : metrics.cardPadding - 4,
                vertical: metrics.isCompact ? 8 : metrics.cardPadding - 6,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(metrics.cardRadius - 8),
                color: const Color(0xFFF6FAFF),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: <Widget>[
                            Text(
                              headlineTime,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    color: ScheduleBoardPalette.blueAccent,
                                    fontWeight: FontWeight.w900,
                                    fontSize: metrics.nextTaskHeadlineFontSize,
                                  ),
                            ),
                            if (badge != null)
                              _StatusBadge(badge: badge, metrics: metrics),
                          ],
                        ),
                        SizedBox(height: metrics.isCompact ? 4 : 6),
                        Text(
                          task.title,
                          maxLines: metrics.nextTaskTitleMaxLines,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFF22324C),
                                fontSize: metrics.nextTaskTitleFontSize,
                                height: 1.2,
                              ),
                        ),
                        SizedBox(height: metrics.isCompact ? 4 : 6),
                        Row(
                          children: <Widget>[
                            const Icon(
                              Icons.schedule_rounded,
                              size: 14,
                              color: Color(0xFF71809A),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                task.timeLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: const Color(0xFF51637E),
                                      fontWeight: FontWeight.w600,
                                      fontSize: metrics.nextTaskMetaFontSize,
                                    ),
                              ),
                            ),
                          ],
                        ),
                        if (metrics.showNextTaskButton) ...<Widget>[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: () => context.push('/task/${task.id}'),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFFD8E4FF)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                              child: const Text(
                                '查看详情',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _CountdownRing(
                    minutesUntil: minutesUntil,
                    moment: moment,
                    isTomorrow: isTomorrow,
                    metrics: metrics,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CountdownRing extends StatelessWidget {
  const _CountdownRing({
    required this.minutesUntil,
    required this.moment,
    required this.isTomorrow,
    required this.metrics,
  });

  final int? minutesUntil;
  final _TaskMoment moment;
  final bool isTomorrow;
  final DashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final String primaryText;
    final String secondaryText;
    final double progress;

    switch (moment) {
      case _TaskMoment.active:
        primaryText = 'NOW';
        secondaryText = '进行中';
        progress = 1;
      case _TaskMoment.upcoming:
        primaryText = '${minutesUntil ?? 0}';
        secondaryText = '分钟后';
        progress = _countdownProgress(minutesUntil);
      case _TaskMoment.tomorrow:
        primaryText = '明日';
        secondaryText = '已排好';
        progress = 0.92;
      case _TaskMoment.allDay:
        primaryText = '全天';
        secondaryText = isTomorrow ? '明日事项' : '今日事项';
        progress = 0.88;
      case _TaskMoment.completed:
        primaryText = 'DONE';
        secondaryText = '已完成';
        progress = 1;
      case _TaskMoment.overdue:
        primaryText = '待办';
        secondaryText = '尽快处理';
        progress = 0.68;
      case _TaskMoment.later:
        primaryText = '${minutesUntil ?? 0}';
        secondaryText = '分钟后';
        progress = _countdownProgress(minutesUntil);
    }

    final double size = metrics.countdownRingSize;
    final double innerSize = size - 18;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 6,
              backgroundColor: const Color(0xFFE7EFFD),
              valueColor: const AlwaysStoppedAnimation<Color>(
                ScheduleBoardPalette.blueAccent,
              ),
            ),
          ),
          Container(
            width: innerSize,
            height: innerSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x120D47A1),
                  blurRadius: 16,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  primaryText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF1E3152),
                    fontWeight: FontWeight.w900,
                    fontSize: metrics.countdownPrimaryFontSize,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  secondaryText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: const Color(0xFF6C7C97),
                    fontWeight: FontWeight.w700,
                    fontSize: metrics.isCompact ? 10 : 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  double _countdownProgress(int? minutesUntil) {
    if (minutesUntil == null) {
      return 0.82;
    }
    final int clamped = minutesUntil.clamp(0, 180);
    return 0.2 + ((180 - clamped) / 180) * 0.8;
  }
}

class _WeatherPreviewCard extends StatelessWidget {
  const _WeatherPreviewCard({required this.metrics});

  final DashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final List<_WeatherHour> hours = const <_WeatherHour>[
      _WeatherHour(
        time: '10:00',
        icon: Icons.cloud_queue_rounded,
        temp: '23°C',
      ),
      _WeatherHour(
        time: '11:00',
        icon: Icons.cloud_queue_rounded,
        temp: '24°C',
      ),
      _WeatherHour(time: '12:00', icon: Icons.wb_sunny_rounded, temp: '25°C'),
      _WeatherHour(time: '13:00', icon: Icons.wb_sunny_rounded, temp: '26°C'),
      _WeatherHour(time: '14:00', icon: Icons.wb_sunny_rounded, temp: '27°C'),
      _WeatherHour(time: '15:00', icon: Icons.wb_sunny_rounded, temp: '27°C'),
    ];
    // Compact width 不够 6 列时减到 5 列（横向不能滚动）。
    final List<_WeatherHour> visibleHours = metrics.isCompact
        ? hours.take(5).toList()
        : hours;

    final double avatarSize = metrics.isCompact ? 36 : 44;
    return _DashboardCard(
      metrics: metrics,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.wb_sunny_outlined,
                color: ScheduleBoardPalette.blueAccent,
                size: metrics.goalsTitleFontSize + 4,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '天气',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    fontSize: metrics.goalsTitleFontSize,
                    color: const Color(0xFF22324C),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: metrics.isCompact ? 4 : 8),
          Expanded(
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: metrics.isCompact ? 10 : metrics.cardPadding - 4,
                vertical: metrics.isCompact ? 8 : metrics.cardPadding - 6,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(metrics.cardRadius - 8),
                color: const Color(0xFFF6FAFF),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      Container(
                        width: avatarSize,
                        height: avatarSize,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFEAF2FF),
                        ),
                        child: Icon(
                          Icons.cloud_rounded,
                          color: ScheduleBoardPalette.blueAccent,
                          size: metrics.isCompact ? 18 : 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '24',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF1E3152),
                              fontSize: metrics.weatherTempFontSize,
                              height: 1,
                            ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '°C 多云',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF50637E),
                              fontSize: metrics.weatherSummaryFontSize,
                            ),
                      ),
                      const Spacer(),
                      _WeatherMetaChip(
                        icon: Icons.water_drop_outlined,
                        label: '湿度 58%',
                        color: ScheduleBoardPalette.blueAccent,
                        metrics: metrics,
                      ),
                      const SizedBox(width: 6),
                      _WeatherMetaChip(
                        icon: Icons.eco_outlined,
                        label: '空气优 32',
                        color: const Color(0xFF27AE60),
                        metrics: metrics,
                      ),
                    ],
                  ),
                  SizedBox(height: metrics.isCompact ? 6 : 10),
                  const Divider(height: 1, color: Color(0xFFE4ECFA)),
                  SizedBox(height: metrics.isCompact ? 6 : 10),
                  SizedBox(
                    height: metrics.weatherHoursRowHeight,
                    child: Row(
                      children: <Widget>[
                        for (final _WeatherHour hour in visibleHours)
                          Expanded(
                            child: _WeatherHourTile(
                              hour: hour,
                              metrics: metrics,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (metrics.showWeatherTomorrowRow) ...<Widget>[
                    const SizedBox(height: 8),
                    const Divider(height: 1, color: Color(0xFFE4ECFA)),
                    const SizedBox(height: 8),
                    Text(
                      '明天 5月21日  晴  18°C ~ 27°C',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF50637E),
                        fontWeight: FontWeight.w700,
                        fontSize: metrics.weatherTempSecondaryFontSize,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.metrics});

  final String title;
  final DashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
            fontSize: metrics.sectionTitle,
            color: const Color(0xFF22324C),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: 30,
          height: 3,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: ScheduleBoardPalette.blueAccent,
          ),
        ),
      ],
    );
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({
    required this.icon,
    required this.message,
    required this.metrics,
    this.onTap,
  });

  final IconData icon;
  final String message;
  final DashboardMetrics metrics;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget content = Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: metrics.isCompact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8FF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icon, size: 16, color: ScheduleBoardPalette.blueAccent),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: const Color(0xFF5D6D87),
                fontWeight: FontWeight.w700,
                fontSize: metrics.summaryPillFontSize,
              ),
            ),
          ),
          if (onTap != null) ...<Widget>[
            const SizedBox(width: 6),
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: Color(0xFF98A6BE),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) {
      return content;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: content,
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.badge, required this.metrics});

  final _TaskBadge badge;
  final DashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: metrics.isCompact ? 7 : 8,
        vertical: metrics.isCompact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: badge.backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        badge.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: badge.textColor,
          fontWeight: FontWeight.w800,
          fontSize: metrics.isCompact ? 11 : 12,
        ),
      ),
    );
  }
}

class _WeatherMetaChip extends StatelessWidget {
  const _WeatherMetaChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.metrics,
  });

  final IconData icon;
  final String label;
  final Color color;
  final DashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 8,
        vertical: metrics.isCompact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: metrics.isCompact ? 11 : 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _WeatherHourTile extends StatelessWidget {
  const _WeatherHourTile({required this.hour, required this.metrics});

  final _WeatherHour hour;
  final DashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          hour.time,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: const Color(0xFF6E7D97),
            fontWeight: FontWeight.w700,
            fontSize: metrics.weatherHourFontSize,
          ),
        ),
        SizedBox(height: metrics.isCompact ? 4 : 6),
        Icon(hour.icon, color: Colors.orange, size: metrics.isCompact ? 16 : 20),
        SizedBox(height: metrics.isCompact ? 4 : 6),
        Text(
          hour.temp,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: const Color(0xFF3B4D69),
            fontWeight: FontWeight.w800,
            fontSize: metrics.weatherTempSecondaryFontSize,
          ),
        ),
      ],
    );
  }
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({required this.child, required this.metrics});

  final Widget child;
  final DashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(metrics.cardRadius),
        border: Border.all(color: const Color(0xFFDDE7FF)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x140D47A1),
            blurRadius: 28,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(metrics.cardPadding),
        child: child,
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: ScheduleBoardPalette.mutedText,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ScheduleLoadingPlaceholder extends StatelessWidget {
  const _ScheduleLoadingPlaceholder({required this.metrics});

  final DashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: 4,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (BuildContext context, int index) {
        return SizedBox(
          height: metrics.taskRowHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _placeholderBox(width: metrics.taskTimeColWidth, height: 16),
              const SizedBox(width: 12),
              Column(
                children: <Widget>[
                  _placeholderCircle(metrics.timelineDotSize + 2),
                  if (index != 3)
                    Expanded(
                      child: Container(
                        width: 2,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        color: const Color(0xFFE7EEFB),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 8),
              Expanded(child: _placeholderCard(height: double.infinity)),
            ],
          ),
        );
      },
    );
  }
}

class _GoalsLoadingPlaceholder extends StatelessWidget {
  const _GoalsLoadingPlaceholder({required this.metrics});

  final DashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Align(
          alignment: Alignment.centerLeft,
          child: _placeholderBox(width: 140, height: 22),
        ),
        SizedBox(height: metrics.cardGap),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: 4,
            separatorBuilder: (_, _) => Divider(
              height: metrics.goalsRowDividerHeight,
              color: const Color(0xFFE8EEFB),
            ),
            itemBuilder: (BuildContext context, int index) {
              return SizedBox(
                height: metrics.goalsRowHeight,
                child: Row(
                  children: <Widget>[
                    _placeholderCircle(20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _placeholderBox(
                        width: double.infinity,
                        height: 16,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _placeholderCard(height: 24, width: 60),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _NextTaskLoadingPlaceholder extends StatelessWidget {
  const _NextTaskLoadingPlaceholder({required this.metrics});

  final DashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _placeholderBox(width: 120, height: 18),
        SizedBox(height: metrics.isCompact ? 4 : 8),
        Expanded(
          child: _placeholderCard(
            height: double.infinity,
            child: Padding(
              padding: EdgeInsets.all(metrics.isCompact ? 10 : 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        _placeholderBox(width: 88, height: 18),
                        SizedBox(height: metrics.isCompact ? 4 : 8),
                        _placeholderBox(width: double.infinity, height: 14),
                        SizedBox(height: metrics.isCompact ? 4 : 6),
                        _placeholderBox(width: 132, height: 12),
                        if (metrics.showNextTaskButton) ...<Widget>[
                          const SizedBox(height: 10),
                          _placeholderCard(height: 32),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _placeholderCircle(metrics.countdownRingSize),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AmbientGlow extends StatelessWidget {
  const _AmbientGlow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: <BoxShadow>[
            BoxShadow(color: color, blurRadius: size / 2, spreadRadius: 10),
          ],
        ),
      ),
    );
  }
}

class _WeatherHour {
  const _WeatherHour({
    required this.time,
    required this.icon,
    required this.temp,
  });

  final String time;
  final IconData icon;
  final String temp;
}

class _TaskBadge {
  const _TaskBadge({
    required this.label,
    required this.backgroundColor,
    required this.textColor,
  });

  final String label;
  final Color backgroundColor;
  final Color textColor;
}

enum _TaskMoment {
  active,
  upcoming,
  later,
  tomorrow,
  overdue,
  completed,
  allDay,
}

_TaskMoment _resolveTaskMoment(TaskPreview task, DateTime now) {
  if (task.state == TaskVisualState.completed) {
    return _TaskMoment.completed;
  }

  final DateTime today = normalizeDate(now);
  if (task.occurrenceDate.isAfter(today)) {
    return _TaskMoment.tomorrow;
  }

  if (task.isAllDay) {
    return _TaskMoment.allDay;
  }

  final int nowMinutes = now.hour * 60 + now.minute;
  final int? startMinutes = _extractStartMinutes(task.timeLabel);
  final int? endMinutes = _extractEndMinutes(task.timeLabel) ?? startMinutes;

  if (task.isOverdueAt(now)) {
    return _TaskMoment.overdue;
  }

  if (startMinutes == null) {
    return _TaskMoment.later;
  }

  if (nowMinutes >= startMinutes &&
      endMinutes != null &&
      nowMinutes < endMinutes) {
    return _TaskMoment.active;
  }
  if (startMinutes > nowMinutes && startMinutes - nowMinutes <= 90) {
    return _TaskMoment.upcoming;
  }
  return _TaskMoment.later;
}

_TaskBadge? _resolveTaskBadge(TaskPreview task, _TaskMoment moment) {
  switch (moment) {
    case _TaskMoment.active:
      return const _TaskBadge(
        label: '进行中',
        backgroundColor: Color(0xFFEAF3FF),
        textColor: ScheduleBoardPalette.blueAccent,
      );
    case _TaskMoment.upcoming:
      return const _TaskBadge(
        label: '即将开始',
        backgroundColor: Color(0xFFEAF3FF),
        textColor: ScheduleBoardPalette.blueAccent,
      );
    case _TaskMoment.overdue:
      return _TaskBadge(
        label: task.delayDays > 0 ? '顺延${task.delayDays}天' : '待处理',
        backgroundColor: const Color(0xFFFFEFEA),
        textColor: const Color(0xFFE14D3A),
      );
    case _TaskMoment.completed:
      return const _TaskBadge(
        label: '已完成',
        backgroundColor: Color(0xFFF0F4FA),
        textColor: Color(0xFF7B8AA4),
      );
    case _TaskMoment.tomorrow:
    case _TaskMoment.later:
    case _TaskMoment.allDay:
      return null;
  }
}

String _startTimeLabel(TaskPreview task) {
  if (task.isAllDay) {
    return '全天';
  }
  final int? minutes = _extractStartMinutes(task.timeLabel);
  if (minutes == null) {
    return '--:--';
  }
  return formatMinutesOfDay(minutes);
}

int? _minutesUntilTask(TaskPreview task, DateTime now) {
  final DateTime today = normalizeDate(now);
  final DateTime occurrenceDate = normalizeDate(task.occurrenceDate);
  if (occurrenceDate.isAfter(today)) {
    final int? startMinutes = _extractStartMinutes(task.timeLabel);
    if (startMinutes == null) {
      return 24 * 60;
    }
    final DateTime target = occurrenceDate.add(Duration(minutes: startMinutes));
    return target.difference(now).inMinutes;
  }

  final int? startMinutes = _extractStartMinutes(task.timeLabel);
  if (startMinutes == null) {
    return null;
  }
  final DateTime target = today.add(Duration(minutes: startMinutes));
  return target.difference(now).inMinutes;
}

int? _extractStartMinutes(String label) {
  final Iterable<RegExpMatch> matches = RegExp(
    r'(\d{2}):(\d{2})',
  ).allMatches(label);
  if (matches.isEmpty) {
    return null;
  }
  final RegExpMatch match = matches.first;
  final int? hour = int.tryParse(match.group(1) ?? '');
  final int? minute = int.tryParse(match.group(2) ?? '');
  if (hour == null || minute == null) {
    return null;
  }
  return hour * 60 + minute;
}

int? _extractEndMinutes(String label) {
  final List<RegExpMatch> matches = RegExp(
    r'(\d{2}):(\d{2})',
  ).allMatches(label).toList();
  if (matches.length < 2) {
    return null;
  }
  final RegExpMatch match = matches[1];
  final int? hour = int.tryParse(match.group(1) ?? '');
  final int? minute = int.tryParse(match.group(2) ?? '');
  if (hour == null || minute == null) {
    return null;
  }
  return hour * 60 + minute;
}

Widget _placeholderCard({
  required double height,
  double? width,
  Widget? child,
}) {
  return Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: const Color(0xFFF4F7FC),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFE6ECF8)),
    ),
    child: child,
  );
}

Widget _placeholderBox({required double width, required double height}) {
  return Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: const Color(0xFFF0F4FA),
      borderRadius: BorderRadius.circular(999),
    ),
  );
}

Widget _placeholderCircle(double size) {
  return Container(
    width: size,
    height: size,
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      color: Color(0xFFF0F4FA),
    ),
  );
}
