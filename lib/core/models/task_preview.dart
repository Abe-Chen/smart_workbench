import '../../features/task/domain/task.dart';
import '../utils/task_formatters.dart';

enum TaskVisualState { active, completed, overdue }

class TaskPreview {
  const TaskPreview({
    required this.id,
    required this.title,
    required this.timeLabel,
    required this.state,
    required this.occurrenceDate,
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
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
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

    TaskVisualState state = TaskVisualState.active;
    if (task.status == TaskStatus.completed) {
      state = TaskVisualState.completed;
    } else if (occurrenceDate.isBefore(today) ||
        (occurrenceDate == today &&
            !task.isAllDay &&
            (task.endTimeMinutes ?? task.startTimeMinutes ?? 0) <
                (now.hour * 60 + now.minute))) {
      state = TaskVisualState.overdue;
    }

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
  final int delayDays;
  final bool hasVoiceNote;
  final String? voiceFilePath;
  final int voiceDurationMillis;
  final bool isAllDay;
}
