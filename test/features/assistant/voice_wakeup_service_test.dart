import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_workbench/core/voice/voice_wakeup_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('smart_workbench/voice_wakeup');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('non-Android platform does not call native channel', () async {
    bool called = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          called = true;
          return <String, Object?>{};
        });

    const VoiceWakeupService service = VoiceWakeupService(
      methodChannel: channel,
      isAndroidOverride: false,
    );

    final VoiceWakeupStatus status = await service.start(
      const VoiceWakeupConfig(appId: 'app', apiKey: 'key', apiSecret: 'secret'),
    );

    expect(called, isFalse);
    expect(status.supported, isFalse);
    expect(status.running, isFalse);
  });

  test('start sends wake config to native bridge', () async {
    MethodCall? capturedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          capturedCall = call;
          return <String, Object?>{
            'supported': true,
            'running': true,
            'sdkPresent': true,
            'resourceReady': true,
            'abilityId': 'e867a88f2',
            'wakeWord': '小治小治',
          };
        });

    const VoiceWakeupService service = VoiceWakeupService(
      methodChannel: channel,
      isAndroidOverride: true,
    );

    final VoiceWakeupStatus status = await service.start(
      const VoiceWakeupConfig(appId: 'app', apiKey: 'key', apiSecret: 'secret'),
    );

    expect(capturedCall?.method, 'start');
    expect(capturedCall?.arguments, <String, Object?>{
      'appId': 'app',
      'apiKey': 'key',
      'apiSecret': 'secret',
      'wakeWord': '小治小治',
    });
    expect(status.available, isTrue);
    expect(status.running, isTrue);
  });

  test('event parser accepts wake, status, and error events', () {
    final VoiceWakeupEvent wake = VoiceWakeupEvent.fromMap(<String, Object?>{
      'type': 'wake',
      'wakeWord': '小治小治',
    });
    final VoiceWakeupEvent status = VoiceWakeupEvent.fromMap(<String, Object?>{
      'type': 'status',
      'status': <String, Object?>{
        'supported': true,
        'running': false,
        'sdkPresent': false,
        'resourceReady': false,
        'abilityId': 'e867a88f2',
        'wakeWord': '小治小治',
        'lastError': 'aikit_sdk_missing',
      },
    });
    final VoiceWakeupEvent error = VoiceWakeupEvent.fromMap(<String, Object?>{
      'type': 'error',
      'code': 'aikit_runtime_error',
      'message': 'failed',
    });

    expect(wake.type, VoiceWakeupEventType.wake);
    expect(wake.wakeWord, '小治小治');
    expect(status.type, VoiceWakeupEventType.status);
    expect(status.status?.lastError, 'aikit_sdk_missing');
    expect(error.type, VoiceWakeupEventType.error);
    expect(error.code, 'aikit_runtime_error');
  });
}
