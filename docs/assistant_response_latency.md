# 助手响应慢 + 错误恢复 优化方案

最近更新：2026-05-12。
状态：调研完成，等用户拍板优先级。

## 用户反馈

1. **响应慢**：问"上海今天天气"等约 **40 秒**才有反馈（球转圈期间无任何内容显示，最后大卡突然蹦出完整答复）
2. **敏感问题污染**：问过敏感新闻报错后，再问任何新闻都不返回信息（待用户给现象细节进一步诊断）

## 一、响应慢的根因诊断

### 1.1 架构层面盘点

| 层 | 现状 |
|---|---|
| LLM 客户端（`DoubaoResponsesClient`） | ✅ **已是流式**（SSE，`stream: true`，`ResponseType.stream`，每个 delta 立即 yield `PublicResponseTextDeltaEvent`） |
| Controller 进度反馈（`AssistantProgressPhase`） | ✅ 已有 7 个 phase（routing / preparingContext / requestAccepted / searching / receiving / summarizing / completed） |
| **大卡渲染（`FullScreenAnswerCard`）** | ❌ **等模型完全答完才显示**（`_finishAssistantTurn` 里设 `surfaceState = fullscreenAnswer`） |
| TTS 播报 | ❌ 等完整文本才送 `speakAndWaitComplete`（虽然火山 V3 双向流式支持边生成边播）|

### 1.2 真正问题

> **接收是流式，呈现是非流式**

DoubaoResponsesClient 实时接收 delta，但 controller 把它们累加到 `messages` 里（不弹大卡），等模型 finish 才一次性切到 `surfaceState = fullscreenAnswer`。中间过程**只有抽屉打开时**用户能看到 `_messageBubble` 的流式追加；**抽屉关闭时**用户只看到球转圈 + `AssistantRunStatusCard` 的进度文字，看不到任何答复内容。

### 1.3 「40 秒」的链路拆解

| 阶段 | 耗时 | 用户能看到啥 |
|---|---|---|
| 1. ASR 识别 | 1-2s | 球周围 `_ListenStrip` partial 文字 |
| 2. routing / preparingContext | 0.5s | 球切"在想" + 进度文字 |
| 3. requestAccepted（豆包接受请求） | 0.5-1s | 进度文案"正在请求" |
| 4. **searching（豆包联网搜索）** | **5-15s** | 进度文案"正在联网查询" |
| 5. **summarizing + receiving（流式 delta）** | **3-10s** | 进度文案，**内容不可见** |
| 6. completed → 弹大卡 3a | <0.1s | 大卡突然出现完整内容 |
| 7. TTS 生成（火山 WebSocket V3 等所有音频） | 1-3s | 还没播 |
| 8. TTS 播报 | 5-10s | 终于听到声音 |
| **合计** | **15-40s** | 大部分时间球转圈 |

### 1.4 「时间不能压缩 vs 体验可以提前」

对前端可控的部分：
- ❌ **联网搜索 5-15s** 是豆包服务端时间，前端无法直接缩短
- ❌ **模型生成 3-10s** 是模型推理时间，前端无法直接缩短
- ✅ **大卡呈现时机** 完全前端可控
- ✅ **TTS 启动时机** 当前是等完整文本，可改为边收边播

如果改成"流式呈现"——总时长仍然 15-40s，但**用户 1-3 秒内看到大卡开始出现首字**，主观感受从"等了 40 秒"变成"边说边出"。

## 二、6 个优化方向

| # | 方向 | 收益 | 复杂度 | 风险 |
|---|---|---|---|---|
| **A** | **大卡支持流式增量呈现**（边收 delta 边 append 到 `answerCardText`）| 🟢 体验巨变（TTFT 从 30s → 1-3s）| 中 | 中（需要把 `surfaceState` 提前到 receiving phase） |
| **B** | 进度文案做更细粒度（"联网查询中…→ 整理结果中…→ 准备播报中…"） | 🟡 缓解等待焦虑 | 低 | 极低 |
| **C** | TTS 流式化（边生成文字边切句送 TTS 分句播报，火山 V3 双向流式支持） | 🟢 听感也提前 5-10s | 高 | 中（要做 sentence-splitter + 串行调度） |
| **D** | 直接对接和风/高德天气 API，绕过豆包联网搜索 | 🟢 砍掉 5-15s 搜索时间 | 中 | 中（数据源依赖变更，可信度需校验） |
| **E** | 同城天气短时缓存（30 分钟内复用） | 🟢 二次问秒回 | 低 | 低 |
| **F** | 模型预热（用户唤醒时 ASR 还在识别就 prefetch 常见问题） | 🟡 命中率不确定 | 高 | 高（无效预热浪费配额） |

## 三、推荐组合

### P0：立即做（1-2 天）

**A 流式大卡呈现 + B 进度文案细化**

- A 是核心改动，把"等完整答复"改为"边收边显示"
  - 收到第一个 `PublicResponseTextDeltaEvent` 时立即 `surfaceState = fullscreenAnswer + answerCardKind = plainText`
  - 后续每个 delta 追加到 `state.answerCardText`
  - 模型完整答完时若发现 `<assistant-card>` 块就切到 `infoCard`
- B 跟 A 配合，让等待期间用户更清楚"在干啥"
- 不动 API 层、不动服务端，纯前端改动
- 预计 1-2 天

### P1：体验观察后做（1 周内）

**C 流式 TTS + E 天气缓存**

- C 利用火山 V3 双向流式能力，边生成边播——但需要做 sentence-splitter（按"。！？"切句）+ 顺序调度，复杂度不低
- E 实施简单（仿照 `dueRemindersForWindow` 模式做 city → CachedWeather 字典 + 30min TTL）

### P2：数据源升级（单独立项）

**D 直接对接和风/高德**

- 绕过豆包联网搜索，时延从 5-15s 降到 0.5-2s
- 但要承担"数据源运维"成本（API Key、quota、降级方案）
- 改动范围大（需要新建 weather repository 层，原 `<assistant-card type="weather">` 解析逻辑保留作 fallback）

## 四、A 方案技术细节（备开工时参考）

### 4.1 当前 _finishAssistantTurn 流程

```
模型完整答完 →
parseAssistantDisplayContent(content) →
_replaceTrailingAssistant(content) →
state.copyWith(
  surfaceState: fullscreenAnswer,
  answerCardKind: classify(...),
  answerCardText: text,
  answerCardResultCard: resultCard,
)
```

### 4.2 改造后流程

```
首个 PublicResponseTextDeltaEvent →
  if surfaceState != fullscreenAnswer:
    立即 state.copyWith(
      surfaceState: fullscreenAnswer,
      answerCardKind: AnswerCardKind.plainText,  // 默认占位
      answerCardText: '',
    )

后续 delta →
  state.copyWith(answerCardText: state.answerCardText + delta)

模型 finish →
  parseAssistantDisplayContent(完整 content) →
    if resultCard != null:
      state.copyWith(
        answerCardKind: AnswerCardKind.infoCard,  // 切到带卡形态
        answerCardResultCard: resultCard,
      )
    // 其他 kind（confirm/error/clarification）按现有判定切
  开始 TTS（仍用 speakAndWaitComplete，C 阶段再改流式 TTS）
```

### 4.3 注意事项 / 边界

- **抽屉打开时**：保持现状（在 messages 里 inline 流式追加），不弹大卡（沉浸模式优先）
- **模型未必产生 `<assistant-card>` 直到最后才出现** → kind 切换可能视觉跳变（plainText → infoCard），需要平滑过渡
- **错误回退**：流式中途报错，要把已显示内容保留 + 切到 error 形态附加错误提示
- **打断**：用户在大卡显示中再次唤醒（已实现），TTS 立停 + 大卡淡出 → 跟现有逻辑一致
- **测试覆盖**：`PublicResponseTextDeltaEvent` 的流式聚合 + kind 切换的 surface_state_test 需要补

## 五、敏感问题污染（待诊断，独立议题）

### 5.1 现象

- 第一次问敏感新闻 → 报错
- 之后问任何新闻 → 都不返回信息

### 5.2 待用户给的现象细节

1. 第一次报错具体是什么样？（大卡 3f / 抽屉里某条 / 仅 toast）
2. 之后"不返回"具体是？
   - 球一直在"在想"动画转圈？（→ stage 卡死）
   - 球回了 idle，但助手没说话？（→ 历史污染）
   - 球都没反应？（→ 错误状态拦截）
3. 重启 app 后是否恢复？（恢复 → state 污染；不恢复 → 服务端会话级故障）
4. 试问"非新闻"问题（"几点了"/"上海天气"）能不能正常回答？

### 5.3 5 个候选方向（等现象细节再精准选）

| # | 方向 | 复杂度 |
|---|---|---|
| A | 检测到 LLM 拒绝答时，把那条 user message 从下发给模型的历史里**软删** | 中 |
| B | 加"清空当前会话"按钮，用户主动一键清状态 | 低 |
| C | 错误后自动 reset：清 errorState / 清 stage / 不清 messages | 低 |
| D | prompt 里加"如果上一轮被拒绝，不要让该话题影响后续无关问题" | 低 |
| E | 检测到连续 N 次同类失败 → 自动 reset 整个会话 | 中 |

**推荐 A + C 组合**：
- C 即时止血（让用户能继续问）
- A 根治污染（剔除被过滤的 message 不再发模型）
- A 的关键是**识别"被过滤"的信号**（豆包返回特定 finish_reason / error code，需要查文档）

## 六、关联文档

- `docs/assistant_interaction_design.md` — 4 种 surface 设计稿
- `docs/assistant_interaction_dev_plan.md` — 9 phase 实施方案
- `docs/tts_voice_optimization.md` — 火山豆包 TTS 2.0 接入（含双向流式能力）

## 七、关联代码位置

- `lib/features/assistant/data/doubao_responses_client.dart` — 流式 LLM 客户端（line 142 `streamPublicResponse` / line 197 `ResponseType.stream`）
- `lib/features/assistant/application/assistant_controller.dart` — `_finishAssistantTurn` 设置 `surfaceState`（line 3530+）
- `lib/features/assistant/application/assistant_state.dart` — `AssistantProgressPhase` 7 个阶段定义
- `lib/features/assistant/data/volc_tts_client.dart` — 火山 WebSocket V3 双向流式 client（已实现但 controller 仍用 speakAndWaitComplete 等完整文本）
