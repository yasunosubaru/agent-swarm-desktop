# ============================================================
#  Agent Swarm 控制台（桌面 GUI 应用）
#  由桌面快捷方式启动；点一下即可拉起整套系统并打开对话/工作台。
#
#  首次使用请先运行安装向导：
#    powershell -ExecutionPolicy Bypass -File .\setup.ps1
# ============================================================
param([switch]$SelfTest, [switch]$Chat)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# ---------- 配置（由 setup.ps1 生成 config.json） ----------
$script:guiDir = $PSScriptRoot
$script:repoRoot = Split-Path $script:guiDir -Parent
$script:cfgFile = Join-Path $script:repoRoot "config.json"
if (-not (Test-Path $script:cfgFile)) {
    try {
        Add-Type -AssemblyName PresentationFramework
        [System.Windows.MessageBox]::Show(
            "找不到配置文件 config.json。`n`n请先运行一次安装向导：`n`n  powershell -ExecutionPolicy Bypass -File .\setup.ps1",
            "Agent Swarm") | Out-Null
    }
    catch { }
    exit 2
}
$script:cfg = Get-Content $script:cfgFile -Raw -Encoding UTF8 | ConvertFrom-Json
$script:root = $script:cfg.swarmRoot
$script:ctl = Join-Path $script:guiDir "swarm-ctl.ps1"
$script:ico = Join-Path $script:repoRoot "assets\agent-swarm.ico"
$script:logo = Join-Path $script:cfg.swarmSrc "apps\ui\public\logo.png"
$script:proxyPort = if ($script:cfg.proxyPort) { [int]$script:cfg.proxyPort } else { 18080 }
$script:apiPort = if ($script:cfg.apiPort) { [int]$script:cfg.apiPort } else { 3013 }
$script:uiPort = if ($script:cfg.uiPort) { [int]$script:cfg.uiPort } else { 5274 }
$script:dashboard = "http://127.0.0.1:$($script:uiPort)/"
$script:chatUrl = "http://127.0.0.1:$($script:uiPort)/chat.html"
$script:openUrl = if ($Chat) { $script:chatUrl } else { $script:dashboard }
$script:edge = $script:cfg.edge

$script:job = $null
$script:tick = 0
$script:autoOpened = $false
$script:busy = $false

# ---------- 单实例守卫（避免重复打开多个控制台） ----------
$script:mutexCreated = $false
$script:mutex = New-Object System.Threading.Mutex($true, "Local\AgentSwarmConsole", [ref]$script:mutexCreated)
if (-not $script:mutexCreated) {
    try {
        $sig = @'
using System;
using System.Runtime.InteropServices;
public class SwarmWin32 {
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
'@
        Add-Type -TypeDefinition $sig -ErrorAction SilentlyContinue
        $hWnd = [SwarmWin32]::FindWindow($null, "Agent Swarm 控制台")
        if ($hWnd -ne [IntPtr]::Zero) {
            [void][SwarmWin32]::ShowWindow($hWnd, 9)   # SW_RESTORE
            [void][SwarmWin32]::SetForegroundWindow($hWnd)
        }
        else {
            if (Test-Path $script:edge) {
                Start-Process -FilePath $script:edge -ArgumentList "--app=$($script:openUrl)", "--window-size=1440,920"
            }
            else { Start-Process $script:openUrl }
        }
    }
    catch { }
    exit 0
}

# ---------- 配色 ----------
function C([string]$hex) { [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString($hex)) }
$script:colOk = C "#22C55E"
$script:colWarn = C "#F59E0B"
$script:colBad = C "#EF4444"
$script:colIdle = C "#52525B"
$script:colMuted = C "#8B8B93"
$script:colText = C "#C9C9CF"

# ---------- 界面 ----------
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Agent Swarm 控制台"
        Height="680" Width="1010" MinHeight="600" MinWidth="900"
        WindowStartupLocation="CenterScreen"
        Background="#0A0A0B"
        FontFamily="Segoe UI"
        UseLayoutRounding="True"
        TextOptions.TextFormattingMode="Display">
  <Window.Resources>
    <Style x:Key="Primary" TargetType="Button">
      <Setter Property="Foreground" Value="#1A1205"/>
      <Setter Property="FontSize" Value="14.5"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" CornerRadius="12" Background="#F59E0B">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="#FBBF24"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="bd" Property="Background" Value="#D97706"/></Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="bd" Property="Background" Value="#24242A"/>
                <Setter Property="Foreground" Value="#5A5A63"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Secondary" TargetType="Button">
      <Setter Property="Foreground" Value="#E4E4E7"/>
      <Setter Property="FontSize" Value="13.5"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" CornerRadius="12" Background="#1A1A1F" BorderBrush="#2A2A31" BorderThickness="1">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="#24242B"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="bd" Property="Background" Value="#151519"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter Property="Foreground" Value="#55555D"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Card" TargetType="Border">
      <Setter Property="Background" Value="#111114"/>
      <Setter Property="BorderBrush" Value="#222228"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="16"/>
    </Style>
    <Style x:Key="RowLabel" TargetType="TextBlock">
      <Setter Property="Foreground" Value="#C9C9CF"/>
      <Setter Property="FontSize" Value="13.5"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>
    <Style x:Key="RowValue" TargetType="TextBlock">
      <Setter Property="Foreground" Value="#75757E"/>
      <Setter Property="FontSize" Value="12.5"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>
  </Window.Resources>

  <Grid Margin="26,22,26,22">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="196"/>
    </Grid.RowDefinitions>

    <!-- 顶部 -->
    <Grid Grid.Row="0" Margin="0,0,0,20">
      <StackPanel Orientation="Horizontal">
        <Border Width="54" Height="54" CornerRadius="15" Background="#17171B" BorderBrush="#26262C" BorderThickness="1" Margin="0,0,16,0">
          <Image x:Name="imgLogo" Width="36" Height="36" Stretch="Uniform"/>
        </Border>
        <StackPanel VerticalAlignment="Center">
          <TextBlock Text="Agent Swarm" Foreground="#FAFAFA" FontSize="25" FontWeight="SemiBold"/>
          <TextBlock Text="你的 AI 开发团队  ·  点「开始对话」继续聊" Foreground="#75757E" FontSize="12.5" Margin="0,3,0,0"/>
        </StackPanel>
      </StackPanel>
      <Border HorizontalAlignment="Right" VerticalAlignment="Center" CornerRadius="20" Background="#111114" BorderBrush="#222228" BorderThickness="1" Padding="15,8">
        <StackPanel Orientation="Horizontal">
          <Ellipse x:Name="dotSummary" Width="9" Height="9" Fill="#52525B" Margin="0,0,9,0" VerticalAlignment="Center"/>
          <TextBlock x:Name="txtSummary" Text="检查中…" Foreground="#A1A1AA" FontSize="12.5"/>
        </StackPanel>
      </Border>
    </Grid>

    <!-- 主体 -->
    <Grid Grid.Row="1">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="306"/>
      </Grid.ColumnDefinitions>

      <Border Grid.Column="0" Style="{StaticResource Card}" Margin="0,0,16,0" Padding="22,20">
        <StackPanel>
          <TextBlock Text="运行状态" Foreground="#FAFAFA" FontSize="15.5" FontWeight="SemiBold"/>
          <TextBlock Text="全部就绪后即可开始派活" Foreground="#6B6B73" FontSize="12" Margin="0,4,0,18"/>

          <Grid Margin="0,0,0,13">
            <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <Ellipse x:Name="dotProxy" Width="10" Height="10" Fill="#52525B" VerticalAlignment="Center" Margin="0,0,13,0"/>
            <TextBlock Grid.Column="1" Text="宿主代理" Style="{StaticResource RowLabel}"/>
            <TextBlock x:Name="txtProxy" Grid.Column="2" Text="—" Style="{StaticResource RowValue}"/>
          </Grid>

          <Grid Margin="0,0,0,13">
            <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <Ellipse x:Name="dotDocker" Width="10" Height="10" Fill="#52525B" VerticalAlignment="Center" Margin="0,0,13,0"/>
            <TextBlock Grid.Column="1" Text="Docker 引擎" Style="{StaticResource RowLabel}"/>
            <TextBlock x:Name="txtDocker" Grid.Column="2" Text="—" Style="{StaticResource RowValue}"/>
          </Grid>

          <Grid Margin="0,0,0,13">
            <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <Ellipse x:Name="dotApi" Width="10" Height="10" Fill="#52525B" VerticalAlignment="Center" Margin="0,0,13,0"/>
            <TextBlock Grid.Column="1" Text="API 服务" Style="{StaticResource RowLabel}"/>
            <TextBlock x:Name="txtApi" Grid.Column="2" Text="—" Style="{StaticResource RowValue}"/>
          </Grid>

          <Grid Margin="0,0,0,13">
            <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <Ellipse x:Name="dotAgents" Width="10" Height="10" Fill="#52525B" VerticalAlignment="Center" Margin="0,0,13,0"/>
            <TextBlock Grid.Column="1" Text="AI 员工" Style="{StaticResource RowLabel}"/>
            <TextBlock x:Name="txtAgents" Grid.Column="2" Text="—" Style="{StaticResource RowValue}"/>
          </Grid>

          <Grid>
            <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <Ellipse x:Name="dotUi" Width="10" Height="10" Fill="#52525B" VerticalAlignment="Center" Margin="0,0,13,0"/>
            <TextBlock Grid.Column="1" Text="网页仪表盘" Style="{StaticResource RowLabel}"/>
            <TextBlock x:Name="txtUi" Grid.Column="2" Text="—" Style="{StaticResource RowValue}"/>
          </Grid>
        </StackPanel>
      </Border>

      <StackPanel Grid.Column="1">
        <Button x:Name="btnChat" Style="{StaticResource Primary}" Content="开始对话" Height="54" Margin="0,0,0,10"/>
        <Button x:Name="btnOpen"  Style="{StaticResource Secondary}" Content="打开工作台" Height="46" Margin="0,0,0,10"/>
        <Button x:Name="btnStart" Style="{StaticResource Secondary}" Content="启动 / 修复服务" Height="42" Margin="0,0,0,10"/>
        <Button x:Name="btnStop"  Style="{StaticResource Secondary}" Content="停止全部" Height="42" Margin="0,0,0,10"/>
        <Button x:Name="btnRefresh" Style="{StaticResource Secondary}" Content="刷新状态" Height="40" Margin="0,0,0,10"/>
        <Button x:Name="btnFolder" Style="{StaticResource Secondary}" Content="打开安装文件夹" Height="40"/>
      </StackPanel>
    </Grid>

    <!-- 日志 -->
    <Border Grid.Row="2" Style="{StaticResource Card}" Margin="0,16,0,0" Padding="0">
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <Border Grid.Row="0" BorderBrush="#222228" BorderThickness="0,0,0,1" Padding="20,11">
          <TextBlock Text="运行日志" Foreground="#FAFAFA" FontSize="13.5" FontWeight="SemiBold"/>
        </Border>
        <TextBox x:Name="logBox" Grid.Row="1" IsReadOnly="True" BorderThickness="0"
                 Background="Transparent" Foreground="#8E8E97"
                 FontFamily="Consolas" FontSize="12" Padding="18,11"
                 VerticalScrollBarVisibility="Auto" TextWrapping="Wrap" AcceptsReturn="True"/>
      </Grid>
    </Border>
  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

foreach ($n in 'imgLogo','dotSummary','txtSummary','dotProxy','txtProxy','dotDocker','txtDocker',
    'dotApi','txtApi','dotAgents','txtAgents','dotUi','txtUi','btnChat','btnStart','btnOpen','btnStop','btnRefresh','btnFolder','logBox') {
    Set-Variable -Name $n -Value $window.FindName($n) -Scope Script
}

# 图标 / LOGO
if (Test-Path $script:ico) { try { $window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create([Uri]$script:ico) } catch { } }
if (Test-Path $script:logo) {
    try {
        $bi = New-Object System.Windows.Media.Imaging.BitmapImage
        $bi.BeginInit(); $bi.UriSource = [Uri]$script:logo; $bi.CacheOption = 'OnLoad'; $bi.EndInit()
        $imgLogo.Source = $bi
    }
    catch { }
}

function Add-Log([string]$msg) {
    $ts = Get-Date -Format "HH:mm:ss"
    $logBox.AppendText("[$ts]  $msg`r`n")
    $logBox.ScrollToEnd()
}

function Set-Row($dot, $label, [string]$state, [string]$text) {
    switch ($state) {
        'ok' { $dot.Fill = $script:colOk }
        'warn' { $dot.Fill = $script:colWarn }
        'bad' { $dot.Fill = $script:colBad }
        default { $dot.Fill = $script:colIdle }
    }
    $label.Text = $text
}

function Test-Port([int]$p) {
    [bool](Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue)
}

function Set-Busy([bool]$b) {
    $script:busy = $b
    $btnStart.IsEnabled = -not $b
    $btnStop.IsEnabled = -not $b
    $btnRefresh.IsEnabled = -not $b
    $btnFolder.IsEnabled = -not $b
    $btnOpen.IsEnabled = -not $b
}

function Open-Target([string]$url) {
    if (Test-Path $script:edge) {
        Start-Process -FilePath $script:edge -ArgumentList "--app=$url", "--window-size=1440,920"
    }
    else { Start-Process $url }
    Add-Log "已打开 $url"
}
function Open-Dashboard { Open-Target $script:dashboard }
function Open-Chat { Open-Target $script:chatUrl }
function Open-Preferred { Open-Target $script:openUrl }

$script:allOk = $false

function Update-Status {
    $proxyOk = Test-Port $script:proxyPort
    Set-Row $dotProxy $txtProxy $(if ($proxyOk) { 'ok' } else { 'bad' }) $(if ($proxyOk) { '运行中' } else { '未启动' })

    $dockerOk = [bool](Get-Process -Name 'com.docker.backend' -ErrorAction SilentlyContinue)
    Set-Row $dotDocker $txtDocker $(if ($dockerOk) { 'ok' } else { 'bad' }) $(if ($dockerOk) { '运行中' } else { '未启动' })

    $apiUp = Test-Port $script:apiPort
    $health = ''; $ver = ''
    if ($apiUp) {
        try {
            $h = Invoke-RestMethod -Uri "http://localhost:$($script:apiPort)/health" -TimeoutSec 2
            $health = $h.status; $ver = $h.version
        }
        catch { }
    }
    $apiOk = ($apiUp -and $health -eq 'ok')
    Set-Row $dotApi $txtApi $(if ($apiOk) { 'ok' } elseif ($apiUp) { 'warn' } else { 'bad' }) $(if ($apiOk) { "v$ver" } elseif ($apiUp) { '启动中' } else { '未启动' })

    $agentCount = 0; $idle = 0; $busy = 0
    if ($apiOk) {
        try {
            $key = ((Get-Content "$($script:root)\.env" | Where-Object { $_ -match '^API_KEY=' } | Select-Object -First 1) -replace '^API_KEY=', '').Trim()
            $r = Invoke-RestMethod -Uri "http://localhost:$($script:apiPort)/api/agents" -Headers @{ Authorization = "Bearer $key" } -TimeoutSec 2
            $agentCount = @($r.agents).Count
            $idle = @($r.agents | Where-Object { $_.status -eq 'idle' }).Count
            $busy = @($r.agents | Where-Object { $_.status -eq 'busy' }).Count
        }
        catch { }
    }
    if ($agentCount -gt 0) { Set-Row $dotAgents $txtAgents 'ok' "$agentCount 名（$idle 空闲 / $busy 忙碌）" }
    else { Set-Row $dotAgents $txtAgents $(if ($apiOk) { 'warn' } else { 'bad' }) $(if ($apiOk) { '等待注册' } else { '未启动' }) }

    $uiOk = Test-Port $script:uiPort
    Set-Row $dotUi $txtUi $(if ($uiOk) { 'ok' } else { 'bad' }) $(if ($uiOk) { '运行中' } else { '未启动' })

    $script:allOk = ($proxyOk -and $dockerOk -and $apiOk -and ($agentCount -gt 0) -and $uiOk)
    if ($script:allOk) {
        $dotSummary.Fill = $script:colOk
        $txtSummary.Text = "全部就绪"
        $txtSummary.Foreground = C "#22C55E"
    }
    elseif ($script:busy) {
        $dotSummary.Fill = $script:colWarn
        $txtSummary.Text = "正在启动…"
        $txtSummary.Foreground = $script:colWarn
    }
    else {
        $dotSummary.Fill = $script:colWarn
        $txtSummary.Text = "部分未就绪"
        $txtSummary.Foreground = $script:colWarn
    }
}

function Start-Ctl([string]$action) {
    if ($script:busy) { return }
    Set-Busy $true
    Add-Log "—— 执行：$action ——"
    $script:pendingAction = $action
    $ctl = $script:ctl
    $script:job = Start-Job -ScriptBlock {
        param($ctlPath, $act)
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ctlPath -Action $act 2>&1
    } -ArgumentList $ctl, $action
}

# ---------- 事件 ----------
$btnChat.Add_Click({ Open-Chat })
$btnStart.Add_Click({ Start-Ctl 'start' })
$btnStop.Add_Click({
        $ans = [System.Windows.MessageBox]::Show(
            "确定要停止 AI 团队吗？`n`n数据会保留，下次启动即恢复。",
            "Agent Swarm",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Question)
        if ($ans -eq [System.Windows.MessageBoxResult]::Yes) { Start-Ctl 'stop' }
    })
$btnRefresh.Add_Click({ Update-Status; Add-Log "状态已刷新" })
$btnOpen.Add_Click({ Open-Dashboard })
$btnFolder.Add_Click({ Start-Process explorer.exe $script:repoRoot })

# ---------- 定时器 ----------
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(1200)
$timer.Add_Tick({
        if ($script:job) {
            $out = Receive-Job $script:job -ErrorAction SilentlyContinue
            foreach ($line in $out) {
                $s = ("$line").TrimEnd()
                if ($s -eq 'READY') { continue }
                if ($s -eq 'FAILED') { continue }
                if ($s -eq 'STOPPED') { continue }
                if ($s -match '^\s*$') { continue }
                Add-Log ($s -replace '^\s+', '    ')
            }
            if ($script:job.State -in @('Completed', 'Failed', 'Stopped')) {
                $kind = $script:pendingAction
                Remove-Job $script:job -Force -ErrorAction SilentlyContinue
                $script:job = $null
                Set-Busy $false
                Update-Status
                if ($kind -eq 'start') {
                    if ($script:allOk) {
                        if (-not $script:autoOpened) { $script:autoOpened = $true; Open-Preferred }
                        Add-Log "✔ 系统已就绪"
                    }
                    else { Add-Log "✘ 有项目未就绪，请查看上方日志" }
                }
                elseif ($kind -eq 'stop') { Add-Log "✔ 已停止" }
            }
        }

        $script:tick++
        if ($script:tick % 4 -eq 0) {
            Update-Status
            if ($script:allOk -and -not $script:autoOpened -and -not $script:busy -and $script:started) {
                $script:autoOpened = $true
                Open-Preferred
            }
        }
    })
$timer.Start()

# ---------- 启动 ----------
$window.Add_Loaded({
        Add-Log "Agent Swarm 控制台已启动"
        Update-Status
        $script:started = $true
        if ($script:allOk) {
            Add-Log "检测到服务已在运行"
            $script:autoOpened = $true
            Open-Preferred
        }
        else {
            Add-Log "服务未全部就绪，自动开始启动…"
            Start-Ctl 'start'
        }
    })

if ($SelfTest) {
    Write-Output "XAML_OK"
    $window.Close()
    exit 0
}

$window.ShowDialog() | Out-Null
