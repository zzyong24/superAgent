# Bootstrap & Validation Protocol

> **承接** SKILL.md 里的 bash 校验命令和 JSON 示例。
> Hermes 在对应 STEP 需要具体命令时查本文件,不需要时**不加载**。
> 本文件是"动作百科",不是"规则",规则仍在 SKILL.md 的铁律章节。

---

## 1. STEP 0.5 环境能力探测

### 1.1 必跑的探测命令

```bash
# 1. which claude-code
which claude-code 2>&1

# 2. claude-code 版本号(验证真能启动,不只是找到文件)
claude-code --version 2>&1

# 3. 用户是否配了别名 / 路径
command -v claude-code 2>&1
command -v claude 2>&1

# 4. 环境变量
echo "PATH=$PATH"
echo "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:+SET}${ANTHROPIC_API_KEY:-UNSET}"
```

### 1.2 探测结果的 3 种情况

| 情况 | 判据 | 行动 |
|---|---|---|
| **A. CLI 可用** | `claude-code --version` 返回版本号 | 记录实际命令路径,后续 STEP 3.3 用此路径启 session |
| **B. CLI 不可用** | `which claude-code` 无输出 且 `claude` 也无 | 推 gate checkpoint 问用户:"未检测到 claude-code CLI,请确认:(a) 已安装但不在 PATH→请告诉我绝对路径 (b) 未安装→需要安装或换架构 (c) 确认无此能力,切换 Hermes-only 模式"。**不得自行决定**。 |
| **C. 不确定** | 命令报错或输出异常 | 把完整输出(stderr+stdout)贴给用户,问 (a)(b)(c) 同 B |

### 1.3 探测结果必须落盘

在 `$HARNESS_ROOT` 建好后,立刻写入 `$HARNESS_ROOT/.harness/environment_probe.json`:

```json
{
  "probed_at": "<now_utc>",
  "claude_code_cli": {
    "which_output": "<which claude-code 的原样输出>",
    "version_output": "<claude-code --version 的原样输出>",
    "resolved_command": "<实际将用于启 session 的命令,如 /usr/local/bin/claude-code>",
    "status": "available | unavailable | uncertain"
  },
  "api_keys": {
    "anthropic": "SET | UNSET"
  }
}
```

---

## 2. STEP 1.4 状态文件初始值

按对应 schema 生成。**时间戳必须是 ISO 8601 UTC 带 Z**,生成命令:`date -u +%Y-%m-%dT%H:%M:%SZ`

| 文件 | 初始值 | 对应 schema |
|---|---|---|
| `.harness/runtime_state.json` | `{mode:"planning", current_sprint:"<sprint_id>", current_project_path:"<HARNESS_ROOT 绝对路径>", pending_user_replies:[], session_started_at:<now_utc>, last_heartbeat:<now_utc>, last_reset_at:null}` | runtime_state.schema.json |
| `.harness/feature_list.json` | `{version:"1.2", sprint:"<sprint_id>", pipeline_id:null, pipeline_version:null, tooling_locked:false, updated_at:<now_utc>, updated_by:"hermes", features:[], blocked:[]}` | feature_list.schema.json |
| `.harness/session_pool.json` | `{max_concurrent:2, policy:"start_when_dependency_ready", active:{}}` | session_pool.schema.json |
| `.harness/eval_log.jsonl` | 空文件(0 字节) | eval_log.schema.json 逐行 |
| `.harness/hermes_context_state.json` | `{agent:"hermes", updated_at:<now_utc>, token_usage_ratio:0, consecutive_sprints_with_retries:0, current_sprint:"<sprint_id>", session_start:<now_utc>, pending_eval:null, pending_checkpoints:[]}` | — |
| `.harness/claude_code_context_state.json` | `{}` | — |
| `.harness/.current_agent` | `{role:"planner", platform:"hermes", developer:"hermes", session_id:null, started_at:<now_utc>, current_feature:null, current_phase:null, last_activity:<now_utc>}` | 见 spec/project.md 第 2 条 |

---

## 3. STEP 1.5 自检命令

任一非零退出立即停止:

```bash
# 1. 五个 skill 资源目录存在且非空
test -d "$HARNESS_ROOT/schemas" && ls "$HARNESS_ROOT/schemas" | grep -q .
test -d "$HARNESS_ROOT/templates" && ls "$HARNESS_ROOT/templates" | grep -q .
test -d "$HARNESS_ROOT/spec" && ls "$HARNESS_ROOT/spec" | grep -q .
test -d "$HARNESS_ROOT/protocols" && ls "$HARNESS_ROOT/protocols" | grep -q .
test -d "$HARNESS_ROOT/.claude-hooks-src" && ls "$HARNESS_ROOT/.claude-hooks-src/"*.sh | grep -q .

# 2. hook 脚本可执行
for f in session-start pre-edit-guard pre-bash-guard stop-guard; do
  test -x "$HARNESS_ROOT/.claude-hooks-src/$f.sh"
done

# 3. 7 个状态文件存在
for f in runtime_state feature_list session_pool hermes_context_state claude_code_context_state .current_agent; do
  test -f "$HARNESS_ROOT/.harness/$f.json" || test -f "$HARNESS_ROOT/.harness/$f"
done
test -f "$HARNESS_ROOT/.harness/eval_log.jsonl"

# 4. 3 个运行时目录存在
test -d "$HARNESS_ROOT/.harness/features"
test -d "$HARNESS_ROOT/.harness/sprint_contracts"
test -d "$HARNESS_ROOT/.harness/logs"

# 5. runtime_state.current_project_path 字面等于 $HARNESS_ROOT
jq -e --arg p "$HARNESS_ROOT" '.current_project_path == $p' "$HARNESS_ROOT/.harness/runtime_state.json"

# 6. 根目录无平铺文件污染(只读资源不能平铺)
POLLUTED=$(find "$HARNESS_ROOT" -maxdepth 1 -type f \( \
    -name "*.schema.json" -o -name "*.template.md" \
    -o -name "AGENTS.md" -o -name "index.md" -o -name "project.md" \
    -o -name "checkpoint-qa.md" -o -name "yolo.md" \
    -o -name "feature-isolation.md" -o -name "reset-mechanism.md" \
    -o -name "process-protocol.md" -o -name "execution-paths.md" \
    -o -name "pipeline.schema.yaml" \
  \))
if [ -n "$POLLUTED" ]; then
  echo "❌ 根目录平铺了只读文件(必须只存在于子目录):"
  echo "$POLLUTED"
  exit 1
fi
```

---

## 4. STEP 2.5 进入 STEP 3 前的硬校验

### 4.1 sprint 级前置条件

```bash
FL=$HARNESS_ROOT/.harness/feature_list.json
RS=$HARNESS_ROOT/.harness/runtime_state.json
EL=$HARNESS_ROOT/.harness/eval_log.jsonl
SC_DIR=$HARNESS_ROOT/.harness/sprint_contracts

# 1. tooling_locked 必须为 true
jq -e '.tooling_locked == true' $FL || { echo "❌ tooling_locked=false,不得推进"; exit 1; }

# 2. eval_log 必须有 tooling gate approved
grep -q '"checkpoint_id":"cp-sprint-tooling"' $EL && \
  grep '"checkpoint_id":"cp-sprint-tooling"' $EL | tail -1 | grep -qE '"decision":"(approved|pass)"' \
  || { echo "❌ tooling gate 未 approved"; exit 1; }

# 3. eval_log 必须有 DAG gate approved
grep -q '"checkpoint_id":"cp-sprint-dag"' $EL && \
  grep '"checkpoint_id":"cp-sprint-dag"' $EL | tail -1 | grep -qE '"decision":"(approved|pass)"' \
  || { echo "❌ DAG gate 未 approved(或从未推送)"; exit 1; }

# 4. runtime_state.mode 必须是合法枚举
jq -re '.mode' $RS | grep -qE '^(idle|planning|active|waiting_human|suspended)$' \
  || { echo "❌ runtime_state.mode 非法枚举"; exit 1; }

# 5. sprint_contract status 合法
find $SC_DIR -name contract.json | head -1 | xargs -I{} jq -re '.status' {} \
  | grep -qE '^(planning|tooling|planned|active|waiting_human|suspended|finalizing|sunk|closed)$' \
  || { echo "❌ sprint_contract.status 非法"; exit 1; }
```

### 4.2 每个要启动的 feature 级前置条件

对每个要置为 `in_progress` 或 phase >= 2 的 feature `<fid>`:

```bash
FDIR=$HARNESS_ROOT/.harness/features/<fid>

# 1. feature 目录存在
test -d $FDIR || { echo "❌ $fid: 目录不存在,必须先走 STEP 3.1"; exit 1; }

# 2. feature 5 个文件齐全
test -f $FDIR/context_snapshot.md || { echo "❌ $fid: 缺 context_snapshot.md"; exit 1; }
test -f $FDIR/AGENTS.md || { echo "❌ $fid: 缺 AGENTS.md"; exit 1; }
test -f $FDIR/generator_log.md || { echo "❌ $fid: 缺 generator_log.md"; exit 1; }
test -f $FDIR/handoff.md || touch $FDIR/handoff.md
test -f $FDIR/session_id.txt || { echo "❌ $fid: 缺 session_id.txt"; exit 1; }

# 3. hook 4 个 + settings.json 部署到位
for h in session-start pre-edit-guard pre-bash-guard stop-guard; do
  test -x $FDIR/.claude/hooks/$h.sh || { echo "❌ $fid: hook $h.sh 未部署"; exit 1; }
done
test -f $FDIR/.claude/settings.json || { echo "❌ $fid: settings.json 未部署"; exit 1; }

# 4. session_pool.active.<fid> 必须非空
jq -e --arg f $fid '.active[$f]' $HARNESS_ROOT/.harness/session_pool.json \
  || { echo "❌ $fid: session_pool.active 无此 feature"; exit 1; }

# 5. session_id.txt 非空(CC 进程写入过,或 Hermes 写入 hermes-proxy-<fid>)
test -s $FDIR/session_id.txt \
  || { echo "❌ $fid: session_id.txt 为空,CC 未真正启动"; exit 1; }

# 6. .current_agent 指向该 feature
jq -e --arg f $fid \
  '.role == "generator" and .current_feature == $f' \
  $HARNESS_ROOT/.harness/.current_agent \
  || { echo "❌ .current_agent 未切换到 generator"; exit 1; }
```

### 4.3 违规即回滚

如果发现某 feature 已被写成 `in_progress` / `phase >= 2` 但上述检查不过:

1. 把该 feature 状态回滚到 `status=pending, phase=1`
2. 在 eval_log 追加一条 `event_type=fail`,`reason="违反 STEP 2.5 硬校验:<具体哪条>"`
3. 停止任何后续动作,推 gate checkpoint 给用户说明

---

## 5. STEP 3.1 feature 目录创建

### 5.1 目录路径铁律

```bash
FDIR=$HARNESS_ROOT/.harness/features/f<N>    # ← 就是这个路径,不要改
mkdir -p $FDIR/.claude/hooks
```

**错误位置**:
- ❌ `$HARNESS_ROOT/f<N>/.harness/`(顺序反了)
- ❌ `$HARNESS_ROOT/features/f<N>/`(少了 `.harness`)
- ❌ `$HARNESS_ROOT/.harness/f<N>/`(少了 `features`)

### 5.2 必需的 5 个文件

| 文件 | 生成方式 |
|---|---|
| `context_snapshot.md` | 基于 `$HARNESS_ROOT/templates/feature_session_init.template.md` 填空(feature_id / name / acceptance / depends_on 产物路径 / 当前 phase / execution_path) |
| `AGENTS.md` | `cp $HARNESS_ROOT/spec/AGENTS.md $FDIR/AGENTS.md` |
| `generator_log.md` | `cp $HARNESS_ROOT/templates/generator_log.template.md $FDIR/generator_log.md`,替换 `{feature_id}` 占位符 |
| `handoff.md` | `touch $FDIR/handoff.md`(空文件,Reset 时填) |
| `session_id.txt` | `touch $FDIR/session_id.txt`(空文件,STEP 3.3 填) |

---

## 6. STEP 3.2 Hook 部署

### 6.1 generator_cc / generator_cc_mcp 路径

```bash
# 复制 4 个 hook 脚本 + settings 模板
cp $HARNESS_ROOT/.claude-hooks-src/session-start.sh    $FDIR/.claude/hooks/
cp $HARNESS_ROOT/.claude-hooks-src/pre-edit-guard.sh   $FDIR/.claude/hooks/
cp $HARNESS_ROOT/.claude-hooks-src/pre-bash-guard.sh   $FDIR/.claude/hooks/
cp $HARNESS_ROOT/.claude-hooks-src/stop-guard.sh       $FDIR/.claude/hooks/
chmod +x $FDIR/.claude/hooks/*.sh

sed "s|\${HARNESS_ROOT}|$HARNESS_ROOT|g" \
    $HARNESS_ROOT/.claude-hooks-src/settings.json.template \
  > $FDIR/.claude/settings.json

# 验证
test -f $FDIR/.claude/settings.json || { echo "❌ settings.json 未部署"; exit 1; }
for h in session-start pre-edit-guard pre-bash-guard stop-guard; do
  test -x $FDIR/.claude/hooks/$h.sh || { echo "❌ $h.sh 未部署或无执行权限"; exit 1; }
done
```

### 6.2 generator_mcp_direct 路径(简化版)

详见 `protocols/execution-paths.md` 第 3.C 节。核心差异:

- 可以不复制 `session-start.sh`(没 CC session 启动)
- `settings.json` 写自检标记:`{"_self_audit_mode": "hermes_mcp_proxy"}`
- Hermes 代理执行时**每次写文件前手动调 pre-edit-guard.sh 自检**(见 execution-paths.md 第 4 节)

---

## 7. STEP 3.4 状态更新命令

### 7.1 session_pool.json 更新

**位置铁律**:`$HARNESS_ROOT/.harness/session_pool.json` 是**唯一**的 session pool 文件。不在每个 feature 下建自己的。

```bash
POOL=$HARNESS_ROOT/.harness/session_pool.json
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# 读 session_id.txt
SID=$(cat $FDIR/session_id.txt)

# 按路径确定 session_type
case "<本 feature 的 execution_path>" in
  generator_cc)         STYPE="cc-print" ;;
  generator_cc_mcp)     STYPE="cc-interactive-mcp" ;;
  generator_mcp_direct) STYPE="mcp_direct" ;;
esac

# 更新 active 字典
jq --arg f "f<N>" --arg sid "$SID" --arg t "$NOW" --arg st "$STYPE" \
  '.active[$f] = {
     session_id: $sid,
     session_type: $st,
     status: "running",
     started_at: $t,
     current_phase: 1,
     last_activity: $t
   }' $POOL > $POOL.tmp && mv $POOL.tmp $POOL
```

### 7.2 .current_agent 更新

```bash
CA=$HARNESS_ROOT/.harness/.current_agent    # ← 文件名无 .json 扩展名
# 确保只有这一个文件,删掉 .current_agent.json 如果存在
rm -f $HARNESS_ROOT/.harness/.current_agent.json

jq --arg sid "$SID" --arg f "f<N>" --arg t "$NOW" \
  '.role = "generator"
   | .session_id = $sid
   | .current_feature = $f
   | .current_phase = 1
   | .last_activity = $t
   | .developer = (if .session_id | startswith("hermes-proxy") then "hermes-as-proxy" else "claude-code" end)' \
  $CA > $CA.tmp && mv $CA.tmp $CA
```

---

## 8. STEP 3.5 Phase 推进 eval_log 格式

### 8.1 phase=1 plan

```json
{
  "timestamp": "<now_utc>",
  "sprint_id": "<sprint_id>",
  "feature_id": "f<N>",
  "phase": 1,
  "event_type": "phase_evaluation",
  "result": "pass",
  "reason": "<具体拆了什么子任务,说了就是 plan>"
}
```

### 8.2 phase=2 implement

```json
{
  "timestamp": "<now_utc>",
  "sprint_id": "<sprint_id>",
  "feature_id": "f<N>",
  "phase": 2,
  "event_type": "phase_evaluation",
  "result": "pass",
  "reason": "<产出物路径 + 核心动作总结>"
}
```

### 8.3 phase=3 verify(**关键:必含 acceptance_results**)

这一条是管线能否沉淀的**关键证据**。缺 `acceptance_results` 或没有逐条对应 feature.acceptance → phase=3 不能判 pass。

```json
{
  "timestamp": "<now_utc>",
  "sprint_id": "<sprint_id>",
  "feature_id": "f<N>",
  "phase": 3,
  "event_type": "phase_evaluation",
  "result": "pass",
  "reason": "<总结:N 条 acceptance 逐条通过,证据见 acceptance_results>",
  "acceptance_results": [
    {
      "id": "a1",
      "criteria": "<feature.acceptance[0] 原文>",
      "status": "pass",
      "evidence": "<可验证的证据,如:文件 md5 / 行数 / 输出片段 / test 命令返回 0>"
    },
    {
      "id": "a2",
      "criteria": "<feature.acceptance[1] 原文>",
      "status": "pass",
      "evidence": "<证据>"
    }
  ]
}
```

**铁律**:
- `acceptance_results` 数组长度 == `feature.acceptance` 数组长度
- 每条 `criteria` 字段是 feature.acceptance 的原样文字
- `status` 只能是 `pass` / `fail` / `skipped`
- `evidence` 不能空,不能敷衍("ok" / "done" / "no issue" 都不行,stop-guard 会拦)

### 8.4 phase=4 deliver

```json
{
  "timestamp": "<now_utc>",
  "sprint_id": "<sprint_id>",
  "feature_id": "f<N>",
  "phase": 4,
  "event_type": "phase_evaluation",
  "result": "pass",
  "reason": "<commit 信息 / 交付路径>",
  "commit": "<git commit hash>"
}
```

### 8.5 每次 phase 切换必须同步更新

- `feature_list.features[N].phase` → 新 phase
- `feature_list.features[N].next_phases[i].done` → 刚完成那个 phase 置 true
- `feature_list.features[N].next_phases[i+1].current` → 下一个 phase 置 true,其他置 false
- `session_pool.active.f<N>.current_phase` → 新 phase
- `session_pool.active.f<N>.last_activity` → now_utc

### 8.6 phase=4 完成后

- `feature_list.features[N].status` → `"completed"`
- `feature_list.features[N].completed_at` → now_utc
- `feature_list.features[N].commit` → git commit hash
- `session_pool.active.f<N>` 字段 → **从 `active` 字典删除**(不保留 `status: completed`)
- 触发下游依赖的 feature 启动(见 protocols/feature-isolation.md)

---

## 9. 查询索引

按 STEP 反查本文件章节:

| SKILL.md 引用 | 本文件章节 |
|---|---|
| STEP 0.5 探测命令 | §1 |
| STEP 1.4 状态文件初始值 | §2 |
| STEP 1.5 自检 | §3 |
| STEP 2.5 硬校验 | §4 |
| STEP 3.1 目录创建 | §5 |
| STEP 3.2 Hook 部署 | §6 |
| STEP 3.4 状态更新 jq 命令 | §7 |
| STEP 3.5 Phase eval_log JSON | §8 |
