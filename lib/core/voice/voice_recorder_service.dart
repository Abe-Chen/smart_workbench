import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class VoiceRecorderService {
  VoiceRecorderService();

  final AudioRecorder _recorder = AudioRecorder();
  DateTime? _startedAt;
  String? _currentPath;

  Future<bool> hasPermission() {
    return _recorder.hasPermission();
  }

  Future<bool> isRecording() {
    return _recorder.isRecording();
  }

  Future<String> startTempRecording() async {
    final Directory dir = await getTemporaryDirectory();
    final String filePath = path.join(
      dir.path,
      'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
    );
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 96000),
      path: filePath,
    );
    _startedAt = DateTime.now();
    _currentPath = filePath;
    return filePath;
  }

  Future<VoiceRecordingResult?> stopRecording() async {
    final String? finalPath = await _recorder.stop();
    if (finalPath == null) {
      _startedAt = null;
      _currentPath = null;
      return null;
    }
    final DateTime endedAt = DateTime.now();
    final int duration = _startedAt == null
        ? 0
        : endedAt.difference(_startedAt!).inMilliseconds;
    _startedAt = null;
    _currentPath = null;
    return VoiceRecordingResult(
      filePath: finalPath,
      durationMillis: duration,
    );
  }

  Future<void> cancelRecording() async {
    final String? activePath = await _recorder.stop();
    final String? toDelete = activePath ?? _currentPath;
    _startedAt = null;
    _currentPath = null;
    if (toDelete != null) {
      final File file = File(toDelete);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  Future<void> dispose() async {
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
    await _recorder.dispose();
  }

  static Future<Directory> voiceNotesDir() async {
    final Directory base = await getApplicationDocumentsDirectory();
    final Directory dir = Directory(path.join(base.path, 'voice_notes'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<String> moveToPersistent({
    required String tempPath,
    required int taskId,
  }) async {
    final Directory dir = await voiceNotesDir();
    final String target = path.join(
      dir.path,
      '${taskId}_${DateTime.now().millisecondsSinceEpoch}.m4a',
    );
    final File source = File(tempPath);
    if (!await source.exists()) {
      throw StateError('voice file missing: $tempPath');
    }
    final File moved = await source.rename(target).catchError((_) async {
      final File copy = await source.copy(target);
      await source.delete();
      return copy;
    });
    return moved.path;
  }
}

class VoiceRecordingResult {
  const VoiceRecordingResult({
    required this.filePath,
    required this.durationMillis,
  });

  final String filePath;
  final int durationMillis;
}
