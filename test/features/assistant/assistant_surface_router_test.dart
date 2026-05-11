import 'package:flutter_test/flutter_test.dart';

import 'package:smart_workbench/features/assistant/application/assistant_state.dart';
import 'package:smart_workbench/features/assistant/application/assistant_surface_router.dart';

void main() {
  const LegacySurfaceRouter router = LegacySurfaceRouter();

  group('LegacySurfaceRouter', () {
    test('drawer 入口始终走抽屉', () {
      for (final AssistantEntrySource source in <AssistantEntrySource>[
        AssistantEntrySource.drawerText,
        AssistantEntrySource.drawerVoice,
      ]) {
        expect(
          router.resolve(text: '短回答', entrySource: source),
          AssistantReplySurface.drawer,
        );
        expect(
          router.resolve(
            text: '这是一段很长的回答，用来确认抽屉入口不会因为字数变化而改变现有 surface。',
            entrySource: source,
          ),
          AssistantReplySurface.drawer,
        );
      }
    });

    test('quickVoice 短答走 compactCard', () {
      expect(
        router.resolve(
          text: '现在 14:30。',
          entrySource: AssistantEntrySource.quickVoice,
        ),
        AssistantReplySurface.compactCard,
      );
    });

    test('quickVoice 超过两句走 drawer', () {
      expect(
        router.resolve(
          text: '第一句。第二句。第三句。',
          entrySource: AssistantEntrySource.quickVoice,
        ),
        AssistantReplySurface.drawer,
      );
    });

    test('quickVoice 无标点超过 72 字走 drawer', () {
      expect(
        router.resolve(
          text:
              '这是一段没有明显句末标点的长回答内容需要保持旧逻辑超过七十二个字之后不要再显示成短答卡片否则现有体验会发生变化并且继续补充一些内容确保长度真的超过阈值',
          entrySource: AssistantEntrySource.quickVoice,
        ),
        AssistantReplySurface.drawer,
      );
    });

    test('quickVoice 带句末标点且不超过 120 字走 compactCard', () {
      expect(
        router.resolve(
          text: '这是一段稍长但仍然适合短答卡展示的回答，只包含一个句末标点，长度控制在旧阈值以内。',
          entrySource: AssistantEntrySource.quickVoice,
        ),
        AssistantReplySurface.compactCard,
      );
    });
  });
}
