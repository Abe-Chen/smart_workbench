import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/utils/calendar_utils.dart';
import '../../../task/application/task_providers.dart';
import '../../../task/data/local_task_repository.dart';
import '../../../task/domain/task.dart';
import '../../domain/assistant_confirm_preview.dart';
import '../../domain/assistant_tool.dart';
import '_task_tool_helpers.dart';

/// 修改已存在的任务。**写入工具**，必经 confirm。
class UpdateTaskTool extends AssistantTool {
  UpdateTaskTool(this._ref);

  final Ref _ref;

  @override
  String get name => 'update_task';

  @override
  String get description =>
      '修改已存在的任务/日程/提醒。先用 query_tasks 拿 task_id，再用此工具更新字段。'
      '只填要改的字段，其余字段保留原值。调用后会弹确认卡，等用户确认才真正写入。';

  @override
  Map<String, dynamic> get parametersSchema => <String, dynamic>{
    'type': 'object',
    'properties': <String, dynamic>{
      'task_id': <String, dynamic>{
        'type': 'integer',
        'description': '任务 id，必填。从 query_tasks 的返回里取。',
      },
      'title': <String, dynamic>{'type': 'string'},
      'start_date': <String, dynamic>{
        'type': 'string',
        'description': 'YYYY-MM-DD',
      },
      'is_all_day': <String, dynamic>{'type': 'boolean'},
      'start_time_minutes': <String, dynamic>{'type': 'integer'},
      'end_time_minutes': <String, dynamic>{'type': 'integer'},
      'reminder_key': <String, dynamic>{
        'type': 'string',
        'description': 'none / day9am / dayNoon / day6pm / dayBefore9am / '
            'atStart / before5m / before10m / before30m / before1h',
      },
      'repeat_key': <String, dynamic>{
        'type': 'string',
        'description': 'none / daily / weekly / monthly',
      },
    },
    'required': <String>['task_id'],
  };

  int? _parseTaskId(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw);
    return null;
  }

  Future<Task?> _loadTask(int taskId) async {
    final LocalTaskRepository repo = _ref.read(taskRepositoryProvider);
    return repo.getTaskById(taskId);
  }

  Task _applyArgs(Task base, Map<String, dynamic> args) {
    Task next = base;
    final String? title = (args['title'] as Object?)?.toString().trim();
    if (title != null && title.isNotEmpty) {
      next = next.copyWith(title: title);
    }
    final DateTime? newDate = parseTaskDate(args['start_date']);
    if (newDate != null) {
      next = next.copyWith(startDate: normalizeDate(newDate));
    }
    final bool? isAllDay = parseBool(args['is_all_day']);
    final int? startMin = parseTaskTimeMinutes(args['start_time_minutes']);
    final int? endMin = parseTaskTimeMinutes(args['end_time_minutes']);
    if (isAllDay != null) {
      next = next.copyWith(
        isAllDay: isAllDay,
        startTimeMinutes: isAllDay ? null : (startMin ?? next.startTimeMinutes),
        endTimeMinutes: isAllDay ? null : (endMin ?? next.endTimeMinutes),
      );
    } else {
      if (startMin != null) {
        next = next.copyWith(isAllDay: false, startTimeMinutes: startMin);
      }
      if (endMin != null) {
        next = next.copyWith(isAllDay: false, endTimeMinutes: endMin);
      }
    }
    if (args.containsKey('reminder_key')) {
      next = next.copyWith(reminderKey: parseReminderKey(args['reminder_key']));
    }
    if (args.containsKey('repeat_key')) {
      next = next.copyWith(repeatKey: parseRepeatKey(args['repeat_key']));
    }
    return next.copyWith(updatedAt: DateTime.now());
  }

  @override
  Future<AssistantConfirmPreview?> buildConfirmPreview(
    Map<String, dynamic> args,
  ) async {
    final int? taskId = _parseTaskId(args['task_id']);
    if (taskId == null) {
      return const AssistantConfirmPreview(
        title: '准备修改任务（缺少 task_id）',
        rows: <ConfirmRow>[
          ConfirmRow(label: '提示', value: '没有提供 task_id，无法定位任务。'),
        ],
      );
    }
    final Task? original = await _loadTask(taskId);
    if (original == null) {
      return AssistantConfirmPreview(
        title: '任务不存在',
        rows: <ConfirmRow>[
          ConfirmRow(label: '提示', value: '找不到 id=$taskId 的任务。'),
        ],
      );
    }
    final Task updated = _applyArgs(original, args);

    final List<ConfirmRow> rows = <ConfirmRow>[];
    if (updated.title != original.title) {
      rows.add(
        ConfirmRow(
          label: '标题',
          value: '${original.title} → ${updated.title}',
          icon: '📌',
          highlighted: true,
        ),
      );
    } else {
      rows.add(
        ConfirmRow(label: '标题', value: original.title, icon: '📌'),
      );
    }

    final String oldWhen = taskWhenLabel(
      date: original.startDate,
      isAllDay: original.isAllDay,
      startTimeMinutes: original.startTimeMinutes,
      endTimeMinutes: original.endTimeMinutes,
    );
    final String newWhen = taskWhenLabel(
      date: updated.startDate,
      isAllDay: updated.isAllDay,
      startTimeMinutes: updated.startTimeMinutes,
      endTimeMinutes: updated.endTimeMinutes,
    );
    if (oldWhen != newWhen) {
      rows.add(
        ConfirmRow(
          label: '时间',
          value: '$oldWhen → $newWhen',
          icon: '🕐',
          highlighted: true,
        ),
      );
    } else {
      rows.add(ConfirmRow(label: '时间', value: oldWhen, icon: '🕐'));
    }

    if (updated.reminderKey != original.reminderKey) {
      rows.add(
        ConfirmRow(
          label: '提醒',
          value:
              '${reminderLabel(original.reminderKey)} → ${reminderLabel(updated.reminderKey)}',
          icon: '🔔',
          highlighted: true,
        ),
      );
    }
    if (updated.repeatKey != original.repeatKey) {
      rows.add(
        ConfirmRow(
          label: '重复',
          value:
              '${repeatLabel(original.repeatKey)} → ${repeatLabel(updated.repeatKey)}',
          icon: '🔁',
          highlighted: true,
        ),
      );
    }

    return AssistantConfirmPreview(title: '准备修改', rows: rows);
  }

  @override
  Future<String> call(Map<String, dynamic> args) async {
    try {
      final int? taskId = _parseTaskId(args['task_id']);
      if (taskId == null) {
        return jsonEncode(<String, Object?>{
          'ok': false,
          'reason': '缺少 task_id',
        });
      }
      final Task? original = await _loadTask(taskId);
      if (original == null) {
        return jsonEncode(<String, Object?>{
          'ok': false,
          'reason': '找不到 id=$taskId 的任务',
        });
      }
      final Task updated = _applyArgs(original, args);
      await _ref.read(taskMutationControllerProvider).updateTask(updated);
      return jsonEncode(<String, Object?>{
        'ok': true,
        'id': taskId,
        'title': updated.title,
      });
    } catch (e) {
      return jsonEncode(<String, Object?>{'ok': false, 'reason': '$e'});
    }
  }
}

final Provider<UpdateTaskTool> updateTaskToolProvider = Provider<UpdateTaskTool>(
  (Ref ref) => UpdateTaskTool(ref),
);
