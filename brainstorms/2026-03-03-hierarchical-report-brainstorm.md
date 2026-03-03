# JiT Test Protocol — 分层报告架构优化

## What We're Building

将 jit-test 的单体报告拆分为 **Index → Batch → Detail** 三层结构，解决两个核心问题：
1. **Agent 上下文溢出**：report-generator 读取全部 testdata 后 token 超限，报告生成失败或截断
2. **人工阅读困难**：70+ 用例的 1800 行单文件难以快速定位关键信息

## Why This Approach (方案 A: 分层报告)

**对比淘汰方案：**
- 方案 B (数据/视图分离)：Agent 只产 JSON + 脚本渲染 → 失去智能分析能力
- 方案 C (增量生成)：execute 阶段即时生成报告 → 跨阶段耦合太强

**选择方案 A 的理由：**
- 保留 Agent 的自然语言分析和诊断能力
- 改动范围适中（不需要重构 execute 核心逻辑）
- 向后兼容老项目（无 batch-manifest 则降级为单文件）

## Key Decisions

### 1. 批次分组策略
- 每批上限 **8 个用例**（保证 agent 上下文可控）
- 优先按 plan 中的功能区域分组，无明确分组时按 TC 编号每 5 个一组
- 分组信息通过 `testdata/batch-manifest.json` 传递
- 最后一组若只有 1-2 个用例，合并到前一组

### 2. 报告生成两阶段架构
- **batch-reporter**：per batch 并行执行（max_concurrent: 3），只处理单批次 testdata
- **summary-aggregator**：等全部 batch 完成后，读取各 batch 摘要生成 Index

### 3. 文件结构
```
reports/
├── YYYY-MM-DD-test-results.md          ← Index（< 100 行）
├── batch-1-基础功能/
│   └── batch-1-results.md              ← 该批次完整报告
├── batch-2-错误处理/
│   └── batch-2-results.md
└── batch-3-边界条件/
    └── batch-3-results.md
```

### 4. Protocol 层改动清单
| 文件 | 操作 |
|------|------|
| `protocol/stages.yaml` | report 阶段增加 sub_steps (batch_report → summary_aggregate) |
| `protocol/agent-roles.md` | 拆分 report-generator 为 batch-reporter + summary-aggregator |
| `protocol/quality-gates.md` | 更新 report 阶段门禁（Index + batch 报告完整性检查） |
| `adapters/tekton/agents/report-generator.md` | 重命名为 batch-reporter.md，缩小 scope |
| `adapters/tekton/agents/summary-aggregator.md` | 新增 |
| `adapters/tekton/templates/batch-report.md.template` | 新增 |
| `adapters/tekton/templates/index-report.md.template` | 新增 |
| `skills/jit-report/SKILL.md` | 更新流程：检测 batch-manifest → 分层/降级 |

### 5. 向后兼容
- `/jit-report` 检查 `testdata/batch-manifest.json` 是否存在
- 存在 → 新分层流程；不存在 → 降级为原有单文件流程
- 原有 report-generator 逻辑保留为 legacy 降级路径

### 6. Index 报告模板
- 摘要表格（总数/通过/失败/超时/通过率）
- 失败用例速览表
- 批次报告导航链接
- 简短结论与建议
- 目标 < 100 行

## Open Questions

*(已全部在设计讨论中解决)*

## Date
2026-03-03
