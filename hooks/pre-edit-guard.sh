#!/usr/bin/env bash
# superAgent hook: PreToolUse (Edit / Write)
# 作用:硬拦截 Generator 修改只读文件 / 其他 feature 目录
# 触发:Claude Code 调用 Edit / Write / NotebookEdit 前
# 返回:exit 0 放行,exit 2 阻断

set -u

HARNESS_ROOT="${HARNESS_ROOT:-$(pwd)}"
FEATURE_ID="${FEATURE_ID:-}"

# Claude Code 通过 stdin 传入 JSON,含 tool_input.file_path
INPUT=$(cat)
TARGET=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')

log() {
  mkdir -p "$HARNESS_ROOT/.harness/logs"
  echo "[$(date -u +%FT%TZ)] [pre-edit] $*" >> "$HARNESS_ROOT/.harness/logs/hook.log"
}

block() {
  local reason="$1"
  log "BLOCK: $reason | target=$TARGET"
  # 输出给 Claude Code 看(exit 2 时 stderr 进入上下文)
  cat >&2 <<EOF
❌ superAgent hook blocked: $reason

Target: $TARGET

若你认为此操作应允许,请:
1. 检查是否误操作(大多数情况是越权)
2. 若确需更改只读文件,找 Hermes(Planner)授权
3. 若是 tooling.md 运行时新增,先追加到"## 6. 运行时新增"章节而不是改正文
EOF
  exit 2
}

if [[ -z "$TARGET" ]]; then
  log "target 为空,放行"
  exit 0
fi

# 规范化路径(相对 HARNESS_ROOT)
REL_PATH="${TARGET#$HARNESS_ROOT/}"

log "check target=$TARGET rel=$REL_PATH feature=$FEATURE_ID"

# --- 规则 1:只读目录 ---
READONLY_DIRS=(
  "schemas/"
  "templates/"
  "spec/"
  "protocols/"
  "sub-skills/"
)

for dir in "${READONLY_DIRS[@]}"; do
  if [[ "$REL_PATH" == "$dir"* ]]; then
    block "只读目录禁止修改(本目录由 skill 维护)"
  fi
done

# --- 规则 2:只读文件 ---
READONLY_FILES=(
  "SKILL.md"
  "README.md"
  ".harness/runtime_state.json"
  ".harness/hermes_handoff.md"
  ".harness/hermes_context_state.json"
  ".harness/session_pool.json"
  ".harness/.current_agent"
)

for file in "${READONLY_FILES[@]}"; do
  if [[ "$REL_PATH" == "$file" ]]; then
    block "只读文件禁止 Generator 修改(由 Hermes 维护)"
  fi
done

# --- 规则 3:sprint_contract 正文禁止改(tooling.md 除外,另有规则)---
if [[ "$REL_PATH" == .harness/sprint_contracts/*/contract.json ]]; then
  block "sprint_contract 由 Hermes 维护,Generator 禁止修改"
fi

# --- 规则 4:tooling.md 禁止整体 Edit(只能通过 append 脚本到"运行时新增")---
if [[ "$REL_PATH" == .harness/sprint_contracts/*/tooling.md ]]; then
  # Edit tool 的 old_string 如果不是"## 6. 运行时新增"章节内容,直接拦
  OLD_STRING=$(echo "$INPUT" | jq -r '.tool_input.old_string // empty')
  # 简单策略:tooling.md 全面禁止 Edit;追加用 Bash `echo >> tooling.md`
  # 这要求 Generator 用 Bash 脚本而不是 Edit tool
  # 若 Claude Code 用 Write 完全覆盖也要拦
  TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
  if [[ "$TOOL_NAME" == "Write" ]]; then
    block "tooling.md 禁止 Write 覆盖。如需追加,用 Bash: echo '...' >> tooling.md 追加到运行时新增章节"
  fi
  # Edit tool 允许,但 old_string 必须在"## 6. 运行时新增"之后
  if [[ -n "$OLD_STRING" ]]; then
    TOOLING_FILE="$HARNESS_ROOT/$REL_PATH"
    # 找"## 6. 运行时新增"的行号
    SECTION_LINE=$(grep -n "^## 6\. 运行时新增" "$TOOLING_FILE" 2>/dev/null | head -1 | cut -d: -f1)
    if [[ -z "$SECTION_LINE" ]]; then
      block "tooling.md 缺'## 6. 运行时新增'章节,请由 Hermes 先补齐"
    fi
    # 检查 old_string 是否出现在该章节之后
    OLD_LINE=$(grep -n -F "$OLD_STRING" "$TOOLING_FILE" 2>/dev/null | head -1 | cut -d: -f1)
    if [[ -n "$OLD_LINE" && "$OLD_LINE" -lt "$SECTION_LINE" ]]; then
      block "tooling.md 仅允许修改'## 6. 运行时新增'章节之后的内容"
    fi
  fi
fi

# --- 规则 5:其他 feature 目录 ---
if [[ "$REL_PATH" == .harness/features/f* ]]; then
  # 提取 feature_id
  TARGET_FEATURE=$(echo "$REL_PATH" | sed -E 's|^\.harness/features/(f[^/]+)/.*|\1|')
  if [[ -n "$FEATURE_ID" && "$TARGET_FEATURE" != "$FEATURE_ID" ]]; then
    block "禁止操作其他 feature 的目录(当前 feature=$FEATURE_ID, 目标 feature=$TARGET_FEATURE)"
  fi
fi

# --- 规则 6:eval_log.jsonl 只允许 append(不允许 Edit 覆盖历史)---
if [[ "$REL_PATH" == .harness/eval_log.jsonl ]]; then
  TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
  if [[ "$TOOL_NAME" == "Write" || "$TOOL_NAME" == "Edit" ]]; then
    block "eval_log.jsonl 是 append-only,用 Bash: echo '{...}' >> eval_log.jsonl 追加"
  fi
fi

# --- 规则 7:generator_log.md 历史段落只读(只能 append 新段落)---
# 检查:Edit 时 old_string 不能是历史 phase 段落的内容
if [[ "$REL_PATH" == .harness/features/*/generator_log.md ]]; then
  TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
  # Write 覆盖禁止
  if [[ "$TOOL_NAME" == "Write" ]]; then
    block "generator_log.md 禁止整体覆盖,用 Bash: cat >> generator_log.md <<EOF 追加新 phase 段落"
  fi
fi

log "PASS $REL_PATH"
exit 0
