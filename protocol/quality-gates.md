# JiT Test Protocol — 质量门参考

质量门是阶段推进的**硬性前提**，必须全部满足才能进入下一阶段。
标注 MUST 的是强制项，SHOULD 的是推荐项。

---

## Triage → Brainstorm

| 级别 | 质量门 |
|------|--------|
| MUST | 测试对象已明确（类型 + 版本） |
| MUST | 测试范围已界定（功能点列表） |
| SHOULD | 优先级已标注（P0/P1/P2） |

## Brainstorm → Plan

| 级别 | 质量门 |
|------|--------|
| MUST | 测试用例矩阵已生成（含正向/反向/边界） |
| MUST | 环境预检通过（或已知问题已标注解决方案） |
| SHOULD | 已知失败模式已对照 known-patterns |

## Plan → Env Setup（需用户审批）

| 级别 | 质量门 |
|------|--------|
| MUST | 每个用例有：ID、标题、前置条件、步骤、预期结果、验证命令 |
| MUST | 用例覆盖所有 P0 功能点 |
| MUST | **用户已审批计划** |
| SHOULD | 回归用例已标注（如有历史 Bug） |

## Env Setup → Execute

| 级别 | 质量门 |
|------|--------|
| MUST | Namespace 存在且可用 |
| MUST | 所有 Secret/ConfigMap 已创建 |
| MUST | 测试镜像可拉取（实际验证） |
| MUST | 目标资源类型的 CRD 已注册 |
| ADAPTER | Adapter 定义的额外环境检查项（见 adapter.yaml → env_checks） |

## Execute → Report

| 级别 | 质量门 |
|------|--------|
| MUST | 所有用例已执行（PASSED/FAILED/SKIPPED） |
| MUST | 每个 FAILED 用例有完整日志和失败原因 |
| SHOULD | 每个 FAILED 用例已对照 known-patterns 自动诊断 |

## Report → Optimize

| 级别 | 质量门 |
|------|--------|
| MUST | 报告包含：环境信息、用例汇总表、每个用例详情、已知问题、结论 |
| MUST | PASS/FAIL 统计准确 |
| SHOULD | 每个 FAILED 用例有失败原因和建议 |

## Optimize → Regression（或结束）

| 级别 | 质量门 |
|------|--------|
| MUST | 6 个回顾维度均已检查 |
| MUST | 改动建议已列出并获用户确认 |

## Regression 完成条件（需用户审批回归计划）

| 级别 | 质量门 |
|------|--------|
| MUST | 所有 P0 Bug 对应用例已回归 |
| MUST | 回归报告已生成并引用原始报告 |
| MUST | **用户已审批回归计划** |

---

## Adapter 扩展

Adapter 可在 `adapter.yaml` 的 `env_checks` 字段定义额外的环境检查项。
这些检查项在 Env Setup 阶段由 env-checker agent 执行，与通用检查项合并。

示例：
```yaml
# adapters/<name>/adapter.yaml
env_checks:
  - "Controller 运行中"
  - "Resolver 可用"
  - "目标资源版本可解析"
```
