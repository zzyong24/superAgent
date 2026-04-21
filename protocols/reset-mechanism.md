# Reset Protocol

> 双 Reset 机制:Claude Code feature 级 Reset + Hermes 进程内 Reset。
> v0.5 相对 v0.4 的关键变化:
> - Claude Code Reset 粒度下沉到 **feature 级**(不再是 sprint 级)
> - Hermes Reset 是**常驻进程内清空上下文**(不再是新会话启动)

---

## 一、Claude Code Feature Reset

### 触发条件(任一满足)

| 条件 | 阈值 | 数据源 |
|---|---|---|
| token 使用率超标 | > 0.70 | Generator 自感(session 内部监控) |
| 连续 retry | >= 2 次 | eval_log 本 feature 的 `event_type=retry` 计数 |
| 连续工作时长 | > 2h | session_pool.active.<id>.started_at 到现在 |

### 触发来源

- **Generator 自感**:Claude Code 在每次 phase 推进或重要动作后自检 token 比率,触达阈值后自己触发
- **Hermes 监听**:Hermes 监控 session_pool + eval_log,发现 retry>=2 或 >2h 也会主动要求 Reset

### 执行流程

1. Generator 写 `.harness/features/<feature_id>/handoff.md`(按 `templates/claude_code_handoff.template.md`)
 - **关键字段**:current_phase / 最后工作 / 下一步计划 / 关键决策 / 运行时引入的依赖
2. Generator 在 `generator_log.md` 追加一段 `## Reset at <timestamp>`
3. Generator 更新 `session_pool.active.<feature_id>.status = "resetting"`
4. Generator 退出 session
5. Hermes 监听到 `resetting` 状态 → 启动同 feature 新 session
6. 新 session 初始化(按 `protocols/feature-isolation.md`):
 - 读 `context_snapshot.md`(**不变**,还是原始的)
 - 读 `handoff.md`(Reset 的中断快照)
 - 读 `generator_log.md`(历史进度)
 - 读 `tooling.md`(含运行时新增)
7. 新 session 接续 current_phase,继续工作

### 关键约束

- ❌ 新 session 不能回退已完成的 phase
- ❌ 新 session 不能翻盘 tooling 决策
- ✅ 新 session 的 token 使用从 0 开始(真正的上下文清空)

---

## 二、Hermes 进程内 Reset

### 核心区别 vs v0.4

v0.4: 新 Hermes 会话启动
v0.5: **同进程内清空上下文 + 重读外部文件**

Hermes 是常驻 Agent,"Reset"意味着:
1. 让出当前 LLM 上下文窗口的所有历史消息
2. 保留 runtime_state 在磁盘上的最新值
3. 重新从磁盘加载必要信息,从零开始推理

### 触发条件(任一满足)

| 条件 | 阈值 | 说明 |
|---|---|---|
| Hermes 自身 token | > 0.70 | Hermes 自感 |
| 连续 sprint 都有 retry | >= 3 | `hermes_context_state.consecutive_sprints_with_retries` |
| Hermes 连续工作时长 | > 3h | `runtime_state.session_started_at` 到现在 |

### 为什么阈值比 Claude Code 更宽松

- Hermes 承担 Planner + Evaluator,"记忆价值"更高
- Hermes 上下文含多 sprint 历史、用户长期目标、feature 依赖
- Hermes Reset 代价比 Claude Code 大

### 执行流程(自己触发自己)

**Hermes Reset 必须自己触发**,不能依赖 Claude Code 或用户。没有外部 Agent 比 Hermes 更了解自己的上下文状态。

1. Hermes 感知自身接近临界
2. 写 `.harness/hermes_handoff.md`(按 `templates/hermes_handoff.template.md`)
 - **关键字段**:pending_eval(最重要!)+ pending_checkpoints + feature_list 快照 + 待确认事项
3. 更新 `.harness/hermes_context_state.json`:
 - `last_reset_at = now()`
 - `token_usage_ratio` 重置
4. 更新 `.harness/runtime_state.json`:
 - `last_reset_at = now()`
 - `last_heartbeat = now()`
5. 清空 LLM 上下文
6. 重新加载:
 - 读 `runtime_state.json` 恢复 mode / current_sprint
 - 读 `hermes_handoff.md` 获取中断快照
 - 读 `feature_list.json` 恢复全局状态
 - **第一件事:处理 pending_eval**(见下方)
 - 第二件事:检查 pending_checkpoints(见下方)
 - 继续正常工作

### pending_eval 的处理(最关键)

**最危险的情况**:Hermes 判断了 retry 但还没写 eval_log 就触达阈值。

`hermes_context_state.pending_eval` 字段专门为此存在:

```json
{
  "feature_id": "f003",
  "reason": "Hermes 上下文满之前未完成评价",
  "eval_decision": "retry",
  "fix_direction": "补充 mock 数据后重新运行 verify phase"
}
```

**新 Hermes 启动后,在做任何决策前:**
1. 读 `hermes_context_state.pending_eval`
2. 如非空,立即写 eval_log(event_type=phase_evaluation, result=retry, reason=<pending_eval.reason> + "(恢复自 Hermes Reset 前的 pending eval)")
3. 触发 retry 动作
4. 清空 `pending_eval` 字段
5. 然后继续正常工作

### pending_checkpoints 的处理

Hermes Reset 前可能有已推送给用户但未处理回复的 checkpoint。

新 Hermes:
1. 读 `hermes_context_state.pending_checkpoints`
2. 对每个 checkpoint,检查 `feature_list` 里该 checkpoint 的 `decision`:
 - 若已填(用户已回复但旧 Hermes 没处理)→ 立即按 `protocols/checkpoint-qa.md` 处理
 - 若未填 → 继续等,不重推

### 数据落盘顺序(顺序固定)

1. `hermes_handoff.md`(先写)
2. `hermes_context_state.json`(再写,含 pending_eval / last_reset_at)
3. `runtime_state.json`(最后更新)

**目的**:防止中间状态丢失。如果先更新 runtime_state 再写 handoff,进程崩了就丢数据。

---

## 三、两种 Reset 的对比

| 维度 | Claude Code Feature Reset | Hermes 进程内 Reset |
|---|---|---|
| 粒度 | 单 feature | 整个 Hermes |
| 谁触发 | Generator 自感 / Hermes 监听 | Hermes 自己 |
| 谁执行 | Generator 写 handoff 后退出 | Hermes 自己清空上下文 |
| 新启动 | Hermes 启动新 Claude Code session | Hermes 自己重读文件继续 |
| 关键文件 | `features/<id>/handoff.md` | `hermes_handoff.md` + `hermes_context_state.pending_eval` |
| 数据风险 | 最后一次 generator_log 未写 | pending_eval 丢失 |
| 防护机制 | handoff 写完才退出 | handoff 写完才更新 state |

---

## 四、监控与日志

### 每次 Reset 必须写 eval_log

```json
{
  "event_type": "reset",
  "agent": "claude-code" | "hermes",
  "feature_id": "f003" | null,
  "reason": "token > 0.70" | "retry >= 2" | "duration > 2h" | "...",
  "timestamp": "..."
}
```

### 监控关注

- Reset 频率过高(单 feature 内 >2 次 CC Reset) → 说明 feature 设计太重,应拆分
- Hermes Reset 频率过高(单 sprint >1 次) → 说明 sprint 太大,或 Planner 拆分不合理
- pending_eval 丢失(新 Hermes 发现 `eval_log` 最后条目时间戳很久远,但 feature 进度推进了) → 写告警

---

## 五、绝对禁止

- ❌ 不要在 handoff.md 写完前更新 context_state(顺序不能颠倒)
- ❌ 不要假设 Reset 后上下文会自动恢复——**新 session 必须通过文件重建所有必要信息**
- ❌ 不要让新 Hermes 跳过 pending_eval 处理
- ❌ 不要在 Reset 时清空 eval_log 或 feature_list(它们是永久性的)
- ❌ 不要在 suspended 状态下触发 Reset(suspended 已经释放了上下文,不需要再 Reset)
