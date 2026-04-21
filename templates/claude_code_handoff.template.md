# Claude Code Feature Handoff

> **模板说明**:Claude Code feature session 触发 Reset 时(token>70% / retry>=2 / >2h),由当前 session 自己写入。
> 位置:`.harness/features/f<N>/handoff.md`
> 用途:同 feature 新 session 启动时的"中断快照"。

**Generated at**: {timestamp}
**Feature**: {feature_id}
**Sprint**: {sprint_id}
**Trigger reason**: {reason}

---

## 当前状态

### 已完成
- phase=1 plan ✓(输出了子任务清单)
- phase=2 implement 进度 70%

### 进行中
- **Phase**: {current_phase}
- **Action**: {current_action}
- **完成度**: {pct}%
- **最后工作**: {last_work_description}
- **当前文件**: {current_files}
- **阻塞点**: {blockers_if_any}

## 下一步计划

按顺序列出新 session 接手后该做的事:
1. {next_step_1}
2. {next_step_2}
3. {next_step_3}

## 关键架构决策

本 feature 执行中已经做出的决策(避免新 session 重复决策或翻案):
- 使用 {tech_choice} 作为 {purpose}(在 tooling.md 已定义)
- Token 存储在 {location}
- ...

## 最近失败模式

Evaluator 历史 retry 反馈、本 feature 遇到过的坑:
- {failure_mode_1}
- {failure_mode_2}

## 运行时依赖变更

本 feature 执行中引入的新工具 / 依赖(已同步写入 sprint tooling.md 的"运行时新增"章节):
- {new_dependency_1}

## 给新 session 的提醒

- 必读:`.harness/features/{feature_id}/context_snapshot.md`
- 必读:`.harness/sprint_contracts/{sprint_id}/tooling.md`
- 必读:`spec/AGENTS.md`
- 必读:本文件

**新 session 禁止**:
- ❌ 重新走 phase=1(已完成)
- ❌ 翻盘 tooling 决策
- ❌ 跳过 verify 直接 deliver
