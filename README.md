# superAgent

> **Hermes 的一个 skill**。入口是 `SKILL.md`。
>
> 当你(Hermes)被触发执行这个 skill 时,你的任务是在 `~/Workbase/pipeline/` 下初始化一个标准化的 Agent 协作环境,并作为 Planner + Evaluator 带领 Claude Code 完成一个重任务。

---

## 这是什么

superAgent 是一个**纯约束类 skill**。仓库里**没有任何可执行代码**,全部都是:

- `schemas/` — 所有运行时文件的 JSON/YAML schema
- `templates/` — 所有 Markdown 产物的模板
- `spec/` — Generator(Claude Code)的约束规范
- `protocols/` — 跨 Agent 的协作协议
- `sub-skills/` — Hermes 在不同阶段进入的子 skill 定义
- `SKILL.md` — Hermes 的入口

仓库本身**不运行**。它是被 Hermes 这个常驻 Agent "加载" + "按约定执行"的一套规矩。

---

## 解决什么问题

基于 Context Engineering 三层架构(Planner / Generator / Evaluator),把"让 AI Agent 完成一个复杂任务"这件事,从**每次都靠临场发挥**,变成**遵循一套可沉淀的工程化流程**。

### 核心痛点

| 痛点 | 对应机制 |
|---|---|
| Generator 不知道"做完"的标准 | sprint_contract + acceptance + checkpoint |
| 跨 session 状态丢失 | `.harness/` 文件系统作为 Source of Truth |
| Claude Code 越权充当 Planner | Generator AGENTS.md 严格约束 + phase 隔离 |
| Claude Code 上下文膨胀 | feature 级独立 session + feature Reset |
| Hermes 自己也会 Context Overload | Hermes 进程内 Reset + pending_eval 防丢 |
| Harness Engineering 没工程化 | 本 skill 把一切约束显式化 |
| 工具选型隐性、不可复用 | phase=0 tooling(v0.5 新增) |
| 每次任务重做一遍 | 管线(pipeline)作为"成功 sprint 的抽象物" |
| 人类介入密度无法控制 | gate/review/notify 三类 checkpoint |
| 熟悉管线后仍然频繁打扰 | YOLO 模式(stats 驱动) |

---

## 核心概念一张表

| 概念 | 含义 | 位置 |
|---|---|---|
| **Sprint** | 一次走完整三层架构的任务 | `~/Workbase/pipeline/sprint_<id>/` |
| **Pipeline** | "跑通的 sprint" 抽象成的可复用模板 | `~/.hermes/pipelines/<id>/` |
| **Feature** | Sprint 内的一个可交付单元 | `feature_list.json` 中一条 |
| **Phase** | feature 的阶段(0=tooling 1=plan 2=implement 3=verify 4=deliver) | feature.phase |
| **Checkpoint** | 人类决策点,三类:gate / review / notify | feature.checkpoints[N] |
| **Blocker** | checkpoint 里具体的待决策问题(必含 catch_all 兜底) | checkpoint.blockers[N] |
| **YOLO** | 管线跑熟后 gate 自动通过模式 | pipeline.yolo + 本 sprint 的 abort 状态 |
| **过程协议** | 运行时必须留下的结构化产物清单 | 见 `protocols/process-protocol.md` |
| **Handoff** | Reset 时的中断快照(Hermes 一份、每个 feature 一份) | `.harness/` 下 |

---

## 架构速览

### 三层角色

```
用户 → Hermes(常驻 Agent) → Claude Code(feature 级独立 session)
 ↕    Planner + Evaluator          Generator
```

### 八层联动(v0.5)

```
第零层  管线层(超级 skill 库)       ~/.hermes/pipelines/
第一层  文件层(.harness/)            Source of Truth
第二层  Skill 层(本仓库 + sub-skills)Hermes 的强制行为
第三层  约束层(Generator AGENTS.md) Claude Code 不越权
第四层  CC Feature Reset              feature 级 session 断点续传
第五层  Hermes Reset                  进程内清空上下文,文件恢复
第六层  监控层                         token + retry + 时长 + yolo
第七层  Checkpoint 交互层              飞书问答(不发链接)
第八层  YOLO 层                         stats 驱动 + 激进 abort
```

### 十大关键设计决策(v0.5)

1. **phase=0 tooling** 独立成 sprint 级阶段,产出 `tooling.md`
2. **Checkpoint 问答形态**:不发链接,Hermes 提炼 2-4 个 blocker 问用户,含 catch_all 兜底
3. **YOLO 激进退出**:一旦本 sprint 偏离历史模式,所有 auto_approved_yolo checkpoint 全部 revoke
4. **stats 继承**:管线小版本升级继承 stats,major 变更重置
5. **干完再抽象**:sprint-finalizer 在 sprint 结束后问是否沉淀管线
6. **feature 级独立 session**:每个 feature 一个 Claude Code session(v0.4 是 sprint 级)
7. **Hermes 常驻 Agent**:不是新会话启动,是进程内清空上下文
8. **单 sprint 独占**:同时不并行多 sprint,临时轻任务走老路
9. **用户手选管线**:不自动匹配,Hermes 列候选用户选
10. **waiting_human 时推进无冲突 feature**:不浪费带宽

---

## 怎么用

### 一、给 Hermes(Agent)看

Hermes 被用户触发这个 skill 后:

1. 读 `SKILL.md`
2. 按其中"第一步 / 第二步 / 第三步"依次执行
3. 在各阶段进入 `sub-skills/` 对应文件
4. 遵守 `protocols/` 和 `spec/`
5. 产出物严格遵循 `schemas/` 和 `templates/`

### 二、给用户(人类)看

触发 skill 时告诉 Hermes:

```
用 tutorial-content 管线做一个 CC Switch 教学任务,
服务器是 ubuntu-22.04,Mac/Windows 只做文字版
```

或(没有已有管线时):

```
帮我做 <任务描述>,从零规划
```

之后用户只需:
- 在飞书回复 Hermes 推送的卡点问题(按 `1a 2b 3a` 格式)
- 等 sprint 完成 → 决定是否沉淀成管线

---

## 目录结构

```
superAgent/
├── SKILL.md                     # Hermes 入口,必读
├── README.md                    # 本文件(给人看)
├── schemas/                     # 7 个 schema(JSON/YAML)
│   ├── runtime_state.schema.json
│   ├── feature_list.schema.json
│   ├── sprint_contract.schema.json
│   ├── session_pool.schema.json
│   ├── eval_log.schema.json
│   ├── pipeline.schema.yaml
│   └── checkpoint.schema.json
├── templates/                   # 6 个 Markdown 模板
│   ├── tooling.template.md
│   ├── hermes_handoff.template.md
│   ├── claude_code_handoff.template.md
│   ├── feature_session_init.template.md
│   ├── generator_log.template.md
│   └── checkpoint_notify.template.md
├── spec/                        # Generator 约束
│   ├── index.md
│   ├── project.md
│   ├── AGENTS.md                # Generator 主约束(必读)
│   └── guides/
│       ├── phase-workflow.md
│       ├── acceptance-writing.md
│       └── cross-layer.md
├── sub-skills/                  # Hermes 的 4 个子 skill
│   ├── sprint-planner.md        # phase=0 + phase=1
│   ├── sprint-evaluator.md      # 监听 + 判决 + checkpoint 处理
│   ├── sprint-finalizer.md      # 收尾 + 管线沉淀
│   └── hermes-reset.md          # 进程内 Reset
└── protocols/                   # 协作协议
    ├── checkpoint-qa.md
    ├── yolo.md
    ├── feature-isolation.md
    ├── reset-mechanism.md
    └── process-protocol.md
```

---

## 运行时产出(Hermes 初始化的协作环境)

Hermes 每次执行本 skill,会在 `~/Workbase/pipeline/sprint_<YYYYMMDD>_<N>/` 下生成:

```
~/Workbase/pipeline/sprint_20260421_1/
├── schemas/                     # 从本 skill 复制
├── templates/                   # 从本 skill 复制
├── spec/                        # 从本 skill 复制
├── protocols/                   # 从本 skill 复制
└── .harness/                    # 运行时
    ├── runtime_state.json
    ├── feature_list.json
    ├── session_pool.json
    ├── eval_log.jsonl
    ├── hermes_context_state.json
    ├── claude_code_context_state.json
    ├── hermes_handoff.md
    ├── .current_agent
    ├── sprint_contracts/
    │   └── sprint_20260421_1/
    │       ├── contract.json
    │       └── tooling.md
    └── features/
        ├── f001/
        │   ├── session_id.txt
        │   ├── context_snapshot.md
        │   ├── generator_log.md
        │   ├── handoff.md
        │   └── AGENTS.md
        └── f002/
            └── ...
```

---

## Sprint 生命周期

```
planning → tooling → planned → active ⇄ waiting_human
                                   ↓
                                suspended(可 resume)
                                   ↓
                              finalizing
                                   ↓
                              sunk / closed
```

详细见 `sub-skills/sprint-planner.md` 和 v0.5 架构文档(在 vault 中)。

---

## 绝对禁止(skill 使用铁律)

- ❌ 不修改本仓库里的 `schemas/` / `templates/` / `spec/` / `protocols/`(Hermes 运行时复制到 pipeline 子目录后也不改)
- ❌ 不跳过 phase=0 tooling
- ❌ 不跳过 gate checkpoint(除非 YOLO 明确允许,且非 external_irreversible)
- ❌ 不并行多 sprint(单 sprint 独占)
- ❌ 不越权(Generator 不做 Planner 的事,Planner 不做 Generator 的事)

---

## 版本历史

- **v0.4**(2026-04-21 上午):六层联动架构初稿。定义文件层 + Skill 层 + 约束层 + 双 Reset 层 + 监控层,给 Hermes Context Overload 提供了 hermes_handoff + pending_eval 机制
- **v0.5**(2026-04-21 下午):新增 phase=0 tooling、Checkpoint 问答机制、YOLO、管线层、feature 级隔离、Hermes 常驻进程、单 sprint 独占、sprint-finalizer。七层联动 + 十大核心决策

完整架构决策记录位于用户 vault:
`vault/space/crafted/writing/20260421_Hermes___Claude_Code_三层架构落地计划_v0_5.md`

---

## 哲学

**工程化文件夹 = 可复用的步骤 = 超级 skill。**

第一次跑一个任务会累,但过程协议留好、管线沉淀下来之后,第 4 次基本自动化。
人工投入一次,换长期稳定自动化,而不是追求一次性全自动。
