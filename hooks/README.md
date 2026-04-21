# superAgent Hooks

> 4 个 P0 级硬约束 hook。由 Hermes 在启动 Claude Code feature session 前部署到 feature 目录下。

---

## 文件清单

| 文件 | Hook 类型 | 作用 | 阻断能力 |
|---|---|---|---|
| `session-start.sh` | SessionStart | 强制注入 AGENTS.md + tooling.md + 过程协议到 Claude Code 初始上下文 | 不阻断(仅注入) |
| `pre-edit-guard.sh` | PreToolUse (Edit/Write/NotebookEdit) | 拦截修改只读目录 / 其他 feature / eval_log 覆盖 / tooling 正文 | ✅ 硬阻断 |
| `pre-bash-guard.sh` | PreToolUse (Bash) | 拦截危险命令(force push / rm -rf / sudo / 生产环境) | ✅ 硬阻断 |
| `stop-guard.sh` | Stop | 未完成过程协议禁止结束 session(generator_log + eval_log + feature_list 三件套)| ✅ 硬阻断 |
| `settings.json.template` | — | Claude Code hook 配置模板,由 Hermes 填 env 后部署 | — |

---

## 部署方式(由 Hermes 在 feature session 启动时执行)

```bash
FEATURE_DIR=.harness/features/<feature_id>
mkdir -p $FEATURE_DIR/.claude/hooks

# 1. 复制 hook 脚本
cp hooks/session-start.sh $FEATURE_DIR/.claude/hooks/
cp hooks/pre-edit-guard.sh $FEATURE_DIR/.claude/hooks/
cp hooks/pre-bash-guard.sh $FEATURE_DIR/.claude/hooks/
cp hooks/stop-guard.sh $FEATURE_DIR/.claude/hooks/
chmod +x $FEATURE_DIR/.claude/hooks/*.sh

# 2. 渲染 settings.json(注入 HARNESS_ROOT 绝对路径)
sed "s|\${HARNESS_ROOT}|$HARNESS_ROOT|g" hooks/settings.json.template \
  > $FEATURE_DIR/.claude/settings.json

# 3. 启动 Claude Code session,带上环境变量
HARNESS_ROOT=$HARNESS_ROOT \
FEATURE_ID=<feature_id> \
SPRINT_ID=<sprint_id> \
claude-code --cwd $HARNESS_ROOT
```

---

## Hook 拦截时 Generator 看到什么

所有 hook 阻断时:
1. Claude Code 进程收到 exit code 2
2. hook 的 stderr 输出作为"tool error"反馈给 Claude Code 的上下文
3. Generator 看到 `❌ superAgent hook blocked: <reason>` 提示
4. Generator 知道该停下来,不是重试

---

## 例外机制

### Reset 场景绕过 Stop 检查

如果 `handoff.md` 在最近 5 分钟内被新写入(> 50 字节),Stop hook 放行。
这允许 Generator 在触达 Reset 阈值时,写完 handoff 就正常退出。

### tooling.md 运行时新增

`pre-edit-guard.sh` 对 `tooling.md` 的 Edit 操作,只允许修改"## 6. 运行时新增"章节之后的内容。
Write 整体覆盖一律拒绝。
最简单的合规做法:用 Bash `echo '- YYYY-MM-DD ...' >> tooling.md` 追加。

---

## 日志

所有 hook 动作写入 `.harness/logs/hook.log`,格式:

```
[2026-04-21T00:30:00Z] [session-start] SessionStart feature=f001 sprint=sprint_20260421_1
[2026-04-21T00:31:00Z] [pre-edit] check target=... rel=... feature=f001
[2026-04-21T00:31:00Z] [pre-edit] PASS ...
[2026-04-21T00:35:00Z] [pre-bash] BLOCK: git force push 风险 | cmd=git push --force
[2026-04-21T01:00:00Z] [stop] PASS feature=f001 phase=2
```

Hermes 在 Evaluator 阶段可读此日志,辅助判断 Generator 是否频繁触发 block。

---

## 添加新规则的原则

- ❌ 不在 hook 里做 LLM 级别的判断(让 Hermes 做)
- ✅ 只拦"绝对不该做的事",不拦"建议不做的"
- ✅ 拦截信息必须清晰告诉 Generator 怎么绕(合法路径)
- ✅ 规则写成 array,后续可以在 settings.json 里通过 env 配置扩展
- ✅ 每个规则在 hook.log 留痕,用于事后审计

---

## 已覆盖的约束(对照 AGENTS.md)

| AGENTS.md 约束 | Hook 覆盖 |
|---|---|
| 不修改 schemas/ / templates/ / spec/ / protocols/ | ✅ pre-edit-guard 规则 1 |
| 不操作其他 feature 目录 | ✅ pre-edit-guard 规则 5 |
| 不修改 tooling.md 正文(只能 append 运行时新增)| ✅ pre-edit-guard 规则 4 |
| eval_log append-only | ✅ pre-edit-guard 规则 6 |
| generator_log 不能整体覆盖 | ✅ pre-edit-guard 规则 7 |
| 不 git push --force / amend / add -A | ✅ pre-bash-guard |
| 不 sudo / rm -rf | ✅ pre-bash-guard |
| 结束前写完过程协议 | ✅ stop-guard |
| 启动必读 AGENTS.md + tooling.md | ✅ session-start |
| eval_log reason 非空 + 非敷衍 | ✅ stop-guard 检查 4 |
| feature_list phase 更新 | ✅ stop-guard 检查 5 |

### 未覆盖的(只能靠 Hermes 在 Evaluator 判)

- 不自己定义 acceptance(只能看 Generator 输出文字判断)
- 不跳 phase(phase 字段更新本身是 Generator 主动做的,如果恶意跳 Hermes 会在 Evaluator 判 fail)
- 工具选型是否符合 tooling.md(Hermes 读 generator_log 判断)
