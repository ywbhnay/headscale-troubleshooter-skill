# Headscale 组网故障排障报告

> 日期：2026-04-26
> 环境：腾讯云 Ubuntu ([IP]) + Tailscale/Headscale 自建控制平面
> 涉及节点：`[SERVER_NODE]` (服务端), `[CLIENT_LINUX_NODE]` (Linux 客户端), `[CLIENT_NEW_NODE]` (待接入), Win11 (待接入)

---

## 一、问题描述

客户端无法通过自建 Headscale 控制平面建立 Tailscale 组网连接。表现为：
- `tailscale up` 卡住或报错
- 节点之间无法互 ping
- `tailscale status` 显示节点在线但无数据收发

## 二、全部操作记录（按时间顺序）

### 2.1 初始诊断

| 操作 | 命令 | 结果 | 判定 |
|------|------|------|------|
| curl 域名 443 | `curl -vk https://[DOMAIN]:443/key?v=133` | `Connection was reset` | SNI 拦截 |
| curl IP 443 | `curl -vk https://[IP]:443/key?v=133` | 正常 | 确认是 SNI 问题 |
| curl 域名 [PORT] | `curl -vk https://[DOMAIN]:[PORT]/key?v=133` | 正常 | 非标端口绕过 SNI |

### 2.2 证书问题

| 操作 | 命令 | 结果 | 判定 |
|------|------|------|------|
| 检查证书 | `openssl s_client -connect [DOMAIN]:[PORT]` | 证书仅有 CN，无 SAN | Go TLS 不合法 |
| 生成新证书 | `openssl req -x509 ... -addext "subjectAltName=DNS:[DOMAIN],IP:[IP]"` | 成功 | 含 SAN |

### 2.3 客户端连接

| 操作 | 命令 | 结果 | 判定 |
|------|------|------|------|
| 首次连接 | `tailscale up --login-server=https://[DOMAIN]:[PORT]` | 返回 AuthURL，等待浏览器认证 | 需要 authkey |
| 带 authkey 连接 | `tailscale up --login-server=... --authkey=hskey-...` | 认证成功 | OK |
| 首次 ping | `tailscale ping 100.64.0.2` | 超时 10 次 | DERP 未连接 |
| 再次 ping | 同上 | 通，30ms | DERP 已连接 |

### 2.4 服务端修复

| 操作 | 命令 | 结果 |
|------|------|------|
| 安装证书 | `sudo cp cert.pem /usr/local/share/ca-certificates/headscale.crt && sudo update-ca-certificates` | 证书已信任 |
| 重启 tailscaled | `sudo systemctl restart tailscaled` | 服务端 DERP 连接建立 |
| 验证 DERP | `tailscale debug derp 999` | `Successfully established a DERP connection` |

### 2.5 最终验证

| 操作 | 结果 |
|------|------|
| `tailscale status` | 两端均 `active` |
| `tailscale ping 100.64.0.X` | 正常回复，30ms 延迟 |
| `tailscale debug derp 999` | DERP 双向连接正常 |
| `tailscale netcheck` | 网络检查通过 |

## 三、根因分析（三层叠加）

### 第一层：腾讯云 SNI 深度包检测（网络层）

**现象:** `curl [DOMAIN]:443` → `Connection was reset`，但 `curl [IP]:443` 正常

**根因:** 腾讯云对 443 端口实施 SNI 深度包检测，未备案或未注册白名单的域名会被 TCP RST 静默阻断。这是四层（TCP）重置，不是 DNS 问题。

**解决:** 改用 [PORT] 端口。SNI 检测仅覆盖标准端口 443。需要三端同步修改：
1. Nginx `listen [PORT] ssl;`
2. Docker `ports: ["[PORT]:443"]`
3. 客户端 `--login-server=https://[DOMAIN]:[PORT]`

### 第二层：自签名证书缺少 SAN 字段（证书层）

**现象:** `x509: certificate relies on legacy Common Name field, use SANs instead`

**根因:** Go 1.15+ 完全废弃了 X.509 证书的 CN (Common Name) 字段，强制要求 Subject Alternative Name (SAN)。浏览器出于兼容性仍接受仅 CN 的证书，但 Tailscale/Headscale 底层使用 Go TLS 栈，会直接拒绝。

**解决:** 重新生成证书时必须包含 `-addext "subjectAltName=DNS:[DOMAIN],IP:[IP]"`。

### 第三层：服务端 tailscaled 不信任自签名证书（DERP 层）

**现象:** 客户端认证成功，但 `tailscale ping` 超时，`tailscale status` 显示 `tx N rx 0`

**根因:** 服务端 `tailscaled` 连接自身 DERP 服务器时也需要验证 TLS 证书。自签名证书未被服务端系统信任库接受，导致 DERP 连接无法建立。关键日志：`derp-999 does not know about peer [xty2p], removing route`——这表示对端未连接 DERP，而非本端问题。

**解决:** 服务端也需安装证书到信任库：
```bash
sudo cp cert.pem /usr/local/share/ca-certificates/headscale.crt
sudo update-ca-certificates
sudo systemctl restart tailscaled
```

## 四、最终落地方案

### 服务端配置

| 组件 | 配置 |
|------|------|
| 证书 | OpenSSL 自签名，CN=[DOMAIN], SAN=DNS:[DOMAIN],IP:[IP] |
| Nginx | 监听 [PORT] 端口，`proxy_buffering off`，`proxy_read_timeout 600s` |
| Docker | 端口映射 `[PORT]:443` |
| 信任库 | 证书安装到 `/usr/local/share/ca-certificates/` 并 `update-ca-certificates` |
| Tailscale | `systemctl restart tailscaled` 重新加载证书信任 |

### 客户端连接

```bash
sudo tailscale up \
  --login-server=https://[DOMAIN]:[PORT] \
  --authkey=hskey-auth-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX \
  --force-reauth --reset --accept-risk=lose-ssh
```

## 五、排障心得

### 5.1 控制面和数据面必须分开排查

Tailscale 有两层连接：
- **控制面** (HTTPS)：认证、注册、密钥交换。用 `curl` 和 `journalctl -u tailscaled` 排查。
- **数据面** (WireGuard UDP 41641 / DERP TCP 443)：实际节点间数据传输。用 `tailscale ping`、`tailscale debug derp`、`tailscale netcheck` 排查。

控制面通 ≠ 数据面通。本次排障中控制面一直正常（curl 能访问），但数据面因 DERP 未连接而完全不通。

### 5.2 日志永远比猜测可靠

`tailscale debug prefs`、`journalctl -u tailscaled`、`tailscale debug metrics` 的输出是排障的唯一证据。不要猜——看日志。

关键日志关键词：
- `derp-XXX does not know about peer` → 对端未连接 DERP
- `context canceled` → Nginx 缓冲问题
- `certificate signed by unknown authority` → 证书未信任
- `derp-XXX connected; connGen=1` → DERP 连接成功

### 5.3 服务端也需要信任自己的证书

这是一个容易被忽略的点：`tailscaled` 本身也是一个 TLS 客户端。当它连接到自身的 DERP 服务器时，会使用系统 TLS 栈验证证书。如果证书不在信任库中，DERP 就无法建立，所有依赖 DERP 的客户端都会受影响。

### 5.4 腾讯/阿里云 443 端口 SNI 拦截是 TCP 层重置

不是 DNS 问题、不是证书问题、不是防火墙规则。是云厂商在 TCP 握手阶段检测 SNI 字段，对未备案域名的 443 连接发送 RST。绕过方式是使用非标准端口（8443、9443 等）。

### 5.5 `tx N rx 0` 是单向通信的典型表现

`tailscale status` 中看到 `tx 3120 rx 0`（发送有数据，接收为零）意味着：
- 本端能发出数据（控制面通）
- 对端无法回传数据（数据面不通）
- 大概率是 DERP 单向连接或 WireGuard 握手失败

### 5.6 Nginx 缓冲会导致长轮询超时

Headscale 使用 HTTP long-polling 保持控制面连接。Nginx 默认的 `proxy_buffering on` 会缓冲上游响应，导致 Tailscale 的长轮询请求超时并被取消，表现为 `context canceled` 错误。必须在 location 块中设置 `proxy_buffering off`。

---

## 附录：关键命令速查

```bash
# 控制面检查
curl -vk https://[DOMAIN]:[PORT]/key?v=133

# 服务端日志
journalctl -u tailscaled --since "10 min ago" --no-pager | grep -iE 'control|error|derp'

# 数据面检查
tailscale status
tailscale ping 100.64.0.X
tailscale netcheck

# DERP 调试
tailscale debug derp 999
tailscale debug metrics | grep -iE 'derp|magicsock|health'

# 证书验证
openssl x509 -in cert.pem -noout -subject -ext subjectAltName

# 重新连接
sudo tailscale up --login-server=https://[DOMAIN]:[PORT] --authkey=YOUR_KEY --force-reauth --reset --accept-risk=lose-ssh
```
