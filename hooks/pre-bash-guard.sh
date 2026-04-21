#!/usr/bin/env bash
# superAgent hook: PreToolUse (Bash)
# 作用:拦截危险命令
# 触发:Claude Code 调用 Bash 前
# 返回:exit 0 放行,exit 2 阻断

set -u

HARNESS_ROOT="${HARNESS_ROOT:-$(pwd)}"
FEATURE_ID="${FEATURE_ID:-}"

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

log() {
  mkdir -p "$HARNESS_ROOT/.harness/logs"
  echo "[$(date -u +%FT%TZ)] [pre-bash] $*" >> "$HARNESS_ROOT/.harness/logs/hook.log"
}

block() {
  local reason="$1"
  log "BLOCK: $reason | cmd=$CMD"
  cat >&2 <<EOF
❌ superAgent hook blocked: $reason

Command: $CMD

此命令会造成不可逆后果或绕过协作协议,已拦截。
若确实需要执行:
- 写入 tooling.md 的"运行时新增"章节说明理由
- 在 eval_log 追加 event_type=retry,reason 说明
- 让 Hermes 走 gate checkpoint 确认
EOF
  exit 2
}

if [[ -z "$CMD" ]]; then
  log "cmd 为空,放行"
  exit 0
fi

log "check cmd=$CMD"

# --- 危险命令黑名单 ---
# 格式:regex|说明
BLOCKED_PATTERNS=(
  "git push.*--force|git force push 风险,禁止直接使用"
  "git push.*-f( |$|\")|git force push 风险"
  "git reset --hard|git reset --hard 会丢失工作,谨慎(如需执行请由 Hermes 确认)"
  "git add -A|用明确的文件名 git add <file>,避免误提交敏感文件"
  "git add \.( |$)|用明确的文件名 git add <file>"
  "git commit.*--amend|禁止 amend,创建新 commit"
  "git checkout \.|git checkout . 会覆盖所有工作树,禁止"
  "git clean -f|git clean -f 会删除未追踪文件,禁止"
  "git branch -D|强制删除 branch 需要 Hermes 确认"
  "(^| )rm -rf( |$)|rm -rf 极度危险,禁止直接使用"
  "(^| )sudo( |$)|sudo 需由 tooling.md 明确授权"
  "(^| )chmod 777|chmod 777 不安全,禁止"
  ":\(\)\{ :\|:& \};:|Fork bomb 禁止"
  "dd if=|dd 命令风险高,禁止"
  "mkfs\.|格式化命令禁止"
  "> /dev/sda|直写磁盘禁止"
)

for item in "${BLOCKED_PATTERNS[@]}"; do
  pattern="${item%%|*}"
  reason="${item#*|}"
  if echo "$CMD" | grep -qE "$pattern"; then
    block "$reason"
  fi
done

# --- 生产环境保护(tooling.md 授权列表)---
# 读 tooling.md 的"## 4. 禁止清单"和"## 5. 全局约束",看是否明确禁止当前命令
# 这里简化:检测常见生产域名 / IP
PROD_PATTERNS=(
  "ssh.*@prod"
  "ssh.*@production"
  "kubectl.*--context.*prod"
  "aws.*--profile prod"
)

for pattern in "${PROD_PATTERNS[@]}"; do
  if echo "$CMD" | grep -qE "$pattern"; then
    block "疑似生产环境操作,需 tooling.md 明确授权 + gate checkpoint"
  fi
done

# --- 警告类命令(不拦但记录)---
WARN_PATTERNS=(
  "curl.*-X DELETE"
  "curl.*PUT"
  "npm publish"
  "pip upload"
  "docker push"
)

for pattern in "${WARN_PATTERNS[@]}"; do
  if echo "$CMD" | grep -qE "$pattern"; then
    log "WARN: 高风险命令 $CMD(未拦截,但记录)"
    cat >&2 <<EOF
⚠️  高风险命令提醒:$CMD
这可能是 external_irreversible 操作。
若是:请确保 feature.checkpoints 有 external_irreversible 标记的 gate。
未拦截,但已记录。
EOF
  fi
done

log "PASS"
exit 0
