import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/models/task_preview.dart';
import '../../../core/utils/calendar_utils.dart';
import '../../../core/utils/task_formatters.dart';
import '../../home/application/home_view_mode.dart';
import '../../task/application/task_providers.dart';
import '../../task/domain/task.dart';

class ReminderAlertPage extends ConsumerWidget {
  const ReminderAlertPage({
    required this.taskId,
    required this.occurrenceDate,
    super.key,
  });

  final int taskId;
  final DateTime occurrenceDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Task?> taskAsync = ref.watch(taskDetailsProvider(taskId));

    return Scaffold(
      backgroundColor: const Color(0xB31A2435),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                  child: taskAsync.when(
                    data: (Task? task) => _buildContent(context, ref, task),
                    loading: () => const _ReminderLoading(),
                    error: (_, stackTrace) => _ReminderFallback(
                      title: '提醒打开失败了',
                      message: '这条待办暂时没读出来，你可以先回到首页再试一次。',
                      onClose: () => _closePage(context),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref, Task? task) {
    if (task == null || task.deletedAt != null) {
      return _ReminderFallback(
        title: '这条提醒已经不存在了',
        message: '它可能已经被删除，你可以直接回到首页继续安排别的事。',
        onClose: () => _closePage(context),
      );
    }

    final DateTime normalizedDate = normalizeDate(occurrenceDate);
    final TaskPreview preview = TaskPreview.fromOccurrence(
      TaskOccurrence(task: task, occurrenceDate: normalizedDate),
    );
    final bool alreadyCompleted =
        task.repeatKey == TaskRepeatKey.none &&
        task.status == TaskStatus.completed;
    final String subtitle =
        '${formatHeadlineDate(normalizedDate)} · ${preview.timeLabel}';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              colors: <Color>[
                ScheduleBoardPalette.blueAccent,
                ScheduleBoardPalette.tealAccent,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const Icon(
            Icons.notifications_active_rounded,
            color: Colors.white,
            size: 34,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          alreadyCompleted ? '这项待办已经完成了' : '该处理这项待办了',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Text(
          task.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: ScheduleBoardPalette.mutedText,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (task.repeatKey != TaskRepeatKey.none) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            '这是重复待办，本次完成后会自动跳到下一次。',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: ScheduleBoardPalette.mutedText,
            ),
          ),
        ],
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: alreadyCompleted
                ? null
                : () async {
                    await ref
                        .read(taskMutationControllerProvider)
                        .completeTaskById(
                          taskId: taskId,
                          occurrenceDate: normalizedDate,
                        );
                    if (context.mounted) {
                      _closePage(context);
                    }
                  },
            style: FilledButton.styleFrom(
              backgroundColor: ScheduleBoardPalette.warmAccent,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.workspace_premium_rounded),
            label: Text(
              alreadyCompleted ? '已完成' : '完成这项待办',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              ref.read(selectedDateProvider.notifier).state = normalizedDate;
              ref.read(homeViewModeProvider.notifier).state = HomeViewMode.day;
              context.pushReplacement('/task/$taskId');
            },
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text(
              '查看详情',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.center,
          child: TextButton(
            onPressed: () => _closePage(context),
            child: const Text(
              '稍后处理',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }

  void _closePage(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      context.pop();
      return;
    }
    context.go('/');
  }
}

class _ReminderLoading extends StatelessWidget {
  const _ReminderLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 40),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _ReminderFallback extends StatelessWidget {
  const _ReminderFallback({
    required this.title,
    required this.message,
    required this.onClose,
  });

  final String title;
  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Text(
          message,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: ScheduleBoardPalette.mutedText,
          ),
        ),
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: onClose,
            child: const Text(
              '回到首页',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }
}
