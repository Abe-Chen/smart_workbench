import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/config/env_config.dart';
import '../../settings/domain/app_settings.dart';

/// 火山引擎豆包语音合成大模型 2.0 — WebSocket V3 双向流式 client。
///
/// 协议参考 `docs/_scratch_volc_tts_doc.md`：
/// - URL: wss://openspeech.bytedance.com/api/v3/tts/bidirection
/// - Header: X-Api-Key + X-Api-Resource-Id（按音色路由 seed-tts-2.0 / seed-icl-2.0）
/// - 自定义二进制帧：[4B header][4B event][4B id_size + id][4B payload_size + payload]
/// - 状态机：StartConnection(1) → ConnectionStarted(50) → StartSession(100) →
///   SessionStarted(150) → TaskRequest(200) → TTSResponse(352)... →
///   FinishSession(102) → SessionFinished(152) → FinishConnection(2) → ConnectionFinished(52)
const String _kVolcTtsWsUrl =
    'wss://openspeech.bytedance.com/api/v3/tts/bidirection';

class VolcTtsException implements Exception {
  VolcTtsException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() =>
      'VolcTtsException(${statusCode ?? '-'}): $message';
}

class VolcTtsClient {
  VolcTtsClient({required EnvConfig env}) : _env = env {
    _playerCompleteSub = _player.onPlayerComplete.listen((_) {
      final _VolcSession? s = _session;
      if (s == null || s.playbackDone.isCompleted) return;
      s.playbackDone.complete();
    });
  }

  final EnvConfig _env;
  final AudioPlayer _player = AudioPlayer();
  final Uuid _uuid = const Uuid();
  _VolcSession? _session;
  StreamSubscription<void>? _playerCompleteSub;

  /// 合成并播放。Future 在播放开始时 resolve（不等播完）。
  /// [speedRate] 透传到 `audio_params.speech_rate`，范围 [-50, 100]，0 是正常。
  Future<void> speak(
    String text, {
    required String voice,
    int speedRate = 0,
  }) => _speakOnce(text, voice, speedRate: speedRate);

  Future<void> speakAndWaitComplete(
    String text, {
    required String voice,
    int speedRate = 0,
  }) =>
      _speakOnce(text, voice,
          speedRate: speedRate, waitUntilPlaybackComplete: true);

  Future<void> _speakOnce(
    String text,
    String voice, {
    bool waitUntilPlaybackComplete = false,
    int speedRate = 0,
  }) async {
    if (text.trim().isEmpty) return;
    if (!_env.hasVolcTtsCredentials) {
      throw VolcTtsException('火山 TTS 凭据未配置（VOLC_TTS_API_KEY）');
    }
    await stop();

    final String resourceId = volcResourceIdForVoice(voice);
    final String sessionId = _uuid.v4();
    final String connectId = _uuid.v4();

    final WebSocketChannel ws = IOWebSocketChannel.connect(
      Uri.parse(_kVolcTtsWsUrl),
      headers: <String, dynamic>{
        'X-Api-Key': _env.volcTtsApiKey,
        'X-Api-Resource-Id': resourceId,
        'X-Api-Connect-Id': connectId,
      },
    );

    final _VolcSession session = _VolcSession(ws, sessionId);
    _session = session;

    session.subscription = ws.stream.listen(
      (dynamic raw) => _handleFrame(session, raw),
      onError: (Object e, StackTrace _) =>
          session.failOnce('WS 异常：$e'),
      onDone: () {
        if (!session.audioDone.isCompleted) {
          session.failOnce('WS 提前关闭');
        }
      },
    );

    try {
      // 1. StartConnection
      ws.sink.add(_encodeFrameWithoutId(eventCode: 1, payload: '{}'));
      await session.connectionStarted.future;

      if (_session != session) return;

      // 2. StartSession（带音色和音频参数）
      ws.sink.add(_encodeStartSession(
        sessionId: sessionId,
        voice: voice,
        speedRate: speedRate,
      ));
      await session.sessionStarted.future;

      if (_session != session) return;

      // 3. TaskRequest（一次性发完整文本，不做流式分句）
      ws.sink.add(_encodeTaskRequest(sessionId: sessionId, text: text));

      // 4. FinishSession（告诉服务端文本发完）
      ws.sink.add(_encodeFinishSession(sessionId: sessionId));

      // 等所有 TTSResponse(352) 收齐 + SessionFinished(152)
      final Uint8List audioBytes = await session.audioDone.future;
      if (_session != session) return;

      // 5. FinishConnection（让服务端知道我们要走了，不影响本次播放）
      try {
        ws.sink.add(_encodeFrameWithoutId(eventCode: 2, payload: '{}'));
      } catch (_) {
        // 关闭阶段错误忽略，不影响播放
      }

      // 写文件并播放
      final File audioFile = await _writeAudioFile(audioBytes);
      if (_session != session) return;
      await _player.play(DeviceFileSource(audioFile.path));

      if (waitUntilPlaybackComplete && _session == session) {
        await session.playbackDone.future;
      }
    } finally {
      // 关闭 ws，但保留 _session 引用让上层能 stop()
      try {
        await ws.sink.close();
      } catch (_) {}
    }
  }

  Future<void> stop() async {
    final _VolcSession? s = _session;
    _session = null;
    if (s != null) {
      await s.subscription?.cancel();
      try {
        await s.ws.sink.close();
      } catch (_) {}
      s.failOnce('被中断');
    }
    await _player.stop();
  }

  Future<void> dispose() async {
    await stop();
    await _playerCompleteSub?.cancel();
    await _player.dispose();
  }

  // —— 帧解析 ——

  void _handleFrame(_VolcSession session, dynamic raw) {
    if (raw is! List<int>) {
      session.failOnce('收到非二进制帧');
      return;
    }
    final Uint8List bytes = raw is Uint8List ? raw : Uint8List.fromList(raw);
    if (bytes.length < 4) {
      session.failOnce('帧长度不足 4');
      return;
    }
    final ByteData view = ByteData.sublistView(bytes);
    final int b1 = bytes[1];
    final int messageType = (b1 >> 4) & 0x0f;
    final int flags = b1 & 0x0f;
    final bool hasEvent = (flags & 0x04) != 0;

    int offset = 4;

    // Error frame: messageType=0x0F，事件位置实际是 error code，跳过统一处理
    if (messageType == 0x0F) {
      session.failOnce('服务端错误帧');
      return;
    }

    if (!hasEvent) {
      // 不带 event 的帧目前不处理（双向流式 V3 服务端帧都带 event）
      return;
    }
    if (bytes.length < offset + 4) {
      session.failOnce('event 字段不完整');
      return;
    }
    final int event = view.getInt32(offset, Endian.big);
    offset += 4;

    // ConnectionStarted/Failed 带 connection_id；其他带 session_id
    if (bytes.length < offset + 4) {
      session.failOnce('id_size 字段不完整');
      return;
    }
    final int idSize = view.getUint32(offset, Endian.big);
    offset += 4;
    if (bytes.length < offset + idSize) {
      session.failOnce('id 数据不完整');
      return;
    }
    offset += idSize; // 读取后 offset 推进，但 id 内容本身不强制校验

    // Audio-only response: payload 是原始音频字节
    if (messageType == 0x0B) {
      if (bytes.length < offset + 4) {
        session.failOnce('音频 size 不完整');
        return;
      }
      final int audioSize = view.getUint32(offset, Endian.big);
      offset += 4;
      if (bytes.length < offset + audioSize) {
        session.failOnce('音频数据不完整');
        return;
      }
      session.audioBuf.add(bytes.sublist(offset, offset + audioSize));
      return;
    }

    // Full-server response: payload 是 JSON
    String? payloadJson;
    if (bytes.length >= offset + 4) {
      final int payloadSize = view.getUint32(offset, Endian.big);
      offset += 4;
      if (payloadSize > 0 && bytes.length >= offset + payloadSize) {
        payloadJson = utf8.decode(bytes.sublist(offset, offset + payloadSize));
      }
    }

    _processEvent(session, event, payloadJson);
  }

  void _processEvent(_VolcSession session, int event, String? payloadJson) {
    switch (event) {
      case 50: // ConnectionStarted
        if (!session.connectionStarted.isCompleted) {
          session.connectionStarted.complete();
        }
        break;
      case 51: // ConnectionFailed
        session.failOnce(
            'ConnectionFailed: ${_extractMessage(payloadJson) ?? '未知'}');
        break;
      case 150: // SessionStarted
        if (!session.sessionStarted.isCompleted) {
          session.sessionStarted.complete();
        }
        break;
      case 152: // SessionFinished — 所有音频块应已收齐
        if (!session.audioDone.isCompleted) {
          final Uint8List audio = session.audioBuf.takeBytes();
          if (audio.isEmpty) {
            session.audioDone.completeError(
              VolcTtsException('SessionFinished 但音频为空'),
            );
          } else {
            session.audioDone.complete(audio);
          }
        }
        break;
      case 153: // SessionFailed
        session.failOnce(
            'SessionFailed: ${_extractMessage(payloadJson) ?? '未知'}');
        break;
      case 350: // TTSSentenceStart
      case 351: // TTSSentenceEnd
      case 354: // TTSSubtitle（2.0）
      case 52: // ConnectionFinished
        // 字幕 / 时间戳 / 关闭确认事件，TTS 主流程不依赖
        break;
      default:
        // 未知事件忽略
        break;
    }
  }

  String? _extractMessage(String? payloadJson) {
    if (payloadJson == null || payloadJson.isEmpty) return null;
    try {
      final dynamic decoded = jsonDecode(payloadJson);
      if (decoded is Map<String, dynamic>) {
        final Object? msg = decoded['message'];
        if (msg is String) return msg;
      }
    } catch (_) {}
    return payloadJson;
  }

  // —— 帧编码 ——

  Uint8List _encodeStartSession({
    required String sessionId,
    required String voice,
    required int speedRate,
  }) {
    final Map<String, dynamic> payload = <String, dynamic>{
      'user': <String, dynamic>{'uid': 'smart_workbench'},
      'event': 100,
      'namespace': 'BidirectionalTTS',
      'req_params': <String, dynamic>{
        'speaker': voice,
        'audio_params': <String, dynamic>{
          'format': 'mp3',
          'sample_rate': 24000,
          'bit_rate': 128000,
          'speech_rate': speedRate.clamp(-50, 100),
          'loudness_rate': 0,
        },
      },
    };
    return _encodeFrameWithId(
      eventCode: 100,
      sessionId: sessionId,
      payload: jsonEncode(payload),
    );
  }

  Uint8List _encodeTaskRequest({
    required String sessionId,
    required String text,
  }) {
    final Map<String, dynamic> payload = <String, dynamic>{
      'user': <String, dynamic>{'uid': 'smart_workbench'},
      'event': 200,
      'namespace': 'BidirectionalTTS',
      'req_params': <String, dynamic>{'text': text},
    };
    return _encodeFrameWithId(
      eventCode: 200,
      sessionId: sessionId,
      payload: jsonEncode(payload),
    );
  }

  Uint8List _encodeFinishSession({required String sessionId}) {
    return _encodeFrameWithId(
      eventCode: 102,
      sessionId: sessionId,
      payload: '{}',
    );
  }

  Uint8List _encodeFrameWithoutId({
    required int eventCode,
    required String payload,
  }) {
    final Uint8List payloadBytes = Uint8List.fromList(utf8.encode(payload));
    final BytesBuilder b = BytesBuilder();
    // header: protocol v1 (0001) + 4-byte header size (0001) = 0x11
    b.addByte(0x11);
    // Full-client request (0001) + with event flag (0100) = 0x14
    b.addByte(0x14);
    // JSON serialization (0001) + no compression (0000) = 0x10
    b.addByte(0x10);
    // reserved
    b.addByte(0x00);
    b.add(_int32(eventCode));
    b.add(_uint32(payloadBytes.length));
    b.add(payloadBytes);
    return b.toBytes();
  }

  Uint8List _encodeFrameWithId({
    required int eventCode,
    required String sessionId,
    required String payload,
  }) {
    final Uint8List sessionIdBytes = Uint8List.fromList(utf8.encode(sessionId));
    final Uint8List payloadBytes = Uint8List.fromList(utf8.encode(payload));
    final BytesBuilder b = BytesBuilder();
    b.addByte(0x11);
    b.addByte(0x14);
    b.addByte(0x10);
    b.addByte(0x00);
    b.add(_int32(eventCode));
    b.add(_uint32(sessionIdBytes.length));
    b.add(sessionIdBytes);
    b.add(_uint32(payloadBytes.length));
    b.add(payloadBytes);
    return b.toBytes();
  }

  Uint8List _int32(int v) {
    final ByteData bd = ByteData(4);
    bd.setInt32(0, v, Endian.big);
    return bd.buffer.asUint8List();
  }

  Uint8List _uint32(int v) {
    final ByteData bd = ByteData(4);
    bd.setUint32(0, v, Endian.big);
    return bd.buffer.asUint8List();
  }

  Future<File> _writeAudioFile(Uint8List bytes) async {
    final Directory dir = await getTemporaryDirectory();
    final String filePath = path.join(
      dir.path,
      'volc_tts_${DateTime.now().millisecondsSinceEpoch}.mp3',
    );
    final File file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}

class _VolcSession {
  _VolcSession(this.ws, this.sessionId);

  final WebSocketChannel ws;
  final String sessionId;
  final BytesBuilder audioBuf = BytesBuilder();
  final Completer<void> connectionStarted = Completer<void>();
  final Completer<void> sessionStarted = Completer<void>();
  final Completer<Uint8List> audioDone = Completer<Uint8List>();
  final Completer<void> playbackDone = Completer<void>();
  StreamSubscription<dynamic>? subscription;

  void failOnce(String msg) {
    final VolcTtsException err = VolcTtsException(msg);
    if (!connectionStarted.isCompleted) {
      connectionStarted.completeError(err);
    }
    if (!sessionStarted.isCompleted) sessionStarted.completeError(err);
    if (!audioDone.isCompleted) audioDone.completeError(err);
    if (!playbackDone.isCompleted) playbackDone.completeError(err);
  }
}

final Provider<VolcTtsClient> volcTtsClientProvider =
    Provider<VolcTtsClient>((Ref ref) {
  final EnvConfig env = ref.watch(envConfigProvider);
  final VolcTtsClient client = VolcTtsClient(env: env);
  ref.onDispose(() => client.dispose());
  return client;
});

/// 把语义化倍率（0.8/1.0/1.2/1.5）映射到火山 `speech_rate` 整数（-50~100）。
/// 与讯飞的换算保持类似的语义边界。
int volcSpeedRateForRate(double rate) {
  final double n = normalizeTtsSpeed(rate);
  if (n == 0.8) return -20;
  if (n == 1.0) return 0;
  if (n == 1.2) return 20;
  if (n == 1.5) return 50;
  return 0;
}
