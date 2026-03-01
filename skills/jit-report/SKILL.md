---
name: jit-report
description: 生成 JiT 测试报告（汇编 testdata/ 下的结果为 Markdown 报告）
license: MIT
compatibility: opencode
---

# /jit-report — 生成测试报告

## 功能

读取 `testdata/` 下的测试结果文件，委托 report-generator agent 汇编为结构化 Markdown 报告。

## 参数

| 参数 | 必选 | 说明 |
|------|------|------|
| `type` | 否 | 报告类型：`test`（默认）或 `regression` |
| `format` | 否 | 输出格式：`markdown`（默认） |

## 执行步骤

### 1. 检查前置条件

```
- testdata/ 目录存在且非空
- 至少有 1 个 TC-XX-result.json 文件
- memory/context.md 的当前阶段是 execute 或 report
```

如果不满足，提示用户先执行测试。

### 2. 收集结果文件

```bash
# 查找所有结果文件
ls testdata/TC-*-result.json

# 统计
TOTAL=$(ls testdata/TC-*-result.json | wc -l)
PASSED=$(grep -l '"status": "PASSED"' testdata/TC-*-result.json | wc -l)
FAILED=$(grep -l '"status": "FAILED"' testdata/TC-*-result.json | wc -l)
```

### 3. 委托 report-generator

启动 report-generator agent，传入：
- 所有 `testdata/TC-*-result.json` 文件路径
- 测试计划文件路径（`plans/` 下最新的）
- 报告类型（test / regression）
- 如果是 regression，传入原始报告路径

### 4. 验证报告

report-generator 完成后：
- 检查报告文件是否已创建：`reports/YYYY-MM-DD-test-results.md`
- 验证 PASS/FAIL 计数与实际结果一致
- 显示报告摘要

### 5. 更新状态

更新 `memory/context.md`：
- report 阶段 → completed

### 6. 输出

```
📊 测试报告已生成！

📄 文件: reports/YYYY-MM-DD-test-results.md

## 摘要
- 总计: X 个用例
- ✅ PASSED: Y
- 🔴 FAILED: Z
- 通过率: N%

下一步: 使用 /jit-next 进入 optimize 阶段。
```
