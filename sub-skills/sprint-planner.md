# Sub-skill: sprint-planner

> Hermes 在 phase=0 tooling 和 phase=1 plan 阶段进入本 sub-skill。
> 本 sub-skill 的产出:完整的 `tooling.md` + `feature_list.json` + `sprint_contract.json`,并通过两个 gate checkpoint。

---

## 进入条件

满足任一即进入:

- 用户提交新任务(指定管线 或 从零规划)
- Hermes Reset 后新上下文启动,检测到 `runtime_state.mode=planning`
- YOLO abort 后需要 replan

---

## 职责范围(严格)

- ✅ 生成 tooling.md
- ✅ 拆分 feature DAG
- ✅ 创建 sprint_contract.json
- ✅ 推 gate checkpoint 确认 tooling 和 DAG
- ❌ **不做 Generator 的工作**(不实现代码、不写产出物)
- ❌ **不做 Evaluator 的工作**(不判断 feature 完成度)

---

## 工作流程

### Step 1. 前置检查

1. 读 `.harness/runtime_state.json`,确认 `mode=planning`
2. 读 `.harness/hermes_handoff.md`(若存在):
 - 有 `pending_eval`:**停下,先按 `protocols/reset-mechanism.md` 处理**,处理完才继续
 - 有 `pending_checkpoints`:检查 `feature_list` 确认是否已有用户回复
3. 读 `.harness/feature_list.json`(若存在):理解当前状态
4. 读用户任务描述

### Step 2. 管线判断(v0.5 决策:不自动匹配,用户手选)

- 用户任务中若**指定了管线**(如"用 tutorial-content 管线"):
 - 读 `~/.hermes/pipelines/<pipeline_id>/pipeline.yaml`
 - 跳到 Step 3 以使用管线模板
- 用户**未指定**:
 - 提示用户:"你要用哪条管线?选项:A / B / C / 从零规划"
 - 等用户回复
 - 回复后再进入 Step 3

**禁止**:不要自己猜管线,不要擅自匹配。

### Step 3. phase=0 tooling

#### 3.1 能力清单推理

基于用户任务描述,LLM 推理出需要的能力。例如教学任务需要:
- 视频素材检索
- 远程执行
- HTML PPT 渲染
- AI 配音
- 飞书文档上传

#### 3.2 扫描自己可用的工具

读你(Hermes)自己的 skill 列表 + MCP 工具列表 + 环境凭证。对每个能力,检查:

- 已有工具直接可用 → 标"已有"
- 需要引入新工具 → 标"新增",附理由
- 用户任务里指定 → 标"用户指定"

**若是基于管线**:读 `pipeline.yaml.required_capabilities` 和 `tooling_template.md`,优先复用上一版选型。

#### 3.3 生成 tooling.md 草稿

基于 `templates/tooling.template.md` 填空:
- 第 1 节:能力清单(勾选)
- 第 2 节:能力 → 工具映射表
- 第 3 节:**每个多候选项的选型理由**(必写,这是过程协议核心)
- 第 4 节:禁止清单
- 第 5 节:全局约束(如"无 Windows 环境")
- 第 6 节:留空(运行时新增)

写入 `.harness/sprint_contracts/<sprint_id>/tooling.md`。

#### 3.4 推 tooling gate checkpoint

创建 checkpoint 对象(按 `schemas/checkpoint.schema.json`):

```json
{
  "id": "cp-sprint-tooling",
  "phase": 0,
  "type": "gate",
  "blockers": [
    { "id": "b1", "question": "工具选型 OK 吗?", "options": [...] },
    { "id": "b2", "question": "禁止清单是否完整?", "options": [...] },
    { "id": "b3", "question": "全局约束是否写到位?", "options": [...] },
    { "id": "catch_all", "question": "还有其他你觉得不对的地方吗?", "options": [...] }
  ],
  "artifacts": [".harness/sprint_contracts/<sprint_id>/tooling.md"],
  "status": "pending"
}
```

按 `protocols/checkpoint-qa.md` 推送飞书消息。**Hermes 进入 mode=waiting_human**。

#### 3.5 处理回复

用户 approved:
- checkpoint.decision = "approved"
- 写 eval_log
- 置 `feature_list.tooling_locked = true`
- 置 `sprint_contract.status = "planned"`

用户 approved_with_changes:
- 更新 tooling.md 相关章节(明确根据 feedback 改)
- 再推一次 checkpoint 确认(避免死循环:最多 2 轮,第 2 轮后 rejected 则 replan)

用户 rejected:
- 回到 Step 3.1 重做能力推理

### Step 4. phase=1 plan — 拆分 feature DAG

#### 4.1 feature 模板实例化(若有管线)

读 `pipeline.yaml.feature_template` 指向的 JSON。针对用户本次任务,填入变量(`{product_name}` 等)。

#### 4.2 从零拆分(若无管线)

按任务分层拆:
- 调研类 feature
- 基础设施 / 工具准备类 feature
- 核心实现 feature(可能多个)
- 验证类 feature
- 交付类 feature

#### 4.3 每个 feature 必填字段

按 `schemas/feature_list.schema.json` 填:
- `id`(`f001`、`f002`...)
- `name`
- `status = "pending"`
- `phase = 1`
- `next_phases`(四个 phase,done 全 false)
- `acceptance`(按 `spec/guides/acceptance-writing.md`,可验证,1-7 条)
- `verification_mode`(automated / human / hybrid)
- `depends_on`(明确的 feature_id 列表)
- `checkpoints`(每个 feature 至少在 phase=3 有一个,type 按下方原则)

#### 4.4 Checkpoint 类型决定原则

| feature 性质 | 建议 checkpoint 分布 |
|---|---|
| 内容创作(大纲 / 成品) | phase=1 gate, phase=3 gate |
| 实操部署 | phase=3 review |
| 信息采集 | phase=1 gate(确认素材方向) |
| 编码(automated 充分) | phase=3 notify(自动判) |
| 编码(有主观) | phase=3 review |
| 对外发布(git push / 飞书发布) | phase=4 gate(external_irreversible) |

**YOLO 命中时会自动跳过 gate,但 external_irreversible 强制保留。**

#### 4.5 Blockers 提炼(每个 gate)

对每个 gate checkpoint,提炼 2-4 个 blocker:
- 每个 blocker 有 2-4 个候选选项
- 必含 `catch_all` 兜底最后一问
- 见 `spec/guides/acceptance-writing.md` 最后一节

⚠️ 注意:phase=1 时 blockers 是"初稿",phase=3 结束时 Hermes 会根据实际产出再**提炼一次**,可能替换 blockers。

#### 4.6 依赖检查

- feature DAG 不能有环
- 没有依赖的 feature(entry 节点)至少 1 个
- 每个 feature 至少有一条出边或到 deliver

#### 4.7 写入 feature_list.json

整体覆盖写入。`updated_at = now()`,`updated_by = "hermes"`。

#### 4.8 创建 sprint_contract.json

按 `schemas/sprint_contract.schema.json`:
- 填 generator_contract(如"完成 feature_list 中所有 feature 的 phase=4")
- 填 evaluator_criteria(pass / retry / fail 判断标准)
- features 列表
- retry_policy(按任务类型)
- status = "planned"

写入 `.harness/sprint_contracts/<sprint_id>/contract.json`。

### Step 5. 推 DAG gate checkpoint

blockers 建议:
- "feature 拆分粒度 OK 吗?"(太粗 / OK / 太细)
- "依赖关系是否合理?"
- "checkpoint 分布密度合适吗?"(太松 / OK / 太密)
- `catch_all`

用户 approved 后:
- `sprint_contract.status = "active"`
- `runtime_state.mode = "active"`
- 退出本 sub-skill,进入 `sub-skills/sprint-evaluator.md`

### Step 6. 交接给 Evaluator

变更 `.current_agent`:role = evaluator, developer = hermes。

触发 feature 启动流程(见 `SKILL.md` 第三步):
- 读 session_pool.max_concurrent
- 选出 depends_on 为空的 feature
- 依次调用 "启动 feature session" 子流程(见 `feature-isolation.md`)

---

## 绝对禁止

- ❌ 不要在 tooling 未 approved 时拆 feature
- ❌ 不要自己跳过 tooling gate
- ❌ 不要写"acceptance 模糊"的 feature(见 acceptance-writing.md)
- ❌ 不要在 DAG 里设置环
- ❌ 不要在 planner 阶段启动 Claude Code session

## 必须做到

- ✅ 处理 pending_eval / pending_checkpoints 先于任何新决策
- ✅ tooling.md 每个选型写理由
- ✅ 每个 feature 至少 1 条可验证 acceptance
- ✅ 每个 feature 至少 1 个 checkpoint
- ✅ 两个 gate(tooling + DAG)都通过才进入 Evaluator
