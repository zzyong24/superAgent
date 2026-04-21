# SKILL.md

你是 Hermes。按以下顺序执行。

---

## STEP 1 初始化

### 1.1 定位 sprint 目录

- 今天日期: `YYYYMMDD`
- 扫描 `~/Workbase/pipeline/sprint_YYYYMMDD_*` 最大序号 N
- 本次 sprint 目录: `~/Workbase/pipeline/sprint_YYYYMMDD_<N+1>/`
- 记作 `$HARNESS_ROOT`

### 1.2 复制 skill 资源到 sprint 目录

从本 skill 根目录,复制到 `$HARNESS_ROOT/`:

```
schemas/  →  $HARNESS_ROOT/schemas/
templates/  →  $HARNESS_ROOT/templates/
spec/  →  $HARNESS_ROOT/spec/
protocols/  →  $HARNESS_ROOT/protocols/
hooks/  →  $HARNESS_ROOT/.claude-hooks-src/  (暂存,feature 启动时用)
```

**不复制** `SKILL.md` / `README.md` / `sub-skills/`(Hermes 自己留着)。

### 1.3 建运行时骨架

```
$HARNESS_ROOT/.harness/
├── features/
├── sprint_contracts/
└── logs/
```

### 1.4 初始化状态文件

按 `schemas/` 对应 schema,生成:

| 文件 | 初始值 |
|---|---|
| `.harness/runtime_state.json` | `{mode:"planning", current_sprint:"sprint_YYYYMMDD_<N+1>", current_project_path:"<HARNESS_ROOT>", pending_user_replies:[], session_started_at:<now>, last_heartbeat:<now>}` |
| `.harness/feature_list.json` | `{version:"1.2", sprint:"<sprint_id>", tooling_locked:false, features:[]}` |
| `.harness/session_pool.json` | `{max_concurrent:2, policy:"start_when_dependency_ready", active:{}}` |
| `.harness/eval_log.jsonl` | 空文件 |
| `.harness/hermes_context_state.json` | `{agent:"hermes", updated_at:<now>, token_usage_ratio:0, consecutive_sprints_with_retries:0, current_sprint:"<sprint_id>", session_start:<now>}` |
| `.harness/claude_code_context_state.json` | `{}` |
| `.harness/.current_agent` | `{role:"planner", platform:"hermes", developer:"hermes", started_at:<now>}` |

### 1.5 自检

- [ ] 4 个复制目录齐全
- [ ] `.harness/` 7 个状态文件齐全且通过 schema 校验
- [ ] `.claude-hooks-src/` 存在且 `*.sh` 有可执行权限

**任一失败 → 报告用户 + 停止**。

---

## STEP 2 Planner

进入 `sub-skills/sprint-planner.md` 严格执行。产出:

1. `.harness/sprint_contracts/<sprint_id>/tooling.md`(phase=0)+ tooling gate 通过
2. `.harness/feature_list.json` feature DAG(phase=1)+ DAG gate 通过
3. `.harness/sprint_contracts/<sprint_id>/contract.json`
4. 置 `feature_list.tooling_locked=true`, `sprint_contract.status="active"`, `runtime_state.mode="active"`

---

## STEP 3 部署 Claude Code feature 工作区

对 `feature_list` 中 `depends_on` 为空或全部 completed 的 feature,**按 max_concurrent 上限**启动。

对每个要启动的 feature `f<N>`:

### 3.1 建 feature 目录

```
$HARNESS_ROOT/.harness/features/f<N>/
├── context_snapshot.md   # 按 templates/feature_session_init.template.md 填空
├── AGENTS.md              # 从 spec/AGENTS.md 复制
├── generator_log.md       # 按 templates/generator_log.template.md 空壳
├── handoff.md             # 空文件
├── session_id.txt         # 空文件
└── .claude/
    ├── settings.json      # 见 3.2
    └── hooks/             # 见 3.2
```

### 3.2 部署 hook(必须,硬约束)

```bash
FDIR=$HARNESS_ROOT/.harness/features/f<N>
mkdir -p $FDIR/.claude/hooks
cp $HARNESS_ROOT/.claude-hooks-src/session-start.sh $FDIR/.claude/hooks/
cp $HARNESS_ROOT/.claude-hooks-src/pre-edit-guard.sh $FDIR/.claude/hooks/
cp $HARNESS_ROOT/.claude-hooks-src/pre-bash-guard.sh $FDIR/.claude/hooks/
cp $HARNESS_ROOT/.claude-hooks-src/stop-guard.sh $FDIR/.claude/hooks/
chmod +x $FDIR/.claude/hooks/*.sh

# 渲染 settings.json(替换 HARNESS_ROOT 占位符)
sed "s|\${HARNESS_ROOT}|$HARNESS_ROOT|g" \
  $HARNESS_ROOT/.claude-hooks-src/settings.json.template \
  > $FDIR/.claude/settings.json
```

### 3.3 启动 session

```bash
HARNESS_ROOT=$HARNESS_ROOT \
FEATURE_ID=f<N> \
SPRINT_ID=<sprint_id> \
claude-code --cwd $FDIR
```

把 `context_snapshot.md` 内容作为初始 prompt 注入。

### 3.4 更新状态

```
session_pool.active.f<N> = {session_id, status:"running", started_at:<now>, current_phase:1}
.current_agent: role=generator, developer=claude-code, current_feature=f<N>, current_phase=1
```

---

## STEP 4 Evaluator 监听

所有 feature 启动后,进入 `sub-skills/sprint-evaluator.md`。事件驱动:

- eval_log 新增条目 → phase 判决
- feature_list.status 变化 → 释放 session 槽 / 触发下游依赖
- 用户飞书回复 → 按 `protocols/checkpoint-qa.md` 解析
- session 失联 → 按 `protocols/reset-mechanism.md` 触发 feature Reset

每次事件处理后自检 Hermes Reset 条件 → 触达进入 `sub-skills/hermes-reset.md`。

---

## STEP 5 Sprint 收尾

所有 feature status ∈ {completed, cancelled} → `sub-skills/sprint-finalizer.md`:

- 过程协议完整性检查
- 问用户是否沉淀管线
- 写入 `~/.hermes/pipelines/<id>/` 或归档
- `runtime_state.mode="idle"`

---

## 引用索引

| 场景 | 文件 |
|---|---|
| 选型决策 + feature 拆分 | `sub-skills/sprint-planner.md` |
| 判决 + checkpoint 处理 | `sub-skills/sprint-evaluator.md` |
| sprint 收尾 + 管线沉淀 | `sub-skills/sprint-finalizer.md` |
| 自身 Reset | `sub-skills/hermes-reset.md` |
| checkpoint 问答协议 | `protocols/checkpoint-qa.md` |
| YOLO 规则 | `protocols/yolo.md` |
| feature 并行规则 | `protocols/feature-isolation.md` |
| 双 Reset 机制 | `protocols/reset-mechanism.md` |
| 过程协议落盘清单 | `protocols/process-protocol.md` |

---

## 铁律

- 单 sprint 独占(不并行)
- tooling_locked=false 禁止任何 feature 进入 phase=2
- 两个 gate(tooling + DAG)必须通过才进 Evaluator
- pending_eval / pending_checkpoints 处理先于任何新决策
- Hermes Reset 落盘顺序:handoff → context_state → runtime_state
- 所有 feature session 必须带 hook 启动(STEP 3.2)
- 过程协议缺漏不能沉淀管线
