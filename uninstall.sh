#!/bin/bash
# 卸载 launchd 任务；配置 ~/.config/ssh-link-failover 与缓存 ~/.cache/ssh-link-failover 保留，需要时手动删除
set -uo pipefail
launchctl bootout "gui/$(id -u)/local.ssh-link-failover" 2>/dev/null && echo "已停止 local.ssh-link-failover"
rm -f "$HOME/Library/LaunchAgents/local.ssh-link-failover.plist" && echo "已删除 plist"
