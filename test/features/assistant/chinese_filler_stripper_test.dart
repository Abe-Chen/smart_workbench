import 'package:flutter_test/flutter_test.dart';
import 'package:smart_workbench/features/assistant/domain/chinese_filler_stripper.dart';

void main() {
  group('stripChineseFillers', () {
    test('空字符串与纯空白', () {
      expect(stripChineseFillers(''), '');
      expect(stripChineseFillers('   '), '');
      expect(stripChineseFillers('\n\t'), '');
    });

    test('剥离前导单字 filler', () {
      expect(stripChineseFillers('嗯，确认'), '确认');
      expect(stripChineseFillers('啊好的'), '好的');
      expect(stripChineseFillers('哦，明天 3 点开会'), '明天 3 点开会');
      expect(stripChineseFillers('呃，我想想'), '我想想');
    });

    test('剥离前导多字 filler', () {
      expect(stripChineseFillers('嗯嗯，可以'), '可以');
      expect(stripChineseFillers('那个，开会'), '开会');
      expect(stripChineseFillers('就是说，明天'), '明天');
    });

    test('反复剥离堆叠 filler', () {
      expect(stripChineseFillers('嗯啊嗯，确认吧'), '确认');
      expect(stripChineseFillers('那个，那个，开会'), '开会');
      expect(stripChineseFillers('嗯嗯，那个，可以'), '可以');
    });

    test('剥离后置语气词', () {
      expect(stripChineseFillers('确认吧'), '确认');
      expect(stripChineseFillers('可以呀'), '可以');
      expect(stripChineseFillers('好的呢'), '好的');
      expect(stripChineseFillers('行哈'), '行');
    });

    test('剥离礼貌前缀', () {
      expect(stripChineseFillers('麻烦帮我建个日程'), '建个日程');
      expect(stripChineseFillers('请问明天天气'), '明天天气');
      // "我想/我要" 不剥，避免误剥"我想想"等犹豫表达
      expect(stripChineseFillers('我想确认'), '我想确认');
      expect(stripChineseFillers('帮我创建任务'), '创建任务');
    });

    test('混合：filler + 礼貌词 + 后置', () {
      expect(stripChineseFillers('嗯，麻烦帮我创建任务吧'), '创建任务');
      expect(stripChineseFillers('那个，请帮我看下明天日程呀'), '看下明天日程');
    });

    test('全是 filler 的不剥光，保留原文给上层判断', () {
      expect(stripChineseFillers('嗯'), '嗯');
      expect(stripChineseFillers('嗯嗯'), '嗯嗯');
      expect(stripChineseFillers('嗯啊嗯'), '嗯啊嗯');
      expect(stripChineseFillers('啊'), '啊');
    });

    test('不剥句中实词', () {
      expect(stripChineseFillers('开会'), '开会');
      expect(stripChineseFillers('明天 3 点开会'), '明天 3 点开会');
      expect(stripChineseFillers('需求讨论会'), '需求讨论会');
    });

    test('不误剥含有 filler 字符的实词', () {
      // "好烦" 不是 filler，开头"好"也不在剥离列表
      expect(stripChineseFillers('好烦'), '好烦');
      // "对了" 整体保留（"对"不在 leading list；"了"不在 trailing list）
      expect(stripChineseFillers('对了'), '对了');
      // "那是"——"那"是前导 filler，剥后"是"
      expect(stripChineseFillers('那是'), '是');
      // "就开会"——"就"是前导 filler，剥后"开会"
      expect(stripChineseFillers('就开会'), '开会');
    });

    test('全角与半角标点都能剥', () {
      expect(stripChineseFillers('嗯，确认。'), '确认');
      expect(stripChineseFillers('嗯, 确认.'), '确认');
      expect(stripChineseFillers('嗯！确认？'), '确认');
    });

    test('leadingOnly = true 不剥后置', () {
      expect(stripChineseFillers('嗯确认吧', leadingOnly: true), '确认吧');
      expect(stripChineseFillers('开会呢', leadingOnly: true), '开会呢');
    });

    test('用户偏好 confirm/cancel 真实场景', () {
      // 这些后续会被 confirm 识别接住
      expect(stripChineseFillers('嗯，确认'), '确认');
      // 句中标点+词不剥（confirm 识别会用 contains 模式接住）
      expect(stripChineseFillers('好的，确认'), '好的，确认');
      // "对" 不是 filler 不剥，confirm 识别会用 contains 接住
      expect(stripChineseFillers('对，是这样'), '对，是这样');
      expect(stripChineseFillers('嗯啊好的'), '好的');
      expect(stripChineseFillers('啊不用'), '不用');
      expect(stripChineseFillers('嗯算了吧'), '算了');
      expect(stripChineseFillers('那不要了'), '不要了');
    });

    test('日程标题污染场景', () {
      // 这些后续会被 slots/模型接住，title 不应当含 filler
      expect(
        stripChineseFillers('嗯，明天下午 3 点开会'),
        '明天下午 3 点开会',
      );
      expect(
        stripChineseFillers('那个，帮我加个明天的会议'),
        '加个明天的会议',
      );
    });
  });

  group('isOnlyFillers', () {
    test('纯 filler 返回 true', () {
      expect(isOnlyFillers('嗯'), true);
      expect(isOnlyFillers('嗯嗯'), true);
      expect(isOnlyFillers('啊'), true);
      expect(isOnlyFillers('嗯，啊。'), true);
    });

    test('含实词返回 false', () {
      expect(isOnlyFillers('确认'), false);
      expect(isOnlyFillers('嗯确认'), false);
      expect(isOnlyFillers('开会'), false);
    });
  });
}
