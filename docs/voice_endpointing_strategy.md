# 语音端点检测与超时策略

最近更新：2026-05-09。
状态：**已落地**，真机冒烟通过。

## 背景与问题

旧实现里"用户开口→停止开麦倒计时"的逻辑挂在远端 ASR 文本上：

```dart
// assistant_controller.dart 旧代码
if (event is AsrPartialEvent) {
  if (event.text.trim().isNotEmpty) {
    _markSpeechDetectedInOpenMic();
  }
  ...
}
```

实际链路 PCM→WS→讯飞→partial 文本回包，存在 1-3 秒延迟；遇到含糊语气词（"嗯…那个…"）讯飞 partial 会一直返回空字符串，倒计时持续走，最终弹"这次没听到你说话"。用户感知就是"我在说但它不等我说完"。

另一组问题：`_kOpenMicWait`（开麦等开口）和 `vad_eos`（说话中静音判句尾）都是写死常量，对"追问 + 用户思考"场景太短。

## 方案三件事

### 1. 本地音频能量探测（治本）

`PcmStreamRecorder` 在 `_onRawChunk` 内对每帧（40ms / 1280 字节）算 PCM16 RMS，归一化到 0.0-1.0，通过 `ValueListenable<double> audioLevel` 暴露。

`AssistantController._setupVoice` 订阅这个 listenable：连续 ≥ 2 帧 RMS ≥ 0.025 → 调 `_markSpeechDetectedInOpenMic()`。

**双轨并行**：原 ASR partial 触发逻辑保留作为兜底，谁先到算谁。

阈值 0.025（约 -32 dBFS）= 室内正常说话起步音量；连续 2 帧 = 80ms 防抖，避免环境噪声误触发。

### 2. 超时分档（按对话上下文）

把 `_kOpenMicWait` 与 `vad_eos` 改成按 `_VoiceContinuationTrigger` 取值：

| trigger | openMicWait | vad_eos |
|---|---|---|
| `none`（首次唤醒/主动开麦） | 12s | 2800ms |
| `missingWriteSlots`（追问日程信息） | **18s** | **5000ms** |
| `confirm`（等"确认/取消"） | 10s | 2500ms |
| `pendingTaskChoice`（等"第一条"） | 10s | 2500ms |
| `tripPlanning`（出行规划追问） | 18s | 5000ms |
| `proactiveSuggestion`（主动建议追问） | 12s | 3000ms |

`pressToTalk`（长按）单独：openMicWait 不启动，**vad_eos 用 8000ms**（防止长按时中间停顿被讯飞误判句尾）。

### 3. ball/麦克风视觉反馈

新增 `audioLevelNotifierProvider` 暴露 `ValueNotifier<double>`，controller 在 _setupVoice 订阅 recorder.audioLevel 写入此 notifier，停麦归零。

`AssistantBall` 在 listen 阶段用 `AnimatedBuilder(animation: notifier, ...)` 监听，把能量值映射到 `_AmbientGlow` / `_RippleHalo` 的 pulse / opacity，让光环大小随说话音量起伏。

**最后 3s 视觉切换**：当 `state.listenWindowRemainingMs <= 3000` 且未探测到说话时，glow 颜色从蓝色（#28D8FF）切到暖橙（#FFA374），呼吸节奏从 2s 加快到 0.6s。**不切换文字**——视觉暗示已足够，文字会强行打断用户思考。

文案保持现有"我在听，你可以直接说" / "我在听..."不变。

## 安全边界（不影响现有功能）

| 现有功能 | 是否受影响 | 原因 |
|---|---|---|
| 长按 `pressToTalk` | 否 | `_startOpenMicWait` 已 `if (mode == openMic)` 才启动；`_markSpeechDetectedInOpenMic` 内部 `if (state.listeningMode != openMic) return` |
| 唤醒词触发 | 否 | 唤醒后走 startListening(openMic)，新逻辑生效但更宽容 |
| 公网 doubao 流 / TTS | 否 | 不在改动路径上 |
| ASR partial → mark | 否 | 保留为双轨兜底 |
| 倒计时 UI（`_ListenStrip`+`_CountdownBadge`） | 仅扩展 | 时长变长但显示逻辑不变 |
| `_speakPromptThenContinueListening` 自动续听 | 仅扩展 | 它把 trigger 传给 startListening，按上下文取分档值 |

## 关键实现要点

1. **ASR client 工厂参数化**：`xunfeiAsrClientFactoryProvider` 改成 `Provider<XunfeiAsrClient Function({int vadEosMs})>`；controller 在 `startListening` 时按 trigger 计算 vadEosMs 传入。
2. **trigger 来源**：`startListening` 加可选参数 `_VoiceContinuationTrigger trigger = none`；`_speakPromptThenContinueListening` 续听时传入对应 trigger；其他调用点保持默认 none。
3. **能量阈值常量**：`_kSpeechRmsThreshold = 0.025`、`_kSpeechHoldFrames = 2` 放 controller 顶部，不暴露 settings（先内置，调试后再决定是否暴露）。
4. **audioLevel 性能**：用 `ValueNotifier + AnimatedBuilder`，**不要走 Riverpod ref.watch**，避免每 40ms 触发 widget tree rebuild。
5. **能量归零**：`stopListening` / `cancelListening` / `_teardownVoice` 必须把 audioLevel notifier 重置为 0.0，否则 ball 残留旧动画。
6. **能量计算精度**：PCM16 sample 范围 [-32768, 32767]，RMS = sqrt(mean(sample²)) / 32768，得到 0.0-1.0。

## 回归冒烟清单（真机过一遍）

- [ ] 抽屉点麦：开口立即说"明天下午三点开会"，全程不被截
- [ ] 抽屉点麦：开口先说"嗯…那个…"再说内容，不被截（验证能量探测）
- [ ] 抽屉点麦：开口后中间停顿 3 秒继续说，不被截（验证 vad_eos 提升）
- [ ] 创建日程被追问标题：思考 10 秒再说，倒计时不能在 12s 弹"没听到"（验证 missingWriteSlots 18s）
- [ ] 等确认场景：说"确认"，10s 内能正常处理
- [ ] 长按麦克风说长指令：中间停顿 5 秒不松手，不被讯飞截（验证 pressToTalk vad_eos 8000）
- [ ] 完全不开口：12s 后仍然正常超时弹"没听到你说话"（验证超时机制本身没坏）
- [ ] 听音过程 ball 光环随说话音量明显起伏（视觉反馈生效）
- [ ] 倒计时进入最后 3s 且没说话：ball 颜色变暖橙，呼吸加快
- [ ] 关麦后 ball 立即恢复 idle 蓝、无残留动画（audioLevel 归零）
- [ ] 唤醒词触发的开麦走新流程
- [ ] `flutter analyze` 通过

## 关联代码位置

- `lib/core/voice/pcm_stream_recorder.dart` — RMS 计算 + audioLevel 暴露
- `lib/features/assistant/data/xunfei_asr_client.dart` — vadEosMs 参数化
- `lib/features/assistant/application/assistant_controller.dart` — `_listenTimingFor` / `startListening` / `_setupVoice` / 双轨 mark
- `lib/features/assistant/presentation/widgets/assistant_ball.dart` — audioLevel 接动画 + 末 3s 视觉
- `lib/features/assistant/presentation/assistant_drawer.dart` — `_ListenStrip` 末 3s 视觉同步（可选）
- `lib/core/voice/voice_providers.dart` — `audioLevelNotifierProvider` 新增
