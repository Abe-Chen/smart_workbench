import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env_config.dart';

const String _methodChannelName = 'smart_workbench/voice_wakeup';
const String _eventChannelName = 'smart_workbench/voice_wakeup_events';

class VoiceWakeupConfig {
  const VoiceWakeupConfig({
    required this.appId,
    required this.apiKey,
    required this.apiSecret,
    this.wakeWord = '小治小治',
  });

  factory VoiceWakeupConfig.fromEnv(EnvConfig env) {
    return VoiceWakeupConfig(
      appId: env.xfAppId,
      apiKey: env.xfApiKey,
      apiSecret: env.xfApiSecret,
    );
  }

  final String appId;
  final String apiKey;
  final String apiSecret;
  final String wakeWord;

  bool get hasCredentials =>
      appId.trim().isNotEmpty &&
      apiKey.trim().isNotEmpty &&
      apiSecret.trim().isNotEmpty;

  Map<String, Object?> toMethodArgs() {
    return <String, Object?>{
      'appId': appId,
      'apiKey': apiKey,
      'apiSecret': apiSecret,
      'wakeWord': wakeWord,
    };
  }
}

class VoiceWakeupStatus {
  const VoiceWakeupStatus({
    required this.supported,
    required this.running,
    required this.sdkPresent,
    required this.resourceReady,
    required this.abilityId,
    required this.wakeWord,
    this.lastError,
  });

  factory VoiceWakeupStatus.unsupported() {
    return const VoiceWakeupStatus(
      supported: false,
      running: false,
      sdkPresent: false,
      resourceReady: false,
      abilityId: '',
      wakeWord: '小治小治',
    );
  }

  factory VoiceWakeupStatus.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) {
      return VoiceWakeupStatus.unsupported();
    }
    return VoiceWakeupStatus(
      supported: map['supported'] == true,
      running: map['running'] == true,
      sdkPresent: map['sdkPresent'] == true,
      resourceReady: map['resourceReady'] == true,
      abilityId: map['abilityId']?.toString() ?? '',
      wakeWord: map['wakeWord']?.toString() ?? '小治小治',
      lastError: map['lastError']?.toString(),
    );
  }

  final bool supported;
  final bool running;
  final bool sdkPresent;
  final bool resourceReady;
  final String abilityId;
  final String wakeWord;
  final String? lastError;

  bool get available => supported && sdkPresent && resourceReady;
}

enum VoiceWakeupEventType { wake, status, error, unknown }

class VoiceWakeupEvent {
  const VoiceWakeupEvent({
    required this.type,
    this.wakeWord,
    this.status,
    this.code,
    this.message,
  });

  factory VoiceWakeupEvent.fromMap(Map<dynamic, dynamic> map) {
    final String type = map['type']?.toString() ?? '';
    return VoiceWakeupEvent(
      type: switch (type) {
        'wake' => VoiceWakeupEventType.wake,
        'status' => VoiceWakeupEventType.status,
        'error' => VoiceWakeupEventType.error,
        _ => VoiceWakeupEventType.unknown,
      },
      wakeWord: map['wakeWord']?.toString(),
      status: map['status'] is Map
          ? VoiceWakeupStatus.fromMap(map['status'] as Map<dynamic, dynamic>)
          : null,
      code: map['code']?.toString(),
      message: map['message']?.toString(),
    );
  }

  final VoiceWakeupEventType type;
  final String? wakeWord;
  final VoiceWakeupStatus? status;
  final String? code;
  final String? message;
}

class VoiceWakeupService {
  const VoiceWakeupService({
    MethodChannel methodChannel = const MethodChannel(_methodChannelName),
    EventChannel eventChannel = const EventChannel(_eventChannelName),
    bool? isAndroidOverride,
  }) : _methodChannel = methodChannel,
       _eventChannel = eventChannel,
       _isAndroidOverride = isAndroidOverride;

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  final bool? _isAndroidOverride;

  bool get _isAndroid => _isAndroidOverride ?? Platform.isAndroid;

  Stream<VoiceWakeupEvent> get events {
    if (!_isAndroid) {
      return const Stream<VoiceWakeupEvent>.empty();
    }
    return _eventChannel
        .receiveBroadcastStream()
        .where((dynamic event) => event is Map)
        .cast<Map<dynamic, dynamic>>()
        .map((Map<dynamic, dynamic> event) => VoiceWakeupEvent.fromMap(event));
  }

  Future<VoiceWakeupStatus> getStatus() async {
    if (!_isAndroid) {
      return VoiceWakeupStatus.unsupported();
    }
    final Map<dynamic, dynamic>? result = await _methodChannel
        .invokeMapMethod<dynamic, dynamic>('getStatus');
    return VoiceWakeupStatus.fromMap(result);
  }

  Future<VoiceWakeupStatus> start(VoiceWakeupConfig config) async {
    if (!_isAndroid || !config.hasCredentials) {
      return VoiceWakeupStatus.unsupported();
    }
    final Map<dynamic, dynamic>? result = await _methodChannel.invokeMapMethod(
      'start',
      config.toMethodArgs(),
    );
    return VoiceWakeupStatus.fromMap(result);
  }

  Future<VoiceWakeupStatus> stop() async {
    if (!_isAndroid) {
      return VoiceWakeupStatus.unsupported();
    }
    final Map<dynamic, dynamic>? result = await _methodChannel
        .invokeMapMethod<dynamic, dynamic>('stop');
    return VoiceWakeupStatus.fromMap(result);
  }
}

final Provider<VoiceWakeupService> voiceWakeupServiceProvider =
    Provider<VoiceWakeupService>((Ref ref) => const VoiceWakeupService());
