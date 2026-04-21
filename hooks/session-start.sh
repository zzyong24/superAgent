#!/usr/bin/env bash
# superAgent hook: SessionStart
# 作用:强制注入必读文件到 Claude Code 上下文
# 触发:Claude Code session 启动时
# 返回:stdout 作为 additional context 注入;退出码永远 0(SessionStart 不阻断)

set -u

# HARNESS_ROOT 由启动时 env 传入,指向 ~/Workbase/pipeline/sprint_<id>/
HARNESS_ROOT="${HARNESS_ROOT:-$(pwd)}"
FEATURE_ID="${FEATURE_ID:-}"
SPRINT_ID="${SPRINT_ID:-}"

log() {
  mkdir -p "$HARNESS_ROOT/.harness/logs"
  echo "[$(date -u +%FT%TZ)] [session-start] $*" >> "$HARNESS_ROOT/.harness/logs/hook.log"
}

log "SessionStart feature=$FEATURE_ID sprint=$SPRINT_ID"

if [[ -z "$FEATURE_ID" ]]; then
  echo "⚠️  FEATURE_ID 环境变量未设置,无法加载 feature 上下文"
  log "FEATURE_ID 缺失,SessionStart 退出"
  exit 0
fi

FEATURE_DIR="$HARNESS_ROOT/.harness/features/$FEATURE_ID"

if [[ ! -d "$FEATURE_DIR" ]]; then
  echo "⚠️  feature 目录不存在: $FEATURE_DIR"
  log "feature 目录缺失"
  exit 0
fi

cat <<EOF
===== superAgent 强制注入:feature 上下文 =====
(本段由 SessionStart hook 自动注入,请你作为 Generator 完整遵守)

Feature: $FEATURE_ID
Sprint: $SPRINT_ID
Harness Root: $HARNESS_ROOT

---- AGENTS.md(Generator 约束,硬约束)----
EOF

if [[ -f "$FEATURE_DIR/AGENTS.md" ]]; then
  cat "$FEATURE_DIR/AGENTS.md"
else
  cat "$HARNESS_ROOT/spec/AGENTS.md" 2>/dev/null || echo "⚠️  AGENTS.md 缺失"
fi

cat <<'EOF'

---- context_snapshot.md(本 feature 初始化上下文)----
EOF

cat "$FEATURE_DIR/context_snapshot.md" 2>/dev/null || echo "⚠️  context_snapshot.md 缺失"

cat <<'EOF'

---- tooling.md(sprint 级选型,不可推翻)----
EOF

cat "$HARNESS_ROOT/.harness/sprint_contracts/$SPRINT_ID/tooling.md" 2>/dev/null || echo "⚠️  tooling.md 缺失"

cat <<'EOF'

---- 过程协议(每 phase 必须落盘的产物)----
EOF

cat "$HARNESS_ROOT/protocols/process-protocol.md" 2>/dev/null || echo "⚠️  process-protocol.md 缺失"

cat <<'EOF'

---- Hook 硬约束提醒 ----
以下动作会被 PreToolUse/Stop hook 直接拦截,你做不到:
- Edit schemas/ / templates/ / spec/ / protocols/ 下任何文件
- Edit 其他 feature 的目录
- git push --force / git add -A / sudo / rm -rf 等危险命令
- 未完成过程协议(generator_log + eval_log + feature_list phase 更新)前结束 session

若看到 "❌ superAgent hook blocked" 提示,停下来检查你是不是越权了。
===== 注入结束 =====
EOF

log "SessionStart 注入完成"
exit 0
