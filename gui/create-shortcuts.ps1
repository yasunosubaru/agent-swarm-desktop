# Create (or refresh) the two desktop shortcuts:
#   Agent Swarm        -> opens the console window
#   Agent Swarm 对话   -> boots everything and goes straight into the chat
param(
    [string]$Desktop = ""
)

$ErrorActionPreference = "Stop"

$guiDir = $PSScriptRoot
$repoRoot = Split-Path $guiDir -Parent
$cfgFile = Join-Path $repoRoot "config.json"
if (-not (Test-Path $cfgFile)) {
    throw "找不到 config.json，请先运行 setup.ps1"
}

if (-not $Desktop) { $Desktop = [Environment]::GetFolderPath("Desktop") }
$app = Join-Path $guiDir "AgentSwarm.ps1"
$ico = Join-Path $repoRoot "assets\agent-swarm.ico"
$ps = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"

$defs = @(
    @{
        Name = "Agent Swarm 对话.lnk"
        Args = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$app`" -Chat"
        Desc = "Agent Swarm - 直接开始对话"
    },
    @{
        Name = "Agent Swarm.lnk"
        Args = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$app`""
        Desc = "Agent Swarm - 控制台"
    }
)

$ws = New-Object -ComObject WScript.Shell
foreach ($d in $defs) {
    $path = Join-Path $Desktop $d.Name
    $sc = $ws.CreateShortcut($path)
    $sc.TargetPath = $ps
    $sc.Arguments = $d.Args
    $sc.WorkingDirectory = $repoRoot
    if (Test-Path $ico) { $sc.IconLocation = "$ico,0" }
    $sc.Description = $d.Desc
    $sc.WindowStyle = 7
    $sc.Save()
    Write-Output "已创建快捷方式：$path"
}
