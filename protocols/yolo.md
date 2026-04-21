# YOLO Protocol

> YOLO = 管线跑熟后,gate checkpoint 自动通过,不再打扰用户。
> **v0.5 决策**:激进策略——一旦偏离历史模式,立即退出 YOLO,所有 auto_approved_yolo 的 checkpoint 全部 revoke。

---

## YOLO 进入条件

当 sprint 基于某条管线实例化时,Hermes 检查该管线的 stats:

```yaml
yolo.eligibility:
  min_total_runs: 3        # 默认 3
  min_success_rate: 0.9    # 默认 0.9
```

两个条件**同时满足**,则 `yolo_eligible=true`,本次 sprint 的 gate checkpoint 进入自动通过模式。

**注意**:
- `total_runs` 是跨版本累加(v0.5 决策 3:stats 继承)
- 但需同时检查 `current_version_success_rate`,若当前版本连续 2 次失败,**即使 total_runs 够,也不进入 YOLO**(安全阀)

---

## YOLO 跳过范围

| 可跳过 | 不可跳过 |
|---|---|
| ✅ gate checkpoint 的用户问答 | ❌ eval_log 写入(必须记录) |
| ✅ review checkpoint(本来就可超时通过) | ❌ phase 基本校验 |
| ✅ notify 本来就不阻塞 | ❌ Reset 机制 |
| | ❌ fail 状态下的人类升级 |
| | ❌ **外部不可逆操作**(git push / 飞书发布 / 生产部署)—— 这类操作即使 YOLO 也强制 gate |

---

## YOLO 自动通过的具体行为

1. Evaluator 判 phase pass
2. 检查 `feature.checkpoints` 是否有 gate
3. gate 存在且 YOLO 生效:
 - **不推送**用户
 - 直接 `decision=auto_approved_yolo`
 - 写 eval_log(含 `yolo_context` 字段:pipeline_id + run_count + success_rate)
 - feature 进入下一 phase
4. gate 是 "external_irreversible" 类型 → 即使 YOLO 也**必须推送**

---

## YOLO Abort 触发条件

满足**任一**即触发 abort:

| 触发条件 | 解释 |
|---|---|
| `retry_count_in_sprint >= 2` | 本 sprint 任何 feature 累计 retry 达 2 次 |
| `any_feature_fail` | 任何 feature 进入 fail 状态 |
| `external_irreversible` | 本次要执行不可逆外部操作(单次豁免,非全局退出)|

前两个触发**全局 YOLO abort**,第三个仅对该操作恢复 gate,其他 feature 继续 YOLO。

---

## YOLO Abort 执行流程(激进策略)

### Step 1. 找出所有 auto_approved_yolo 的 checkpoint

扫描 `feature_list.json` 里所有 feature 的 checkpoints,收集 `decision=auto_approved_yolo` 的。

### Step 2. Revoke 全部

对每个:
- `checkpoint.status = "revoked"`
- `checkpoint.revoked_from = "auto_approved_yolo"`
- `checkpoint.revoke_reason = "yolo_aborted: <原因>"`
- `checkpoint.decision = null`(回到 pending)

### Step 3. 写 eval_log

每个 revoke 的 checkpoint 追加一条 `event_type=yolo_abort` 记录,含 `revoked_from` 和 `revoke_reason`。

再追加一条 sprint 级的 `event_type=yolo_abort`,记录整体触发原因。

### Step 4. 聚合推送

**单条飞书消息**(不允许刷屏)。用 `templates/checkpoint_notify.template.md` 的 "YOLO Abort 聚合推送" 模板。

### Step 5. feature 产物不回滚

⚠️ **重要**:只 revoke checkpoint 决策,**不回滚 feature 产物**。

- 若 f002 PPT 大纲曾 auto_approved_yolo → f006 HTML PPT 已基于它做完 → 现在 revoke f002 的 cp
- 用户回头审 f002 大纲,如果发现不对:
 - `decision=rejected` → 触发 **replan**(不是物理撤销 f006)
 - `decision=approved_with_changes` → 把反馈写入下一轮 sprint_contract,f006 在必要时 retry

### Step 6. Hermes 进入 waiting_human

- `runtime_state.mode = "waiting_human"`
- 不启动新 feature session
- 但已在运行的 feature session 不中断,等它们自然走到下个 phase 再说
- 等用户清算所有 revoke 的 checkpoint

---

## YOLO 退出后的恢复

用户回复完所有聚合 checkpoint 后:

- 如果全部 `approved` → 可以恢复 YOLO(但需要再次满足 eligibility)
- 如果有 `rejected` / `approved_with_changes` → YOLO 永久退出,本 sprint 剩余 checkpoint 全部走正常流程
- 不主动重启 YOLO,**除非新 sprint**

---

## Stats 更新规则(sprint 完成后)

- 成功完成(所有 feature deliver,无 YOLO abort)→ `pipeline.stats.total_runs += 1`,`success_rate` 重算
- YOLO abort 后最终完成 → `total_runs += 1`,但**本次不计入 success_rate 分子**
- sprint 被 suspended 或 closed → 不计入 stats

---

## 外部不可逆操作清单(必须强制 gate,即使 YOLO)

由 tooling.md 在 phase=0 定义。常见:

- `git push` 到 main / master / release 分支
- 飞书 / 微信 / 邮件 发布
- 生产服务器部署
- 数据库 schema 迁移
- 任何带副作用的 HTTP 请求到生产环境
- 付款 / 发送通知给终端用户

tooling.md 第 4 节"禁止"里必须列出这些,同时在 feature 的 `checkpoints[*].type="gate"` 显式标记。

---

## 数据落盘清单

YOLO 相关数据:

| 文件 | 内容 |
|---|---|
| `eval_log.jsonl` | `event_type=yolo_enter / yolo_abort` 条目 |
| `feature_list.json` | checkpoints 的 decision / revoked_from / revoke_reason |
| `runtime_state.json` | mode 变化(waiting_human) |
| pipeline.yaml | sprint 完成后更新 stats |

漏写任一 → 过程协议不完整,该 sprint 不能作为管线更新的参考。
