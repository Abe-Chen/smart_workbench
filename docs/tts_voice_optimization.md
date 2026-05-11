# 语音音色优化方案

最近更新：2026-05-11。
状态：**Stage B 已落地** — 火山豆包语音合成 2.0 通过 WebSocket V3 双向流式接入，讯飞作为 fallback 保留。**真机验证：音色可以，6 个火山音色 + 1 个讯飞备用切换正常**。

## 实施结果

| Stage | 描述 | 状态 |
|---|---|---|
| A 止损 | 调讯飞参数 + 试听按钮 + 切换提示 | ⏸️ 跳过（直接做 B 一步到位）|
| **B 接火山引擎 TTS** | 豆包 2.0 主路径 + 讯飞 fallback | ✅ **已落地，真机过** |
| C 流式 + 情感 | 边吐字边合成、按对话情绪选 prosody | 暂未启动 |
| D 音色克隆 | 用户自定义音色 | 暂未启动 |

## 当前架构（落地版）

- **主 TTS**：豆包语音合成大模型 2.0（Seed-TTS 2.0），WebSocket V3 双向流式，URL `wss://openspeech.bytedance.com/api/v3/tts/bidirection`，新版鉴权 `X-Api-Key + X-Api-Resource-Id`
- **音色路由**：`saturn_*` 前缀走 `seed-icl-2.0` 资源（声音复刻 2.0），其他走 `seed-tts-2.0`
- **音色清单**（6 个火山主推 + 1 个讯飞备用）：小荷 / 刘飞 / 轻盈朵朵 / Vivi / 云舟 / 少年自信 / 聆小璇（讯飞备用）
- **Fallback 机制**：`TtsFacade` 在火山失败时自动降级到讯飞默认音色（聆小璇），用户无感
- **音频参数**：mp3 / 24000 Hz / 128 kbps（讯飞之前是 16000Hz mp3）

## 关键代码位置

- `lib/features/assistant/data/volc_tts_client.dart` — 火山豆包 WebSocket V3 实现（含二进制帧编解码、12 种 event 状态机）
- `lib/features/assistant/data/tts_facade.dart` — 按音色路由 + 失败 fallback
- `lib/features/settings/domain/app_settings.dart` — 音色清单 + `TtsProvider` enum + `volcResourceIdForVoice` 路由函数
- `lib/core/config/env_config.dart` — `volcTtsApiKey` 字段
- `.env` — `VOLC_TTS_API_KEY`

## 用户反馈

> "音色一直有问题，音色很难听，而且无法切换音色。"

拆解为两个独立问题：

1. **难听**：当前默认音色 `x6_lingxiaoxuan_pro`（聆小璇）听感不及预期，有"机器味 / 远 / 闷"等可能感受
2. **无法切换**：在设置页选了别的音色，实际播报没变化（或者直接没声音）

这两个问题原因不同，方案也不同。

## 现状摸排

### TTS 服务

- **服务商**：讯飞云端 TTS（在线 WebSocket 合成 + 本地播放 mp3）
- **入口**：`lib/features/assistant/data/xunfei_tts_client.dart`
- **协议**：`wss://tts-api.xfyun.cn/v2/tts`
- **业务参数**（写死）：`aue=lame`（mp3）/ `auf=audio/L16;rate=16000`（16kHz）/ `volume=60` / `pitch=50` / `speed=可调`
- **音色列表**（5 个，全是讯飞 x5/x6 超拟人系列）：
  | code | 标签 | 描述 |
  |---|---|---|
  | `x6_lingxiaoxuan_pro` | 聆小璇 | 女声，自然柔和，**默认** |
  | `x5_lingyuzhao_flow` | 聆玉昭 | 女声，衔接自然 |
  | `x6_lingxiaoyue_pro` | 聆小玥 | 女声，温和轻柔 |
  | `x6_lingyuyan_pro` | 聆玉言 | 女声，吐字清晰稳重 |
  | `x6_lingfeiyi_pro` | 聆飞逸 | 男声，沉稳 |

### 切换链路

`settings_page.dart` dropdown → `AppSettingsController.setTtsVoice()` → 写入 SharedPreferences + `state = AsyncData(next)` → `currentTtsVoiceProvider` 自动刷新 → 下次 `assistant_controller` 调 TTS 时 `ref.read(currentTtsVoiceProvider)` 取到新值 → 传给 `xunfei_tts_client.speak(voice:)` → WebSocket `vcn` 字段 → 讯飞返回新音色 mp3。

**链路代码无明显 bug**，每个环节都串得通。

### 错误处理

`xunfei_tts_client.dart:218`：
```
讯飞 TTS 错误 (11200)：当前音色[$voice]未授权、已过期，或账号没有开通该发音人
```

11200 是讯飞标准错误码，含义就是字面：账号没开通这个发音人，但我们前端把它当 `XunfeiTtsException` 抛了——上层 catch 后只显示 ttsError，**用户不会被强提示音色没授权**，只感觉"切了没声音"。

## 问题诊断（待真机复现确认）

### 问题 1：无法切换 — 推测 90% 是「未授权」

**最可能的原因**：讯飞账号实际只开通了默认音色 `x6_lingxiaoxuan_pro`，其他 4 个超拟人发音人（聆玉昭 / 聆小玥 / 聆玉言 / 聆飞逸）在控制台没有授权。

**真机验证**：
1. 进设置页切换到「聆飞逸」（男声）
2. 触发一次播报（让小治朗读一句话）
3. 看 Flutter 调试控制台是否有 `讯飞 TTS 错误 (11200)：当前音色[x6_lingfeiyi_pro]未授权` 字样
4. 如果有 → 确认是授权问题
5. 如果没有但音色没变 → 走到下面问题 2 的方向

**附带 bug**：当前 ttsError 只悄悄塞到 state，UI 里不一定醒目展示。**应该在切换音色失败时强提示用户**，而不是默默 fallback。

### 问题 2：难听 — 多因素

| 可能因素 | 评估 |
|---|---|
| 讯飞超拟人音色本身 | 业界中上，但与火山引擎 / MiniMax / OpenAI 对比有差距，尤其在情感与韵律 |
| `auf=L16;rate=16000` 限制采样率 16kHz + mp3 编码 | 高频细节丢失，听感"闷"。讯飞实际支持 24kHz、aac 等 |
| `volume=60`（写死偏小）| 听感"远 / 没气" |
| `pitch=50`（中性）| 没问题，但没适配不同发音人 |
| 没有情感 / 风格控制 | 报新闻和聊天用同一种 prosody |
| 没有流式 TTS | 等整段合成完才播，长文本延迟感强 |

## 行业顶级方案对标

### 中文 TTS 当前梯队（2026-05）

| 服务商 | 中文表现 | 音色数 | 情感/风格 | 流式 | 接入难度 | 与豆包账号关系 |
|---|---|---|---|---|---|---|
| **字节火山引擎语音合成** | 业界顶级（多模 TTS 2.0） | 100+ | 强（情感、角色、场景）| 支持 | 中 | **同账号体系**，已在用豆包 |
| **MiniMax speech-02** | 顶级（2026 新版）| 100+ | 顶级（含克隆）| 支持 | 简单（REST） | 独立 |
| **阿里 CosyVoice 2.0** | 顶级（开源版本也强）| 多 + 克隆 | 强 | 支持 | 中 | 独立 |
| **OpenAI gpt-4o-tts** | 好（带情感）| 11 | 强 | 支持 | 简单 | 独立 |
| **腾讯云 TTS** | 好 | 60+ | 中 | 支持 | 中 | 独立 |
| **讯飞超拟人**（当前）| 中上 | 几十（超拟人 10+）| 中 | 支持 | 已接入 | 独立 |
| **ElevenLabs** | 中（中文非主打）| 几十+ | 顶级 | 支持 | 简单 | 独立 |

### 关键洞察

- **跟"豆包同生态"是天然优势**：项目已经在用豆包做 LLM，账号、API 鉴权、计费、控制台都是火山一套。接火山 TTS 几乎"零额外认知成本"。
- **MiniMax 是音质天花板**：今年（2026）多份评测里 speech-02 在中文情感、自然度上压 ElevenLabs，且支持快速音色克隆。
- **CosyVoice 2.0 开源**：如果未来要做"完全本地化"或"可控成本"，开源 + 自托管是路径。
- **讯飞不必丢掉**：保留作为 fallback（火山宕机、配额耗尽时降级），免去单点故障。

### 桌面助理类竞品做法

- **Apple Siri**：本地神经网络 TTS，1 个语音多种语调
- **Google Assistant**：云端 + 本地 fallback
- **小爱同学 / 小度**：自研 + 火山合作
- **ChatGPT Voice / 豆包语音**：OpenAI tts / 火山 TTS，极强情感

我们这个产品（中文桌面 AI 助理）跟豆包定位最像，**直接对标豆包语音的水平**是合理目标。

## 推荐方向

按"立即收益 / 工作量"两轴排序：

| 优先级 | 工作 | 工作量 | 预期收益 |
|---|---|---|---|
| 🟥 **P0** | 修「切换失败」诊断与提示链路 | 0.5 天 | 用户至少能看到"为啥切了没用" |
| 🟥 **P0** | 调讯飞参数：volume 提到 80、采样率提到 24kHz | 0.5 天 | 立即提升音质（在不换服务前提下） |
| 🟧 **P1** | 设置页加「试听」按钮 | 0.5 天 | 用户切换前能听到效果再决定 |
| 🟧 **P1** | 音色清单瘦身（5→3）+ 按风格分组 | 0.5 天 | 减少选择困难，避免授权坑 |
| 🟨 **P2** | 接入火山引擎 TTS（保留讯飞作为 fallback）| 2-3 天 | 音质飞跃，与豆包账号打通 |
| 🟦 **P3** | 流式 TTS（边合成边播） | 2 天 | 长文本延迟感大幅降低 |
| 🟦 **P3** | 按对话情绪选 prosody / 音色 | 1-2 天 | 体验更"像人"（朗读新闻 vs 聊天用不同调） |
| 🟪 **P4** | 音色克隆（用户自定义音色） | 5+ 天 | 个性化，差异化卖点 |

## 分阶段实施方案

### Stage A：止损 + 体验改善（不换服务）— 1.5 天

**目标**：在不接新 TTS 服务的前提下，把当前讯飞用到最好。

A1. **诊断切换失败链路**
- 真机复现，确认是否 11200
- 如果是 11200：在设置页 dropdown 切换后**主动触发一次试合成**（用一句固定文本），失败时弹明确提示"该音色未授权，请到讯飞控制台开通后再切换"
- 失败的音色项 dropdown 里灰显 + 加个红色感叹号，用户一眼看出"这个不能选"

A2. **调讯飞参数提音质**
- `volume: 60 → 80`（更近、更有气）
- `auf: audio/L16;rate=16000 → audio/L16;rate=24000`（讯飞超拟人支持 24kHz）
- `aue: lame → speex / opus`（如果讯飞支持，更高效；否则保 mp3）
- 实测对比，不行再回退

A3. **设置页加试听按钮**
- 选了某个音色后，旁边出现「试听」按钮
- 点击播放固定文本"你好，我是小治。今天天气不错，你想聊点什么？"（30 字以内，避免占用配额）
- 试听完成后自动停止

A4. **音色清单瘦身**
- 当前 5 个全是女声（4）+ 男声（1）的讯飞超拟人，重复度高
- 改为 3 选：默认女声（聆小璇）+ 男声（聆飞逸）+ 一个备选
- 减选项 = 减选择困难 + 少踩授权坑
- 后续接火山时再扩

**Stage A 验收**：
- [ ] 切换音色失败有明确提示，不再静默
- [ ] 真机听感对比：volume / 采样率调整后，主观判断是否变好
- [ ] 试听按钮可用，30 字内不耗费过多配额
- [ ] 设置页 5 个改为 3 个，dropdown 简洁

### Stage B：接入火山引擎 TTS — 2-3 天

**目标**：用业界中文 TTS 顶级方案接管主路径，讯飞降级为 fallback。

B1. **火山账号准备**
- 用户：开通火山引擎语音合成服务，拿到 appid / cluster / token / voice_type 列表
- 给我：把这些信息加到 `.env`（`VOLC_TTS_*`）

B2. **代码侧**
- 新建 `lib/features/assistant/data/volc_tts_client.dart`，照 xunfei_tts_client.dart 的接口契约
- 抽出 `TtsClient` 抽象基类（speak / stop / dispose），讯飞和火山实现同接口
- `currentTtsClient` 由 settings 决定（用户选的 provider）
- 默认 provider = volc，失败 fallback 到 xunfei
- Fallback 触发时控制台 log 一行，但不打扰用户

B3. **音色清单合并**
- 火山主推音色 6-8 个 + 讯飞备选 2 个，标注来源
- code 加前缀区分：`volc:zh_male_M_...` / `xunfei:x6_...`
- 音色 dropdown 按 provider 分组

B4. **配额监控**
- 调用日志记录每次 TTS 字符数 + 耗时 + 服务商
- 出现连续失败时主动降级（避免反复连接超时）

**Stage B 验收**：
- [ ] 火山 TTS 真机能播
- [ ] 切换 provider 立即生效
- [ ] 火山失败时自动降级到讯飞（不超过 1 次重试）
- [ ] 音色清单按服务商分组显示

### Stage C：流式 + 情感（增强）— 2-4 天

**目标**：从"能听清"升级到"听着舒服"。

C1. **流式 TTS**
- 火山支持流式合成（边合成边返回 chunk）
- 改 audioplayers 为支持流式的 AAC/opus 解码 + 播放（可能需要换 just_audio）
- 长文本（>60 字）首字延迟从 1-2 秒降到 200-400ms

C2. **情感 prosody 自动选**
- 在 `_buildSpeechText` 之前，**根据消息内容粗分**：
  - 任务确认 / 提醒 → 中性
  - 故事化建议（advice）→ 偏温和
  - 紧急通知 → 偏沉稳
  - 主动建议 → 偏轻松
- 火山 TTS 支持 `emotion` 参数，按这个映射

C3. **音色按场景配（可选）**
- 唤醒词触发 → 默认音色
- 闹钟提醒 → 沉稳男声（聆飞逸）
- 主动建议 → 默认女声
- 用户可在 settings 关掉自动切换

**Stage C 验收**：
- [ ] 长文本首字延迟 ≤ 500ms
- [ ] 不同消息类型主观听感有差异
- [ ] 关闭自动场景音色后，全部走默认音色

### Stage D：音色克隆（差异化卖点，可选）— 5+ 天

**目标**：用户可以训练自己的音色（"用我自己的声音念日程提醒"）。

- 火山引擎 / MiniMax 都提供音色克隆 API（30s 样音 → 个人音色）
- 设置页加「我的音色」入口，引导录音
- 涉及隐私 + 合规（需要用户授权 + 数据本地存储）

**这一步先不做规划，等 Stage B 跑通且产品验证有需求后再启动**。

## 待用户决策点

1. **优先级**：Stage A → B → C 顺序对吗？还是直接跳 Stage B？
   - 我的建议：**Stage A 先做**（成本极低，立即可见），即使决定接火山，A 的诊断与试听按钮在火山上也通用。
2. **火山引擎账号**：是否已经有？没有的话需要你去开通服务（豆包账号应该可以直接看到火山控制台），以及加一笔 TTS 调用的预算评估。
3. **音色风格偏好**：你心目中"理想音色"更像谁？
   - 豆包 App 里某个音色？（告诉我名字）
   - Siri？小爱？还是更偏专业播报员？
   - 这个会影响接火山时默认音色的选择。
4. **是否保留讯飞**：火山接通后，讯飞作为 fallback（备用）保留 vs 直接拆掉？
   - 我倾向**保留**：单点服务故障时不至于完全没声音。
5. **流式 TTS 是必须吗**：当前长文本朗读你能接受多少首字延迟？
6. **音色克隆**：未来想做吗？做的话需要预留架构。

## 真机验证步骤（等设备恢复后）

请按这个顺序操作并记录现象，方便定位 Stage A 的具体改法：

1. 打开 app，进设置页
2. 在「音色」dropdown 里**依次切到每一个音色**，每次切换后让小治说一句话（比如问"几点了"）
3. 观察并记录：
   - 哪些音色**完全没声音**（疑似 11200）
   - 哪些音色**有声音但听感差**（音质 / 韵律 / 音量问题）
   - 切换后**界面提示**有没有变化（默默失败还是有 toast）
4. 截图设置页 + 截图错误提示（如果有）
5. 把 Flutter 调试控制台的 `讯飞 TTS 错误` 相关 log 发我

拿到这些数据后，我能精准定位是 **授权问题** 还是 **代码 bug** 还是 **音色本身就这样**，再决定从 Stage A 哪一步开干。

## 关联代码位置

- `lib/features/assistant/data/xunfei_tts_client.dart` — 讯飞 TTS 客户端，`vcn` 参数与 11200 错误处理
- `lib/features/settings/domain/app_settings.dart` — `kTtsVoiceOptions` 音色清单 + `kDefaultTtsVoice`
- `lib/features/settings/application/app_settings_controller.dart` — `setTtsVoice` 切换逻辑 + `currentTtsVoiceProvider`
- `lib/features/settings/presentation/settings_page.dart` — `_TtsVoiceSection` dropdown UI
- `lib/features/assistant/application/assistant_controller.dart` L3297 / L3317 / L3680 — `ref.read(currentTtsVoiceProvider)` 读取并 speak
