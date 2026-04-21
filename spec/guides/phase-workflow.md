# Phase Workflow Guide

> phase 0-4 的完整定义,以及 phase 切换的精确规则。
> 本文件是 **Generator 和 Evaluator 共同的判断依据**。

---

## Phase 总览

| Phase | Scope | Action | 执行者 | 完成标志 |
|-------|-------|--------|--------|---------|
| 0 | sprint | tooling | Hermes | tooling.md 产出 + gate approved → `feature_list.tooling_locked=true` |
| 1 | feature | plan | Claude Code | feature.children 拆好 + plan checkpoint 通过 |
| 2 | feature | implement | Claude Code | 代码 / 内容编写完,生成约定的产物 |
| 3 | feature | verify | Claude Code | 测试通过 + lint clean + acceptance 自检通过 |
| 4 | feature | deliver | Claude Code | git commit + feature.status=completed |

---

## phase=0 tooling

### 谁来做
**只有 Hermes**。Claude Code 在此 phase **没有任何动作**。

### 产出
`.harness/sprint_contracts/<sprint_id>/tooling.md`,基于 `templates/tooling.template.md` 填空。

### 完成标志
1. tooling.md 6 个章节齐全
2. gate checkpoint 推送给用户
3. 用户回复 approved
4. `feature_list.tooling_locked` 置 `true`

### 硬性约束
`tooling_locked=false` 时,**任何 feature 禁止进入 phase=2**(可以 phase=1 plan,但不能 implement)。

---

## phase=1 plan

### 谁来做
Claude Code,对单个 feature。

### 职责
- 理解 feature 的 name + acceptance
- 拆解出 1-N 个子任务(写入 feature.children,或在 generator_log 记录)
- 不实现代码,只拆

### 产出
- `generator_log.md` 追加 "phase=1 plan" 段
- `feature_list.json` 更新 `next_phases[0].done=true`

### 完成标志(Evaluator 判)
- 子任务拆解合理(对应 acceptance)
- 子任务之间无循环依赖
- generator_log 已记录关键决策

### 可能的 checkpoint
视 `feature.checkpoints` 配置,phase=1 后可能有 gate/review/notify。如果是 gate,Hermes 推 blockers 问用户"大纲 OK 吗"。

---

## phase=2 implement

### 谁来做
Claude Code,对单个 feature。

### 前置条件
- `tooling_locked=true`
- 本 feature 的 phase=1 已 approved
- 依赖的 feature 已 completed

### 职责
- 按 phase=1 的子任务编码 / 生产内容
- 严格遵循 tooling.md 选型(不得擅自换工具)
- 引入新依赖必须 append 到 tooling.md"运行时新增"

### 产出
- 业务产出物(代码 / 文档 / 图片 / 音频等)
- `generator_log.md` 追加 "phase=2 implement" 段

### 不做
- ❌ 测试(留给 phase=3)
- ❌ commit(留给 phase=4)

---

## phase=3 verify

### 谁来做
Claude Code,对单个 feature。

### 职责
- 运行测试(根据 tooling.md 指定的测试框架)
- 运行 lint / format 检查
- 对照 acceptance 自检,每条给出"pass/fail + 证据"
- 如测试 fail 且明确可修:标记 retry,**不进 phase=4**;返回 phase=2 修

### 产出
- 测试输出(跑通的证据)
- `generator_log.md` 追加 "phase=3 verify" 段,含 acceptance 自检表
- `eval_log` 的 `acceptance_results` 字段填全

### 完成标志(Evaluator 判)
- 所有 acceptance 标记为 pass
- 测试全部通过
- 无新增 critical lint error

### Retry 语义
- verify 发现可修 bug → retry 回 phase=2
- retry 计数写入 `sprint_contract.iteration_history`
- 达到 `max_iterations` 升级人类

---

## phase=4 deliver

### 谁来做
Claude Code,对单个 feature。

### 前置条件
phase=3 已 approved(Evaluator 判 pass)。

### 职责
- `git add <明确的文件>`
- `git commit` 按 `spec/project.md` commit 格式
- 更新 `feature_list.json` 本 feature `status=completed`, `commit=<hash>`, `completed_at=<timestamp>`
- 释放 session_pool 里本 feature 的槽位

### 完成标志
- commit 成功
- feature_list 更新完成
- 触发下游依赖 feature 启动的信号已发出(Hermes 监听 feature_list 变化)

---

## Phase 切换决策表

| 当前 phase | 结果 | 下一步 |
|---|---|---|
| 1 plan | Evaluator pass | phase=2 |
| 1 plan | Evaluator retry | 重走 phase=1 |
| 1 plan | checkpoint rejected | replan,重走 phase=1 |
| 2 implement | Evaluator pass | phase=3 |
| 2 implement | Evaluator retry | 重走 phase=2 |
| 3 verify | Evaluator pass | phase=4 |
| 3 verify | Evaluator retry | **返回 phase=2**(不是 phase=3)|
| 3 verify | Evaluator fail | 升级 Hermes,可能 replan |
| 4 deliver | Evaluator pass | feature completed |
| 4 deliver | Evaluator retry | 修 commit(谨慎)|

---

## 禁止跳 phase

- ❌ phase=1 不能直接跳 phase=3
- ❌ phase=2 不能直接跳 phase=4
- ❌ phase=3 不能直接跳 phase=4(即使自觉没问题)
- ❌ phase=4 完成后不能回 phase=1(需要新 feature)

发现跳 phase,Evaluator 直接判 fail,写 `event_type=fail`。
