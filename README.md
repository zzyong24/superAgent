# superAgent

> **一个给 Hermes 看的 skill**。入口是 `SKILL.md`。
>
> Hermes 被触发执行这个 skill 时,在用户指定的 pipeline 根目录下初始化一个标准化的 Agent 协作环境,作为 Planner + Evaluator 带领 Claude Code feature session 完成复杂任务。

本仓库配合 [pipeline](https://github.com/zzyong24/pipeline) 使用。superAgent 是"约束集",pipeline 是"跑出来的结果"。

---

## 这是什么

superAgent 是一个**纯约束类 skill**。仓库里没有任何可执行代码(除了 4 个 hook shell),全部是:

| 目录 | 职责 |
|---|---|
| `SKILL.md` | Hermes 的入口 + STEP 0-5 流程 + Z1-Z20 铁律 |
| `sub-skills/` | 6 个分阶段子 skill(planner / evaluator / finalizer / reset / task-runner / task-builder) |
| `schemas/` | 7 个运行时文件的 JSON/YAML schema |
| `templates/` | 6 个 Markdown 产物模板 |
| `spec/` | Generator(Claude Code)的约束规范 + 开发指南 |
| `protocols/` | 7 个跨 Agent 协作协议 |
| `hooks/` | 4 个 P0 级硬约束 hook(shell 脚本,CC 启动时加载) |

仓库本身**不运行**。它是 Hermes + Claude Code 的"协作契约"。

---

## 解决什么问题

基于 Context Engineering 三层架构,把"让 AI Agent 完成复杂任务"这件事从**临场发挥**变成**工程化流程**。

```
用户 → Hermes(Planner + Evaluator) → Claude Code(Generator)
       ↑ 你管决策                    ↑ 它管执行
```

### 核心痛点

| 痛点 | 对应机制 |
|---|---|
| Agent 分工没契约 | `sprint_contract.json` + `acceptance` 清单 |
| 跨 session 状态丢失 | `.harness/feature_list.json` 作为 Source of Truth |
| Agent 越权 | `spec/AGENTS.md` + `hooks/` 硬拦截 |
| Agent 上下文膨胀 | feature 级独立 session + feature Reset |
| Hermes 自己也会上下文过载 | 进程内 Reset + `pending_eval` 防丢 |
| 工具选型隐性不可复用 | `phase=0 tooling` 独立阶段 |
| 每次任务重做 | 管线(pipeline)= 成功 sprint 的抽象物 |
| 人类介入密度不可控 | gate / review / notify 三类 checkpoint |
| 熟悉任务仍频繁打扰 | YOLO 模式(管线级 + task 级) |
| 任务没法排队 | task 队列(pending / running / 归档) |

---

## 目录结构

```
superAgent/
├── SKILL.md                        Hermes 入口(489 行,薄入口 + 厚引用)
├── README.md                        本文件
│
├── sub-skills/                      Hermes 分阶段 skill
│   ├── sprint-planner.md             phase=0 tooling + phase=1 DAG
│   ├── sprint-evaluator.md           监听 + 判决 + checkpoint 处理
│   ├── sprint-finalizer.md           sprint 收尾 + 管线沉淀
│   ├── hermes-reset.md               Hermes 进程内 Reset
│   ├── task-runner.md                ⭐ 被 crontab 触发的 task 调度
│   └── task-builder.md               ⭐ 用户调用,提问式建 task
│
├── schemas/                         运行时文件结构定义(7 个)
│   ├── runtime_state.schema.json
│   ├── feature_list.schema.json
│   ├── sprint_contract.schema.json
│   ├── session_pool.schema.json
│   ├── eval_log.schema.json
│   ├── checkpoint.schema.json
│   └── pipeline.schema.yaml
│
├── templates/                       Markdown 产物模板(6 个)
│   ├── tooling.template.md
│   ├── hermes_handoff.template.md
│   ├── claude_code_handoff.template.md
│   ├── feature_session_init.template.md
│   ├── generator_log.template.md
│   └── checkpoint_notify.template.md
│
├── spec/                            Generator 约束
│   ├── AGENTS.md                     ⭐ Claude Code 必读
│   ├── index.md
│   ├── project.md
│   └── guides/
│       ├── phase-workflow.md          phase 0-4 详细定义
│       ├── acceptance-writing.md      如何写可验证的 acceptance
│       └── cross-layer.md             跨层 feature 开发指南
│
├── protocols/                       协作协议
│   ├── execution-paths.md            ⭐ cc / cc_mcp / mcp_direct 三路径
│   ├── bootstrap-validation.md       ⭐ 所有 bash 校验 + JSON 示例
│   ├── checkpoint-qa.md              checkpoint 问答协议
│   ├── yolo.md                       管线级 YOLO 规则
│   ├── feature-isolation.md          feature 并行协议
│   ├── reset-mechanism.md            双 Reset 机制
│   └── process-protocol.md           过程协议落盘清单
│
└── hooks/                           P0 级硬约束
    ├── session-start.sh               强制注入上下文
    ├── pre-edit-guard.sh              拦只读目录 / 跨 feature / eval_log 覆盖
    ├── pre-bash-guard.sh              拦 force push / rm -rf / sudo
    ├── stop-guard.sh                  未完成过程协议不得退出
    ├── settings.json.template         CC hook 配置模板
    └── README.md                      hook 使用说明
```

⭐ = v0.5 后的关键新增

---

## 核心概念速查

| 概念 | 含义 | 位置 |
|---|---|---|
| **Task** | 一次完整任务 = 一个 sprint,由 task JSON 描述 | `tasks/pending/<id>.json` |
| **Sprint** | 一次完整的 Planner→Generator→Evaluator→Finalizer 循环 | `sprints/sprint_YYYYMMDD_N/` |
| **Pipeline** | 成功 sprint 抽象成的可复用管线模板 | `~/.hermes/pipelines/<id>/` |
| **Feature** | sprint 内的可交付单元,有 4 phase | `feature_list.features[]` |
| **Phase** | feature 阶段:1=plan, 2=implement, 3=verify, 4=deliver;sprint 级还有 phase=0=tooling | feature.phase |
| **Checkpoint** | 人类决策点,三类:gate(阻塞)/ review(48h 默认过)/ notify(仅通知) | feature.checkpoints[] |
| **Execution Path** | feature 执行路径:generator_cc / generator_cc_mcp / generator_mcp_direct | feature.execution_path |

---

## 工作流

### 启动一个 task

**推荐**:让 Hermes 执行 `sub-skills/task-builder.md`,提问式建 task。

**手动**:

1. 写 prompt → `pipeline/PROMPTS/<slug>.md`
2. 建 task JSON → `pipeline/tasks/pending/task_YYYYMMDD_NNN.json`
3. 等 Hermes 的 crontab 扫到

### Hermes 被 crontab 触发后

```
task-runner skill
 → 扫 tasks/pending/ 选优先级最高的
 → 原子 mv 到 tasks/running/
 → 读 prompt + mode,加 YOLO 提示(若 yolo)
 → 进入 SKILL.md STEP 0 → STEP 5
 → sprint 完成后 mv task JSON 到 sprints/<id>/TASK.json
```

### STEP 0-5 流程

```
STEP 0   身份定锚(Hermes 不产出业务)
STEP 0.5 环境探测(必须真跑 bash,不得假设)
STEP 1   初始化(问根目录 / 复制资源 / 建状态文件 / 自检)
STEP 2   Planner(phase=0 tooling gate + phase=1 DAG gate)
STEP 2.5 硬校验(进 STEP 3 前 15+ 条 bash test)
STEP 3   启动 feature(按 execution_path 路径部署 hook + 启 CC)
STEP 3.5 Phase 推进(每 phase 写 eval_log,phase=3 必含 acceptance_results)
STEP 4   Evaluator 监听(读+判,不产出)
STEP 5   sprint-finalizer(过程协议检查 → 沉淀管线或归档)
```

---

## YOLO 模式

**两种 YOLO 正交**:

| 类型 | 触发 | 覆盖 | decision |
|---|---|---|---|
| Pipeline YOLO | 管线跑够 3 次 + 成功率 ≥ 90% | 管线中特定 feature 的 gate | `auto_approved_yolo` |
| Task YOLO | 用户建 task 时勾选 `yolo` | 本 task 全程所有 gate(含 external_irreversible) | `auto_approved_yolo_task` |

两者都有**安全底线**:

- 无法决策(acceptance 失败 / 环境异常 / 连续 retry 上限)→ 立即失败退出,不编造通过
- eval_log 每条 auto_approved 带 audit context,可事后审计

---

## 硬约束 Z1-Z20

SKILL.md 末尾有 20 条铁律,违反任一 = 本次 skill 调用失败。每条对应一个实际失败场景:

- Z1 Hermes 不产出业务
- Z4 Feature 启动必走 STEP 3 完整流程
- Z11 DAG gate 必走
- Z12 封装 spawn 的诚实性(`delegate_task` 不等于真启 CC)
- Z14 feature 目录必须在 `.harness/features/f<N>/`
- Z17 phase=3 必含 acceptance_results 逐条证据
- Z20 task 模式与相对路径规范
- ...(完整见 SKILL.md)

---

## 版本历史关键里程碑

| commit | 关键改动 |
|---|---|
| `ab92af0` | v0.5 初始落地 |
| `bd8bccd` | 加反越权铁律(修 sprint_1 越权) |
| `781bc4d` | 加 STEP 0.5 环境探测(修 sprint_2 假装合规) |
| `40bc096` | 三路径 + Phase 规则(修 sprint_4 8 个偏差) |
| `2d6c81c` | SKILL 瘦身 49% + bootstrap-validation(上下文过载优化) |
| `871d367` | task 队列 + task-runner + task-builder(YOLO task 模式) |

---

## 使用前提

1. Hermes 已部署(常驻 Agent 支持 skill 加载 + crontab)
2. Claude Code CLI 已安装(STEP 0.5 会探测)
3. pipeline 仓库已建(放 PROMPTS/ + tasks/ + sprints/)
4. `jq` 可用(bash 校验命令依赖)

---

## 参考

- pipeline 仓库: https://github.com/zzyong24/pipeline
- 架构完整方案:vault 的「Hermes + Claude Code 三层架构完全落地方案」
- 调试记录:vault 的「调试一个 AI Agent 协作架构:5 轮实跑、10 次 SKILL 迭代、3 种失败模式」

---

## 哲学

> **工程化文件夹 = 可复用的步骤 = 超级 skill**
>
> 第一次跑累点,过程协议留全,管线沉淀后,第 4 次基本自动化。
> 人工投入一次,换长期稳定自动化。

这套架构的核心不是"让 AI 更强",是**让人类和 AI 的协作契约显式化、工程化、可沉淀**。
