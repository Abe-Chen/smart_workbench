import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/config/env_config.dart';
import '../../../core/xunfei/xunfei_auth.dart';

const String _kTtsWssUrl = 'wss://tts-api.xfyun.cn/v2/tts';

class XunfeiTtsException implements Exception {
  XunfeiTtsException(this.message);
  final String message;
  @override
  String toString() => 'XunfeiTtsException: $message';
}

class XunfeiTtsClient {
  XunfeiTtsClient({required EnvConfig env}) : _env = env {
    _playerCompleteSub = _player.onPlayerComplete.listen((_) {
      final _TtsSession? session = _session;
      if (session == null || session.playbackDone.isCompleted) {
        return;
      }
      session.playbackDone.complete();
    });
  }

  final EnvConfig _env;
  final AudioPlayer _player = AudioPlayer();
  _TtsSession? _session;
  StreamSubscription<void>? _playerCompleteSub;

  /// 合成 + 播放。返回 Future 在播放真正开始时 resolve（不等播完）。
  /// 多次调用会先停掉前一次。
  ///
  /// [xunfeiSpeed] 透传到讯飞 `business.speed`（0-100，默认 50）。调用方负责
  /// 把"语义化倍率"换算成讯飞数值，client 层不做换算避免耦合产品配置。
  Future<void> speak(
    String text, {
    required String voice,
    int xunfeiSpeed = 50,
  }) => _speakOnce(text, voice, xunfeiSpeed: xunfeiSpeed);

  Future<void> speakAndWaitComplete(
    String text, {
    required String voice,
    int xunfeiSpeed = 50,
  }) => _speakOnce(
    text,
    voice,
    waitUntilPlaybackComplete: true,
    xunfeiSpeed: xunfeiSpeed,
  );

  Future<void> _speakOnce(
    String text,
    String voice, {
    bool waitUntilPlaybackComplete = false,
    int xunfeiSpeed = 50,
  }) async {
    if (text.trim().isEmpty) return;
    if (!_env.hasXunfeiCredentials) {
      throw XunfeiTtsException('讯飞凭据未配置');
    }
    await stop();

    final XunfeiAuth auth = XunfeiAuth(
      apiKey: _env.xfApiKey,
      apiSecret: _env.xfApiSecret,
    );
    final String url = auth.signedUrl(_kTtsWssUrl);
    final WebSocketChannel ws = IOWebSocketChannel.connect(Uri.parse(url));
    final _TtsSession session = _TtsSession(ws);
    _session = session;

    session.subscription = ws.stream.listen(
      (dynamic raw) => _handleMessage(session, raw, voice: voice),
      onError: (Object err, StackTrace _) {
        _completeSessionError(session, 'WS 异常：$err');
      },
      onDone: () {
        if (!session.receivedFinalFrame) {
          _completeSessionError(session, 'WS 提前关闭，未收到完整音频');
        }
      },
    );

    final int clampedSpeed = xunfeiSpeed.clamp(0, 100);
    final Map<String, dynamic> frame = <String, dynamic>{
      'common': <String, dynamic>{'app_id': _env.xfAppId},
      'business': <String, dynamic>{
        'aue': 'lame',
        'sfl': 1,
        'auf': 'audio/L16;rate=16000',
        'vcn': voice,
        'tte': 'UTF8',
        'speed': clampedSpeed,
        'volume': 60,
        'pitch': 50,
      },
      'data': <String, dynamic>{
        'status': 2,
        'text': base64.encode(utf8.encode(text)),
      },
    };
    ws.sink.add(jsonEncode(frame));

    final Uint8List audioBytes = await session.done.future;
    if (_session != session) {
      return;
    }
    final File audioFile = await _writeAudioFile(audioBytes);
    if (_session != session) {
      return;
    }
    await _player.play(DeviceFileSource(audioFile.path));
    if (waitUntilPlaybackComplete && _session == session) {
      await session.playbackDone.future;
    }
  }

  Future<void> stop() async {
    final _TtsSession? session = _session;
    _session = null;
    if (session != null) {
      await session.subscription?.cancel();
      await session.ws.sink.close();
      if (!session.done.isCompleted) {
        session.done.completeError(XunfeiTtsException('被中断'));
      }
      if (!session.playbackDone.isCompleted) {
        session.playbackDone.completeError(XunfeiTtsException('被中断'));
      }
    }
    await _player.stop();
  }

  Future<void> dispose() async {
    await stop();
    await _playerCompleteSub?.cancel();
    await _player.dispose();
  }

  Future<void> _handleMessage(
    _TtsSession session,
    dynamic raw, {
    required String voice,
  }) async {
    try {
      final Map<String, dynamic> msg =
          jsonDecode(raw as String) as Map<String, dynamic>;
      final int code = msg['code'] as int? ?? 0;
      if (code != 0) {
        final String message = _readErrorMessage(
          code: code,
          voice: voice,
          serverMessage: msg['message']?.toString() ?? '',
        );
        _completeSessionError(session, message);
        return;
      }
      final Map<String, dynamic>? data = msg['data'] as Map<String, dynamic>?;
      if (data == null) return;
      final String? audioB64 = data['audio'] as String?;
      if (audioB64 != null && audioB64.isNotEmpty) {
        final Uint8List bytes = base64.decode(audioB64);
        session.audioBuf.add(bytes);
      }
      final int status = data['status'] as int? ?? 0;
      if (status == 2) {
        session.receivedFinalFrame = true;
        final Uint8List audioBytes = session.audioBuf.takeBytes();
        if (audioBytes.isEmpty) {
          _completeSessionError(session, '讯飞返回结束帧，但音频为空');
          return;
        }
        if (!session.done.isCompleted) {
          session.done.complete(audioBytes);
        }
        unawaited(session.ws.sink.close());
      }
    } catch (e) {
      _completeSessionError(session, '解析失败：$e');
    }
  }

  Future<File> _writeAudioFile(Uint8List audioBytes) async {
    final Directory dir = await getTemporaryDirectory();
    final String filePath = path.join(
      dir.path,
      'tts_${DateTime.now().millisecondsSinceEpoch}.mp3',
    );
    final File file = File(filePath);
    await file.writeAsBytes(audioBytes, flush: true);
    return file;
  }

  void _completeSessionError(_TtsSession session, String message) {
    if (!session.done.isCompleted) {
      session.done.completeError(XunfeiTtsException(message));
    }
  }

  String _readErrorMessage({
    required int code,
    required String voice,
    required String serverMessage,
  }) {
    if (code == 11200) {
      return '讯飞 TTS 错误 (11200)：当前音色[$voice]未授权、已过期，或账号没有开通该发音人';
    }
    final String suffix = serverMessage.isEmpty ? '' : ': $serverMessage';
    return '讯飞 TTS 错误 ($code)$suffix';
  }
}

class _TtsSession {
  _TtsSession(this.ws);

  final WebSocketChannel ws;
  final BytesBuilder audioBuf = BytesBuilder();
  final Completer<Uint8List> done = Completer<Uint8List>();
  final Completer<void> playbackDone = Completer<void>();
  StreamSubscription<dynamic>? subscription;
  bool receivedFinalFrame = false;
}

final Provider<XunfeiTtsClient> xunfeiTtsClientProvider =
    Provider<XunfeiTtsClient>((Ref ref) {
      final EnvConfig env = ref.watch(envConfigProvider);
      final XunfeiTtsClient client = XunfeiTtsClient(env: env);
      ref.onDispose(() => client.dispose());
      return client;
    });
