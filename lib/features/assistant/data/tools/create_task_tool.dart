import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/calendar_utils.dart';
import '../../../task/application/task_providers.dart';
import '../../../task/domain/task.dart';
import '../../domain/assistant_confirm_preview.dart';
import '../../domain/assistant_tool.dart';
import '_task_tool_helpers.dart';

/// 创建任务/日程/提醒。**写入工具**，必经 confirm。
class CreateTaskTool extends AssistantTool {
  CreateTaskTool(this._ref);

  final Ref _ref;

  @override
  String get name => 'create_task';

  @override
  String get description =>
      '创建任务/日程/提醒。所有需要"加进日历""加到待办""定一个提醒"的请求都用这个工具。'
      '提醒类（"提醒我喝水"）也用这个，把 reminder_key 设成对应档位即可。'
      '调用前应先确认时间、标题已经清楚；调用后会弹确认卡，等用户点"确认"才真正写入。';

  @override
  Map<String, dynamic> get parametersSchema => <String, dynamic>{
    'type': 'object',
    'properties': <String, dynamic>{
      'title': <String, dynamic>{'type': 'string', 'description': '任务标题，必填。'},
      'start_date': <String, dynamic>{
        'type': 'string',
        'description': '开始日期 YYYY-MM-DD，必填。今天用今天的日期。',
      },
      'is_all_day': <String, dynamic>{
        'type': 'boolean',
        'description': '是否全天（缺省 true）。如果用户给了具体时间点，传 false。',
      },
      'start_time_minutes': <String, dynamic>{
        'type': 'integer',
        'description': '开始时间（当日分钟数 0-1440），仅在 is_all_day=false 时使用。',
      },
      'end_time_minutes': <String, dynamic>{
        'type': 'integer',
        'description': '结束时间（当日分钟数 0-1440），可选。',
      },
      'reminder_key': <String, dynamic>{
        'type': 'string',
        'description':
            '提醒档位。可选值：none / day9am / dayNoon / day6pm / dayBefore9am / '
            'atStart / before5m / before10m / before30m / before1h。'
            '"提醒我 X" 类语句通常用 atStart 或 before10m。',
      },
      'repeat_key': <String, dynamic>{
        'type': 'string',
        'description': '重复档位：none / daily / weekly / monthly。缺省 none。',
      },
    },
    'required': <String>['title', 'start_date'],
  };

  Task? _buildTaskFromArgs(Map<String, dynamic> args) {
    final String title = (args['title'] as Object?)?.toString().trim() ?? '';
    if (title.isEmpty) return null;
    final DateTime? startDate = parseTaskDate(args['start_date']);
    if (startDate == null) return null;

    final bool? isAllDayRaw = parseBool(args['is_all_day']);
    final int? startMin = parseTaskTimeMinutes(args['start_time_minutes']);
    final int? endMinRaw = parseTaskTimeMinutes(args['end_time_minutes']);
    // 如果用户给了 start_time_minutes，自动判断 is_all_day=false
    final bool isAllDay = isAllDayRaw ?? (startMin == null);
    final int? finalStart = isAllDay ? null : startMin;
    final int? finalEnd = isAllDay
        ? null
        : (endMinRaw ?? (finalStart != null ? finalStart + 60 : null));

    final TaskReminderKey reminderKey = parseReminderKey(args['reminder_key']);
    final TaskRepeatKey repeatKey = parseRepeatKey(args['repeat_key']);
    final DateTime now = DateTime.now();

    return Task(
      title: title,
      startDate: normalizeDate(startDate),
      isAllDay: isAllDay,
      startTimeMinutes: finalStart,
      endTimeMinutes: finalEnd,
      reminderKey: reminderKey,
      repeatKey: repeatKey,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Future<AssistantConfirmPreview?> buildConfirmPreview(
    Map<String, dynamic> args,
  ) async {
    final Task? task = _buildTaskFromArgs(args);
    if (task == null) {
      return const AssistantConfirmPreview(
        title: '信息没识别完整',
        rows: <ConfirmRow>[
          ConfirmRow(label: '提示', value: '标题或日期还不清楚，我先不直接放进日程。'),
        ],
      );
    }

    return AssistantConfirmPreview(
      title: '准备创建',
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
          highlighted: true,
        ),
        if (task.reminderKey != TaskReminderKey.none)
          ConfirmRow(
            label: '提醒',
            value: reminderLabel(task.reminderKey),
            icon: '🔔',
          ),
        if (task.repeatKey != TaskRepeatKey.none)
          ConfirmRow(
            label: '重复',
            value: repeatLabel(task.repeatKey),
            icon: '🔁',
          ),
      ],
    );
  }

  @override
  Future<String> call(Map<String, dynamic> args) async {
    try {
      final Task? task = _buildTaskFromArgs(args);
      if (task == null) {
        return jsonEncode(<String, Object?>{
          'ok': false,
          'reason': '缺少必要字段：title 或 start_date',
        });
      }
      final int id = await _ref
          .read(taskMutationControllerProvider)
          .createTask(task);
      return jsonEncode(<String, Object?>{
        'ok': true,
        'id': id,
        'title': task.title,
      });
    } catch (e) {
      return jsonEncode(<String, Object?>{'ok': false, 'reason': '$e'});
    }
  }
}

final Provider<CreateTaskTool> createTaskToolProvider =
    Provider<CreateTaskTool>((Ref ref) => CreateTaskTool(ref));
