import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smart_workbench/features/assistant/domain/assistant_result_card.dart';
import 'package:smart_workbench/features/assistant/presentation/widgets/assistant_result_card_view.dart';

void main() {
  group('news card', () {
    test('解析模型输出的 news assistant-card', () {
      const String raw =
          '今天重点看两条科技新闻。'
          '<assistant-card type="news">{"title":"今日科技新闻",'
          '"summary":"AI 芯片和大模型应用是主要焦点。",'
          '"updatedAt":"刚刚",'
          '"items":[{"title":"新一代 AI 芯片发布","source":"新华社",'
          '"timeLabel":"今天","summary":"新品强调端侧推理能力。"}],'
          '"sourceNote":"以各媒体最新报道为准"}</assistant-card>';

      final AssistantDisplayContent content = parseAssistantDisplayContent(raw);

      expect(content.text, '今天重点看两条科技新闻。');
      expect(content.resultCard, isA<NewsCard>());
      final NewsCard card = content.resultCard! as NewsCard;
      expect(card.title, '今日科技新闻');
      expect(card.items.single.title, '新一代 AI 芯片发布');
      expect(card.items.single.source, '新华社');
    });

    testWidgets('渲染新闻标题、来源和摘要', (WidgetTester tester) async {
      const NewsCard card = NewsCard(
        title: '今日科技新闻',
        summary: 'AI 芯片和大模型应用是主要焦点。',
        updatedAt: '刚刚',
        sourceNote: '以各媒体最新报道为准',
        items: <NewsItem>[
          NewsItem(
            title: '新一代 AI 芯片发布',
            source: '新华社',
            timeLabel: '今天',
            summary: '新品强调端侧推理能力。',
          ),
        ],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AssistantResultCardView(card: card)),
        ),
      );

      expect(find.text('今日科技新闻'), findsOneWidget);
      expect(find.text('新一代 AI 芯片发布'), findsOneWidget);
      expect(find.text('新华社 · 今天'), findsOneWidget);
    });
  });
}
