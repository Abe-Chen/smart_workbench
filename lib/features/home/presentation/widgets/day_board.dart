import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme.dart';
import '../../../../core/models/task_preview.dart';
import '../../../../core/utils/calendar_utils.dart';
import '../../../../core/utils/task_formatters.dart';
import '../../../task/application/task_providers.dart';
import '../../application/home_view_mode.dart';
import 'date_timeline_strip.dart';
import 'task_section_card.dart';

class DayBoard extends ConsumerStatefulWidget {
  const DayBoard({
    required this.compact,
    required this.selectedDate,
    super.key,
  });

  final bool compact;
  final DateTime selectedDate;

  @override
  ConsumerState<DayBoard> createState() => _DayBoardState();
}

class _DayBoardState extends ConsumerState<DayBoard> {
  late final ConfettiController _centerConfettiController;
  List<DailyTaskPreviewBucket>? _cachedBuckets;
  List<TaskPreview>? _cachedNextTasks;

  @override
  void initState() {
    super.initState();
    _centerConfettiController = ConfettiController(
      duration: const Duration(milliseconds: 1000),
    );
  }

  @override
  void dispose() {
    _centerConfettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DateTime normalizedSelected = normalizeDate(widget.selectedDate);
    final List<DateTime> dates = weekDates(normalizedSelected);
    final DateTime nextDate = normalizedSelected.add(const Duration(days: 1));
    final AsyncValue<List<DailyTaskPreviewBucket>> weekBuckets = ref.watch(
      taskPreviewBucketsProvider(
        TaskDateWindow(startDate: dates.first, dayCount: dates.length),
      ),
    );
    final AsyncValue<List<TaskPreview>> nextTasks = ref.watch(
      taskPreviewsForDateProvider(nextDate),
    );
    final List<TaskPreview>? nextTasksData = nextTasks.valueOrNull;
    if (nextTasksData != null) {
      _cachedNextTasks = nextTasksData;
    }

    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: <Widget>[
        _buildBody(
          context: context,
          dates: dates,
          normalizedSelected: normalizedSelected,
          nextDate: nextDate,
          weekBuckets: weekBuckets,
          nextTasks: nextTasksData ?? _cachedNextTasks ?? const <TaskPreview>[],
        ),
        IgnorePointer(
          child: _CompletionCelebrationLayer(
            confettiController: _centerConfettiController,
          ),
        ),
      ],
    );
  }

  Widget _buildBody({
    required BuildContext context,
    required List<DateTime> dates,
    required DateTime normalizedSelected,
    required DateTime nextDate,
    required AsyncValue<List<DailyTaskPreviewBucket>> weekBuckets,
    required List<TaskPreview> nextTasks,
  }) {
    final List<DailyTaskPreviewBucket>? buckets = weekBuckets.valueOrNull;
    if (buckets != null) {
      _cachedBuckets = buckets;
      return _buildContent(
        context: context,
        dates: dates,
        normalizedSelected: normalizedSelected,
        nextDate: nextDate,
        buckets: buckets,
        nextTasks: nextTasks,
      );
    }

    final List<DailyTaskPreviewBucket>? cachedBuckets = _cachedBuckets;
    if (cachedBuckets != null) {
      return _buildContent(
        context: context,
        dates: dates,
        normalizedSelected: normalizedSelected,
        nextDate: nextDate,
        buckets: cachedBuckets,
        nextTasks: nextTasks,
      );
    }

    return weekBuckets.when(
      data: (_) => const SizedBox.shrink(),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, StackTrace stackTrace) => Center(
        child: Text(
          '日视图加载失败，请稍后重试',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }

  Widget _buildContent({
    required BuildContext context,
    required List<DateTime> dates,
    required DateTime normalizedSelected,
    required DateTime nextDate,
    required List<DailyTaskPreviewBucket> buckets,
    required List<TaskPreview> nextTasks,
  }) {
    final Map<DateTime, List<TaskPreview>> bucketMap =
        <DateTime, List<TaskPreview>>{
          for (final DailyTaskPreviewBucket bucket in buckets)
            normalizeDate(bucket.date): bucket.tasks,
        };
    final Map<DateTime, int> taskCounts = <DateTime, int>{
      for (final DailyTaskPreviewBucket bucket in buckets)
        normalizeDate(bucket.date): bucket.tasks.length,
    };
    final DateTime tomorrow = normalizeDate(
      DateTime.now().add(const Duration(days: 1)),
    );
    final List<TaskPreview> selectedTasks =
        bucketMap[normalizedSelected] ?? const <TaskPreview>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        DateTimelineStrip(
          dates: dates,
          selectedDate: normalizedSelected,
          taskCounts: taskCounts,
          onSelectDate: (DateTime date) {
            ref.read(selectedDateProvider.notifier).state = normalizeDate(date);
          },
        ),
        const SizedBox(height: 10),
        Expanded(
          child: widget.compact
              ? ListView(
                  children: <Widget>[
                    _buildSection(
                      context,
                      title: _sectionTitleForDate(normalizedSelected),
                      tasks: selectedTasks,
                      accentColor: ScheduleBoardPalette.blueAccent,
                      leadingIcon: Icons.schedule_rounded,
                      fillHeight: false,
                      emptyMessage: _emptyMessageForSelected(
                        normalizedSelected,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildSection(
                      context,
                      title: isSameDate(nextDate, tomorrow)
                          ? '明日待办'
                          : '${formatMonthDayLabel(nextDate)}待办',
                      tasks: nextTasks,
                      accentColor: ScheduleBoardPalette.tealAccent,
                      leadingIcon: Icons.task_alt_rounded,
                      fillHeight: false,
                      emptyMessage: _emptyMessageForNext(nextDate, tomorrow),
                    ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(
                      child: _buildSection(
                        context,
                        title: _sectionTitleForDate(normalizedSelected),
                        tasks: selectedTasks,
                        accentColor: ScheduleBoardPalette.blueAccent,
                        leadingIcon: Icons.schedule_rounded,
                        fillHeight: true,
                        emptyMessage: _emptyMessageForSelected(
                          normalizedSelected,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildSection(
                        context,
                        title: isSameDate(nextDate, tomorrow)
                            ? '明日待办'
                            : '${formatMonthDayLabel(nextDate)}待办',
                        tasks: nextTasks,
                        accentColor: ScheduleBoardPalette.tealAccent,
                        leadingIcon: Icons.task_alt_rounded,
                        fillHeight: true,
                        emptyMessage: _emptyMessageForNext(nextDate, tomorrow),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required List<TaskPreview> tasks,
    required Color accentColor,
    required IconData leadingIcon,
    required bool fillHeight,
    required String emptyMessage,
  }) {
    return TaskSectionCard(
      title: title,
      subtitle: '${tasks.length}',
      tasks: tasks,
      accentColor: accentColor,
      leadingIcon: leadingIcon,
      fillHeight: fillHeight,
      emptyMessage: emptyMessage,
      onTapTask: (TaskPreview task) {
        context.push('/task/${task.id}');
      },
      onToggleComplete: (TaskPreview task) async {
        final bool completed = task.state != TaskVisualState.completed;
        if (completed) {
          _playCompletionCelebration();
          await SchedulerBinding.instance.endOfFrame;
        }
        await ref.read(taskMutationControllerProvider).toggleCompletion(task);
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(completed ? '已完成' : '已恢复为未完成')));
      },
      onDelete: (TaskPreview task) async {
        await ref.read(taskMutationControllerProvider).softDeleteTask(task);
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('待办已删除')));
      },
    );
  }

  String _sectionTitleForDate(DateTime date) {
    final DateTime today = normalizeDate(DateTime.now());
    if (isSameDate(date, today)) {
      return '今日待办';
    }
    return '${formatMonthDayLabel(date)}待办';
  }

  String _emptyMessageForSelected(DateTime date) {
    final DateTime today = normalizeDate(DateTime.now());
    if (isSameDate(date, today)) {
      return '今天暂无待办，点击右上角 + 创建一个待办';
    }
    return '${formatMonthDayLabel(date)}暂无待办';
  }

  String _emptyMessageForNext(DateTime nextDate, DateTime tomorrow) {
    if (isSameDate(nextDate, tomorrow)) {
      return '明天暂无待办';
    }
    return '${formatMonthDayLabel(nextDate)}暂无待办';
  }

  void _playCompletionCelebration() {
    HapticFeedback.mediumImpact();
    _centerConfettiController.play();
  }
}

class _CompletionCelebrationLayer extends StatelessWidget {
  const _CompletionCelebrationLayer({required this.confettiController});

  final ConfettiController confettiController;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: ConfettiWidget(
        confettiController: confettiController,
        blastDirectionality: BlastDirectionality.explosive,
        emissionFrequency: 0.24,
        numberOfParticles: 24,
        maxBlastForce: 24,
        minBlastForce: 10,
        gravity: 0.2,
        particleDrag: 0.04,
        shouldLoop: false,
        colors: _celebrationColors,
        minimumSize: const Size(7, 7),
        maximumSize: const Size(14, 14),
      ),
    );
  }
}

const List<Color> _celebrationColors = <Color>[
  ScheduleBoardPalette.blueAccent,
  ScheduleBoardPalette.tealAccent,
  ScheduleBoardPalette.warmAccent,
  Color(0xFFFFD166),
  Color(0xFFFF6B6B),
];
