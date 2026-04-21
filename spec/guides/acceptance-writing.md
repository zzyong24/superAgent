# Acceptance Writing Guide

> **给 Hermes 看**:phase=1 plan 时,你写入 `feature_list.feature.acceptance` 的每一条,必须符合本文档规范。
> 原则:**不可验证的 acceptance = 无法执行的三层架构**。

---

## 核心原则

每条 acceptance 必须满足:

1. **可验证**:有明确的"通过 / 失败"判定方式
2. **原子**:一句话一件事,不复合
3. **无歧义**:不同人读同一条 acceptance,判决结果一致

---

## 好 vs 坏

### ❌ 禁止写这类 acceptance

- "代码质量好"
- "PPT 讲得清楚"
- "架构合理"
- "性能优秀"
- "用户体验好"
- "覆盖主要场景"

### ✅ 改写示范

| 坏 | 好 |
|---|---|
| "代码质量好" | "lint 无新增 error,单元测试覆盖率 ≥ 80%" |
| "PPT 讲得清楚" | "PPT 15-20 页;每页有 1 句主标题 + 3-5 条要点;首页含教学大纲" |
| "架构合理" | "模块间无循环依赖;单一模块依赖数 ≤ 5" |
| "性能优秀" | "在 1000 并发下 p99 延迟 ≤ 200ms" |
| "覆盖主要场景" | "覆盖以下 5 个场景:登录、登出、忘记密码、邮箱验证、二次认证" |

---

## 按任务类型的 acceptance 模板

### 编码类
- "类 / 函数 `XxxYyy` 实现完成"
- "单元测试 `test_xxx` 全部通过"
- "测试覆盖率 ≥ N%"
- "`npm run lint` / `ruff check` 无新增 error"
- "PR CI 全部绿"

### 内容类
- "产出文件 `xxx.md`,章节数 N,总字数 ≥ M"
- "每章含至少 1 个代码示例 / 示意图"
- "符合 `spec/xxx-style.md` 样式规范"

### 部署类
- "服务启动成功,`curl /health` 返回 200"
- "日志无 ERROR 级别输出"
- "关键 API `/xxx` 可访问,返回预期结构"

### 调研类
- "收集 ≥ N 个参考资料,来源含 X / B 站 / 官方文档"
- "产出 `sources.md`,每条含链接 + 摘要 ≤ 200 字"

---

## 何时用 `verification_mode`

acceptance 可验证性分三档(见 `schemas/feature_list.schema.json`):

| verification_mode | 含义 | 使用场景 |
|---|---|---|
| `automated` | Evaluator 全自动判 | 编码任务,acceptance 全部能跑脚本判断 |
| `human` | Evaluator 仅检查完整性,必须用户签字 | 内容创作类,质量无法自动判 |
| `hybrid` | Evaluator 跑自动检查 + 用户抽查 | 混合任务(默认) |

**规则**:
- 写不出"可验证"的 acceptance 时,不要编造,**标 `human`**,交给 checkpoint 解决
- `human` 模式下的 acceptance 可以相对模糊(如"节奏合理"),但仍要列出具体 checkpoint 问题

---

## Checkpoint Blocker 写法

`feature.checkpoints[*].blockers[*].question` 和 acceptance 一样有规范:

- 每个 blocker 必须有 **2-4 个候选选项**(不能开放式)
- 选项互斥(不能"选 a 也选 b"——那应该拆成两个 blocker)
- 必须含 `catch_all` 兜底最后一问

### 好 blocker

```json
{
  "question": "Windows 章节用文字+官方截图 OK 吗?",
  "options": ["a. OK 这样交付", "b. 找人代录截图", "c. 去掉 Windows 章节"]
}
```

### 坏 blocker

```json
{
  "question": "你觉得这个 PPT 怎么样?",
  "options": ["a. 好", "b. 不好"]
}
```
(开放太大,"不好"没有行动项)

---

## Acceptance 数量

- 每个 feature 至少 1 条,不超过 7 条
- 超过 7 条 → 考虑拆子 feature
- 0 条不允许(phase=3 无法判决)
