import 'package:flutter_test/flutter_test.dart';

import 'package:smart_workbench/features/assistant/application/assistant_controller.dart';
import 'package:smart_workbench/features/assistant/application/assistant_state.dart';
import 'package:smart_workbench/features/settings/domain/app_settings.dart';

/// 决策矩阵覆盖：
/// - 3 入口（drawerText / drawerVoice / quickVoice）
/// - 4 模式（auto / always / shortOnly / silent）
/// - 2 承载面（fullscreenAnswer / drawer）
/// - sessionMute 优先级
void main() {
  bool decide({
    required AssistantEntrySource entry,
    required AssistantReplySurface surface,
    required TtsPlaybackMode mode,
    bool fullscreenAnswer = false,
    AssistantSessionMute sessionMute = AssistantSessionMute.followSettings,
  }) {
    return decideAutoSpeak(
      entrySource: entry,
      surface: surface,
      fullscreenAnswer: fullscreenAnswer,
      mode: mode,
      sessionMute: sessionMute,
    );
  }

  group('auto 模式（默认）', () {
    test('quickVoice + fullscreenAnswer → 播', () {
      expect(
        decide(
          entry: AssistantEntrySource.quickVoice,
          surface: AssistantReplySurface.none,
          fullscreenAnswer: true,
          mode: TtsPlaybackMode.auto,
        ),
        true,
      );
    });

    test('drawerText + drawer → 不播', () {
      expect(
        decide(
          entry: AssistantEntrySource.drawerText,
          surface: AssistantReplySurface.drawer,
          mode: TtsPlaybackMode.auto,
        ),
        false,
      );
    });

    test('drawerVoice + drawer → 播', () {
      expect(
        decide(
          entry: AssistantEntrySource.drawerVoice,
          surface: AssistantReplySurface.drawer,
          mode: TtsPlaybackMode.auto,
        ),
        true,
      );
    });

    test('quickVoice + drawer（抽屉已打开的会话）→ 播', () {
      expect(
        decide(
          entry: AssistantEntrySource.quickVoice,
          surface: AssistantReplySurface.drawer,
          mode: TtsPlaybackMode.auto,
        ),
        true,
      );
    });

    test('任意入口 + none 且无大卡 → 不播', () {
      expect(
        decide(
          entry: AssistantEntrySource.quickVoice,
          surface: AssistantReplySurface.none,
          mode: TtsPlaybackMode.auto,
        ),
        false,
      );
    });
  });

  group('always 模式', () {
    test('文字输入也播', () {
      expect(
        decide(
          entry: AssistantEntrySource.drawerText,
          surface: AssistantReplySurface.drawer,
          mode: TtsPlaybackMode.always,
        ),
        true,
      );
    });

    test('fullscreenAnswer 也播', () {
      expect(
        decide(
          entry: AssistantEntrySource.quickVoice,
          surface: AssistantReplySurface.none,
          fullscreenAnswer: true,
          mode: TtsPlaybackMode.always,
        ),
        true,
      );
    });

    test('none 不播（无承载面）', () {
      expect(
        decide(
          entry: AssistantEntrySource.drawerText,
          surface: AssistantReplySurface.none,
          mode: TtsPlaybackMode.always,
        ),
        false,
      );
    });
  });

  group('shortOnly 模式', () {
    test('fullscreenAnswer 才播', () {
      expect(
        decide(
          entry: AssistantEntrySource.quickVoice,
          surface: AssistantReplySurface.none,
          fullscreenAnswer: true,
          mode: TtsPlaybackMode.shortOnly,
        ),
        true,
      );
    });

    test('drawer 不播（即使是语音入口）', () {
      expect(
        decide(
          entry: AssistantEntrySource.drawerVoice,
          surface: AssistantReplySurface.drawer,
          mode: TtsPlaybackMode.shortOnly,
        ),
        false,
      );
    });
  });

  group('silent 模式', () {
    test('任意入口 + 任意承载面 → 不播', () {
      for (final AssistantEntrySource entry in AssistantEntrySource.values) {
        for (final bool fullscreenAnswer in <bool>[false, true]) {
          for (final AssistantReplySurface surface
              in AssistantReplySurface.values) {
            expect(
              decide(
                entry: entry,
                surface: surface,
                fullscreenAnswer: fullscreenAnswer,
                mode: TtsPlaybackMode.silent,
              ),
              false,
              reason: '$entry + $surface + fullscreen=$fullscreenAnswer 应不播',
            );
          }
        }
      }
    });
  });

  group('sessionMute 优先级最高', () {
    test('sessionMute=muted + always 模式 → 仍然不播', () {
      expect(
        decide(
          entry: AssistantEntrySource.quickVoice,
          surface: AssistantReplySurface.none,
          fullscreenAnswer: true,
          mode: TtsPlaybackMode.always,
          sessionMute: AssistantSessionMute.muted,
        ),
        false,
      );
    });

    test('sessionMute=followSettings + auto + drawerVoice → 播', () {
      expect(
        decide(
          entry: AssistantEntrySource.drawerVoice,
          surface: AssistantReplySurface.drawer,
          mode: TtsPlaybackMode.auto,
          sessionMute: AssistantSessionMute.followSettings,
        ),
        true,
      );
    });

    test('sessionMute=muted 覆盖所有模式', () {
      for (final TtsPlaybackMode mode in TtsPlaybackMode.values) {
        expect(
          decide(
            entry: AssistantEntrySource.quickVoice,
            surface: AssistantReplySurface.none,
            fullscreenAnswer: true,
            mode: mode,
            sessionMute: AssistantSessionMute.muted,
          ),
          false,
          reason: '$mode 模式 + sessionMute=muted 应不播',
        );
      }
    });
  });
}
