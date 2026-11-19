# ssh-link-failover

macOS 上的多链路 ssh 自动选路、故障切换与回切。两台机器之间有多条路（网线直连、局域网、Tailscale 等内网穿透）时，让 `ssh` 和常驻端口转发始终走当前能用的最优那条：

- 新连接：按优先级探测，用第一条通的链路。
- 常驻隧道：当前链路断了立即切到下一条；更优链路恢复后自动切回。
- 不需要对端安装任何东西，对端只要有 sshd。

```
有线 192.168.10.2 ──┐
局域网 10.0.0.5 ────┼──  link-endpoint（按优先级测 TCP 22，第一个通的胜出）
Tailscale 100.64.x ─┘            │
                                 ├── ~/.ssh/config 的 ProxyCommand：新连接自动选路
                                 └── link-manager（launchd，每 30 秒 + 网络变化时）：
                                       常驻隧道不在最优链路上 → 结束它 → launchd 按最优链路重连
```

## 为什么不只用 autossh 或只用 Tailscale

- **autossh / launchd KeepAlive** 只负责"断了重连"。重连时虽然会重新选路，但一旦落到备用链路，只要连接不断就一直停在那里，网线插回来也不会回到最快的路。
- **只用 Tailscale** 可以保证永远连得上，但它按自己的探测结果选物理路径，不能指定"网线优先"。实测中两端有网线直连，它仍选了校园网路径。
- 本项目把 Tailscale 当作最后一档兜底，前面几档由自己按固定优先级选，并补上回切。

## 工作原理

1. **`bin/link-endpoint`** 依次对候选 IP 做 `nc -z`（TCP 端口探测），输出第一个通的。用端口探测而不是 ping，是因为对端防火墙可能放行 sshd 却禁 ICMP。
2. **`~/.ssh/config`** 用它做 ProxyCommand，于是任何 `ssh myhost` 都自动选路。`HostName` 固定写一个 IP，让 known_hosts 对所有链路复用同一个主机密钥条目，切换链路不会出现 host key 告警（几条链路通向的是同一台机器）。
3. **`bin/link-manager`** 由 launchd 每 30 秒运行一次，DNS 或网络配置变化时也会立即运行。每轮它找出受管隧道当前实际连的 IP：
   - 对 launchd 托管的 `ssh -L` 隧道，看 ProxyCommand 拉起的 `nc` 子进程参数；
   - 对目标 IP 直接写在参数里的转发（`-R 127.0.0.1:2222:<IP>:22`），按配置的前缀从命令行取出。

   如果当前 IP 不是最优：
   - 当前 IP 已经不通：立即结束该 ssh，不用等 ServerAliveInterval 超时（默认配置下约 45 秒）。
   - 当前 IP 还通，但有更优链路：更优链路要连续 `FAILBACK_ROUNDS` 轮（默认 2 轮，约 30–60 秒）保持最优才切回，避免网线接触不良时来回切换。

   结束之后由 launchd 的 KeepAlive（或你自己的外层循环）重连，重连时经 ProxyCommand 自然落到最优链路。
4. **可选：动态 IP。** 局域网那一档若是对端 DHCP 分配的地址，可以配置 `REFRESH_LABEL`。当这一档探测不通、而别的链路通时，管理器会经 ssh 读回对端的新 IP 并缓存，`link-endpoint` 下一轮即使用新地址。

只有在发生动作时才写日志：`~/Library/Logs/ssh-link-failover.log`。

## 安装

要求：macOS（用到 `launchctl`、BSD `nc -G`、`stat -f`），bash 3.2 即可。

```bash
git clone https://github.com/NatsUIJM/ssh-link-failover.git
cd ssh-link-failover
./install.sh          # 第一次运行只生成 ~/.config/ssh-link-failover/config.sh
$EDITOR ~/.config/ssh-link-failover/config.sh
./install.sh          # 注册 launchd 任务 local.ssh-link-failover
```

然后：

1. 按 [examples/ssh_config](examples/ssh_config) 给对端主机加一个用 `link-endpoint` 做 ProxyCommand 的别名，`ssh 别名` 即可自动选路。
2. 想让某条常驻端口转发跟着切换：参考 [examples/tunnel.plist](examples/tunnel.plist) 用 launchd 托管它（`KeepAlive=true`，目标写别名），再把它的 Label 加进配置的 `TUNNEL_LABELS`。
3. 目标 IP 只能写进参数的转发（如反向转发到另一台机器）：参考 [examples/reverse-tunnel-loop.sh](examples/reverse-tunnel-loop.sh)，并在 `FORWARD_PREFIXES` 里写上 IP 前面的固定前缀。

卸载：`./uninstall.sh`。配置和缓存目录会保留。

## 配置

见 [config.example.sh](config.example.sh)，每项都有注释。常用项：

| 项 | 作用 |
|---|---|
| `CANDIDATES` | 候选链路，按优先级排列，每项 `"IP 标签"` |
| `PORT` / `PROBE_TIMEOUT` | 探测端口与每跳超时（秒） |
| `TUNNEL_LABELS` | 受管的 launchd 隧道任务 |
| `FORWARD_PREFIXES` | 目标 IP 写在参数里的转发进程匹配前缀 |
| `FAILBACK_ROUNDS` | 回切前需要的连续确认轮数 |
| `REFRESH_LABEL` / `REFRESH_CMD` | 动态 IP 刷新（可选） |
| `DRY_RUN=1` | 只记录"本应结束哪个进程"，不真正动作 |

排查：`LINK_ENDPOINT_DEBUG=1 bin/link-endpoint` 打印每一跳的探测结果；`bin/link-endpoint --list` 打印应用缓存后的候选名单。

## 怎么验证切换

不方便拔网线时，可以在对端防火墙临时阻断"来自本机网线地址的 22 端口"，效果与断线相同。已建立的会话通常不受影响，新的探测会失败。对端是 Windows 时，从另一条链路执行：

```powershell
New-NetFirewallRule -DisplayName _linktest -Direction Inbound -Protocol TCP -LocalPort 22 -RemoteAddress 192.168.10.1 -Action Block
Start-Sleep 90
Remove-NetFirewallRule -DisplayName _linktest
```

作者环境（Mac ↔ Windows，网线 / 校园网 / Tailscale 三条链路，4 条受管隧道）的一次实测：阻断开始后约 8 秒，4 条隧道全部切到局域网；阻断解除后约 30 秒（2 轮确认）全部切回网线。期间 `ssh 别名` 始终可用。

## 限制

- 只处理配置里列出的隧道。交互式 ssh 会话不会被迁移；链路断了以后重新 `ssh` 即可自动选到可用的路。
- 切换方式是结束旧连接再重连，转发端口会中断几秒，正在传输的连接会断开。
- 只支持 macOS。Linux 上需要把 launchd 换成 systemd timer，并把 `nc -G` 和 `stat -f` 换成对应写法。
- 只看 TCP 端口通不通，不比较延迟。链路的好坏完全由你在 `CANDIDATES` 里的排序决定。

## 不走 ssh 的长连接程序

键鼠共享（Deskflow / Barrier）、串流之类自己建 TCP 连接的程序不经过 ssh，本项目管不到。最简单的做法是让它们连对端的 Tailscale（或其他内网穿透）地址：只要两边都能上网，这个地址始终可达，物理路径由 Tailscale 自己切换。代价是不一定走最快的那条路，但键鼠这类流量很小，延迟差几毫秒基本感觉不到。

## License

MIT
