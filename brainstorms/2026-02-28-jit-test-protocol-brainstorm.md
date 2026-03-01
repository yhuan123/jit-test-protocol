# JiT Test Protocol — Brainstorm

**Date**: 2026-02-28
**Topic**: 设计可安装的 JiT（Just-in-Time）测试工作流协议，兼容 Claude Code 和 OpenCode

---

## What We're Building

一个 **可安装的测试工作流协议仓库**（`jit-test-protocol`），让团队成员通过 Skill 命令驱动 8 阶段测试生命周期，适用于任何 K8s 资源的功能测试。

**核心理念**：Protocol（方法论）与 Adapter（领域知识）分离——Protocol 定义"如何测试"，Adapter 定义"测试什么"。

**目标用户**：使用 Claude Code 或 OpenCode 进行 K8s 资源测试的 QA 工程师。

---

## Why This Approach

### 选择 "Protocol Core + Skill Shell" 架构的原因

1. **Protocol 是稳定的方法论**——8 阶段生命周期（triage → brainstorm → plan → env_setup → execute → report → optimize → regression）经 merge-image-test 实战验证，与具体测试对象无关
2. **Adapter 可插拔**——Tekton 是第一个 Adapter，团队可以为 Argo Workflows、自定义 CRD 等添加新 Adapter 而不改核心 Protocol
3. **双工具兼容**——OpenCode 有专门兼容层，不污染 Claude Code 结构；利用 OpenCode 原生支持 CLAUDE.md fallback 和 .claude/skills/ 的特性
4. **Skill 驱动 > 纯配置驱动**——Skill 命令提供清晰的交互入口，降低上手门槛

### 未选择的方案

- **Flat Skills**：Protocol 逻辑散落在各 Skill 中，维护成本高
- **Monolithic Skill**：单个 SKILL.md 会膨胀到 2000+ 行，不可维护

---

## Key Decisions

### 1. 仓库结构

```
jit-test-protocol/
├── skills/                          # 用户入口（轻薄 shell）
│   ├── jit-init/SKILL.md           # 初始化测试项目
│   ├── jit-status/SKILL.md         # 查看生命周期状态
│   ├── jit-next/SKILL.md           # 推进下一阶段
│   └── jit-report/SKILL.md         # 汇编报告
├── protocol/                        # 核心逻辑（工具无关）
│   ├── stages.yaml                  # 8 阶段 + 质量门 + agent 角色
│   ├── agent-roles.md               # 4 种 agent 角色定义
│   ├── quality-gates.md             # 质量门检查清单
│   └── known-patterns/
│       └── common.md                # 通用 K8s 失败模式
├── adapters/                        # 领域适配
│   └── tekton/
│       ├── adapter.yaml             # Tekton 特有配置（镜像、CRD 类型等）
│       ├── agents/                  # Tekton 专用 agent prompt
│       │   ├── coordinator.md
│       │   ├── env-checker.md
│       │   ├── test-executor.md
│       │   └── report-generator.md
│       ├── known-patterns.md        # Tekton 特有失败模式
│       └── templates/
│           ├── CLAUDE.md.template   # 项目 CLAUDE.md 模板
│           ├── AGENTS.md.template   # 项目 AGENTS.md 模板（OpenCode）
│           └── context.md.template  # 跨 session 状态模板
├── opencode/                        # OpenCode 兼容层
│   ├── agents/                      # OpenCode agent 格式（YAML frontmatter）
│   │   ├── coordinator.md
│   │   ├── env-checker.md
│   │   ├── test-executor.md
│   │   └── report-generator.md
│   ├── commands/                    # OpenCode 自定义命令
│   │   ├── jit-init.md
│   │   ├── jit-status.md
│   │   └── jit-next.md
│   └── opencode.json.template      # OpenCode 配置模板
├── install.sh                       # 智能安装脚本
├── uninstall.sh                     # 卸载脚本
└── README.md
```

### 2. Skill 命令设计

| Skill | 触发词 | 功能 | 参数 |
|-------|--------|------|------|
| jit-init | `/jit-init` | 初始化测试项目 | adapter, test-object, kubeconfig, namespace |
| jit-status | `/jit-status` | 显示当前阶段和进度 | 无 |
| jit-next | `/jit-next` | 推进到下一阶段 | 可选：跳转到指定阶段 |
| jit-report | `/jit-report` | 生成测试报告 | 可选：format (markdown/json) |

### 3. 安装机制

```bash
# 安装
git clone https://github.com/yhuan123/jit-test-protocol.git ~/.jit-test-protocol
cd ~/.jit-test-protocol && ./install.sh

# install.sh 行为：
# 1. 检测已安装的 AI 工具（Claude Code / OpenCode / 两者都有）
# 2. Claude Code: ln -s skills/* → ~/.claude/skills/
# 3. OpenCode: ln -s skills/* → ~/.config/opencode/skills/
#              ln -s opencode/agents/* → ~/.config/opencode/agents/
#              ln -s opencode/commands/* → ~/.config/opencode/commands/
# 4. 验证安装成功

# 更新
cd ~/.jit-test-protocol && git pull

# 卸载
cd ~/.jit-test-protocol && ./uninstall.sh
```

### 4. OpenCode 兼容策略

| 特性 | Claude Code | OpenCode | 兼容方式 |
|------|------------|----------|----------|
| 项目指令 | CLAUDE.md | AGENTS.md (fallback: CLAUDE.md) | 生成两者 |
| Agent 定义 | .claude/agents/*.md | .opencode/agents/*.md (YAML frontmatter) | 维护两套格式 |
| Skill | .claude/skills/*/SKILL.md | .opencode/skills/*/SKILL.md | **共享**（格式兼容） |
| 自定义命令 | N/A | .opencode/commands/*.md | OpenCode 独有 |
| 配置文件 | N/A | opencode.json | OpenCode 独有 |

**关键发现**：Skill 文件格式两者兼容（都支持 .claude/skills/），这是共享的基础。

### 5. Agent 角色定义

| Agent | 职责 | 写集群 | 写文件 |
|-------|------|--------|--------|
| coordinator | 生命周期编排、委派任务、检查质量门 | 否 | 否 |
| env-checker | K8s 集群预检（CRD、namespace、镜像、storage 等） | 否 | 否 |
| test-executor | apply YAML、等待结果、收集日志、自动诊断 | 是 | 否 |
| report-generator | 汇编 Markdown 报告 | 否 | 否 |

### 6. Adapter 接口规范

每个 Adapter 必须提供：

```yaml
# adapter.yaml
name: tekton
version: "0.1"
description: "Tekton TaskRun/PipelineRun 测试适配器"

# Adapter 特有的执行命令
commands:
  apply: "kubectl apply -f {{yaml_file}}"
  wait: "kubectl wait --for=condition=Succeeded {{resource}} --timeout={{timeout}}s"
  logs: "kubectl logs -l tekton.dev/taskRun={{name}} --all-containers"
  verify: "kubectl get {{resource}} -o jsonpath='{.status.conditions[0].type}'"

# Adapter 特有的 CRD 类型
resource_types:
  - TaskRun
  - PipelineRun

# 需要预检的项目
env_checks:
  - "CRD tekton.dev 已安装"
  - "Hub Resolver 可用"
  - "目标 namespace 存在"
```

---

## Resolved Questions

- **使用入口**: Skill 命令驱动（/jit-init, /jit-status 等）
- **测试对象范围**: K8s 资源通用，Tekton 为第一个 Adapter
- **安装方式**: git clone + install.sh 软链接
- **第一版范围**: 包含 Tekton Adapter
- **架构方案**: Protocol Core + Skill Shell（方案 B）
- **OpenCode 兼容**: Skill 共享 + Agent/Commands 维护双格式
- **路径引用**: 全量链接到 ~/.jit-test-protocol，Skill 用绝对路径 ~/.jit-test-protocol/protocol/ 引用
- **Adapter 策略**: 单 Adapter 绑定（每项目一个 Adapter，多资源类型创建多项目）
