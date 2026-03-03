---
name: jit-report
description: 生成 JiT 测试报告（分层模式或 Legacy 单文件模式）
license: MIT
compatibility: opencode
---

# /jit-report — 生成测试报告

## 功能

读取 `testdata/` 下的测试结果文件，根据项目规模和模式自动选择：
- **分层模式**：按 batch 并行生成批次报告 + Index 报告（推荐，适合 3+ 用例）
- **Legacy 模式**：委托 report-generator 生成单文件报告（回归测试或小项目）

## 参数

| 参数 | 必选 | 说明 |
|------|------|------|
| `type` | 否 | 报告类型：`test`（默认）或 `regression` |
| `format` | 否 | 输出格式：`markdown`（默认） |

## 执行步骤

### Step 1: 检查前置条件

```
- testdata/ 目录存在且非空
- 至少有 1 个 TC-XX-result.json 文件
- memory/context.md 的当前阶段是 execute 或 report
```

如果不满足，提示用户先执行测试。

### Step 2: 收集结果文件

```bash
# 查找所有结果文件
ls testdata/TC-*-result.json

# 统计
TOTAL=$(ls testdata/TC-*-result.json | wc -l)
PASSED=$(grep -l '"status": "PASSED"' testdata/TC-*-result.json | wc -l)
FAILED=$(grep -l '"status": "FAILED"' testdata/TC-*-result.json | wc -l)
```

### Step 2.5: 选择报告模式

根据以下条件决定使用分层模式还是 Legacy 模式：

| 条件 | 模式 |
|------|------|
| type=regression | **Legacy** — 回归报告暂不支持分层 |
| TC 总数 ≤ 2 | **Legacy** — 用例太少，分层无意义 |
| testdata/batch-manifest.json 已存在（前次生成） | **分层** — 复用已有 manifest |
| TC 总数 ≥ 3 且 type=test | **分层** — 自动生成 manifest |

**决定后向用户告知模式**：
```
📊 检测到 {{TOTAL}} 个用例，使用 [分层/Legacy] 模式生成报告。
```

---

### Step 3-hierarchical: 分层报告生成

> 仅在选择分层模式时执行

#### 3a. 生成 batch-manifest.json

**由 skill 主会话执行**（非委派 agent），因为需要读取 plan 和 testdata：

1. 读取最新 plan 文件（`plans/` 目录下最新的 `.md` 文件）
2. 从 plan 中提取功能区域分组：
   - 查找 `##` 级别标题中包含"测试"或"用例"或"功能"的 section
   - 每个 section 下的 TC-XX 引用构成一个功能分组
3. 如果 plan 中无明确分组，按 TC 序号每 5 个一组
4. 应用分组规则：
   - 每组最多 **8 个 TC**
   - 最后一组如果只有 **1-2 个 TC**，合并到前一组
   - TC 总数 ≤ 2 时为单组
5. 为每组生成 label：
   - 有功能区域名 → 使用功能区域名（移除特殊字符 `&|<>"/` 和多余空格）
   - 无功能区域名 → 使用 `sequential`
6. 写入 `testdata/batch-manifest.json`：

```json
{
  "version": 1,
  "generated_at": "ISO8601 时间戳",
  "grouped_by": "feature_area 或 sequential",
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

#### 3b. 清理已有报告

```bash
# 删除已有的 batch 目录和旧 Index（全量重新生成）
rm -rf reports/batch-*/
rm -f reports/*-test-results.md
```

**注意**：如果 `reports/` 中有 Legacy 模式的旧报告，也一并清理。

#### 3c. 并行启动 batch-reporter agents

对 batch-manifest.json 中的每个 batch，启动 batch-reporter agent：

```
# 最多 3 个并行
for each batch in manifest.batches:
    Agent(
        subagent_type: "general-purpose",  # 使用通用 agent 加载 batch-reporter prompt
        prompt: """
        你是 batch-reporter agent。请读取以下 agent 定义并严格遵循：
        ~/.jit-test-protocol/adapters/tekton/agents/batch-reporter.md

        你的任务参数：
        - batch_id: {{batch.id}}
        - batch_label: {{batch.label}}
        - tc_ids: {{batch.tc_ids}}
        - plan_file: {{plan_file_path}}
        - output_dir: reports/{{batch.id}}-{{batch.label}}/

        请按照 batch-reporter.md 中的执行流程和报告模板生成该批次的报告。
        报告模板参考：~/.jit-test-protocol/adapters/tekton/templates/batch-report.md.template
        """,
        description: "生成 {{batch.id}} 批次报告"
    )
```

**等待所有 batch-reporter 完成后再继续。**

#### 3d. 启动 summary-aggregator

```
Agent(
    subagent_type: "general-purpose",
    prompt: """
    你是 summary-aggregator agent。请读取以下 agent 定义并严格遵循：
    ~/.jit-test-protocol/adapters/tekton/agents/summary-aggregator.md

    你的任务参数：
    - batch_report_paths: [所有 batch 报告的路径列表]
    - context_file: memory/context.md
    - output_file: reports/{{DATE}}-test-results.md
    - project_name: [从 context.md 获取]
    - test_object: [从 context.md 获取]

    请按照 summary-aggregator.md 中的执行流程和 Index 模板生成 Index 报告。
    报告模板参考：~/.jit-test-protocol/adapters/tekton/templates/index-report.md.template
    """,
    description: "聚合生成 Index 报告"
)
```

---

### Step 3-legacy: 单文件报告生成

> 仅在选择 Legacy 模式时执行（原有流程，保持不变）

启动 report-generator agent，传入：
- 所有 `testdata/TC-*-result.json` 文件路径
- 测试计划文件路径（`plans/` 下最新的）
- 报告类型（test / regression）
- 如果是 regression，传入原始报告路径

---

### Step 4: 验证报告

#### 分层模式验证

1. 检查 Index 文件是否已创建：`reports/YYYY-MM-DD-test-results.md`
2. 检查每个 batch 报告是否已创建：`reports/batch-{N}-{label}/batch-{N}-results.md`
3. 验证 Index 中的统计数据与各 batch 摘要合计一致：
   - 从 Index 的 `## 摘要` 提取总数
   - 从各 batch 报告的 `## 摘要` 提取并求和
   - 两者必须一致
4. 验证 batch-manifest.json 中的所有 TC 都出现在某个 batch 报告中
5. 如果 Index 超过 100 行，显示警告（但不阻塞）

#### Legacy 模式验证

- 检查报告文件是否已创建：`reports/YYYY-MM-DD-test-results.md`
- 验证 PASS/FAIL 计数与实际结果一致

**如果验证失败**，列出具体问题并建议修复方式。

### Step 5: 更新状态

更新 `memory/context.md`：
- report 阶段 → completed

### Step 6: 输出

#### 分层模式输出

```
📊 测试报告已生成！（分层模式）

📄 Index: reports/YYYY-MM-DD-test-results.md

📁 批次报告:
  - reports/batch-1-基础功能/batch-1-results.md (5/5 通过)
  - reports/batch-2-错误处理/batch-2-results.md (3/5 通过)
  - reports/batch-3-边界条件/batch-3-results.md (4/5 通过)

## 摘要
- 总计: X 个用例
- ✅ PASSED: Y
- 🔴 FAILED: Z
- 通过率: N%

下一步: 使用 /jit-next 进入 optimize 阶段。
```

#### Legacy 模式输出

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
