import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smart_workbench/features/assistant/application/assistant_surface_router.dart';
import 'package:smart_workbench/features/assistant/domain/assistant_result_card.dart';
import 'package:smart_workbench/features/assistant/presentation/widgets/answer_cards/answer_card_models.dart';
import 'package:smart_workbench/features/assistant/presentation/widgets/full_screen_answer_card.dart';

void main() {
  group('FullScreenAnswerCard', () {
    testWidgets('渲染信息卡形态', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          const FullScreenAnswerCard(
            kind: AnswerCardKind.infoCard,
            message: '出门带把薄外套。',
            resultCard: WeatherCard(
              title: '上海',
              subtitle: '多云',
              summary: '出门带把薄外套。',
              headline: '24°',
              secondaryHeadline: '18-27°',
            ),
          ),
        ),
      );

      expect(find.text('小治整理好了'), findsOneWidget);
      expect(find.text('上海'), findsWidgets);
      expect(find.text('24°'), findsOneWidget);
    });

    testWidgets('渲染工具反馈形态', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          const FullScreenAnswerCard(
            kind: AnswerCardKind.toolFeedback,
            toolFeedback: ToolFeedbackCardData(
              title: '已加到日程',
              subtitle: '确认后我会提醒你',
              rows: <ToolFeedbackRow>[
                ToolFeedbackRow(label: '时间', value: '5月12日 15:00'),
              ],
              undoLabel: '撤销',
            ),
          ),
        ),
      );

      expect(find.text('操作完成'), findsOneWidget);
      expect(find.text('已加到日程'), findsOneWidget);
      expect(find.text('撤销'), findsOneWidget);
    });

    testWidgets('渲染纯文字形态', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          const FullScreenAnswerCard(
            kind: AnswerCardKind.plainText,
            message: '14:30',
          ),
        ),
      );

      expect(find.text('小治回答'), findsOneWidget);
      expect(find.text('14:30'), findsOneWidget);
    });

    testWidgets('渲染澄清形态', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          const FullScreenAnswerCard(
            kind: AnswerCardKind.clarification,
            message: '这个会议是几点？',
          ),
        ),
      );

      expect(find.text('需要补充'), findsOneWidget);
      expect(find.text('这个会议是几点？'), findsOneWidget);
      expect(find.text('我在听...'), findsOneWidget);
    });

    testWidgets('渲染确认形态 fallback', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(const FullScreenAnswerCard(kind: AnswerCardKind.confirm)),
      );

      expect(find.text('等你确认'), findsWidgets);
    });

    testWidgets('渲染错误形态', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          const FullScreenAnswerCard(
            kind: AnswerCardKind.error,
            message: '没拿到稳定的天气信息',
          ),
        ),
      );

      expect(find.text('遇到问题'), findsOneWidget);
      expect(find.text('没成功'), findsOneWidget);
      expect(find.text('没拿到稳定的天气信息'), findsOneWidget);
    });

    testWidgets('渲染提醒形态', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          const FullScreenAnswerCard(
            kind: AnswerCardKind.reminder,
            reminder: ReminderCardData(
              title: '需求讨论会',
              timeLabel: '现在开始',
              subtitle: '5月12日 15:00',
            ),
          ),
        ),
      );

      expect(find.text('提醒'), findsWidgets);
      expect(find.text('需求讨论会'), findsOneWidget);
      expect(find.text('已读'), findsOneWidget);
      expect(find.text('稍后'), findsOneWidget);
      expect(find.text('关闭'), findsWidgets);
    });
  });
}

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SizedBox.expand(child: child)),
  );
}
