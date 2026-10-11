# Иконка в трее: управление вторым монитором на Raspberry Pi.
#   левый клик - переключить Windows / рабочий стол Pi; правый клик - меню.
# Запускается стражем second-monitor-run.ps1 (он же перезапускает при сбое).
$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$catchOk = $true
try { [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException) } catch { $catchOk = $false }

$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, 'SecondMonitorTray', [ref]$createdNew)
if (-not $createdNew) { exit 0 }

# ---- настройки ----
$piUser = 'raspi'                                   # пользователь на Pi
$root = Split-Path $PSScriptRoot -Parent            # корень папки Second_monitor
$hostsDir = Join-Path $root 'hosts'
$key = Join-Path $env:USERPROFILE '.ssh\sm_key'
$ssh = Join-Path $env:SystemRoot 'System32\OpenSSH\ssh.exe'
$pinScript = Join-Path $PSScriptRoot 'second-monitor-pin.ps1'
$logDir = Join-Path $env:APPDATA 'SecondMonitor'
$logFile = Join-Path $logDir 'tray.log'

New-Item -ItemType Directory -Force $logDir | Out-Null
New-Item -ItemType Directory -Force $hostsDir | Out-Null
if ((Test-Path $logFile) -and ((Get-Item $logFile).Length -gt 200KB)) { Remove-Item $logFile }
function Log([string]$m) { try { Add-Content $logFile -Encoding UTF8 -Value ("{0:HH:mm:ss} {1}" -f (Get-Date), $m) } catch {} }
Log ("tray started, catchmode=" + $catchOk + ", root=" + $root)
[System.Windows.Forms.Application]::add_ThreadException({ param($s, $e) Log ('ThreadException: ' + $e.Exception.ToString()) })

$utf8 = New-Object System.Text.UTF8Encoding $false

# ---- списки адресов ----
function Read-List([string]$path) {
  if (-not (Test-Path $path)) { return @() }
  Get-Content $path -Encoding UTF8 | ForEach-Object { ($_ -replace '#.*$', '').Trim() } | Where-Object { $_ }
}
function Get-PiHosts {
  @(Read-List (Join-Path $hostsDir 'pi.auto.txt')) + @(Read-List (Join-Path $hostsDir 'pi.manual.txt')) | Select-Object -Unique
}
function Ensure-Manual([string]$name, [string]$what, [string]$who, [string]$example) {
  $p = Join-Path $hostsDir $name
  if (-not (Test-Path $p)) {
    $tpl = Join-Path $hostsDir ($name -replace '\.txt$', '.example.txt')
    if (Test-Path $tpl) { Copy-Item $tpl $p }
    else {
      $lines = @("# РУЧНОЙ список адресов $what (читает $who).",
                 '# По одному в строке: IP или имя. Всё после # - комментарий.',
                 $example)
      [System.IO.File]::WriteAllLines($p, $lines, $utf8)
    }
  }
  return $p
}
$piManual = Ensure-Manual 'pi.manual.txt' 'Raspberry Pi' 'трей на Windows' 'RaspiOS.local'
$winManual = Ensure-Manual 'windows.manual.txt' 'Windows-компьютера' 'Raspberry Pi' ("{0}.local" -f $env:COMPUTERNAME)

function Get-MyAddrs {
  $a = Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' -and $_.InterfaceAlias -notmatch 'VMware|Loopback|vEthernet|VirtualBox|Hyper-V' } |
    ForEach-Object { $_.IPAddress }
  @($a) + ("{0}.local" -f $env:COMPUTERNAME)
}
# Пишет текущие адреса этого компьютера в hosts\windows.auto.txt (читает Pi через Syncthing).
# Файл не трогает, если ничего не изменилось.
function Write-WindowsAuto {
  try {
    $lines = @('# Пишется автоматически треем Windows. Руками не правь.',
               '# Свои адреса добавляй в windows.manual.txt') + @(Get-MyAddrs)
    $dst = Join-Path $hostsDir 'windows.auto.txt'
    $old = @(); if (Test-Path $dst) { $old = @(Get-Content $dst -Encoding UTF8) }
    if (($old -join "`n") -eq ($lines -join "`n")) { return }
    $tmp = Join-Path $hostsDir ('.windows.auto.tmp.' + $PID)
    [System.IO.File]::WriteAllLines($tmp, $lines, $utf8)
    Move-Item -Force $tmp $dst
    Log 'windows.auto.txt updated'
  } catch { Log ('write auto error: ' + $_.Exception.Message) }
}
Write-WindowsAuto

# ---- уведомления ----
$notify = New-Object System.Windows.Forms.NotifyIcon
function Notify([string]$t, [string]$m) {
  try { $notify.ShowBalloonTip(4000, $t, $m, [System.Windows.Forms.ToolTipIcon]::Info) } catch { Log ('notify error: ' + $_.Exception.Message) }
}

# ---- фоновые SSH-задания (интерфейс не блокируется) ----
$global:jobs = New-Object System.Collections.ArrayList

function Start-PiJob([string]$cmd, [bool]$silent) {
  if (-not (Test-Path $key)) {
    Log 'ssh key missing'
    Notify 'Нет ключа SSH' 'Запусти install-windows.ps1 (создаст ключ), затем install-pi.sh на Pi.'
    return
  }
  if ($cmd -in @('start', 'stop', 'toggle') -and @($global:jobs | Where-Object { $_.Cmd -eq $cmd }).Count -gt 0) {
    Log "job $cmd ignored (already running)"; return
  }
  if ($cmd -eq 'start') { Write-WindowsAuto }
  $hosts = @(Get-PiHosts)
  if ($hosts.Count -eq 0) { Notify 'Нет адресов Pi' 'Добавь адрес Pi: меню -> «Изменить адреса Pi».'; return }
  $ps = [powershell]::Create()
  [void]$ps.AddScript({
    param($ssh, $key, $user, $hosts, $cmd)
    foreach ($h in $hosts) {
      $out = & $ssh -i $key -o BatchMode=yes -o ConnectTimeout=2 -o StrictHostKeyChecking=accept-new "$user@$h" $cmd 2>&1
      if ($LASTEXITCODE -ne 255) { return [pscustomobject]@{ Host = $h; Code = $LASTEXITCODE; Out = @($out) } }
    }
    return $null
  }).AddArgument($ssh).AddArgument($key).AddArgument($piUser).AddArgument($hosts).AddArgument($cmd)
  $handle = $ps.BeginInvoke()
  [void]$global:jobs.Add([pscustomobject]@{ PS = $ps; Handle = $handle; Cmd = $cmd; Silent = $silent })
  Log "job started: $cmd"
}

function Finish-Job($j, $r) {
  $cmd = $j.Cmd
  if (-not $r) {
    Log "job $cmd -> no host"
    if (-not $j.Silent) { Notify 'Нет связи с Pi' 'Ни один адрес Pi не ответил. Меню: «Изменить адреса Pi» (или проверь, включена ли Pi и сеть).' }
    return
  }
  Log "job $cmd -> host=$($r.Host) code=$($r.Code) out=$($r.Out -join ' | ')"
  switch ($cmd) {
    'ping'   { if ($r.Code -eq 0) { Notify 'Pi найдена' ("Адрес: $($r.Host)") } else { Notify 'Pi отвечает, но SSH-ключ не принят' 'Запусти install-pi.sh на Pi.' } }
    'start'  {
      if ($r.Code -eq 3) { Notify 'Windows не найден с Pi' 'Pi не нашла этот компьютер ни по одному адресу. Проверь, что служба Apollo запущена; адреса: меню -> «Изменить адреса Windows».' }
      elseif ($r.Code -ne 0 -and $r.Code -ne 4) { Notify 'Не удалось запустить' "Код ответа Pi: $($r.Code). Запусти диагностику (меню)." }
    }
    'toggle' { if ($r.Code -eq 1) { Notify 'Второй монитор' 'Стрим не запущен.' } elseif ($r.Code -ne 0) { Notify 'Ошибка переключения' "Код: $($r.Code)" } }
    'stop'   { if ($r.Code -ne 0) { Notify 'Ошибка остановки' "Код: $($r.Code)" } }
  }
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 400
$timer.add_Tick({
  try {
    foreach ($j in @($global:jobs)) {
      if ($j.Handle.IsCompleted) {
        [void]$global:jobs.Remove($j)
        $res = $null
        try { $res = $j.PS.EndInvoke($j.Handle) | Select-Object -First 1 } catch { Log ('job error: ' + $_.Exception.Message) }
        $j.PS.Dispose()
        Finish-Job $j $res
      }
    }
  } catch { Log ('timer error: ' + $_.Exception.Message) }
})
$timer.Start()

# раз в 10 минут проверяем, не сменились ли адреса этого компьютера
$addrTimer = New-Object System.Windows.Forms.Timer
$addrTimer.Interval = 600000
$addrTimer.add_Tick({ Write-WindowsAuto })
$addrTimer.Start()

# ---- значок и меню ----
function Make-Icon {
  $bmp = New-Object System.Drawing.Bitmap 16, 16
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.Clear([System.Drawing.Color]::Transparent)
  $g.FillRectangle([System.Drawing.Brushes]::SteelBlue, 0, 2, 10, 8)
  $g.FillRectangle([System.Drawing.Brushes]::DarkOrange, 6, 6, 10, 8)
  $g.Dispose()
  [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}

$menu = New-Object System.Windows.Forms.ContextMenuStrip
[void]$menu.Items.Add('Включить второй монитор').add_Click({ Start-PiJob 'start' $false })
[void]$menu.Items.Add('Переключить: Windows / рабочий стол Pi').add_Click({ Start-PiJob 'toggle' $false })
[void]$menu.Items.Add('Выключить второй монитор').add_Click({ Start-PiJob 'stop' $false })
[void]$menu.Items.Add('-')
[void]$menu.Items.Add('Проверить связь с Pi').add_Click({ Write-WindowsAuto; Start-PiJob 'ping' $false })
[void]$menu.Items.Add('Изменить адреса Pi').add_Click({ Start-Process notepad.exe $piManual })
[void]$menu.Items.Add('Изменить адреса Windows (для Pi)').add_Click({ Start-Process notepad.exe $winManual })
[void]$menu.Items.Add('Диагностика').add_Click({
  Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-File', "`"$PSScriptRoot\sm-doctor.ps1`""
})
[void]$menu.Items.Add('Окна на втором мониторе (диагностика)').add_Click({
  Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-File', "`"$PSScriptRoot\sm-windows.ps1`""
})
[void]$menu.Items.Add('Открыть папку скриптов').add_Click({ Start-Process explorer.exe $root })
[void]$menu.Items.Add('-')
$exitItem = $menu.Items.Add('Выход')

# закрепление окон: чужие "осиротевшие" копии закрываем, запускаем свою
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.CommandLine -like '*second-monitor-pin.ps1*' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
$pin = $null
if (Test-Path $pinScript) {
  $pin = Start-Process powershell -WindowStyle Hidden -PassThru -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$pinScript`""
}

$ctx = New-Object System.Windows.Forms.ApplicationContext
$exitItem.add_Click({
  Log 'exit'
  $timer.Stop(); $addrTimer.Stop()
  if ($pin -and -not $pin.HasExited) { $pin.Kill() }
  $notify.Visible = $false; $notify.Dispose()
  $ctx.ExitThread()
})

$global:lastClick = [DateTime]::MinValue
$notify.Icon = Make-Icon
$notify.Text = 'Второй монитор (Pi)'
$notify.ContextMenuStrip = $menu
$notify.add_MouseUp({
  param($s, $e)
  if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
    if (((Get-Date) - $global:lastClick).TotalMilliseconds -gt 800) {
      $global:lastClick = Get-Date
      Log 'left click -> toggle'
      Start-PiJob 'toggle' $false
    }
  }
})
$notify.Visible = $true
[System.Windows.Forms.Application]::Run($ctx)
exit 0
