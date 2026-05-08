import '../domain/assistant_confirm_preview.dart';
import 'assistant_state.dart';

/// 小治在本地执行链路里的微文案。
///
/// 这里只负责“怎么说”，不决定“做什么”。执行状态和工具调用仍由
/// [AssistantController] 控制，避免话术优化影响写入链路。
class AssistantCopywriter {
  const AssistantCopywriter();

  String missingWriteDraft(AssistantPendingWriteDraft draft) {
    final bool hasTitle = draft.title != null && draft.title!.trim().isNotEmpty;
    final bool hasDate = draft.startDate != null;
    final bool hasTime = draft.startTimeMinutes != null;
    final String title = draft.title?.trim() ?? '';
    final List<String> missing = <String>[
      if (!hasTitle) _titleLabel(draft.kind),
      if (!hasDate) '日期',
      if (!hasTime) '时间',
    ];

    if (!hasTitle && !hasDate && !hasTime) {
      return draft.kind == AssistantWriteDraftKind.reminder
          ? '可以。要提醒你什么，什么时候提醒？'
          : '可以。这个日程是什么，安排在什么时候？';
    }
    if (hasTitle && !hasDate && !hasTime) {
      return draft.kind == AssistantWriteDraftKind.reminder
          ? '「$title」我记下了。什么时候提醒？'
          : '「$title」我记下了。安排在什么时候？';
    }
    if (hasTitle && hasDate && !hasTime) {
      return draft.kind == AssistantWriteDraftKind.reminder
          ? '「$title」我记下了。几点提醒你？'
          : '「$title」我记下了。几点开始？';
    }
    if (hasTitle && !hasDate && hasTime) {
      final String time = _timeLabel(draft.startTimeMinutes!);
      return draft.kind == AssistantWriteDraftKind.reminder
          ? '「$title」和$time我记下了。是哪一天提醒？'
          : '「$title」和$time我记下了。是哪一天？';
    }
    if (!hasTitle && hasDate && hasTime) {
      final String when = _dateTimeLabel(
        draft.startDate!,
        draft.startTimeMinutes!,
      );
      return draft.kind == AssistantWriteDraftKind.reminder
          ? '$when我记下了。要提醒你什么？'
          : '$when我记下了。这条日程叫什么？';
    }
    if (!hasTitle && !hasDate && hasTime) {
      final String time = _timeLabel(draft.startTimeMinutes!);
      return draft.kind == AssistantWriteDraftKind.reminder
          ? '$time我记下了。哪一天提醒你什么？'
          : '$time我记下了。是哪一天、什么事？';
    }
    if (!hasTitle && hasDate && !hasTime) {
      final String date = _dateLabel(draft.startDate!);
      return draft.kind == AssistantWriteDraftKind.reminder
          ? '$date我记下了。要提醒你什么，几点提醒？'
          : '$date我记下了。这条日程是什么，几点开始？';
    }
    return '还差${missing.join('、')}，你补充一下就行。';
  }

  String readyToConfirm(AssistantPendingWriteDraft draft) {
    return draft.kind == AssistantWriteDraftKind.reminder
        ? '我整理好了，你看下没问题我就设置提醒。'
        : '我整理好了，你看下没问题我就创建。';
  }

  String pendingConfirmUnknown(AssistantPendingConfirm pending) {
    final String? title = _rowValue(pending.preview, '标题');
    final String subject = title == null || title.isEmpty ? '这项操作' : '「$title」';
    switch (pending.toolCall.name) {
      case 'create_task':
        return '我还在等你确认是否创建$subject。你可以说“确认”或“取消”，也可以点卡片上的按钮。';
      case 'update_task':
        return '我还在等你确认是否修改$subject。你可以说“确认”或“取消”，也可以点卡片上的按钮。';
      case 'delete_task':
        return '我还在等你确认是否删除$subject。你可以说“确认”或“取消”，也可以点卡片上的按钮。';
      default:
        return '我还在等你确认刚才那项操作。你可以说“确认”或“取消”，也可以点卡片上的按钮。';
    }
  }

  String createCancelled(AssistantWriteDraftKind kind) {
    return kind == AssistantWriteDraftKind.reminder
        ? '好，这次先不设置提醒。'
        : '好，这次先不创建。';
  }

  String confirmCancelled(AssistantPendingConfirm pending) {
    switch (pending.toolCall.name) {
      case 'create_task':
        return createCancelled(_kindFromConfirm(pending));
      case 'update_task':
        return '好，这次先不修改。';
      case 'delete_task':
        return '好，这次先不删除。';
      default:
        return '好，这次先不执行。';
    }
  }

  String cannotCreate(AssistantWriteDraftKind kind) {
    return kind == AssistantWriteDraftKind.reminder
        ? '我现在还不能直接设置提醒，但可以先帮你把内容整理出来。'
        : '我现在还不能直接创建日程，但可以先帮你把内容整理出来。';
  }

  String unclearCreate(AssistantWriteDraftKind kind) {
    return kind == AssistantWriteDraftKind.reminder
        ? '这次提醒内容还没识别清楚。你可以把提醒内容和时间一起说一遍。'
        : '这次日程内容还没识别清楚。你可以把标题和时间一起说一遍。';
  }

  String confirmedCreateResult({
    required AssistantPendingConfirm pending,
    required Map<String, dynamic>? result,
  }) {
    return confirmedWriteResult(pending: pending, result: result);
  }

  String confirmedWriteResult({
    required AssistantPendingConfirm pending,
    required Map<String, dynamic>? result,
  }) {
    if (result?['ok'] == true) {
      switch (pending.toolCall.name) {
        case 'create_task':
          return _createdText(pending, result);
        case 'update_task':
          return _updatedText(pending, result);
        case 'delete_task':
          return _deletedText(pending);
      }
    }
    final String reason = (result?['reason'] as String?) ?? '工具没有返回成功结果';
    switch (pending.toolCall.name) {
      case 'create_task':
        return _kindFromConfirm(pending) == AssistantWriteDraftKind.reminder
            ? '这次没设置成功：$reason。你可以稍后再试，或者换个说法重新设置。'
            : '这次没创建成功：$reason。你可以稍后再试，或者换个说法重新创建。';
      case 'update_task':
        return '这次没修改成功：$reason。你可以稍后再试，或者重新说一遍要怎么改。';
      case 'delete_task':
        return '这次没删除成功：$reason。你可以稍后再试。';
      default:
        return '这次没执行成功：$reason。你可以稍后再试。';
    }
  }

  String completedTaskResult(Map<String, dynamic>? result) {
    if (result?['ok'] == true) {
      final String title = (result?['title'] as String?) ?? '这项任务';
      return '已把「$title」标记完成。刚才这一步可以撤销。';
    }
    final String reason = (result?['reason'] as String?) ?? '工具没有返回成功结果';
    return '这次没标记成功：$reason。你可以稍后再试。';
  }

  String queryTasksResult(Map<String, dynamic>? result) {
    if (result?['ok'] != true) {
      final String reason = (result?['reason'] as String?) ?? '没有拿到查询结果';
      return '这次没查到本地安排：$reason。你可以稍后再试。';
    }
    final List<Map<String, dynamic>> tasks = _readTaskList(result?['tasks']);
    if (tasks.isEmpty) {
      return '我没查到符合条件的任务或日程。';
    }
    final StringBuffer buffer = StringBuffer();
    final String dayLabel = _dayLabelForTasks(tasks);
    buffer.write(
      dayLabel.isEmpty ? '这些是你的安排：' : '$dayLabel有 ${tasks.length} 个安排：',
    );
    for (final Map<String, dynamic> task in tasks) {
      final String title =
          (task['title'] as Object?)?.toString().trim() ?? '未命名安排';
      final String time = (task['time'] as Object?)?.toString().trim() ?? '';
      final String date = (task['date'] as Object?)?.toString().trim() ?? '';
      final String timePart = time.isEmpty || time == '无时间' ? '' : '$time ';
      final String datePart = dayLabel.isEmpty && date.isNotEmpty
          ? '${_shortDateLabel(date)} '
          : '';
      buffer.write('\n- $datePart$timePart$title');
    }
    if (result?['truncated'] == true) {
      buffer.write('\n我先显示前 ${tasks.length} 个。');
    }
    return buffer.toString();
  }

  String _createdText(
    AssistantPendingConfirm pending,
    Map<String, dynamic>? result,
  ) {
    final AssistantWriteDraftKind kind = _kindFromConfirm(pending);
    final String title =
        (result?['title'] as String?) ??
        _rowValue(pending.preview, '标题') ??
        _typeLabel(kind);
    final String? when = _rowValue(pending.preview, '时间');
    if (kind == AssistantWriteDraftKind.reminder) {
      return when == null || when.isEmpty
          ? '已设置，会提醒你「$title」。'
          : '已设置，$when 会提醒你「$title」。';
    }
    return when == null || when.isEmpty
        ? '已创建，「$title」已经放到日程里。'
        : '已创建，$when 的「$title」已经放到日程里。';
  }

  String _updatedText(
    AssistantPendingConfirm pending,
    Map<String, dynamic>? result,
  ) {
    final String title =
        (result?['title'] as String?) ??
        _cleanChangedValue(_rowValue(pending.preview, '标题')) ??
        '这项安排';
    return '已修改「$title」。';
  }

  String _deletedText(AssistantPendingConfirm pending) {
    final String title = _rowValue(pending.preview, '标题') ?? '这项安排';
    return '已删除「$title」。';
  }

  String? _cleanChangedValue(String? value) {
    if (value == null || value.isEmpty) return null;
    if (!value.contains('→')) return value;
    final List<String> parts = value.split('→');
    return parts.last.trim().isEmpty ? value : parts.last.trim();
  }

  List<Map<String, dynamic>> _readTaskList(Object? raw) {
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map(
          (Map item) => item.map<String, dynamic>(
            (dynamic key, dynamic value) =>
                MapEntry<String, dynamic>(key.toString(), value),
          ),
        )
        .toList();
  }

  String _dayLabelForTasks(List<Map<String, dynamic>> tasks) {
    final Set<String> dates = tasks
        .map((Map<String, dynamic> task) {
          return (task['date'] as Object?)?.toString().trim() ?? '';
        })
        .where((String date) => date.isNotEmpty)
        .toSet();
    if (dates.length != 1) {
      return '';
    }
    return _shortDateLabel(dates.single);
  }

  String _shortDateLabel(String date) {
    final DateTime? parsed = DateTime.tryParse(date.replaceAll('/', '-'));
    if (parsed == null) return date;
    return _dateLabel(parsed);
  }

  AssistantWriteDraftKind _kindFromConfirm(AssistantPendingConfirm pending) {
    final Map<String, dynamic> args = pending.toolCall.argumentsAsMap();
    final String reminder = (args['reminder_key'] as Object?)?.toString() ?? '';
    return reminder.isNotEmpty && reminder != 'none'
        ? AssistantWriteDraftKind.reminder
        : AssistantWriteDraftKind.schedule;
  }

  String? _rowValue(AssistantConfirmPreview preview, String label) {
    for (final ConfirmRow row in preview.rows) {
      if (row.label == label) {
        return row.value;
      }
    }
    return null;
  }

  String _typeLabel(AssistantWriteDraftKind kind) {
    return kind == AssistantWriteDraftKind.reminder ? '提醒' : '日程';
  }

  String _titleLabel(AssistantWriteDraftKind kind) {
    return kind == AssistantWriteDraftKind.reminder ? '提醒内容' : '标题';
  }

  String _dateTimeLabel(DateTime date, int minutes) {
    return '${_dateLabel(date)}${_timeLabel(minutes)}';
  }

  String _dateLabel(DateTime date) {
    final DateTime today = _dateOnly(DateTime.now());
    final DateTime target = _dateOnly(date);
    final int diff = target.difference(today).inDays;
    if (diff == 0) return '今天';
    if (diff == 1) return '明天';
    if (diff == 2) return '后天';
    return '${target.month} 月 ${target.day} 日';
  }

  DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  String _timeLabel(int minutes) {
    final int hour = minutes ~/ 60;
    final int minute = minutes % 60;
    final String period;
    final int displayHour;
    if (hour == 0) {
      period = '凌晨';
      displayHour = 12;
    } else if (hour < 6) {
      period = '凌晨';
      displayHour = hour;
    } else if (hour < 12) {
      period = '上午';
      displayHour = hour;
    } else if (hour == 12) {
      period = '中午';
      displayHour = 12;
    } else if (hour < 18) {
      period = '下午';
      displayHour = hour - 12;
    } else {
      period = '晚上';
      displayHour = hour - 12;
    }
    if (minute == 0) return '$period$displayHour 点';
    if (minute == 30) return '$period$displayHour 点半';
    return '$period$displayHour 点 $minute 分';
  }
}
