# NLU 中文语气词剥离方案

最近更新：2026-05-11。
状态：**P0 已落地**，自动化测试 145/145 全绿，真机验证通过。

## 用户反馈（截图复盘）

会话流程：
```
[助理] 我理解是这样。确认后我就放到日程里。
[用户] 提前 10 分钟提醒我。
[助理] 要给「需求讨论会」加上提前 10 分钟提醒吗？
[用户] 嗯，确认。              ← 没识别为 confirm
[助理] 「需求讨论会」还没放进日程。要继续的话说"确认"，不创建就说"取消"。
[用户] 确认。                   ← 才识别
[助理] 好的，提醒设置好了。
```

附带反馈：**创建日程时，"嗯"等语气词会被带入 title**。

## 根因诊断

整个 NLU 链路**没有"语气词预处理"层**。原始 ASR 文本（带"嗯/啊/哦/那个"等口语化语气词）直接进入业务逻辑，污染了 3 个地方：

| 受影响的点 | 之前 | 现象 |
|---|---|---|
| ① confirm/cancel/close 识别 | 正则 `^(确认\|可以\|...\|嗯)$` 严格锚定，没剥离前后语气词 | "嗯，确认" → unknown |
| ② 本地 slots 抽取（路由判断） | `_extractScheduleTitle` 只 trim 尾部 `的/了/，/。`，不剥前导 | 路由判断带"嗯" |
| ③ 传给模型的原始文本 | controller 把 `"嗯，明天 3 点开会"` 直接喂给豆包 | **模型把"嗯"写进 title** |

## 解决方案

### 核心：建立 `ChineseFillerStripper` 工具，三个入口共用

`lib/features/assistant/domain/chinese_filler_stripper.dart`

**剥离规则**：
- 前导语气词列表：嗯 / 嗯嗯 / 嗯嗯啊 / 啊 / 哦 / 哦哦 / 呃 / 哎 / 诶 / 那 / 那个 / 那么 / 就 / 就是 / 就是说
- 后置语气词列表：吧 / 呀 / 呢 / 嘛 / 哈 / 啊 / 哦 / 哟
- 礼貌前缀列表：麻烦 / 麻烦你 / 帮我 / 帮个忙 / 辛苦 / 辛苦你 / 请问 / 请你 / 请
- **故意不收录"我想 / 我要"**：避免误剥"我想想"等犹豫表达
- **保留全是 filler 的原文**（如单独"嗯" → "嗯"），让上层判定为单字 confirm

**反复剥离直到稳定**：处理"嗯啊嗯，那个，请帮我开会吧" → "开会"

### confirm/cancel/close 识别架构升级

`assistant_controller.dart` 的 `_parsePendingConfirmInput` 改为 4 层判定：

```
1. _normalizeForIntentMatch(text)
   = stripChineseFillers(text) + 去标点空白
2. 显式否定 + confirm 关键词（"不确认" / "不可以" / "不行"）→ cancel
3. cancel/close 关键词 contains（"算了" / "不用" / "就这样"）→ cancel
4. confirm 单字白名单完全相等（对/是/好/行/嗯/嗯嗯/嗯啊/嗯哼）→ confirm
5. confirm 多字关键词 contains（确认/确定/可以/好的/没错/是的/对的/执行/创建/...）→ confirm
6. 都不匹配 → unknown
```

**关键设计点**：
- 单字关键词必须**完全相等**：避免"好烦"误判 confirm（"好"在白名单但不等于"好烦"）
- 多字关键词允许 **contains**：让"嗯，确认" 剥离后 "确认" 命中
- **cancel 优先于 confirm**：避免"不要确认"被误判 confirm
- 显式否定模式 `^(不|别|不要|不想)(确认|可以|好的|执行|...|行|是|对|要)` 锚定开头，避免"我不行"误匹配

### Slots 抽取接入

`assistant_slots.dart` 的 `AssistantSlots.from(text)` 入口：
```dart
final String t = stripChineseFillers(text, leadingOnly: true).trim();
```
`leadingOnly: true` 是因为某些 slot 抽取依赖句尾词，不剥后置。

### sendUserMessage 入口接入

`assistant_controller.dart` 的 `sendUserMessage`：
```dart
final String original = text.trim();
final String stripped = stripChineseFillers(original).trim();
final String trimmed = stripped.isEmpty ? original : stripped;
```
全是 filler 时（用户只说"嗯"）保留原文，让上层判定为单字 confirm。

效果：
- 历史 `messages.content` 是清理后文本（用户在 ChatHistory UI 看到的也是清理后的）
- 传给模型的 user 消息也是清理后
- router 判断、slots 抽取、confirm 识别全部拿到干净文本

### Prompt 双保险

`system_prompt.dart` 加段：
```
语音输入清理：
- 用户的输入可能来自语音识别，常带"嗯/啊/哦/呃/哎/那个/就是/麻烦/请/帮我"等口语化语气词与礼貌前缀。理解时**忽略**这些词，不要写进任何工具参数。
- 例：用户说"嗯，明天下午3点开会"，create_task 的 title 应是"开会"，不要写成"嗯开会"。
- 例：用户说"嗯，确认"，理解为确认意图，不需要再追问"是不是要确认"。
```

前端剥离 + Prompt 提示双保险，模型即便偶尔不听话也有前端兜底。

## 测试覆盖

### 工具单测（`chinese_filler_stripper_test.dart`，16 个）

| 类别 | 覆盖 |
|---|---|
| 空字符串、纯空白 | 3 case |
| 前导单字 filler | 4 case |
| 前导多字 filler | 3 case |
| 反复剥离堆叠 filler | 3 case |
| 后置语气词 | 4 case |
| 礼貌前缀 | 4 case |
| 混合 + 后置 | 2 case |
| 全是 filler 不剥光 | 4 case |
| 不剥句中实词 | 3 case |
| 不误剥含 filler 字符的实词（"好烦" / "对了" / "那是"） | 4 case |
| 全角与半角标点 | 3 case |
| `leadingOnly = true` 不剥后置 | 2 case |
| confirm/cancel 真实场景 | 7 case |
| 日程标题污染场景 | 2 case |
| `isOnlyFillers` | 2 case |

### 全量回归

flutter analyze: No issues found
flutter test: **145 / 145 passed**（其中 16 个为本次新增 stripper 单测）

## 修复后效果（对照表）

| 用户说 | 修复前 | 修复后 |
|---|---|---|
| 嗯，确认 | unknown → 反问 | confirm → 直接执行 |
| 好的，确认 | unknown | confirm |
| 嗯啊好的 | unknown | confirm |
| 确认吧 | unknown | confirm |
| 嗯啊嗯，可以 | unknown | confirm |
| 不确认 | unknown | cancel |
| 不可以 | unknown | cancel |
| 嗯算了吧 | unknown | cancel |
| **"好烦"** | unknown（侥幸正确） | unknown（设计保证）|
| **"我想想"** | unknown | unknown（不误剥成"想"）|
| **"嗯，明天下午 3 点开会"** | title 含"嗯" | title = "开会" |

## 关联代码位置

- `lib/features/assistant/domain/chinese_filler_stripper.dart` — 工具类（新建）
- `test/features/assistant/chinese_filler_stripper_test.dart` — 单测（新建）
- `lib/features/assistant/domain/assistant_slots.dart` — `from(text)` 接入
- `lib/features/assistant/application/assistant_controller.dart` — `sendUserMessage` 入口 + `_parsePendingConfirmInput` 4 层判定 + `_isCancelOrCloseInput` / `_isConversationCloseInput` 接入 + 正则常量重写
- `lib/features/assistant/prompts/system_prompt.dart` — 加「语音输入清理」段

## 推迟项

| 项 | 原因 |
|---|---|
| confirm 多字关键词扩展（同意 / 没问题 / 行的） | 等真实用户语料反馈再加，避免无限扩展 |
| 双重否定（"不取消"）| 罕见 case，先不处理 |
| 重叠收敛（"行行行" / "好好好"）| 边界优化，第一版不做 |
| 用户名/品牌名含 filler 字（如"嗯哥"）| 不在 NLU 入口出现，模型层兜底 |
