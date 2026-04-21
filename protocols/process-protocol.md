# Process Protocol

> **过程协议**:运行时必须留下的结构化记录清单。
> 存在目的:让 sprint-finalizer 在 sprint 结束时能**抽象出可复用的管线**。
> **不留过程协议 = 这次 sprint 无法沉淀**,只是一次性任务。

---

## 为什么需要过程协议

v0.5 决策:**干完成之后再抽象,干的时候留过程协议**。

这意味着:
- 实时沉淀会打断用户 → 改为事后抽象
- 事后抽象的前提:运行时留下了**足够结构化**的原始记录
- 过程协议 = 这份"结构化原始记录"的硬性清单

---

## 必须落盘的产物清单

### Sprint 级

| 产物 | 位置 | 职责 Agent | 必含内容 |
|---|---|---|---|
| tooling.md | `.harness/sprint_contracts/<sprint>/tooling.md` | Hermes(phase=0)| 能力清单 + 选型 + **选型理由** + 禁止 + 全局约束 |
| sprint_contract.json | `.harness/sprint_contracts/<sprint>/contract.json` | Hermes(phase=1)| generator_contract + features + evaluator_criteria |
| feature_list.json | `.harness/feature_list.json` | Hermes(phase=1),Generator(各 phase 推进)| 所有 feature + phase + checkpoints + depends_on |

### Feature 级

| 产物 | 位置 | 职责 Agent | 必含内容 |
|---|---|---|---|
| context_snapshot.md | `.harness/features/<fid>/context_snapshot.md` | Hermes(启动时) | 初始上下文 |
| generator_log.md | `.harness/features/<fid>/generator_log.md` | Generator(每 phase)| 做了什么 + 关键决策 + 产出物 + 遇到的问题 |
| handoff.md | `.harness/features/<fid>/handoff.md` | Generator(Reset 时)| 中断快照 |
| AGENTS.md | `.harness/features/<fid>/AGENTS.md` | Hermes(启动时复制)| 约束 |

### 事件级

| 产物 | 位置 | 职责 Agent | 必含内容 |
|---|---|---|---|
| eval_log.jsonl | `.harness/eval_log.jsonl` | Hermes(每次判决)+ Generator(每 phase 完成)| timestamp + event_type + feature_id + phase + **reason** |
| hermes_handoff.md | `.harness/hermes_handoff.md` | Hermes(Reset 时)| pending_eval + pending_checkpoints + 快照 |
| runtime_state.json | `.harness/runtime_state.json` | Hermes(每次状态变化) | mode + current_sprint + timestamps |
| session_pool.json | `.harness/session_pool.json` | Hermes(每次启动/结束 feature session) | active map |

---

## 关键字段要求

### tooling.md 必含"选型理由"

每个"多候选"的选项,必须写明理由。**没有理由 → 过程协议不完整。**

反面:
```
PPT 工具:reveal.js
```

正面:
```
PPT 工具:reveal.js(不选 marp,因 reveal.js 交互性更强,教学场景需要)
```

### generator_log.md 必含"关键决策"

每个 phase 段落必须有"关键决策"小节,即使"没有特殊决策"也要明确写"按常规实现,无特殊决策"。

### eval_log 必含 reason

每条 eval_log 必须有 `reason` 字段。禁止:
- ❌ "看起来不错"
- ❌ "通过"(无具体证据)
- ❌ 空字符串

正面:
- ✅ "3 个 acceptance 全部 pass,测试覆盖率 92%"
- ✅ "retry:b1 acceptance 失败,原因是 mock 数据不全,修正方向:补充 admin 角色的 mock"

---

## Sprint-Finalizer 的检查清单

sprint 结束时,sprint-finalizer 按以下清单扫描,任一不满足标记 `incomplete_for_abstraction`:

- [ ] tooling.md 存在且 6 章节齐全
- [ ] tooling.md 每个选型都有理由
- [ ] feature_list.json 所有 feature status=completed(或明确 cancelled)
- [ ] 每个 completed feature 的 generator_log.md 四个 phase 段落齐全
- [ ] 每个 completed feature 的 phase=4 有 commit hash
- [ ] eval_log 每条都有 reason 字段
- [ ] eval_log 的 checkpoint 条目 decision 字段非空
- [ ] 没有 pending_eval 残留
- [ ] 没有 pending_checkpoints 残留

**不完整的部分**:
- Finalizer 尝试基于 LLM 对话历史补录(若能访问)
- 补录不了的:标记该字段 `incomplete_for_abstraction`,该部分不能被抽象到 pipeline 模板

---

## 补录规则

Finalizer 补录时必须遵守:

- ❌ 不能编造不存在的决策
- ❌ 不能改写 Generator 已写的内容(即使觉得不够好)
- ✅ 可以从 eval_log 反推做了什么(但 reason 不能替 Generator 写)
- ✅ 可以在补录的条目加 `补录:` 前缀,方便事后审计

例:
```
## phase=2 implement — 2026-04-21T14:00:00Z (补录 by sprint-finalizer)

### 做了什么
[补录:根据 eval_log 和 git commit 推断,本阶段完成了 src/auth.ts 的实现]

### 关键决策
[补录失败:未找到相关记录,标记 incomplete_for_abstraction]
```

---

## 抽象化规则(Finalizer 把 sprint 转管线)

过程协议齐全后,抽象化步骤:

1. **去具体名**
 - 项目名 / IP / 文档 ID / 真实数据 → 模板变量
 - `CC Switch` → `{product_name}`
 - `ubuntu-22.04` → `{deploy_target}`

2. **保留决策理由**
 - tooling.md 里的"不选 marp,因 reveal.js 交互性更强" → **保留**
 - 这是新 sprint 复用的价值所在

3. **保留 feature DAG 结构**
 - feature 之间的 depends_on 关系 → 保留
 - 具体 acceptance 文字可模板化,但结构保留

4. **保留 checkpoint policy**
 - 哪些 phase 放了 gate、哪些 review → 保留

5. **不保留**
 - 具体 commit hash
 - 具体 session id
 - 具体 timestamp(除了版本号)
 - 具体用户反馈文本(反馈会随任务变化)

---

## 运行时协议检查(可选)

Hermes 在运行时可以定期做"过程协议健康检查":

- 每个 feature phase 切换时检查 generator_log 是否有对应段落
- 每次写 eval_log 前校验 reason 字段非空
- Reset 前检查 handoff 是否已写

不强制,但推荐。发现缺漏时 Hermes 应该:
1. 让 Generator 补齐(PostToolUse 提醒)
2. 自己补录(如果是 Hermes 自己的疏漏)

---

## 协议失败的后果

| 缺漏程度 | 后果 |
|---|---|
| 个别字段缺 reason | 该 sprint 可完成,但管线抽象时标部分 incomplete |
| generator_log 某 phase 缺段 | sprint-finalizer 补录 / 标 incomplete |
| tooling.md 无选型理由 | 管线 stats 不计入 success(即使业务完成) |
| eval_log 大面积缺失 | sprint **不能沉淀**成管线,只归档 |
| pending_eval 未处理 | sprint 状态异常,需人工介入 |

---

**协议本身即是价值**。第一次跑累点,把协议留好,后续复用才能真正"超级"。
