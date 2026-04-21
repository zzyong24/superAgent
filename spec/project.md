# 项目级规范

> 本文件是所有 Agent(Hermes / Claude Code)共同遵守的基础规范。
> sprint 初始化时被复制到工作区,为本次 sprint 的"常识基准"。

---

## 1. 命名规则

### Sprint id
`sprint_<YYYYMMDD>_<N>`,如 `sprint_20260421_1`。
同一天多 sprint(实际不允许,但编号为兼容)递增 N。

### Feature id
`f<number>`,如 `f001`、`f002`。子 feature 用 `f001-1`、`f001-2`。

### Checkpoint id
`cp-<feature_id>-<seq>`,如 `cp-f006-1`(f006 的第 1 个 checkpoint)。

### Session id
由 Claude Code 启动时生成,格式如 `sess_abc123`。写入 `.harness/features/<feature_id>/session_id.txt`。

## 2. `.current_agent` 文件格式

位置:`.harness/.current_agent`

```json
{
  "role": "planner | generator | evaluator",
  "platform": "hermes | claude-code",
  "developer": "hermes | claude-code",
  "session_id": "sess_abc123",
  "started_at": "2026-04-21T00:00:00Z",
  "current_feature": "f001",
  "current_phase": 2,
  "last_activity": "2026-04-21T00:30:00Z"
}
```

- sprint 进入 planning 时,role=planner,developer=hermes
- 交接给 Claude Code feature 执行时,role=generator,developer=claude-code
- Evaluator 阶段 role=evaluator,developer=hermes
- **任意时刻只能有一个 current_agent**。这是读写 feature_list / eval_log 的授权标记

## 3. 文件读写授权

| 文件 | Hermes | Claude Code |
|---|---|---|
| `runtime_state.json` | 读 + 写 | 读 |
| `feature_list.json` | 读 + 写 | 读 + 写自己的 feature 的 phase/status |
| `sprint_contracts/<id>/contract.json` | 读 + 写 | 只读 |
| `sprint_contracts/<id>/tooling.md` | 读 + 写 | 只读 + append 到"运行时新增" |
| `eval_log.jsonl` | append | append |
| `session_pool.json` | 读 + 写 | 读 |
| `features/<fid>/*.md` | 读 + 写 | 读 + 写(仅自己的 feature 目录) |
| `hermes_handoff.md` | 读 + 写 | 不访问 |
| `spec/` / `schemas/` / `templates/` / `protocols/` | 只读 | 只读 |

## 4. 时间戳格式

所有时间戳使用 ISO 8601 UTC:`2026-04-21T00:30:00Z`。

## 5. 日志原则

- `eval_log.jsonl` 是 **append-only**,永不删除、永不修改历史条目
- `generator_log.md` 是 **append-only**,每个 phase 追加一段,不修改历史段
- `hermes_handoff.md` 每次 Reset 完全覆盖(不是历史档案,是最新中断快照)

## 6. Commit 规范(deliver phase)

Claude Code 在 phase=4 deliver 时 git commit,message 格式:

```
[<feature_id>] <简短描述>

<详细描述>

Sprint: <sprint_id>
Phase: 4
```

例:
```
[f001] JWT 验证模块完成

- 实现 JwtVerifier 类
- 单元测试覆盖率 92%
- 所有 acceptance 通过

Sprint: sprint_20260421_1
Phase: 4
```

## 7. 禁止

- ❌ 不得用 `git add -A` 或 `git add .`,必须明确指定文件
- ❌ 不得 `git commit --amend` 已 push 的 commit
- ❌ 不得 `git push --force`
- ❌ 不得修改 `.harness/` 以外项目主仓库的文件(除非 feature 的 acceptance 明确要求)
- ❌ 不得在生产环境操作(除非 tooling.md 明确授权)
