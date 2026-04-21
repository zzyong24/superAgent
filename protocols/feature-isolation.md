# Feature Isolation Protocol

> 多 feature 并行执行的协议。**v0.5 决策**:每个 feature 一个独立 Claude Code session,不共享上下文。
> 核心目的:降低单 session 的 context 压力 + 支持 waiting_human 时并行推进其他 feature。

---

## Feature 目录结构

每个 feature 独占一个目录:

```
.harness/features/<feature_id>/
├── session_id.txt              # Claude Code 启动时写入
├── context_snapshot.md         # Hermes 在启动前写入,是新 session 的初始 prompt
├── generator_log.md            # Claude Code 每 phase 追加
├── handoff.md                  # Reset 时写入(首次启动时为空)
└── AGENTS.md                   # 从 spec/AGENTS.md 复制(避免 Generator 找不到)
```

**严格约束**:
- ❌ Generator 禁止读 / 写其他 feature 目录
- ❌ Generator 禁止启动 / 停止其他 feature 的 session
- ✅ Generator 可以读"依赖 feature 的产物",但**必须通过产物路径**(如 `output/xxx.md`),不通过其他 feature 目录

---

## Session Pool 管理

`.harness/session_pool.json` 由 **Hermes 独占维护**。

### max_concurrent

默认 `2`。同时最多 2 个 Claude Code feature session。

理由:
- API 成本
- 用户 review 带宽有限
- 并发高了依赖关系难管

### 启动策略:`start_when_dependency_ready`

```
新 feature 可以启动 iff:
  1. feature.depends_on 全部 completed
  2. 当前 active session 数 < max_concurrent
  3. tooling_locked=true
  4. feature.status = pending
  5. 没有全局 suspend(runtime_state.mode ≠ suspended)
```

### waiting_human 时的并行推进(v0.5 核心)

假设 f002 在 gate checkpoint 等用户回复:

```
if f003.depends_on 不含 f002(直接或间接):
    f003 可以启动  ← 并行
else:
    f003 必须等 f002 完成
```

**判断规则**:递归检查 depends_on。只要依赖链**不经过** waiting_human 的 feature,就可以启动。

### suspended 时的全局暂停

用户说 "suspend" / 回复 "suspend" 时:
1. 所有活跃 session 在当前 phase 完成后退出(写 handoff.md)
2. `sprint_contract.status = "suspended"`
3. `runtime_state.mode = "suspended"`
4. **不启动新 session**(哪怕依赖满足)
5. 等用户 "resume"

---

## Feature Session 启动流程

Hermes 启动一个新 feature session:

1. 创建 `.harness/features/<feature_id>/` 目录(如不存在)
2. 写 `context_snapshot.md`(基于 `templates/feature_session_init.template.md`)
3. 复制 `spec/AGENTS.md` 到 feature 目录
4. 调起 Claude Code,把 `context_snapshot.md` 内容作为初始 prompt
5. Claude Code 启动后写 `session_id.txt`
6. 更新 `session_pool.json.active.<feature_id>`
7. 更新 `.current_agent`:role=generator, developer=claude-code, current_feature=<feature_id>

---

## Feature Session 结束流程

Generator 完成 phase=4 deliver 后:

1. 写 `generator_log.md` 的 phase=4 段
2. 写 eval_log 的 deliver 条目
3. 更新 `feature_list.json` 本 feature `status=completed`
4. **退出 session**
5. Hermes 监听到 feature_list 变化:
 - 从 `session_pool.json.active` 移除本 feature
 - 检查是否有依赖本 feature 的 feature 现在可以启动
 - 启动下一批(受 max_concurrent 限制)

---

## 跨 Feature 通信

Generator 之间**不直接通信**。所有"共享信息"都通过 Hermes 管理的文件传递:

| 信息类型 | 通道 |
|---|---|
| 选型决策 | `tooling.md`(sprint 级,全部 Generator 共享) |
| 依赖产物 | 通过文件路径(如 `output/shared_schema.json`)|
| 运行时新增依赖 | `tooling.md` 的"运行时新增"章节(Generator append,其他 feature 下次启动时读到)|
| 设计决策 | 各自的 `generator_log.md`;跨 feature 依赖时 Hermes 可以在 context_snapshot 里摘录 |

---

## 运行时新增依赖的同步

**场景**:f003 执行中发现 tooling.md 里的 TTS 工具失败,需要用备用 TTS。

**正确流程**:
1. Generator 在 `.harness/sprint_contracts/<sprint_id>/tooling.md` 的"运行时新增"章节 append 一行
2. Generator 同时在自己的 `generator_log.md` 记录引入理由
3. Generator **通知 Hermes**(通过 eval_log,event_type=retry 或 phase_evaluation,reason 里说明)
4. Hermes 判断是否需要 gate checkpoint:
 - 轻微替换(同类工具,等效):notify 即可
 - 重大变更(新依赖,需要钥匙/费用):gate,推送用户
5. 后续其他 feature 启动前,Hermes 把"运行时新增"内容同步进 context_snapshot

**禁止**:
- ❌ Generator 修改 tooling.md 已有章节
- ❌ Generator 擅自调新工具不记录

---

## Feature 与 Pipeline 的隔离

- pipeline 里的 `feature_templates` 是**抽象模板**,实例化后每个 feature 独立运行
- feature 隔离不影响管线沉淀——sprint-finalizer 读全部 feature 的 generator_log 再抽象

---

## 失败场景处理

### Feature 执行中 Claude Code session 崩了

- Hermes 检测到 session 失联(session_pool.active.<id>.last_activity 超时)
- 标记 `session_pool.active.<id>.status = failed`
- 读 `features/<id>/handoff.md`(若有)+ `generator_log.md` 恢复上下文
- 启动新 session(同 feature,走 feature 级 Reset 流程)

### Feature 依赖关系环

- phase=1 plan 时 Hermes 校验 depends_on 有无环
- 有环 → reject 该 feature 设计,回到 Planner 重拆

### Session pool 满但有高优先级 feature

- `feature.priority=P0` 可以"挤掉"正在 `waiting_human` 的低优 session(标记该 session `suspended`,让位)
- 实际很少用,默认不启用
