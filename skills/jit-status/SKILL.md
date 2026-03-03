---
name: jit-status
description: 查看当前 JiT 测试项目的生命周期状态和进度
license: MIT
compatibility: opencode
---

# /jit-status — 查看测试生命周期状态

## 功能

读取当前项目的 `memory/context.md` 和 `lifecycle/stages.yaml`，显示 ASCII 生命周期图和进度摘要。纯只读操作，不修改任何文件。

## 执行步骤

### 1. 定位项目

从当前目录向上查找 `lifecycle/stages.yaml`：

```bash
DIR=$(pwd)
while [ "$DIR" != "/" ]; do
  [ -f "$DIR/lifecycle/stages.yaml" ] && break
  DIR=$(dirname "$DIR")
done
```

如果未找到，提示用户：
> "未检测到 JiT 测试项目。请 cd 到项目目录，或使用 /jit-init 初始化新项目。"

### 2. 读取状态文件

读取以下文件：
- `memory/context.md` — 当前阶段、用例统计、阻塞问题
- `lifecycle/stages.yaml` — 阶段定义
- `reports/` 目录下最新报告（如有）

**报告检测**：
- 优先查找 `reports/YYYY-MM-DD-test-results.md`（Index 或 Legacy 报告）
- 如果发现 `reports/batch-*/` 目录，识别为**分层报告模式**，统计 batch 数量
- 显示报告摘要时，优先从 Index 报告的 `## 摘要` section 读取

### 3. 显示 ASCII 生命周期图

```
╭─────────────────────────────────────────────────────────────╮
│                    JiT Test Lifecycle                        │
│                                                             │
│  ✅ triage → ✅ brainstorm → 🔒 plan → ⬜ env_setup       │
│                                                             │
│  → ⬜ execute → ⬜ report → ⬜ optimize → 🔒 regression   │
╰─────────────────────────────────────────────────────────────╯

图标说明:
  ✅ completed    🔄 in_progress    ⬜ pending
  🔒 needs approval    ⛔ blocked
```

### 4. 显示进度摘要

```markdown
## 项目: {{PROJECT_NAME}}

| 字段 | 值 |
|------|-----|
| 测试对象 | {{TEST_OBJECT}} |
| Adapter | {{ADAPTER}} |
| 当前阶段 | {{CURRENT_STAGE}} |
| 上次更新 | {{LAST_UPDATE}} |
| 阻塞问题 | {{BLOCKING}} |

## 用例统计（如有）

| 指标 | 值 |
|------|-----|
| 总计 | X |
| PASSED | Y |
| FAILED | Z |
| 通过率 | N% |
```

### 5. 提供详情选项

如果用户想看更多，提示：
- "查看完整阶段历史？"
- "查看用例详情？"
- "查看最新报告？"

如果是分层报告模式，额外提示：
- "查看某个批次的详细报告？"（列出 batch 列表供选择）
