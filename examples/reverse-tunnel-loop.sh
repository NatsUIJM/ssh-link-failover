#!/bin/bash
# 目标 IP 只能写进 ssh 参数的转发（这里是把对端 22 端口反向转发进另一台机器的 2222）。
# 每次重连前用 link-endpoint 重新选 IP；link-manager 发现它不在最优链路时会结束 ssh，
# 本循环随即按新链路重连。对应配置：FORWARD_PREFIXES=("127.0.0.1:2222:")
ENDPOINT=/path/to/ssh-link-failover/bin/link-endpoint
while true; do
  DST=$("$ENDPOINT" 2>/dev/null) || DST=192.168.10.2
  /usr/bin/ssh -o ExitOnForwardFailure=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=3 \
    -N -R "127.0.0.1:2222:${DST}:22" jumpbox
  echo "$(date '+%F %T') tunnel to ${DST} exited rc=$?"
  sleep 15
done
