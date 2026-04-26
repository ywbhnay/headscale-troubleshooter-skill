#!/bin/bash
# Headscale 自签名证书生成脚本（带 SAN 字段）
# Go 1.15+ 要求证书必须包含 Subject Alternative Name (SAN)
# 浏览器接受仅 CN 的证书，但 Tailscale/Headscale 的 Go TLS 栈会拒绝
#
# 用法：
#   chmod +x gen-cert.sh
#   ./gen-cert.sh

set -euo pipefail

# ======================== 配置区 ========================
DOMAIN="hs.167895.xyz"
PUBLIC_IP="124.220.169.4"
DAYS=3650          # 证书有效期（10 年）
RSA_BITS=2048
OUTPUT_DIR="./certs"
# ========================================================

mkdir -p "${OUTPUT_DIR}"

KEY_FILE="${OUTPUT_DIR}/key.pem"
CERT_FILE="${OUTPUT_DIR}/cert.pem"

echo "============================================"
echo "  Headscale 自签名证书生成"
echo "============================================"
echo ""
echo "域名:     ${DOMAIN}"
echo "公网 IP:  ${PUBLIC_IP}"
echo "有效期:   ${DAYS} 天"
echo "输出目录: ${OUTPUT_DIR}"
echo ""

openssl req -x509 -nodes -newkey rsa:${RSA_BITS} -days ${DAYS} \
  -keyout "${KEY_FILE}" \
  -out "${CERT_FILE}" \
  -subj "/CN=${DOMAIN}" \
  -addext "subjectAltName=DNS:${DOMAIN},IP:${PUBLIC_IP}" \
  2>/dev/null

echo "[OK] 私钥: ${KEY_FILE}"
echo "[OK] 证书: ${CERT_FILE}"
echo ""

# 验证证书
echo "========== 证书信息 =========="
openssl x509 -in "${CERT_FILE}" -noout -subject -issuer -dates -ext subjectAltName

echo ""
echo "========== 验证 SAN 字段 =========="
if openssl x509 -in "${CERT_FILE}" -noout -ext subjectAltName 2>/dev/null | grep -q "DNS:"; then
    echo "[OK] SAN 字段存在"
else
    echo "[ERROR] SAN 字段缺失！Go TLS 会拒绝此证书"
    exit 1
fi

echo ""
echo "下一步:"
echo "  1. 将 cert.pem 和 key.pem 复制到 /etc/nginx/"
echo "  2. 将 cert.pem 安装到系统信任库:"
echo "     sudo cp ${CERT_FILE} /usr/local/share/ca-certificates/headscale.crt"
echo "     sudo update-ca-certificates"
echo "  3. 重启 tailscaled: sudo systemctl restart tailscaled"
