---
title: "feat: Implement JiT Test Protocol Repository"
type: feat
status: active
date: 2026-02-28
origin: brainstorms/2026-02-28-jit-test-protocol-brainstorm.md
---

# feat: Implement JiT Test Protocol Repository

## Overview

构建 `jit-test-protocol`——一个可安装的 JiT（Just-in-Time）测试工作流协议，通过 Skill 命令驱动 8 阶段测试生命周期，适用于任何 K8s 资源的功能测试。支持 Claude Code 和 OpenCode 双工具。

核心架构：**Protocol Core + Skill Shell + Adapter**。Protocol 定义通用方法论（阶段、质量门、agent 角色），Adapter 提供领域知识（Tekton 命令、CRD 类型、环境检查项），Skill 作为用户交互入口。

## Problem Statement / Motivation

当前 Tekton 测试生命周期框架（`~/Claude/templates/tekton-test-project/`）存在以下限制：

1. **Tekton 强绑定**——env-checker 的 7 项检查、质量门文本、Hub Resolver 引用全部硬编码 Tekton 概念，无法用于 Argo Workflows 或其他 K8s CRD
2. **安装靠手动复制**——新项目需手动 cp 模板目录、替换占位符，团队其他成员无法轻松获取
3. **仅支持 Claude Code**——OpenCode 用户无法使用（Agent 格式不同、缺少 opencode.json 配置）
4. **无版本管理**——模板散落在本地目录，无法 git pull 更新

## Proposed Solution

创建一个 GitHub 仓库 `yhuan123/jit-test-protocol`，包含：

```
jit-test-protocol/
├── skills/                          # 用户入口（4 个轻薄 Skill）
│   ├── jit-init/SKILL.md
│   ├── jit-status/SKILL.md
│   ├── jit-next/SKILL.md
│   └── jit-report/SKILL.md
├── protocol/                        # 核心方法论（工具无关）
│   ├── stages.yaml                  # 8 阶段 + 质量门 + agent 角色
│   ├── agent-roles.md               # 4 种 agent 角色定义
│   ├── quality-gates.md             # 通用质量门检查清单
│   └── known-patterns/
│       └── common.md                # 通用 K8s 失败模式（5 个）
├── adapters/                        # 领域适配
│   └── tekton/
│       ├── adapter.yaml             # 命令模板 + CRD 类型 + 环境检查
│       ├── agents/                  # 4 个 Tekton 专用 agent prompt
│       │   ├── coordinator.md
│       │   ├── env-checker.md
│       │   ├── test-executor.md
│       │   └── report-generator.md
│       ├── known-patterns.md        # Tekton 特有失败模式（3 个）
│       └── templates/
│           ├── CLAUDE.md.template
│           ├── AGENTS.md.template
│           └── context.md.template
├── opencode/                        # OpenCode 兼容层
│   ├── agents/                      # OpenCode 格式 agent 定义
│   │   ├── coordinator.md
│   │   ├── env-checker.md
│   │   ├── test-executor.md
│   │   └── report-generator.md
│   ├── commands/                    # OpenCode 自定义命令
│   │   ├── jit-init.md
│   │   ├── jit-status.md
│   │   └── jit-next.md
│   └── opencode.json.template
├── install.sh
├── uninstall.sh
└── README.md
```

## Technical Approach

### Architecture

```
┌─────────────────────────────────────────────┐
│                  User                        │
│         /jit-init  /jit-next  ...           │
├─────────────────────────────────────────────┤
│              Skill Shell Layer               │
│  (skills/jit-init/SKILL.md 等)              │
│  - 参数收集、路由、用户交互                    │
│  - 引用 ~/.jit-test-protocol/ 绝对路径        │
├─────────────────────────────────────────────┤
│             Protocol Core Layer              │
│  (protocol/stages.yaml + agent-roles.md)    │
│  - 8 阶段状态机                               │
│  - 通用质量门                                 │
│  - Agent 角色定义（职责 + 权限边界）            │
│  - 通用 known-patterns                       │
├─────────────────────────────────────────────┤
│              Adapter Layer                   │
│  (adapters/tekton/)                         │
│  - 领域命令模板（kubectl apply/wait/logs）     │
│  - CRD 类型列表                               │
│  - 环境检查项                                 │
│  - Agent prompt 特化                          │
│  - 领域 known-patterns                       │
│  - 项目模板（CLAUDE.md / AGENTS.md / context）│
├─────────────────────────────────────────────┤
│           Tool Compatibility Layer           │
│  Claude Code: .claude/skills/, agents/       │
│  OpenCode: .opencode/skills/, agents/,       │
│            commands/, opencode.json          │
└─────────────────────────────────────────────┘
```

### Implementation Phases

#### Phase 1: Protocol Core（基础骨架）

从现有 `~/Claude/templates/tekton-test-project/` 提取通用部分。

**Tasks:**

- [ ] `protocol/stages.yaml` — 从 `lifecycle/stages.yaml` 提取，去掉所有 Tekton 特定的质量门文本和 action 描述，改为通用 K8s 语言。保留 8 阶段结构、parallel_strategy、optimize 6 维回顾、global 配置块。添加 `adapter_overrides` 机制让 Adapter 可以扩展质量门
- [ ] `protocol/agent-roles.md` — 从 4 个 agent `.md` 文件提取角色定义（职责、权限边界表、通用行为规则），不含具体 prompt 实现
- [ ] `protocol/quality-gates.md` — 汇总所有阶段的通用质量门为一个可引用文档，标注哪些是必选（MUST）哪些是可选（SHOULD）
- [ ] `protocol/known-patterns/common.md` — 从 `known-patterns.md` 提取 Pattern-001~005（x509、ImagePullBackOff、docker.io timeout、401/403、StorageClass missing）

**文件清单（4 个新建）：**
```
protocol/stages.yaml
protocol/agent-roles.md
protocol/quality-gates.md
protocol/known-patterns/common.md
```

**Quality gate:** 每个阶段有通用质量门文本，无 Tekton 关键词。Adapter 扩展点已标注。

---

#### Phase 2: Tekton Adapter（领域适配）

从现有模板提取 Tekton 特有内容。

**Tasks:**

- [ ] `adapters/tekton/adapter.yaml` — 新建，定义 Tekton 命令模板：
  ```yaml
  name: tekton
  version: "0.1"
  description: "Tekton TaskRun/PipelineRun 测试适配器"
  commands:
    apply: "kubectl apply -f {{yaml_file}}"
    wait: "kubectl wait --for=condition=Succeeded {{resource}} --timeout={{timeout}}s"
    logs: "kubectl logs -l tekton.dev/taskRun={{name}} --all-containers"
    verify: "kubectl get {{resource}} -o jsonpath='{.status.conditions[0].type}'"
    cleanup: "kubectl delete {{resource}} --ignore-not-found"
  resource_types: [TaskRun, PipelineRun]
  env_checks:
    - "CRD tasks.tekton.dev 已安装"
    - "CRD pipelines.tekton.dev 已安装"
    - "Hub Resolver deployment 运行中"
    - "tekton-pipelines-controller 运行中"
    - "目标 Task/Pipeline 可解析"
  default_image: "152-231-registry.alauda.cn:60070/devops/tektoncd/hub/run-script:v3.21"
  additional_fields:
    - name: hub_resolver_ref
      description: "Hub Resolver 引用（如 catalog/task/merge-image/0.1）"
      required: true
  ```
- [ ] `adapters/tekton/agents/coordinator.md` — 从 `~/Claude/templates/.claude/agents/coordinator.md` 复制，注入 Tekton 特有的 session 启动协议和 Hub Resolver 引用逻辑
- [ ] `adapters/tekton/agents/env-checker.md` — 从模板复制，保留 7 项 Tekton 特有检查清单
- [ ] `adapters/tekton/agents/test-executor.md` — 从模板复制，保留 TaskRun/PipelineRun apply + 验证工具差异化原则
- [ ] `adapters/tekton/agents/report-generator.md` — 从模板复制（几乎无改动，最通用的 agent）
- [ ] `adapters/tekton/known-patterns.md` — Pattern-006（Hub Resolver failure）+ Pattern-007/008（crane/merge-image 特有）
- [ ] `adapters/tekton/templates/CLAUDE.md.template` — 从 `CLAUDE.md.template` 重构：Session 启动读取 adapter.yaml、引用 `~/.jit-test-protocol/protocol/` 路径
- [ ] `adapters/tekton/templates/AGENTS.md.template` — CLAUDE.md.template 的 OpenCode 变体（内容相同，格式调整）
- [ ] `adapters/tekton/templates/context.md.template` — 从 `context.md.template` 复制，环境状态行添加 Tekton 特有项（Hub Resolver、Operator 版本）

**文件清单（9 个新建）：**
```
adapters/tekton/adapter.yaml
adapters/tekton/agents/coordinator.md
adapters/tekton/agents/env-checker.md
adapters/tekton/agents/test-executor.md
adapters/tekton/agents/report-generator.md
adapters/tekton/known-patterns.md
adapters/tekton/templates/CLAUDE.md.template
adapters/tekton/templates/AGENTS.md.template
adapters/tekton/templates/context.md.template
```

**Quality gate:** `jit-init --adapter=tekton` 可生成功能完整的项目目录，与现有 merge-image-test 的 CLAUDE.md 结构等价。

---

#### Phase 3: Skills（用户入口）

4 个 Skill 文件，格式同时兼容 Claude Code 和 OpenCode。

**Tasks:**

- [ ] `skills/jit-init/SKILL.md` — 基于 `alauda-test-project.md` 重写：
  - 参数：adapter（必选）、test-object、kubeconfig、namespace、project-dir
  - 流程：收集参数 → 验证 adapter 存在 → 复制 adapter/templates/ → 替换占位符 → 复制 adapter/agents/ 到 .claude/agents/ → 初始化 context.md（stage=triage）→ 验证无残留占位符
  - OpenCode 额外动作：复制 opencode/agents/ 到 .opencode/agents/，生成 opencode.json
- [ ] `skills/jit-status/SKILL.md` — 基于 `test-status.md` 重写：
  - 读取 CWD 的 memory/context.md + lifecycle/stages.yaml
  - 显示 ASCII 生命周期图（保留现有图标集）
  - 显示当前阶段、阻塞问题、用例统计
- [ ] `skills/jit-next/SKILL.md` — 全新：
  - 读取 context.md 确定当前阶段
  - 验证当前阶段质量门已通过
  - 如果下一阶段需要 human_approval，触发审批流程
  - 更新 context.md 推进到下一阶段
  - 根据阶段调度对应 agent（coordinator/env-checker/test-executor/report-generator）
- [ ] `skills/jit-report/SKILL.md` — 全新：
  - 读取 testdata/ 下所有结果
  - 委托 report-generator agent 汇编报告
  - 输出到 reports/YYYY-MM-DD-test-results.md

**文件清单（4 个新建）：**
```
skills/jit-init/SKILL.md
skills/jit-status/SKILL.md
skills/jit-next/SKILL.md
skills/jit-report/SKILL.md
```

**Quality gate:** 每个 Skill 有正确的 YAML frontmatter（name 满足 `^[a-z0-9]+(-[a-z0-9]+)*$`），description 明确，在 Claude Code 中可通过 `/jit-init` 触发。

---

#### Phase 4: OpenCode 兼容层

为 OpenCode 用户提供原生体验。

**Tasks:**

- [ ] `opencode/agents/coordinator.md` — 从 `adapters/tekton/agents/coordinator.md` 转换为 OpenCode YAML frontmatter 格式：
  ```yaml
  ---
  description: 生命周期编排 agent
  mode: subagent
  temperature: 0.1
  tools:
    write: false
    bash: false
  ---
  ```
- [ ] `opencode/agents/env-checker.md` — 同上转换，`bash` 权限开启但约束为只读命令
- [ ] `opencode/agents/test-executor.md` — 同上转换，`bash: true`, `write: true`
- [ ] `opencode/agents/report-generator.md` — 同上转换，`bash: false`, `write: true`
- [ ] `opencode/commands/jit-init.md` — OpenCode 自定义命令格式（YAML frontmatter + template）：
  ```yaml
  ---
  description: 初始化 JiT 测试项目
  agent: build
  ---
  ```
- [ ] `opencode/commands/jit-status.md` — 同上
- [ ] `opencode/commands/jit-next.md` — 同上
- [ ] `opencode/opencode.json.template` — OpenCode 项目配置模板：
  ```json
  {
    "$schema": "https://opencode.ai/config.json",
    "instructions": ["AGENTS.md", "lifecycle/stages.yaml"]
  }
  ```

**文件清单（8 个新建）：**
```
opencode/agents/coordinator.md
opencode/agents/env-checker.md
opencode/agents/test-executor.md
opencode/agents/report-generator.md
opencode/commands/jit-init.md
opencode/commands/jit-status.md
opencode/commands/jit-next.md
opencode/opencode.json.template
```

**Quality gate:** OpenCode agent 文件有合法 YAML frontmatter，command 文件可被 OpenCode `/jit-init` 触发。

---

#### Phase 5: 安装系统 + 文档

**Tasks:**

- [ ] `install.sh` — 智能安装脚本：
  1. 检测已安装工具（`which claude` / `which opencode` / 检测 `~/.claude/` / `~/.config/opencode/`）
  2. Claude Code: `ln -sf` skills 到 `~/.claude/skills/`
  3. OpenCode: `ln -sf` skills 到 `~/.config/opencode/skills/`，agents 到 `~/.config/opencode/agents/`，commands 到 `~/.config/opencode/commands/`
  4. 设置 `JIT_PROTOCOL_HOME` 环境变量（写入 ~/.zshrc 或 ~/.bashrc）——作为备选引用路径
  5. 验证：列出所有创建的软链接
  6. 显示安装成功信息和快速开始指南
- [ ] `uninstall.sh` — 清理所有软链接，移除环境变量
- [ ] `README.md` — 项目文档：
  - 一句话介绍
  - 安装/卸载
  - Quick Start（初始化第一个 Tekton 测试项目）
  - Skill 命令参考
  - 架构说明（Protocol + Adapter）
  - 创建新 Adapter 指南
  - Claude Code vs OpenCode 使用差异

**文件清单（3 个新建）：**
```
install.sh
uninstall.sh
README.md
```

---

#### Phase 6: 验证 + 发布

**Tasks:**

- [ ] 在 merge-image-test 项目上验证兼容性——用 `jit-init --adapter=tekton` 生成新项目，对比与现有结构
- [ ] 验证 Skill 命令在 Claude Code 中可触发
- [ ] `git init` + 推送到 `https://github.com/yhuan123/jit-test-protocol`
- [ ] 用 README 中的 Quick Start 流程做端到端验证

## Alternative Approaches Considered

(see brainstorm: brainstorms/2026-02-28-jit-test-protocol-brainstorm.md)

1. **Flat Skills（方案 A）**——Protocol 逻辑散落在各 Skill 中，维护成本高，pass/fail 模式无法共享
2. **Monolithic Skill（方案 C）**——单 SKILL.md 会膨胀到 2000+ 行，不可维护，不支持多 Adapter

## Acceptance Criteria

### Functional Requirements

- [ ] `install.sh` 可在 macOS 上一键安装，创建正确的软链接
- [ ] `/jit-init --adapter=tekton` 可生成完整项目目录（CLAUDE.md + agents/ + lifecycle/ + memory/）
- [ ] `/jit-status` 可读取项目状态并显示 ASCII 生命周期图
- [ ] `/jit-next` 可推进阶段，检查质量门，触发审批
- [ ] `/jit-report` 可汇编 Markdown 报告
- [ ] 生成的项目结构与现有 merge-image-test 等价（功能不退化）
- [ ] OpenCode 用户可通过 `/jit-init` 命令使用

### Non-Functional Requirements

- [ ] 所有 Skill 的 YAML frontmatter 合法（name 匹配 `^[a-z0-9]+(-[a-z0-9]+)*$`）
- [ ] 无硬编码的绝对路径（除 `~/.jit-test-protocol/`）
- [ ] Adapter 接口清晰：任何人可参照 `adapters/tekton/` 创建新 Adapter
- [ ] README 提供完整的 Quick Start 和 Adapter 开发指南

### Quality Gates

- [ ] `grep -r '{{' protocol/` 返回空（Protocol 无未替换占位符）
- [ ] `grep -r 'tekton\|Tekton\|TaskRun\|PipelineRun' protocol/` 返回空（Protocol 无 Tekton 关键词）
- [ ] install.sh 在全新 macOS 环境可执行（无额外依赖）

## Dependencies & Prerequisites

- GitHub 账户 `yhuan123` 可访问并可创建仓库
- 现有模板文件 `~/Claude/templates/tekton-test-project/` 完整
- macOS with zsh（install.sh 目标平台）

## Risk Analysis & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| OpenCode 格式兼容问题 | 中 | 中 | Skills 格式已确认共享；Agent 维护双格式 |
| Skill 引用路径在不同机器上不同 | 低 | 高 | 使用 `~/.jit-test-protocol/` 标准路径 |
| Adapter 接口过度设计 | 中 | 低 | 先实现 Tekton，接口基于实际需求而非假设 |
| 现有 merge-image-test 功能退化 | 低 | 高 | Phase 6 做回归对比验证 |

## File Inventory Summary

| Phase | New Files | Source |
|-------|-----------|--------|
| Phase 1: Protocol Core | 4 | 从现有模板提取通用部分 |
| Phase 2: Tekton Adapter | 9 | 从现有模板提取 Tekton 部分 |
| Phase 3: Skills | 4 | 2 个重写 + 2 个全新 |
| Phase 4: OpenCode | 8 | 从 Phase 2/3 转换格式 |
| Phase 5: Install + Docs | 3 | 全新 |
| **Total** | **28** | |

## Sources & References

### Origin

- **Brainstorm document:** [brainstorms/2026-02-28-jit-test-protocol-brainstorm.md](../../brainstorms/2026-02-28-jit-test-protocol-brainstorm.md)
  - Key decisions: Protocol+Adapter 架构、Skill 命令驱动、git clone+软链接安装、单 Adapter 绑定

### Internal References

- 现有模板: `~/Claude/templates/tekton-test-project/`
- 现有 init skill: `~/Claude/skills/alauda-test-project.md`
- 现有 status skill: `~/Claude/skills/test-status.md`
- 实战项目: `/Users/alauda/Projects/Tekton/merge-image-test/`

### External References

- OpenCode Rules: https://opencode.ai/docs/rules/
- OpenCode Agents: https://opencode.ai/docs/agents/
- OpenCode Skills: https://opencode.ai/docs/skills/
- OpenCode Commands: https://opencode.ai/docs/commands/
