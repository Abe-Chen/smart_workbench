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
        ? '我理解是这样。确认后我就帮你设置提醒。'
        : '我理解是这样。确认后我就放到日程里。';
  }

  String pendingConfirmUnknown(AssistantPendingConfirm pending) {
    final String? title = _rowValue(pending.preview, '标题');
    final String subject = title == null || title.isEmpty ? '这项操作' : '「$title」';
    switch (pending.toolCall.name) {
      case 'create_task':
        return '$subject还没放进日程。要继续的话说“确认”，不创建就说“取消”。';
      case 'update_task':
        return '$subject还没改。要继续的话说“确认”，不改就说“取消”。';
      case 'delete_task':
        return '$subject还没删。确认删除就说“确认”，不删就说“取消”。';
      default:
        return '这一步还没确认。要继续的话说“确认”，不做就说“取消”。';
    }
  }

  String readyToUpdateTime({
    required String title,
    required DateTime date,
    required int? currentStartMinutes,
    required String currentTimeLabel,
    required int newStartMinutes,
  }) {
    final String currentWhen = _schedulePointLabel(
      date: date,
      startMinutes: currentStartMinutes,
      fallbackTimeLabel: currentTimeLabel,
    );
    return '我看到$currentWhen是「$title」，要改到${_timeLabel(newStartMinutes)}吗？';
  }

  String readyToDelete({
    required String title,
    required DateTime date,
    required int? currentStartMinutes,
    required String currentTimeLabel,
  }) {
    final String currentWhen = _schedulePointLabel(
      date: date,
      startMinutes: currentStartMinutes,
      fallbackTimeLabel: currentTimeLabel,
    );
    return '我看到$currentWhen是「$title」，确认要删掉吗？';
  }

  String readyToChangeReminder({
    required String title,
    required String reminderLabel,
    required bool removeReminder,
  }) {
    return removeReminder
        ? '要把「$title」改成不提醒吗？'
        : '要给「$title」加上$reminderLabel吗？';
  }

  String choiceReplyHint() {
    return '我刚才列了几条，你可以说“第一条”或“第二条”。';
  }

  String choiceOutOfRange(int count) {
    return '刚才只有 $count 条。你可以重新说“第一条”或“第二条”。';
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
        return '好，这次先不做。';
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
        return '这次没处理成功：$reason。你可以稍后再试。';
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
      dayLabel.isEmpty ? '这些是你的安排：' : '你$dayLabel有 ${tasks.length} 个安排：',
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
          ? '好的，提醒设置好了。'
          : '好的，提醒设置好了。$when会提醒你「$title」。';
    }
    return when == null || when.isEmpty
        ? '好的，已经放到日程里了。'
        : '好的，已经放到日程里了。$when「$title」。';
  }

  String _updatedText(
    AssistantPendingConfirm pending,
    Map<String, dynamic>? result,
  ) {
    final String? newWhen = _cleanChangedValue(
      _rowValue(pending.preview, '时间'),
    );
    if (newWhen != null &&
        newWhen.isNotEmpty &&
        !_looksTechnicalValue(newWhen)) {
      return '好的，改好了。现在是$newWhen。';
    }
    return '好的，改好了。';
  }

  String _deletedText(AssistantPendingConfirm pending) {
    return '好的，删掉了。';
  }

  String? _cleanChangedValue(String? value) {
    if (value == null || value.isEmpty) return null;
    if (!value.contains('→')) return value;
    final List<String> parts = value.split('→');
    return parts.last.trim().isEmpty ? value : parts.last.trim();
  }

  bool _looksTechnicalValue(String value) {
    return RegExp(r'^\d+$').hasMatch(value.trim());
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

  String _schedulePointLabel({
    required DateTime date,
    required int? startMinutes,
    required String fallbackTimeLabel,
  }) {
    if (startMinutes != null) {
      return _dateTimeLabel(date, startMinutes);
    }
    final String cleanFallback = fallbackTimeLabel.trim();
    if (cleanFallback.isNotEmpty && cleanFallback != '无时间') {
      return '${_dateLabel(date)} $cleanFallback';
    }
    return _dateLabel(date);
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
    if (minute == 0) return '$period $displayHour 点';
    if (minute == 30) return '$period $displayHour 点半';
    return '$period $displayHour 点 $minute 分';
  }
}
