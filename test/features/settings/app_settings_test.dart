import 'package:flutter_test/flutter_test.dart';

import 'package:smart_workbench/features/settings/domain/app_settings.dart';

/// AppSettings 序列化与字段容错测试。
///
/// 重点保证：从老数据库（缺新字段）加载也能正常工作，给新字段填默认值；
/// 非法值降级到合法档位，不抛异常。
void main() {
  group('AppSettings 默认值', () {
    test('无参构造 → 全默认', () {
      const AppSettings s = AppSettings();
      expect(s.ttsPlaybackMode, TtsPlaybackMode.auto);
      expect(s.ttsSpeed, kDefaultTtsSpeed);
      expect(s.ttsVoice, kDefaultTtsVoice);
    });
  });

  group('AppSettings.fromMap', () {
    test('完整字段解析', () {
      final AppSettings s = AppSettings.fromMap(<String, Object?>{
        'reminders_enabled': 1,
        'show_completed': 0,
        'show_lunar': 1,
        'locale_code': 'zh-CN',
        'tts_voice': 'x6_lingxiaoxuan_pro',
        'tts_playback_mode': 'always',
        'tts_speed': 1.2,
      });
      expect(s.ttsPlaybackMode, TtsPlaybackMode.always);
      expect(s.ttsSpeed, 1.2);
      expect(s.showCompleted, false);
    });

    test('老数据缺新字段 → 用默认值', () {
      // 模拟从 v2 库读到的行
      final AppSettings s = AppSettings.fromMap(<String, Object?>{
        'reminders_enabled': 1,
        'show_completed': 1,
        'show_lunar': 1,
        'locale_code': 'zh-CN',
        'tts_voice': 'x6_lingxiaoxuan_pro',
      });
      expect(s.ttsPlaybackMode, TtsPlaybackMode.auto);
      expect(s.ttsSpeed, kDefaultTtsSpeed);
    });

    test('未知 playback_mode → 降级到 auto', () {
      final AppSettings s = AppSettings.fromMap(<String, Object?>{
        'tts_playback_mode': 'wtf',
        'tts_speed': 1.0,
      });
      expect(s.ttsPlaybackMode, TtsPlaybackMode.auto);
    });

    test('非法 tts_speed → 落到最近合法档位', () {
      final AppSettings s = AppSettings.fromMap(<String, Object?>{
        'tts_speed': 1.7,
      });
      expect(s.ttsSpeed, 1.5);
    });

    test('字符串 tts_speed → 解析', () {
      final AppSettings s = AppSettings.fromMap(<String, Object?>{
        'tts_speed': '0.8',
      });
      expect(s.ttsSpeed, 0.8);
    });

    test('字符串无法解析的 tts_speed → 默认值', () {
      final AppSettings s = AppSettings.fromMap(<String, Object?>{
        'tts_speed': 'fast',
      });
      expect(s.ttsSpeed, kDefaultTtsSpeed);
    });
  });

  group('AppSettings.toDatabaseMap', () {
    test('包含新字段', () {
      const AppSettings s = AppSettings(
        ttsPlaybackMode: TtsPlaybackMode.shortOnly,
        ttsSpeed: 1.2,
      );
      final Map<String, Object?> map = s.toDatabaseMap(DateTime(2026, 5, 8));
      expect(map['tts_playback_mode'], 'shortOnly');
      expect(map['tts_speed'], 1.2);
    });

    test('toMap → fromMap 来回值不变', () {
      const AppSettings s = AppSettings(
        remindersEnabled: false,
        showCompleted: true,
        showLunar: false,
        ttsVoice: 'x5_lingyuzhao_flow',
        ttsPlaybackMode: TtsPlaybackMode.silent,
        ttsSpeed: 1.5,
      );
      final Map<String, Object?> map = s.toDatabaseMap(DateTime(2026, 5, 8));
      final AppSettings s2 = AppSettings.fromMap(map);
      expect(s2.remindersEnabled, false);
      expect(s2.showCompleted, true);
      expect(s2.showLunar, false);
      expect(s2.ttsVoice, 'x5_lingyuzhao_flow');
      expect(s2.ttsPlaybackMode, TtsPlaybackMode.silent);
      expect(s2.ttsSpeed, 1.5);
    });
  });

  group('TtsPlaybackMode.fromCode', () {
    test('合法 code → 对应枚举', () {
      expect(TtsPlaybackMode.fromCode('auto'), TtsPlaybackMode.auto);
      expect(TtsPlaybackMode.fromCode('always'), TtsPlaybackMode.always);
      expect(
        TtsPlaybackMode.fromCode('shortOnly'),
        TtsPlaybackMode.shortOnly,
      );
      expect(TtsPlaybackMode.fromCode('silent'), TtsPlaybackMode.silent);
    });

    test('null / 未知 → auto', () {
      expect(TtsPlaybackMode.fromCode(null), TtsPlaybackMode.auto);
      expect(TtsPlaybackMode.fromCode('xyz'), TtsPlaybackMode.auto);
    });
  });

  group('normalizeTtsSpeed', () {
    test('合法档位保持', () {
      expect(normalizeTtsSpeed(0.8), 0.8);
      expect(normalizeTtsSpeed(1.0), 1.0);
      expect(normalizeTtsSpeed(1.2), 1.2);
      expect(normalizeTtsSpeed(1.5), 1.5);
    });

    test('明显偏向某档时落到该档', () {
      expect(normalizeTtsSpeed(0.85), 0.8); // 0.05 vs 0.15
      expect(normalizeTtsSpeed(0.95), 1.0);
      expect(normalizeTtsSpeed(1.4), 1.5);
      expect(normalizeTtsSpeed(2.0), 1.5); // 超出区间向上夹
      expect(normalizeTtsSpeed(0.0), 0.8); // 超出区间向下夹
    });

    test('平局或临近平局时仍返回合法档位（浮点精度容忍）', () {
      // 1.1 介于 1.0/1.2，浮点上略偏 1.2；1.35 略偏 1.2 或 1.5。
      // 不强求具体档位，只要求返回值在合法集合内。
      expect(kTtsSpeedOptions, contains(normalizeTtsSpeed(1.1)));
      expect(kTtsSpeedOptions, contains(normalizeTtsSpeed(1.35)));
    });

    test('NaN / Infinity → 默认值', () {
      expect(normalizeTtsSpeed(double.nan), kDefaultTtsSpeed);
      expect(normalizeTtsSpeed(double.infinity), kDefaultTtsSpeed);
      expect(normalizeTtsSpeed(double.negativeInfinity), kDefaultTtsSpeed);
    });
  });

  group('xunfeiSpeedForRate', () {
    test('档位映射', () {
      expect(xunfeiSpeedForRate(0.8), 30);
      expect(xunfeiSpeedForRate(1.0), 50);
      expect(xunfeiSpeedForRate(1.2), 65);
      expect(xunfeiSpeedForRate(1.5), 85);
    });

    test('非档位先 normalize 再映射', () {
      expect(xunfeiSpeedForRate(2.0), 85); // → 1.5 → 85
      expect(xunfeiSpeedForRate(0.5), 30); // → 0.8 → 30
    });
  });
}
