# Sub-skill: sprint-finalizer

> 所有 feature 完成 deliver 后,Hermes 进入本 sub-skill。
> 职责:检查过程协议完整性 → 问用户是否沉淀管线 → 抽象化写入 `~/.hermes/pipelines/`

---

## 进入条件

- `sprint_contract.status = "finalizing"`
- `feature_list` 中所有 feature `status ∈ {completed, cancelled}`
- 没有 pending_checkpoints
- 没有 pending_eval

---

## 工作流程

### Step 1. 过程协议完整性检查

按 `protocols/process-protocol.md` 的"sprint-finalizer 检查清单"逐项扫描:

- [ ] tooling.md 存在且 6 章节齐全
- [ ] tooling.md 每个选型都有理由
- [ ] feature_list.json 所有 feature status=completed 或 cancelled
- [ ] 每个 completed feature 的 generator_log.md 四个 phase 段落齐全
- [ ] 每个 completed feature 的 phase=4 有 commit hash
- [ ] eval_log 每条都有 reason 字段
- [ ] eval_log 的 checkpoint 条目 decision 字段非空
- [ ] 没有 pending_eval 残留
- [ ] 没有 pending_checkpoints 残留

### Step 2. 补录缺漏

对检查不通过的项:

1. **缺 tooling.md 选型理由**:
 - 基于 LLM 对话历史或 eval_log 反推理由
 - 不能补录 → 标记该选型 `incomplete_for_abstraction`

2. **缺 generator_log 某 phase 段落**:
 - 基于 eval_log + git log 反推"做了什么"
 - 关键决策无法反推 → 标"补录失败,incomplete_for_abstraction"

3. **缺 eval_log reason**:
 - 基于上下文补一句(明确标"补录:...")
 - 不能补 → 该条目不能作为抽象参考

**补录规则**(硬性):
- ❌ 不编造
- ❌ 不改写 Generator 已写的内容
- ✅ 补录条目必须加 `(补录 by sprint-finalizer)` 标记

### Step 3. 向用户报告检查结果

飞书推送:

```
【Sprint finalizing】sprint_<id>

过程协议检查结果:
- 完整项:N/N
- 需补录:M 项 (已自动补录 K 项,K' 项失败)
- 失败项详情:{列出}

要不要把这次的过程抽象成可复用管线?

a. 是,作为 <pipeline_id> v1.0 / 升版
b. 否,仅归档(closed)
c. 让我先看看抽象后的草稿

耗时:{duration}h
最终状态:{N_feature} 完成,{M_retry} 次 retry,{Y/N} YOLO 参与
```

### Step 4. 等用户回复

**a. 沉淀**:
- 进入 Step 5(抽象化)
- 完成后 `sprint_contract.status = "sunk"`

**b. 仅归档**:
- `sprint_contract.status = "closed"`
- 跳过 Step 5
- 归档产物(见 Step 6)

**c. 先看草稿**:
- 进入 Step 5 生成草稿但不写入 pipelines/
- 推给用户 review
- 用户 approved → 写入 + sunk
- 用户 rejected → closed

### Step 5. 抽象化

按 `protocols/process-protocol.md` 的抽象化规则:

1. **判断是新管线还是升版**
 - 用户回复里若指定管线 id → 升版
 - 若是全新 id → 新管线

2. **去具体名**
 - 扫描 tooling.md / feature_list / generator_log
 - 项目名 / IP / 文档 ID / 真实用户名 → 模板变量
 - 例:`CC Switch` → `{product_name}`,`ubuntu-22.04` → `{deploy_target}`

3. **保留决策理由**
 - tooling.md 里的所有"因为 X 所以选 Y"全部保留
 - 这是管线价值核心

4. **提取 feature_template**
 - 保留 feature DAG 结构(id + 依赖关系)
 - 保留每个 feature 的 reusable 标记(判断:本 feature 是否可能被其他管线复用)
 - 具体 acceptance 文字 → 模板化

5. **提取 tooling_template**
 - 基于本次 tooling.md + 选型理由

6. **提取 checkpoint_policy**
 - 哪些 phase 放 gate、review、notify → 保留分布

7. **版本号**
 - 新管线:v1.0
 - 升版:
 - 微调 checkpoint prompt → patch(x.y.z+1)
 - 新增 / 改 policy → minor(x.y+1.0)
 - 改 feature DAG 结构 → major(x+1.0.0)
 - 规则见 v0.5 决策 3

8. **stats 更新**
 - 新管线:`total_runs=1, success_rate=1.0, current_version_runs=1, yolo_eligible=false`
 - 升版(非 major):继承 total_runs + 1,current_version_runs 重置为 1
 - major 升版:**重置 stats**,total_runs=1

9. **version_history 追加一条**

10. **写入**
 - `~/.hermes/pipelines/<pipeline_id>/pipeline.yaml`
 - `~/.hermes/pipelines/<pipeline_id>/feature_template.json`
 - `~/.hermes/pipelines/<pipeline_id>/tooling_template.md`
 - `~/.hermes/pipelines/<pipeline_id>/checkpoint_policy.yaml`
 - 在 `runs/` 下建软链指向本 sprint 的 `.harness/`

### Step 6. 归档与清理

1. 把 `.harness/` 打包并归档(位置:`~/Workbase/pipeline/archive/sprint_<id>/`)
 - 或保留在 `~/Workbase/pipeline/sprint_<id>/`,Hermes 读 pipelines/runs 里的软链

2. 更新 `runtime_state`:
 - `mode = "idle"`
 - `current_sprint = null`
 - `current_project_path = null`

3. 清理 `session_pool.json`(置空 active)

4. 飞书通知"sprint 完成":
 ```
 【Sprint 完成】sprint_<id>
 - 沉淀为 <pipeline_id> v<version>(或 "仅归档")
 - Hermes 回到 idle
 ```

---

## 失败场景

### 过程协议严重不完整

- 缺失比例 > 30% → 不能沉淀
- 直接 status=closed,用户选 a 也强制转 b

### 用户 72h 不回复

- 默认 "b. 仅归档"
- 写入 eval_log 注明"用户未响应,默认归档"

### Finalizer 自身触达 Hermes Reset 阈值

- 按 `sub-skills/hermes-reset.md` 走 Reset
- 新 Hermes 启动后继续 finalizing 流程
- `pending_finalize` 字段记录:sprint_id + 当前 finalize step

---

## 禁止

- ❌ 不能在过程协议不完整时强行沉淀成管线
- ❌ 不能编造选型理由
- ❌ 不能修改 Generator 写的 generator_log 原文
- ❌ 不能在用户未确认时写入 pipelines/

## 必须做到

- ✅ 先检查完整性再问沉淀
- ✅ 补录明确标记
- ✅ 每次沉淀写 version_history
- ✅ stats 更新遵循继承规则
- ✅ 归档完成后 Hermes 真正回到 idle
