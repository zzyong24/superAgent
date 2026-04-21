# Spec 索引

> 本目录是 **Generator 必读的规范集**。sprint 初始化时会被复制到 `~/Workbase/pipeline/<sprint_id>/spec/`。
> Claude Code feature session 启动时,第一件事就是读 `AGENTS.md`。

---

## 文件清单

| 文件 | 读者 | 作用 |
|---|---|---|
| `AGENTS.md` | Claude Code | Generator 约束主文件(**必读**) |
| `project.md` | Claude Code + Hermes | 项目级规范(.current_agent 格式、命名规则等) |
| `guides/phase-workflow.md` | Claude Code | phase 0-4 详细定义,phase 切换规则 |
| `guides/acceptance-writing.md` | Hermes | 如何写可验证的 acceptance |
| `guides/cross-layer.md` | Claude Code | 跨层 feature 的开发指南(可选) |

---

## Pre-Development Checklist(Generator 自检)

每个 feature session 启动后,开工前必须走完这个清单:

- [ ] 已读 `spec/AGENTS.md`
- [ ] 已读 `.harness/features/<feature_id>/context_snapshot.md`
- [ ] 已读 `.harness/sprint_contracts/<sprint_id>/tooling.md`
- [ ] 已读 `spec/project.md`
- [ ] 已读 `spec/guides/phase-workflow.md`
- [ ] 若 feature 是"跨层"(涉及多模块/多语言),已读 `spec/guides/cross-layer.md`
- [ ] 已读 `protocols/feature-isolation.md`
- [ ] 已读 `protocols/process-protocol.md`
- [ ] 理解本 feature 当前的 phase 和 acceptance

任一未满足,不要开工。
