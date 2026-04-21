# task-runner SKILL

你是 Hermes。本 skill 由 crontab 定期触发。每次触发做一件事:**扫 task 队列,如果有活且没活在跑,挑一个开始跑**。

---

## 入口约束

**所有路径都是相对的**。进入本 skill 时,你应该已经处于某个"pipeline 根目录"(后文称 `$PIPELINE_ROOT`,但不要硬编码绝对路径,用相对路径)。

```bash
# 本 skill 期望的工作目录布局(相对路径):
# tasks/pending/       ← 待跑 task(*.json)
# tasks/running/       ← 正在跑的 task(≤ 1 个文件)
# PROMPTS/             ← 原始 prompt 文件
# sprints/             ← sprint 运行时 + 完成后的 TASK.json 归档
# scripts/             ← 可选工具脚本
```

---

## 执行流程

### STEP A:守门(3 条前置检查)

```bash
# A.1 running/ 有文件 → 说明有 task 在跑,直接退出
if ls tasks/running/*.json 2>/dev/null | head -1 | grep -q .; then
  echo "有 task 在运行,本次跳过"
  exit 0
fi

# A.2 pending/ 空 → 没活可干,退出
PENDING_COUNT=$(ls tasks/pending/*.json 2>/dev/null | wc -l)
if [ "$PENDING_COUNT" -eq 0 ]; then
  echo "队列为空,本次跳过"
  exit 0
fi

# A.3 Hermes 自身状态检查:runtime_state.mode 必须是 idle
#     如果之前 sprint 没干净收尾,current_sprint 还挂着 → 不启新 task
# (这步取决于你当前是否有全局 runtime_state 文件,若没有可跳过)
```

### STEP B:选 task(按 priority + created_at)

```bash
# 从 pending/ 中按 priority 升序 + created_at 升序选最优先的
NEXT_TASK=$(ls tasks/pending/*.json | while read f; do
  PRIO=$(jq -r '.priority // 3' "$f")
  CTIME=$(jq -r '.created_at // ""' "$f")
  echo "$PRIO|$CTIME|$f"
done | sort -t'|' -k1,1n -k2,2 | head -1 | awk -F'|' '{print $3}')

TASK_ID=$(basename "$NEXT_TASK" .json)
echo "选中 task: $TASK_ID"
```

### STEP C:原子移到 running/

```bash
# 原子操作 mv,避免并发(crontab 虽然不会并发触发,但保险起见)
mv "tasks/pending/$TASK_ID.json" "tasks/running/$TASK_ID.json"
TASK_FILE="tasks/running/$TASK_ID.json"
```

### STEP D:解析 task,决定执行模式

```bash
# 读 task 的关键字段
MODE=$(jq -r '.mode // "interactive"' "$TASK_FILE")
PROMPT_FILE=$(jq -r '.prompt_file' "$TASK_FILE")
PIPELINE_HINT=$(jq -r '.pipeline_hint // ""' "$TASK_FILE")
AUTO_APPROVE=$(jq -r '.auto_approve_all // false' "$TASK_FILE")

# 更新 task 状态
jq --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   '.status = "running" | .started_at = $t' \
   "$TASK_FILE" > "$TASK_FILE.tmp" && mv "$TASK_FILE.tmp" "$TASK_FILE"
```

### STEP E:加载 superAgent 主 skill,带 YOLO 参数启动

把 task 的 prompt 文件内容读出来,加上 YOLO 模式提示(如果是 yolo),作为输入进入 superAgent SKILL.md 的完整流程。

```
# 伪代码:
PROMPT_CONTENT = read(PROMPT_FILE)

if MODE == "yolo":
    EXTENDED_PROMPT = PROMPT_CONTENT + """

---

## 🟢 YOLO 模式激活

用户已通过 task.auto_approve_all=true 明确授权本 task 全程无人值守。

按 superAgent SKILL.md 的"§ YOLO 模式行为"章节执行:
- 所有 gate checkpoint 自动 approved(写 eval_log decision=auto_approved_yolo_task)
- 包括 external_irreversible(用户签 task 时就等于签了所有发布操作)
- 遇到无法决策时(acceptance 失败 / 环境探测异常 / 连续 retry 上限),
  立即标 task failed 退出,不要编造通过
- STEP 1.1 不问根目录,默认使用相对路径 "sprints/"
"""
else:
    EXTENDED_PROMPT = PROMPT_CONTENT

# 进入 superAgent SKILL.md,按 STEP 0 → STEP 5 执行
execute_skill("superAgent/SKILL.md", input=EXTENDED_PROMPT, task_file=TASK_FILE)
```

### STEP F:sprint 完成后归档 task 文件

superAgent SKILL.md 跑完(STEP 5 sprint-finalizer 完成),Hermes 回到 idle。
此时本 skill 接管,做归档:

```bash
# 取出 sprint_id(Hermes 应该在 task 文件里填了这个字段)
SPRINT_ID=$(jq -r '.sprint_id' "$TASK_FILE")

if [ -n "$SPRINT_ID" ] && [ -d "sprints/$SPRINT_ID" ]; then
  # task 完成,挪进 sprint 结果目录作为完成凭证
  mv "$TASK_FILE" "sprints/$SPRINT_ID/TASK.json"
  echo "✅ task $TASK_ID 归档到 sprints/$SPRINT_ID/TASK.json"
else
  # sprint 未产生或 Hermes 异常退出 → 留在 running/,等人工检查
  echo "⚠️  sprint_id 异常($SPRINT_ID),task 文件留在 running/ 等人工介入"
fi
```

---

## 失败处理

### 场景 1:superAgent SKILL 执行中途 Hermes Reset 退出

- 如果 Hermes 进程被信号杀掉(crontab 超时 / 人工 kill),task 文件留在 `tasks/running/`
- **下一次 crontab 触发时,STEP A.1 会检测到 running/ 非空,直接跳过**
- 人工介入:检查 sprint 状态,决定 `mv running/ → pending/`(重跑)还是 `mv running/ → tasks/failed/`(归档失败,需要手动建 tasks/failed/ 目录)

### 场景 2:YOLO task 遇到无法决策

- Hermes 在 superAgent SKILL.md 里应主动把 task 标成 failed(见 SKILL.md "§ YOLO 模式行为")
- 退出后,STEP F 检查 `.status="failed"`,挪到 `tasks/failed/`(按需创建):

```bash
FINAL_STATUS=$(jq -r '.status' "$TASK_FILE")
if [ "$FINAL_STATUS" == "failed" ]; then
  mkdir -p tasks/failed
  mv "$TASK_FILE" "tasks/failed/"
  echo "❌ task $TASK_ID 失败,归档到 tasks/failed/"
fi
```

### 场景 3:prompt 文件不存在

- STEP D 读 PROMPT_FILE 失败 → 标 task failed,移到 tasks/failed/

---

## 不要做的事

- ❌ 不要在 running/ 有文件时启新 task(违反单 sprint 独占 Z8)
- ❌ 不要自动重试 failed task(等用户看,人类掌舵)
- ❌ 不要用绝对路径(本 skill 在任何机器上都要能跑)
- ❌ 不要修改 PROMPTS/ 里的 prompt 文件
- ❌ 不要跳过 superAgent SKILL.md 流程(STEP E 必须严格走)

---

## 与 superAgent SKILL.md 的关系

本 skill 是 **superAgent SKILL.md 的调度层**,不替代。

- task-runner 只负责:选任务 → 启动 → 归档
- superAgent 负责:实际的 Planner / Generator / Evaluator 执行

进入 STEP E 后,控制权完全交给 superAgent SKILL.md。
