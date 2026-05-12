import 'package:flutter_test/flutter_test.dart';

import 'package:smart_workbench/features/assistant/domain/assistant_speech_text.dart';

void main() {
  group('assistant speech text', () {
    test('摘要播报不会把新闻编号 1. 当作完整句子', () {
      final String speech = buildAssistantSpeechText(
        '核心内容如下：1. 第一条新闻有明确进展。2. 第二条新闻也值得关注。',
      );

      expect(speech, isNot('核心内容如下：1.'));
      expect(speech, contains('第1条'));
      expect(speech, contains('第一条新闻'));
    });

    test('完整播报会保留全文并移除 assistant-card block', () {
      final String speech = buildAssistantSpeechText(
        '核心内容如下：1. 第一条。2. 第二条。'
        '<assistant-card type="news">{"title":"新闻","items":[]}</assistant-card>',
        mode: AssistantSpeechMode.full,
      );

      expect(speech, contains('第1条'));
      expect(speech, contains('第2条'));
      expect(speech, isNot(contains('assistant-card')));
    });

    test('识别完整播报类本地语音指令', () {
      expect(isAssistantFullReadoutRequest('全部播报一遍'), isTrue);
      expect(isAssistantFullReadoutRequest('你把刚才内容完整读一下'), isTrue);
      expect(isAssistantFullReadoutRequest('继续朗读'), isTrue);
      expect(isAssistantFullReadoutRequest('第一条'), isFalse);
      expect(isAssistantFullReadoutRequest('继续说一下方案'), isFalse);
    });
  });
}
