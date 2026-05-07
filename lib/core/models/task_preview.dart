import '../../features/task/domain/task.dart';
import '../utils/task_formatters.dart';

/// 持久化层关心的状态：任务是否已勾完。
/// "是否逾期" 是 (now > endTime && state==active) 的派生，由 [TaskPreview.isOverdueAt]
/// 在 UI 层根据当前时间实时算，不在数据层固化。
enum TaskVisualState { active, completed }

class TaskPreview {
  const TaskPreview({
    required this.id,
    required this.title,
    required this.timeLabel,
    required this.state,
    required this.occurrenceDate,
    required this.startTimeMinutes,
    required this.endTimeMinutes,
    this.delayDays = 0,
    this.hasVoiceNote = false,
    this.voiceFilePath,
    this.voiceDurationMillis = 0,
    this.isAllDay = false,
  });

  factory TaskPreview.fromOccurrence(
    TaskOccurrence occurrence, {
    bool hasVoiceNote = false,
    String? voiceFilePath,
    int voiceDurationMillis = 0,
  }) {
    final Task task = occurrence.task;
    final DateTime occurrenceDate = DateTime(
      occurrence.occurrenceDate.year,
      occurrence.occurrenceDate.month,
      occurrence.occurrenceDate.day,
    );
    final DateTime sourceDate = DateTime(
      occurrence.sourceDate.year,
      occurrence.sourceDate.month,
      occurrence.sourceDate.day,
    );
    final int delayDays = occurrenceDate.isAfter(sourceDate)
        ? occurrenceDate.difference(sourceDate).inDays
        : 0;

    final TaskVisualState state = task.status == TaskStatus.completed
        ? TaskVisualState.completed
        : TaskVisualState.active;

    return TaskPreview(
      id: task.id ?? 0,
      title: task.title,
      timeLabel: formatTaskTimeLabel(
        isAllDay: task.isAllDay,
        startTimeMinutes: task.startTimeMinutes,
        endTimeMinutes: task.endTimeMinutes,
      ),
      state: state,
      occurrenceDate: occurrenceDate,
      startTimeMinutes: task.startTimeMinutes,
      endTimeMinutes: task.endTimeMinutes,
      delayDays: delayDays,
      hasVoiceNote: hasVoiceNote,
      voiceFilePath: voiceFilePath,
      voiceDurationMillis: voiceDurationMillis,
      isAllDay: task.isAllDay,
    );
  }

  final int id;
  final String title;
  final String timeLabel;
  final TaskVisualState state;
  final DateTime occurrenceDate;
  final int? startTimeMinutes;
  final int? endTimeMinutes;
  final int delayDays;
  final bool hasVoiceNote;
  final String? voiceFilePath;
  final int voiceDurationMillis;
  final bool isAllDay;

  /// 任务是否在 [now] 时刻被视为逾期（未完成 + 截止时间已过）。
  bool isOverdueAt(DateTime now) {
    if (state == TaskVisualState.completed) {
      return false;
    }
    final DateTime today = DateTime(now.year, now.month, now.day);
    if (occurrenceDate.isBefore(today)) {
      return true;
    }
    if (occurrenceDate.isAfter(today)) {
      return false;
    }
    if (isAllDay) {
      return false;
    }
    final int boundaryMinutes =
        endTimeMinutes ?? startTimeMinutes ?? 0;
    final int nowMinutes = now.hour * 60 + now.minute;
    return boundaryMinutes < nowMinutes;
  }
}
