# 信息卡系统研发方案

最近更新：2026-05-10。
状态：**Phase 1-7 实施完成**，自动化测试 129/129 全绿，等真机端到端验证。

## 实施进度

| Phase | 状态 | commit | 已 push |
|---|---|---|---|
| 1 数据层抽象 | ✅ 完成 | `5beee68` | ✅ |
| 2 BaseAssistantCard 骨架 + 7 套主题 token | ✅ 完成 | `692812e` | ✅ |
| 3 天气卡视觉重做（4 套主题色 + 按需 chip + advice） | ✅ 完成 | `be5ca4a` | ⏳ 待真机 |
| 4 汇率卡 | ✅ 完成 | `dbdb9ec` | ⏳ 待真机 |
| 5 世界时间卡（单/多 union） | ✅ 完成 | `1759235` | ⏳ 待真机 |
| 6 景点推荐卡（强校验防瞎编） | ✅ 完成 | `4f9f245` | ⏳ 待真机 |
| 7 酒店推荐卡（复用 Poi，价格突出） | ✅ 完成 | `4e59fc1` | ⏳ 待真机 |
| 8 收尾验证 | ⏳ 等真机端到端冒烟 | — | — |

**Phase 8 还差**：真机过 5 类卡端到端冒烟（清单见文末）→ 视觉如有问题修复 → 全部 push → 更新本文档与 memory 状态为"已落地" → 2 周后清理 advice / summary 兼容字段。

**已知未做（推迟）**：
- 关键转折行（需要 timeline.condition 字段）→ 留 Phase 9
- 展开/收起按钮（需要 24h / 7 天数据扩展）→ 单独立项
- "看更多"按钮（景点/酒店）→ 等 POI API 数据源确定后接通


## 背景

当前对话回答里只有「天气卡」一种结构化卡片：用户问天气时，模型在回复尾部输出 `<assistant-card type="weather">{...}</assistant-card>`，前端正则解析渲染。问题：

1. 天气卡本身视觉/信息密度差（详见「现状诊断」）。
2. 数据/解析/渲染层都是为天气硬编码的，要扩展到汇率、世界时间、景点、酒店，必须先抽象。
3. 卡片视觉规范缺失，每加一种就重新发明轮子。

目标：建立**统一的信息卡系统**，本轮覆盖 5 种卡（天气重做 + 汇率 + 世界时间 + 景点 + 酒店），并保证现有天气问答功能在每一阶段都正常工作。

## 现状诊断

### 数据层
- `lib/features/assistant/domain/assistant_result_card.dart`
  - `AssistantResultCardKind` 枚举只有 `weather`
  - `AssistantResultCard` 字段全是天气专用（city/condition/currentTemp/tempRange/humidity/airQuality/wind/timeline/summary）
  - `parseAssistantDisplayContent` 解析器内部硬编码 `if (type != 'weather')` 直接返回 null

### 渲染层
- `lib/features/assistant/presentation/widgets/assistant_result_card_view.dart`
  - 一个 `AssistantResultCardView`，内部 switch kind → `_WeatherResultCard`
  - 头部 36-40px 小图标 + 标题/副标题 → 大温度 + 范围 → 3 个 chip → 4 个 timeline → summary。**信息密度过高，没有视觉锚点**
  - 配色单一（蓝白渐变），不区分晴/雨/雪/阴
  - summary 与 hero 信息重复（"今天上海多云转晴，最高 27 度" 与上面温度+condition 重复）

### Prompt 层
- `lib/features/assistant/prompts/system_prompt.dart` L97-102 教模型输出 weather 卡 schema
- 没有「不要出卡」的明确反例，模型偶尔会在不该出卡时出卡

### 使用点
- 抽屉聊天气泡 `MessageBubble`（`message_bubble.dart:91-95`），full 形态
- 紧凑回复卡 `_CompactReplyCard`（`assistant_drawer.dart:1132-1135`），compact 形态
- 状态字段 `compactReplyCard`（`assistant_state.dart:231`）/ `messages[].resultCard`（`assistant_message.dart`）

## 影响面盘点（避免破坏其他功能）

下面列出本次改造**可能涉及但不能破坏**的功能，每条都要在每个阶段验证。

| # | 功能 | 关联文件 | 风险点 | 兜底验证 |
|---|---|---|---|---|
| 1 | 现有天气问答 | 上述全部 | 抽象后字段映射出错 → 卡片渲染异常 | 天气问答端到端冒烟（"上海今天天气"），渲染必须像素级一致直到 Phase 3 |
| 2 | 紧凑回复卡（球外卡） | `_CompactReplyCard` | `compactReplyCard` 类型变化 → 抽屉外卡崩 | 状态字段类型保持 `AssistantResultCard?` 不变 |
| 3 | 抽屉消息气泡 | `MessageBubble` | `message.resultCard` 类型变化 | 同上 |
| 4 | TTS 朗读 | `_buildSpeechText` | 朗读文本来自 `displayContent.text` 不是 `summary` | 已确认不影响（grep 验证，见 `assistant_controller.dart:3299`） |
| 5 | 历史会话 | （无持久化） | 数据结构变更不影响会话恢复 | 当前无 message 持久化，确认无历史负担 |
| 6 | API 上行格式 | `AssistantMessage.toApiJson` | `resultCard` 不进 API JSON | 已确认 toApiJson 不引用 resultCard |
| 7 | 测试套件 | `test/features/assistant/*` | mock 了 message 结构 | 每个 phase 跑全量 `flutter test` |
| 8 | 工具调用流程 | `assistant_controller.dart` 大段 | 不在改动路径上 | 不改动 |
| 9 | 语音端点检测 | 上一轮已落地 | 不在改动路径上 | 不改动 |
| 10 | 看板/任务/编辑器 | `features/dashboard, features/task` | 不在改动路径上 | 不改动 |
| 11 | `_resolveReplySurface` 决策逻辑 | `assistant_controller.dart` | 决定卡片走 drawer 还是 compactCard | 抽象不能改决策语义 |
| 12 | followUp 续听 | `followUpRemainingMs` | 与 compact 卡同生命周期 | 不改动 |

**总原则**：Phase 1-2 是**纯重构**，UI 与 prompt 输出格式都不变；Phase 3 起才动视觉与 prompt。每个 phase 单独 commit，可独立回滚。

## 总体架构设计

### 数据层目标结构

```
abstract class AssistantResultCard {
  String get type;              // 'weather' / 'exchange_rate' / 'world_clock' / 'poi_recommend'
  String get fallbackSpeechText; // 兜底朗读文本（一般不用，TTS 走正文）
}

class WeatherCard extends AssistantResultCard { ... }
class ExchangeRateCard extends AssistantResultCard { ... }
class WorldClockCard extends AssistantResultCard {
  // 单/多城市 union，cities.length == 1 走单值视图，否则走列表视图
  final List<WorldClockEntry> cities;
}
class PoiRecommendCard extends AssistantResultCard {
  // 景点/酒店共用，subtype 区分
  final PoiKind subtype; // attraction / hotel
  final List<PoiItem> items;
}
```

`AssistantDisplayContent.resultCard` 字段类型保持 `AssistantResultCard?`，**调用方零修改**。

### 解析器注册表

```
typedef CardParser = AssistantResultCard? Function(Map<String, dynamic> json);

class AssistantCardRegistry {
  static final Map<String, CardParser> _parsers = {
    'weather': WeatherCard.tryParse,
    'exchange_rate': ExchangeRateCard.tryParse,
    'world_clock': WorldClockCard.tryParse,
    'poi_recommend': PoiRecommendCard.tryParse,
  };

  static AssistantResultCard? parse(String type, Map<String, dynamic> json) {
    return _parsers[type]?.call(json);
  }
}
```

新增卡型只需要：① 加 model 类 + tryParse；② 注册一行；③ 加 widget；④ 加 prompt 段落。**不需要改任何现有代码**。

### 渲染层目标结构

```
AssistantResultCardView (dispatcher)
  switch (card.type)
    weather → WeatherCardView
    exchange_rate → ExchangeRateCardView
    world_clock → WorldClockCardView
    poi_recommend → PoiRecommendCardView

每个 *CardView 内部使用：
  BaseAssistantCard(
    theme: CardThemeToken,    // 来自 card_theme.dart
    hero: ...,
    body: ...,
    footer: ...,
    compact: bool,
  )
```

`BaseAssistantCard` 提供统一的圆角/阴影/边框/外距/padding，子卡只填 hero/body/footer 三个 slot，并选择主题色 token。

### 主题色板（card_theme.dart）

| token | 主渐变 | accent | 适用 |
|---|---|---|---|
| `sunny` | `#FFD194 → #FFA374` | `#FF8A4C` | 天气-晴/暖 |
| `rainy` | `#6FA8DC → #3D5A80` | `#5B82B5` | 天气-雨 |
| `snowy` | `#E0F2FF → #B8D6F0` | `#5B82B5` | 天气-雪 |
| `cloudy` | `#A8B5C8 → #6E7E96` | `#5B6A82` | 天气-阴/多云 |
| `gold` | `#FFE9A8 → #F2C94C` | `#D69E00` | 汇率/价格 |
| `night` | `#2A3D6F → #0F1A3B` | `#7090E0` | 世界时间 |
| `neutral` | `#FFFFFF → #F4F8FF` | `#3C7BFF` | 列表（景点/酒店） |

字号/字重/角度/阴影统一：

| 槽位 | full | compact |
|---|---|---|
| 卡圆角 | 22 | 18 |
| 外阴影 | `Color(0x140D47A1) blur 28 y 12` | `Color(0x0F0D47A1) blur 18 y 8` |
| Hero 主数字 | 56sp / w900 | 36sp / w900 |
| Hero 标题 | 16sp / w800 | 14sp / w800 |
| Body chip | 12sp / w700 | 12sp / w700 |
| Footer 文字 | 13sp / w600 | 12sp / w600 |

## 分阶段研发计划

**总策略**：8 个 phase，每个 phase 单独 commit，每个 commit 都通过 `flutter analyze + flutter test` + 手动天气问答冒烟。Phase 1-2 不改 UI 不改 prompt，是纯重构。Phase 3 起改 UI 和 prompt，每改一项跑回归。

---

### Phase 1：数据层抽象迁移（不改 UI，不改 prompt）

**目标**：把 `AssistantResultCard` 从 sealed class 改成抽象基类 + 子类，但对外暴露的接口、字段访问方式、渲染结果完全不变。

**任务清单**：
1. 新建 `lib/features/assistant/domain/cards/` 目录
2. 抽 `AssistantResultCard` 为抽象基类（保留 `kind` getter 兼容旧调用，标 deprecated）
3. 新建 `weather_card.dart`，`WeatherCard extends AssistantResultCard`，字段照搬
4. 新建 `assistant_card_registry.dart`，注册 weather parser
5. 改 `parseAssistantDisplayContent` 走注册表
6. **`compactReplyCard` 字段类型保持 `AssistantResultCard?`，状态层零改动**
7. 渲染层 `AssistantResultCardView` 内部 switch 改为按 `card.type` 字符串而不是 enum

**影响范围**：
- `assistant_result_card.dart` 拆分
- `assistant_message.dart` 字段类型不变
- `assistant_state.dart` 字段类型不变
- `assistant_controller.dart` 调用 `parseAssistantDisplayContent` 处不变
- `message_bubble.dart` / `_CompactReplyCard` 不变
- `assistant_result_card_view.dart` switch 表达式微改

**验收标准**：
- [ ] `flutter analyze` 通过
- [ ] `flutter test` 全绿
- [ ] 手动："上海今天天气" → 卡片渲染**与改造前像素级一致**
- [ ] 关闭抽屉再打开 → compact 卡仍显示
- [ ] 续听窗口 → 朗读文本无变化

**回滚**：单 commit revert。

---

### Phase 2：卡片骨架 BaseAssistantCard 与主题 token

**目标**：抽出可复用的卡壳，把 weather 卡迁过去，**视觉仍保持改造前一致**（先不动样式，只走骨架）。

**任务清单**：
1. 新建 `lib/features/assistant/presentation/widgets/cards/` 目录
2. 新建 `card_theme.dart`：定义上面表格中所有 token
3. 新建 `base_assistant_card.dart`：提供 hero/body/footer slot + theme 注入
4. 把现有 `_WeatherResultCard` 的 build 内容迁到 `WeatherCardView`，套 `BaseAssistantCard` 壳
5. 主题用 `cloudy` token（与现有蓝白渐变最接近，避免视觉跳变）
6. `AssistantResultCardView` 改为 dispatcher

**影响范围**：仅渲染层，不动数据/状态/prompt。

**验收标准**：
- [ ] `flutter analyze` 通过
- [ ] `flutter test` 全绿
- [ ] 天气卡视觉**与 Phase 1 后一致**（最多有 1-2px 角度差异，可接受）
- [ ] compact 卡内嵌天气卡正常

**回滚**：单 commit revert。

---

### Phase 3：天气卡视觉重做（动 UI、动 prompt）

**目标**：实施第三节方案中的天气卡新设计——按需触发字段、4 套主题色、故事化 summary、inline 展开。

**任务清单**：

A. 视觉
1. `WeatherCardView` 按 condition 选 `sunny/rainy/snowy/cloudy` 主题
2. Hero 区：48-56sp 主温度 + 18sp 范围 + 32px 大图标
3. Body 区：**按需触发**——仅当满足以下条件才显示对应字段：
   - 湿度 chip：humidity > 70% 或 < 30%
   - 空气 chip：AQI > 100（解析数字部分）
   - 风力 chip：风力 ≥ 4 级
   - 关键转折行：timeline 中检测到 condition 变化（雨/雪/晴切换）或温度跨度 ≥ 5°
4. Footer：故事化 summary（"出门记得带伞，傍晚回程要避开 17-18 点雨势"）
5. 增加「展开/收起」按钮：默认收起精简态；展开后显示完整 24h timeline + 7 天预报（如果 prompt 有要的话）
6. compact 形态：去掉关键转折行，只保留 hero + footer

B. Prompt 改造（`system_prompt.dart`）
1. 把 weather schema 字段语义改清楚：
   - `summary` 改名 `advice`，要求"建议/提醒"语气，不要重复 hero 信息
   - `timeline` 增加"标记关键转折点"的指引
   - 字段标注"该字段在异常时填，正常时可省"
2. 加反例段落：「天气优良时不要塞 humidity/airQuality；用户没问详情时 timeline 最多 2 条」
3. 兼容旧字段名：解析层若拿到 `summary` 当 `advice` 用，避免模型 transition 期间崩

**影响范围**：
- `WeatherCardView` 重写
- `weather_card.dart` 字段重命名（保留旧字段读取兼容）
- Prompt 段落

**验收标准**：
- [ ] `flutter analyze` 通过
- [ ] `flutter test` 全绿
- [ ] 真机问"上海今天天气"→ 出现新卡，主题色与天气匹配
- [ ] 真机问"上海空气怎么样"→ 仅在 AQI 异常时出现空气 chip
- [ ] 模型偶尔仍输出旧字段名 `summary` → 渲染正常（兼容期）
- [ ] TTS 朗读文本仍是 `displayContent.text`，不引用 advice
- [ ] 紧凑卡天气主题切换正常

**回滚**：保留 Phase 2 的 cloudy 主题分支即可降级。

**已知风险**：
- 模型可能不严格按"按需"输出，仍输出全部字段 → 渲染层兜底过滤（核心：渲染层做最后裁决，不依赖 prompt 听话）
- 旧版字段名兼容期至少 2 周，之后清理

---

### Phase 4：汇率卡（A 类示例，验证抽象层）

**目标**：完整加一种新卡，验证 Phase 1-2 的抽象是否真好用。

**任务清单**：
1. `domain/cards/exchange_rate_card.dart`：
   ```
   ExchangeRateCard {
     String fromCurrency;     // "USD"
     String fromCurrencyName; // "美元"
     String toCurrency;       // "CNY"
     String toCurrencyName;   // "人民币"
     double fromAmount;       // 100
     double toAmount;         // 723.45
     String? change24h;       // "+0.12%"
     bool? isUp;
     String? updatedAt;       // "5 分钟前"
     String? note;            // "仅供参考"
   }
   ```
2. 注册到 registry
3. `widgets/cards/exchange_rate_card_view.dart`：用 `gold` 主题
   - Hero：「100 USD = 723.45 CNY」+ 副标题「美元 → 人民币」
   - Body：1 个 chip「24h +0.12% ↑」
   - Footer：「数据 5 分钟前更新 · 仅供参考」
4. Prompt 加段落：触发条件（"换算/汇率/折算"）+ schema + 反例（"币种不全或数字不稳就不要出卡"）
5. 解析校验：fromAmount/toAmount 必须是正数，币种代码必须 3 字母大写

**验收标准**：
- [ ] `flutter analyze` 通过 + `flutter test` 全绿
- [ ] 真机问"100 美元等于多少人民币"→ 出现汇率卡
- [ ] 真机问"美元最近怎么样"→ **不出**汇率卡（无具体数字）
- [ ] 字段不全 → 降级到文字
- [ ] 天气卡功能不受影响

**回滚**：单 commit revert。

---

### Phase 5：世界时间卡（验证单/多 union）

**目标**：测试基础结构能否支持单/多元素并存。

**任务清单**：
1. `domain/cards/world_clock_card.dart`：
   ```
   WorldClockCard {
     List<WorldClockEntry> cities; // 至少 1 个，最多 5 个
   }
   WorldClockEntry {
     String cityName;     // "东京"
     String timezone;     // "Asia/Tokyo"
     String localTime;    // "14:30"
     String weekday;      // "周五"
     String? offsetHint;  // "+1h vs 北京"
     bool? isDst;         // 夏令时切换标记
   }
   ```
2. 渲染：
   - 单城市（cities.length == 1）：Hero 大号 HH:mm + 副标题"东京·周五" + chip 时差
   - 多城市：纵向列表（最多 3 行展示，超出"还有 N 个城市"），每行"城市 时间 时差"
   - 主题 `night`
3. Prompt：触发"几点/时差/世界时间"，反例"模糊问'国外什么时候开会'不出卡"
4. 时差展示要明确"vs 当前用户城市"——用 `get_user_location` 拿到的城市作为基准

**验收标准**：
- [ ] 真机问"东京几点"→ 单城市卡
- [ ] 真机问"伦敦、纽约、东京几点"→ 列表卡（3 行不滚动）
- [ ] DST 切换日期 → 显示"夏令时已切换"
- [ ] 不知道当前用户城市时 → 不显示时差 chip（不报错）
- [ ] 天气/汇率卡仍正常

---

### Phase 6：景点推荐卡（C 类骨架，重风险点：编造）

**目标**：验证列表型卡 + 严格的"反编造"机制。

**任务清单**：
1. `domain/cards/poi_recommend_card.dart`：
   ```
   PoiRecommendCard {
     PoiKind subtype;        // attraction / hotel / restaurant
     String title;            // "上海推荐 3 个景点"
     String subtitle;         // "按距离排序"
     List<PoiItem> items;     // 最多 5 个，渲染最多 3 个
     String? sourceNote;      // "信息来自 XX，以官方为准"
   }
   PoiItem {
     String name;
     double? rating;          // 0-5
     String? priceLabel;      // "¥ 320 起" or null
     String? distanceLabel;   // "1.2km"
     String? tag;             // "亲子"/"夜景"
     String? iconEmoji;       // 类目图标，无图片
   }
   ```
2. 渲染（`poi_recommend_card_view.dart`）：
   - Hero：title + subtitle
   - Body：纵向列表 3 行（**禁横向滚动**，看板约束）
   - Footer：sourceNote + "看更多" 按钮（先占位，跳转留 TODO）
   - 主题 `neutral`
3. 严格校验（解析层）：
   - rating 必须 0-5
   - distance 必须有单位（km/m）
   - items 至少 1 条，全条目字段缺失 → 整卡降级
4. Prompt 强约束：
   - "推荐景点必须基于联网搜索结果，不得编造名称、评分、价格"
   - "任一字段不确定就不要出卡，改用纯文字回答"
   - "景点数量不超过 5，距离按近到远排"
   - 反例：列了一堆评分但没有联网证据 → 不出卡

**验收标准**：
- [ ] 真机问"上海有什么好玩的"→ 出现景点卡（3 条）
- [ ] 真机问"附近景点"→ 调 get_user_location 后再出卡
- [ ] 模型瞎编（场景：联网失败仍硬出）→ 解析校验拦截，降级文字
- [ ] 列表行不会因为名字过长撑破卡片（ellipsis）
- [ ] 纵向滚动正常，**横向无滚动**
- [ ] 天气/汇率/世界时间卡仍正常

---

### Phase 7：酒店推荐卡（复用 Phase 6 骨架）

**目标**：用同一个 widget 跑酒店场景，证明 PoiRecommendCard 的扩展性。

**任务清单**：
1. 在 `PoiKind.hotel` 分支下，PoiItem 的 priceLabel 改成大字号（用户决策点）
2. Prompt 加酒店场景段落：触发"酒店/住宿"，必须包含价格（"无价格不出卡"）
3. iconEmoji 默认值改"🏨"

**影响范围**：仅扩展 widget 内的 subtype 分支 + prompt 段落，不新增 widget 类。

**验收标准**：
- [ ] 真机问"上海便宜的酒店"→ 酒店卡
- [ ] 价格字段醒目
- [ ] 天气/汇率/世界时间/景点卡仍正常

---

### Phase 8：收尾验证

**任务清单**：
1. 所有卡端到端真机回归（见下方"测试与验证策略"）
2. `flutter analyze` 全绿
3. `flutter test` 全绿
4. 清理 Phase 3 兼容期保留的旧字段名（如果模型已稳定）
5. 更新 `docs/info_card_system.md` 状态为"已落地"
6. 更新 `memory/project_smart_workbench.md` 索引
7. 评估是否要把"看更多"按钮接通详情页（Phase 6 留的 TODO）

## 风险控制

### 共性风险

| 风险 | 缓解 |
|---|---|
| 模型瞎编 / 字段不稳 | 解析层严格校验，任何字段缺失直接 return null → 走文字回复 |
| 视觉变更击穿 compact 形态 | 每个 phase 都单独验证 `_CompactReplyCard` 内嵌渲染 |
| Prompt 改动影响其他场景 | 卡片相关段落与正文回答指引明确分隔；新增段落不改既有指引 |
| 测试 mock 与新结构不匹配 | 每 phase 跑全量 test；测试若用了具体字段，单独修 mock |
| 新卡 hero/body/footer 不适合所有场景 | BaseAssistantCard 三槽全 optional；不适合的子卡可绕开骨架直接用 BaseAssistantCard 的样式 token |
| 字段命名重构破坏 toApiJson | toApiJson 不引用 resultCard（已确认），但每 phase 仍跑公网请求测试 |

### 阶段间隔离

- 每个 phase 单独 commit + push，可独立 revert
- Phase 1-2 是纯重构，可在 1 天内完成并验证
- Phase 3 后任何一个 phase 失败，前面的 phase 不需要回滚（向前兼容）
- 任何 phase 完成后，如果发现真机有问题可以单独 revert 该 phase，不影响前序

### Prompt 兼容期

Phase 3 改 weather schema 字段名（summary → advice）期间，模型可能仍输出旧字段名。解析层做兼容映射：

```
final String advice = readString(json['advice']);
final String legacySummary = readString(json['summary']);
final String finalAdvice = advice.isNotEmpty ? advice : legacySummary;
```

兼容期 2 周后清理。

## 测试与验证策略

### 自动化

每个 phase 必须通过：

```
flutter analyze   # 0 issue
flutter test      # 全绿
```

涉及到的测试文件（已 grep）：

- `test/features/assistant/confirm_flow_test.dart`
- `test/features/assistant/public_response_flow_test.dart`
- `test/features/assistant/assistant_copywriter_test.dart`
- `test/features/assistant/assistant_request_router_test.dart`
- `test/features/assistant/auto_speak_decision_test.dart`
- `test/features/assistant/voice_wakeup_service_test.dart`
- `test/features/assistant/tool_args_test.dart`

如果 mock 用到了 `AssistantResultCard.weather(...)` 构造器，Phase 1 需要同步修改成 `WeatherCard(...)`。

### 真机回归冒烟（每 phase 最后一步）

- [ ] 抽屉问「上海今天天气」→ 渲染正常
- [ ] 球形态紧凑卡 → 渲染正常
- [ ] 续听窗口 → 朗读文本不变
- [ ] 关闭/重开抽屉 → 卡片状态正常
- [ ] 工具调用（创建日程）→ 不受影响
- [ ] 语音端点检测 → 不受影响

### 端到端冒烟（Phase 8）

- [ ] 天气：晴/雨/雪/阴 4 种主题切换
- [ ] 汇率：单币种 / 罕见币种（瑞郎、日元）
- [ ] 世界时间：单城市 / 多城市 / DST
- [ ] 景点：本地 / 异地 / 编造测试
- [ ] 酒店：价格醒目 / 无价格降级
- [ ] 真机长时段使用，无残留状态

## 回滚预案

| 场景 | 回滚操作 |
|---|---|
| Phase 1-2 重构后天气卡渲染异常 | 单 commit revert，回到改造前 |
| Phase 3 视觉重做后用户不接受 | revert Phase 3 commit，保留 Phase 1-2 抽象 |
| Phase 4-7 任意新卡上线后出问题 | revert 该 phase commit，其余卡不受影响 |
| Prompt 改动让模型回答质量下降 | 单独 revert prompt 段落，渲染层不动 |

## 附录 A：色板 token 完整清单

```dart
// lib/features/assistant/presentation/widgets/cards/card_theme.dart

class CardThemeToken {
  final List<Color> gradient;
  final Color accent;
  final Color heroTextColor;
  final Color bodyTextColor;
  final Color borderColor;

  static const sunny = CardThemeToken(
    gradient: [Color(0xFFFFD194), Color(0xFFFFA374)],
    accent: Color(0xFFFF8A4C),
    heroTextColor: Color(0xFF3A2410),
    bodyTextColor: Color(0xFF5A3D20),
    borderColor: Color(0xFFFFC890),
  );

  static const rainy = CardThemeToken(
    gradient: [Color(0xFF6FA8DC), Color(0xFF3D5A80)],
    accent: Color(0xFFA8D8FF),
    heroTextColor: Color(0xFFFFFFFF),
    bodyTextColor: Color(0xFFE0EAF5),
    borderColor: Color(0xFF5B82B5),
  );

  static const snowy = CardThemeToken(
    gradient: [Color(0xFFE0F2FF), Color(0xFFB8D6F0)],
    accent: Color(0xFF5B82B5),
    heroTextColor: Color(0xFF1F2A44),
    bodyTextColor: Color(0xFF3D4A6B),
    borderColor: Color(0xFFA8C8E5),
  );

  static const cloudy = CardThemeToken(
    gradient: [Color(0xFFA8B5C8), Color(0xFF6E7E96)],
    accent: Color(0xFFD0DAE8),
    heroTextColor: Color(0xFFFFFFFF),
    bodyTextColor: Color(0xFFE5EBF2),
    borderColor: Color(0xFF5B6A82),
  );

  static const gold = CardThemeToken(
    gradient: [Color(0xFFFFE9A8), Color(0xFFF2C94C)],
    accent: Color(0xFFD69E00),
    heroTextColor: Color(0xFF4A3500),
    bodyTextColor: Color(0xFF6E5200),
    borderColor: Color(0xFFE5BC4A),
  );

  static const night = CardThemeToken(
    gradient: [Color(0xFF2A3D6F), Color(0xFF0F1A3B)],
    accent: Color(0xFF7090E0),
    heroTextColor: Color(0xFFFFFFFF),
    bodyTextColor: Color(0xFFC8D2E8),
    borderColor: Color(0xFF1F2D5C),
  );

  static const neutral = CardThemeToken(
    gradient: [Color(0xFFFFFFFF), Color(0xFFF4F8FF)],
    accent: Color(0xFF3C7BFF),
    heroTextColor: Color(0xFF1F2A44),
    bodyTextColor: Color(0xFF60708A),
    borderColor: Color(0xFFE1E8F5),
  );
}
```

## 附录 B：阶段-代码-文件 影响矩阵

| Phase | domain | application | presentation | prompts | tests |
|---|---|---|---|---|---|
| 1 | 拆分 + 注册表 | 不动 | switch 微改 | 不动 | 修构造器调用 |
| 2 | 不动 | 不动 | 加 BaseCard + 主题 token + 迁移 weather | 不动 | 不动 |
| 3 | weather 字段重命名 | 不动 | weather 视觉重做 | weather 段落改写 | 修 mock 字段 |
| 4 | 加 exchange_rate | 不动 | 加 ExchangeRateCardView | 加段落 | 加测试（可选） |
| 5 | 加 world_clock | 不动 | 加 WorldClockCardView | 加段落 | 加测试（可选） |
| 6 | 加 poi_recommend | 不动 | 加 PoiRecommendCardView | 加段落 | 加测试（可选） |
| 7 | 不动 | 不动 | 扩 PoiKind.hotel 分支 | 加段落 | 不动 |
| 8 | 清理兼容字段 | 不动 | 不动 | 清理兼容段落 | 跑全量 |

## 附录 C：开工前 Checklist

开工前确认：

- [ ] 当前 main 分支干净，无未提交改动
- [ ] `flutter analyze` 已通过（基线）
- [ ] `flutter test` 已通过（基线）
- [ ] 真机问"上海今天天气" → 卡片正常（基线快照）
- [ ] 已和用户确认本方案的关键决策点
