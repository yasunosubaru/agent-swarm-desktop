# ============================================================
#  Agent Swarm 控制脚本（桌面 GUI 与命令行共用）
#
#  依赖仓库根目录的 config.json —— 由 setup.ps1 首次运行生成：
#    powershell -ExecutionPolicy Bypass -File .\setup.ps1
#
#  用法：
#    powershell -File .\gui\swarm-ctl.ps1 -Action start
#    powershell -File .\gui\swarm-ctl.ps1 -Action stop
#    powershell -File .\gui\swarm-ctl.ps1 -Action status
#    powershell -File .\gui\swarm-ctl.ps1 -Action open
#    powershell -File .\gui\swarm-ctl.ps1 -Action open-chat
#    powershell -File .\gui\swarm-ctl.ps1 -Action verify
# ============================================================
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('start', 'stop', 'open', 'open-chat', 'status', 'verify')]
    [string]$Action
)

$ErrorActionPreference = "Continue"

# ---------------------------------------------------------------- 配置
$guiDir = $PSScriptRoot
$repoRoot = Split-Path $guiDir -Parent
$cfgFile = Join-Path $repoRoot "config.json"

if (-not (Test-Path $cfgFile)) {
    Write-Output "MISSING_CONFIG"
    Write-Output "找不到配置文件：$cfgFile"
    Write-Output "请先运行一次向导："
    Write-Output "  powershell -ExecutionPolicy Bypass -File .\setup.ps1"
    exit 2
}

$cfg = Get-Content $cfgFile -Raw -Encoding UTF8 | ConvertFrom-Json
$root = $cfg.swarmRoot                  # 部署目录：compose / .env / opencode-config
$src = $cfg.swarmSrc                    # agent-swarm 源码目录
$uiDir = Join-Path $src "apps\ui"       # 仪表盘与对话页所在目录
$py = $cfg.python                       # 跑 host_proxy.py 的 Python
$edge = $cfg.edge                       # 用 Edge --app 打开无边框窗口
$proxyPort = if ($cfg.proxyPort) { [int]$cfg.proxyPort } else { 18080 }
$apiPort = if ($cfg.apiPort) { [int]$cfg.apiPort } else { 3013 }
$uiPort = if ($cfg.uiPort) { [int]$cfg.uiPort } else { 5274 }
$logDir = Join-Path $repoRoot "logs"
$dashboard = "http://127.0.0.1:$uiPort/"
$chatPage = "http://127.0.0.1:$uiPort/chat.html"
$script:fail = 0

New-Item -ItemType Directory -Force -Path $logDir | Out-Null

# ---------------------------------------------------------------- 工具函数
function Test-Port([int]$p) {
    [bool](Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue)
}

function Get-EnvValue([string]$name, [string]$default = "") {
    $envFile = Join-Path $root ".env"
    if (-not (Test-Path $envFile)) { return $default }
    $line = Get-Content $envFile -Encoding UTF8 | Where-Object { $_ -match "^$name=" } | Select-Object -First 1
    if ($line) { return ($line -replace "^$name=", "").Trim() }
    return $default
}

function Get-ApiKey { Get-EnvValue "API_KEY" }

# 把 API Key 以运行时配置的形式注入对话页，使 chat.html 本身可以公开提交。
function Write-ChatConfig {
    $key = Get-ApiKey
    if (-not $key) { return $false }
    try {
        $pub = Join-Path $uiDir "public"
        if (-not (Test-Path $pub)) { return $false }
        $file = Join-Path $pub "swarm-config.js"
        $body = "// 由 agent-swarm-desktop 自动生成，含真实凭据，请勿提交。`r`n" +
        "window.SWARM_CONFIG = { apiKey: `"$key`" };`r`n"
        [System.IO.File]::WriteAllText($file, $body, (New-Object System.Text.UTF8Encoding($false)))
        return $true
    }
    catch { return $false }
}

function Start-Dashboard {
    if (Test-Port $uiPort) { return $true }

    if (-not (Test-Path (Join-Path $uiDir "node_modules"))) {
        Write-Output "      仪表盘依赖缺失，正在安装（首次较慢）..."
        Push-Location $uiDir
        & npm install --no-audit --no-fund *> (Join-Path $logDir "ui-install.log")
        Pop-Location
    }

    $key = Get-ApiKey
    $env:VITE_API_URL = "http://127.0.0.1:$uiPort"
    $env:VITE_API_KEY = $key
    if (-not (Write-ChatConfig)) {
        Write-Output "      警告：无法写入 public\swarm-config.js，对话页可能提示缺少 API Key"
    }

    $uiLog = Join-Path $logDir "ui-dev.log"
    Start-Process -FilePath "cmd.exe" `
        -ArgumentList "/c", "npx vite --host 127.0.0.1 --port $uiPort --strictPort > `"$uiLog`" 2>&1" `
        -WorkingDirectory $uiDir -WindowStyle Hidden

    for ($i = 0; $i -lt 30; $i++) { Start-Sleep 1; if (Test-Port $uiPort) { return $true } }
    return (Test-Port $uiPort)
}

function Open-Target([string]$url) {
    if ($edge -and (Test-Path $edge)) {
        Start-Process -FilePath $edge -ArgumentList "--app=$url", "--window-size=1440,920"
    }
    else { Start-Process $url }
}

# ---------------------------------------------------------------- 动作
switch ($Action) {

    'status' {
        $api = Test-Port $apiPort
        $agents = "0"; $healthy = "no"
        if ($api) {
            try { $healthy = (Invoke-RestMethod -Uri "http://localhost:$apiPort/health" -TimeoutSec 3).status } catch { }
            try {
                $r = Invoke-RestMethod -Uri "http://localhost:$apiPort/api/agents" `
                    -Headers @{ Authorization = "Bearer $(Get-ApiKey)" } -TimeoutSec 3
                $agents = "$(@($r.agents).Count)"
            }
            catch { }
        }
        Write-Output "PROXY=$(if (Test-Port $proxyPort) { 'up' } else { 'down' })"
        Write-Output "DOCKER=$(if (Get-Process -Name 'com.docker.backend' -ErrorAction SilentlyContinue) { 'up' } else { 'down' })"
        Write-Output "API=$(if ($api) { 'up' } else { 'down' })"
        Write-Output "API_HEALTH=$healthy"
        Write-Output "AGENTS=$agents"
        Write-Output "UI=$(if (Test-Port $uiPort) { 'up' } else { 'down' })"
    }

    'open' { Open-Target $dashboard;  Write-Output "已打开工作台 $dashboard" }

    'open-chat' { Open-Target $chatPage; Write-Output "已打开对话页 $chatPage" }

    'verify' {
        $ok = $true
        Write-Output "=== Agent Swarm 端到端自检 ==="
        Write-Output "1. 宿主代理 :$proxyPort"
        if (Test-Port $proxyPort) { Write-Output "   OK" } else { Write-Output "   未监听"; $ok = $false }

        Write-Output "2. Docker 引擎"
        try {
            & docker info --format "   OK (engine {{.ServerVersion}})" 2>$null
            if ($LASTEXITCODE -ne 0) { Write-Output "   未就绪"; $ok = $false }
        }
        catch { Write-Output "   未就绪"; $ok = $false }

        Write-Output "3. API /health"
        try {
            $h = Invoke-RestMethod -Uri "http://localhost:$apiPort/health" -TimeoutSec 5
            Write-Output "   OK (v$($h.version), status=$($h.status))"
        }
        catch { Write-Output "   不可达"; $ok = $false }

        Write-Output "4. 已注册员工"
        try {
            $r = Invoke-RestMethod -Uri "http://localhost:$apiPort/api/agents" `
                -Headers @{ Authorization = "Bearer $(Get-ApiKey)" } -TimeoutSec 5
            foreach ($a in @($r.agents)) {
                $cred = if ($a.credStatus) { "$($a.credStatus.ready)/$($a.credStatus.satisfiedBy)" } else { "?" }
                $role = if ($a.isLead) { "lead" } else { "coder" }
                Write-Output "   - $($a.name)  role=$role  status=$($a.status)  harness=$($a.harnessProvider)  cred=$cred"
            }
            if (@($r.agents).Count -eq 0) { Write-Output "   没有员工注册"; $ok = $false }
        }
        catch { Write-Output "   不可达"; $ok = $false }

        Write-Output "5. 网页仪表盘 / 对话页"
        foreach ($u in @($dashboard, $chatPage)) {
            $code = curl.exe -s -o NUL -w "%{http_code}" --max-time 8 $u
            Write-Output "   $code  $u"
            if ($code -ne "200") { $ok = $false }
        }

        if ($ok) { Write-Output ""; Write-Output "VERIFY_OK" }
        else { Write-Output ""; Write-Output "VERIFY_FAILED" }
    }

    'stop' {
        Write-Output "停止网页仪表盘 ..."
        Get-NetTCPConnection -LocalPort $uiPort -State Listen -ErrorAction SilentlyContinue |
            ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }
        Write-Output "停止 AI 团队容器 ..."
        Push-Location $root
        & docker compose -f (Join-Path $root "docker-compose.swarm.yml") --env-file (Join-Path $root ".env") stop 2>&1 |
            ForEach-Object { Write-Output "      $_" }
        Pop-Location
        Write-Output "已停止（数据保留，下次启动即恢复）。"
        Write-Output "STOPPED"
    }

    'start' {
        # --- 1/5 宿主代理 ---
        Write-Output "[1/5] 宿主代理 ($proxyPort) ..."
        if (-not (Test-Port $proxyPort)) {
            $proxyPy = Join-Path $guiDir "host_proxy.py"
            if ($py -and (Test-Path $py) -and (Test-Path $proxyPy)) {
                Start-Process -FilePath $py -ArgumentList @($proxyPy, "$proxyPort") -WorkingDirectory $guiDir -WindowStyle Hidden
                Start-Sleep 2
            }
            else { Write-Output "      找不到可用的 Python：$py"; $script:fail++ }
        }
        $sup = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -like "*proxy_supervisor*" }
        if (-not $sup) {
            Start-Process powershell.exe -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $guiDir "proxy_supervisor.ps1") -WindowStyle Hidden
        }
        Write-Output $(if (Test-Port $proxyPort) { "      正常" } else { "      未监听！" })

        # --- 2/5 Docker 引擎 ---
        Write-Output "[2/5] Docker 引擎 ..."
        $dockerOk = $false
        try { & docker info --format "{{.ServerVersion}}" 2>$null | Out-Null; if ($LASTEXITCODE -eq 0) { $dockerOk = $true } } catch { }
        if (-not $dockerOk) {
            $dd = Join-Path ${env:ProgramFiles} "Docker\Docker\Docker Desktop.exe"
            if (Test-Path $dd) {
                Write-Output "      Docker 未运行，正在启动 Docker Desktop ..."
                Start-Process $dd
                for ($i = 0; $i -lt 90; $i++) {
                    Start-Sleep 2
                    try { & docker info --format "{{.ServerVersion}}" 2>$null | Out-Null; if ($LASTEXITCODE -eq 0) { $dockerOk = $true; break } } catch { }
                    if ($i % 10 -eq 9) { Write-Output "      仍在等待 Docker 引擎 ..." }
                }
            }
        }
        if ($dockerOk) { Write-Output "      正常" }
        else { Write-Output "      Docker 未就绪，无法继续。请手动打开 Docker Desktop 后重试。"; $script:fail++; Write-Output "FAILED"; break }

        # --- 3/5 AI 团队 ---
        Write-Output "[3/5] 启动 AI 团队 (API + Lead + Coder x2) ..."
        Push-Location $root
        & docker compose -f (Join-Path $root "docker-compose.swarm.yml") --env-file (Join-Path $root ".env") up -d --no-build 2>&1 |
            ForEach-Object { if ($_ -and $_ -notmatch '^\s*$') { Write-Output "      $_" } }
        Pop-Location

        # --- 4/5 等待 API ---
        Write-Output "[4/5] 等待 API 健康检查 ..."
        $apiOk = $false; $h = $null
        for ($i = 0; $i -lt 40; $i++) {
            try {
                $h = Invoke-RestMethod -Uri "http://localhost:$apiPort/health" -TimeoutSec 3
                if ($h.status -eq 'ok') { $apiOk = $true; break }
            }
            catch { }
            Start-Sleep 3
        }
        if ($apiOk) { Write-Output "      API v$($h.version) 就绪" }
        else { Write-Output "      API 尚未就绪"; $script:fail++ }

        # --- 5/5 仪表盘 + 对话页 ---
        Write-Output "[5/5] 启动网页仪表盘 ($uiPort) 与对话页 ..."
        if (Start-Dashboard) { Write-Output "      正常 -> $chatPage" }
        else { Write-Output "      启动失败，请查看 logs\ui-dev.log"; $script:fail++ }

        if ($script:fail -eq 0) {
            Write-Output ""
            Write-Output "全部就绪。"
            Write-Output "READY"
        }
        else {
            Write-Output ""
            Write-Output "有 $($script:fail) 项未就绪，请查看上方日志。"
            Write-Output "FAILED"
        }
    }
}
