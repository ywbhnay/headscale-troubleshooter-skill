# Headscale Troubleshooter — Windows 11 一键安装脚本
# 用途：安装自签名证书到 Windows 信任库 + 连接 Headscale
#
# 用法（PowerShell 管理员）：
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#   .\install-win.ps1
#
# 使用前请先修改下方变量

# ======================== 配置区 ========================
$HEADSCALE_URL = "https://hs.167895.xyz:8443"
$HEADSCALE_DOMAIN = "hs.167895.xyz"
$HEADSCALE_PORT = 8443
$AUTHKEY = "hskey-auth-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
$DERP_ID = 999
# ========================================================

function Write-Info  { param($m) Write-Host "[INFO] $m" -ForegroundColor Green }
function Write-Warn  { param($m) Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Write-Error { param($m) Write-Host "[ERROR] $m" -ForegroundColor Red }

function Check-Admin {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Error "请以管理员身份运行 PowerShell"
        exit 1
    }
    Write-Info "管理员权限确认"
}

function Install-Certificate {
    Write-Info "正在从 ${HEADSCALE_URL} 获取证书..."

    # 临时跳过证书验证以获取自签名证书
    [Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

    try {
        $req = [System.Net.WebRequest]::Create($HEADSCALE_URL)
        $req.Timeout = 10000
        $req.GetResponse() | Out-Null
        $cert = $req.ServicePoint.Certificate.Export(
            [System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
        $certPath = "$env:TEMP\headscale-ca.cer"
        [System.IO.File]::WriteAllBytes($certPath, $cert)
        Write-Info "证书已保存到 ${certPath}"
    } catch {
        Write-Error "证书下载失败: $_"
        Write-Warn "请手动下载: 浏览器访问 ${HEADSCALE_URL} → 锁图标 → 证书 → 导出"
        exit 1
    }

    # 导入到受信任的根证书颁发机构
    Import-Certificate -FilePath "$env:TEMP\headscale-ca.cer" -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
    Write-Info "证书已安装到 Windows 信任库"

    # 恢复证书验证
    [Net.ServicePointManager]::ServerCertificateValidationCallback = $null
}

function Verify-HTTPS {
    Write-Info "验证 HTTPS 连接..."
    try {
        $response = Invoke-WebRequest -Uri "${HEADSCALE_URL}/key?v=133" -UseBasicParsing -TimeoutSec 10
        if ($response.StatusCode -eq 200) {
            Write-Info "HTTPS 连接正常"
        }
    } catch {
        Write-Warn "HTTPS 连接异常: $($_.Exception.Message)"
    }
}

function Connect-Tailscale {
    Write-Info "正在连接 Headscale..."

    # 先断开现有连接
    tailscale down 2>$null

    # 连接
    tailscale up `
        --login-server=$HEADSCALE_URL `
        --authkey=$AUTHKEY `
        --force-reauth `
        --reset `
        --accept-risk=all

    Write-Info "等待 tailscaled 启动..."
    Start-Sleep -Seconds 5
}

function Verify-Connection {
    Write-Info "========== 连接状态 =========="

    Write-Info "节点状态:"
    tailscale status 2>$null

    Write-Info "DERP 连接测试 (node ${DERP_ID}):"
    tailscale debug derp $DERP_ID 2>$null

    Write-Info "网络检查:"
    tailscale netcheck 2>$null

    Write-Info "========== 完成 =========="
}

function Main {
    Write-Host "============================================"
    Write-Host "  Headscale 一键安装脚本 (Windows 11)"
    Write-Host "============================================"
    Write-Host ""

    Check-Admin
    Install-Certificate
    Verify-HTTPS
    Connect-Tailscale
    Verify-Connection
}

Main
