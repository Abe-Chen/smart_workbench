import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/domain/app_settings.dart';
import 'volc_tts_client.dart';
import 'xunfei_tts_client.dart';

/// 统一 TTS 入口。
///
/// - 按音色 code 路由到火山豆包 2.0 (`VolcTtsClient`) 或讯飞超拟人 (`XunfeiTtsClient`)。
/// - 火山失败时自动 fallback 到讯飞默认音色，避免对话场景"卡半天没声音"。
/// - 所有调用方应当走 facade，不要直接持有具体 client。
class TtsFacade {
  TtsFacade({required this.volc, required this.xunfei});

  final VolcTtsClient volc;
  final XunfeiTtsClient xunfei;

  Future<void> speak(
    String text, {
    required String voice,
    required double rate,
  }) =>
      _dispatch(text,
          voice: voice, rate: rate, waitUntilPlaybackComplete: false);

  Future<void> speakAndWaitComplete(
    String text, {
    required String voice,
    required double rate,
  }) =>
      _dispatch(text,
          voice: voice, rate: rate, waitUntilPlaybackComplete: true);

  Future<void> _dispatch(
    String text, {
    required String voice,
    required double rate,
    required bool waitUntilPlaybackComplete,
  }) async {
    final TtsProvider provider = TtsProvider.fromVoiceCode(voice);
    if (provider == TtsProvider.volc) {
      try {
        if (waitUntilPlaybackComplete) {
          await volc.speakAndWaitComplete(
            text,
            voice: voice,
            speedRate: volcSpeedRateForRate(rate),
          );
        } else {
          await volc.speak(
            text,
            voice: voice,
            speedRate: volcSpeedRateForRate(rate),
          );
        }
      } catch (e) {
        if (isTtsInterrupted(e)) {
          rethrow;
        }
        // 火山失败 fallback 到讯飞默认音色（聆小璇）
        const String fallbackVoice = 'x6_lingxiaoxuan_pro';
        if (waitUntilPlaybackComplete) {
          await xunfei.speakAndWaitComplete(
            text,
            voice: fallbackVoice,
            xunfeiSpeed: xunfeiSpeedForRate(rate),
          );
        } else {
          await xunfei.speak(
            text,
            voice: fallbackVoice,
            xunfeiSpeed: xunfeiSpeedForRate(rate),
          );
        }
      }
      return;
    }

    // 直接走讯飞
    if (waitUntilPlaybackComplete) {
      await xunfei.speakAndWaitComplete(
        text,
        voice: voice,
        xunfeiSpeed: xunfeiSpeedForRate(rate),
      );
    } else {
      await xunfei.speak(
        text,
        voice: voice,
        xunfeiSpeed: xunfeiSpeedForRate(rate),
      );
    }
  }

  Future<void> stop() async {
    await Future.wait<void>(<Future<void>>[
      volc.stop(),
      xunfei.stop(),
    ]);
  }
}

/// 调用方判断 TTS 异常是否是"被中断"（用户切换 / stop 主动取消）。
/// 这种情况下不应当上报 ttsError 通道，避免显示无意义的报错。
bool isTtsInterrupted(Object e) {
  if (e is VolcTtsException && e.message == '被中断') return true;
  if (e is XunfeiTtsException && e.message == '被中断') return true;
  return false;
}

final Provider<TtsFacade> ttsFacadeProvider = Provider<TtsFacade>((Ref ref) {
  return TtsFacade(
    volc: ref.watch(volcTtsClientProvider),
    xunfei: ref.watch(xunfeiTtsClientProvider),
  );
});
