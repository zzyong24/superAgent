# Sub-skill: hermes-reset

> Hermes 自感上下文接近临界时进入本 sub-skill。
> v0.5 特性:**常驻进程内清空上下文,不是新会话启动**。

---

## 进入条件(任一满足)

| 条件 | 阈值 | 数据源 |
|---|---|---|
| Hermes 自身 token | > 0.70 | Hermes 自感 |
| 连续 sprint 有 retry | >= 3 | `hermes_context_state.consecutive_sprints_with_retries` |
| 连续工作时长 | > 3h | `runtime_state.session_started_at` |

---

## 核心原则

1. **Hermes Reset 必须自己触发自己**——没有外部 Agent 比 Hermes 更了解它的内部状态
2. **优雅让位,不是崩溃**——所有状态在清空上下文前必须落盘
3. **落盘顺序固定**——handoff → context_state → runtime_state(见下方"关键落盘顺序")

---

## 工作流程

### Step 1. 自感确认

被事件循环唤醒到本 sub-skill 时,先确认是否真要 Reset:

- token 达标 → 确认 Reset
- 连续 sprint retry 达标 → 确认 Reset
- 时长达标 → 确认 Reset
- 若用户明确在 waiting_human 回复中,或正在关键判决 → **推迟 Reset**,完成当前动作再 Reset

### Step 2. 生成 hermes_handoff.md

按 `templates/hermes_handoff.template.md` 填空。**关键内容**:

#### 2.1 Hermes 最后的工作

一段自然语言,描述:
- 最后一个完成的判决是什么
- 当前 Hermes 在哪个 sprint、什么阶段
- 最后 5 分钟 Hermes 在干嘛

#### 2.2 Pending Eval(最重要!)

**最危险的情况**:Hermes 判断了 retry 但还没写 eval_log。

如果存在未写入的判决,必须填:

```json
{
  "feature_id": "f003",
  "reason": "Hermes 上下文满之前未完成评价",
  "eval_decision": "retry",
  "fix_direction": "补充 mock 数据后重新运行 verify phase"
}
```

如果没有,明确写 `无 pending eval`。

#### 2.3 Pending Checkpoints

列出已推送给用户但未处理回复的 checkpoint id:
- cp-f006-1
- cp-f007-2

#### 2.4 feature_list 快照(摘要)

只记录关键状态,详见 feature_list.json:
- f001: completed
- f002: completed
- f003: in_progress, phase=3

#### 2.5 待确认事项

Hermes Reset 前没来得及决定的事。

### Step 3. 落盘(顺序固定!)

**绝对不可颠倒**:

```
1. 写 .harness/hermes_handoff.md
2. 写 .harness/hermes_context_state.json:
   - last_reset_at = now()
   - token_usage_ratio = 0 (重置)
   - pending_eval = <Step 2.2 内容,若有>
   - pending_checkpoints = <Step 2.3 内容>
3. 写 .harness/runtime_state.json:
   - last_reset_at = now()
   - last_heartbeat = now()
```

**原因**:任一顺序错乱,Reset 中崩溃会丢数据。

### Step 4. 清空进程内上下文

清空 LLM 上下文历史(注意:不是杀进程,是让当前 LLM 会话开一个"新对话"但进程本身还在)。

### Step 5. 重新加载

按以下顺序:

#### 5.1 读 runtime_state.json

获取:
- mode(恢复到 Reset 前的 mode)
- current_sprint
- current_project_path
- last_reset_at(确认刚 Reset 完)

#### 5.2 读 hermes_handoff.md

获取 Reset 前的工作快照。

#### 5.3 处理 pending_eval(第一件事!)

**绝对必须**:在任何其他动作前处理。

```
if hermes_context_state.pending_eval 非空:
    写 eval_log 条目:
      event_type = phase_evaluation
      feature_id = pending_eval.feature_id
      result = pending_eval.eval_decision  # retry / pass / fail
      reason = pending_eval.reason + "(恢复自 Hermes Reset 前的 pending eval)"
      hermes_notes = pending_eval.fix_direction
    触发相应动作(retry 就通知 Generator,pass 就推进 phase)
    清空 pending_eval 字段
    写回 hermes_context_state.json
```

#### 5.4 处理 pending_checkpoints

```
for checkpoint_id in pending_checkpoints:
    读 feature_list 里该 checkpoint 的 decision
    if decision 已填(用户已回复但旧 Hermes 没处理):
        按 protocols/checkpoint-qa.md 处理
    elif decision 为空:
        继续等,不重推
从 pending_checkpoints 移除已处理的
写回 hermes_context_state.json
```

#### 5.5 恢复正常工作

- 读 feature_list.json 恢复全局 feature 视图
- 读 sprint_contract 恢复契约
- 读 tooling.md 恢复选型
- 根据 mode 回到对应 sub-skill:
 - planning → `sub-skills/sprint-planner.md`
 - active → `sub-skills/sprint-evaluator.md`
 - finalizing → `sub-skills/sprint-finalizer.md`
 - waiting_human → evaluator 模式(继续等回复)
 - suspended → 回 idle

### Step 6. 写 eval_log

追加一条 reset 记录:

```json
{
  "event_type": "reset",
  "agent": "hermes",
  "reason": "token > 0.70" | "retry >= 3" | "duration > 3h",
  "timestamp": "...",
  "pending_eval_recovered": true/false,
  "pending_checkpoints_recovered": N
}
```

---

## 监控 / 告警条件

Hermes Reset 后应立即检查:

- pending_eval 丢失告警:如果 eval_log 最后条目很久远但 feature_list 进度推进了 → 说明有判决未入库,写 warning
- Reset 频率异常:单 sprint Hermes Reset >1 次 → warning,可能 sprint 太大

---

## 禁止

- ❌ **绝对不能颠倒落盘顺序**(handoff → context_state → runtime_state)
- ❌ 不能在 Reset 中间状态(clear 了上下文但还没重读)处理新事件
- ❌ 不能丢掉 pending_eval(这是 Reset 机制的核心防护)
- ❌ 不能在 suspended / idle 状态下触发 Reset(没必要)
- ❌ 不能让新 Hermes 跳过 pending_eval 处理

## 必须做到

- ✅ Reset 前生成完整 handoff
- ✅ pending_eval / pending_checkpoints 准确填写
- ✅ Reset 后第一件事处理 pending_eval
- ✅ 每次 Reset 写 eval_log
- ✅ 推迟 Reset(若正在关键动作中)合理,不硬触发
