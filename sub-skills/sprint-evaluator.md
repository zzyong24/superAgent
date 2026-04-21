# Sub-skill: sprint-evaluator

> Planner 完成 + tooling/DAG 两个 gate 通过后,Hermes 进入 Evaluator 模式。
> 本 sub-skill 的职责:监听 Claude Code feature session 的产出,按 phase 判决,处理 checkpoint,管理 session pool。

---

## 进入条件

- Planner 已完成(tooling_locked=true + sprint_contract.status=active)
- `runtime_state.mode = active`
- `.current_agent.role = evaluator`

---

## 职责范围

- ✅ 监听 feature session 进展(读 eval_log / generator_log)
- ✅ 判决每个 phase 完成质量(pass/retry/fail)
- ✅ 按 checkpoint 类型处理(gate/review/notify)
- ✅ 触发 YOLO 判断
- ✅ 管理 session pool(启动依赖满足的 feature,处理 Reset)
- ✅ 识别 suspend / 触发 Hermes Reset 阈值
- ❌ **不做** feature 本身的工作
- ❌ **不做** replan(发生 fail 时,切回 sprint-planner 处理)

---

## 事件驱动

Evaluator 是事件响应的。监听以下事件源:

### 事件 1:eval_log 新增条目(Generator 写入)

通常是 Generator 完成一个 phase 后追加。内容含:
- event_type = phase_evaluation
- feature_id + phase + acceptance_results

**动作**:读整条记录 → 触发 phase 判决流程(Step A)

### 事件 2:feature_list.json 变化

Generator 完成某 phase 后会更新 phase 字段。

**动作**:
- 若 status 变 completed → 释放 session 槽位 + 检查下游依赖(Step C)
- 若 status 变 failed / waiting → 记录状态

### 事件 3:用户飞书回复

用户回复了某 checkpoint。

**动作**:按 `protocols/checkpoint-qa.md` 解析回复,更新 checkpoint.decision,触发下一步

### 事件 4:超时定时器

review checkpoint 48h 超时,或 gate 24h/72h 催办。

**动作**:按 `protocols/checkpoint-qa.md` 处理

### 事件 5:session 失联

session_pool.active.<id>.last_activity 超时。

**动作**:启动 feature Reset 流程(见 `protocols/reset-mechanism.md`)

---

## 核心流程

### Step A: Phase 判决

Generator 完成某 phase,写了 eval_log 和 generator_log。Evaluator:

1. **读取最新状态**
 - `.harness/features/<feature_id>/generator_log.md` 最新段落
 - `.harness/eval_log.jsonl` 最后一条关于本 feature 的
 - `.harness/feature_list.json` 本 feature 的 acceptance + 当前 phase

2. **判决依据**
 - 对照 acceptance 逐条检查(acceptance_results 字段)
 - 对照 sprint_contract.evaluator_criteria 的 pass/retry/fail 定义
 - 看 phase-workflow.md 本 phase 的完成标志

3. **判决结果**(三选一):
 - `pass`:全部 acceptance 通过 + 本 phase 完成标志满足
 - `retry`:有测试失败 / acceptance 未满足但明确可修
 - `fail`:方向性错误 / 严重越权 / 连续 retry 超 max_iterations

4. **写 eval_log**
 - event_type = phase_evaluation
 - result = pass / retry / fail
 - **reason 字段必填**,引用具体 acceptance id
 - 按 `schemas/eval_log.schema.json`

5. **根据结果推进**:

 **pass**:
 - 更新 `feature_list.features[N].next_phases[current].done = true`
 - 更新 feature.phase = 下一 phase
 - 进入 Step B(checkpoint 处理)

 **retry**:
 - 更新 sprint_contract.iteration_history
 - 把修正方向写入 feature 的 "retry_hint" 字段(Generator 下次读)
 - 通知 Generator 重启本 phase(或若需要 Reset,触发 feature Reset)

 **fail**:
 - 更新 feature.status = "failed"
 - 升级 Hermes(或推 gate checkpoint 问用户怎么办)
 - 可能 replan:切回 `sprint-planner.md` 重拆

### Step B: Checkpoint 处理

phase pass 后,检查本 feature 的 `checkpoints` 中该 phase 的 checkpoint 配置。

1. **检查 YOLO 条件**(见 `protocols/yolo.md`):
 - pipeline.stats 达标 + 当前 sprint 无 abort trigger → YOLO 生效
 - YOLO 生效且 checkpoint 不是 external_irreversible → `decision=auto_approved_yolo`,直接进入 Step B 后续

2. **按 checkpoint 类型处理**:
 - `gate`:提炼 blockers → 推飞书 → 等回复(参考 `protocols/checkpoint-qa.md`)
 - `review`:推飞书 + 启动 48h 定时器
 - `notify`:推飞书(只通知)

3. **写 eval_log**:event_type = checkpoint,含 decision

4. **根据 decision 推进**:
 - approved / auto_approved_* → 进入下一 phase(或若 phase=4,feature completed)
 - approved_with_changes → 把 feedback 写入 feature.retry_hint(下一 phase 读),进入下一 phase
 - rejected → retry 当前 phase(返回 Step A 的 retry 分支)
 - revoked(YOLO abort)→ 进入 Step D(YOLO Abort)

### Step C: 依赖触发(feature completed 后)

某 feature 到达 phase=4 且 deliver 成功:

1. 更新 `feature_list.features[N].status = "completed"`,写 completed_at 和 commit
2. 从 `session_pool.active` 移除本 feature
3. 扫描其他 feature:
 - 若 `feature.status = "pending"` 且 `depends_on` 全部 completed → 候选启动
4. 按 `max_concurrent` 选出至多 N 个候选启动(见 `protocols/feature-isolation.md`)
5. 对每个启动:
 - 写 context_snapshot.md(含 tooling 最新版 + 本 feature 的 acceptance)
 - 复制 AGENTS.md
 - 启动 Claude Code session
 - 更新 session_pool
6. 若所有 feature 都 completed → 进入 Step E(sprint 结束)

### Step D: YOLO Abort 处理

按 `protocols/yolo.md` Step 3:

1. 扫描所有 auto_approved_yolo 的 checkpoint → revoke
2. 写 eval_log (每个 revoke 一条 + sprint 级 abort 一条)
3. **单条**聚合飞书消息(按 `templates/checkpoint_notify.template.md` YOLO Abort 模板)
4. `runtime_state.mode = "waiting_human"`
5. 不启动新 feature,但已在运行的等它们自然到下个 phase

### Step E: Sprint 收尾

所有 feature status=completed(或明确 cancelled):

1. `sprint_contract.status = "finalizing"`
2. 退出 Evaluator 模式
3. 进入 `sub-skills/sprint-finalizer.md`

---

## Hermes 自检(每次事件处理后)

处理完任一事件后,Hermes 检查自己的状态:

- token_usage_ratio > 0.70 ?
- 连续 3 sprint 有 retry ?
- session_started_at 到现在 > 3h ?

任一满足 → 进入 `sub-skills/hermes-reset.md`。

---

## 禁止

- ❌ 不在同一 phase 重复判决(避免上下游混乱)
- ❌ 不跳过 checkpoint 处理直接推进 phase
- ❌ 不擅自 fail 没达到 max_iterations 的 retry
- ❌ 不在 waiting_human 时启动依赖链上游有冲突的 feature
- ❌ 不修改 Generator 写入的 generator_log(只能读)
- ❌ 不在 Evaluator 模式下修改 tooling.md

## 必须做到

- ✅ 每次判决都对照具体 acceptance
- ✅ 每条 eval_log 必含 reason
- ✅ YOLO 判断先于 checkpoint 类型判断
- ✅ external_irreversible 检测严格(绝不 YOLO 跳过)
- ✅ suspended / Hermes Reset 信号立即响应
