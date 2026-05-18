# 桌面助理沉浸式动效时序规范

> 适用场景：全屏沉浸式语音交互（非抽屉态）
> 改造方向：A（状态切换事件瞬间）+ C（EdgeGlow 跟 voiceEcho.phase 联动）
> 目标：用户无需文字标签即可清晰感知"在听 / 已识别 / 在处理"的状态切换

## 总览：5 个事件 + 4 段稳定态

```
[idle] → 唤醒 → [listening] → ASR final → [finalText] → 触发LLM → [processing] → 出结果 → [大卡]
                  稳定 0~Ns       0.5s 切换    稳定 0.8s      0.4s 脉冲     稳定 0~Ns       渐隐 0.4s
```

三个图层协同表达：

- **底部波形**（`_AssistantSignalVisual` / `AssistantBottomVoiceOverlay`）
- **整屏环境光**（`_AssistantEdgeGlow`）
- **文字层**（partial / final text 居中显示）

## 阶段 ①：listening 稳定态

| 图层 | 表现 |
|---|---|
| 底部波形 | 蓝色 `#2F6BFF` 条形频谱，**实时声压响应**（大声→振幅大，停顿→压平），36 根条，宽度 500→**880**，高度 34→**80** |
| 整屏 EdgeGlow | 蓝青 `#28D8FF + #6A7BFF` sweep，opacity 0.82（已最强），**转速从 2.6s/圈 加快到 1.8s/圈** |
| 文字层 | partial text，字号 24→**20**，w800→**w700**，居中 |
| 视觉重心 | 波形占屏 80% + 屏幕四边发光呼吸 → "整个屏幕在听" |

## 阶段 ②：listening → finalText 切换（A 方向核心）

ASR 给出 final 那一刻起，**0~500ms 关键帧**：

```
0ms ┃ 蓝色条形 + 声压最后一帧                     ← listening 末态
    ┃
100ms ┃ 36 根条往中线"塌缩"——envelope 翻转       ← 收束开始
    ┃   两端高度降至 0，中央 2-3 根维持
    ┃
250ms ┃ 残留一条横向"光线"贯穿屏幕宽度            ← 凝成一行
    ┃   颜色已从蓝渐变到绿 #16A078
    ┃
350ms ┃ 光线从中心向两侧"涟漪扩散"               ← 涟漪
    ┃   扩散到屏宽 90% 时 fade out
    ┃   同步：整屏 EdgeGlow 底边闪一次（亮度 1.4x）
    ┃
500ms ┃ 波形整体 fade in 回来，已是绿色平静态     ← finalText 稳定
```

**关键时长**：500ms 总长；350ms 时整屏底边脉冲一次（C 方向辅助）。

## 阶段 ③：finalText 稳定态（短暂 0.4~0.8s）

| 图层 | 表现 |
|---|---|
| 底部波形 | 绿色 `#16A078` 条形，振幅锁死在 0.2（不再响应声压），轻微呼吸 |
| 整屏 EdgeGlow | 青绿 `#19C7BD + #2F6BFF` sweep，opacity 0.58（降下来），转速回 2.6s/圈 |
| 文字层 | final text（用户最终说的话），字号 24，短暂高亮 0.6s 后回常态（color alpha 1.0 → 0.96） |
| 视觉重心 | "我听清楚了"——色温变暖、转速放缓，呼吸感 |

## 阶段 ④：finalText → processing 切换（A 方向第二个事件）

触发工具/LLM 那一帧起，**0~400ms 关键帧**：

```
0ms ┃ 绿色稳定波形                              ← finalText 末态
    ┃
80ms ┃ 整屏 EdgeGlow 来一次"脉冲呼吸"            ← C 方向核心
    ┃   sweep gradient 整体亮度 0.58 → 1.0 → 0.68
    ┃   颜色由青绿渐变为紫蓝（150ms 渐变）
    ┃   strokeWidth 临时 +30%，maskBlur 18 → 28
    ┃
240ms ┃ 底部波形开始"形态切换"                   ← 形态变化
    ┃   bars 上下错位 → 散开成 5 个点
    ┃   颜色完成 蓝/绿 → 紫 #6B5CFF 过渡
    ┃
400ms ┃ 点点沿正弦曲线开始游走（现有逻辑）        ← processing 稳定
```

**关键时长**：400ms；80~230ms 是 EdgeGlow 脉冲窗口——用户**最容易感知到"进入了下一阶段"** 的一帧。

## 阶段 ⑤：processing 稳定态（持续 1~30s）

| 图层 | 表现 |
|---|---|
| 底部波形 | 紫色 `#6B5CFF` 5 个点沿正弦游走，0.84s 一周期（保留现有） |
| 整屏 EdgeGlow | **从 sweep 改成"中心向外呼吸"**——颜色环不再旋转，整体 opacity 在 0.45 ↔ 0.78 间 2.0s 一呼吸 |
| 文字层 | **保留 final text 不动**（不要清空，让用户知道"在处理你刚说的"） |
| 视觉重心 | 屏幕变安静（无旋转）+ 点点流动 → "在思考"的隐喻 |

> EdgeGlow 在 listening / processing 是**完全不同的节奏**（一个旋转一个呼吸），这是 C 方向最重要的辨识度差异。

## 阶段 ⑥：processing → 大卡呈现（结束）

```
0ms     ┃ processing 末态
        ┃
0~200ms ┃ 底部波形 + 文字层一起 scale 0.94 + fade out 至 opacity 0
        ┃ 同时大卡从屏幕中央 scale 0.96 → 1.0 + fade in
        ┃
200~400ms ┃ EdgeGlow 颜色平滑过渡到 idle 18% 透明蓝绿
        ┃ 整屏从"在思考"过渡到"答案陈列"
400ms   ┃ 大卡完全可交互，回显层 SizedBox.shrink
```

## 异常分支：任意 → error

任何阶段触发错误，**0~300ms 关键帧**：

```
0ms   ┃ 当前状态
50ms  ┃ EdgeGlow 整圈"急促闪 2 次"：红色 1.0 → 0.4 → 1.0 → 0.72（共 200ms）
150ms ┃ 底部波形 fade 切到红色 #E14D3A，振幅整体抖一下（±4px 横向震颤 200ms）
300ms ┃ error 稳定态
```

## 关键参数汇总

| 参数 | 旧值 | 新值 |
|---|---|---|
| 底部波形宽度 | 500px | **880px** |
| 底部波形高度 | 34px | **80px** |
| 底部文字字号 | 24px / w800 | **20px / w700** |
| listening EdgeGlow 转速 | 2.6s/圈 | **1.8s/圈** |
| processing EdgeGlow 模式 | sweep 旋转 | **整体 opacity 呼吸 2.0s/周期** |
| listening → finalText 总时长 | 0（瞬切） | **500ms**（收束+涟漪+脉冲）|
| finalText → processing 总时长 | 0（瞬切） | **400ms**（EdgeGlow 脉冲+形态切换）|
| 大卡呈现过渡 | 现有 280ms | **400ms**（波形 fade + 大卡 scale）|

## 实施风险点

1. **性能**：EdgeGlow 用了 3 层 maskBlur + sweep gradient，再加脉冲动画时 maskBlur 加宽要测一下 PZ200 真机帧率（1920×1200 物理 / 1097×685 logical）。
2. **状态来源**：EdgeGlow 现在接 `state.stage`，要改成同时接 `voiceEcho.phase`——需要在 controller 暴露 phase 给 EdgeGlow，**别破坏现有 stage 联动**（confirm 卡也用 stage glow）。
3. **listening 形态切换的"凝成一行"**：当前 `_AssistantSignalPainter` 是 painter 单帧绘制，要做 0~500ms 的过渡动画得在 painter 外面套一个 `AnimationController` 控制 envelope 衰减系数。
4. **状态切换瞬间的视觉冲突**：listening → finalText 时如果用户继续说话（barge-in），动画要被打断回 listening——controller 里需要 cancellation 逻辑。

## 实施顺序建议

1. 先做 **C 方向**：EdgeGlow 改接 `voiceEcho.phase`，加入"呼吸 vs 旋转"两种模式（最便宜、效果立刻可见）
2. 再做 **A 方向 finalText → processing 脉冲**：EdgeGlow 亮度脉冲 + 波形形态切换（中等成本）
3. 最后做 **A 方向 listening → finalText 涟漪**：需要 painter 外套动画控制器（最贵）
4. 异常分支动画放最后，可在 v1.1 补
