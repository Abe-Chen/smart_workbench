import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/config/env_config.dart';
import '../../../core/xunfei/xunfei_auth.dart';

const String _kIatWssUrl = 'wss://iat-api.xfyun.cn/v2/iat';

sealed class AsrEvent {}

class AsrPartialEvent extends AsrEvent {
  AsrPartialEvent(this.text);
  final String text;
}

class AsrFinalEvent extends AsrEvent {
  AsrFinalEvent(this.text);
  final String text;
}

class AsrErrorEvent extends AsrEvent {
  AsrErrorEvent(this.code, this.message);
  final int code;
  final String message;
}

/// 讯飞 IAT 流式语音识别（中文普通话）。生命周期：
///   final c = XunfeiAsrClient(env: env);
///   c.events.listen(...)
///   await c.start();      // 建 WS
///   c.sendAudio(pcm)      // 多次推 16kHz 16bit mono PCM 帧
///   await c.stop();       // 推 end frame，等 final
///   c.dispose();          // 拆连接
class XunfeiAsrClient {
  XunfeiAsrClient({required EnvConfig env}) : _env = env;

  final EnvConfig _env;
  WebSocketChannel? _ws;
  StreamSubscription<dynamic>? _wsSub;
  final StreamController<AsrEvent> _eventCtrl =
      StreamController<AsrEvent>.broadcast();
  final StringBuffer _accumulated = StringBuffer();
  bool _firstFrameSent = false;
  bool _ended = false;

  Stream<AsrEvent> get events => _eventCtrl.stream;

  Future<void> start() async {
    if (!_env.hasXunfeiCredentials) {
      throw StateError('讯飞凭据未配置');
    }
    final XunfeiAuth auth = XunfeiAuth(
      apiKey: _env.xfApiKey,
      apiSecret: _env.xfApiSecret,
    );
    final String url = auth.signedUrl(_kIatWssUrl);
    _ws = IOWebSocketChannel.connect(Uri.parse(url));
    _firstFrameSent = false;
    _ended = false;
    _accumulated.clear();
    _wsSub = _ws!.stream.listen(
      _handleMessage,
      onError: (Object err, StackTrace _) {
        _eventCtrl.add(AsrErrorEvent(-1, err.toString()));
      },
      onDone: () {
        if (!_ended) {
          _eventCtrl.add(AsrFinalEvent(_accumulated.toString()));
        }
      },
    );
  }

  /// 推一段 PCM（16kHz 16bit mono raw）。讯飞建议每帧 40ms（1280B）。
  void sendAudio(Uint8List pcm) {
    if (_ws == null) return;
    if (_ended) return;
    final String audioB64 = base64.encode(pcm);
    final Map<String, dynamic> frame = _firstFrameSent
        ? <String, dynamic>{
            'data': <String, dynamic>{
              'status': 1,
              'format': 'audio/L16;rate=16000',
              'encoding': 'raw',
              'audio': audioB64,
            },
          }
        : <String, dynamic>{
            'common': <String, dynamic>{'app_id': _env.xfAppId},
            'business': <String, dynamic>{
              'language': 'zh_cn',
              'domain': 'iat',
              'accent': 'mandarin',
              'vad_eos': 2000,
              'dwa': 'wpgs',
            },
            'data': <String, dynamic>{
              'status': 0,
              'format': 'audio/L16;rate=16000',
              'encoding': 'raw',
              'audio': audioB64,
            },
          };
    _firstFrameSent = true;
    _ws!.sink.add(jsonEncode(frame));
  }

  /// 推结束帧，等服务端返回 final 后 close。
  Future<void> stop() async {
    if (_ws == null || _ended) return;
    _ended = true;
    if (!_firstFrameSent) {
      // 没推过音频，发一个空的 first+end 让服务端释放连接。
      _ws!.sink.add(
        jsonEncode(<String, dynamic>{
          'common': <String, dynamic>{'app_id': _env.xfAppId},
          'business': <String, dynamic>{
            'language': 'zh_cn',
            'domain': 'iat',
            'accent': 'mandarin',
          },
          'data': <String, dynamic>{
            'status': 2,
            'format': 'audio/L16;rate=16000',
            'encoding': 'raw',
            'audio': '',
          },
        }),
      );
    } else {
      _ws!.sink.add(
        jsonEncode(<String, dynamic>{
          'data': <String, dynamic>{
            'status': 2,
            'format': 'audio/L16;rate=16000',
            'encoding': 'raw',
            'audio': '',
          },
        }),
      );
    }
  }

  void dispose() {
    _wsSub?.cancel();
    _ws?.sink.close();
    _ws = null;
    _eventCtrl.close();
  }

  void _handleMessage(dynamic raw) {
    try {
      final Map<String, dynamic> msg =
          jsonDecode(raw as String) as Map<String, dynamic>;
      final int code = msg['code'] as int? ?? 0;
      if (code != 0) {
        _eventCtrl.add(
          AsrErrorEvent(code, (msg['message'] as String?) ?? '讯飞 IAT 异常'),
        );
        return;
      }
      final Map<String, dynamic>? data = msg['data'] as Map<String, dynamic>?;
      if (data == null) return;
      final int status = data['status'] as int? ?? 0;
      final Map<String, dynamic>? result = data['result'] as Map<String, dynamic>?;
      if (result != null) {
        final String segment = _extractWords(result);
        final String pgs = (result['pgs'] as String?) ?? 'apd';
        if (pgs == 'rpl') {
          // 替换模式：移除上次最后一段，目前简化处理：直接重写
          _accumulated.clear();
          _accumulated.write(segment);
        } else {
          _accumulated.write(segment);
        }
        _eventCtrl.add(AsrPartialEvent(_accumulated.toString()));
      }
      if (status == 2) {
        _eventCtrl.add(AsrFinalEvent(_accumulated.toString()));
        _ws?.sink.close();
      }
    } catch (e) {
      _eventCtrl.add(AsrErrorEvent(-2, '解析失败：$e'));
    }
  }

  String _extractWords(Map<String, dynamic> result) {
    final List<dynamic>? ws = result['ws'] as List<dynamic>?;
    if (ws == null) return '';
    final StringBuffer buf = StringBuffer();
    for (final dynamic w in ws) {
      if (w is! Map<String, dynamic>) continue;
      final List<dynamic>? cw = w['cw'] as List<dynamic>?;
      if (cw == null) continue;
      for (final dynamic c in cw) {
        if (c is! Map<String, dynamic>) continue;
        final String? text = c['w'] as String?;
        if (text != null) buf.write(text);
      }
    }
    return buf.toString();
  }
}

final Provider<XunfeiAsrClient Function()> xunfeiAsrClientFactoryProvider =
    Provider<XunfeiAsrClient Function()>((Ref ref) {
      final EnvConfig env = ref.watch(envConfigProvider);
      return () => XunfeiAsrClient(env: env);
    });
