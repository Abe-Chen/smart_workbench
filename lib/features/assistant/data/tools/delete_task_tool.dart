import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../../task/application/task_providers.dart';
import '../../../task/data/local_task_repository.dart';
import '../../../task/domain/task.dart';
import '../../domain/assistant_confirm_preview.dart';
import '../../domain/assistant_tool.dart';
import '_task_tool_helpers.dart';

/// 软删除任务。**写入工具**，必经 confirm（warning 严重度）。
class DeleteTaskTool extends AssistantTool {
  DeleteTaskTool(this._ref);

  final Ref _ref;

  @override
  String get name => 'delete_task';

  @override
  String get description =>
      '删除任务/日程/提醒。先用 query_tasks 拿 task_id，再用此工具删除。'
      '调用后会弹红色确认卡，等用户确认才真正删除（软删除，可后续恢复）。';

  @override
  Map<String, dynamic> get parametersSchema => <String, dynamic>{
    'type': 'object',
    'properties': <String, dynamic>{
      'task_id': <String, dynamic>{
        'type': 'integer',
        'description': '任务 id，必填。',
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

  @override
  Future<AssistantConfirmPreview?> buildConfirmPreview(
    Map<String, dynamic> args,
  ) async {
    final int? taskId = _parseTaskId(args['task_id']);
    if (taskId == null) {
      return const AssistantConfirmPreview(
        title: '准备删除任务（缺少 task_id）',
        severity: ConfirmSeverity.warning,
        rows: <ConfirmRow>[
          ConfirmRow(label: '提示', value: '没有提供 task_id，无法定位任务。'),
        ],
      );
    }
    final LocalTaskRepository repo = _ref.read(taskRepositoryProvider);
    final Task? task = await repo.getTaskById(taskId);
    if (task == null) {
      return AssistantConfirmPreview(
        title: '任务不存在',
        severity: ConfirmSeverity.warning,
        rows: <ConfirmRow>[
          ConfirmRow(label: '提示', value: '找不到 id=$taskId 的任务。'),
        ],
      );
    }

    return AssistantConfirmPreview(
      title: '准备删除',
      subtitle: '删除后可在"已完成/已删除"列表中找回',
      severity: ConfirmSeverity.warning,
      rows: <ConfirmRow>[
        ConfirmRow(label: '标题', value: task.title, icon: '📌'),
        ConfirmRow(
          label: '时间',
          value: taskWhenLabel(
            date: task.startDate,
            isAllDay: task.isAllDay,
            startTimeMinutes: task.startTimeMinutes,
            endTimeMinutes: task.endTimeMinutes,
          ),
          icon: '🕐',
        ),
      ],
    );
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
      await _ref
          .read(taskMutationControllerProvider)
          .softDeleteTaskById(taskId);
      return jsonEncode(<String, Object?>{'ok': true, 'id': taskId});
    } catch (e) {
      return jsonEncode(<String, Object?>{'ok': false, 'reason': '$e'});
    }
  }
}

final Provider<DeleteTaskTool> deleteTaskToolProvider = Provider<DeleteTaskTool>(
  (Ref ref) => DeleteTaskTool(ref),
);
