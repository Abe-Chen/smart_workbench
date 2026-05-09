import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

const int _kSampleRate = 16000;
const int _kFrameBytes = 1280; // 16kHz * 16bit * mono * 40ms

/// 录 16kHz 16bit mono raw PCM，按 40ms（1280 字节）分帧推流，给讯飞 IAT 用。
///
/// 同时计算每帧 RMS 能量并通过 [audioLevel] 暴露 0.0-1.0 归一化值，
/// 给 controller 做本地端点检测、给 UI 做麦克风脉动动画。
class PcmStreamRecorder {
  PcmStreamRecorder();

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _rawSub;
  StreamController<Uint8List>? _frameCtrl;
  final BytesBuilder _buffer = BytesBuilder();
  final ValueNotifier<double> _audioLevel = ValueNotifier<double>(0.0);

  /// 每完整帧（40ms）更新一次的 RMS 归一化能量值，0.0-1.0。
  /// stop/dispose 时归零。
  ValueListenable<double> get audioLevel => _audioLevel;

  Future<bool> hasPermission() => _recorder.hasPermission();

  /// 启动录音，返回每 40ms 一帧的 PCM stream。
  Future<Stream<Uint8List>> start() async {
    await stop();
    final Stream<Uint8List> raw = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _kSampleRate,
        numChannels: 1,
        bitRate: _kSampleRate * 16,
      ),
    );
    _frameCtrl = StreamController<Uint8List>.broadcast();
    _rawSub = raw.listen(
      _onRawChunk,
      onError: (Object err, StackTrace _) {
        _frameCtrl?.addError(err);
      },
      onDone: _flushBuffer,
    );
    return _frameCtrl!.stream;
  }

  Future<void> stop() async {
    await _rawSub?.cancel();
    _rawSub = null;
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
    _flushBuffer();
    await _frameCtrl?.close();
    _frameCtrl = null;
    _buffer.clear();
    _audioLevel.value = 0.0;
  }

  Future<void> dispose() async {
    await stop();
    await _recorder.dispose();
    _audioLevel.dispose();
  }

  void _onRawChunk(Uint8List chunk) {
    _buffer.add(chunk);
    while (_buffer.length >= _kFrameBytes) {
      final Uint8List all = _buffer.takeBytes();
      final Uint8List frame = Uint8List.sublistView(all, 0, _kFrameBytes);
      _frameCtrl?.add(Uint8List.fromList(frame));
      _audioLevel.value = _computeRms(frame);
      if (all.length > _kFrameBytes) {
        _buffer.add(Uint8List.sublistView(all, _kFrameBytes));
      }
    }
  }

  void _flushBuffer() {
    if (_buffer.length > 0 && _frameCtrl != null && !_frameCtrl!.isClosed) {
      _frameCtrl!.add(_buffer.takeBytes());
    }
  }

  /// PCM16 little-endian → 归一化 RMS（0.0-1.0）。
  double _computeRms(Uint8List frame) {
    final ByteData view = ByteData.sublistView(frame);
    final int sampleCount = frame.lengthInBytes ~/ 2;
    if (sampleCount == 0) return 0.0;
    double sumSquare = 0.0;
    for (int i = 0; i < sampleCount; i++) {
      final int sample = view.getInt16(i * 2, Endian.little);
      final double normalized = sample / 32768.0;
      sumSquare += normalized * normalized;
    }
    final double rms = math.sqrt(sumSquare / sampleCount);
    return rms.clamp(0.0, 1.0);
  }
}

final Provider<PcmStreamRecorder Function()>
pcmStreamRecorderFactoryProvider = Provider<PcmStreamRecorder Function()>(
  (Ref ref) => () => PcmStreamRecorder(),
);
