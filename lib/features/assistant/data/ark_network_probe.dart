import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

const String kArkHost = 'ark.cn-beijing.volces.com';

class ArkNetworkProbe {
  DateTime? _lastReachableAt;

  Future<void> ensureReachable() async {
    final DateTime now = DateTime.now();
    if (_lastReachableAt != null &&
        now.difference(_lastReachableAt!) < const Duration(seconds: 15)) {
      return;
    }

    Socket? socket;
    try {
      socket = await Socket.connect(
        kArkHost,
        443,
        timeout: const Duration(seconds: 2),
      );
      _lastReachableAt = now;
    } on SocketException {
      throw const ArkNetworkUnavailableException();
    } on HandshakeException {
      _lastReachableAt = now;
    } on OSError {
      throw const ArkNetworkUnavailableException();
    } finally {
      await socket?.close();
    }
  }
}

class ArkNetworkUnavailableException implements Exception {
  const ArkNetworkUnavailableException();
}

final Provider<ArkNetworkProbe> arkNetworkProbeProvider =
    Provider<ArkNetworkProbe>((Ref ref) {
      return ArkNetworkProbe();
    });
