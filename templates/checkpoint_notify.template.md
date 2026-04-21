# Checkpoint 推送消息模板

> **模板说明**:Hermes 生成 gate / review / notify checkpoint 后,通过飞书(或其他用户指定渠道)推送。
> v0.5 决策:**不发链接,只发卡点问题**。让用户回复编号+选项。

---

## gate 型模板

```
【Checkpoint】{feature_id} {feature_name}

{opening_prompt}

我做完了 {work_summary},有 {N} 个地方要你确认:

1. {blocker_1_question}
   a. {option_1a}
   b. {option_1b}
   c. {option_1c}

2. {blocker_2_question}
   a. {option_2a}
   b. {option_2b}

3. 还有其他你觉得不对的地方吗?(catch_all 兜底)
   a. 没有
   b. 有(请详述)

请回复编号+选项,例如 "1a 2b 3a"。
```

**必需字段**:
- catch_all 兜底问题必须是最后一条
- blocker 数量建议 2-4 条,不超过 5 条
- 每条必须有至少 2 个选项

---

## review 型模板

```
【Review】{feature_id} {feature_name}(48h 默认通过)

{summary}

可选确认点:
1. {blocker_1}
   a. OK  b. 需要调整

如果你没回复,48h 后自动标记为通过。
要改请直接回复;没问题可以不回。
```

---

## notify 型模板

```
【Notify】{feature_id} 已完成

{summary}

无需你回复,仅通知。详见 eval_log。
```

---

## gate 催办模板(24h)

```
【催办】Checkpoint {checkpoint_id} 已等待你 24h

原问题见上一条。

sprint 当前处于 waiting_human 状态,
但我已经推进了其他不冲突的 feature:{parallel_features}。
```

## gate 催办模板(72h)

```
【催办-紧急】Checkpoint {checkpoint_id} 已等待你 72h

我已经推进完所有不依赖此 checkpoint 的 feature,
sprint 真正卡住了。请尽快回复。

如果你想挂起 sprint,回复 "suspend"。
```

---

## YOLO Abort 聚合推送模板

```
【YOLO 已退出,请回来审】

原因:{abort_reason}(如:f007 配音 API 连续失败)

以下 {N} 个 checkpoint 已被 revoke 回 pending,需要你补审:

========== 1. {cp_id_1} - {feature_1} ==========
{原 blocker 问题组}

========== 2. {cp_id_2} - {feature_2} ==========
{原 blocker 问题组}

...

请按顺序回复,每个 checkpoint 用 "cp1: 1a 2b" 格式。
```

**关键约束**:YOLO abort 必须**单条消息**聚合,不允许刷屏。
