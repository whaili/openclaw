#!/bin/bash
# OpenClaw 每日版本检查 + 飞书通知（中文摘要版）
# 用法: ./scripts/check-version-notify.sh

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
USER_OPEN_ID="ou_37a31fb48de34cc1cf02d1bb952cbc6d"
STATE_FILE="$REPO_DIR/.last-checked-version"

cd "$REPO_DIR"

# 1. 从 npm registry 获取最新正式版本（最权威来源，不依赖本地 git 同步进度）
CURRENT_VERSION=$(curl -sf https://registry.npmjs.org/openclaw/latest \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['version'])" 2>/dev/null || echo "")

if [ -z "$CURRENT_VERSION" ]; then
  echo "❌ 无法获取 npm 版本，跳过通知" >&2
  exit 1
fi

# 2. 同步本地 repo（用于获取 changelog 内容）
git fetch origin 2>/dev/null || true

# 3. 读取上次已通知的版本
LAST_VERSION=""
if [ -f "$STATE_FILE" ]; then
  LAST_VERSION=$(cat "$STATE_FILE" | tr -d '[:space:]')
fi

# 4. 最新提交信息
LATEST_COMMIT=$(git log --oneline -1 origin/main 2>/dev/null || git log --oneline -1)

TODAY=$(TZ='Asia/Shanghai' date +%Y-%m-%d)

# 5. 判断是否有新版本
if [ "$CURRENT_VERSION" = "$LAST_VERSION" ]; then
  # ---- 无新版本：发简短日报 ----
  FEISHU_MD="## 📋 OpenClaw 每日版本检查｜${TODAY}

**当前最新版：** ${CURRENT_VERSION}
**最新提交：** \`${LATEST_COMMIT}\`

✅ 暂无新正式版本发布。"

else
  # ---- 有新版本：从 CHANGELOG 提取内容，用 Claude API 生成中文摘要 ----
  RAW_NOTES=$(awk "/^## ${CURRENT_VERSION}/{found=1; next} found && /^## /{exit} found && NF{print}" \
    "$REPO_DIR/CHANGELOG.md" | head -60)

  # 若本地 CHANGELOG 尚未包含该版本（repo 滞后），从 npm 获取简要说明
  if [ -z "$RAW_NOTES" ]; then
    RAW_NOTES="版本 ${CURRENT_VERSION} 的详细 changelog 尚未同步到本地仓库，请访问 GitHub Releases 查看。"
  fi

  # 调用 Claude API 生成中文摘要，输出到临时文件避免 stop-hook 污染变量
  TMPFILE=$(mktemp)
  CLAUDE_SKIP_HOOKS=1 claude --print \
    "以下是 OpenClaw 项目 ${CURRENT_VERSION} 版本的英文 changelog，请用简洁的中文整理成更新摘要。
要求：
- 用 markdown 格式输出，分「重要变更」「新功能」「问题修复」三个三级标题（### ），没有的类别可省略
- 每条用「- 」列表格式
- 保留关键技术术语（如 Telegram、Matrix、Feishu 等）
- 总字数控制在 400 字以内
- 只输出摘要内容，不要任何前缀或额外说明

changelog 内容：
${RAW_NOTES}" > "$TMPFILE" 2>/dev/null || echo "（摘要生成失败）" > "$TMPFILE"

  SUMMARY=$(cat "$TMPFILE")
  rm -f "$TMPFILE"

  FEISHU_MD="## 🆕 OpenClaw 新版本发布！｜${TODAY}

**新版本：** ${CURRENT_VERSION}　　**上一版本：** ${LAST_VERSION:-首次检查}

---

${SUMMARY}

---

📌 [完整 changelog](https://github.com/openclaw/openclaw/releases/tag/v${CURRENT_VERSION})"

  # 更新已通知版本记录
  echo "$CURRENT_VERSION" > "$STATE_FILE"
fi

# 6. 发飞书消息（markdown 格式）
lark-cli im +messages-send \
  --user-id "$USER_OPEN_ID" \
  --markdown "$FEISHU_MD" \
  --as bot 2>&1

echo "✅ 通知已发送 | 版本: $CURRENT_VERSION | $(TZ='Asia/Shanghai' date)"
