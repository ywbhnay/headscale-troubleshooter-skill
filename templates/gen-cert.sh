#!/bin/bash
# Headscale 自签名证书生成脚本（带 SAN 字段）
# Go 1.15+ 要求证书必须包含 Subject Alternative Name (SAN)
# 浏览器接受仅 CN 的证书，但 Tailscale/Headscale 的 Go TLS 栈会拒绝
#
# 用法：
#   chmod +x gen-cert.sh
#   ./gen-cert.sh
#
# 脚本会读取下方配置区的变量，生成包含 SAN 的自签名证书。
# 请将 YOUR_DOMAIN 和 YOUR_IP 替换为实际值。

set -euo pipefail

# ======================== 配置区 ========================
# 替换下方两个变量为你的实际域名和公网 IP
DOMAIN="YOUR_DOMAIN"       # 例如: hs.example.com
PUBLIC_IP="YOUR_IP"         # 例如: 124.220.169.4
DAYS=3650                   # 证书有效期（10 年）
RSA_BITS=2048
OUTPUT_DIR="./certs"
# ========================================================

# 检查占位符是否已替换
if [[ "${DOMAIN}" == "YOUR_DOMAIN" ]] || [[ "${PUBLIC_IP}" == "YOUR_IP" ]]; then
    echo "[ERROR] 请先修改脚本中的 DOMAIN 和 PUBLIC_IP 变量！"
    echo "  将 YOUR_DOMAIN 替换为你的 Headscale 域名"
    echo "  将 YOUR_IP 替换为你的服务器公网 IP"
    exit 1
fi

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
echo "  1. 将 cert.pem 和 key.pem 复制到 Nginx 配置目录"
echo "     sudo cp ${CERT_FILE} /etc/nginx/cert.pem"
echo "     sudo cp ${KEY_FILE} /etc/nginx/key.pem"
echo "  2. 将 cert.pem 安装到系统信任库:"
echo "     sudo cp ${CERT_FILE} /usr/local/share/ca-certificates/headscale.crt"
echo "     sudo update-ca-certificates"
echo "  3. 重启 Nginx: sudo systemctl restart nginx"
echo "  4. 重启 tailscaled: sudo systemctl restart tailscaled"
