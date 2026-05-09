import 'package:flutter_test/flutter_test.dart';

import 'package:smart_workbench/features/assistant/application/assistant_copywriter.dart';
import 'package:smart_workbench/features/assistant/application/assistant_state.dart';
import 'package:smart_workbench/features/assistant/domain/assistant_confirm_preview.dart';
import 'package:smart_workbench/features/assistant/domain/tool_call.dart';

void main() {
  group('AssistantCopywriter', () {
    const AssistantCopywriter copywriter = AssistantCopywriter();

    test('缺少全部创建字段时，用自然语言引导补充', () {
      expect(
        copywriter.missingWriteDraft(
          const AssistantPendingWriteDraft(
            kind: AssistantWriteDraftKind.schedule,
          ),
        ),
        '可以。这个日程是什么，安排在什么时候？',
      );
    });

    test('已有标题但缺时间时，只追问缺失部分', () {
      expect(
        copywriter.missingWriteDraft(
          AssistantPendingWriteDraft(
            kind: AssistantWriteDraftKind.schedule,
            title: '需求讨论会',
            startDate: DateTime(2026, 5, 9),
          ),
        ),
        '「需求讨论会」我记下了。几点开始？',
      );
    });

    test('缺标题时不泄漏固定示例', () {
      final String text = copywriter.missingWriteDraft(
        AssistantPendingWriteDraft(
          kind: AssistantWriteDraftKind.schedule,
          startDate: DateTime.now().add(const Duration(days: 1)),
          startTimeMinutes: 15 * 60,
        ),
      );

      expect(text, contains('这条日程叫什么'));
      expect(text, isNot(contains('需求讨论会')));
      expect(text, isNot(contains('标题')));
    });

    test('创建成功文案不使用系统日志式冒号', () {
      final AssistantPendingConfirm pending = AssistantPendingConfirm(
        toolCall: ToolCall(
          id: 'call_1',
          name: 'create_task',
          argumentsJson: '{"reminder_key":"none"}',
        ),
        preview: const AssistantConfirmPreview(
          title: '准备创建',
          rows: <ConfirmRow>[
            ConfirmRow(label: '标题', value: '需求讨论会'),
            ConfirmRow(label: '时间', value: '明天 15:00'),
          ],
        ),
      );

      expect(
        copywriter.confirmedCreateResult(
          pending: pending,
          result: <String, dynamic>{'ok': true, 'title': '需求讨论会'},
        ),
        '好的，已经放到日程里了。明天 15:00「需求讨论会」。',
      );
    });

    test('创建失败时说明原因，但不误报成功', () {
      final AssistantPendingConfirm pending = AssistantPendingConfirm(
        toolCall: ToolCall(
          id: 'call_2',
          name: 'create_task',
          argumentsJson: '{"reminder_key":"none"}',
        ),
        preview: const AssistantConfirmPreview(
          title: '准备创建',
          rows: <ConfirmRow>[ConfirmRow(label: '标题', value: '需求讨论会')],
        ),
      );

      final String text = copywriter.confirmedCreateResult(
        pending: pending,
        result: <String, dynamic>{'ok': false, 'reason': '缺少必要字段'},
      );

      expect(text, '这次没创建成功：缺少必要字段。你可以稍后再试，或者换个说法重新创建。');
      expect(text, isNot(contains('已创建')));
    });

    test('修改成功文案不依赖模型总结', () {
      final AssistantPendingConfirm pending = AssistantPendingConfirm(
        toolCall: ToolCall(
          id: 'call_3',
          name: 'update_task',
          argumentsJson: '{"task_id":1}',
        ),
        preview: const AssistantConfirmPreview(
          title: '准备修改',
          rows: <ConfirmRow>[ConfirmRow(label: '标题', value: '旧会议 → 新会议')],
        ),
      );

      expect(
        copywriter.confirmedWriteResult(
          pending: pending,
          result: <String, dynamic>{'ok': true, 'title': '新会议'},
        ),
        '好的，改好了。',
      );
    });

    test('删除确认态追问带出操作对象', () {
      final AssistantPendingConfirm pending = AssistantPendingConfirm(
        toolCall: ToolCall(
          id: 'call_4',
          name: 'delete_task',
          argumentsJson: '{"task_id":1}',
        ),
        preview: const AssistantConfirmPreview(
          title: '准备删除',
          rows: <ConfirmRow>[ConfirmRow(label: '标题', value: '旧会议')],
        ),
      );

      expect(
        copywriter.pendingConfirmUnknown(pending),
        '「旧会议」还没删。确认删除就说“确认”，不删就说“取消”。',
      );
      expect(copywriter.confirmCancelled(pending), '好，这次先不删除。');
    });

    test('查询结果有自然摘要', () {
      final String text = copywriter.queryTasksResult(<String, dynamic>{
        'ok': true,
        'tasks': <Map<String, Object?>>[
          <String, Object?>{
            'title': '需求讨论会',
            'date': '2026-05-09',
            'time': '15:00 - 16:00',
          },
          <String, Object?>{'title': '写周报', 'date': '2026-05-09', 'time': '全天'},
        ],
      });

      expect(text, contains('有 2 个安排'));
      expect(text, contains('- 15:00 - 16:00 需求讨论会'));
      expect(text, contains('- 全天 写周报'));
      expect(text, isNot(contains('查到 2 条')));
    });

    test('标记完成结果提醒可撤销', () {
      expect(
        copywriter.completedTaskResult(<String, dynamic>{
          'ok': true,
          'title': '写周报',
        }),
        '已把「写周报」标记完成。刚才这一步可以撤销。',
      );
    });
  });
}
