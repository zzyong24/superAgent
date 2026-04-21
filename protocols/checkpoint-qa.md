# Checkpoint QA Protocol

> Checkpoint 的交互形态协议。gate / review / notify 三种类型的完整定义 + 用户回复解析规则。
> **v0.5 决策:不发链接,只发卡点问题。** 用户在飞书(或等价通道)回复,Hermes 解析。

---

## 三种 Checkpoint 类型

| 类型 | 触发场景 | 交互 | 超时行为 | 写 eval_log |
|---|---|---|---|---|
| **gate** | 关键决策点(大纲、成品、发布前) | 必须用户回复 | 永不超时,24h/72h 催办 | decision=approved/rejected/approved_with_changes |
| **review** | 完整性检查点(调研、Mac 文字稿) | 建议回复 | 48h 默认通过 | decision=auto_approved_timeout |
| **notify** | 完成通知(飞书发布成功) | 可看可不看 | 立即放行 | event_type=notify |

---

## Checkpoint 何时生成

- feature 某个 phase 结束后,Evaluator 根据 `feature.checkpoints` 配置生成对应 checkpoint
- checkpoint 的 `type` 在 phase=1 plan 时由 Hermes 决定(写入 feature_list)
- 决定规则参考 `~/.hermes/pipelines/<pipeline>/checkpoint_policy.yaml`(若实例化自管线)

---

## Gate Checkpoint 的完整流程

### Step 1. Hermes 提炼 blockers

**这是 gate checkpoint 的核心能力。** Hermes 不直接把产物甩给用户,而是:

1. 自己看一遍产物
2. 识别 2-4 个"超出 sprint_contract 定义"的决策点
3. 每个决策点写成 `blocker` 对象(见 `schemas/checkpoint.schema.json`)
4. 每个 blocker 必须含 2-4 个候选选项
5. 最后追加一条 `catch_all` 兜底问(见下方模板)

### Step 2. 推送

基于 `templates/checkpoint_notify.template.md` 的 gate 模板生成飞书消息。

推送要点:
- 开头注明 feature_id + feature_name
- 每个 blocker 编号,选项用 a/b/c
- 结尾提示回复格式

### Step 3. 等待回复

- Hermes 进入 `mode=waiting_human`(如果所有活跃 feature 都被 blocked)
- **但可以继续推进无依赖冲突的其他 feature**(见 `feature-isolation.md`)
- `runtime_state.pending_user_replies` 记录该 checkpoint id

### Step 4. 催办

- 24h 未回复:推送催办模板(v0.5 `templates/checkpoint_notify.template.md` 中"24h 催办")
- 72h 未回复:推送紧急催办 + 告知用户可以 "suspend"

### Step 5. 解析回复

见下方"用户回复解析规则"。

### Step 6. 写 eval_log + 推进

- 追加 `event_type=checkpoint` 条目
- 更新 `feature_list` 中本 checkpoint 的 `decision` / `feedback` / `responded_at`
- 从 `runtime_state.pending_user_replies` 移除
- 根据 decision 推进 feature:
 - `approved` → 进入下一 phase
 - `approved_with_changes` → 把 feedback 写入下一 phase 的指令
 - `rejected` → retry 当前 phase,按 feedback 修改

---

## Review Checkpoint

流程简化版:

1. 推送 review 模板(见 `templates/checkpoint_notify.template.md`)
2. 启动 48h 定时器
3. 用户回复 → 立即处理,同 gate
4. 48h 超时 → 自动 approved,写 eval_log `decision=auto_approved_timeout`
5. 即使超时通过,之后也可被 YOLO abort 回 pending(见 `protocols/yolo.md`)

---

## Notify Checkpoint

最简:

1. 推送 notify 消息
2. 立即写 eval_log `event_type=notify`,不记录 decision
3. 不阻塞,feature 直接进下一 phase 或 completed

---

## 用户回复解析规则

用户可能的回复格式(Hermes 必须都能解析):

### 严格格式
```
1a 2b 3a
```

### 宽松格式
```
1 选 a,配音按章节好,2b
```

### 带反馈
```
1a 2 我觉得按页,但简短
```

### 解析步骤

1. **提取编号-选项对**:正则匹配 `\d+[a-z]`,或 "N 选 x" / "N: x" 等变体
2. **识别反馈文本**:选项 + 附加文字 → 视为 `approved_with_changes`
3. **歧义处理**:
 - 回复里 blocker 数量 ≠ checkpoint blocker 数量 → Hermes 追问一次:"我没看到你对 blocker N 的回答,请补一下"
 - 回复"reject" / "no" / "不对" → `decision=rejected`,追问具体反馈
 - 回复 "suspend" → sprint 进入 suspended 状态(见 `protocols/feature-isolation.md`)

### 绝对禁止
- ❌ 不要猜用户意图。看不懂就追问,不要默认通过或默认拒绝
- ❌ 不要把 `approved_with_changes` 降级为 `approved`——反馈必须写入下一轮指令

---

## Catch-all 兜底问(每个 gate 必含)

```json
{
  "id": "catch_all",
  "question": "还有其他你觉得不对的地方吗?",
  "options": ["a. 没有", "b. 有(请详述)"]
}
```

设计目的:防止 Hermes 提炼 blocker 时漏掉关键决策点。用户如果回 `b`,后续文字视为 feedback。

---

## Checkpoint 与 YOLO 的交互

- YOLO 命中时,gate checkpoint 自动通过,`decision=auto_approved_yolo`,**不推送**
- YOLO abort 时,所有 auto_approved_yolo 的 checkpoint `decision=revoked`,聚合推送(见 `protocols/yolo.md`)

---

## 数据落盘清单

每个 checkpoint 生命周期内必须落盘:

| 文件 | 动作 |
|---|---|
| `feature_list.json` | checkpoint 对象的 status / decision / feedback / responded_at 字段更新 |
| `eval_log.jsonl` | 追加一条 `event_type=checkpoint` |
| `runtime_state.json` | `pending_user_replies` 增删 |

漏写任一 → 过程协议不完整。
