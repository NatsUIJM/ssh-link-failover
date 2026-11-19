#!/bin/bash
# 安装：生成配置（若不存在）+ 注册 launchd 任务 local.ssh-link-failover（当前用户 gui 域）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
CONF_DIR="$HOME/.config/ssh-link-failover"
PLIST="$HOME/Library/LaunchAgents/local.ssh-link-failover.plist"
LOG="$HOME/Library/Logs/ssh-link-failover.log"

chmod +x "$ROOT/bin/link-endpoint" "$ROOT/bin/link-manager"
mkdir -p "$CONF_DIR" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
if [ ! -f "$CONF_DIR/config.sh" ]; then
  cp "$ROOT/config.example.sh" "$CONF_DIR/config.sh"
  echo "已生成配置 $CONF_DIR/config.sh，请先按自己的网络修改 CANDIDATES 等项，再重新运行 install.sh。"
  exit 0
fi

"$ROOT/bin/link-endpoint" --list >/dev/null   # 配置能被正常读取

sed -e "s|__BIN_DIR__|$ROOT/bin|g" -e "s|__LOG__|$LOG|g" \
  -e "s|__CONFIG__|$CONF_DIR/config.sh|g" -e "s|__STATE__|$HOME/.cache/ssh-link-failover|g" \
  "$ROOT/launchd/ssh-link-failover.plist.template" > "$PLIST"
plutil -lint "$PLIST" >/dev/null
launchctl bootout "gui/$(id -u)/local.ssh-link-failover" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "已安装：$PLIST"
echo "当前最优链路：$("$ROOT/bin/link-endpoint" || echo '无可达候选')"
echo "日志：$LOG"
