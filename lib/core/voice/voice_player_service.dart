import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

class VoicePlayerService {
  VoicePlayerService() {
    _player.onPlayerStateChanged.listen((PlayerState state) {
      _state = state;
      _stateController.add(_currentSnapshot);
    });
    _player.onDurationChanged.listen((Duration value) {
      _duration = value;
      _stateController.add(_currentSnapshot);
    });
    _player.onPositionChanged.listen((Duration value) {
      _position = value;
      _stateController.add(_currentSnapshot);
    });
    _player.onPlayerComplete.listen((_) {
      _activePath = null;
      _stateController.add(_currentSnapshot);
    });
  }

  final AudioPlayer _player = AudioPlayer();
  final StreamController<VoicePlaybackSnapshot> _stateController =
      StreamController<VoicePlaybackSnapshot>.broadcast();

  PlayerState _state = PlayerState.stopped;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  String? _activePath;

  Stream<VoicePlaybackSnapshot> get stateStream => _stateController.stream;

  VoicePlaybackSnapshot get _currentSnapshot => VoicePlaybackSnapshot(
        path: _activePath,
        state: _state,
        duration: _duration,
        position: _position,
      );

  bool isPlaying(String filePath) {
    return _state == PlayerState.playing && _activePath == filePath;
  }

  Future<void> playFile(String filePath) async {
    if (_activePath != null && _activePath != filePath) {
      await _player.stop();
    }
    _activePath = filePath;
    await _player.play(DeviceFileSource(filePath));
  }

  Future<void> stop() async {
    _activePath = null;
    await _player.stop();
  }

  Future<void> dispose() async {
    await _player.dispose();
    await _stateController.close();
  }
}

class VoicePlaybackSnapshot {
  const VoicePlaybackSnapshot({
    required this.path,
    required this.state,
    required this.duration,
    required this.position,
  });

  final String? path;
  final PlayerState state;
  final Duration duration;
  final Duration position;

  bool isActiveFor(String filePath) =>
      path == filePath && state == PlayerState.playing;
}
