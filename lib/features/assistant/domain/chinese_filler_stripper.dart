// 中文口语语气词剥离工具。
//
// 设计目标：把 ASR 文本里的"嗯/啊/哦/那个"等口语化语气词剥掉，
// 让下游 NLU（confirm 识别 / slots 抽取 / 模型理解）拿到干净文本。
//
// 例：
//   "嗯，明天下午 3 点开会" → "明天下午 3 点开会"
//   "麻烦帮我创建一个日程" → "创建一个日程"
//   "嗯啊，那个，确认吧" → "确认"
//
// 边界：
// - 完全由 filler 组成的文本（如 "嗯" / "嗯啊嗯"）保留不剥光，
//   下游可以自行判断"是不是只有语气词"
// - 不剥句中实词，避免"我想开会"被误剥成"开会"丢失主语

/// 前导语气词。出现在文本开头时剥掉。
const List<String> kLeadingFillers = <String>[
  // 重叠词放前面（更长的优先匹配）
  '嗯嗯啊', '嗯嗯',
  '哦哦', '啊啊',
  '那个', '那么',
  '就是说', '就是',
  // 单字
  '嗯', '啊', '哦', '呃', '哎', '诶',
  '那', '就',
];

/// 后置语气词。出现在文本结尾时剥掉。
const List<String> kTrailingFillers = <String>[
  '吧', '呀', '呢', '嘛', '哈', '啊', '哦', '哟',
];

/// 礼貌前缀。剥前导语气词后，若仍以这些词开头继续剥。
///
/// 不收录"我想 / 我要"——这些词在"我想想"等犹豫表达里会被误剥成"想"。
/// 这一类用户输入由模型层兜底理解。
const List<String> kPolitenessFillers = <String>[
  '麻烦你', '麻烦',
  '帮我', '帮个忙',
  '辛苦你', '辛苦',
  '请问', '请你', '请',
];

/// 剥离首尾语气词与礼貌前缀。
///
/// [leadingOnly] = true 时只剥前导（slots 抽取场景，避免误剥实词尾部）。
String stripChineseFillers(String text, {bool leadingOnly = false}) {
  String s = text.trim();
  if (s.isEmpty) return s;

  // 反复剥离，直到稳定。每轮：标点 → 前导 filler → 礼貌词 → （可选）后置 filler
  String prev;
  do {
    prev = s;
    s = _stripLeadingPunctuation(s);
    s = _stripFromList(s, kLeadingFillers, leading: true);
    s = _stripLeadingPunctuation(s);
    s = _stripFromList(s, kPolitenessFillers, leading: true);
    s = _stripLeadingPunctuation(s);
    if (!leadingOnly) {
      s = _stripTrailingPunctuation(s);
      s = _stripFromList(s, kTrailingFillers, leading: false);
      s = _stripTrailingPunctuation(s);
    }
  } while (s != prev && s.isNotEmpty);

  // 全空了说明原文几乎全是 filler — 还原原文，让上层决定怎么处理
  // （单独"嗯"是合法 confirm 词，不能剥光）
  if (s.isEmpty) return text.trim();
  return s;
}

/// 完全等价于"内容只有语气词/标点/空白"。
bool isOnlyFillers(String text) {
  final String stripped = stripChineseFillers(text);
  return stripped == text.trim() && _isAllFillerChars(text.trim());
}

bool _isAllFillerChars(String s) {
  if (s.isEmpty) return false;
  // 把所有可能的 filler 字符删掉，剩下是不是空白
  String t = s;
  for (final String f in kLeadingFillers) {
    t = t.replaceAll(f, '');
  }
  for (final String f in kTrailingFillers) {
    t = t.replaceAll(f, '');
  }
  t = t.replaceAll(RegExp(r'[，。！？,.!?\s、；;:：]'), '');
  return t.isEmpty;
}

String _stripLeadingPunctuation(String s) {
  return s.replaceFirst(RegExp(r'^[，。！？,.!?\s、；;:：]+'), '');
}

String _stripTrailingPunctuation(String s) {
  return s.replaceFirst(RegExp(r'[，。！？,.!?\s、；;:：]+$'), '');
}

String _stripFromList(String s, List<String> list, {required bool leading}) {
  for (final String token in list) {
    if (leading) {
      if (s.startsWith(token)) {
        return s.substring(token.length);
      }
    } else {
      if (s.endsWith(token)) {
        return s.substring(0, s.length - token.length);
      }
    }
  }
  return s;
}
