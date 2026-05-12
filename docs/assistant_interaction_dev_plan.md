# 助手交互系统 — 开发实施方案

最近更新：2026-05-12。
状态：**核心交互已实施，待真机回归**。
关联设计：`docs/assistant_interaction_design.md`（4 种 surface 设计稿）。

## 0. 总原则与不变量

### 0.1 必须遵守的"不变量"（任何 phase 都不能破坏）

| # | 现有功能 | 不变量 | 失败影响 |
|---|---|---|---|
| 1 | 唤醒词「小治小治」（Android 原生） | 唤醒触发 listen 流程不变 | 用户唤不出助手 |
| 2 | 长按球 press-to-talk | 长按持续录音、`vad_eos` 8s | 长按对话失效 |
| 3 | TTS facade（火山+讯飞）| `ttsFacadeProvider` 接口不变；只改"何时调用" | TTS 直接挂 |
| 4 | NLU 语气词剥离 | `stripChineseFillers` 接入点不变 | "嗯，确认" 又识别失败 |
| 5 | 语音端点检测 | 倒计时只表示“等待开口”；用户一开口即停倒计时，录音继续等讯飞 final | 说话被截断 / 倒计时误导 |
| 6 | 信息卡 5 类（weather/exchange/world_clock/poi）| 数据层 + 解析层不动；只改"渲染容器"（从抽屉气泡改为大卡内 inline）| 卡片显示异常 |
| 7 | confirm 流程（pendingConfirm 状态机）| 现有触发与完成路径不变；只改"展示位置" | 创建日程流程崩 |
| 8 | pending write draft（多轮补字段）| 草稿状态机不动 | 创建草稿流程崩 |
| 9 | proactive suggestion（主动建议）| 触发不变；只改"展示位置"（球外卡 → 顶部 banner）| 主动建议看不到 |
| 10 | session mute / completion undo / followUp 续听 | 状态字段保留；只改 UI 表现层 | 撤销 / 续听失效 |
| 11 | dashboard 看板 | 大卡显示时模糊背景，消散后立即恢复 | 看板被覆盖到打不开 |
| 12 | 任务编辑器 / 设置页 / 试听按钮 | 完全不动 | 跨页面流断 |

### 0.2 设计原则：助手像人

**用户拍板的核心产品原则**（2026-05-12）：

> 助手不应该在自己说话过程中突然中断换话题。人不会在说话的中途切断自己。

这条原则贯穿所有"打断 / 切换 surface"逻辑——所有触发源按"主体"分类：

| 触发源 | 主体 | TTS 是否立刻停 | 大卡是否立刻切 |
|---|---|---|---|
| 用户唤醒词 / 长按球 / 点 ✕ / 抽屉里输入 | **用户主动** | ✅ 立即停 | ✅ 立即切 |
| 紧急提醒到点 | **系统被动** | ❌ **等 TTS 完再播** | ❌ 等 TTS 完再切 |
| 普通推送 banner | 系统被动 | ❌ 不打断 | ❌ 顶部叠加，不抢主场 |
| 错误事件 | 系统被动 | ❌ 不打断（可视化呈现）| 错误大卡 5s 后才弹 |

**关键差异**：
- 用户主动 = 用户已经做出"我要立即响应"的动作 → 系统立即响应
- 系统被动 = 系统侧的事件 → 必须等当前"对话回合"自然结束（TTS 播完）再切

**极端 case 兜底**：单条 TTS 默认 ≤ 200 字（≈ 15s），紧急提醒最多等 15s。如果未来出现长答复需要等更久，单独立项做"长 TTS 强制打断" 选项。

### 0.3 总策略

- **9 个 phase 渐进迁移**，每 phase 单独 commit、可独立回滚
- **Phase 1-3 是纯新增**（新组件不接入，旧组件全在）→ 零回归风险
- **Phase 4-7 是迁移期**（新旧并存，逐步切流量）→ 必须保留 fallback
- **Phase 8-9 是清理期**（删旧代码，验证全场景）→ 集中爆破点
- 每 phase 必跑：`flutter analyze` 0 issue + `flutter test` 全绿 + 真机关键场景冒烟

## 1. 影响面全景盘点

### 1.1 改造范围

| 类别 | 内容 |
|---|---|
| **新建组件** | `assistant_surface_router.dart`、`FullScreenAnswerCard` widget、`TopFloatingBanner` widget、`SurfaceController` 状态管理 |
| **重构组件** | `AssistantDrawer`（改 60% bottom sheet 三段式拖动）、`_AssistantDock`（球加"等确认"暖橙状态） |
| **删除组件** | `_CompactReplyCard`、`replySurface.compactCard` enum、`_resolveReplySurface`（字数判断版本） |
| **修改状态字段** | `compactReplyText/compactReplyCard` 移除；`replySurface` enum 重构；新增 `surfaceState`（fullscreenAnswer/topBanner/drawer/none） |

### 1.2 联动的现有逻辑（必须协同处理）

| 现有逻辑 | 文件位置 | 影响 |
|---|---|---|
| 自动续听窗口 | `assistant_controller.dart:_speakCompactReplyAndStartFollowUp` | 大卡消散计时器要跟续听窗口对齐 |
| TTS 播报 | `assistant_controller.dart:_speakAsync` 等 5 处 | 大卡消散触发条件含"TTS 完毕" |
| 信息卡渲染 | `assistant_result_card_view.dart` + 5 个 view | 容器从抽屉气泡改为大卡 inline，子组件不动 |
| ASR partial 文本 | `state.listenPartialText` | 显示位置从抽屉/球周围迁到顶部浮窗 |
| 唤醒/打断 | `voice_wakeup_service.dart` | 唤醒事件触发 stopTts + 打开顶部浮窗 |
| 错误通道 | `state.ttsError` / `state.error` / `state.progress.error` | 全部走大卡 3f，5s 消散 |
| 完成撤销 | `state.completionUndo` | 走大卡 3b 内 undo 按钮 |
| proactive suggestion | `state.proactiveSuggestion` | 走顶部 banner（推送形态） |

### 1.3 需要新增的能力

| 能力 | 用途 | 难点 |
|---|---|---|
| 大卡消散计时器 | TTS 完 + 5s 自动消散 | 跟 TTS 完毕事件协同；触屏点卡延长 |
| 触屏延长手势 | 用户点大卡 → 重置消散计时器 | 不能跟"上滑跳抽屉"手势冲突 |
| 上滑跳抽屉手势 | 用户上滑大卡 → 大卡淡出 + 抽屉打开 | 滑动方向 + 阈值判定 |
| 抽屉拖动 grabber | peek/half/full 三段切换 | DraggableScrollableSheet 标准做法 |
| 紧急提醒打断 | 提醒到点 → TTS 立停 + 大卡接管 | 跟当前大卡的转场动画 |
| 推送队列 | 多个 banner 排队 | 先到先消化，单线程显示 |
| 状态机 SurfaceController | 管理 4 种 surface 切换 + 转场动画 | 状态转换覆盖完整、无非法状态 |

## 2. Surface 状态机详细设计

### 2.1 状态定义

```dart
enum AssistantSurfaceState {
  none,                  // dashboard 满屏，无任何助手 UI
  topBannerListen,       // 顶部浮窗显示 ASR partial（用户说话中）
  topBannerPush,         // 顶部浮窗显示推送 banner（系统推送）
  fullscreenAnswer,      // 全屏大卡（按 7 种形态变内容）
  drawerOpen,            // 抽屉打开（用户主动上滑唤起的对话模式）
}

enum AnswerCardKind {
  infoCard,        // 3a 含 <assistant-card>
  toolFeedback,    // 3b create_task / update_task 等成功反馈
  plainText,       // 3c 纯文字答复
  clarification,   // 3d 澄清/追问
  confirm,         // 3e pendingConfirm 等待
  error,           // 3f ttsError / 异常
  reminder,        // 3g 紧急提醒
}
```

### 2.2 状态转换图（mermaid）

```
none ──────────[唤醒]──────────────► topBannerListen
none ──────────[系统普通推送]──────► topBannerPush
none ──────────[系统紧急提醒]──────► fullscreenAnswer(reminder)
none ──────────[用户上滑]──────────► drawerOpen

topBannerListen ──[用户说完话]────► fullscreenAnswer(按内容类型)
topBannerListen ──[用户取消/超时]► none

topBannerPush ──[5s 自动收起]────► none
topBannerPush ──[用户点展开]──────► drawerOpen

fullscreenAnswer ──[TTS 完+5s]────► none（仅答复型 3a/3b/3c/3f）
fullscreenAnswer ──[用户上滑]─────► drawerOpen
fullscreenAnswer ──[用户点关闭]───► none
fullscreenAnswer ──[用户触屏点卡]► fullscreenAnswer (重置消散计时)
fullscreenAnswer ──[用户决策完毕]► none（决策型 3d/3e/3g 完成后）
fullscreenAnswer ──[自动续听触发]► topBannerListen
fullscreenAnswer ──[紧急提醒插队]► fullscreenAnswer(reminder)（保留历史）
fullscreenAnswer ──[再次唤醒打断]► topBannerListen（停 TTS）

drawerOpen ──[用户问答]──────────► drawerOpen（inline 追加，不弹大卡）
drawerOpen ──[用户 ✕ 关闭]──────► none
drawerOpen ──[紧急提醒]───────── ► fullscreenAnswer(reminder)（抽屉收起）
```

### 2.3 关键转换说明

**用户主动打断（核心场景）**：
- 任意状态 → 唤醒/长按/点✕ → `topBannerListen` 或 `none`
- 转换时立即执行：`stopTts()` + 当前 surface 淡出
- 用户主动动作意味着用户已选择立即响应

**自动续听**（已有 `_speakPromptThenContinueListening`）：
- `fullscreenAnswer` (TTS 完毕) → 触发续听 → `topBannerListen`
- 大卡消散 + 顶部浮窗弹出 + 自动开麦
- 跟"TTS 完 + 5s 消散"二选一：续听优先

**抽屉模式与大卡模式互斥**：
- 抽屉打开期间，新答复 **inline 在抽屉里追加**（不弹大卡）
- 用户主动 ✕ 抽屉后，下一次问答又走大卡
- 切换原则：用户主动选择"快速模式"（球唤醒）→ 大卡；"沉浸模式"（上滑抽屉）→ 抽屉 inline

**紧急提醒插队**（按"助手像人"原则）：
- 提醒触发时**不立即打断当前 TTS**
- 提醒进入待处理队列 `pendingReminder`
- 等当前 TTS 自然播完
- TTS 完毕事件触发后：
  - 如果有 `pendingReminder` → 当前大卡淡出 + 大卡 3g 接管 + 播提醒 TTS
  - 如果同时有自动续听窗口 → 提醒优先于续听（提醒 TTS 完后再开麦）
- 当前大卡内容存到历史（不丢失）
- 抽屉打开时同样等 TTS 完才收起 + 弹大卡 3g
- 极端 case：TTS 超过 30s 仍未播完时打印 warning（不强制打断，等极端 case 真实发生再优化）

## 3. 7 种大卡形态规格

### 3.1 触发判定（代码可知，不依赖字数）

| 形态 | 判定条件 | 优先级 |
|---|---|---|
| 3g 紧急提醒 | `notification 触发` | 最高（打断一切） |
| 3e confirm 等待 | `state.pendingConfirm != null` | 高 |
| 3f 错误 | `state.ttsError != null` 或 `progress.error != null` | 高 |
| 3d 澄清/追问 | `state.pendingWriteDraft != null` 且最新 assistant 消息含问号 | 中 |
| 3a 信息卡答复 | `displayContent.resultCard != null` | 中 |
| 3b 工具成功反馈 | 最新 tool_call 成功且非 query 类（create/update/delete/complete） | 中 |
| 3c 纯文字答复 | 不属于以上任何类 | 兜底 |

判定函数（在 `assistant_surface_router.dart`）：
```dart
AnswerCardKind classify(AssistantUiState state, AssistantDisplayContent content) {
  if (state.pendingConfirm != null) return AnswerCardKind.confirm;
  if (state.ttsError != null || _hasError(state)) return AnswerCardKind.error;
  if (_isClarificationQuestion(state)) return AnswerCardKind.clarification;
  if (content.resultCard != null) return AnswerCardKind.infoCard;
  if (_isWriteToolFeedback(state)) return AnswerCardKind.toolFeedback;
  return AnswerCardKind.plainText;
}
```

### 3.2 形态消散规则

| 形态 | 自动消散 | 触屏点卡 | 上滑 |
|---|---|---|---|
| 3a 信息卡 | TTS 完 + 5s | 重置 5s 计时 | 大卡淡出 + 抽屉打开 |
| 3b 工具反馈 | TTS 完 + 5s（可在内有 undo 按钮）| 同上 | 同上 |
| 3c 纯文字 | TTS 完 + 5s | 同上 | 同上 |
| 3d 澄清 | 不消散，等用户说话 | 重置开麦窗口 | 大卡淡出 + 抽屉打开 |
| 3e confirm | 不消散，等用户决策 | 仅高亮按钮 | 大卡淡出 + 抽屉打开 |
| 3f 错误 | 5s 自动消散 | 重置 5s 计时 | 大卡淡出 + 抽屉打开 |
| 3g 提醒 | 不消散，等用户操作（已读/稍后/关闭） | 仅高亮按钮 | 大卡淡出 + 抽屉打开 |

## 4. 分阶段实施（9 phase）

### Phase 1：抽 SurfaceRouter（仅决策层重构，UI 不变）

**目标**：把"按字数判断 surface"的逻辑挪到独立 router 类，但**输出仍是旧的 surface 类型**（compactCard / drawer / none）。
等价重构。

**任务**：
1. 新建 `lib/features/assistant/application/assistant_surface_router.dart`
2. 实现 `LegacySurfaceRouter.resolve(text, source)` → 复制 `_resolveReplySurface` 逻辑
3. `_finishAssistantTurn` 改为调 router

**影响范围**：仅 controller 内部 1 处调用。
**风险**：决策跟现状不一致 → 单测覆盖所有 case。
**验收**：
- [ ] `flutter analyze` 0 issue
- [ ] 现有 145 个测试全绿
- [ ] 真机：信息卡 5 类、纯文字答、确认日程，跟改前完全一致

**回滚**：单 commit revert。

---

### Phase 2：新建 FullScreenAnswerCard widget（不接入）

**目标**：完整新组件代码，含 7 种形态渲染，但不接入 controller，仅可在 widget book / dev preview 看效果。

**任务**：
1. 新建 `lib/features/assistant/presentation/widgets/full_screen_answer_card.dart`
   - `FullScreenAnswerCard({required AnswerCardKind kind, required ...})`
   - 7 种 kind 各自的 layout
2. 新建 `lib/features/assistant/presentation/widgets/answer_cards/` 子目录放各形态子组件：
   - `info_card_layout.dart`（3a，复用现有 `AssistantResultCardView`）
   - `tool_feedback_layout.dart`（3b）
   - `plain_text_layout.dart`（3c）
   - `clarification_layout.dart`（3d）
   - `confirm_layout.dart`（3e，复用现有 `ConfirmCard`）
   - `error_layout.dart`（3f）
   - `reminder_layout.dart`（3g）
3. 单测：每种 kind 渲染快照测试

**影响范围**：纯新增，不接入。
**风险**：几乎无。
**验收**：
- [ ] flutter analyze + test
- [ ] 视觉走查 7 种形态（dev page 临时开个入口）

---

### Phase 3：新建 TopFloatingBanner widget（不接入）

**目标**：顶部浮窗组件，支持两种用途（ASR partial / 推送 banner）。

**任务**：
1. 新建 `lib/features/assistant/presentation/widgets/top_floating_banner.dart`
   - `TopFloatingBanner({required TopBannerKind kind, ...})`
   - kind: `listenPartial` / `pushNotification`
2. 进出动画（顶部下滑入，淡出退出）
3. 单测

**影响范围**：纯新增。
**风险**：无。

---

### Phase 4：抽屉重构成 60% bottom sheet（保留 compactCard 逻辑）

**目标**：把现有窄抽屉换成 `DraggableScrollableSheet`，三段式 peek/half/full 拖动。
**仍保留 `_CompactReplyCard` 和旧 `_resolveReplySurface`**，让用户在过渡期可以并存。

**任务**：
1. 重构 `AssistantDrawer` 用 `DraggableScrollableSheet`
2. 默认 60% 高度（minSize peek 0.15、initSize half 0.6、maxSize full 0.9）
3. Header 56px + 滚动区域 + 输入条 56px
4. 拖动 grabber 顶部 36×4
5. 抽屉底部上滑触发 → 唤起抽屉（drawerOpen 状态）
6. ✕ 按钮关闭

**影响范围**：抽屉 UI 完全重构，但 surface 路由仍跟之前一样（drawer 来源 → 抽屉）。
**风险**：键盘弹起冲突、拖动手势跟内部 ListView 滚动冲突 → 用 `DraggableScrollableSheet` 标准方案。
**验收**：
- [ ] 抽屉打开/关闭/拖动各档位流畅
- [ ] 输入框获焦键盘弹起 sheet 自动顶高
- [ ] 抽屉里 ListView 滚动不被 sheet 拖动手势抢占
- [ ] confirm card / 信息卡 / 历史消息全部正常

**回滚**：单 commit revert（旧 widget 保留作 fallback）。

---

### Phase 5：接入 FullScreenAnswerCard，替换 compactCard 路径

**目标**：把"快速语音 → 短答 compactCard"路径切到"全屏大卡"。
**保留旧 `_CompactReplyCard` 代码**（仅做 fallback / 死代码状态），下个 phase 再删。

**任务**：
1. 改 `SurfaceRouter`：输出新 enum `AssistantSurfaceState`
2. `assistant_state.dart` 新增 `surfaceState: AssistantSurfaceState` + `currentAnswerCard: AnswerCardKind?`
3. controller `_finishAssistantTurn` 写入新状态
4. 新建大卡消散计时器（TTS 播完事件 + 5s）
5. workbench_shell_page 增加 `FullScreenAnswerCard` 渲染层（在 dashboard 之上、抽屉之下）
6. compactCard 路径全部改走 fullscreenAnswer
7. 旧 `_CompactReplyCard` widget 不再被引用（保留代码）

**影响范围**：UI 大改、controller 状态机改。
**风险**：高。每个 surface 转换 case 都要走通。
**验收**（必须 100% 通过）：
- [ ] 球唤醒说"上海天气" → 顶部浮窗 → 全屏大卡（信息卡 3a） → TTS 播完 + 5s 消散
- [ ] 球唤醒说"几点了" → 顶部浮窗 → 全屏大卡（纯文字 3c） → 消散
- [ ] 球唤醒说"创建明天 3 点开会" → 顶部浮窗 → 全屏大卡（confirm 3e）→ 不消散
- [ ] 大卡显示中触屏点卡 → 重置 5s 计时
- [ ] 大卡显示中上滑 → 大卡淡出 + 抽屉打开
- [ ] 大卡显示中再次唤醒 → TTS 停 + 顶部浮窗 + 大卡淡出
- [ ] 大卡显示中错误 → 大卡 3f → 5s 消散
- [ ] 跟 dashboard 看板互不影响（消散后看板 100% 可见）

**回滚**：单 commit revert，回到 Phase 4 状态。

---

### Phase 6：语音回显 Dock 与主动建议 banner

**目标**：用户语音回显统一走 `VoiceEchoBar`；proactive suggestion 走顶部 banner。

> 2026-05-12 最终实现：顶部 listen 浮窗已撤销。语音回显不进入大卡内部，改为“中间大卡 + 底部固定 Dock”。Dashboard 空闲在底部球附近显示，抽屉打开在抽屉内显示，全屏大卡打开时在屏幕下方固定 Dock 显示。详见 `docs/voice_echo_interaction_solution.md`。

**任务**：
1. controller 统一维护 `AssistantVoiceEchoState`
2. `AsrPartialEvent` 更新 `VoiceEchoBar` 的“识别中”文本
3. open mic 等待倒计时只在用户未开口时显示
4. 用户开口后立即停倒计时，录音继续等讯飞 final
5. 全屏大卡显示时，底部固定 `VoiceEchoBar` Dock；大卡给 Dock 预留空间
6. `state.proactiveSuggestion` 触发 → 顶部浮窗（推送 banner 形态）

**影响范围**：语音回显位置、open mic 倒计时、主动建议显示位置。
**风险**：多处 UI 可能同时读取 `listenWindowRemainingMs`，导致看起来倒计时没有停止；已移除小治球的倒计时视觉态，只保留回显条倒计时。
**决策**：
- **抽屉打开时**：partial 显示在抽屉内 `VoiceEchoBar`
- **抽屉关闭普通唤醒时**：partial 显示在底部球附近 `VoiceEchoBar`
- **全屏大卡打开时**：partial 显示在底部固定 Dock，不显示在大卡内部
- **顶部 banner**：只承载主动建议/系统推送，不承载用户语音
**验收**：
- [x] 球唤醒说话 → 底部回显条显示识别中文字
- [x] 抽屉打开后语音输入 → 抽屉内显示识别中文字
- [x] 全屏大卡显示中说话 → 底部固定 Dock 显示识别中文字
- [x] 用户一开口 → 倒计时停止，录音继续等待 final
- [x] proactive suggestion 触发 → 顶部 banner，点展开进抽屉

---

### Phase 7：提醒功能接入

**目标**：定时提醒 / 日程到点触发对应 surface。

**任务**：
1. 新建 `lib/features/assistant/application/reminder_dispatcher.dart`
2. 监听 `flutter_local_notifications` 回调
3. 紧急提醒（日程到点 / 闹钟）→ `SurfaceController.showReminder(...)` → 大卡 3g
4. 普通推送（"还有 3 件事"等汇总）→ 顶部 banner
5. 紧急提醒打断逻辑：当前 TTS 立停 + 当前大卡淡出 + 大卡 3g 接管
6. 提醒结束（用户点已读/稍后/关闭）→ surface 回到 none

**影响范围**：新功能，不破坏现有交互。
**风险**：跟当前对话冲突的转场动画。
**验收**：
- [ ] 模拟日程到点 → 大卡 3g 弹出 + TTS 提醒话术
- [ ] 用户点已读 → 大卡消散 + 看板恢复
- [ ] 用户点稍后 → 5 分钟后再弹
- [ ] 提醒打断当前 TTS → 立停 + 平滑转场

---

### Phase 8：多轮对话 + 语音打断验证（不写新代码，专门跑场景）

**目标**：把所有"多轮 / 打断 / 状态机边界"case 在真机过一遍，发现问题修复。

**任务**：
1. 写场景测试脚本（含 30+ 真机测试 case）
2. 跑全场景验证
3. 发现状态混乱时修复

**关键场景**：
- A1. 唤醒 → 答 → 自动续听 → 再问 → 答 → 续听结束
- A2. 唤醒 → 答 → 5s 消散 → 看板满屏
- A3. 唤醒 → 答（含 confirm）→ 用户说"确认" → 完成大卡 3b → 消散
- A4. 唤醒 → 创建日程草稿（缺字段 3d）→ 用户补充 → confirm 3e → 完成
- A5. TTS 中再次唤醒 → 立停 + 顶部 partial
- A6. 大卡显示中触屏 → 计时重置
- A7. 大卡 3a 显示中上滑 → 抽屉打开（含历史）
- A8. 抽屉打开后语音问 → 抽屉 inline 追加（不弹大卡）
- A9. 抽屉关闭 → 下次问回到大卡模式
- A10. confirm 3e 等待中收到日程到点提醒 → 大卡 3g 接管 + confirm 状态保留？还是自动取消？

**A10 是关键决策**——我倾向 **confirm 状态保留**：用户处理完提醒后，原 confirm 仍在 `pendingConfirm` 状态，重新弹大卡 3e。这样不会因为提醒打断丢失用户操作。

---

### Phase 9：移除 compactCard 旧逻辑（清理期）

**目标**：删除所有跟 compactCard 相关的死代码。

**任务**：
1. 删除 `_CompactReplyCard` widget
2. 删除 `state.compactReplyText` / `compactReplyCard` 字段
3. 删除 `replySurface.compactCard` enum 值
4. 移除 `_resolveReplySurface` 旧版本（已在 Phase 1 替换）
5. 清理 controller 内残留的 compactCard 路径

**影响范围**：纯删除代码。
**风险**：漏改导致 import 错误。
**验收**：
- [ ] flutter analyze 0 issue
- [ ] flutter test 全绿
- [ ] 真机过 Phase 8 全场景

---

## 5. 测试覆盖矩阵

### 5.1 自动化测试（每 phase 必跑）

| 测试文件 | Phase 1 | Phase 4 | Phase 5 | Phase 6 | Phase 7 | Phase 9 |
|---|---|---|---|---|---|---|
| `assistant_surface_router_test.dart`（新建） | ✅ 新增 | — | ✅ 扩展 | — | — | ✅ 清理 |
| `confirm_flow_test.dart` | 跑过 | 跑过 | 必改（compactCard 路径变） | 跑过 | 跑过 | 必改 |
| `auto_speak_decision_test.dart` | 跑过 | 跑过 | 跑过 | 跑过 | 跑过 | 跑过 |
| `public_response_flow_test.dart` | 跑过 | 跑过 | 必改 | 跑过 | 跑过 | 必改 |
| `full_screen_answer_card_test.dart`（新建） | — | — | ✅ 新增 | — | — | — |
| `top_floating_banner_test.dart`（新建） | — | — | — | ✅ 新增 | — | — |
| `surface_state_machine_test.dart`（新建） | — | — | ✅ 新增 | ✅ 扩展 | ✅ 扩展 | — |
| `reminder_dispatcher_test.dart`（新建） | — | — | — | — | ✅ 新增 | — |

### 5.2 真机回归冒烟（每 phase 后必过）

按 Phase 8 的 A1-A10 场景全跑一遍。

## 6. 边界 Case 详细处理

### 6.1 多轮对话

| 场景 | 处理 |
|---|---|
| 用户连续多轮问答 | 每轮：顶部浮窗(partial) → 大卡(answer) → 续听 → 顶部浮窗(partial) ... 直到无续听 |
| 续听超时无输入 | 大卡当前内容继续显示直到 5s 消散计时结束 |
| 续听过程中 TTS 没播完用户说话 | TTS 立停 + 大卡淡出 + 顶部浮窗 |
| 续听过程中用户长按球 | 同上 + 进入 press-to-talk 模式 |

### 6.2 用户主动打断（立即响应）

按 0.2 节"助手像人"原则，**用户主动动作立即停 TTS**。

| 触发 | 当前状态 | 处理 |
|---|---|---|
| 唤醒词「小治小治」 | TTS 播报中 | **立刻 stopTts** + 大卡淡出 + 顶部浮窗 listen |
| 唤醒词 | 等 confirm（3e）| 立刻 stopTts + 顶部浮窗 listen，**保留 pendingConfirm** |
| 唤醒词 | 等澄清（3d） | 同上 |
| 长按球 | 任意 | 立刻 stopTts + 进 press-to-talk |
| 用户点关闭按钮 ✕ | 任意大卡 | stopTts + 大卡消散 + dashboard 恢复 |
| 用户在抽屉里输入 | TTS 播报中 | stopTts + 抽屉里追加新问题 |

### 6.3 系统被动事件（不打断 TTS，等播完）

按 0.2 节"助手像人"原则，**系统事件等 TTS 自然播完再处理**。

| 当前状态 | 提醒触发 | 处理 |
|---|---|---|
| dashboard 满屏（无 TTS）| 紧急提醒 | 立即弹大卡 3g |
| 顶部 partial（用户在说话） | 紧急提醒 | 等用户说完 → 进入大卡 3g（不立即打断用户说话）|
| fullscreenAnswer (3a/3b/3c) TTS 中 | 紧急提醒 | **不打断 TTS**，进入 `pendingReminder` 队列。TTS 完毕事件后立即弹大卡 3g + 播提醒 TTS |
| fullscreenAnswer (3a/3b/3c) TTS 已完毕（5s 消散计时中） | 紧急提醒 | 立即转场大卡 3g（无需等待） |
| fullscreenAnswer (3e confirm) | 紧急提醒 | 等 TTS 完毕 → 大卡转场 3g，**pendingConfirm 保留**，提醒处理完后回到 3e |
| fullscreenAnswer (3d 澄清) | 紧急提醒 | 等 TTS 完毕 → 大卡转场 3g，澄清状态保留，提醒处理完后回到 3d 重新开麦 |
| drawerOpen TTS 中 | 紧急提醒 | 等 TTS 完毕 → 抽屉收起 + 大卡 3g |
| drawerOpen 无 TTS | 紧急提醒 | 立即抽屉收起 + 大卡 3g |
| topBannerPush | 紧急提醒 | 当前 banner 立即消失 + 大卡 3g 接管（推送 banner 不算"对话回合"，可被打断）|

**实现要点**：
- 监听 TTS 播放完毕事件（已有 `_player.onPlayerComplete`）
- 维护 `pendingReminder: ReminderEvent?` 状态
- TTS 完毕回调 → 检查是否有 `pendingReminder`，有则触发大卡 3g 转场

### 6.4 推送排队

- 多个普通 banner 排队，先到先消化（一次只显示一个，5s 后下一个）
- 多个紧急提醒不排队，**最新的覆盖前一个**（避免堆叠遮挡）
- 普通 banner 显示中收到紧急提醒 → banner 消散 + 大卡 3g 接管

### 6.5 错误处理

| 错误类型 | 阻塞性 | 处理 |
|---|---|---|
| LLM 调用失败 | 阻塞（无答复）| 大卡 3f + retry 按钮 |
| TTS 失败但答复有 | 非阻塞 | 大卡正常显示答复 + 顶部 banner 提示"播报失败" 5s 消散 |
| 工具执行失败 | 取决于场景 | 阻塞场景大卡 3f；非阻塞文字提示 |
| 网络超时 | 阻塞 | 大卡 3f + retry |
| 录音权限被拒 | 阻塞 | 大卡 3f + 引导去设置 |

### 6.6 键盘弹起

- 抽屉打开时输入文字 → 键盘弹起 → DraggableScrollableSheet 自动顶高到键盘上方
- 全屏大卡显示时不展示输入框（避免键盘冲突）
- 抽屉 maxSize 改为屏高 - 键盘高（dynamic）

### 6.7 横竖屏旋转

- 当前主场景横屏，竖屏作降级支持
- 抽屉竖屏时占 70% 高（横屏 60% 不够用）
- 大卡竖屏时宽度占 90%（横屏 80%）

## 7. 工作量估算

| Phase | 工作内容 | 工作量 | 风险 |
|---|---|---|---|
| 1 | SurfaceRouter 等价重构 | 0.5d | 低 |
| 2 | FullScreenAnswerCard 7 种 layout | 1.5d | 低 |
| 3 | TopFloatingBanner | 0.5d | 低 |
| 4 | 抽屉重构 60% bottom sheet | 1d | 中（手势）|
| 5 | 接入大卡 + 状态机 + 消散计时 | 1.5d | 高（核心改造）|
| 6 | TopBanner 接入 | 0.5d | 低 |
| 7 | 提醒功能接入 | 1d | 中（联动）|
| 8 | 多轮 / 打断 / 边界 真机验证 | 1d | 中（场景多）|
| 9 | 清理 compactCard 旧代码 | 0.5d | 低 |
| **合计** | | **8 天** | 单人不间断 |

## 8. 回滚预案

| 阶段 | 出问题怎么办 |
|---|---|
| Phase 1 失败 | 单 commit revert，回到改前 |
| Phase 2-3 失败 | 几乎不可能（纯新增） |
| Phase 4 抽屉手势卡 | revert Phase 4，回到 Phase 3 后状态（旧抽屉） |
| Phase 5 状态机出问题 | revert Phase 5，回到 Phase 4 后状态（新抽屉 + 旧 compactCard） |
| Phase 6 partial 显示乱 | revert Phase 6，partial 仍在球周围 |
| Phase 7 提醒不响 / 反复响 | revert Phase 7，提醒仍走老 notification 通道 |
| Phase 9 删错 | revert Phase 9，旧代码恢复 |

## 9. 已拍板的决策点（2026-05-12 用户拍板）

| # | 议题 | 决策 |
|---|---|---|
| 1 | confirm 等待中被紧急提醒打断后 | **回到 confirm**（保留 pendingConfirm 状态，提醒处理完回到 3e） |
| 2 | 抽屉打开时 ASR partial 位置 | **抽屉内**（用户已选择"沉浸模式"，partial 跟随主场聚焦） |
| 3 | 大卡 3b 工具反馈 undo 按钮 | **卡内**（视觉简洁，5s 内点即可） |
| 4 | 紧急提醒是否打断当前 TTS | **不打断**，等 TTS 播完再播报。"助手像人，不会在说话过程中突然换话题"——这条原则提到 0.2 设计原则层级，贯穿所有打断逻辑 |
| 5 | 大卡 3d 澄清是否自动开麦 | **自动开麦**（复用 `_speakPromptThenContinueListening`） |
| 6 | ASR 动态修正 | **暂缓完整 `pgs/rpl/rg` 片段表实现**。保留 `wpgs` 与 `[XunfeiASR]` 日志，先保证当前 final 文本稳定；后续基于真机日志恢复完整动态修正 |

## 10. 关联文档

- `docs/assistant_interaction_design.md` — 4 种 surface 设计稿（本方案的设计依据）
- `docs/info_card_system.md` — 信息卡 5 类（被本方案"装入"大卡 3a 的内容）
- `docs/tts_voice_optimization.md` — 火山+讯飞 TTS facade（被本方案在大卡消散逻辑里使用）
- `docs/nlu_filler_stripper.md` — NLU 语气词剥离（不动，但要确认大卡里 partial 显示用清理后文本）
- `docs/voice_endpointing_strategy.md` — 语音端点检测基础策略
- `docs/voice_echo_interaction_solution.md` — 底部语音 Dock、开口即停倒计时、echo 生命周期与调试日志方案
- 飞书文档：https://my.feishu.cn/docx/HWKKdFwxFopu8oxXN3sc4mLtnOc
