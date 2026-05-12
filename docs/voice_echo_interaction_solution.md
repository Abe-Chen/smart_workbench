# 语音回显与大卡交互方案

最近更新：2026-05-12。
状态：已实施，待真机回归。
关联：`assistant_interaction_dev_plan.md`、`voice_endpointing_strategy.md`、`nlu_filler_stripper.md`。

## 1. 背景

助手交互迁到全屏大卡后，确认、澄清、提醒和信息卡更适合 PZ200 这类桌面横屏设备。但大卡显示时用户继续说话，如果页面没有显示用户说了什么，会造成两个问题：

- 用户不知道小治是否真的在听。
- 用户不知道小治听到/理解的是不是刚才那句话。

之前曾考虑用顶部浮窗显示 ASR partial。后来为了减少视觉焦点跳动，决定不恢复顶部 listen 浮窗，而是保留底部语音回显能力，并把它补齐到全屏大卡场景。

## 2. 最终结论

不恢复顶部 listen 浮窗。顶部 banner 只保留给系统推送、主动建议等被动信息。

最终实现采用：

> **中间是大卡，底部是固定语音 Dock。大卡负责任务内容，Dock 负责用户语音回显。**

| 当前场景 | 语音回显位置 | 说明 |
|---|---|---|
| Dashboard 空闲 | 底部球附近 `VoiceEchoBar` | 用户焦点在小治球，轻量显示 |
| 抽屉打开 | 抽屉内 `VoiceEchoBar` | 沉浸对话，回显跟随聊天上下文 |
| 全屏大卡打开 | 屏幕下方固定 `VoiceEchoBar` Dock | 中间区域留给大卡，底部显示用户语音 |
| 顶部 banner | 不显示用户语音 | 仅用于主动建议/系统推送 |

关键取舍：

- 不把用户语音塞进大卡内部。实测会让大卡内容和用户回显混在一起，视觉和语义都不自然。
- 不让悬浮球承担倒计时视觉。倒计时只在回显条中出现，避免用户看到多处倒计时。
- 不把回显写入聊天历史。它是当前语音回合的临时确认状态。

## 3. 交互原则

### 3.1 倒计时只代表“等待开口”

open mic 倒计时不是用户说话时长限制，而是“等待用户开始说话”的提示。

规则：

- 还没检测到用户开口：显示倒计时。
- 用户一开口：立即停倒计时。
- 用户说话中：继续录音，等待讯飞 VAD/final。
- 完全没有开口信号且等待窗口结束：显示“这次没听到你说话”。

开口信号来源：

- 实际送给讯飞的 PCM 音频帧连续达到阈值。
- 讯飞返回非空 partial。

任一信号命中，就进入“已开口”状态，只停止等待倒计时，不停止录音、不取消业务执行。

### 3.2 partial 只能表示“识别中”

讯飞 IAT 的 partial 可能延迟、为空或被后续结果修正，所以 UI 不能把 partial 当成最终文本。

规则：

- partial：显示“识别中：xxx”。
- final 原文可直接使用：显示“听到：xxx”。
- final 被唤醒词/语气词清理过：显示“我理解为：xxx”。
- 开始处理业务：显示“正在处理：xxx”。

### 3.3 大卡和语音 Dock 各司其职

全屏大卡负责任务主内容：

- 信息卡
- 澄清问题
- 确认卡
- 工具反馈
- 提醒卡
- 错误卡

底部语音 Dock 负责用户当前语音回合：

- 正在听
- 识别中
- 已识别/已理解
- 正在处理
- 识别异常
- 取消入口

## 4. UI 方案

统一组件：`VoiceEchoBar`。

### 4.1 底部 Dock

全屏大卡显示时，如果 `state.voiceEcho.isVisible`，在屏幕底部展示固定 Dock：

- 左右边距：16
- 最大宽度：680
- 底部位置：避开底部导航栏或键盘
- 大卡通过 `bottomReservedSpace` 给 Dock 预留空间

这样可以保证：

- 大卡不会遮住用户语音回显。
- 回显不会挤压大卡主内容。
- 用户视觉上能清楚区分“助手内容”和“我刚说的话”。

### 4.2 视觉风格

`VoiceEchoBar` 采用轻量玻璃态：

- 半透明白底
- 轻边框
- 小状态图标
- 状态标签 + 文本主体
- 文本最多 1-2 行，全部 `maxLines + overflow`

倒计时只在以下条件同时满足时显示：

- phase 为 `listening`
- 还没有 partial 文本
- `remainingMs > 0`

用户已经说话后，不再显示倒计时。

## 5. 状态模型

已新增 `AssistantVoiceEchoState`：

```dart
enum AssistantVoiceEchoPhase {
  hidden,
  listening,
  finalText,
  processing,
  error,
}

class AssistantVoiceEchoState {
  const AssistantVoiceEchoState({
    required this.phase,
    this.partialText = '',
    this.finalText = '',
    this.rawFinalText = '',
    this.displayText = '',
    this.cleaned = false,
    this.remainingMs = 0,
  });
}
```

字段含义：

| 字段 | 含义 |
|---|---|
| `partialText` | ASR 实时识别文本，只用于“识别中” |
| `rawFinalText` | ASR final 原文 |
| `finalText` | 去唤醒词/语气词后的业务输入 |
| `displayText` | 当前 UI 展示文案 |
| `cleaned` | 清理前后不同时为 true |
| `remainingMs` | 等待开口倒计时，只在未开口时展示 |

## 6. 生命周期

### 6.1 开始听

`startListening`：

- 清掉上一轮 echo hide timer。
- phase = `listening`。
- 文案显示“我在听，你可以直接说”。
- open mic 模式启动等待开口倒计时。

### 6.2 检测到用户开口

触发来源：

- PCM 音频帧能量连续达到阈值。
- ASR partial 非空。

处理：

- `_heardSpeechInCurrentOpenMic = true`
- 停止 open mic 等待倒计时。
- `listenWindowRemainingMs = 0`
- `voiceEcho.remainingMs = 0`
- 录音和 ASR 继续运行。

### 6.3 partial 更新

`AsrPartialEvent`：

- 更新 `partialText`
- phase 保持 `listening`
- UI 显示“识别中：xxx”
- 不触发业务逻辑

### 6.4 final 到达

`AsrFinalEvent`：

- 先去唤醒词
- 再剥离中文语气词
- phase = `finalText`
- 冻结 final 文本
- 如果清理过，显示“我理解为”
- 如果是唤醒词-only，重新开麦，不当成业务指令

### 6.5 开始处理

`sendUserMessage` 或本地任务开始后：

- phase = `processing`
- 保留用户刚才说的话
- 显示“正在处理：xxx”

### 6.6 结果出现

`_finishAssistantTurn` 或 `_showAssistantError`：

- 大卡/抽屉结果正常显示
- echo 延迟短时间淡出
- confirm / clarification 等等待用户回应的卡继续停留

### 6.7 取消/超时/新回合

以下场景清掉 echo：

- 用户取消听音
- 完全未开口且等待窗口结束
- 用户关闭大卡
- 下一轮 `startListening`
- `clearConversation`

## 7. ASR 识别逻辑与动态修正

结论：**ASR 动态修正没有被放弃，但当前没有启用完整实现。**

讯飞请求仍然开启 `dwa: wpgs`，服务端会返回 `pgs`、`rg`、`sn` 等动态修正字段。当前代码会记录这些字段，方便后续基于真机日志恢复完整修正能力。

当前暂不启用完整 `pgs/rpl/rg` 片段表方案。

当前采用回退后的稳定策略：

- `pgs=apd`：追加片段。
- `pgs=rpl`：清空当前累计文本并写入替换片段。

原因：

- 之前复杂修正影响了实际识别体验。
- 当前阶段优先保证 final 文本稳定、业务链路可靠。
- 已增加 `[XunfeiASR]` 调试日志，便于真机观察讯飞返回片段和 displayText。

后续待恢复的完整动态修正方案：

- 维护 `sn -> segment` 片段表。
- `pgs=apd` 时追加或更新当前 `sn`。
- `pgs=rpl` 时按 `rg` 指定范围替换片段。
- 每次事件按 `sn` 排序拼接 displayText。
- 补覆盖 `apd`、`rpl`、跨范围替换、final 的单测。

恢复前置条件：

- 先收集真机 `[XunfeiASR]` 日志，确认实际 `pgs/rg/sn` 返回结构。
- 不再凭协议印象直接改主链路。
- 完整修正必须保证 final 文本和业务执行准确性不倒退。

## 8. 调试日志

已新增三类日志：

| 日志前缀 | 位置 | 用途 |
|---|---|---|
| `[XunfeiASR]` | `xunfei_asr_client.dart` | 查看 partial/final、pgs、rg、displayText |
| `[DoubaoChat]` | `doubao_chat_client.dart` | 查看豆包 Chat 流式事件 |
| `[DoubaoResponses]` | `doubao_responses_client.dart` | 查看豆包 Responses 输入输出和异常 |

日志只在 debug 模式输出。

## 9. 影响范围

| 文件 | 说明 |
|---|---|
| `assistant_state.dart` | 新增 `AssistantVoiceEchoState` |
| `assistant_controller.dart` | 统一 echo 生命周期、开口即停倒计时、ASR final 处理 |
| `assistant_drawer.dart` | 全屏大卡底部 Dock、抽屉/底部回显接入 |
| `full_screen_answer_card.dart` | 大卡给底部 Dock 预留空间 |
| `voice_echo_bar.dart` | 统一语音回显组件 |
| `assistant_ball.dart` | 移除 listen 倒计时视觉态 |
| `workbench_shell_page.dart` | 工作台小治球不再接收 listen 倒计时 |
| `xunfei_asr_client.dart` | 回退稳定识别组装逻辑 + 调试日志 |
| `doubao_chat_client.dart` / `doubao_responses_client.dart` | 豆包调试日志 |
| `confirm_flow_test.dart` | 覆盖开口后停倒计时但继续听 final |

## 10. 验收场景

| 场景 | 预期 |
|---|---|
| 大卡确认态，用户说“确认” | 底部 Dock 显示识别内容，随后执行确认 |
| 大卡澄清态，用户补“明天下午三点” | 底部 Dock 先显示识别中，再显示处理中 |
| 用户一开口 | 倒计时立即停止，继续等 final |
| 用户说话中 | 不显示倒计时，不打断录音 |
| 用户只说“小治小治” | 不当成业务输入，重新开麦 |
| 完全未开口 | 等待窗口结束后显示“这次没听到你说话” |
| 抽屉打开语音输入 | echo 在抽屉内，不弹顶部浮窗 |
| Dashboard 空闲唤醒 | echo 在底部球附近 |
| 全屏大卡显示时继续说话 | echo 在屏幕底部固定 Dock，不进入大卡内部 |

## 11. 后续注意

- TTS 播报延迟问题未在本方案中处理，后续单独分析。
- 语音端点和 ASR 修正不能只看代码推测，必须结合真机日志。
- 任何语音交互改动都要同时检查：状态机、UI 承载位置、倒计时来源、真机表现和自动化测试。
