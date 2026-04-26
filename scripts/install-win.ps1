# Headscale Troubleshooter — Windows 11 一键安装脚本
# 用法： .\install-win.ps1 -Domain "hs.example.com" -Port 8443 -AuthKey "hskey-..."

param (
    [Parameter(Mandatory=$true, HelpMessage="请输入 Headscale 域名 (如 hs.example.com)")]
    [string]$Domain,

    [Parameter(Mandatory=$false)]
    [int]$Port = 8443,

    [Parameter(Mandatory=$true, HelpMessage="请输入 AuthKey")]
    [string]$AuthKey
)

$HEADSCALE_URL = "https://${Domain}:${Port}"

function Check-Admin {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) { Write-Host "[ERROR] 请以管理员身份运行 PowerShell" -ForegroundColor Red; exit 1 }
}

function Install-Certificate {
    Write-Host "[INFO] 正在从 ${HEADSCALE_URL} 获取证书链..." -ForegroundColor Green
    [Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    try {
        $req = [System.Net.WebRequest]::Create($HEADSCALE_URL)
        $req.Timeout = 10000
        $req.GetResponse() | Out-Null
        $certs = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
        $certs.Import($req.ServicePoint.Certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))

        foreach ($c in $certs) {
            if ($c.Subject -eq $c.Issuer) {
                Import-Certificate -FilePath $c.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert) -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
            } else {
                Import-Certificate -FilePath $c.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert) -CertStoreLocation Cert:\LocalMachine\CA | Out-Null
            }
        }
        Write-Host "[INFO] 证书已安装到 Windows 信任库" -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] 证书下载失败: $_" -ForegroundColor Red
        exit 1
    }
    [Net.ServicePointManager]::ServerCertificateValidationCallback = $null
}

function Connect-Tailscale {
    Write-Host "[INFO] 正在连接 Headscale..." -ForegroundColor Green
    tailscale down 2>$null
    tailscale up `
        --login-server=$HEADSCALE_URL `
        --authkey=$AuthKey `
        --force-reauth `
        --reset `
        --accept-risk=lose-ssh
}

Check-Admin
Install-Certificate
Connect-Tailscale
Start-Sleep -Seconds 3
tailscale status
