#!/bin/bash
# Headscale Troubleshooter — Linux 一键安装脚本 (v1.1)
# 用途：安装自签名证书到系统信任库 + 连接 Headscale
#
# 用法：
#   chmod +x install-linux.sh
#   sudo ./install-linux.sh <domain> <port> <authkey> [derp_id]
#
# 示例：
#   sudo ./install-linux.sh hs.example.com 8443 hskey-auth-XXXXX 999
#
# 参数说明：
#   $1 域名（必填）
#   $2 端口（必填，通常 8443）
#   $3 AuthKey（必填，通过 headscale preauthkeys 生成）
#   $4 DERP ID（可选，默认 999）

set -euo pipefail

# ======================== 参数解析 ========================
if [ $# -lt 3 ]; then
    echo "用法: $0 <domain> <port> <authkey> [derp_id]"
    echo ""
    echo "示例:"
    echo "  $0 hs.example.com 8443 hskey-auth-XXXXX 999"
    echo ""
    echo "参数说明:"
    echo "  domain   Headscale 服务器域名"
    echo "  port     HTTPS 端口（腾讯云/阿里云建议 8443，绕过 SNI 拦截）"
    echo "  authkey  Headscale 预认证密钥"
    echo "  derp_id  DERP 节点 ID（可选，默认 999）"
    exit 1
fi

HEADSCALE_DOMAIN="$1"
HEADSCALE_PORT="$2"
AUTHKEY="$3"
DERP_ID="${4:-999}"
HEADSCALE_URL="https://${HEADSCALE_DOMAIN}:${HEADSCALE_PORT}"
# ===========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ======================== 环境检测 ========================
detect_environment() {
    log_info "检测运行环境..."

    local ENV_TYPE="vm"
    local EXTRA_FLAGS=""

    # 检测 LXC 容器（共享宿主机内核，netfilter 受限）
    if grep -Eq "lxc" /proc/1/cgroup 2>/dev/null || grep -q "container=lxc" /proc/1/environ 2>/dev/null; then
        ENV_TYPE="lxc"
        EXTRA_FLAGS="--netfilter-mode=off --accept-dns=false"
        log_warn "检测到 LXC 容器环境"
        log_warn "已自动添加: --netfilter-mode=off --accept-dns=false"
        log_warn "LXC 共享内核，netfilter 规则与标准 VM 不同"
    # 检测 Docker 容器
    elif [ -f /.dockerenv ] || grep -Eq "docker|kubepods" /proc/1/cgroup 2>/dev/null; then
        ENV_TYPE="docker"
        EXTRA_FLAGS="--accept-dns=false"
        log_warn "检测到 Docker 容器环境"
        log_warn "已自动添加: --accept-dns=false"
    # Proxmox VE 虚拟机（检查内核版本是否含 pve 标识）
    elif uname -r | grep -qi 'pve'; then
        ENV_TYPE="pve-vm"
        log_info "检测到 Proxmox VE 虚拟机环境"
    else
        ENV_TYPE="vm"
        log_info "检测到标准 VM/物理机环境"
    fi

    export ENV_TYPE
    export EXTRA_FLAGS
}
# ============================================================

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

# ======================== 证书安装（带证书链） ========================
install_certificate() {
    log_info "正在从 ${HEADSCALE_URL} 获取证书链..."

    local CERT_DIR="/usr/local/share/ca-certificates"
    local CERT_PATH="${CERT_DIR}/headscale-ca.crt"

    # 拉取完整证书链（包含中间证书），而非仅叶子证书
    # 缺少中间证书会导致 "certificate signed by unknown authority" 错误
    echo | openssl s_client \
        -connect "${HEADSCALE_DOMAIN}:${HEADSCALE_PORT}" \
        -servername "${HEADSCALE_DOMAIN}" \
        -showcerts 2>/dev/null \
        | awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/{print}' \
        > /tmp/headscale-ca-chain.pem

    if [ ! -s /tmp/headscale-ca-chain.pem ]; then
        log_error "证书下载失败"
        log_error "请检查: 1) 域名和端口是否正确  2) 服务器是否在线  3) 防火墙是否放行"
        exit 1
    fi

    # 验证证书
    log_info "证书信息:"
    openssl x509 -in /tmp/headscale-ca-chain.pem -noout -subject -dates -ext subjectAltName 2>/dev/null || true

    # 安装到系统信任库
    cp /tmp/headscale-ca-chain.pem "${CERT_PATH}"
    update-ca-certificates

    log_info "证书链已安装到 ${CERT_PATH}"
    rm -f /tmp/headscale-ca-chain.pem
}
# =======================================================================

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

    # --accept-risk=lose-ssh：替代已废弃的 --accept-risk=all
    # 当 tailscale up 失败时，可能丢失 SSH 访问（如果 SSH 走 Tailscale IP）
    # 仅在确认有备用访问方式（控制台/其他网络）时使用
    log_warn "注意：--accept-risk=lose-ssh 会在 tailscale 配置失败时可能导致 SSH 断开"
    log_warn "请确认你有备用访问方式（如 VNC 控制台）"

    if [ -n "${EXTRA_FLAGS}" ]; then
        log_info "使用环境特定参数: ${EXTRA_FLAGS}"
    fi

    # shellcheck disable=SC2086
    tailscale up \
        --login-server="${HEADSCALE_URL}" \
        --authkey="${AUTHKEY}" \
        --force-reauth \
        --reset \
        --accept-risk=lose-ssh \
        ${EXTRA_FLAGS:-}

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
    echo "  Headscale 一键安装脚本 (Linux) v1.1"
    echo "============================================"
    echo ""
    echo "域名:   ${HEADSCALE_DOMAIN}"
    echo "端口:   ${HEADSCALE_PORT}"
    echo "DERP:   ${DERP_ID}"
    echo ""

    check_root
    detect_environment
    check_dependencies
    install_certificate
    verify_https
    connect_tailscale
    verify_connection
}

main "$@"
