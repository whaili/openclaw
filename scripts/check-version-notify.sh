#!/bin/bash
# OpenClaw 每日版本检查 + 飞书通知
# 用法: ./scripts/check-version-notify.sh

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
USER_OPEN_ID="ou_37a31fb48de34cc1cf02d1bb952cbc6d"
STATE_FILE="$REPO_DIR/.last-checked-version"

cd "$REPO_DIR"

# 1. 拉取最新代码
git fetch origin 2>&1 | grep -v "^$" || true

# 2. 读取上次记录的版本
LAST_VERSION=""
if [ -f "$STATE_FILE" ]; then
  LAST_VERSION=$(cat "$STATE_FILE")
fi

# 3. 读取当前 CHANGELOG 中最新正式版本（非 beta、非 Unreleased）
CURRENT_VERSION=$(grep -m1 "^## [0-9]" "$REPO_DIR/CHANGELOG.md" | sed 's/^## //' | tr -d '[:space:]')

# 4. 读取最新提交信息
LATEST_COMMIT=$(git log --oneline -1 origin/main 2>/dev/null || git log --oneline -1)
COMMIT_DATE=$(git log -1 --format="%ad" --date=format:"%Y-%m-%d" origin/main 2>/dev/null || git log -1 --format="%ad" --date=format:"%Y-%m-%d")

# 5. 判断是否有新版本
if [ "$CURRENT_VERSION" = "$LAST_VERSION" ]; then
  # 无新版本，发简短通知
  MSG="📋 OpenClaw 版本检查（$(date +%Y-%m-%d)）\n\n当前最新版：$CURRENT_VERSION\n最新提交：$LATEST_COMMIT\n\n无新正式版本发布。"
else
  # 有新版本，提取 release notes
  RELEASE_NOTES=$(awk "/^## $CURRENT_VERSION/{found=1; next} found && /^## /{exit} found{print}" "$REPO_DIR/CHANGELOG.md" | head -30)
  MSG="🆕 OpenClaw 新版本发布！（$(date +%Y-%m-%d)）\n\n新版本：$CURRENT_VERSION\n上次版本：${LAST_VERSION:-首次检查}\n\n📝 更新摘要：\n$RELEASE_NOTES"
  # 更新记录
  echo "$CURRENT_VERSION" > "$STATE_FILE"
fi

# 6. 发飞书消息
lark-cli im +messages-send \
  --user-id "$USER_OPEN_ID" \
  --text "$MSG" \
  --as bot 2>&1

echo "✅ 通知已发送 | 版本: $CURRENT_VERSION | $(date)"
