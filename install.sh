#!/bin/bash
# JiT Test Protocol — 安装脚本
# 用法: git clone https://github.com/yhuan123/jit-test-protocol.git ~/.jit-test-protocol
#       cd ~/.jit-test-protocol && ./install.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/.jit-test-protocol"

echo "╭──────────────────────────────────────╮"
echo "│   JiT Test Protocol — 安装          │"
echo "╰──────────────────────────────────────╯"
echo ""

# ── 1. 检查仓库位置 ──
if [ "$SCRIPT_DIR" != "$INSTALL_DIR" ]; then
  echo "⚠️  仓库不在标准位置 (~/.jit-test-protocol)"
  echo "   当前位置: $SCRIPT_DIR"
  echo ""
  read -p "是否创建软链接到 $INSTALL_DIR? [Y/n] " answer
  if [ "${answer:-Y}" = "Y" ] || [ "${answer:-y}" = "y" ]; then
    ln -sf "$SCRIPT_DIR" "$INSTALL_DIR"
    echo "✅ 已创建: $INSTALL_DIR → $SCRIPT_DIR"
  else
    echo "ℹ️  跳过。请注意 Skill 中的路径引用使用 ~/.jit-test-protocol/"
  fi
  echo ""
fi

# ── 2. 检测已安装的 AI 工具 ──
CLAUDE_CODE=false
OPENCODE=false

if [ -d "$HOME/.claude" ]; then
  CLAUDE_CODE=true
  echo "✅ 检测到 Claude Code (~/.claude/)"
fi

if [ -d "$HOME/.config/opencode" ]; then
  OPENCODE=true
  echo "✅ 检测到 OpenCode (~/.config/opencode/)"
fi

if ! $CLAUDE_CODE && ! $OPENCODE; then
  echo "⚠️  未检测到 Claude Code 或 OpenCode"
  echo "   将创建 Claude Code 目录结构"
  mkdir -p "$HOME/.claude/skills"
  CLAUDE_CODE=true
fi

echo ""

# ── 3. 安装 Skills ──
install_skills() {
  local target_dir="$1"
  local tool_name="$2"

  echo "📦 安装 Skills → $target_dir"
  mkdir -p "$target_dir"

  for skill_dir in "$INSTALL_DIR/skills"/*/; do
    skill_name=$(basename "$skill_dir")
    target="$target_dir/$skill_name"

    if [ -L "$target" ]; then
      rm "$target"
    elif [ -d "$target" ]; then
      echo "   ⚠️  $skill_name 已存在（非软链接），跳过"
      continue
    fi

    ln -sf "$skill_dir" "$target"
    echo "   ✅ $skill_name → $target"
  done
}

if $CLAUDE_CODE; then
  install_skills "$HOME/.claude/skills" "Claude Code"
fi

if $OPENCODE; then
  install_skills "$HOME/.config/opencode/skills" "OpenCode"

  # 安装 OpenCode agents
  echo ""
  echo "📦 安装 OpenCode Agents → ~/.config/opencode/agents/"
  mkdir -p "$HOME/.config/opencode/agents"
  for agent_file in "$INSTALL_DIR/opencode/agents"/*.md; do
    agent_name=$(basename "$agent_file")
    target="$HOME/.config/opencode/agents/$agent_name"
    ln -sf "$agent_file" "$target"
    echo "   ✅ $agent_name"
  done

  # 安装 OpenCode commands
  echo ""
  echo "📦 安装 OpenCode Commands → ~/.config/opencode/commands/"
  mkdir -p "$HOME/.config/opencode/commands"
  for cmd_file in "$INSTALL_DIR/opencode/commands"/*.md; do
    cmd_name=$(basename "$cmd_file")
    target="$HOME/.config/opencode/commands/$cmd_name"
    ln -sf "$cmd_file" "$target"
    echo "   ✅ $cmd_name"
  done
fi

# ── 4. 验证 ──
echo ""
echo "╭──────────────────────────────────────╮"
echo "│   验证安装                           │"
echo "╰──────────────────────────────────────╯"

errors=0

# 验证核心文件
for f in protocol/stages.yaml protocol/agent-roles.md protocol/known-patterns/common.md; do
  if [ -f "$INSTALL_DIR/$f" ]; then
    echo "✅ $f"
  else
    echo "❌ $f — 缺失！"
    errors=$((errors + 1))
  fi
done

# 验证 Adapter
for adapter_dir in "$INSTALL_DIR/adapters"/*/; do
  adapter_name=$(basename "$adapter_dir")
  if [ -f "$adapter_dir/adapter.yaml" ]; then
    echo "✅ Adapter: $adapter_name"
  else
    echo "❌ Adapter: $adapter_name — adapter.yaml 缺失！"
    errors=$((errors + 1))
  fi
done

# 验证软链接
echo ""
if $CLAUDE_CODE; then
  for skill_dir in "$HOME/.claude/skills"/jit-*/; do
    if [ -L "$skill_dir" ]; then
      echo "✅ Skill 链接: $(basename "$skill_dir")"
    fi
  done
fi

if [ $errors -eq 0 ]; then
  echo ""
  echo "╭──────────────────────────────────────╮"
  echo "│   ✅ 安装成功！                      │"
  echo "╰──────────────────────────────────────╯"
  echo ""
  echo "🚀 快速开始:"
  echo "   1. 在 Claude Code 或 OpenCode 中输入 /jit-init"
  echo "   2. 按提示填写 adapter、测试对象、集群信息"
  echo "   3. 使用 /jit-status 查看进度"
  echo "   4. 使用 /jit-next 推进阶段"
  echo ""
  echo "📋 可用 Adapter:"
  for adapter_dir in "$INSTALL_DIR/adapters"/*/; do
    echo "   - $(basename "$adapter_dir")"
  done
  echo ""
  echo "📖 更新: cd $INSTALL_DIR && git pull"
else
  echo ""
  echo "⚠️  安装完成，但有 $errors 个错误，请检查。"
fi
