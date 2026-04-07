#!/bin/bash
# OpenClaw 每日版本检查 + 飞书通知（中文摘要版）
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

# 3. 读取 CHANGELOG 中最新正式版本（跳过 beta 和 Unreleased）
CURRENT_VERSION=$(grep -m1 "^## [0-9]" "$REPO_DIR/CHANGELOG.md" \
  | grep -v "beta" | sed 's/^## //' | tr -d '[:space:]')

# 4. 读取最新提交信息
LATEST_COMMIT=$(git log --oneline -1 origin/main 2>/dev/null || git log --oneline -1)
COMMIT_DATE=$(git log -1 --format="%ad" --date=format:"%Y-%m-%d" origin/main 2>/dev/null \
  || git log -1 --format="%ad" --date=format:"%Y-%m-%d")

TODAY=$(TZ='Asia/Shanghai' date +%Y-%m-%d)

# 5. 判断是否有新版本
if [ "$CURRENT_VERSION" = "$LAST_VERSION" ]; then
  # ---- 无新版本：发简短日报 ----
  FEISHU_MD="## 📋 OpenClaw 每日版本检查｜${TODAY}

**当前最新版：** ${CURRENT_VERSION}
**最新提交：** \`${LATEST_COMMIT}\`

✅ 暂无新正式版本发布。"

else
  # ---- 有新版本：提取 changelog 并用 Claude 生成中文摘要 ----
  RAW_NOTES=$(awk "/^## ${CURRENT_VERSION}/{found=1; next} found && /^## /{exit} found && NF{print}" \
    "$REPO_DIR/CHANGELOG.md" | head -60)

  # 调用 claude 生成中文摘要（markdown 格式）
  SUMMARY=$(echo "$RAW_NOTES" | claude --print \
    "以下是 OpenClaw 项目 ${CURRENT_VERSION} 版本的英文 changelog，请用简洁的中文整理成更新摘要。
要求：
- 用 markdown 格式输出，分「重要变更」「新功能」「问题修复」三个二级标题（### ），没有的类别可省略
- 每条用「- 」列表格式
- 保留关键技术术语（如 Telegram、Matrix、Feishu 等）
- 总字数控制在 400 字以内
- 只输出摘要内容，不要其他说明" 2>/dev/null || echo "（摘要生成失败，请查看原始 changelog）")

  FEISHU_MD="## 🆕 OpenClaw 新版本发布！｜${TODAY}

**新版本：** ${CURRENT_VERSION}　　**上一版本：** ${LAST_VERSION:-首次检查}

---

${SUMMARY}

---

📌 [完整 changelog](https://docs.openclaw.ai/changelog)"

  # 更新已通知版本记录
  echo "$CURRENT_VERSION" > "$STATE_FILE"
fi

# 6. 发飞书消息（markdown 格式）
lark-cli im +messages-send \
  --user-id "$USER_OPEN_ID" \
  --markdown "$FEISHU_MD" \
  --as bot 2>&1

echo "✅ 通知已发送 | 版本: $CURRENT_VERSION | $(TZ='Asia/Shanghai' date)"
