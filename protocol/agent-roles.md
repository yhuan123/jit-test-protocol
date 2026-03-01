# JiT Test Protocol — Agent 角色定义

本文件定义 4 种 agent 角色的**职责和权限边界**。
具体 prompt 实现由 Adapter 的 `agents/` 目录提供。

---

## 角色总览

| Agent | 职责 | 写集群 | 写文件 | 执行命令 |
|-------|------|--------|--------|----------|
| coordinator | 生命周期编排、委派任务、检查质量门 | ❌ | ❌ | ❌ |
| env-checker | 集群环境预检，只读验证 | ❌ 只读 | ❌ | ✅ 只读命令 |
| test-executor | apply 测试资源、等待结果、收集日志、自动诊断 | ✅ 仅测试 NS | ✅ 仅 testdata/ | ✅ |
| report-generator | 汇编测试结果为 Markdown 报告 | ❌ | ✅ 仅 reports/ | ❌ |

---

## Coordinator

### 职责
1. 读取 `lifecycle/stages.yaml`（或 `protocol/stages.yaml`），确定当前阶段
2. 检查当前阶段的质量门是否满足
3. 委派任务给其他 agent（env-checker、test-executor、report-generator）
4. 推进生命周期到下一阶段
5. 在 `human_approval: true` 的阶段暂停并请求用户确认
6. 在 optimize 阶段执行 6 维度回顾

### 权限边界

**可以做**：
- 读取项目中任何文件
- 搜索代码和文件
- 创建/管理任务（TodoWrite / TaskCreate）
- 委派任务给其他 agent
- 向用户提问
- 搜索网络获取信息

**不可以做**：
- ❌ 不能执行任何 shell 命令（委派给 test-executor 或 env-checker）
- ❌ 不能修改/创建文件（委派给 report-generator 或主 session）
- ❌ 不能跳过质量门
- ❌ 不能跳过 `human_approval: true` 的审批

### 推荐 Tools (Claude Code)
```
Read, Glob, Grep, Agent, TaskCreate, TaskUpdate, TaskList, TaskGet, AskUserQuestion, SendMessage, WebFetch, WebSearch
```

---

## Env-Checker

### 职责
1. 使用只读命令验证集群环境就绪状态
2. 输出结构化检查报告
3. 标注已知问题和修复建议

### 权限边界

**可以做**：
- 读取项目文件
- 执行只读的集群查询命令（`kubectl get/describe/logs`）
- 执行网络探测（`curl`）
- 输出检查结果

**不可以做**：
- ❌ 不能执行任何修改集群状态的命令
- ❌ 不能创建、修改、删除任何 K8s 资源
- ❌ 不能修改项目文件

### Bash 约束
只允许以下命令开头：
- `kubectl get`, `kubectl describe`, `kubectl logs`, `kubectl api-resources`
- `curl`, `echo`, `openssl` (验证用)

### 检查项（通用基线）

| # | 检查项 | 说明 |
|---|--------|------|
| 1 | 集群连通性 | `kubectl cluster-info` 返回 control plane 地址 |
| 2 | 当前 context | 匹配预期集群 |
| 3 | Namespace 存在 | namespace 存在且 Active |
| 4 | CRD 已注册 | Adapter 定义的 resource_types 对应 CRD 存在 |
| 5 | 镜像可拉取 | Pull secret 存在且格式正确 |

> Adapter 可在此基线上追加领域特有检查项（通过 `adapter.yaml` 的 `env_checks`）。

### 推荐 Tools (Claude Code)
```
Read, Glob, Grep, Bash, WebFetch
```

### 输出格式

```markdown
# 环境预检报告

**集群**: [cluster name]
**Namespace**: [namespace]
**检查时间**: [timestamp]

| # | 检查项 | 状态 | 详情 |
|---|--------|------|------|
| 1 | 集群连通性 | ✅ PASS | ... |

## 总结
- 通过: X/N
- 失败: Y/N
- 就绪状态: ✅ / ❌
```

---

## Test-Executor

### 职责
1. 根据测试计划 apply K8s 测试资源
2. 等待资源达到终态
3. 收集执行日志和状态
4. 执行验证命令确认结果
5. 对 FAILED 用例进行自动诊断

### 权限边界

**可以做**：
- 执行 `kubectl apply/create/delete` 操作（**仅限测试 namespace**）
- 等待资源完成（`kubectl wait`）
- 收集日志（`kubectl logs`）
- 执行验证命令
- 在 `testdata/` 目录下创建/修改文件

**不可以做**：
- ❌ 不能操作测试 namespace 以外的资源
- ❌ 不能删除非当前测试创建的资源
- ❌ 不能修改 `plans/`、`reports/`、`lifecycle/`、`.claude/` 下的文件
- ❌ 不能修改集群级资源（ClusterRole、CRD 等）

### 核心原则：验证工具差异化

**被测工具与验证工具必须差异化**，避免同源 Bug 导致验证失效。

> 例：如果被测对象使用工具 A 操作镜像，验证时应使用工具 B（不同工具链）。

### 执行流程（每个用例）

```
1. 准备 → 读取用例定义，生成/使用 testdata/TC-XX-run.yaml
2. 执行 → apply 资源，wait 完成
3. 收集 → 获取 status JSON、日志、执行验证命令
4. 诊断 → FAILED 用例匹配 known-patterns
```

### 结果 JSON 格式

```json
{
  "tc_id": "TC-XX",
  "title": "用例标题",
  "status": "PASSED|FAILED|TIMEOUT|SKIPPED",
  "start_time": "ISO8601",
  "end_time": "ISO8601",
  "duration_seconds": 123,
  "resource_name": "资源名称",
  "verification": {
    "command": "验证命令",
    "expected": "预期结果",
    "actual": "实际结果",
    "match": true
  },
  "diagnosis": {
    "matched_pattern": "pattern-id 或 null",
    "description": "诊断描述",
    "suggestion": "修复建议"
  },
  "logs_file": "testdata/TC-XX-logs.txt"
}
```

### 推荐 Tools (Claude Code)
```
Read, Glob, Grep, Bash, Write, Edit
```

---

## Report-Generator

### 职责
1. 读取 testdata/ 中的所有测试结果
2. 汇编为结构化 Markdown 报告
3. 生成用例汇总表和详细分析

### 权限边界

**可以做**：
- 读取项目中任何文件（特别是 testdata/、plans/）
- 在 `reports/` 目录下创建和编辑报告文件

**不可以做**：
- ❌ 不能执行任何 shell 命令
- ❌ 不能修改 `testdata/`、`plans/`、`lifecycle/`、`.claude/` 下的文件
- ❌ 不能修改 `memory/context.md`

### 生成规则

1. **数据来源**：只从 `testdata/` 读取结果，不推测或假设
2. **准确性**：PASS/FAIL 计数必须与实际结果文件一致
3. **日志引用**：只引用关键片段（不超过 20 行），完整日志引用文件路径
4. **Emoji 规范**：✅ PASSED、🔴 FAILED、⏱️ TIMEOUT、⏭️ SKIPPED

### 推荐 Tools (Claude Code)
```
Read, Glob, Grep, Write, Edit
```
