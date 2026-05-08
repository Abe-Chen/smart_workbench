import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/utils/calendar_utils.dart';
import '../../../../core/utils/task_formatters.dart';
import '../../../task/data/local_task_repository.dart';
import '../../../task/domain/task.dart';
import '../../domain/assistant_tool.dart';
import '_task_tool_helpers.dart';

/// 查询用户本地任务/日程/提醒。**不修改任何数据**，因此不走 confirm。
class QueryTasksTool extends AssistantTool {
  QueryTasksTool(this._ref);

  final Ref _ref;

  static const int _kMaxResults = 20;
  static const int _kMaxRangeDays = 60;

  @override
  String get name => 'query_tasks';

  @override
  String get description =>
      '查询用户本地任务/日程/提醒。当用户问"我今天的任务"、"明天有什么会"、"周五安排"等需要看本地数据时调用。返回 JSON 列表，最多 20 条。';

  @override
  Map<String, dynamic> get parametersSchema => <String, dynamic>{
    'type': 'object',
    'properties': <String, dynamic>{
      'start_date': <String, dynamic>{
        'type': 'string',
        'description': '起始日期 YYYY-MM-DD。缺省 = 今天。',
      },
      'end_date': <String, dynamic>{
        'type': 'string',
        'description': '结束日期 YYYY-MM-DD。缺省 = start_date（仅查一天）。最大跨度 60 天。',
      },
      'keyword': <String, dynamic>{
        'type': 'string',
        'description': '在标题里包含的关键词（可选）。',
      },
      'include_completed': <String, dynamic>{
        'type': 'boolean',
        'description': '是否包含已完成的任务（缺省 false）。',
      },
    },
    'required': <String>[],
  };

  @override
  Future<String> call(Map<String, dynamic> args) async {
    try {
      final LocalTaskRepository repo = _ref.read(taskRepositoryProvider);
      final DateTime today = normalizeDate(DateTime.now());
      DateTime start = parseTaskDate(args['start_date']) ?? today;
      DateTime end = parseTaskDate(args['end_date']) ?? start;
      if (end.isBefore(start)) {
        final DateTime tmp = start;
        start = end;
        end = tmp;
      }
      final int days = end
          .difference(start)
          .inDays
          .clamp(0, _kMaxRangeDays);
      final String? keyword = (args['keyword'] as Object?)?.toString().trim();
      final bool includeCompleted = parseBool(args['include_completed']) ?? false;

      final List<Map<String, Object?>> results = <Map<String, Object?>>[];
      for (int i = 0; i <= days; i++) {
        if (results.length >= _kMaxResults) break;
        final DateTime date = start.add(Duration(days: i));
        final List<TaskOccurrence> occurrences = await repo
            .listOccurrencesForDate(date);
        for (final TaskOccurrence o in occurrences) {
          if (results.length >= _kMaxResults) break;
          if (!includeCompleted && o.task.status == TaskStatus.completed) {
            continue;
          }
          if (keyword != null &&
              keyword.isNotEmpty &&
              !o.task.title.contains(keyword)) {
            continue;
          }
          final Map<String, Object?> entry = <String, Object?>{
            'id': o.task.id,
            'title': o.task.title,
            'date': formatStorageDate(o.occurrenceDate),
            'time': formatTaskTimeLabel(
              isAllDay: o.task.isAllDay,
              startTimeMinutes: o.task.startTimeMinutes,
              endTimeMinutes: o.task.endTimeMinutes,
            ),
            'status': o.task.status.name,
          };
          if (o.task.reminderKey != TaskReminderKey.none) {
            entry['reminder'] = o.task.reminderKey.name;
          }
          if (o.task.repeatKey != TaskRepeatKey.none) {
            entry['repeat'] = o.task.repeatKey.name;
          }
          results.add(entry);
        }
      }

      return jsonEncode(<String, Object?>{
        'ok': true,
        'count': results.length,
        'tasks': results,
        if (results.length >= _kMaxResults) 'truncated': true,
      });
    } catch (e) {
      return jsonEncode(<String, Object?>{'ok': false, 'reason': '$e'});
    }
  }
}

final Provider<QueryTasksTool> queryTasksToolProvider = Provider<QueryTasksTool>(
  (Ref ref) => QueryTasksTool(ref),
);
