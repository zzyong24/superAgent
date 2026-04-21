# Hermes Handoff Document

> **模板说明**:Hermes 自感上下文接近临界(token>70% / 连续 3 sprint retry / >3h)时,由自己写入。
> 位置:`.harness/hermes_handoff.md`
> 用途:Hermes 进程内 Reset 后,新上下文的"中断快照"。**不是完整上下文,只是关键决策点**。

**Generated at**: {timestamp}
**Sprint**: {sprint_id}
**Trigger reason**: {reason}(token / retry / duration 三选一)

---

## Hermes 当前工作快照

### 已完成的评价
- f001: pass(3 个 acceptance 全部通过,phase=4)
- f002: retry 一次,第二次 pass(phase=4)
- ...

### 进行中的 Sprint
- 当前 sprint: {sprint_id}
- Generator(Claude Code)正在执行的 feature: {feature_id}
- feature 当前 phase: {phase}
- Claude Code session_id: {session_id}

### Hermes 最后的工作
一段文字,描述 Hermes 在 Reset 前做到哪里、准备做什么。

## Pending Eval(关键!)

> **最危险的情况**:Hermes 判断了 retry 但还没写 eval_log 就 Reset。
> 此字段必须完整填写,新 Hermes 启动后**第一件事就是处理它**。

```json
{
  "feature_id": "f003",
  "reason": "Hermes 上下文满之前未完成评价",
  "eval_decision": "retry",
  "fix_direction": "补充 mock 数据后重新运行 verify phase"
}
```

或:`无 pending eval`(没有未写入的评价)

## Pending Checkpoints(v0.5 新增)

已推送给用户但用户还没回复的 checkpoint id 列表:
- cp-f006-1
- cp-f007-2

新 Hermes 启动后,要先检查这些 checkpoint 的 decision 字段是否已被更新(用户可能已回复但旧 Hermes 没处理)。

## feature_list 快照(仅摘要)

详见 `.harness/feature_list.json`。此处只记录关键状态:

- f001: status=completed, phase=4
- f002: status=completed, phase=4
- f003: status=in_progress, phase=3(verify 阶段失败,待重试)

## 待确认事项

列出 Hermes Reset 前"没来得及决定"的事:
- {待确认 1}
- {待确认 2}

---

**新 Hermes 读完此文件后的动作顺序**:
1. 处理 Pending Eval(如果有)→ 写 eval_log
2. 检查 Pending Checkpoints 是否有已回复未处理的 → 处理
3. 读 feature_list + sprint_contract + tooling.md 恢复全局感知
4. 继续正常 Planner / Evaluator 工作
