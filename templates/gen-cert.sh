#!/bin/bash
# Headscale 自签名证书生成脚本（带 SAN 字段）

set -euo pipefail

# 接收参数
DOMAIN="${1:-}"
PUBLIC_IP="${2:-}"

if [ -z "$DOMAIN" ] || [ -z "$PUBLIC_IP" ]; then
    echo "用法: ./gen-cert.sh <你的域名> <你的公网IP>"
    exit 1
fi

DAYS=3650
RSA_BITS=2048
OUTPUT_DIR="./certs"

mkdir -p "${OUTPUT_DIR}"
KEY_FILE="${OUTPUT_DIR}/key.pem"
CERT_FILE="${OUTPUT_DIR}/cert.pem"

openssl req -x509 -nodes -newkey rsa:${RSA_BITS} -days ${DAYS} \
  -keyout "${KEY_FILE}" \
  -out "${CERT_FILE}" \
  -subj "/CN=${DOMAIN}" \
  -addext "subjectAltName=DNS:${DOMAIN},IP:${PUBLIC_IP}" \
  2>/dev/null

echo "[OK] 私钥: ${KEY_FILE}"
echo "[OK] 证书: ${CERT_FILE}"
