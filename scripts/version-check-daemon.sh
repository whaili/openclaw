#!/bin/bash
# OpenClaw 版本检查守护进程
# 每天北京时间 09:00 触发检查并发飞书通知

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="/tmp/openclaw-version-check.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

log "守护进程启动（PID: $$）"

while true; do
  # 计算到下一个 UTC 01:00（北京时间 09:00）的秒数
  NOW=$(date -u +%s)
  TODAY_TARGET=$(date -u -d "$(date -u +%Y-%m-%d) 01:00:00" +%s 2>/dev/null \
    || date -u -j -f "%Y-%m-%d %H:%M:%S" "$(date -u +%Y-%m-%d) 01:00:00" +%s 2>/dev/null)
  
  if [ "$NOW" -ge "$TODAY_TARGET" ]; then
    # 今天已过，等到明天
    NEXT_TARGET=$((TODAY_TARGET + 86400))
  else
    NEXT_TARGET=$TODAY_TARGET
  fi

  WAIT=$((NEXT_TARGET - NOW))
  NEXT_TIME=$(date -u -d "@$NEXT_TARGET" '+%Y-%m-%d %H:%M UTC' 2>/dev/null || date -u -r "$NEXT_TARGET" '+%Y-%m-%d %H:%M UTC' 2>/dev/null)
  log "下次检查时间：$NEXT_TIME（等待 ${WAIT} 秒）"

  sleep "$WAIT"

  log "开始版本检查..."
  bash "$SCRIPT_DIR/check-version-notify.sh" >> "$LOG" 2>&1
  log "检查完成"

  # 避免秒级重复触发
  sleep 60
done
