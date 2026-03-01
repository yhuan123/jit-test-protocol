#!/bin/bash
# JiT Test Protocol — 卸载脚本
# 清理所有安装的软链接

set -e

echo "╭──────────────────────────────────────╮"
echo "│   JiT Test Protocol — 卸载          │"
echo "╰──────────────────────────────────────╯"
echo ""

removed=0

# ── 清理 Claude Code Skills ──
if [ -d "$HOME/.claude/skills" ]; then
  echo "清理 Claude Code Skills..."
  for link in "$HOME/.claude/skills"/jit-*/; do
    if [ -L "$link" ]; then
      echo "   🗑️  $(basename "$link")"
      rm "$link"
      removed=$((removed + 1))
    fi
  done
fi

# ── 清理 OpenCode Skills ──
if [ -d "$HOME/.config/opencode/skills" ]; then
  echo "清理 OpenCode Skills..."
  for link in "$HOME/.config/opencode/skills"/jit-*/; do
    if [ -L "$link" ]; then
      echo "   🗑️  $(basename "$link")"
      rm "$link"
      removed=$((removed + 1))
    fi
  done
fi

# ── 清理 OpenCode Agents ──
if [ -d "$HOME/.config/opencode/agents" ]; then
  echo "清理 OpenCode Agents..."
  for agent in coordinator env-checker test-executor report-generator; do
    link="$HOME/.config/opencode/agents/$agent.md"
    if [ -L "$link" ]; then
      echo "   🗑️  $agent.md"
      rm "$link"
      removed=$((removed + 1))
    fi
  done
fi

# ── 清理 OpenCode Commands ──
if [ -d "$HOME/.config/opencode/commands" ]; then
  echo "清理 OpenCode Commands..."
  for link in "$HOME/.config/opencode/commands"/jit-*.md; do
    if [ -L "$link" ]; then
      echo "   🗑️  $(basename "$link")"
      rm "$link"
      removed=$((removed + 1))
    fi
  done
fi

# ── 清理标准位置软链接 ──
if [ -L "$HOME/.jit-test-protocol" ]; then
  echo "清理 ~/.jit-test-protocol 软链接..."
  rm "$HOME/.jit-test-protocol"
  removed=$((removed + 1))
fi

echo ""
if [ $removed -gt 0 ]; then
  echo "✅ 已清理 $removed 个软链接"
else
  echo "ℹ️  未发现需要清理的软链接"
fi

echo ""
echo "ℹ️  仓库本身未删除。如需完全移除："
echo "   rm -rf $(cd "$(dirname "$0")" && pwd)"
