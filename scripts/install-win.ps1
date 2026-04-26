# Headscale Troubleshooter — Windows 11 一键安装脚本 (v1.1)
# 用途：安装自签名证书到 Windows 信任库 + 连接 Headscale
#
# 用法（PowerShell 管理员）：
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#   .\install-win.ps1 -Domain "hs.example.com" -Port 8443 -AuthKey "hskey-auth-XXXXX" [-DerpId 999]
#
# 或者直接在脚本顶部修改默认参数后运行：
#   .\install-win.ps1

param(
    [Parameter(Mandatory = $true,  HelpMessage = "Headscale 服务器域名")]
    [string]$Domain,

    [Parameter(Mandatory = $true,  HelpMessage = "HTTPS 端口（腾讯云/阿里云建议 8443）")]
    [int]$Port,

    [Parameter(Mandatory = $true,  HelpMessage = "Headscale 预认证密钥")]
    [string]$AuthKey,

    [Parameter(Mandatory = $false, HelpMessage = "DERP 节点 ID（默认 999）")]
    [int]$DerpId = 999
)

$HEADSCALE_URL = "https://${Domain}:${Port}"
$HEADSCALE_DOMAIN = $Domain
$HEADSCALE_PORT = $Port
$AUTHKEY = $AuthKey
$DERP_ID = $DerpId

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

    # --accept-risk=lose-ssh：替代已废弃的 --accept-risk=all
    # 当 tailscale up 失败时，可能丢失 SSH 访问（如果 SSH 走 Tailscale IP）
    # 仅在确认有备用访问方式时使用
    Write-Warn "注意：--accept-risk=lose-ssh 可能在配置失败时导致远程访问断开"
    Write-Warn "请确认你有备用访问方式（如物理访问、其他远程工具）"

    # 连接
    tailscale up `
        --login-server=$HEADSCALE_URL `
        --authkey=$AUTHKEY `
        --force-reauth `
        --reset `
        --accept-risk=lose-ssh

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
    Write-Host "  Headscale 一键安装脚本 (Windows 11) v1.1"
    Write-Host "============================================"
    Write-Host ""
    Write-Host "域名:   $HEADSCALE_DOMAIN"
    Write-Host "端口:   $HEADSCALE_PORT"
    Write-Host "DERP:   $DERP_ID"
    Write-Host ""

    Check-Admin
    Install-Certificate
    Verify-HTTPS
    Connect-Tailscale
    Verify-Connection
}

Main
