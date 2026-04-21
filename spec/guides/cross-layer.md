# Cross-Layer Development Guide

> 当 feature 的 acceptance 涉及**跨层 / 跨模块 / 跨语言**时,Generator 应该读这份指南。
> 如果 feature 是单层的(比如只改一个 Python 模块),此文件可跳过。

---

## 什么是"跨层"

符合以下任一,视为跨层 feature:

- 同一 feature 涉及 2 种以上编程语言(如:Python 后端 + TypeScript 前端)
- 同一 feature 涉及 2 个以上独立仓库
- 同一 feature 涉及 "代码 + 内容 + 部署" 两类以上
- 同一 feature 产物中既有运行时(会被执行)也有文档(会被阅读)

---

## 跨层 feature 的拆分建议

### 默认策略:拆成多 feature

能拆就拆,不跨层最简单。

**反面示例**:
```
f001: 实现用户登录(后端 API + 前端表单 + 部署)
```

**拆后**:
```
f001: 后端 /auth/login API
f002: 前端 LoginForm 组件(depends_on: f001)
f003: 部署登录功能(depends_on: f001, f002)
```

### 无法拆时(原子跨层)

某些 feature 天然无法拆(如"同步一个 schema 到后端 + 前端 + 文档三处"),这种情况:

- `feature.acceptance` 必须**按层**列清单
- phase=3 verify 必须**逐层检查**
- `generator_log.md` 的 phase 段落中,必须按层小标题组织

---

## 跨层 feature 的 phase 推进规则

### phase=1 plan

拆子任务时,**按层拆**:
```
children:
  - { layer: "backend",  desc: "实现 /auth/login" }
  - { layer: "frontend", desc: "实现 LoginForm" }
  - { layer: "infra",    desc: "更新 nginx 配置" }
```

### phase=2 implement

**按层顺序实现**,不跳层。常见顺序:

1. 底层 / 被依赖层先做(backend / schema / protocol)
2. 中层
3. 上层 / 呈现层(frontend / docs)

### phase=3 verify

**每层独立跑测试**:
- backend: 单元 + 集成测试
- frontend: 组件测试 + e2e
- infra: smoke test

任一层 fail → 整个 feature retry。

---

## 常见跨层陷阱

### 1. 前后端接口不一致
**防范**:phase=2 开始前,先在 `generator_log.md` 的 phase=1 段落里**显式定义接口契约**(字段名、类型、错误码)。phase=2 的任何一层改动接口,都要同步其他层。

### 2. 部署遗漏
**防范**:tooling.md 必须显式写"部署流程 / 部署清单"。feature phase=4 deliver 时,必须有"部署确认"动作,不仅仅是 commit。

### 3. 文档滞后
**防范**:跨层 feature 的 acceptance **必须包含一条 docs 相关**,如"API 文档已更新"。不写这条,deliver 后文档就会烂掉。

---

## 与 tooling.md 的关系

跨层 feature 依赖的工具 / 框架 / 规范,必须在 phase=0 tooling 里**每层分别列出**:

```markdown
## 2. 能力 → 工具映射

| 能力 | 层 | 选用 | ... |
|---|---|---|---|
| HTTP 服务 | backend | FastAPI | |
| UI 框架 | frontend | React 18 | |
| 反向代理 | infra | nginx | |
```

任何一层缺失 tooling → `tooling_locked` 不能置 true,feature 无法进 phase=2。
