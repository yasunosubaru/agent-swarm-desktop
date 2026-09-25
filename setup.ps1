# ============================================================
#  Agent Swarm Desktop —— 首次运行安装向导
#
#    powershell -ExecutionPolicy Bypass -File .\setup.ps1
#
#  它会：
#    1. 找到 agent-swarm 源码目录
#    2. 选定 harness（复用本机 OpenCode 凭据 / OpenRouter / Anthropic / OpenAI）
#    3. 生成本地 API Key 与加密密钥
#    4. 写出 config.json + deploy/.env + opencode-config
#    5. 把对话页装进仪表盘的 public 目录
#    6. 生成图标、创建桌面快捷方式
#
#  全程可交互；也可用参数非交互执行（见 -NonInteractive）。
# ============================================================
param(
    [switch]$NonInteractive,
    [string]$SwarmSrc = "",
    [string]$SwarmRoot = "",
    [string]$Harness = "",
    [string]$OpenCodeAuth = "",
    [string]$ProviderKey = "",
    [string]$ModelOverride = "",
    [string]$Python = "",
    [string]$Desktop = "",
    [switch]$SkipShortcuts,
    [switch]$SkipDockerfiles,
    [switch]$SkipChatPage,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$repoRoot = $PSScriptRoot
$guiDir = Join-Path $repoRoot "gui"
$webDir = Join-Path $repoRoot "web"
$deployDir = Join-Path $repoRoot "deploy"

function Say($msg, $color = "Gray") { Write-Host $msg -ForegroundColor $color }
$script:stepNo = 0
function Step($n, $msg) { $script:stepNo++; Write-Host ""; Write-Host "[$($script:stepNo)] $msg" -ForegroundColor Cyan }
function Ok($msg) { Write-Host "    OK  $msg" -ForegroundColor DarkGray }
function Warn($msg) { Write-Host "    !!  $msg" -ForegroundColor Yellow }
function Die($msg) { Write-Host ""; Write-Host "错误：$msg" -ForegroundColor Red; exit 1 }

function Ask($prompt, $default = "") {
    if ($NonInteractive) { return $default }
    if ($default) {
        $ans = Read-Host "$prompt [$default]"
        if ([string]::IsNullOrWhiteSpace($ans)) { return $default }
        return $ans.Trim()
    }
    return (Read-Host $prompt).Trim()
}

function Test-SwarmSrc([string]$p) {
    if (-not $p) { return $false }
    return ((Test-Path (Join-Path $p "Dockerfile")) -and
            (Test-Path (Join-Path $p "apps\ui\package.json")))
}

function Find-SwarmSrc {
    $roots = @(
        (Join-Path $env:USERPROFILE "Downloads"),
        (Join-Path $env:USERPROFILE "Desktop"),
        (Join-Path $env:USERPROFILE "Documents"),
        $env:USERPROFILE
    )
    $hits = @()
    foreach ($r in $roots) {
        if (-not (Test-Path $r)) { continue }
        try {
            $hits += Get-ChildItem -Path $r -Directory -Recurse -Depth 3 -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like "agent-swarm*" -and (Test-SwarmSrc $_.FullName) } |
                Select-Object -ExpandProperty FullName
        }
        catch { }
    }
    return ($hits | Select-Object -Unique)
}

function Find-Python {
    $cands = @(
        (Join-Path $env:USERPROFILE "multi-agent-collab\.venv\Scripts\python.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python312\python.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python311\python.exe")
    )
    foreach ($c in $cands) { if (Test-Path $c) { return $c } }
    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return ""
}

function Find-Edge {
    foreach ($p in @(
            (Join-Path ${env:ProgramFiles(x86)} "Microsoft\Edge\Application\msedge.exe"),
            (Join-Path $env:ProgramFiles "Microsoft\Edge\Application\msedge.exe"))) {
        if ($p -and (Test-Path $p)) { return $p }
    }
    return ""
}

function New-HexKey([int]$bytes = 32) {
    $b = New-Object byte[] $bytes
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
    return (($b | ForEach-Object { $_.ToString("x2") }) -join "")
}

# ================================================================
Say "" -Color DarkGray
Say "=========================================================" -Color DarkGray
Say "  Agent Swarm Desktop  ·  首次运行安装向导" -Color White
Say "=========================================================" -Color DarkGray

# ---------------------------------------------------------------- 1 源码目录
Step 1 "查找 agent-swarm 源码目录"
if (-not (Test-SwarmSrc $SwarmSrc)) {
    $found = Find-SwarmSrc
    if ($found -and $found.Count -gt 0) {
        Say "    找到以下候选："
        $i = 1
        foreach ($f in $found) { Say "      [$i] $f" -Color DarkGray; $i++ }
        if ($NonInteractive) { $SwarmSrc = $found[0] }
        else {
            $pick = Ask "选哪个？（直接回车用 [1]）" "1"
            if (-not (Test-SwarmSrc $pick) -and [int]::TryParse($pick, [ref]$null)) {
                $idx = [int]$pick
                if ($idx -ge 1 -and $idx -le $found.Count) { $SwarmSrc = $found[$idx - 1] }
            }
            elseif (Test-SwarmSrc $pick) { $SwarmSrc = $pick }
        }
    }
    else {
        $SwarmSrc = Ask "没自动找到。请粘贴 agent-swarm 源码目录（含 Dockerfile 与 apps\ui）" ""
    }
}
if (-not (Test-SwarmSrc $SwarmSrc)) {
    Die "源码目录无效：$SwarmSrc（需要同时存在 Dockerfile 和 apps\ui\package.json）"
}
Ok "源码目录：$SwarmSrc"

# ---------------------------------------------------------------- 2 部署目录
Step 2 "确定部署目录（放 compose / .env / 凭据）"
if (-not $SwarmRoot) { $SwarmRoot = $deployDir }
$SwarmRoot = Ask "部署目录" $SwarmRoot
New-Item -ItemType Directory -Force -Path $SwarmRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $SwarmRoot "opencode-config") | Out-Null
Ok "部署目录：$SwarmRoot"

# ---------------------------------------------------------------- 3 harness
Step 3 "选择 AI harness（AI 员工用什么来干活）"
if (-not $Harness) {
    if ($NonInteractive) { $Harness = "opencode" }
    else {
        Say "      1) opencode    复用本机已登录的 OpenCode 凭据（免费/已有订阅，推荐）"
        Say "      2) openrouter  OpenRouter API Key"
        Say "      3) anthropic   Anthropic API Key"
        Say "      4) openai      OpenAI API Key"
        $Harness = (Ask "选哪个" "1")
        switch ($Harness) {
            "1" { $Harness = "opencode" }
            "2" { $Harness = "openrouter" }
            "3" { $Harness = "anthropic" }
            "4" { $Harness = "openai" }
        }
    }
}
if ($Harness -notin @("opencode", "openrouter", "anthropic", "openai")) { $Harness = "opencode" }
Ok "harness = $Harness"

# ---------------------------------------------------------------- 4 凭据
Step 4 "配置凭据"
$apiKey = ""
$providerEnv = @{}
$opencodeAuthSrc = ""

if ($Harness -eq "opencode") {
    if (-not $opencodeAuthSrc) {
        $defaults = @(
            (Join-Path $env:USERPROFILE ".local\share\opencode\auth.json"),
            (Join-Path $env:APPDATA "opencode\auth.json")
        )
        $guess = ($defaults | Where-Object { Test-Path $_ } | Select-Object -First 1)
        $opencodeAuthSrc = Ask "OpenCode 凭据 auth.json 的位置" ($(if ($guess) { $guess } else { "" }))
    }
    if (-not (Test-Path $opencodeAuthSrc)) {
        Die "找不到 auth.json：$opencodeAuthSrc`n请先在本机 OpenCode 里登录一次，或改用 API Key 方式。"
    }
    Copy-Item $opencodeAuthSrc (Join-Path $SwarmRoot "opencode-config\auth.json") -Force
    Ok "已复制 auth.json（凭据本身不会进 Git 仓库）"

    # opencode.jsonc：只放 provider 声明模板，模型由用户按需改
    $jsonc = @"
{
  // 让 OpenCode 认识你的自定义 provider。
  // 下面是一个示例，请按你实际的 provider / baseURL / 模型改。
  // 若你用的是 OpenCode 官方已支持的 provider，可以整段删掉，只留 {}。
  "`$schema": "https://opencode.ai/config.json",
  "provider": {
    "my-provider": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "My Provider",
      "options": { "baseURL": "https://example.com/v1" },
      "models": { "some/model": { "name": "Some Model" } }
    }
  }
}
"@
    [System.IO.File]::WriteAllText((Join-Path $SwarmRoot "opencode-config\opencode.jsonc"), $jsonc, (New-Object System.Text.UTF8Encoding($false)))
    Ok "已生成 opencode.jsonc 模板（按需改 provider）"
}
else {
    $varName = switch ($Harness) {
        "openrouter" { "OPENROUTER_API_KEY" }
        "anthropic"  { "ANTHROPIC_API_KEY" }
        "openai"     { "OPENAI_API_KEY" }
    }
    if (-not $ProviderKey) { $ProviderKey = Ask "$varName" "" }
    if (-not $ProviderKey) { Die "需要 $varName" }
    $providerEnv[$varName] = $ProviderKey.Trim()
    Ok "已记录 $varName"
    # 仍写一份空的 opencode-config，保证 compose 的挂载路径存在
    if (-not (Test-Path (Join-Path $SwarmRoot "opencode-config\auth.json"))) {
        [System.IO.File]::WriteAllText((Join-Path $SwarmRoot "opencode-config\auth.json"), "{`n}`n", (New-Object System.Text.UTF8Encoding($false)))
    }
    if (-not (Test-Path (Join-Path $SwarmRoot "opencode-config\opencode.jsonc"))) {
        [System.IO.File]::WriteAllText((Join-Path $SwarmRoot "opencode-config\opencode.jsonc"), "{`n}`n", (New-Object System.Text.UTF8Encoding($false)))
    }
}

if (-not $ModelOverride) {
    $ModelOverride = Ask "模型（留空 = 让 harness 自己选默认）" ""
}

$apiKey = New-HexKey 32
Ok "已生成本地 API Key（只写入本地 .env，不进 Git）"

# ---------------------------------------------------------------- 5 密钥与 .env
Step 5 "写出密钥与 .env"
$encFile = Join-Path $SwarmRoot "encryption_key"
if ((-not (Test-Path $encFile)) -or $Force) {
    [System.IO.File]::WriteAllText($encFile, (New-HexKey 32), (New-Object System.Text.UTF8Encoding($false)))
}
Ok "encryption_key"

$envLines = New-Object System.Collections.ArrayList
[void]$envLines.Add("# 由 agent-swarm-desktop 的 setup.ps1 生成。此文件含凭据，已被 .gitignore 排除。")
[void]$envLines.Add("API_KEY=$apiKey")
[void]$envLines.Add("HARNESS_PROVIDER=$Harness")
if ($ModelOverride) { [void]$envLines.Add("MODEL_OVERRIDE=$ModelOverride") }
else { [void]$envLines.Add("# MODEL_OVERRIDE=") }
[void]$envLines.Add("MCP_BASE_URL=http://api:3013")
[void]$envLines.Add("APP_URL=http://localhost:3013")
[void]$envLines.Add("SWARM_SRC=$SwarmSrc")
foreach ($k in $providerEnv.Keys) { [void]$envLines.Add("$k=$($providerEnv[$k])") }
$envText = ($envLines -join "`n") + "`n"
[System.IO.File]::WriteAllText((Join-Path $SwarmRoot ".env"), $envText, (New-Object System.Text.UTF8Encoding($false)))
Ok ".env"

# ---------------------------------------------------------------- 6 配置文件
Step 6 "写出 config.json"
if (-not $Python) { $Python = Find-Python }
if (-not $Python) { Warn "没找到 Python，宿主代理可能无法启动（可稍后改 config.json）" }
$edge = Find-Edge
if (-not $edge) { Warn "没找到 Edge，将改用系统默认浏览器打开" }

$cfgObj = [ordered]@{
    swarmRoot  = $SwarmRoot
    swarmSrc   = $SwarmSrc
    python     = $Python
    edge       = $edge
    proxyPort  = 18080
    apiPort    = 3013
    uiPort     = 5274
}
$cfgJson = $cfgObj | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText((Join-Path $repoRoot "config.json"), $cfgJson + "`n", (New-Object System.Text.UTF8Encoding($false)))
Ok "config.json"

# ---------------------------------------------------------------- 7 装进仪表盘
Step 7 "把对话页装进仪表盘"
$uiPublic = Join-Path $SwarmSrc "apps\ui\public"
if ($SkipChatPage) {
    Say "    已按要求跳过" -Color DarkGray
}
elseif (Test-Path $uiPublic) {
    $chatHtml = Join-Path $uiPublic "chat.html"
    $chatCfgFile = Join-Path $uiPublic "swarm-config.js"

    if ((Test-Path $chatHtml) -and -not $Force) { Ok "apps\ui\public\chat.html 已存在，跳过" }
    else {
        Copy-Item (Join-Path $webDir "chat.html") $chatHtml -Force
        Ok "apps\ui\public\chat.html"
    }

    # 对话页的运行时配置（真实 Key，gitignore）。已存在时不覆盖，避免把能用的 Key 换掉。
    if ((Test-Path $chatCfgFile) -and -not $Force) {
        Ok "apps\ui\public\swarm-config.js 已存在，保留原 Key"
    }
    else {
        $chatCfg = "window.SWARM_CONFIG = { apiKey: `"$apiKey`" };" + "`r`n"
        [System.IO.File]::WriteAllText($chatCfgFile, $chatCfg, (New-Object System.Text.UTF8Encoding($false)))
        Ok "apps\ui\public\swarm-config.js（含真实 Key，切勿提交）"
    }
}
else { Warn "找不到 apps\ui\public，对话页未安装" }

# 可选：把打过补丁的 Dockerfile 覆盖进源码树
if (-not $SkipDockerfiles) {
    Step 8 "Dockerfile（可选）"
    $answer = "y"
    if (-not $NonInteractive) { $answer = Ask "    用本仓库提供的镜像源补丁版 Dockerfile 覆盖源码？（受限网络/国内建议 y）" "y" }
    if ($answer -match '^[Yy]') {
        foreach ($f in @("Dockerfile", "Dockerfile.worker")) {
            $srcFile = Join-Path $repoRoot "deploy\dockerfiles\$f"
            $dstFile = Join-Path $SwarmSrc $f
            if (Test-Path $srcFile) {
                if ((Test-Path $dstFile) -and -not (Test-Path "$dstFile.agent-swarm-orig")) {
                    Copy-Item $dstFile "$dstFile.agent-swarm-orig" -Force
                }
                Copy-Item $srcFile $dstFile -Force
                Ok "$f（原件备份为 $f.agent-swarm-orig）"
            }
        }
    }
    else { Say "    跳过，使用源码树自带的 Dockerfile" -Color DarkGray }
}

# ---------------------------------------------------------------- 8 图标与快捷方式
Step 9 "生成图标"
try {
    & (Join-Path $guiDir "make-icon.ps1") | Out-Null
    Ok "assets\agent-swarm.ico"
}
catch { Warn "图标生成失败：$($_.Exception.Message)" }

if (-not $SkipShortcuts) {
    Step 10 "创建桌面快捷方式"
    try {
        if (-not $Desktop) { $Desktop = [Environment]::GetFolderPath("Desktop") }
        & (Join-Path $guiDir "create-shortcuts.ps1") -Desktop $Desktop | ForEach-Object { Ok $_ }
    }
    catch { Warn "快捷方式创建失败：$($_.Exception.Message)" }
}

# ---------------------------------------------------------------- 收尾
Write-Host ""
Say "=========================================================" -Color DarkGray
Say "  安装完成" -Color Green
Say "=========================================================" -Color DarkGray
Say ""
Say "  下一步：" -Color White
Say "   1) 构建镜像（只需一次，约 10-30 分钟）：" -Color Gray
Say "        docker build -f `"$SwarmSrc\Dockerfile`"        -t agent-swarm:local       `"$SwarmSrc`"" -Color DarkGray
Say "        docker build -f `"$SwarmSrc\Dockerfile.worker`" -t agent-swarm-worker:local --target worker-slim `"$SwarmSrc`"" -Color DarkGray
Say "   2) 双击桌面「Agent Swarm 对话」图标" -Color Gray
Say "   3) 自检： powershell -File .\verify.ps1" -Color Gray
Say ""
Say "  配置在：$(Join-Path $repoRoot 'config.json')" -Color DarkGray
Say "  日志在：$(Join-Path $repoRoot 'logs')" -Color DarkGray
