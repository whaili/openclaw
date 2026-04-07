#!/bin/bash
# OpenClaw 每日版本检查 + 飞书通知
# 用法: ./scripts/check-version-notify.sh

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
USER_OPEN_ID="ou_37a31fb48de34cc1cf02d1bb952cbc6d"
STATE_FILE="$REPO_DIR/.last-checked-version"

cd "$REPO_DIR"

# 1. 从 npm registry 获取最新正式版本
CURRENT_VERSION=$(curl -sf https://registry.npmjs.org/openclaw/latest \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['version'])" 2>/dev/null || echo "")

if [ -z "$CURRENT_VERSION" ]; then
  echo "❌ 无法获取 npm 版本，跳过通知" >&2
  exit 1
fi

# 2. 同步本地 repo（用于读取 changelog）
git fetch origin 2>/dev/null || true

# 3. 读取上次已通知的版本
LAST_VERSION=""
if [ -f "$STATE_FILE" ]; then
  LAST_VERSION=$(cat "$STATE_FILE" | tr -d '[:space:]')
fi

# 4. 最新提交信息
LATEST_COMMIT=$(git log --oneline -1 origin/main 2>/dev/null || git log --oneline -1)

TODAY=$(TZ='Asia/Shanghai' date +%Y-%m-%d)

# 格式化 changelog 段落为中文摘要（纯 bash，无外部依赖）
# 参数：$1 = 版本号
format_changelog() {
  local version="$1"
  # 提取该版本的 changelog 块
  local raw
  raw=$(awk "/^## ${version}/{found=1; next} found && /^## /{exit} found{print}" \
    "$REPO_DIR/CHANGELOG.md" | head -80)

  if [ -z "$raw" ]; then
    echo "（本地 changelog 暂未同步该版本，请访问 GitHub Releases 查看详情）"
    return
  fi

  # 翻译章节标题，清理 PR 编号和 Thanks，截断过长条目
  echo "$raw" | awk '
    /^### Breaking/   { print "### ⚠️ 重要变更"; next }
    /^### Changes/    { print "### ✨ 新功能";   next }
    /^### Fixes/      { print "### 🐛 问题修复"; next }
    /^###/            { print; next }
    /^- / {
      # 去掉末尾 PR 编号 "(#12345)" 和 "Thanks @xxx"
      line = $0
      gsub(/ \(#[0-9]+\)/, "", line)
      gsub(/ Thanks @[^ .]+\.?/, "", line)
      gsub(/\. $/, ".", line)
      # 截断超长行（保留前 120 字符）
      if (length(line) > 120) line = substr(line, 1, 120) "…"
      print line
      next
    }
    /^$/ { print; next }
  ' | head -40
}

# 5. 判断是否有新版本
if [ "$CURRENT_VERSION" = "$LAST_VERSION" ]; then
  # ---- 无新版本：简短日报 ----
  FEISHU_MD="## 📋 OpenClaw 每日版本检查｜${TODAY}

**当前最新版：** ${CURRENT_VERSION}
**最新提交：** \`${LATEST_COMMIT}\`

✅ 暂无新正式版本发布。"

else
  # ---- 有新版本：格式化摘要 ----
  SUMMARY=$(format_changelog "$CURRENT_VERSION")

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
