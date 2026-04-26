#!/bin/bash
# Headscale Troubleshooter — Linux 一键安装脚本
# 用途：自动检测环境、安装自签名证书完整链、静默接入 Headscale

set -euo pipefail

# 接收命令行参数
HEADSCALE_DOMAIN="${1:-}"
HEADSCALE_PORT="${2:-8443}"
AUTHKEY="${3:-}"

if [ -z "$HEADSCALE_DOMAIN" ] || [ -z "$AUTHKEY" ]; then
    echo -e "\033[0;31m[ERROR] 参数缺失！\033[0m"
    echo "用法: curl -sL <url> | bash -s -- <域名> <端口> <AuthKey>"
    echo "示例: bash install-linux.sh hs.example.com 8443 hskey-auth-xxxx..."
    exit 1
fi

HEADSCALE_URL="https://${HEADSCALE_DOMAIN}:${HEADSCALE_PORT}"
CERT_DIR="/usr/local/share/ca-certificates"
CERT_PATH="${CERT_DIR}/headscale-ca.crt"

echo -e "\033[0;32m[INFO] 1. 彻底断开旧连接并清理状态\033[0m"
sudo tailscale down 2>/dev/null || true

echo -e "\033[0;32m[INFO] 2. 拉取服务端完整证书链并加入系统信任库\033[0m"
echo | openssl s_client -connect "${HEADSCALE_DOMAIN}:${HEADSCALE_PORT}" -servername "${HEADSCALE_DOMAIN}" -showcerts 2>/dev/null \
  | awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/{print}' \
  | sudo tee "${CERT_PATH}" > /dev/null

sudo update-ca-certificates

echo -e "\033[0;32m[INFO] 3. 环境检测并执行连接\033[0m"
if [ -f /proc/1/environ ] && grep -q "container=lxc" /proc/1/environ 2>/dev/null; then
    echo -e "\033[1;33m[WARN] 检测到 LXC 容器环境 — 启用内核避让参数\033[0m"
    sudo tailscale up \
      --login-server="${HEADSCALE_URL}" \
      --authkey="${AUTHKEY}" \
      --force-reauth --reset --accept-risk=lose-ssh \
      --netfilter-mode=off --accept-dns=false
elif [ -f /.dockerenv ] || grep -Eq "docker|lxc|kubepods" /proc/1/cgroup 2>/dev/null; then
    echo -e "\033[1;33m[WARN] 检测到 Docker/容器环境 — 启用内核避让参数\033[0m"
    sudo tailscale up \
      --login-server="${HEADSCALE_URL}" \
      --authkey="${AUTHKEY}" \
      --force-reauth --reset --accept-risk=lose-ssh \
      --netfilter-mode=off --accept-dns=false
else
    echo -e "\033[0;32m[INFO] 检测到 VM/物理机 — 使用标准参数\033[0m"
    sudo tailscale up \
      --login-server="${HEADSCALE_URL}" \
      --authkey="${AUTHKEY}" \
      --force-reauth --reset --accept-risk=lose-ssh
fi

echo -e "\033[0;32m[INFO] ========== 连接完成，当前状态 ==========\033[0m"
tailscale status
