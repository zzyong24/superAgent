# Execution Paths Protocol

> **Feature 的三条执行路径**。phase=0 tooling 时,每个 feature 必须**显式分配**到一条路径,写入 tooling.md 第 6 节"Feature 执行路径分类"。
> 路径决定:谁执行产出、如何部署 hook、过程协议如何落盘。

---

## 1. 三条路径定义

| 路径 | 产出者 | 适用场景 | 示例 |
|---|---|---|---|
| **generator_cc** | Claude Code(CLI)+ hook | 代码 / HTML / 脚本 / 配置文件 / 结构化文本 | 写 React 组件、生成 HTML PPT、写 shell 脚本 |
| **generator_cc_mcp** | Claude Code(交互模式)+ MCP 配置 + hook | 需要调 MCP 的代码 / 内容生产 | 读飞书文档写代码、基于 vault 搜索写 PR |
| **generator_mcp_direct** | Hermes 直调 MCP(受限豁免) | 纯检索 / 纯工具调用 / CC 能力无增值 | `web_search` 检索、TTS 配音、MCP 存储调用 |

**默认选 generator_cc**。只有明确说明"CC 能力不增值"或"CC `--print` 无法访问必需 MCP"时,才考虑其他两条。

---

## 2. 路径选择决策表

phase=0 tooling 时对每个 feature 问 5 个问题:

| 问题 | 答"是"则 | 答"否"则 |
|---|---|---|
| Q1: 产出物是代码、HTML、脚本、配置、结构化文本? | 倾向 generator_cc | 看 Q2 |
| Q2: 产出物是纯检索结果(摘要、列表、外部数据抓取)? | 倾向 generator_mcp_direct | 看 Q3 |
| Q3: 产出物是 MCP 工具的**直接调用结果**(TTS 音频、MCP 存储 ID)? | 倾向 generator_mcp_direct | 看 Q4 |
| Q4: CC `--print` 能访问必需的工具吗? | generator_cc | 看 Q5 |
| Q5: 必需 MCP 可通过 `.mcp.json` 配置交互模式加载吗? | generator_cc_mcp | generator_mcp_direct |

**generator_mcp_direct 的硬禁区**:

- ❌ 发布类操作(git push / 飞书发布 / 生产部署)—— 必须走 generator_cc 或 generator_cc_mcp
- ❌ 代码生成 —— CC 增值明显
- ❌ "看起来很麻烦所以绕过 CC" —— 这不是理由

---

## 3. 三条路径的 STEP 3 执行差异

### 3.A generator_cc(标准路径)

**STEP 3.1 建目录**: 按 SKILL.md STEP 3.1 正常建 5 个文件

**STEP 3.2 部署 hook**: 按 SKILL.md STEP 3.2 原样执行

**STEP 3.3 启动**:

```bash
# 启 CC(--print 非交互模式,写代码用)
HARNESS_ROOT=$HARNESS_ROOT \
FEATURE_ID=f<N> \
SPRINT_ID=<sprint_id> \
claude --print "$(cat $FDIR/context_snapshot.md)" \
  --settings $FDIR/.claude/settings.json \
  --cwd $FDIR \
  > $FDIR/generator_log.md.cc_output \
  2>&1

# 读 stdout 取 CC 的 session id,写入 session_id.txt
grep -oE 'session_[a-z0-9]+' $FDIR/generator_log.md.cc_output | head -1 \
  > $FDIR/session_id.txt
```

**STEP 3.4 状态更新**: `session_pool.active.f<N>.session_type = "cc-print"`

---

### 3.B generator_cc_mcp(CC + MCP 配置)

**STEP 3.1**: 按标准 + **额外生成 `.mcp.json`**:

```bash
cat > $FDIR/.mcp.json <<'EOF'
{
  "mcpServers": {
    "<mcp_name>": {
      "command": "<如何启动此 MCP>",
      "args": [...]
    }
  }
}
EOF
```

tooling.md 第 6 节要写明本 feature 需要哪些 MCP,Hermes 据此生成 `.mcp.json`。

**STEP 3.2**: 同标准

**STEP 3.3 启动(交互模式)**:

```bash
# 交互模式,MCP 通过 .mcp.json 加载
HARNESS_ROOT=$HARNESS_ROOT \
FEATURE_ID=f<N> \
claude --settings $FDIR/.claude/settings.json \
  --mcp-config $FDIR/.mcp.json \
  --cwd $FDIR \
  <<< "$(cat $FDIR/context_snapshot.md)"
```

**STEP 3.4**: `session_type = "cc-interactive-mcp"`

---

### 3.C generator_mcp_direct(受限豁免)

Hermes 自己充当 Generator 代理。**但所有过程协议仍然适用**。

**STEP 3.1 建目录**(同标准 5 文件)**+ 两处关键不同**:

1. `context_snapshot.md` 标注路径为 `generator_mcp_direct`,说明本 feature 由 Hermes 代理执行
2. `session_id.txt` 直接写入 `hermes-proxy-<feature_id>`

**STEP 3.2 hook 部署(简化版)**:

```bash
# 仍复制 hook 脚本到 .claude/hooks/(供 Hermes 自检调用)
mkdir -p $FDIR/.claude/hooks
cp $HARNESS_ROOT/.claude-hooks-src/pre-edit-guard.sh $FDIR/.claude/hooks/
cp $HARNESS_ROOT/.claude-hooks-src/pre-bash-guard.sh $FDIR/.claude/hooks/
cp $HARNESS_ROOT/.claude-hooks-src/stop-guard.sh $FDIR/.claude/hooks/
chmod +x $FDIR/.claude/hooks/*.sh

# settings.json 写个标记,表示本 feature 走 mcp_direct 自检
cat > $FDIR/.claude/settings.json <<EOF
{
  "_self_audit_mode": "hermes_mcp_proxy",
  "_note": "Hermes 代理执行,每次写 feature 文件前手动调 pre-edit-guard.sh 自检"
}
EOF
```

**STEP 3.3 "启动"(Hermes 自身作为 Generator)**:

不调用 `claude` CLI。改为:

```bash
# 1. 写 session_id.txt
echo "hermes-proxy-f<N>" > $FDIR/session_id.txt

# 2. Hermes 设置身份切换
# .current_agent 字段:
#   role: "generator"
#   developer: "hermes-as-proxy"  ← 明确可审计
#   current_feature: "f<N>"
jq '.role="generator" | .developer="hermes-as-proxy" | .current_feature="f<N>"' \
  $HARNESS_ROOT/.harness/.current_agent > /tmp/ca && \
  mv /tmp/ca $HARNESS_ROOT/.harness/.current_agent
```

**STEP 3.4 状态**:

```json
// session_pool.active.f<N>
{
  "session_id": "hermes-proxy-f<N>",
  "session_type": "mcp_direct",
  "status": "running",
  "started_at": "<now>",
  "current_phase": 1
}
```

---

## 4. generator_mcp_direct 的 Hermes 自检责任

Hermes 代理执行时,**每次文件写入前**必须手动调 hook 自检:

### 4.1 写文件前

```bash
# 假设要写 $FDIR/generator_log.md
# 构造 PreToolUse hook 的 JSON 输入
HOOK_INPUT=$(jq -n --arg f "$FDIR/generator_log.md" \
  '{tool_name:"Write", tool_input:{file_path:$f}}')

# 调 pre-edit-guard.sh
echo "$HOOK_INPUT" | \
  HARNESS_ROOT=$HARNESS_ROOT FEATURE_ID=f<N> \
  bash $FDIR/.claude/hooks/pre-edit-guard.sh

# 非零退出 → 违规,停下报告用户
if [ $? -ne 0 ]; then
  echo "❌ 自检失败,违规操作"
  exit 1
fi
```

### 4.2 跑 Bash 命令前

```bash
HOOK_INPUT=$(jq -n --arg c "$YOUR_BASH_CMD" \
  '{tool_name:"Bash", tool_input:{command:$c}}')
echo "$HOOK_INPUT" | \
  HARNESS_ROOT=$HARNESS_ROOT FEATURE_ID=f<N> \
  bash $FDIR/.claude/hooks/pre-bash-guard.sh
```

### 4.3 feature 完成前

```bash
HARNESS_ROOT=$HARNESS_ROOT FEATURE_ID=f<N> SPRINT_ID=<sprint_id> \
  bash $FDIR/.claude/hooks/stop-guard.sh
```

过程协议不完整 stop-guard 会拦。

---

## 5. Phase 推进节奏(所有路径通用)

**四个 phase 对所有路径都必须走**。差别只在 generator_mcp_direct 下是 Hermes 自己切 phase,没有 CC session 的自然切点。

### 5.1 generator_cc / generator_cc_mcp 的 phase 节奏

由 CC 自己切(读 AGENTS.md 和 phase-workflow.md 后按规矩走),每切一 phase 写一条 eval_log + 更新 feature_list.

### 5.2 generator_mcp_direct 的 phase 节奏(明确给出)

Hermes 代理执行时,在以下 4 个时间点显式切 phase + 写 eval_log:

| Phase | 触发时机 | 必写 |
|---|---|---|
| 1 plan | 调用任何 MCP 工具**之前**,先拆出"要调几次 MCP、每次的目标" | eval_log + generator_log 的"phase=1 plan"段 |
| 2 implement | 实际执行 MCP 调用、汇总结果、写产出物 | eval_log + generator_log 的"phase=2 implement"段 + 产出物 |
| 3 verify | 产出物写完后,对照 acceptance **逐条**自检 | eval_log 必含 `acceptance_results`(见下方示例)|
| 4 deliver | git commit 产出物(或 MCP 返回的发布 ID) | eval_log + feature_list.features[N].status=completed + commit 字段 |

### 5.3 phase=3 verify 的 eval_log 强制 JSON 格式

```json
{
  "timestamp": "2026-04-21T10:04:00Z",
  "sprint_id": "sprint_20260421_5",
  "feature_id": "f001",
  "phase": 3,
  "event_type": "phase_evaluation",
  "result": "pass",
  "reason": "3 条 acceptance 逐条通过,证据见下方 acceptance_results",
  "acceptance_results": [
    {
      "id": "a1",
      "criteria": "收集 ≥ 5 篇来源,含官方文档 + 中文博客 + X/B 站",
      "status": "pass",
      "evidence": "sources.md 含 15 条,4 个方向覆盖"
    },
    {
      "id": "a2",
      "criteria": "每条素材含标题 + URL + 摘要 ≤ 200 字",
      "status": "pass",
      "evidence": "随机抽样 5 条,均合规"
    },
    {
      "id": "a3",
      "criteria": "产出文件路径 = research/sources.md",
      "status": "pass",
      "evidence": "test -f $HARNESS_ROOT/research/sources.md 返回 0"
    }
  ]
}
```

**`acceptance_results` 必须逐条对应 feature.acceptance 数组**。缺一条 → phase=3 不能判 pass。

---

## 6. Session Pool 状态机流转示例

以 feature f001 的生命周期为例:

### 6.1 启动前(STEP 2.5 校验前)

```json
// $HARNESS_ROOT/.harness/session_pool.json
{
  "max_concurrent": 2,
  "policy": "start_when_dependency_ready",
  "active": {}
}
```

### 6.2 STEP 3.4 启动后

```json
{
  "max_concurrent": 2,
  "policy": "start_when_dependency_ready",
  "active": {
    "f001": {
      "session_id": "hermes-proxy-f001",
      "session_type": "mcp_direct",
      "status": "running",
      "started_at": "2026-04-21T10:00:00Z",
      "current_phase": 1,
      "last_activity": "2026-04-21T10:00:00Z"
    }
  }
}
```

### 6.3 推进到 phase=2

```json
"f001": {
  "session_id": "hermes-proxy-f001",
  "session_type": "mcp_direct",
  "status": "running",
  "started_at": "2026-04-21T10:00:00Z",
  "current_phase": 2,                            // ← 2
  "last_activity": "2026-04-21T10:03:00Z"        // ← 刷新
}
```

### 6.4 等 checkpoint 用户回复时

```json
"f001": {
  ...
  "status": "waiting_human",                     // ← waiting
  "current_phase": 3,
  "last_activity": "2026-04-21T10:08:00Z"
}
```

### 6.5 完成 phase=4 deliver 后(feature 完成)

```json
// f001 从 active 字典移除
{
  "max_concurrent": 2,
  "policy": "start_when_dependency_ready",
  "active": {}              // f001 已移除,供下游 feature 占位
}
```

**不要**在 active 字段里保留 `status: "completed"` 的记录;移除是正确做法。feature 的最终状态看 `feature_list.features[].status`。

---

## 7. feature_list.json 完整结构示例(每个 feature 4 phase 走完后)

```json
{
  "version": "1.2",
  "sprint": "sprint_20260421_5",
  "pipeline_id": null,
  "tooling_locked": true,
  "updated_at": "2026-04-21T10:20:00Z",
  "updated_by": "hermes",
  "features": [
    {
      "id": "f001",
      "name": "调研素材收集",
      "title": "收集 Hermes + Claude Code + CCSwitch 安装相关内容",
      "status": "completed",
      "assignee": "hermes-as-proxy",
      "priority": "P0",
      "phase": 4,
      "next_phases": [
        {"phase": 1, "action": "plan", "done": true, "current": false},
        {"phase": 2, "action": "implement", "done": true, "current": false},
        {"phase": 3, "action": "verify", "done": true, "current": false},
        {"phase": 4, "action": "deliver", "done": true, "current": true}
      ],
      "execution_path": "generator_mcp_direct",
      "acceptance": [
        "收集 ≥ 5 篇来源...",
        "每条含标题 + URL + 摘要...",
        "产出文件路径 = research/sources.md"
      ],
      "verification_mode": "human",
      "depends_on": [],
      "sprint_id": "sprint_20260421_5",
      "created_at": "2026-04-21T09:49:00Z",
      "completed_at": "2026-04-21T09:55:00Z",
      "commit": "abc1234",
      "checkpoints": [
        {
          "id": "cp-f001-1",
          "phase": 3,
          "type": "gate",
          "blockers": [...],
          "artifacts": ["research/sources.md"],
          "status": "approved",
          "decision": "approved",
          "created_at": "2026-04-21T09:55:00Z",
          "responded_at": "2026-04-21T09:56:29Z"
        }
      ]
    }
  ],
  "blocked": []
}
```

`sprint_summary.json` 可以保留作为人类可读总结,但**不能替代** feature_list。

---

## 8. 禁止事项汇总

- ❌ generator_mcp_direct 走发布类 / 代码生成类 feature
- ❌ session_pool 自造字段(每个 feature 下建自己的 session_pool.json)
- ❌ feature_list.features 空数组但 sprint 已有 feature 完成
- ❌ `.current_agent` 冗余(只要 `.current_agent` 无扩展名)
- ❌ phase=3 eval_log 缺 `acceptance_results` 逐条记录
- ❌ 根目录平铺 schema / template / protocol / spec 文件(只能在子目录)
- ❌ shell 变量拼 JSON 时用单引号导致字面量进入(用 jq 或先 eval)
