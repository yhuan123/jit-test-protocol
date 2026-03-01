---
name: jit-init
description: 初始化 JiT 测试项目（从 Protocol + Adapter 模板生成项目骨架）
license: MIT
compatibility: opencode
---

# /jit-init — 初始化 JiT 测试项目

## 功能

从 `~/.jit-test-protocol/` 的 Protocol + Adapter 模板生成一个新的测试项目目录，包含 CLAUDE.md（或 AGENTS.md）、agent 定义、生命周期配置和跨 session 状态文件。

## 参数

| 参数 | 必选 | 说明 | 示例 |
|------|------|------|------|
| `adapter` | 是 | 适配器名称 | `tekton` |
| `test-object` | 是 | 测试对象标识 | `catalog/task/merge-image/0.1` |
| `kubeconfig` | 是 | kubeconfig 路径 | `~/Downloads/kubeconf-arm.yaml` |
| `namespace` | 是 | 测试 namespace | `testing-merge-image` |
| `project-dir` | 否 | 项目目录路径（默认 CWD） | `~/Projects/Tekton/my-test` |

> Adapter 可能定义额外必选参数（如 Tekton 的 `hub_resolver_ref`），在第 3 步中收集。

## 执行步骤

### 1. 收集参数

使用 AskUserQuestion 收集缺失的必选参数。对于已通过命令行提供的参数，不重复询问。

### 2. 验证 Adapter 存在

```bash
ls ~/.jit-test-protocol/adapters/$ADAPTER/adapter.yaml
```

如果不存在，列出可用 Adapter：
```bash
ls ~/.jit-test-protocol/adapters/
```

### 3. 收集 Adapter 额外参数

读取 `~/.jit-test-protocol/adapters/$ADAPTER/adapter.yaml` 的 `additional_fields`，收集必选字段。

### 4. 创建项目目录

```bash
PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"

# 检查目录是否已存在
if [ -d "$PROJECT_DIR/lifecycle" ]; then
  echo "项目已存在，是否覆盖？"
  # 等待用户确认
fi

# 创建目录结构
mkdir -p "$PROJECT_DIR"/{brainstorms,plans,testdata,reports,memory,lifecycle,.claude/agents}

# 复制 Protocol stages.yaml 到项目
cp ~/.jit-test-protocol/protocol/stages.yaml "$PROJECT_DIR/lifecycle/stages.yaml"

# 复制 Adapter 模板
cp ~/.jit-test-protocol/adapters/$ADAPTER/templates/CLAUDE.md.template "$PROJECT_DIR/CLAUDE.md"
cp ~/.jit-test-protocol/adapters/$ADAPTER/templates/context.md.template "$PROJECT_DIR/memory/context.md"

# 复制 Adapter agents
cp ~/.jit-test-protocol/adapters/$ADAPTER/agents/*.md "$PROJECT_DIR/.claude/agents/"
```

### 5. 替换占位符

对所有模板文件执行占位符替换：

```bash
# 替换列表
# {{PROJECT_NAME}} → $PROJECT_NAME
# {{TEST_OBJECT}} → $TEST_OBJECT
# {{KUBECONFIG_PATH}} → $KUBECONFIG
# {{NAMESPACE}} → $NAMESPACE
# {{ADAPTER_NAME}} → $ADAPTER
# {{CREATED_AT}} → $(date +%Y-%m-%d)
# {{CURRENT_STAGE}} → triage
# {{ADDITIONAL_NOTES}} → (空)
# Adapter 额外字段（如 {{HUB_RESOLVER_REF}}）

find "$PROJECT_DIR" -type f \( -name "*.md" -o -name "*.yaml" \) -exec sed -i '' \
  -e "s|{{PROJECT_NAME}}|$PROJECT_NAME|g" \
  -e "s|{{TEST_OBJECT}}|$TEST_OBJECT|g" \
  ... {} +
```

### 6. OpenCode 兼容（如检测到 OpenCode）

如果 `~/.config/opencode/` 存在：

```bash
# 复制 AGENTS.md
cp ~/.jit-test-protocol/adapters/$ADAPTER/templates/AGENTS.md.template "$PROJECT_DIR/AGENTS.md"
# 同样替换占位符

# 复制 OpenCode agents
mkdir -p "$PROJECT_DIR/.opencode/agents"
cp ~/.jit-test-protocol/opencode/agents/*.md "$PROJECT_DIR/.opencode/agents/"

# 生成 opencode.json
cp ~/.jit-test-protocol/opencode/opencode.json.template "$PROJECT_DIR/opencode.json"
```

### 7. 验证

```bash
# 检查是否有未替换的占位符
UNREPLACED=$(grep -r '{{' "$PROJECT_DIR" --include="*.md" --include="*.yaml" | grep -v 'DATE' | grep -v 'topic' | grep -v 'TC_ID' | grep -v 'CASE_COUNT')
if [ -n "$UNREPLACED" ]; then
  echo "WARNING: 发现未替换的占位符："
  echo "$UNREPLACED"
fi

# 验证关键文件存在
for f in CLAUDE.md lifecycle/stages.yaml memory/context.md .claude/agents/coordinator.md; do
  [ -f "$PROJECT_DIR/$f" ] && echo "✅ $f" || echo "❌ $f MISSING"
done
```

### 8. 输出结果

```
✅ JiT 测试项目初始化完成！

📁 项目路径: $PROJECT_DIR
🎯 测试对象: $TEST_OBJECT
🔧 Adapter: $ADAPTER
☸️  集群: $KUBECONFIG
📦 Namespace: $NAMESPACE
📊 当前阶段: triage

下一步: 进入项目目录，开始 triage 阶段。
或使用 /jit-status 查看项目状态。
```
