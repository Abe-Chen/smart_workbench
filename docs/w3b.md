  W3b 实施明细                                                                  
                                         
  2026-05-08 P0.2 本地任务链路对话策略扩展                                        
                                                                                 
  目标：把“像助理说话”的规则扩展到本地任务/日程/提醒的高频场景，但不改变工具执行  
  和数据库写入逻辑。                                                             
                                                                                 
  覆盖范围：                                                                     
  - 查询类：query_tasks 结果由 App 直接组织自然列表，空结果说“没查到符合条件的任务或日程”
  - 完成类：complete_task 直接收尾，成功说“已把 X 标记完成，刚才这一步可以撤销”    
  - 写入确认类：create/update/delete 确认后由 App 按工具 ok 结果收尾，不依赖模型再总结
  - 确认态乱入：按当前操作对象追问，如“我还在等你确认是否删除 X”                  
  - 取消类：按动作区分“先不创建/先不修改/先不删除”，避免笼统“已取消”              
                                                                                 
  保护边界：                                                                     
  - 不改 query/update/delete/complete 工具参数和数据库写入                         
  - 不改公网 Responses 链路                                                       
  - 不改 ASR/TTS 状态机                                                           
  - 仍保留 tool result 写入历史，避免 function calling 后续多轮协议不完整          
                                                                                 
  2026-05-08 P0.1 话术收口方案（助理感优化）                                     
                                                                                 
  目标：在不改工具执行、路由、数据库写入链路的前提下，把本地写入闭环的回复从“系  
  统提示”调整为“可靠助理”的自然表达。                                            
                                                                                 
  设计边界：                                                                     
  - 不做陪伴型人格，不卖萌，不增加无关寒暄                                        
  - 不改变 confirm / pendingWriteDraft / tool.call 的状态机                       
  - 不让模型总结本地写入结果；工具 ok=true 才能说已创建                           
  - 屏幕文案优先说明用户下一步，避免“参数、核验、目标、执行中”等内部词           
                                                                                 
  落地方式：                                                                     
  - 新增 AssistantCopywriter，集中生成缺字段、等待确认、成功、失败、取消等微文案  
  - controller 只传入状态和工具结果，不再散落硬编码话术                           
  - system prompt 增加“像工作助理，不像系统日志”的风格约束                       
  - 给 copywriter 和 confirm flow 加回归测试，防止后续改回机器人式表达            
  - 追问缺失信息时禁止泄漏固定测试示例（如“需求讨论会”）；应按已理解内容自然追问   
  - 缺标题不说“还差标题”，改问“这条日程叫什么？”；缺时间不说“还差时间”，改问“几点开始？”
                                                                                 
  2026-05-08 P0 收口方案（测试问题修复）                                          
                                                                                 
  目标：先把“创建任务/日程/提醒”这条链路做稳定，不扩展到邮件、简报、长期记忆。     
  用户说“创建一个日程”但缺字段时，进入 pendingWriteDraft 草稿态；后续补充内容只    
  更新这个草稿，字段齐了再弹确认卡。                                              
                                                                                 
  必须修复的 3 个问题：                                                           
                                                                                 
  1. 多轮补字段不能丢上下文                                                        
  - 新增 pendingWriteDraft：保存 kind/title/date/time/reminder 等关键字段           
  - 缺 title/date/time 时由 App 确定性追问，不交给模型自由追问                      
  - 用户说“取消/不用了”时清掉草稿                                                 
                                                                                 
  2. 确认后结果必须以工具返回为准                                                  
  - App 直接解析 tool.call 返回的 JSON                                            
  - ok=true 才显示“已创建/已修改/已删除”                                          
  - ok=false 必须显示失败原因，禁止模型把失败总结成成功                            
                                                                                 
  3. confirm 态必须全局拦截输入                                                    
  - pendingConfirm 存在时，“确认/可以/对”直接执行 confirmPendingTool                
  - “取消/不用/算了”直接执行 cancelPendingTool                                    
  - 其他文本或语音不进入普通问答，提示用户先确认或取消                             
  - confirm 期间抽屉强制保持打开，语音确认也必须留在同一个 pendingConfirm 上        
                                                                                 
  不做：                                                                           
  - 不做复杂多任务批量创建                                                         
  - 不做邮件、简报、长期记忆                                                       
  - 不改公网问答链路                                                               
  - 不改 update/delete/complete 的模型工具主流程，只加 confirm 防串线保护           
                                         
  关键设计                                                                      
                                         
  复用现有数据层：写入工具直接                                                  
  ref.read(taskMutationControllerProvider).createTask(...)，看板的
  taskPreviewsForDateProvider / taskPreviewBucketsProvider 通过                 
  taskRefreshTickProvider 自动重 build，与 task_editor_page
  手动建任务走完全相同的链路。           

  confirm 卡载体强制走抽屉：用户做关键操作时需要看清楚字段，胶囊太小放不下；进  
  confirm 态时强制 drawerOpen=true。
                                                                                
  写入并发简化：一次 chat 返回多个写入 tool_call 时，第一个进                   
  confirm，其余直接回 {"ok": false, "reason": 
  "请逐个操作"}。模型本身也很少一次返回多个写入。                               
                                         
  AssistantTool 加 buildConfirmPreview(args) 钩子：默认                         
  null（非写入工具不实现）；写入工具 override，返回 AssistantConfirmPreview
  数据。controller 拦到写入 tool_call 时调它判断是否进 confirm。                
                                         
  complete_task 撤销：执行后通过 state 暴露 lastCompletedTaskId +               
  undoExpireAt，UI 端 watch 变化弹 SnackBar，5 秒倒计时（与现有 follow-up
  窗一致），点撤销调 toggleCompletion(false)。                                  
                                         
  工具参数约定（写到 prompt 里教模型）                                          
  
  工具: query_tasks                                                             
  关键参数: start_date end_date（"YYYY-MM-DD"，可缺，默认今日）；keyword（可选）
  备注: 返回紧凑 JSON 列表，最多 20 条                                       
  ────────────────────────────────────────                                   
  工具: create_task                                                          
  关键参数: title（必）；start_date（必，YYYY-MM-DD）；is_all_day（默认         
    true）；start_time_minutes /                                             
    end_time_minutes（0-1440）；reminder_key（none/day9am/atStart/before10m/... 
  ）；repeat_key（none/daily/weekly/monthly）
  备注: 模型自行从用户语言推 reminder_key                                       
  ────────────────────────────────────────
  工具: update_task                                                             
  关键参数: task_id（必，int）+ 任一可改字段
  备注: 不存在时返回 ok:false                                                   
  ────────────────────────────────────────
  工具: delete_task                                                             
  关键参数: task_id（必）
  备注: confirm 卡用红色 severity                                               
  ────────────────────────────────────────
  工具: complete_task                                                           
  关键参数: task_id（必）；occurrence_date（YYYY-MM-DD，默认今日）
  备注: 不走 confirm，SnackBar 撤销                                             
                                         
  文件级改动清单（17 处，10 新增 + 7 改）                                       
  
  #: 1                                                                          
  文件: domain/assistant_confirm_preview.dart                               
  类型: 新                                                                      
  内容: AssistantConfirmPreview / ConfirmRow / ConfirmSeverity              
  ────────────────────────────────────────                                  
  #: 2                                                                          
  文件: domain/assistant_tool.dart                                          
  类型: 改                                                                      
  内容: + buildConfirmPreview(args) 默认返回 null                           
  ────────────────────────────────────────                                      
  #: 3                                                                      
  文件: data/tools/query_tasks_tool.dart                                        
  类型: 新                                                                      
  内容: 查询任务                                                            
  ────────────────────────────────────────                                      
  #: 4                                                                      
  文件: data/tools/create_task_tool.dart                                        
  类型: 新                                                                  
  内容: 创建 + preview                                                          
  ────────────────────────────────────────                                  
  #: 5                                                                          
  文件: data/tools/update_task_tool.dart                                        
  类型: 新                                                                  
  内容: 更新 + preview                                                          
  ────────────────────────────────────────                                  
  #: 6                                                                      
  文件: data/tools/delete_task_tool.dart                                        
  类型: 新                                                                  
  内容: 删除 + preview（severity=warning）                                      
  ────────────────────────────────────────                                  
  #: 7                                   
  文件: data/tools/complete_task_tool.dart                                      
  类型: 新
  内容: 完成（不走 preview）                                                    
  ────────────────────────────────────────
  #: 8                                   
  文件: application/tool_registry.dart
  类型: 改
  内容: 注册 5 个新工具
  ────────────────────────────────────────
  #: 9
  文件: application/assistant_state.dart
  类型: 改
  内容: + pendingConfirm + completionUndo（id + occurrenceDate + expireAt）
  ────────────────────────────────────────
  #: 10
  文件: application/assistant_controller.dart
  类型: 改
  内容: 拦截写入 tool_call 进 confirm；confirmPendingTool / cancelPendingTool /
    undoLastCompletion；clearConversation 清 pending
  ────────────────────────────────────────
  #: 11                                                                         
  文件: presentation/widgets/confirm_card.dart
  类型: 新                                                                      
  内容: ConfirmCard widget（含 severity 配色）
  ────────────────────────────────────────
  #: 12                                                                         
  文件: presentation/widgets/completion_undo_listener.dart
  类型: 新                                                                      
  内容: watch state.completionUndo 弹 SnackBar + 5 秒倒计时
  ────────────────────────────────────────
  #: 13                                                                         
  文件: presentation/assistant_drawer.dart
  类型: 改                                                                      
  内容: confirm 卡 + undo listener 内嵌；进 confirm 态自动开抽屉（已在
  controller                             
    处理）
  ────────────────────────────────────────
  #: 14                                                                         
  文件: prompts/system_prompt.dart
  类型: 改                                                                      
  内容: 追加工具使用边界 + 参数格式      
  ────────────────────────────────────────
  #: 15                                                                         
  文件: test/.../tool_args_test.dart
  类型: 新                                                                      
  内容: 工具 args 解析容错 + buildConfirmPreview 输出
  ────────────────────────────────────────
  #: 16                                                                         
  文件: test/.../confirm_flow_test.dart
  类型: 新                                                                      
  内容: controller 进/出 confirm 态的状态机覆盖
  ────────────────────────────────────────
  #: 17                                                                         
  文件: docs/ai_assistant_xiaozhi.md
  类型: 改                                                                      
  内容: §5 操作确认卡 / §10 同步 W3b 完成
                                         
  现有功能保护清单

  ┌────────────────────────────────────────────┬─────────────────────────────┐  
  │                  现有功能                  │          保护方式           │
  ├────────────────────────────────────────────┼─────────────────────────────┤  
  │ task_editor_page 手动建任务                │ 用同一 mutation             │
  │                                            │ controller，0 影响          │
  ├────────────────────────────────────────────┼─────────────────────────────┤  
  │                                            │ 通过                        │  
  │ 看板（dashboard / day / week / month）渲染 │ taskRefreshTickProvider     │  
  │                                            │ 自动重 build                │  
  ├────────────────────────────────────────────┼─────────────────────────────┤  
  │ 提醒同步（reminderSyncControllerProvider） │ mutation 后已自动调 syncNow │
  ├────────────────────────────────────────────┼─────────────────────────────┤  
  │ ASR / TTS / 倒计时圈 / 持续对话 / 抽屉滑入 │ 不动                        │
  ├────────────────────────────────────────────┼─────────────────────────────┤  
  │ W3a router / 意图 / 槽位                   │ 不动                        │
  ├────────────────────────────────────────────┼─────────────────────────────┤  
  │ 阶段 1 播报决策                            │ 不动；confirm 态期间不触发  │
  │                                            │ TTS（避免和确认操作打架）   │  
  ├────────────────────────────────────────────┼─────────────────────────────┤
  │ get_user_location 工具                     │ 归非写入，行为不变          │  
  ├────────────────────────────────────────────┼─────────────────────────────┤  
  │ 设置页                                     │ 不动                        │
  └────────────────────────────────────────────┴─────────────────────────────┘  

  不在本次范围

  - ❌ 编辑按钮跳 task_editor_page（W3c）
  - ❌ AI 一次创建多个任务（暂只支持单写入 tool）
  - ❌ 长期记忆三张表（W4b）
  - ❌ 句级流式 / barge-in / TTS 缓存（阶段 2/3）
  - ⚠️ 唤醒（W4a）：桥接、AIKit `.aar` 和 `aikit_resources/` 已接入，等待 PZ200 真机唤醒率、误唤醒和麦克风释放验收

  验证步骤

  1. flutter analyze 0 warning
  2. flutter test 全过 + 新增 tool / confirm 测试
  3. 手测核心流程：
    - "我今天的任务" → 模型调 query_tasks → 文字回答列出
    - "帮我加个明天 3 点的客户拜访" → 弹 confirm → 确认 →
  看板今日/明日板上立即出现卡
    - 同步骤但点取消 → 模型说"好，没创建"
    - "把刚才那个会议改到 4 点" → 模型先 query_tasks 拿 id → 调 update_task → 弹
   confirm
    - "删掉吃药提醒" → 红色 confirm → 确认 → 任务消失
    - "标记完成 Q2 评审" → 直接执行 + SnackBar"已完成 · 撤销"，5 秒倒计时

  ---
