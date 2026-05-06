import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/notification_providers.dart';
import '../../../core/utils/calendar_utils.dart';
import '../../../core/database/database_providers.dart';
import '../../../core/models/task_preview.dart';
import '../../settings/application/app_settings_controller.dart';
import '../domain/task.dart';
import '../domain/task_voice_note.dart';

final taskRefreshTickProvider = StateProvider<int>((Ref ref) => 0);

class TaskDateWindow {
  const TaskDateWindow({required this.startDate, required this.dayCount});

  final DateTime startDate;
  final int dayCount;

  @override
  bool operator ==(Object other) {
    return other is TaskDateWindow &&
        isSameDate(other.startDate, startDate) &&
        other.dayCount == dayCount;
  }

  @override
  int get hashCode =>
      Object.hash(startDate.year, startDate.month, startDate.day, dayCount);
}

class DailyTaskPreviewBucket {
  const DailyTaskPreviewBucket({required this.date, required this.tasks});

  final DateTime date;
  final List<TaskPreview> tasks;
}

final taskPreviewsForDateProvider =
    FutureProvider.family<List<TaskPreview>, DateTime>((
      Ref ref,
      DateTime date,
    ) async {
      ref.watch(taskRefreshTickProvider);
      final bool showCompleted = (await ref.watch(
        appSettingsControllerProvider.future,
      )).showCompleted;

      final repository = ref.watch(taskRepositoryProvider);
      final List<TaskOccurrence> occurrences = await repository
          .listOccurrencesForDate(date);

      final List<TaskOccurrence> filtered = occurrences
          .where(
            (TaskOccurrence occurrence) =>
                showCompleted || occurrence.task.status != TaskStatus.completed,
          )
          .toList();
      final Map<int, TaskVoiceNote> voiceMap = await repository
          .latestVoiceNotesFor(
            filtered
                .map((TaskOccurrence occurrence) => occurrence.task.id)
                .whereType<int>()
                .toList(),
          );
      return filtered.map((TaskOccurrence occurrence) {
        final TaskVoiceNote? note = occurrence.task.id == null
            ? null
            : voiceMap[occurrence.task.id];
        return TaskPreview.fromOccurrence(
          occurrence,
          hasVoiceNote: note != null,
          voiceFilePath: note?.localPath,
          voiceDurationMillis: note?.durationMillis ?? 0,
        );
      }).toList();
    });

final taskPreviewBucketsProvider =
    FutureProvider.family<List<DailyTaskPreviewBucket>, TaskDateWindow>((
      Ref ref,
      TaskDateWindow window,
    ) async {
      ref.watch(taskRefreshTickProvider);
      final bool showCompleted = (await ref.watch(
        appSettingsControllerProvider.future,
      )).showCompleted;
      final repository = ref.watch(taskRepositoryProvider);

      final List<DailyTaskPreviewBucket> buckets = <DailyTaskPreviewBucket>[];
      final List<List<TaskOccurrence>> filteredPerDay =
          <List<TaskOccurrence>>[];
      final Set<int> taskIds = <int>{};

      for (int offset = 0; offset < window.dayCount; offset++) {
        final DateTime date = normalizeDate(
          window.startDate.add(Duration(days: offset)),
        );
        final List<TaskOccurrence> occurrences = await repository
            .listOccurrencesForDate(date);
        final List<TaskOccurrence> filtered = occurrences
            .where(
              (TaskOccurrence occurrence) =>
                  showCompleted ||
                  occurrence.task.status != TaskStatus.completed,
            )
            .toList();
        filteredPerDay.add(filtered);
        for (final TaskOccurrence occurrence in filtered) {
          final int? id = occurrence.task.id;
          if (id != null) {
            taskIds.add(id);
          }
        }
      }

      final Map<int, TaskVoiceNote> voiceMap = await repository
          .latestVoiceNotesFor(taskIds.toList());

      for (int offset = 0; offset < window.dayCount; offset++) {
        final DateTime date = normalizeDate(
          window.startDate.add(Duration(days: offset)),
        );
        buckets.add(
          DailyTaskPreviewBucket(
            date: date,
            tasks: filteredPerDay[offset].map((TaskOccurrence occurrence) {
              final TaskVoiceNote? note = occurrence.task.id == null
                  ? null
                  : voiceMap[occurrence.task.id];
              return TaskPreview.fromOccurrence(
                occurrence,
                hasVoiceNote: note != null,
                voiceFilePath: note?.localPath,
                voiceDurationMillis: note?.durationMillis ?? 0,
              );
            }).toList(),
          ),
        );
      }
      return buckets;
    });

final taskVoiceNoteProvider = FutureProvider.family<TaskVoiceNote?, int>((
  Ref ref,
  int taskId,
) {
  ref.watch(taskRefreshTickProvider);
  return ref.watch(taskRepositoryProvider).getVoiceNote(taskId);
});

final taskMutationControllerProvider = Provider<TaskMutationController>((
  Ref ref,
) {
  return TaskMutationController(ref);
});

final taskDetailsProvider = FutureProvider.family<Task?, int>((
  Ref ref,
  int taskId,
) {
  return ref.watch(taskRepositoryProvider).getTaskById(taskId);
});

class TaskMutationController {
  const TaskMutationController(this._ref);

  final Ref _ref;

  Future<int> createTask(Task task) async {
    final int id = await _ref.read(taskRepositoryProvider).createTask(task);
    _bump();
    unawaited(_syncRemindersInBackground());
    return id;
  }

  Future<void> updateTask(Task task) async {
    await _ref.read(taskRepositoryProvider).updateTask(task);
    _bump();
    unawaited(_syncRemindersInBackground());
  }

  Future<void> toggleCompletion(TaskPreview preview) async {
    await _ref
        .read(taskRepositoryProvider)
        .toggleCompletion(
          taskId: preview.id,
          occurrenceDate: preview.occurrenceDate,
          completed: preview.state != TaskVisualState.completed,
        );
    _bump();
    unawaited(_syncRemindersInBackground());
  }

  Future<void> completeTaskById({
    required int taskId,
    required DateTime occurrenceDate,
  }) async {
    await _ref
        .read(taskRepositoryProvider)
        .toggleCompletion(
          taskId: taskId,
          occurrenceDate: occurrenceDate,
          completed: true,
        );
    _bump();
    unawaited(_syncRemindersInBackground());
  }

  Future<void> softDeleteTask(TaskPreview preview) async {
    await _ref.read(taskRepositoryProvider).softDeleteTask(preview.id);
    _bump();
    unawaited(_syncRemindersInBackground());
  }

  Future<void> softDeleteTaskById(int taskId) async {
    await _ref.read(taskRepositoryProvider).softDeleteTask(taskId);
    _bump();
    unawaited(_syncRemindersInBackground());
  }

  Future<void> upsertVoiceNote({
    required int taskId,
    required String localPath,
    required int durationMillis,
  }) async {
    await _ref
        .read(taskRepositoryProvider)
        .upsertVoiceNote(
          taskId: taskId,
          localPath: localPath,
          durationMillis: durationMillis,
        );
    _bump();
  }

  Future<void> deleteVoiceNote(int taskId) async {
    await _ref.read(taskRepositoryProvider).deleteVoiceNote(taskId);
    _bump();
  }

  void _bump() {
    _ref.read(taskRefreshTickProvider.notifier).state++;
  }

  Future<void> _syncRemindersInBackground() async {
    try {
      await _ref.read(reminderSyncControllerProvider).syncNow();
    } catch (error, stackTrace) {
      debugPrint('Reminder sync failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
