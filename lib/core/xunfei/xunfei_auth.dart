import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// 讯飞 IAT / TTS WebSocket 接入用同一套 HMAC-SHA256 签名。
/// 给定原始 wss URL（如 wss://iat-api.xfyun.cn/v2/iat），返回带鉴权参数的完整 URL。
class XunfeiAuth {
  XunfeiAuth({
    required this.apiKey,
    required this.apiSecret,
  });

  final String apiKey;
  final String apiSecret;

  /// 拼出带签名的 wss URL。
  String signedUrl(String baseWssUrl) {
    final Uri uri = Uri.parse(baseWssUrl);
    final String host = uri.host;
    final String path = uri.path;
    final String date = HttpDate.format(DateTime.now().toUtc());

    final String signatureOrigin =
        'host: $host\ndate: $date\nGET $path HTTP/1.1';
    final List<int> hmac = Hmac(sha256, utf8.encode(apiSecret))
        .convert(utf8.encode(signatureOrigin))
        .bytes;
    final String signature = base64.encode(hmac);

    final String authorizationOrigin =
        'api_key="$apiKey", algorithm="hmac-sha256", '
        'headers="host date request-line", signature="$signature"';
    final String authorization = base64.encode(utf8.encode(authorizationOrigin));

    final Uri signed = uri.replace(
      queryParameters: <String, String>{
        'authorization': authorization,
        'date': date,
        'host': host,
      },
    );
    return signed.toString();
  }
}
