---
title: "feat: Hierarchical Report Architecture for JiT Test Protocol"
type: feat
status: completed
date: 2026-03-03
origin: brainstorms/2026-03-03-hierarchical-report-brainstorm.md
---

# Hierarchical Report Architecture for JiT Test Protocol

## Overview

将 jit-test 的单体报告拆分为 **Index → Batch** 两层结构。report-generator agent 改为按 batch 处理（每批最多 8 个 TC），summary-aggregator agent 从各 batch 摘要聚合生成 Index 报告。解决 agent 上下文溢出和人工阅读困难两个核心问题。

## Problem Statement / Motivation

1. **Agent 上下文溢出**：report-generator 读取 70+ 个 TC 的 result.json + logs 后，加上写报告的输出，总 token 超出上下文窗口，导致报告生成失败或被截断
2. **人工阅读困难**：1800+ 行的单文件报告难以快速定位关键信息（失败用例、通过率）
3. **实际案例**：jit-frontend-test 项目 70 个用例生成了 1816 行报告

## Proposed Solution

### Architecture

```
/jit-report 启动
    │
    ├─ 检查 testdata/ 有结果文件
    │
    ├─ 生成 batch-manifest.json（/jit-report skill 自己生成）
    │   ├─ 读取 plan 中的功能区域分组
    │   ├─ 扫描 testdata/TC-*-result.json
    │   └─ 写入 testdata/batch-manifest.json
    │
    ├─ 对每个 batch 并行启动 batch-reporter agent（max 3）
    │   ├─ batch-reporter 读取该 batch 的 TC result + logs
    │   └─ 写入 reports/batch-{N}-{label}/batch-{N}-results.md
    │
    ├─ 全部 batch 完成后启动 summary-aggregator agent
    │   ├─ 读取各 batch 报告的 ## 摘要 section
    │   └─ 写入 reports/YYYY-MM-DD-test-results.md (Index)
    │
    └─ 质量门验证 + 更新 memory/context.md
```

### Key Design Decisions (see brainstorm)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| batch-manifest 生成者 | /jit-report skill（主会话） | coordinator 没有写文件权限，skill 有完整权限 |
| 每批上限 | 8 个 TC | 保证 batch-reporter 上下文可控 |
| 分组依据 | 优先 plan 功能区域，否则 TC 序号每 5 个 | 平衡语义分组和简单性 |
| batch-reporter 输出 | 单个 .md 文件，含标准 ## 摘要 section | 避免引入新 JSON 格式 |
| summary-aggregator 输入 | 各 batch 报告的 ## 摘要 section（非全文） | 避免 aggregator 也溢出 |
| 回归模式 | 暂保留单文件模式 | 跨 batch 比较复杂度高，后续迭代 |
| 重新生成 | 全量覆盖（删旧 batch 目录 + Index） | 简单可靠 |
| 向后兼容 | 无 batch-manifest → 走原有单文件流程 | 零破坏性变更 |

### File Structure

```
reports/
├── 2026-03-03-test-results.md              ← Index（< 100 行）
├── batch-1-基础功能/
│   └── batch-1-results.md                  ← 该批次完整报告
├── batch-2-错误处理/
│   └── batch-2-results.md
└── batch-3-边界条件/
    └── batch-3-results.md
```

## Technical Considerations

### Agent 上下文预算

- batch-reporter 处理单 batch（最多 8 TC）：~8 × (result.json ~30行 + logs 20行 + 报告输出 ~50行) ≈ 800 行
- summary-aggregator 只读摘要：~N_batch × 10行 ≈ 50-100 行
- 均远低于上下文限制

### batch-manifest.json Schema

```json
{
  "version": 1,
  "generated_at": "2026-03-03T10:00:00Z",
  "grouped_by": "feature_area",
  "default_batch_size": 5,
  "batches": [
    {
      "id": "batch-1",
      "label": "基础功能",
      "tc_ids": ["TC-01", "TC-02", "TC-03", "TC-04", "TC-05"]
    }
  ]
}
```

### Batch 报告标准摘要 Section

每个 batch 报告必须以固定格式的 `## 摘要` 开头，供 summary-aggregator 解析：

```markdown
## 摘要

| 指标 | 数值 |
|------|------|
| 批次 | batch-1: 基础功能 |
| 用例数 | 5 |
| 通过 | 4 |
| 失败 | 1 |
| 超时 | 0 |
| 跳过 | 0 |
| 通过率 | 80% |

### 失败用例
| TC | 标题 | 失败原因 |
|----|------|---------|
| TC-03 | xxx | xxx |
```

### Edge Cases

| 场景 | 处理 |
|------|------|
| TC 总数 ≤ 2 | 单 batch，不分组 |
| 最后一组 ≤ 2 TC | 合并到前一组 |
| batch-manifest 引用了不存在的 TC result | 该 TC 标记为 MISSING，quality gate 报警 |
| 所有 TC PASSED | batch-reporter 正常生成报告，省略失败分析 section |
| 单 batch 内容仍溢出（8 个重度失败） | batch-reporter 应用 20 行日志截断规则 |
| batch-manifest.json 格式错误 | /jit-report 降级为单文件模式并警告 |
| Index 超过 100 行 | 软限制，生成警告但不阻塞 |
| 重复执行 /jit-report | 删除已有 batch 目录和 Index，全量重新生成 |
| 回归测试模式 | 忽略 batch-manifest，走原有单文件回归报告流程 |

## Acceptance Criteria

- [ ] 70+ 用例项目能成功生成分层报告，不触发上下文溢出
- [ ] Index 报告 < 100 行，包含摘要表格和批次导航链接
- [ ] 每个 batch 报告包含该批次所有用例详情
- [ ] Index 统计数据与各 batch 报告一致
- [ ] 无 batch-manifest.json 的老项目仍能正常生成单文件报告
- [ ] /jit-status 能正确读取分层报告
- [ ] 回归测试模式不受影响

## Implementation Phases

### Phase 1: Protocol 层定义（基础设施）

**目标**：定义新的 agent 角色、阶段子步骤和质量门

#### Task 1.1: 更新 `protocol/stages.yaml`

**文件**: `~/.jit-test-protocol/protocol/stages.yaml`

将 report 阶段从平坦结构改为支持 sub_steps：

```yaml
report:
  order: 6
  description: "分层生成测试报告（Index + Batch）"
  sub_steps:
    - name: generate_manifest
      description: "生成 batch-manifest.json（由 skill 主会话执行）"
      agent: null  # skill 自己执行，不需要 agent
      inputs:
        - "测试计划（功能分组信息）"
        - "testdata/TC-*-result.json（实际结果文件列表）"
      outputs:
        - "testdata/batch-manifest.json"
    - name: batch_report
      description: "按批次生成详细报告"
      agent: batch-reporter
      parallel: true
      max_concurrent: 3
      inputs:
        - "testdata/batch-manifest.json（该 batch 的 TC 列表）"
        - "对应 batch 的 TC-XX-result.json 和 TC-XX-logs.txt"
      outputs:
        - "reports/batch-{N}-{label}/batch-{N}-results.md"
    - name: summary_aggregate
      description: "聚合各 batch 摘要生成 Index 报告"
      agent: summary-aggregator
      depends_on: batch_report
      inputs:
        - "所有 batch-{N}-results.md 的 ## 摘要 section"
        - "memory/context.md（项目元数据）"
      outputs:
        - "reports/{{DATE}}-test-results.md"
  # 保留原始定义作为降级路径
  legacy:
    agent: report-generator
    parallel: false
    inputs:
      - "testdata/ 下所有用例结果"
      - "测试计划（作为报告框架）"
    outputs:
      - "reports/{{DATE}}-test-results.md"
  quality_gate:
    - "Index 报告存在，包含摘要表格和批次导航链接"
    - "每个 batch 目录下有完整批次报告"
    - "Index 统计数据与各 batch 报告合计一致"
    - "所有 TC 均在某个 batch 报告中出现"
  human_approval: false
```

#### Task 1.2: 更新 `protocol/agent-roles.md`

**文件**: `~/.jit-test-protocol/protocol/agent-roles.md`

在 agent 表格中：
- 将 `report-generator` 行改为 `batch-reporter`
- 新增 `summary-aggregator` 行
- 保留 `report-generator` 作为 legacy 备注

```markdown
| Agent | 职责 | 写集群 | 写文件 | 执行命令 |
|-------|------|--------|--------|----------|
| coordinator | 生命周期编排 | ❌ | ❌ | ❌ |
| env-checker | 集群预检 | ❌ only read | ❌ | ✅ read-only |
| test-executor | apply + collect + diagnose | ✅ test NS only | ✅ testdata/ only | ✅ |
| batch-reporter | 单批次报告生成 | ❌ | ✅ reports/ only | ❌ |
| summary-aggregator | Index 报告聚合 | ❌ | ✅ reports/ only | ❌ |
| report-generator *(legacy)* | 单文件报告生成 | ❌ | ✅ reports/ only | ❌ |
```

在 `### report-generator` section 下方新增两个角色的详细定义。

#### Task 1.3: 更新 `protocol/quality-gates.md`

**文件**: `~/.jit-test-protocol/protocol/quality-gates.md`

替换 `## Report → Optimize` section：

```markdown
## Report → Optimize

### 分层报告模式（存在 batch-manifest.json）

| 级别 | 质量门 |
|------|--------|
| MUST | Index 报告存在于 reports/ 顶层，包含摘要表格 |
| MUST | 每个 batch 目录下有 batch-{N}-results.md |
| MUST | Index 摘要的 PASS/FAIL/TIMEOUT/SKIPPED 合计 = 各 batch 报告合计 |
| MUST | batch-manifest.json 中所有 TC 均在某个 batch 报告中出现 |
| SHOULD | Index 报告 < 100 行 |
| SHOULD | 每个 FAILED 用例有失败原因和建议 |

### 单文件报告模式（无 batch-manifest.json，legacy）

| 级别 | 质量门 |
|------|--------|
| MUST | 报告包含：环境信息、用例汇总表、每个用例详情、已知问题、结论 |
| MUST | PASS/FAIL 统计准确 |
| SHOULD | 每个 FAILED 用例有失败原因和建议 |
```

---

### Phase 2: Adapter 层实现（Agent 定义 + 模板）

**目标**：创建新 agent prompt 文件和报告模板

#### Task 2.1: 创建 `adapters/tekton/agents/batch-reporter.md`

**文件**: `~/.jit-test-protocol/adapters/tekton/agents/batch-reporter.md` (新建)

基于现有 `report-generator.md` 重构，关键变化：
- 输入从 "所有 testdata" 变为 "单个 batch 的 TC 列表"
- 报告必须以标准 `## 摘要` section 开头（固定表格格式）
- 输出路径从 `reports/` 变为 `reports/batch-{N}-{label}/`
- 只包含首次测试报告模板（回归模板留在 legacy report-generator）
- 保留 20 行日志截断规则
- allowed-tools: `[Read, Glob, Grep, Write, Edit]`

#### Task 2.2: 创建 `adapters/tekton/agents/summary-aggregator.md`

**文件**: `~/.jit-test-protocol/adapters/tekton/agents/summary-aggregator.md` (新建)

定义：
- 输入：各 `batch-{N}-results.md` 的 `## 摘要` section + `memory/context.md`
- 输出：`reports/YYYY-MM-DD-test-results.md` (Index)
- 不读取 batch 报告的用例详情（只读摘要）
- 不读取 testdata/ 原始数据
- allowed-tools: `[Read, Glob, Grep, Write, Edit]`
- Index 模板包含：摘要表格、失败用例速览、批次导航链接、简短结论

#### Task 2.3: 保留 `report-generator.md` 作为 legacy

**文件**: `~/.jit-test-protocol/adapters/tekton/agents/report-generator.md`

不删除，不重命名。在文件顶部添加注释标明 legacy 用途：
```markdown
> **Legacy 模式**：当项目无 batch-manifest.json 时，/jit-report 降级使用此 agent。
> 新项目请使用 batch-reporter + summary-aggregator 分层模式。
```

#### Task 2.4: 创建 `adapters/tekton/templates/batch-report.md.template`

**文件**: `~/.jit-test-protocol/adapters/tekton/templates/batch-report.md.template` (新建)

模板包含：
- `## 摘要`（标准表格，供 summary-aggregator 解析）
- `## 用例汇总`（TC | 标题 | 结果 | 耗时 表格）
- `## 用例详情`（每个 TC 的完整信息）
- `## 发现的问题`（该 batch 内的 bug 列表）

#### Task 2.5: 创建 `adapters/tekton/templates/index-report.md.template`

**文件**: `~/.jit-test-protocol/adapters/tekton/templates/index-report.md.template` (新建)

模板包含：
- 项目名称和测试日期
- `## 摘要`（全局统计表格）
- `## 失败用例速览`（所有批次的失败 TC 汇总表）
- `## 批次报告`（导航链接列表）
- `## 结论与建议`

---

### Phase 3: Skill 层更新（用户入口）

**目标**：更新 /jit-report skill 实现分层流程

#### Task 3.1: 更新 `skills/jit-report/SKILL.md`

**文件**: `~/.jit-test-protocol/skills/jit-report/SKILL.md`

在现有 5 步流程中插入分支逻辑：

```
Step 1: 前置检查（不变）
Step 2: 收集结果文件（不变）
Step 2.5: 检查是否使用分层模式
  - 回归测试 → 走 legacy 流程（跳到 Step 3-legacy）
  - TC 总数 ≤ 2 → 走 legacy 流程
  - 否则 → 生成 batch-manifest.json → 走分层流程
Step 3-hierarchical: 分层报告生成
  a. 生成 batch-manifest.json
     - 读取最新 plan 文件，提取功能区域分组
     - 如果 plan 无分组，按 TC 序号每 5 个一组
     - 最后一组 ≤ 2 TC 则合并到前一组
     - 每组最多 8 TC
     - 写入 testdata/batch-manifest.json
  b. 清理已有 reports/batch-* 目录和旧 Index
  c. 对每个 batch 启动 batch-reporter agent（最多 3 个并行）
     - 传入：batch ID、TC 列表、plan 文件路径
     - batch-reporter 创建 reports/batch-{N}-{label}/ 目录
     - batch-reporter 写入 batch-{N}-results.md
  d. 全部 batch-reporter 完成后启动 summary-aggregator agent
     - 传入：所有 batch 报告路径列表、memory/context.md 路径
     - summary-aggregator 写入 reports/YYYY-MM-DD-test-results.md
Step 3-legacy: 单文件报告生成（原有流程，不变）
Step 4: 质量门验证
  - 分层模式：检查 Index + 所有 batch 报告存在 + 统计匹配
  - legacy 模式：原有检查（不变）
Step 5: 更新 memory/context.md（不变，由 skill 主会话执行）
```

#### Task 3.2: 更新 `skills/jit-status/SKILL.md`

**文件**: `~/.jit-test-protocol/skills/jit-status/SKILL.md`

在读取 reports/ 的逻辑中：
- 优先查找 `reports/YYYY-MM-DD-test-results.md`（Index）
- 如果发现 `reports/batch-*/` 目录，提示 "分层报告模式" 并显示 batch 数量
- 显示 Index 中的摘要表格（如果存在）

#### Task 3.3: 更新模板中的 agent 表格

**文件**:
- `~/.jit-test-protocol/adapters/tekton/templates/CLAUDE.md.template`
- `~/.jit-test-protocol/adapters/tekton/templates/AGENTS.md.template`

将 agent 表格中的 `report-generator` 替换为 `batch-reporter` + `summary-aggregator`。

---

## Implementation Sequence (Build Order)

```
Phase 1 (Protocol)          Phase 2 (Adapter)           Phase 3 (Skill)
┌─────────────────┐        ┌─────────────────┐        ┌─────────────────┐
│ 1.1 stages.yaml │───┐    │ 2.1 batch-      │───┐    │ 3.1 jit-report  │
│ 1.2 agent-roles │───┤    │     reporter.md  │   │    │     SKILL.md    │
│ 1.3 quality-    │───┘    │ 2.2 summary-    │   │    │ 3.2 jit-status  │
│     gates.md    │        │     aggregator  │───┤    │     SKILL.md    │
└─────────────────┘        │ 2.3 legacy note │   │    │ 3.3 templates   │
        │                  │ 2.4 batch tmpl  │   │    └─────────────────┘
        │                  │ 2.5 index tmpl  │───┘            │
        ▼                  └─────────────────┘                ▼
   Phase 1 完成后               Phase 2 完成后           Phase 3 完成后
   Phase 2 可开始               Phase 3 可开始           功能完整
```

**Phase 1 → Phase 2 → Phase 3 严格顺序**：每个 Phase 依赖前一个的定义。

Phase 内部的 Task 可以并行执行：
- Phase 1: Task 1.1, 1.2, 1.3 可并行
- Phase 2: Task 2.1-2.5 可并行
- Phase 3: Task 3.1 先，3.2 和 3.3 可并行

## File Change Summary

| # | File | Action | Phase |
|---|------|--------|-------|
| 1 | `protocol/stages.yaml` | Edit: report 阶段加 sub_steps + legacy | 1.1 |
| 2 | `protocol/agent-roles.md` | Edit: 拆分 report-generator 为两个新角色 | 1.2 |
| 3 | `protocol/quality-gates.md` | Edit: report 门禁改为分层/legacy 两套 | 1.3 |
| 4 | `adapters/tekton/agents/batch-reporter.md` | Create | 2.1 |
| 5 | `adapters/tekton/agents/summary-aggregator.md` | Create | 2.2 |
| 6 | `adapters/tekton/agents/report-generator.md` | Edit: 加 legacy 标注 | 2.3 |
| 7 | `adapters/tekton/templates/batch-report.md.template` | Create | 2.4 |
| 8 | `adapters/tekton/templates/index-report.md.template` | Create | 2.5 |
| 9 | `skills/jit-report/SKILL.md` | Edit: 加分层分支 | 3.1 |
| 10 | `skills/jit-status/SKILL.md` | Edit: 识别分层报告 | 3.2 |
| 11 | `adapters/tekton/templates/CLAUDE.md.template` | Edit: agent 表格 | 3.3 |
| 12 | `adapters/tekton/templates/AGENTS.md.template` | Edit: agent 表格 | 3.3 |

**总计**：4 个新建文件 + 8 个编辑文件 = 12 个文件

## Dependencies & Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| batch-reporter 单 batch 仍溢出 | 报告截断 | 20 行日志截断 + 最多 8 TC/batch |
| summary-aggregator 解析摘要格式失败 | Index 数据不准 | 标准化摘要 Markdown 表格格式 |
| 老项目 batch-manifest 不存在 | 功能不可用 | legacy 降级路径 |
| 批次目录名含特殊字符 | 文件系统问题 | label 转 ASCII-safe slug（保留中文，去掉特殊符号） |
| 回归模式未适配分层 | 回归报告仍是单文件 | 明确标记为 v2 迭代范围 |

## Future Considerations

- **v2: 回归模式分层**：支持跨 batch 的前后对比
- **v2: 增量重新生成**：只重新生成有变更 TC 的 batch
- **v2: HTML 渲染**：从 Markdown Index 生成可交互的 HTML 报告

## Sources & References

### Origin

- **Brainstorm document**: [brainstorms/2026-03-03-hierarchical-report-brainstorm.md](../../brainstorms/2026-03-03-hierarchical-report-brainstorm.md) — Key decisions: 分层架构 > 数据/视图分离，每批 8 TC 上限，batch-manifest.json 传递分组

### Internal References

- `protocol/stages.yaml` — report 阶段当前定义
- `protocol/agent-roles.md` — 4 个 agent 角色表
- `adapters/tekton/agents/report-generator.md` — 现有报告生成 agent prompt 和模板
- `skills/jit-report/SKILL.md` — 报告生成入口 skill

### SpecFlow Analysis Gaps Resolved

| Gap | Resolution |
|-----|-----------|
| batch-manifest 由谁写 | /jit-report skill 主会话（非 coordinator） |
| batch-reporter 输出格式 | 单 .md 文件，含标准 ## 摘要 section |
| 重新生成行为 | 全量覆盖（删旧重建） |
| 回归模式 | 暂不适配，走 legacy |
| 缺失 TC result | 标记 MISSING，质量门警告 |
| aggregator 同步机制 | skill 顺序启动（先 batch 后 aggregate） |
| Index 100 行 | 软限制 |
| batch 目录创建 | batch-reporter 自行创建 |
