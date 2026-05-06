import '../../../core/utils/task_formatters.dart';

class TaskVoiceNote {
  const TaskVoiceNote({
    this.id,
    required this.taskId,
    required this.localPath,
    required this.durationMillis,
    required this.createdAt,
  });

  factory TaskVoiceNote.fromMap(Map<String, Object?> map) {
    return TaskVoiceNote(
      id: map['id'] as int?,
      taskId: map['task_id'] as int? ?? 0,
      localPath: map['local_path'] as String? ?? '',
      durationMillis: map['duration_millis'] as int? ?? 0,
      createdAt:
          parseStorageDateTime(map['created_at'] as String?) ?? DateTime.now(),
    );
  }

  final int? id;
  final int taskId;
  final String localPath;
  final int durationMillis;
  final DateTime createdAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'task_id': taskId,
      'local_path': localPath,
      'duration_millis': durationMillis,
      'created_at': formatStorageDateTime(createdAt),
    };
  }
}
