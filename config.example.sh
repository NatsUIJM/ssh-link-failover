# ssh-link-failover 配置文件（bash 语法，会被 source）
# 复制到 ~/.config/ssh-link-failover/config.sh 后按自己的网络修改。

# 候选链路，按优先级从高到低，每项 "IP 标签"。
# 探测时依次测 TCP 端口，第一个连得上的就是当前最优链路。
CANDIDATES=(
  "192.168.10.2 direct"      # 网线直连（两端手动配同网段静态 IP）
  "10.0.0.5 lan"             # 局域网 / 校园网
  "100.64.0.10 tailscale"    # 内网穿透（Tailscale / ZeroTier 等），兜底
)

# 探测用的端口（一般就是对端 sshd）与每跳超时秒数
PORT=22
PROBE_TIMEOUT=2

# 受管的 launchd 隧道任务（Label）。这些任务应当是 `ssh -N -L ... <SSH_ALIAS>`，
# 且 SSH_ALIAS 在 ~/.ssh/config 里用 link-endpoint 做 ProxyCommand（见 examples/ssh_config）。
TUNNEL_LABELS=(
  # com.example.tunnel-8080
)

# 可选：目标 IP 直接写在 ssh 参数里的转发进程（例如 -R 127.0.0.1:2222:<IP>:22）。
# 每项是命令行里紧挨在 IP 前面的固定前缀；管理器用它找到进程并取出 IP。
# 这类进程需要由外层循环重启（见 examples/reverse-tunnel-loop.sh）。
FORWARD_PREFIXES=(
  # "127.0.0.1:2222:"
)

# 网络恢复到更优链路后，要连续多少轮都判定为更优才切回（防抖）。1 表示立刻切。
FAILBACK_ROUNDS=2

# 可选：某条候选的 IP 是对端 DHCP 分配、可能变化时，管理器在它探测不通而别的链路通时，
# 经 `ssh $SSH_ALIAS "$REFRESH_CMD"` 读回新 IP 并缓存，下一轮探测即使用新地址。
# 留空 REFRESH_LABEL 表示不启用。
SSH_ALIAS=myhost
REFRESH_LABEL=""
REFRESH_INTERVAL=600
# 对端是 Windows（默认 shell 为 PowerShell）时的示例：取有默认网关、且不是 Tailscale 的网卡 IPv4
REFRESH_CMD='(Get-NetIPConfiguration | ? { $_.IPv4DefaultGateway -and $_.InterfaceAlias -notlike "Tailscale*" } | Select -First 1).IPv4Address.IPAddress'
# 对端是 Linux 时可以写成：REFRESH_CMD="ip -4 route get 1.1.1.1 | awk '{print \$7; exit}'"

# 置 1 时只记录"本应执行的动作"，不真正结束任何进程（试运行）
DRY_RUN=0
