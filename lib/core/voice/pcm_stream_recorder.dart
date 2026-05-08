import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

const int _kSampleRate = 16000;
const int _kFrameBytes = 1280; // 16kHz * 16bit * mono * 40ms

/// 录 16kHz 16bit mono raw PCM，按 40ms（1280 字节）分帧推流，给讯飞 IAT 用。
class PcmStreamRecorder {
  PcmStreamRecorder();

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _rawSub;
  StreamController<Uint8List>? _frameCtrl;
  final BytesBuilder _buffer = BytesBuilder();

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
  }

  Future<void> dispose() async {
    await stop();
    await _recorder.dispose();
  }

  void _onRawChunk(Uint8List chunk) {
    _buffer.add(chunk);
    while (_buffer.length >= _kFrameBytes) {
      final Uint8List all = _buffer.takeBytes();
      final Uint8List frame = Uint8List.sublistView(all, 0, _kFrameBytes);
      _frameCtrl?.add(Uint8List.fromList(frame));
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
}

final Provider<PcmStreamRecorder Function()>
pcmStreamRecorderFactoryProvider = Provider<PcmStreamRecorder Function()>(
  (Ref ref) => () => PcmStreamRecorder(),
);
