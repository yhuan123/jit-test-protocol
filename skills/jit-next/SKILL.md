---
name: jit-next
description: 推进 JiT 测试项目到下一阶段（检查质量门、触发审批、调度 agent）
license: MIT
compatibility: opencode
---

# /jit-next — 推进到下一阶段

## 功能

检查当前阶段质量门，满足后推进到下一阶段。如果下一阶段需要 human_approval，触发审批流程。根据阶段定义调度对应 agent 执行工作。

## 参数

| 参数 | 必选 | 说明 |
|------|------|------|
| `stage` | 否 | 指定跳转到的阶段（默认为下一个） |

## 执行步骤

### 1. 读取当前状态

```
读取 memory/context.md → 当前阶段
读取 lifecycle/stages.yaml → 阶段定义
```

### 2. 检查当前阶段质量门

逐项检查当前阶段的 `quality_gate`：

```
FOR each gate in current_stage.quality_gate:
  IF gate 已满足:
    → ✅ [gate 描述]
  ELSE:
    → ❌ [gate 描述] — [缺失说明]
```

如果有未满足的质量门：
- 列出所有缺失项
- 建议如何满足（或委派给对应 agent）
- **不推进**，等用户决定

### 3. 确定下一阶段

```
current_order = stages[current_stage].order
next_stage = stages 中 order = current_order + 1 的阶段
```

特殊情况：
- 如果指定了 `stage` 参数，跳转到该阶段
- regression 完成后，进入 optimize（循环）
- optimize 完成后，如有 FAILED 用例待修复 → regression，否则结束

### 4. 检查审批要求

```
IF next_stage.human_approval == true:
  → 展示审批提示（stages.yaml 中的 approval_prompt）
  → 等待用户确认
  → 用户拒绝 → 保持当前阶段
```

### 5. 推进并调度

更新 `memory/context.md`：
- 当前阶段状态 → `completed`，记录完成时间
- 下一阶段状态 → `in_progress`，记录进入时间

根据 `next_stage.agent` 调度对应 agent：

| 阶段 | 主 Agent | 并行 Agent |
|------|---------|-----------|
| triage | coordinator | — |
| brainstorm | coordinator | env-checker（并行） |
| plan | coordinator | — |
| env_setup | test-executor | — |
| execute | test-executor | 最多 3 个并行 |
| report | report-generator | — |
| optimize | coordinator | — |
| regression | coordinator → test-executor | — |

### 6. 输出状态

```
🔄 阶段推进: {{current}} → {{next}}

下一步: {{next_stage.description}}
Agent: {{next_stage.agent}}
需要审批: {{next_stage.human_approval}}
```
