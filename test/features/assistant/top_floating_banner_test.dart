import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smart_workbench/features/assistant/presentation/widgets/top_floating_banner.dart';

void main() {
  group('TopFloatingBanner', () {
    testWidgets('渲染听音 partial 形态', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          const TopFloatingBanner(
            kind: TopBannerKind.listenPartial,
            message: '上海今天天气怎么样',
            remainingMs: 3000,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('在听...'), findsOneWidget);
      expect(find.text('上海今天天气怎么样'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('渲染推送 banner 形态并支持展开', (WidgetTester tester) async {
      bool expanded = false;

      await tester.pumpWidget(
        _wrap(
          TopFloatingBanner(
            kind: TopBannerKind.pushNotification,
            title: '还有 3 件事',
            message: '下午 3 点需求讨论会，再过 30 分钟',
            onExpand: () => expanded = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('还有 3 件事'), findsOneWidget);
      expect(find.text('下午 3 点需求讨论会，再过 30 分钟'), findsOneWidget);

      await tester.tap(find.text('展开'));
      expect(expanded, isTrue);
    });
  });
}

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: Stack(children: <Widget>[child])),
  );
}
