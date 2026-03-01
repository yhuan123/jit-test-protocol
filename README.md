# JiT Test Protocol

可安装的 Just-in-Time 测试工作流协议。通过 Skill 命令驱动 8 阶段测试生命周期，适用于 K8s 资源的功能测试。支持 Claude Code 和 OpenCode。

## 安装

```bash
git clone https://github.com/yhuan123/jit-test-protocol.git ~/.jit-test-protocol
cd ~/.jit-test-protocol && ./install.sh
```

install.sh 会自动检测 Claude Code / OpenCode，创建相应的软链接。

更新：
```bash
cd ~/.jit-test-protocol && git pull
```

卸载：
```bash
cd ~/.jit-test-protocol && ./uninstall.sh
```

## Quick Start

```bash
# 1. 在 Claude Code 或 OpenCode 中初始化项目
/jit-init

# 按提示填写:
#   adapter: tekton
#   test-object: catalog/task/merge-image/0.1
#   kubeconfig: ~/Downloads/kubeconf-arm.yaml
#   namespace: testing-merge-image

# 2. 查看状态
/jit-status

# 3. 推进阶段
/jit-next

# 4. 生成报告
/jit-report
```

## 架构

```
Protocol Core (方法论)     Adapter (领域知识)
┌──────────────────┐      ┌──────────────────┐
│ 8 阶段状态机      │      │ 命令模板          │
│ 质量门            │  +   │ CRD 类型          │
│ Agent 角色定义    │      │ 环境检查项         │
│ 通用失败模式      │      │ Agent prompt      │
└──────────────────┘      └──────────────────┘
         │                         │
         └─────────┬───────────────┘
                   ▼
          Skill Shell (用户入口)
          /jit-init  /jit-status
          /jit-next  /jit-report
```

### 8 阶段生命周期

```
triage → brainstorm → plan* → env_setup → execute → report → optimize → regression*
                                                                  ↑            │
                                                                  └────────────┘
* = 需要用户审批
```

| 阶段 | 职责 | Agent |
|------|------|-------|
| triage | 需求分析、确定测试范围 | coordinator |
| brainstorm | 用例设计 + 环境预检（并行） | coordinator + env-checker |
| plan | 编写测试计划（需审批） | coordinator |
| env_setup | 创建 K8s 资源 | test-executor |
| execute | 执行测试用例（最多 3 并行） | test-executor |
| report | 生成 Markdown 报告 | report-generator |
| optimize | 6 维度流程回顾 | coordinator |
| regression | 修复后回归（需审批） | coordinator → test-executor |

### 4 个 Agent 角色

| Agent | 写集群 | 写文件 |
|-------|--------|--------|
| coordinator | ❌ | ❌ |
| env-checker | ❌ 只读 | ❌ |
| test-executor | ✅ 仅测试 NS | ✅ testdata/ |
| report-generator | ❌ | ✅ reports/ |

## Skill 命令

| 命令 | 功能 |
|------|------|
| `/jit-init` | 初始化测试项目（指定 adapter、测试对象、集群） |
| `/jit-status` | 显示生命周期状态和进度 |
| `/jit-next` | 推进到下一阶段（检查质量门、触发审批） |
| `/jit-report` | 生成测试报告 |

## 可用 Adapter

| Adapter | 说明 |
|---------|------|
| `tekton` | Tekton TaskRun/PipelineRun 功能测试 |

## 创建新 Adapter

在 `adapters/` 下创建目录：

```
adapters/my-adapter/
├── adapter.yaml          # 命令模板 + CRD 类型 + 环境检查
├── agents/               # 4 个 agent prompt（可继承通用部分）
│   ├── coordinator.md
│   ├── env-checker.md
│   ├── test-executor.md
│   └── report-generator.md
├── known-patterns.md     # 领域特有失败模式
└── templates/
    ├── CLAUDE.md.template
    ├── AGENTS.md.template
    └── context.md.template
```

`adapter.yaml` 必须包含：

```yaml
name: my-adapter
version: "0.1"
description: "适配器描述"
commands:
  apply: "kubectl apply -f {{yaml_file}} -n {{namespace}}"
  wait_succeeded: "..."
  logs: "..."
  verify: "..."
resource_types: [MyResource]
env_checks:
  - description: "检查项描述"
    command: "kubectl get ..."
    pass_condition: "通过条件"
```

## 目录结构

```
jit-test-protocol/
├── skills/                     # Skill 命令入口
│   ├── jit-init/SKILL.md
│   ├── jit-status/SKILL.md
│   ├── jit-next/SKILL.md
│   └── jit-report/SKILL.md
├── protocol/                   # 核心方法论
│   ├── stages.yaml
│   ├── agent-roles.md
│   ├── quality-gates.md
│   └── known-patterns/
│       └── common.md
├── adapters/                   # 领域适配
│   └── tekton/
│       ├── adapter.yaml
│       ├── agents/
│       ├── known-patterns.md
│       └── templates/
├── opencode/                   # OpenCode 兼容
│   ├── agents/
│   ├── commands/
│   └── opencode.json.template
├── install.sh
├── uninstall.sh
└── README.md
```

## Claude Code vs OpenCode

| 特性 | Claude Code | OpenCode |
|------|------------|----------|
| 项目指令 | CLAUDE.md | AGENTS.md |
| Agent 定义 | .claude/agents/*.md | .opencode/agents/*.md |
| Skill 触发 | /jit-init | /jit-init |
| 自定义命令 | N/A | .opencode/commands/*.md |
| 配置文件 | N/A | opencode.json |

Skill 文件格式两者共享，安装脚本会根据检测到的工具自动配置。

## License

MIT
