#!/bin/bash
# Headscale Troubleshooter — Linux 一键安装脚本
# 用途：安装自签名证书到系统信任库 + 连接 Headscale
#
# 用法：
#   curl -sL <url> | bash
# 或：
#   chmod +x install-linux.sh && sudo ./install-linux.sh
#
# 使用前请先修改下方变量

set -euo pipefail

# ======================== 配置区 ========================
HEADSCALE_URL="https://hs.167895.xyz:8443"
HEADSCALE_DOMAIN="hs.167895.xyz"
HEADSCALE_IP="124.220.169.4"
AUTHKEY="hskey-auth-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
DERP_ID="999"
# ========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 sudo 运行此脚本"
        exit 1
    fi
}

check_dependencies() {
    for cmd in openssl curl tailscale systemctl; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "缺少依赖: $cmd"
            exit 1
        fi
    done
    log_info "依赖检查通过"
}

install_certificate() {
    log_info "正在从 ${HEADSCALE_URL} 获取证书..."

    local CERT_DIR="/usr/local/share/ca-certificates"
    local CERT_PATH="${CERT_DIR}/headscale-ca.crt"

    # 从服务器下载证书
    echo | openssl s_client -connect "${HEADSCALE_DOMAIN}:8443" -servername "${HEADSCALE_DOMAIN}" 2>/dev/null | \
        openssl x509 -out /tmp/headscale-ca.pem

    if [ ! -s /tmp/headscale-ca.pem ]; then
        log_error "证书下载失败"
        exit 1
    fi

    # 验证证书
    log_info "证书信息:"
    openssl x509 -in /tmp/headscale-ca.pem -noout -subject -dates -ext subjectAltName 2>/dev/null || true

    # 安装到系统信任库
    cp /tmp/headscale-ca.pem "${CERT_PATH}"
    update-ca-certificates

    log_info "证书已安装到 ${CERT_PATH}"
    rm -f /tmp/headscale-ca.pem
}

verify_https() {
    log_info "验证 HTTPS 连接..."
    if curl -sk "${HEADSCALE_URL}/key?v=133" | grep -q .; then
        log_info "HTTPS 连接正常"
    else
        log_warn "HTTPS 连接异常，继续尝试..."
    fi
}

connect_tailscale() {
    log_info "正在连接 Headscale..."

    tailscale down 2>/dev/null || true

    tailscale up \
        --login-server="${HEADSCALE_URL}" \
        --authkey="${AUTHKEY}" \
        --force-reauth \
        --reset \
        --accept-risk=all

    log_info "等待 tailscaled 启动..."
    sleep 5
}

verify_connection() {
    log_info "========== 连接状态 =========="

    echo ""
    log_info "节点状态:"
    tailscale status 2>/dev/null || true

    echo ""
    log_info "DERP 连接测试 (node ${DERP_ID}):"
    tailscale debug derp "${DERP_ID}" 2>/dev/null || true

    echo ""
    log_info "网络检查:"
    tailscale netcheck 2>/dev/null || true

    echo ""
    log_info "========== 完成 =========="
}

main() {
    echo "============================================"
    echo "  Headscale 一键安装脚本 (Linux)"
    echo "============================================"
    echo ""

    check_root
    check_dependencies
    install_certificate
    verify_https
    connect_tailscale
    verify_connection
}

main "$@"
