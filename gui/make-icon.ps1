# Build a multi-size Windows .ico (16..256 px) from a PNG logo.
# Used by setup.ps1 to generate assets\agent-swarm.ico from the dashboard logo.
param(
    [string]$Logo = "",
    [string]$Out = ""
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$guiDir = $PSScriptRoot
$repoRoot = Split-Path $guiDir -Parent
$cfgFile = Join-Path $repoRoot "config.json"

if (-not $Out) { $Out = Join-Path $repoRoot "assets\agent-swarm.ico" }
if (-not $Logo) {
    $Logo = Join-Path $repoRoot "assets\logo.png"
    if (-not (Test-Path $Logo) -and (Test-Path $cfgFile)) {
        try {
            $cfg = Get-Content $cfgFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $candidate = Join-Path $cfg.swarmSrc "apps\ui\public\logo.png"
            if (Test-Path $candidate) { $Logo = $candidate }
        }
        catch { }
    }
}

if (-not (Test-Path $Logo)) { throw "找不到 logo 图片：$Logo" }
New-Item -ItemType Directory -Force -Path (Split-Path $Out -Parent) | Out-Null

$img = [System.Drawing.Image]::FromFile($Logo)
$sizes = @(16, 24, 32, 48, 64, 128, 256)
$pngs = New-Object System.Collections.ArrayList

foreach ($s in $sizes) {
    $bmp = New-Object System.Drawing.Bitmap($s, $s)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.DrawImage($img, 0, 0, $s, $s)
    $g.Dispose()
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    [void]$pngs.Add($ms.ToArray())
    $bmp.Dispose()
    $ms.Dispose()
}
$img.Dispose()

# ICONDIR + ICONDIRENTRY[] + PNG payloads (Vista+ accepts PNG-compressed entries)
$ms = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter($ms)
$bw.Write([UInt16]0)
$bw.Write([UInt16]1)
$bw.Write([UInt16]$sizes.Count)

$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $s = $sizes[$i]
    $data = $pngs[$i]
    $dim = if ($s -ge 256) { 0 } else { $s }
    $bw.Write([byte]$dim)
    $bw.Write([byte]$dim)
    $bw.Write([byte]0)
    $bw.Write([byte]0)
    $bw.Write([UInt16]1)
    $bw.Write([UInt16]32)
    $bw.Write([UInt32]$data.Length)
    $bw.Write([UInt32]$offset)
    $offset += $data.Length
}
foreach ($d in $pngs) { $bw.Write($d) }
$bw.Flush()

[System.IO.File]::WriteAllBytes($Out, $ms.ToArray())
$bw.Dispose(); $ms.Dispose()

Write-Output "已生成图标：$Out ($((Get-Item $Out).Length) 字节, $($sizes.Count) 种尺寸)"
