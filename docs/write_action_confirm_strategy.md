# 写入动作确认与撤销策略（待讨论）

状态：方案已对齐，**暂不实施**，待后续触发再继续讨论。
最近一次讨论：2026-05-09。

## 背景

当前 assistant 写入类工具的执行模式分两档：

| 工具 | 现状 | 触发口 |
|---|---|---|
| `create_task` | confirm 卡 → 点确认才写 | `buildConfirmPreview()` 返回非 null |
| `update_task` | confirm 卡 → 点确认才写 | 同上 |
| `delete_task` | confirm 卡（warning 红色） | 同上 |
| `complete_task` | 直接执行 + 5s SnackBar 撤销 | `buildConfirmPreview()` 返回 null |

底层机制已就绪：
- `AssistantTool.buildConfirmPreview()` 返回 `null` 即跳过 confirm（已有的逃生口）
- `state.completionUndo` + `CompletionUndoListener` + `undoLastCompletion()` —— 撤销窗整套链路已跑通
- `taskMutationController.softDeleteTaskById` —— 删除是软删，可恢复
- `_lastConfirmedTask` —— 已记录"最近一次确认过的任务"，用于"刚才那个再改一下"

需求来源：希望 `create_task` 不再弹确认卡，直接创建，用户用撤销/删除兜底，提升交互效率。

## 行业惯例参考

| 产品 | create / update | delete |
|---|---|---|
| Google Calendar / Apple Reminders | 直接创建 + Undo | 删除要确认 |
| Gmail | 发邮件直接发 + 10s 撤回 | 归档/删除直接做 + Undo |
| Slack 发消息 / Notion 新建块 | 直接生效 | 删除前 confirm |
| Cursor / Copilot 编辑代码 | 默认 auto-accept | 删文件 confirm |

共识：**低风险写入 → fire-and-undo；破坏性/不可逆/影响他人 → confirm。** 与现有 complete/delete 分档思路一致。

## 推荐方案：分级策略，不动机制只动分级

按"用户能否在撤销窗内察觉异常"分三档：

### A 档 · 直接执行 + Undo（fire-and-undo）
- `complete_task`（已是）
- `create_task`（**改成这档**）：新增内容用户在日程/看板上立刻能看到，错了 7-8s 内可撤
- `update_task` 的低风险字段：仅改提醒档位、单次时间小幅微调（±60min 内）
  - 触发条件由 `buildConfirmPreview` 内部判断：仅这些字段变 → 返回 null

### B 档 · 必须 Confirm
- `delete_task`（保持）。理由：删除后列表里那一项消失，用户来不及察觉的概率最大；尤其语音场景 LLM 选错 task_id 是会发生的。软删兜底属于"恢复"成本，不是"撤销"体验。
- `update_task` 的高风险字段：改标题、改日期、改重复规则、对重复任务的整序列修改
- 任何信息不完整的 create（标题/日期缺失）—— 现有 `'信息没识别完整'` 卡片逻辑保留

### C 档 · 设置开关兜底
Settings 加一个"操作前总是二次确认"单开关（默认 OFF）。给重度谨慎用户回路。**不做 per-tool 配置**——三档开关会让产品变复杂。

## 必须守住的底线（避免代码堆积）

1. **不新建 `AssistantCreateUndo` / `AssistantUpdateUndo`**  
   现有 `AssistantCompletionUndo` 重命名为 `AssistantActionUndo`，加 `kind: create|complete|update`、`undoCallback: Future<void> Function()`。撤销逻辑由调用方传入。

2. **不新建 `_handlePendingCreateInput`**  
   现有 confirm 路径就是天然分流：`buildConfirmPreview` 返回 null → 不进 pending → 直接 `call()` → 写 undo 窗。整条路径不需要新分支，只动 `CreateTaskTool.buildConfirmPreview` 和"call 完成后注入 undo 窗"两处。

3. **不让 tool 自己读 settings**  
   "总是二次确认"开关由 controller 在调 `buildConfirmPreview` 之前判断；开则强制走 confirm，关则尊重 tool 返回值。tool 保持纯函数。

4. **不并存两套 SnackBar listener**  
   `CompletionUndoListener` 重命名为 `ActionUndoListener`，监听同一个 state 字段。

5. **不在 dashboard 里独立显示"刚创建的浮卡"**  
   保留单一撤销出口（SnackBar）+ 对话流里的结果卡（`AssistantResultCard` 已有，加"撤销"按钮）。

## 必须想清楚的边界问题

- **撤销窗时长**：complete 现在 5s 偏短，create 错了影响更大。建议统一 7-8s（不要 create 单独 10s、complete 5s，参数膨胀）。
- **撤销窗未结束就触发新动作**：当前 listener 是单 SnackBar，新动作来时 `hideCurrentSnackBar()` 立即关。需要确认：关掉 SnackBar 不等于自动撤销——上一个动作必须落地，否则用户连说两次"提醒我喝水"，第一条会丢。
- **离开 assistant 抽屉后 SnackBar 是否还在**：取决于 `ScaffoldMessenger` 挂在哪一层。建议挂在 root MaterialApp，抽屉关闭后撤销窗仍可见（顶级方案的通用做法）。
- **重复任务的创建**：create 一个 daily 重复，撤销时一并撤掉所有发生——`softDeleteTaskById` 按 task 维度软删天然成立，但要测一下 dashboard/周历的刷新是否同步。
- **语音模式下的"确认/取消"短语匹配**：create 不再 pending 后，`_parsePendingConfirmInput` 不会被 create 触发，但 delete/高风险 update 仍要走，逻辑保留。不要为了清理而删 `_handlePendingConfirmInput`。
- **`_lastConfirmedTask`**：语义要扩为"最近写入的"（含直接执行的 create），否则"刚才那个再改一下"会断链。

## 改动量预估

- 新增/改名 1 个 domain：`AssistantActionUndo`（替 `AssistantCompletionUndo`）
- 改 controller：`completeTaskById` 之后那段写 undo 窗的代码抽成 `_pushActionUndo()`，create/update 也调它（2-3 个调用点）
- 改 `CreateTaskTool.buildConfirmPreview`：信息齐全 → return null；不齐 → 现有提示卡保留
- 改 `UpdateTaskTool.buildConfirmPreview`：判断"低风险变更"则 return null
- 改 listener 文件名 + 读取字段名（机械替换）
- Settings 加一个 bool 开关 + controller 入口判断

净改动量 < 200 行，不新增模块、不动 tool 接口、不动数据库。

## 待决策问题（恢复讨论时先回答这两条）

1. **delete 要不要也降到 fire-and-undo**？目前倾向不要（删除场景"列表少了一项"不易察觉），但需用户用频率与体感判断。
2. **update 的"低风险字段"边界**怎么定？目前提议"提醒档位 + 单次时间 ±60min"，可调宽/调窄。

## 关联代码位置（开工时直接进这些文件）

- `lib/features/assistant/domain/assistant_tool.dart` — `buildConfirmPreview` 接口
- `lib/features/assistant/domain/assistant_confirm_preview.dart` — 预览数据模型
- `lib/features/assistant/application/assistant_state.dart` — `AssistantPendingConfirm` / `AssistantCompletionUndo`
- `lib/features/assistant/application/assistant_controller.dart` — `confirmPendingTool` / `cancelPendingTool` / `_handlePendingConfirmInput` / `_enterConfirmForDeterministicTool` / completion undo 注入点
- `lib/features/assistant/presentation/widgets/confirm_card.dart` — 确认卡 UI
- `lib/features/assistant/presentation/widgets/completion_undo_listener.dart` — 撤销 SnackBar listener
- `lib/features/assistant/data/tools/create_task_tool.dart` / `update_task_tool.dart` / `delete_task_tool.dart` / `complete_task_tool.dart`
