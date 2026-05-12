import 'package:flutter_test/flutter_test.dart';

import 'package:smart_workbench/features/assistant/application/assistant_state.dart';
import 'package:smart_workbench/features/assistant/application/assistant_surface_router.dart';

void main() {
  const AssistantSurfaceRouter router = AssistantSurfaceRouter();

  group('AssistantSurfaceRouter', () {
    test('抽屉入口始终走抽屉', () {
      for (final AssistantEntrySource source in <AssistantEntrySource>[
        AssistantEntrySource.drawerText,
        AssistantEntrySource.drawerVoice,
      ]) {
        expect(
          router.resolve(entrySource: source, drawerOpen: false),
          AssistantReplySurface.drawer,
        );
        expect(
          router.shouldUseFullscreenAnswer(
            entrySource: source,
            drawerOpen: false,
          ),
          isFalse,
        );
      }
    });

    test('抽屉关闭时 quickVoice 走全屏大卡，不再按字数切抽屉', () {
      expect(
        router.resolve(
          entrySource: AssistantEntrySource.quickVoice,
          drawerOpen: false,
        ),
        AssistantReplySurface.none,
      );
      expect(
        router.shouldUseFullscreenAnswer(
          entrySource: AssistantEntrySource.quickVoice,
          drawerOpen: false,
        ),
        isTrue,
      );
    });

    test('抽屉已打开时 quickVoice 也留在抽屉会话', () {
      expect(
        router.resolve(
          entrySource: AssistantEntrySource.quickVoice,
          drawerOpen: true,
        ),
        AssistantReplySurface.drawer,
      );
      expect(
        router.shouldUseFullscreenAnswer(
          entrySource: AssistantEntrySource.quickVoice,
          drawerOpen: true,
        ),
        isFalse,
      );
    });
  });
}
