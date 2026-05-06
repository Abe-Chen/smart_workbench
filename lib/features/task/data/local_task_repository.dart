import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../../../core/database/schedule_database.dart';
import '../../../core/utils/task_formatters.dart';
import '../domain/task.dart';
import '../domain/task_voice_note.dart';

class LocalTaskRepository {
  const LocalTaskRepository(this._database);

  final ScheduleDatabase _database;

  Future<List<TaskOccurrence>> listOccurrencesForDate(DateTime date) async {
    final Database database = await _database.database;
    final List<Map<String, Object?>> rows = await database.query(
      'tasks',
      where: 'deleted_at IS NULL',
      orderBy: 'start_date ASC, start_time_minutes ASC, updated_at DESC',
    );

    final DateTime target = DateTime(date.year, date.month, date.day);
    final DateTime today = DateTime.now();
    final DateTime normalizedToday = DateTime(
      today.year,
      today.month,
      today.day,
    );
    final List<TaskOccurrence> occurrences = <TaskOccurrence>[];

    for (final Map<String, Object?> row in rows) {
      final Task task = Task.fromMap(row);
      final DateTime sourceDate = DateTime(
        task.startDate.year,
        task.startDate.month,
        task.startDate.day,
      );

      final bool shouldRollToToday =
          task.repeatKey == TaskRepeatKey.none &&
          task.status == TaskStatus.pending &&
          sourceDate.isBefore(normalizedToday);
      if (shouldRollToToday) {
        if (_isSameDate(target, normalizedToday)) {
          occurrences.add(
            TaskOccurrence(
              task: task,
              occurrenceDate: normalizedToday,
              sourceDate: sourceDate,
            ),
          );
        }
        continue;
      }

      if (task.occursOn(target)) {
        occurrences.add(
          TaskOccurrence(
            task: task,
            occurrenceDate: target,
            sourceDate: target,
          ),
        );
      }
    }

    occurrences.sort((TaskOccurrence left, TaskOccurrence right) {
      final bool leftCompleted = left.task.status == TaskStatus.completed;
      final bool rightCompleted = right.task.status == TaskStatus.completed;
      if (leftCompleted != rightCompleted) {
        return leftCompleted ? 1 : -1;
      }

      if (left.task.isAllDay != right.task.isAllDay) {
        return left.task.isAllDay ? -1 : 1;
      }

      final int leftMinutes = left.task.startTimeMinutes ?? 0;
      final int rightMinutes = right.task.startTimeMinutes ?? 0;
      final int timeCompare = leftMinutes.compareTo(rightMinutes);
      if (timeCompare != 0) {
        return timeCompare;
      }

      return left.task.updatedAt.compareTo(right.task.updatedAt);
    });

    return occurrences;
  }

  bool _isSameDate(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  Future<int> createTask(Task task) async {
    final Database database = await _database.database;
    final Map<String, Object?> values = task.toMap()..remove('id');
    return database.insert('tasks', values);
  }

  Future<Task?> getTaskById(int taskId) async {
    final Database database = await _database.database;
    final List<Map<String, Object?>> rows = await database.query(
      'tasks',
      where: 'id = ?',
      whereArgs: <Object?>[taskId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return Task.fromMap(rows.first);
  }

  Future<void> updateTask(Task task) async {
    if (task.id == null) {
      return;
    }

    final Database database = await _database.database;
    final Map<String, Object?> values = task.toMap()..remove('id');
    await database.update(
      'tasks',
      values,
      where: 'id = ?',
      whereArgs: <Object?>[task.id],
    );
  }

  Future<List<Task>> listReminderEligibleTasks() async {
    final Database database = await _database.database;
    final List<Map<String, Object?>> rows = await database.query(
      'tasks',
      where: 'deleted_at IS NULL AND status = ?',
      whereArgs: <Object?>[TaskStatus.pending.name],
      orderBy: 'start_date ASC, start_time_minutes ASC',
    );
    return rows.map(Task.fromMap).toList();
  }

  Future<void> toggleCompletion({
    required int taskId,
    required DateTime occurrenceDate,
    required bool completed,
  }) async {
    final Database database = await _database.database;
    final List<Map<String, Object?>> rows = await database.query(
      'tasks',
      where: 'id = ?',
      whereArgs: <Object?>[taskId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return;
    }

    final Task task = Task.fromMap(rows.first);
    final DateTime now = DateTime.now();

    if (completed) {
      if (task.repeatKey != TaskRepeatKey.none) {
        final DateTime nextDate = task.nextOccurrenceAfter(occurrenceDate);
        await database.update(
          'tasks',
          <String, Object?>{
            'start_date': formatStorageDate(nextDate),
            'updated_at': formatStorageDateTime(now),
            'completed_at': null,
            'status': TaskStatus.pending.name,
          },
          where: 'id = ?',
          whereArgs: <Object?>[taskId],
        );
        return;
      }

      await database.update(
        'tasks',
        <String, Object?>{
          'status': TaskStatus.completed.name,
          'completed_at': formatStorageDateTime(now),
          'updated_at': formatStorageDateTime(now),
        },
        where: 'id = ?',
        whereArgs: <Object?>[taskId],
      );
      return;
    }

    await database.update(
      'tasks',
      <String, Object?>{
        'status': TaskStatus.pending.name,
        'completed_at': null,
        'updated_at': formatStorageDateTime(now),
      },
      where: 'id = ?',
      whereArgs: <Object?>[taskId],
    );
  }

  Future<void> softDeleteTask(int taskId) async {
    final Database database = await _database.database;
    final DateTime now = DateTime.now();
    await database.update(
      'tasks',
      <String, Object?>{
        'status': TaskStatus.deleted.name,
        'deleted_at': formatStorageDateTime(now),
        'updated_at': formatStorageDateTime(now),
      },
      where: 'id = ?',
      whereArgs: <Object?>[taskId],
    );

    final List<TaskVoiceNote> notes = await listVoiceNotes(taskId);
    for (final TaskVoiceNote note in notes) {
      await _deleteVoiceFile(note.localPath);
    }
    await database.delete(
      'task_voice_notes',
      where: 'task_id = ?',
      whereArgs: <Object?>[taskId],
    );
  }

  Future<TaskVoiceNote?> getVoiceNote(int taskId) async {
    final Database database = await _database.database;
    final List<Map<String, Object?>> rows = await database.query(
      'task_voice_notes',
      where: 'task_id = ?',
      whereArgs: <Object?>[taskId],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return TaskVoiceNote.fromMap(rows.first);
  }

  Future<List<TaskVoiceNote>> listVoiceNotes(int taskId) async {
    final Database database = await _database.database;
    final List<Map<String, Object?>> rows = await database.query(
      'task_voice_notes',
      where: 'task_id = ?',
      whereArgs: <Object?>[taskId],
      orderBy: 'created_at DESC',
    );
    return rows.map(TaskVoiceNote.fromMap).toList();
  }

  Future<Map<int, TaskVoiceNote>> latestVoiceNotesFor(List<int> taskIds) async {
    if (taskIds.isEmpty) {
      return const <int, TaskVoiceNote>{};
    }
    final Database database = await _database.database;
    final String placeholders = List<String>.filled(
      taskIds.length,
      '?',
    ).join(',');
    final List<Map<String, Object?>> rows = await database.rawQuery(
      'SELECT * FROM task_voice_notes WHERE task_id IN ($placeholders) ORDER BY created_at DESC',
      taskIds,
    );
    final Map<int, TaskVoiceNote> latest = <int, TaskVoiceNote>{};
    for (final Map<String, Object?> row in rows) {
      final TaskVoiceNote note = TaskVoiceNote.fromMap(row);
      latest.putIfAbsent(note.taskId, () => note);
    }
    return latest;
  }

  Future<void> upsertVoiceNote({
    required int taskId,
    required String localPath,
    required int durationMillis,
  }) async {
    final Database database = await _database.database;
    final DateTime now = DateTime.now();
    await database.transaction((Transaction txn) async {
      final List<Map<String, Object?>> existing = await txn.query(
        'task_voice_notes',
        where: 'task_id = ?',
        whereArgs: <Object?>[taskId],
      );
      for (final Map<String, Object?> row in existing) {
        final String oldPath = row['local_path'] as String? ?? '';
        if (oldPath.isNotEmpty && oldPath != localPath) {
          await _deleteVoiceFile(oldPath);
        }
      }
      await txn.delete(
        'task_voice_notes',
        where: 'task_id = ?',
        whereArgs: <Object?>[taskId],
      );
      await txn.insert('task_voice_notes', <String, Object?>{
        'task_id': taskId,
        'local_path': localPath,
        'duration_millis': durationMillis,
        'created_at': formatStorageDateTime(now),
      });
    });
  }

  Future<void> deleteVoiceNote(int taskId) async {
    final Database database = await _database.database;
    final List<TaskVoiceNote> notes = await listVoiceNotes(taskId);
    for (final TaskVoiceNote note in notes) {
      await _deleteVoiceFile(note.localPath);
    }
    await database.delete(
      'task_voice_notes',
      where: 'task_id = ?',
      whereArgs: <Object?>[taskId],
    );
  }

  Future<void> _deleteVoiceFile(String filePath) async {
    if (filePath.isEmpty) {
      return;
    }
    try {
      final File file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // 忽略删除失败，避免影响业务流程
    }
  }
}
