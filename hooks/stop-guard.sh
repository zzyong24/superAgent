#!/usr/bin/env bash
# superAgent hook: Stop
# 作用:强制 phase 完整性检查,过程协议不完整禁止 session 结束
# 触发:Claude Code 准备结束 session 前
# 返回:exit 0 放行结束,exit 2 阻断(Claude Code 会继续工作)

set -u

HARNESS_ROOT="${HARNESS_ROOT:-$(pwd)}"
FEATURE_ID="${FEATURE_ID:-}"
SPRINT_ID="${SPRINT_ID:-}"

log() {
  mkdir -p "$HARNESS_ROOT/.harness/logs"
  echo "[$(date -u +%FT%TZ)] [stop] $*" >> "$HARNESS_ROOT/.harness/logs/hook.log"
}

block() {
  local reason="$1"
  log "BLOCK stop: $reason"
  cat >&2 <<EOF
❌ superAgent hook blocked: session 不能结束 - $reason

在你结束前,必须完成当前 phase 的过程协议:
1. 在 .harness/features/$FEATURE_ID/generator_log.md 追加当前 phase 的段落
   (模板见 templates/generator_log.template.md)
2. 在 .harness/eval_log.jsonl 追加一条 event_type=phase_evaluation
   (必含 feature_id / phase / result / reason,reason 禁止空 / 禁止"ok")
3. 更新 .harness/feature_list.json 中本 feature 的 phase 字段和 next_phases[i].done

若是 Reset 场景(token>70% / retry>=2 / >2h),必须先写 handoff.md:
- .harness/features/$FEATURE_ID/handoff.md
- 基于 templates/claude_code_handoff.template.md
- 然后这个 hook 会放行

若是正常 phase 结束,以上 3 步写完才能结束。
EOF
  exit 2
}

if [[ -z "$FEATURE_ID" ]]; then
  log "FEATURE_ID 未设置,跳过检查"
  exit 0
fi

FEATURE_DIR="$HARNESS_ROOT/.harness/features/$FEATURE_ID"
GEN_LOG="$FEATURE_DIR/generator_log.md"
HANDOFF="$FEATURE_DIR/handoff.md"
FEATURE_LIST="$HARNESS_ROOT/.harness/feature_list.json"
EVAL_LOG="$HARNESS_ROOT/.harness/eval_log.jsonl"

# --- 例外:handoff 场景(Reset)---
# 如果 handoff.md 非空(>10 字节)且最近 5 分钟修改过,视为 Reset,放行
if [[ -s "$HANDOFF" ]]; then
  HANDOFF_SIZE=$(wc -c < "$HANDOFF" | tr -d ' ')
  HANDOFF_MTIME=$(stat -f %m "$HANDOFF" 2>/dev/null || stat -c %Y "$HANDOFF" 2>/dev/null || echo 0)
  NOW=$(date +%s)
  AGE=$((NOW - HANDOFF_MTIME))
  if [[ "$HANDOFF_SIZE" -gt 50 && "$AGE" -lt 300 ]]; then
    log "Reset 场景(handoff.md 新鲜),放行"
    cat >&2 <<'EOF'
ℹ️  检测到 handoff.md 新写入,视为 Reset 场景,放行 session 结束。
Hermes 会基于 handoff.md 启动同 feature 的新 session。
EOF
    exit 0
  fi
fi

# --- 读当前 phase ---
CURRENT_PHASE=""
if [[ -f "$FEATURE_LIST" ]]; then
  CURRENT_PHASE=$(jq -r --arg fid "$FEATURE_ID" '.features[] | select(.id==$fid) | .phase' "$FEATURE_LIST" 2>/dev/null)
fi

if [[ -z "$CURRENT_PHASE" || "$CURRENT_PHASE" == "null" ]]; then
  log "无法从 feature_list 读到 current_phase,放行(可能是 feature 未启动或已完成)"
  exit 0
fi

log "check phase=$CURRENT_PHASE feature=$FEATURE_ID"

# --- 检查 1:generator_log 含当前 phase 段落 ---
if [[ ! -f "$GEN_LOG" ]]; then
  block "generator_log.md 不存在"
fi

if ! grep -qE "^##.*phase[= ]$CURRENT_PHASE" "$GEN_LOG"; then
  block "generator_log.md 缺 phase=$CURRENT_PHASE 段落"
fi

# --- 检查 2:phase 段落内容非空(至少 200 字符,排除只有标题的情况)---
# 提取当前 phase 段落
PHASE_CONTENT=$(awk -v phase="$CURRENT_PHASE" '
  /^## / {
    if (match($0, "phase[= ]" phase)) { in_section=1; next }
    else { in_section=0 }
  }
  in_section { print }
' "$GEN_LOG")

CONTENT_LEN=$(echo -n "$PHASE_CONTENT" | wc -c | tr -d ' ')
if [[ "$CONTENT_LEN" -lt 100 ]]; then
  block "generator_log.md 的 phase=$CURRENT_PHASE 段落内容过短($CONTENT_LEN 字符 < 100),记录不完整"
fi

# --- 检查 3:eval_log 含当前 phase 的 phase_evaluation 条目 ---
if [[ ! -f "$EVAL_LOG" ]]; then
  block "eval_log.jsonl 不存在"
fi

LAST_EVAL=$(grep "\"feature_id\":\"$FEATURE_ID\"" "$EVAL_LOG" 2>/dev/null | \
  grep "\"phase\":$CURRENT_PHASE" | \
  grep "\"event_type\":\"phase_evaluation\"" | \
  tail -1)

if [[ -z "$LAST_EVAL" ]]; then
  block "eval_log.jsonl 缺 feature=$FEATURE_ID phase=$CURRENT_PHASE 的 phase_evaluation 记录"
fi

# --- 检查 4:eval_log 最后一条 reason 非空且不是敷衍词 ---
REASON=$(echo "$LAST_EVAL" | jq -r '.reason // empty')
if [[ -z "$REASON" || "$REASON" == "null" ]]; then
  block "eval_log 最后一条 reason 字段为空,必须填具体判断理由"
fi

# 敷衍词黑名单
LAZY_PATTERNS=("^ok$" "^OK$" "^done$" "^完成$" "^通过$" "^pass$" "^看起来不错" "^没问题$")
for pattern in "${LAZY_PATTERNS[@]}"; do
  if echo "$REASON" | grep -qE "$pattern"; then
    block "eval_log reason 字段过于敷衍('$REASON'),必须写具体证据(对照 acceptance 说明)"
  fi
done

# reason 长度
REASON_LEN=$(echo -n "$REASON" | wc -c | tr -d ' ')
if [[ "$REASON_LEN" -lt 20 ]]; then
  block "eval_log reason 过短($REASON_LEN 字符 < 20),补充具体判断依据"
fi

# --- 检查 5:feature_list 的 next_phases 已更新 ---
PHASE_DONE=$(jq -r --arg fid "$FEATURE_ID" --argjson p "$CURRENT_PHASE" '
  .features[] | select(.id==$fid) | .next_phases[] | select(.phase==$p) | .done
' "$FEATURE_LIST" 2>/dev/null)

if [[ "$PHASE_DONE" != "true" ]]; then
  block "feature_list.json 中 feature=$FEATURE_ID 的 next_phases[phase=$CURRENT_PHASE].done 未置 true"
fi

# --- 全部通过 ---
log "PASS feature=$FEATURE_ID phase=$CURRENT_PHASE"
cat >&2 <<EOF
✓ superAgent hook: phase=$CURRENT_PHASE 过程协议完整,session 可结束。
Hermes 会读取 eval_log 最后一条进行判决。
EOF
exit 0
