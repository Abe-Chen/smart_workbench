import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smart_workbench/core/utils/task_formatters.dart';
import 'package:smart_workbench/features/assistant/data/tools/_task_tool_helpers.dart';
import 'package:smart_workbench/features/assistant/data/tools/create_task_tool.dart';
import 'package:smart_workbench/features/assistant/domain/assistant_confirm_preview.dart';

void main() {
  group('task tool args 解析', () {
    test('parseTaskDate 支持斜杠日期', () {
      final DateTime? value = parseTaskDate('2026/05/09');
      expect(value, isNotNull);
      expect(formatStorageDate(value!), '2026-05-09');
    });

    test('parseTaskTimeMinutes 支持 HH:MM / 数字 / 上下限钳制', () {
      expect(parseTaskTimeMinutes('09:30'), 570);
      expect(parseTaskTimeMinutes('75'), 75);
      expect(parseTaskTimeMinutes(1600), 1440);
      expect(parseTaskTimeMinutes(-5), 0);
    });

    test('parseBool 兼容常见字符串', () {
      expect(parseBool('true'), true);
      expect(parseBool('0'), false);
      expect(parseBool('yes'), true);
      expect(parseBool('unknown'), isNull);
    });
  });

  group('create_task preview', () {
    test('能生成确认卡并带出提醒、重复与时间', () async {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      final DateTime target = DateTime.now().add(const Duration(days: 1));
      final AssistantConfirmPreview? preview = await container
          .read(createTaskToolProvider)
          .buildConfirmPreview(<String, dynamic>{
            'title': '客户拜访',
            'start_date': formatStorageDate(target),
            'is_all_day': false,
            'start_time_minutes': '15:30',
            'end_time_minutes': 990,
            'reminder_key': 'before10m',
            'repeat_key': 'weekly',
          });

      expect(preview, isNotNull);
      expect(preview!.title, '准备创建');
      expect(
        preview.rows.any(
          (ConfirmRow row) => row.label == '标题' && row.value == '客户拜访',
        ),
        true,
      );
      expect(
        preview.rows.any(
          (ConfirmRow row) =>
              row.label == '时间' &&
              row.highlighted &&
              row.value.contains('15:30') &&
              row.value.contains('16:30'),
        ),
        true,
      );
      expect(
        preview.rows.any(
          (ConfirmRow row) => row.label == '提醒' && row.value == '提前 10 分钟',
        ),
        true,
      );
      expect(
        preview.rows.any(
          (ConfirmRow row) => row.label == '重复' && row.value == '每周',
        ),
        true,
      );
    });

    test('关键字段缺失时返回参数缺失提示', () async {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      final AssistantConfirmPreview? preview = await container
          .read(createTaskToolProvider)
          .buildConfirmPreview(<String, dynamic>{'start_date': '2026-05-09'});

      expect(preview, isNotNull);
      expect(preview!.title, '信息没识别完整');
      expect(preview.rows.single.label, '提示');
    });
  });
}
