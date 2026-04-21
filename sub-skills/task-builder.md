# task-builder SKILL

你是 Hermes。用户调用本 skill 是为了**新建一个 task**(扔进 pipeline/tasks/pending/ 队列,等 crontab 捡起来跑)。

---

## 入口约束

- 所有路径都是相对的(`tasks/`, `PROMPTS/`, `sprints/`)
- 你处于 pipeline 根目录

---

## 执行流程

### STEP 1:提问式收集需求

**不要一口气问完,逐题问,用户回一题问下一题**。按如下顺序:

#### Q1. 任务主题是什么?

开放问答。例如用户答:"做一个 AI Agent 部署教程"。
内部记为 `$TASK_THEME`。

#### Q2. 交付物是什么?(多选)

推用户回编号(a/b/c/...),可多选:

```
a. HTML PPT(发视频用)
b. AI 配音(配合 PPT,MiniMax TTS 男声)
c. 飞书文档 Markdown(给人 + 给 agent 读)
d. 代码 / 脚本 / 工具
e. 调研报告 / 信息汇总
f. 其他(请描述)
```

#### Q3. 内容范围 / 具体要求?

开放问答。让用户讲:
- 这期内容想覆盖哪些范围
- 有没有特定的受众 / 风格 / 禁忌
- 是否引用特定素材来源(X / 小红书 / B站 / 官方文档)
- 有没有环境限制(比如"没有 Windows 电脑")

#### Q4. 模式:interactive 还是 yolo?

```
a. interactive — 我要全程参与,遇到决策点请问我
b. yolo — 我不想被打扰,全程跑到完,所有 checkpoint 自动通过
   (包括飞书发布这类不可逆操作也自动做,用户已授权)
```

#### Q5. 是否基于已有管线?(可选)

```
a. 从零规划(走完整 phase=0 tooling)
b. 基于已有管线 <如 tutorial-content>(如果有)
c. 我不知道,你判断
```

扫 `~/.hermes/pipelines/` 看有哪些管线可选(相对路径:`../../.hermes/pipelines/` 或按 Hermes 自己知道的位置)。

#### Q6. 优先级?

```
a. P1 紧急(1)
b. P2 高(2)
c. P3 正常(3,默认)
d. P4 低(4)
e. P5 有空再做(5)
```

### STEP 2:生成 prompt 文件

基于用户回答,合成一份完整的 prompt,写入 `PROMPTS/<slug>.md`。

**slug 规则**:从 Q1 主题生成 kebab-case 英文短名,如 `agent-deployment-tutorial`。

**prompt 结构参考**(本 skill 内置的模板,不是复制别人的):

```markdown
加载 superAgent/SKILL.md,严格按 STEP 0 → STEP 5 执行。

---

## 任务

<Q1 主题的自然扩展>

### 核心理念(如果用户 Q3 提到了理念)
<Q3 里提炼的理念,引用呈现>

---

## 交付物

<根据 Q2 生成,每个交付物写明受众 + 要求>

### 1. <交付物名称>
**目标受众**:
**要求**:

---

## 内容范围 / 素材

<Q3 里的细节>

---

## 我的工作方式

<如果 Q4 = interactive>
我只做两件事:**检查 + 说想要什么**。
- 决策点请推 gate checkpoint 问我
- 所有细节执行由 Claude Code feature session 完成

<如果 Q4 = yolo>
🟢 本 task 已标记 yolo 模式。
- 所有 gate 自动 approved,不要推给我
- 包括飞书发布等 external_irreversible 也自动做(我已授权)
- 遇到无法决策时立即标 failed 退出,不要编造通过

---

## 环境约定

- sprint 根目录:`sprints/`(相对路径)
- Claude Code CLI:STEP 0.5 探测后用探测到的路径
- 路径全部用相对路径,不要硬编码绝对路径

---

## 启动

<interactive 版本>
先跑 STEP 0.5 探测,再问我根目录,然后进 phase=0 tooling。

<yolo 版本>
YOLO 模式激活,直接:
1. STEP 0.5 探测(失败则 task=failed 退出)
2. 默认根目录 sprints/,不问
3. phase=0 tooling 按 task.pipeline_hint 自动生成(或从零)
4. 所有 gate 自动过
5. sprint 完成自动 finalize,管线沉淀按规则判
```

### STEP 3:生成 task JSON 文件

```bash
# 生成 task id(今天日期 + 递增序号)
TODAY=$(date -u +%Y%m%d)
EXISTING=$(ls tasks/pending/task_${TODAY}_*.json 2>/dev/null | wc -l)
SEQ=$(printf "%03d" $((EXISTING + 1)))
TASK_ID="task_${TODAY}_${SEQ}"

# 生成 task JSON
cat > "tasks/pending/$TASK_ID.json" <<EOF
{
  "id": "$TASK_ID",
  "title": "<Q1 主题>",
  "prompt_file": "PROMPTS/<slug>.md",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "created_by": "user-via-task-builder",
  "mode": "<Q4 答案>",
  "auto_approve_all": <Q4 == yolo 则 true,否则 false>,
  "pipeline_hint": "<Q5 答案,或 null>",
  "priority": <Q6 答案的数字>,
  "status": "pending",
  "sprint_id": null,
  "started_at": null,
  "theme_tags": ["<从 Q1/Q3 提取的关键词>"]
}
EOF
```

### STEP 4:确认并展示

给用户一份清晰的确认:

```
✅ Task 已创建

任务 ID: <TASK_ID>
主题: <Q1>
交付物: <Q2 展开>
模式: <Q4,如 yolo 则加警告"全程无人值守,包括发布类操作">
优先级: P<Q6>

文件位置:
- Prompt: PROMPTS/<slug>.md
- Task:   tasks/pending/<TASK_ID>.json

队列状态:
- 当前 pending: <N> 个 task
- 正在运行: <0 或 1>

Hermes 的 crontab 会在下一次扫到这个 task 并启动。
如果需要调整,直接编辑 tasks/pending/<TASK_ID>.json 或 PROMPTS/<slug>.md,
crontab 启动前的修改都会被读取。

需要:
a. 取消这个 task(mv 到 tasks/cancelled/)
b. 调整 prompt / task(告诉我要改什么)
c. 完美,等它跑
```

---

## YOLO 模式的额外警告

如果 Q4 答了 yolo,STEP 4 输出时必须**额外单独警告一次**:

```
⚠️ YOLO 模式二次确认

本 task 将:
- 不会问你任何 checkpoint
- 不会确认飞书发布 / git push 等不可逆操作
- 一旦启动,只在"无法决策"(如 acceptance 失败)时停下

如果任务涉及对外发布(飞书发布、git push、生产部署),
请确认你已理解并授权。回复:
a. 确认 YOLO,授权所有操作
b. 改为 interactive 模式
c. 保留 YOLO 但禁止 external_irreversible(发布类仍需问我)

你的选择?
```

如果用户选 c,在 task JSON 里加一个覆盖字段:

```json
"yolo_overrides": {
  "keep_gates_for": ["external_irreversible"]
}
```

---

## 不要做的事

- ❌ 不要自动启动这个 task(你只负责创建,启动是 task-runner 的职责)
- ❌ 不要用绝对路径
- ❌ 不要在用户没明确 yolo 时自己加 yolo
- ❌ 不要跳过 STEP 4 的确认,直接丢个 task 就结束
- ❌ YOLO 模式必须做二次确认警告,不要省

---

## 典型对话示例(给用户看怎么用)

```
用户:/task-builder

Hermes(Q1):任务主题是什么?
用户:做一个 Hermes 教程

Hermes(Q2):交付物是什么?可多选。
  a. HTML PPT
  b. AI 配音
  c. 飞书文档
  d. 代码/脚本
  e. 调研报告
  f. 其他
用户:abc

Hermes(Q3):内容范围/要求?
用户:覆盖 macOS/Linux/Windows 三平台,Windows 没环境只写文字

Hermes(Q4):模式?
  a. interactive
  b. yolo
用户:b

Hermes(Q4 二次警告):⚠️ YOLO 模式...(上方警告)
  a. 确认  b. 改 interactive  c. 保留但禁发布
用户:c

Hermes(Q5):基于管线?
  a. 从零
  b. tutorial-content(已沉淀 1 次)
用户:a

Hermes(Q6):优先级?
  a. P1  b. P2  c. P3  d. P4  e. P5
用户:c

Hermes:
✅ Task 已创建
任务 ID: task_20260421_003
...
```
