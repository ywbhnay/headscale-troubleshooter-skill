# Headscale Troubleshooter Skill

> AI 专属技能包：Headscale/Tailscale 自建控制平面高级排障专家

一个结构化的 AI Skill，用于诊断和解决自建 Headscale/Tailscale 组网中的各类连接问题。涵盖中国大陆云环境特有的 SNI 拦截、自签名证书 SAN 要求、DERP 中继双向连接等复杂场景。

## 快速开始

### 作为 AI Skill 使用

将 [skill/ADVANCED.md](skill/ADVANCED.md) 的内容复制为你的 AI 助手的 System Prompt，该 AI 即可成为 Headscale 排障专家。

### 作为工具包使用

```bash
# Linux 客户端一键安装
curl -sL https://raw.githubusercontent.com/ywbhnay/headscale-troubleshooter-skill/main/scripts/install-linux.sh | bash

# Windows 客户端（PowerShell 管理员）
iwr https://raw.githubusercontent.com/ywbhnay/headscale-troubleshooter-skill/main/scripts/install-win.ps1 -UseBasicParsing | iex
```

## 项目结构

```
headscale-troubleshooter-skill/
├── README.md                 # 项目说明
├── skill/
│   └── ADVANCED.md           # AI Skill 定义（System Prompt）
├── scripts/
│   ├── install-linux.sh      # Linux 客户端一键安装
│   └── install-win.ps1       # Windows 客户端一键安装
├── templates/
│   ├── nginx.conf            # Nginx 配置模板（含 SNI 规避 + 缓冲关闭）
│   ├── docker-compose.yml    # Docker Compose 配置模板
│   ├── gen-cert.sh           # SAN 证书生成脚本
│   └── Caddyfile             # Caddy 反代配置（Let's Encrypt 自动证书）
└── reports/
    └── troubleshooting.md    # 完整排障报告
```

## 覆盖场景

| 问题 | 表现 | 解决方案 |
|------|------|----------|
| SNI 拦截 | 域名 443 被 reset，IP 正常 | 改用 8443 非标端口 |
| 证书缺 SAN | `legacy Common Name field` | 重新生成带 SAN 的证书 |
| 证书未信任 | `unknown authority` | 安装到系统信任库 |
| Nginx 缓冲 | `context canceled` | `proxy_buffering off` |
| DERP 单向连接 | `tx N rx 0` | 检查服务端 DERP 状态 |
| 透明代理冲突 | DNS 解析到虚拟 IP | 加 DIRECT 规则 |

## License

MIT
