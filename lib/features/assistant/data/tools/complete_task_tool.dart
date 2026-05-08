import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/utils/calendar_utils.dart';
import '../../../task/application/task_providers.dart';
import '../../../task/data/local_task_repository.dart';
import '../../../task/domain/task.dart';
import '../../domain/assistant_tool.dart';
import '_task_tool_helpers.dart';

/// 标记任务完成。**轻量写入**，不走 confirm（用户可通过 SnackBar 撤销）。
class CompleteTaskTool extends AssistantTool {
  CompleteTaskTool(this._ref);

  final Ref _ref;

  @override
  String get name => 'complete_task';

  @override
  String get description =>
      '标记任务完成。先用 query_tasks 拿 task_id，再调用此工具。'
      '此操作直接生效（不弹确认卡），完成后界面会有撤销提示。';

  @override
  Map<String, dynamic> get parametersSchema => <String, dynamic>{
    'type': 'object',
    'properties': <String, dynamic>{
      'task_id': <String, dynamic>{
        'type': 'integer',
        'description': '任务 id，必填。',
      },
      'occurrence_date': <String, dynamic>{
        'type': 'string',
        'description': 'YYYY-MM-DD。重复任务必填，标记的是哪一次发生；非重复任务可省略。',
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

  /// 不实现 buildConfirmPreview，沿用默认 null → 直接执行。

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
      final LocalTaskRepository repo = _ref.read(taskRepositoryProvider);
      final Task? task = await repo.getTaskById(taskId);
      if (task == null) {
        return jsonEncode(<String, Object?>{
          'ok': false,
          'reason': '找不到 id=$taskId 的任务',
        });
      }
      final DateTime occurrence =
          parseTaskDate(args['occurrence_date']) ?? normalizeDate(DateTime.now());
      await _ref.read(taskMutationControllerProvider).completeTaskById(
        taskId: taskId,
        occurrenceDate: occurrence,
      );
      return jsonEncode(<String, Object?>{
        'ok': true,
        'id': taskId,
        'title': task.title,
        'occurrence_date': args['occurrence_date'] ?? occurrence.toIso8601String(),
      });
    } catch (e) {
      return jsonEncode(<String, Object?>{'ok': false, 'reason': '$e'});
    }
  }
}

final Provider<CompleteTaskTool> completeTaskToolProvider =
    Provider<CompleteTaskTool>((Ref ref) => CompleteTaskTool(ref));
