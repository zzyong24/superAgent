# Generator Log: {feature_id}

> **模板说明**:本文件由 Claude Code(Generator)维护,每个 phase 完成后追加一段。
> 位置:`.harness/features/f<N>/generator_log.md`
> 用途:(1) Evaluator 判断 phase 完成质量的依据;(2) sprint-finalizer 抽象管线时的原始素材。
>
> **过程协议约束**:sprint 结束时若发现某 phase 缺失 log,视为"过程协议不完整",该 sprint 不能作为管线沉淀的参考。

---

## phase=1 plan — {timestamp}

### 做了什么
简短 3-5 句,描述本 phase 的具体动作。

### 关键决策
列出 phase 内做的每个选择 + 理由(Evaluator 和 sprint-finalizer 都靠这个)。
- {decision_1}:{reason}
- {decision_2}:{reason}

### 产出物
- {file_path_1}
- {file_path_2}

### 遇到的问题 / 偏差
- {issue_1}(如何处理)
- {issue_2}

### 引入的新依赖(如有)
同时已追加到 `tooling.md` 运行时新增章节。
- {new_dep}

---

## phase=2 implement — {timestamp}

### 做了什么
...

### 关键决策
...

### 产出物
...

### 遇到的问题 / 偏差
...

---

## phase=3 verify — {timestamp}

### 测试覆盖
- {test_1}: pass
- {test_2}: fail → 如何修复

### Acceptance 自检

> 自检只是提供给 Evaluator 参考,**不能替代 Evaluator 判决**。

- {acceptance_1}: 我认为 pass,证据:{evidence}
- {acceptance_2}: 我认为 pass
- {acceptance_3}: 有不确定,原因:{reason}

---

## phase=4 deliver — {timestamp}

### Commit
- hash: {commit_hash}
- message: {commit_msg}
- branch: {branch_name}

### 最终状态
- feature_list 已更新:status=completed, phase=4
- eval_log 已追加 deliver 条目

---

**追加格式**:每个 phase 完成后,按上述结构在文件末尾追加新段落。不修改已写入的历史段落。
