# Keeps the Agent Swarm host-side CONNECT proxy (host_proxy.py) alive.
#
# Why: Docker Desktop's Linux VM cannot always reach ghcr.io / quay.io directly
# (a system VPN or proxy breaks VM egress), while the Windows host can. So we
# run a small CONNECT proxy on the host and point Docker Desktop's *manual*
# proxy setting at http://host.docker.internal:18080. Containers therefore
# depend on this process staying up -- hence the supervision loop.
$ErrorActionPreference = "SilentlyContinue"

$guiDir = $PSScriptRoot
$repoRoot = Split-Path $guiDir -Parent
$cfgFile = Join-Path $repoRoot "config.json"

$port = 18080
$python = "python"

if (Test-Path $cfgFile) {
    try {
        $cfg = Get-Content $cfgFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($cfg.proxyPort) { $port = [int]$cfg.proxyPort }
        if ($cfg.python) { $python = $cfg.python }
    }
    catch { }
}

$proxyScript = Join-Path $guiDir "host_proxy.py"

while ($true) {
    $listen = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if (-not $listen) {
        Start-Process -FilePath $python -ArgumentList @($proxyScript, "$port") `
            -WorkingDirectory $guiDir -WindowStyle Hidden
    }
    Start-Sleep -Seconds 10
}
