# 助手交互系统设计方案

最近更新：2026-05-12。
状态：设计对齐，等开发排期。

## 产品形态背景

- **设备**：平板（iPad / PZ200），横屏 1180 × 820 logical 起步
- **摆放**：办公桌上立放
- **观看距离**：约 1 米
- **交互方式**：语音为主（唤醒词「小治小治」+ 长按麦），触屏为辅
- **核心价值**：Dashboard 看板（日程/天气/待办常驻），助手是补充能力

这跟手机（30cm 近距离单手操作）/ PC（50-70cm 多窗口）/ TV（2-3m 遥控）都不同。最对标的形态是**带屏智能音箱**（Echo Show / Google Nest Hub / 天猫精灵 CC10）+ **桌面环境屏**（ambient computing）。

## 当前问题

### 痛点 1：surface 不可预测

代码 `_resolveReplySurface` (assistant_controller.dart:3588) 现状：
```
if 来自抽屉（drawerText/drawerVoice）→ drawer
if 来自快速语音（quickVoice）→ 按答复字数：
  ≤72 字（无标点）或 ≤120 字（带标点）→ compactCard（球外卡）
  否则 → drawer
```

**根因**：surface 由"模型生成的字数"决定，但模型每次输出长度不可控。同一问题，模型多说几句话就从 compactCard 跳到 drawer，用户视觉焦点要追着跳。

### 痛点 2：抽屉太小 + confirm card 挤压历史

抽屉宽 ~360-400px 窄列。confirm card 一弹就吃掉至少 200px 高度，历史区剩余空间太小，滚动困难。

### 痛点 3：缺少提醒推送的 surface 设计

当前 surface 系统只覆盖"用户问→助手答"，**没有"系统主动推送"路径**（日程到点、出发提醒、定时事项响起）。

## 行业调研结论

### Echo Show / Alexa 官方设计原则

> "Display templates should typically only be returned when responding with **information the user requested**. Other responses like questions for more information don't typically include display templates."

> "Body Template 6 is ideal for **multi-turn situations**... use it for: welcome, asking questions, navigation, clarification, and goodbye."

**翻译**：
1. 视觉模板按"响应类型"决策，**不按字数**
2. 多轮对话用同一个模板保持一致

### Google Nest Hub

- 知识图谱有结构化答案 → 卡片
- 没有结构化数据 → 纯语音
- 决策依据是**"是否有可视化数据"**，不是字数

### CarPlay 设计哲学

- 语音为主交互
- 触屏作辅助
- conversational app 用 voice control template

### iOS Siri 唤醒形态

- 唤醒后**顶部** banner 显示识别中的文字（不在底部）
- 答复浮层覆盖在 app 上方
- 不打断当前界面

### 1m 距离视觉规范

- 字号需显著加大（建议 hero ≥ 32-48sp，body ≥ 16-18sp）
- 信息密度低，每屏只放最重要的核心
- 卡片留白足够，避免视觉拥挤

## 设计方案：4 种 Surface

### Surface 总览

| # | Surface | 用途 | 触发 | 消散 |
|---|---|---|---|---|
| 1 | **球** | 状态指示（待机/在听/在想/完成/等确认/静音） | 永远在屏（右下角） | 不消散 |
| 2 | **顶部小浮窗** | ASR 识别中文字 / 系统推送 banner | 用户说话 / 系统推送 | partial: 用户说完；推送: 5s |
| 3 | **全屏大卡** | 助手响应 / confirm / 错误 / 紧急提醒 | 助手要展示内容 / 等用户决策 / 提醒到点 | 答复型: TTS 完 + 5s；决策型: 不消散 |
| 4 | **抽屉** | 看历史 | 用户主动上滑 | 用户主动 ✕ |

**关键原则**：每种 surface 的触发条件**完全在代码控制内**，不依赖模型输出长度。

### 球（Surface 1）

| 状态 | 视觉 | 触发 |
|---|---|---|
| 待机 | 蓝色呼吸 | 默认 |
| 在听 | 蓝色 + 能量光环（已有 audioLevel） | 唤醒 / 长按 |
| 在想 | 蓝色旋转点 | LLM 思考中 |
| 完成 | 绿色脉冲 0.5s 回蓝 | 助手回复完毕 |
| 等确认 | 暖橙脉冲 | confirm 浮层弹出 |
| 静音 | 灰色 | 用户主动 mute |

球**不再显示文字答复**——所有内容只进对应 surface。球只是"麦克风 + 状态指示器"。

位置：右下角（避免遮挡 dashboard 中央内容）。

### 顶部小浮窗（Surface 2）

**两种用途共用同一组件**：

#### 2a. ASR partial（用户说话过程中）

```
┌──────────────────────────────────────────────┐
│ Dashboard 仍可见                              │
│   ┌─ 🎤 在听... ─────────────────┐           │ ← 顶部居中
│   │ 上海今天天气怎么...            │           │   宽度 480-560px
│   └────────────────────────────┘           │   高 56px
│                                              │
│                                       ●     │
└──────────────────────────────────────────────┘
```

- 触发：用户唤醒并开始说话
- 内容：ASR 实时识别的 partial 文本
- 消散：用户说完话（ASR final）→ 浮窗淡出 → 全屏大卡接管

#### 2b. 系统推送 banner（普通提醒）

```
┌──────────────────────────────────────────────┐
│   ┌─ 🔔 还有 3 件事 ─────────────[展开]──┐  │
│   │ 下午 3 点需求讨论会，再过 30 分钟      │  │
│   └────────────────────────────────────┘  │
│                                              │
│ Dashboard 全屏可见                            │
│                                       ●     │
└──────────────────────────────────────────────┘
```

- 触发：定时提醒到点 / 出行提醒 / 日程预告
- 内容：1-2 行核心信息
- 消散：5s 自动收起 / 点击「展开」进抽屉看完整

### 全屏大卡（Surface 3）—— 核心 surface

**统一容器，按响应类型变内容**：

#### 3a. 信息卡答复（含 `<assistant-card>`）

```
┌──────────────────────────────────────────────┐
│ ▒▒▒▒ Dashboard 模糊背景 ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒│
│                                              │
│   ┌────────────────────────────────────┐     │
│   │ ☀ 上海 · 多云                      │     │ 全屏大卡
│   │                                    │     │ 占屏 70-80% 宽
│   │       24°  18-27°                  │     │ 字号比抽屉大 1.5x
│   │                                    │     │
│   │ 出门带把薄外套，下午太阳大注意防晒。│     │
│   │                                    │     │
│   │             [完整查看 ↑]            │     │ 上滑/点按开抽屉
│   └────────────────────────────────────┘     │
│                                              │
└──────────────────────────────────────────────┘
```

#### 3b. 工具成功反馈

```
┌──────────────────────────────────────────────┐
│   ✅ 已加到日程                              │
│                                              │
│   📅 需求讨论会                              │
│   ⏰ 5月12日 15:00 - 16:00                   │
│   🔔 提前 10 分钟提醒                         │
│                                              │
│   [撤销]                                     │
└──────────────────────────────────────────────┘
```

#### 3c. 纯文字答复（"现在几点了"）

```
┌──────────────────────────────────────────────┐
│                                              │
│              14:30                           │ ← 字号超大
│                                              │
│         星期一 · 5 月 12 日                   │
│                                              │
└──────────────────────────────────────────────┘
```

#### 3d. 澄清/追问

```
┌──────────────────────────────────────────────┐
│                                              │
│  这个会议是几点？                            │
│                                              │
│  🎤 在听...                                  │ 自动重新开麦
│                                              │
└──────────────────────────────────────────────┘
```

#### 3e. confirm 等待

```
┌──────────────────────────────────────────────┐
│ ⚠ 等你确认                                   │
│                                              │
│ 要给「需求讨论会」加 10 分钟提醒吗？          │
│                                              │
│ ┌────────┐    ┌─────────┐                   │
│ │ 取消   │    │ 确认    │                   │
│ └────────┘    └─────────┘                   │
└──────────────────────────────────────────────┘
```

#### 3f. 错误/异常

```
┌──────────────────────────────────────────────┐
│ ⚠ 没成功                                     │
│                                              │
│ 没拿到稳定的天气信息                         │
│                                              │
│ ┌────────────────────┐                       │
│ │ 重试               │                       │
│ └────────────────────┘                       │
└──────────────────────────────────────────────┘
```

#### 3g. 紧急提醒到点

```
┌──────────────────────────────────────────────┐
│ 🔔 提醒                                      │
│                                              │
│ 需求讨论会                                   │
│ 现在开始（5月12日 15:00）                    │
│                                              │
│ ┌──────┐  ┌────────┐  ┌──────┐               │
│ │ 已读 │  │ 稍后  │  │ 关闭 │               │
│ └──────┘  └────────┘  └──────┘               │
└──────────────────────────────────────────────┘
```

### 大卡消散规则

| 类型 | 消散行为 |
|---|---|
| 答复型（3a/3b/3c/3f） | TTS 播完 + 5 秒自动消散 |
| 等待型（3d/3e/3g） | 不自动消散，等用户语音/触屏决策 |
| 用户触屏点卡 | 延长大卡时间（重新计时） |
| 用户上滑 | 大卡淡出，抽屉唤起接管 |

### 响应类型判定逻辑（代码层）

| 触发条件（代码可知） | 响应类型 | 大卡形态 |
|---|---|---|
| 答复包含 `<assistant-card>` block | 信息卡答复 | 3a |
| tool_call 成功（create/update/delete/complete_task）| 工具成功反馈 | 3b |
| 答复无 card / 无 tool / 无 confirm | 纯文字答复 | 3c |
| 模型返回是问句 + 待补字段（_isMissingWriteSlot 等） | 澄清/追问 | 3d |
| `state.pendingConfirm != null` | confirm 等待 | 3e |
| 答复有错误（ttsError / progress.error / 工具异常） | 错误 | 3f |
| 系统推送：定时提醒到点 | 紧急提醒 | 3g |

**没有"按字数判断"的逻辑**——完全消除黑盒。

### 抽屉（Surface 4）

- 触发：用户主动从底部**上滑**唤起 / 点击大卡的「完整查看 ↑」
- 默认高度：60%（492 px on iPad Air 横屏）
- 三段式：peek（120px）/ half（60%）/ full（90%）—— 用户拖 grabber 调整
- 内容：
  - 完整聊天历史（用户消息 + 助手回复 + inline 卡）
  - 输入条 + 麦克风按钮
  - Header 56px：助手头像 + 状态 + 历史/设置/关闭按钮
- 关闭：用户点 ✕ / 下拉到底

抽屉跟全屏大卡的关系：
- 大卡是"瞬时全屏接管 + 自动消散"
- 抽屉是"持久看历史 + 用户主动控制"
- 二者**不会同时出现**（大卡出现时抽屉自动收起）

## 完整流程图

```
[Dashboard 满屏]
       ↓ 唤醒（说"小治小治"或长按球）
[球切"在听" + Dashboard + 顶部浮窗（识别 partial）]
       ↓ 用户说完话
[顶部浮窗淡出 + 球切"在想" + 全屏大卡接管 + TTS 同步]
       ↓ TTS 完 + 5s（除非是 3d/3e/3g）
[Dashboard 满屏]
       ↓ 用户上滑（任意时刻）
[抽屉 60% 看历史]
```

并行链路：

```
[系统主动推送]
   ↓
普通提醒 → [顶部浮窗 banner，5s 后消散 / 点展开进抽屉]
紧急提醒 → [全屏大卡 3g，等用户决策]
```

## 实施工作量评估

| 任务 | 工作量 | 备注 |
|---|---|---|
| 抽出 `assistant_surface_router.dart`，按响应类型决策 | 0.5d | 替代 `_resolveReplySurface` |
| 全屏大卡组件（hero/body/footer 7 种形态） | 1.5d | 新建 `FullScreenAnswerCard` widget |
| 顶部小浮窗组件（ASR partial / banner 双用途） | 0.5d | 新建 `TopFloatingBanner` widget |
| 抽屉重构：占 60% bottom sheet + 三段式拖动 | 1d | 改 `AssistantDrawer`，拖手势 |
| 大卡自动消散逻辑（含触屏延长 / 上滑跳抽屉） | 0.5d | timer + 手势 |
| 球状态扩展（加"等确认"暖橙）| 0.3d | 已有 audioLevel 基础 |
| 紧急提醒接入 | 1d | 联动 flutter_local_notifications，弹大卡 3g |
| 普通推送接入 | 0.5d | 顶部 banner 复用 |
| 移除 compactCard / replySurface 旧逻辑 | 0.5d | 清理 controller 与 widget |
| 全量回归测试 | 1d | 分类后所有 case 单测 |
| **合计** | **~7-8 天** | 单人不间断估算 |

## 边界与注意事项

1. **键盘弹起**：抽屉 sheet 自动顶高，但保留 dashboard ≥100px 可见
2. **横竖屏旋转**：当前主场景是横屏，竖屏作降级支持（抽屉比例自适应）
3. **多个 confirm 排队**：先到先弹，后续 confirm 替代当前大卡（不堆叠）
4. **多个推送排队**：banner 队列，先到先消化
5. **大卡 + 提醒冲突**：紧急提醒优先于答复型大卡（打断助手回答以播报提醒）
6. **球永远可见**：抽屉打开时仍显示在右下角（被压到 sheet 上方边缘）
7. **TTS 中断**：大卡触屏延长时 TTS 不打断；用户主动 ✕ 时 TTS 立即停
8. **离线 / 错误**：如果 LLM 调用失败 → 大卡 3f 显示错误 + retry

## 推迟项 / 待立项 V2

- 大卡内容自适应字号（按内容长度动态缩放）
- 抽屉宽度可拖拽（横向拖动调宽窄）
- 多设备配对（手机 → 平板镜像）
- 视频/图片消息（卡片含图）

## 关联文档

- `docs/info_card_system.md` — 信息卡 Phase 1-7 已落地
- `docs/tts_voice_optimization.md` — 火山豆包 TTS 2.0 已落地
- `docs/nlu_filler_stripper.md` — 中文语气词剥离 P0 已落地
- `docs/voice_endpointing_strategy.md` — 语音端点检测已落地

## 行业调研来源

- [Designing Skills for Echo Show: Choosing the Right Display Template](https://developer.amazon.com/en-US/blogs/alexa/post/982c9134-fbf6-4465-a105-5f5c4b4774f6/building-for-echo-show-choosing-the-right-templat)
- [Building for Echo Show and Echo Spot: VUI & GUI Best Practices](https://developer.amazon.com/en-US/blogs/alexa/post/05a2ea89-2118-4dcb-a8df-af3d8ac623a8/building-for-echo-show-and-echo-spot-vui-gui-best-practice)
- [Use Display Templates - Alexa Skills Kit](https://developer.amazon.com/en-US/docs/alexa/custom-skills/display-and-behavior-specifications-for-alexa-enabled-devices-with-a-screen.html)
- [What you can ask Google Assistant - Nest Help](https://support.google.com/googlenest/answer/7172842)
- [Voice UI Design Guide 2026 - VUI Best Practices](https://fuselabcreative.com/voice-user-interface-design-guide-2026/)
- [Spatial UI Design - IxDF](https://ixdf.org/literature/article/spatial-ui-design-tips-and-best-practices)
- [Bottom Sheets vs Fullscreen Modals - Design for Native](https://designfornative.com/bottom-sheets-vs-fullscreen-modals/)
- [Sheets - Apple HIG](https://developer.apple.com/design/human-interface-guidelines/sheets)
- [Ambient Computing UX](https://lollypop.design/blog/2020/november/ambient-computing-user-experience-design/)
- [Nest Hub Max Smart Display Review](https://undecided.tech/nest-hub-max-smart-display-review/)
