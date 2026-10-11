# Диагностика стороны Windows: "всё установлено, но ничего не работает".
# Запуск: powershell -ExecutionPolicy Bypass -File sm-doctor.ps1   (или меню трея -> Диагностика)
$ErrorActionPreference = 'SilentlyContinue'
$root = Split-Path $PSScriptRoot -Parent
$hostsDir = Join-Path $root 'hosts'
$key = Join-Path $env:USERPROFILE '.ssh\sm_key'
$ssh = Join-Path $env:SystemRoot 'System32\OpenSSH\ssh.exe'
$piUser = 'raspi'
$script:fails = 0
function Ok([string]$m)   { Write-Host "[ OK ] $m" -ForegroundColor Green }
function Bad([string]$m)  { Write-Host "[FAIL] $m" -ForegroundColor Red; $script:fails++ }
function Warn([string]$m) { Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Read-List([string]$path) {
  if (-not (Test-Path $path)) { return @() }
  Get-Content $path -Encoding UTF8 | ForEach-Object { ($_ -replace '#.*$', '').Trim() } | Where-Object { $_ }
}

Write-Host '== Apollo (сервер стрима) =='
$svc = Get-Service -Name 'ApolloService', 'SunshineService' | Select-Object -First 1
if ($svc) {
  if ($svc.Status -eq 'Running') { Ok "служба $($svc.Name) работает" } else { Bad "служба $($svc.Name) остановлена -> net start $($svc.Name) (cmd от администратора)" }
} else { Bad 'служба Apollo не найдена -> установить: winget install ClassicOldSong.Apollo --source winget' }
$listen = Get-NetTCPConnection -State Listen -LocalPort 47989
if ($listen) { Ok 'порт 47989 слушается' } else { Bad 'порт 47989 не слушается (Apollo не принимает подключения; перезапусти службу)' }
$vd = Get-PnpDevice | Where-Object { $_.FriendlyName -match 'SudoMaker|SudoVDA|Virtual Display' -and $_.Class -eq 'Display' }
if ($vd) { Ok "драйвер виртуального дисплея: $(($vd | Select-Object -First 1).FriendlyName)" } else { Warn 'драйвер виртуального дисплея (SudoVDA) не виден; он ставится вместе с Apollo. Если монитор не появляется - переустанови Apollo' }

Write-Host '== Сеть =='
Get-NetConnectionProfile | ForEach-Object {
  $line = "$($_.InterfaceAlias): профиль $($_.NetworkCategory)"
  if ($_.NetworkCategory -eq 'Public') { Warn "$line (входящие подключения могут блокироваться; для доверенной сети: Set-NetConnectionProfile -InterfaceAlias '<имя>' -NetworkCategory Private)" } else { Ok $line }
}
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' -and $_.InterfaceAlias -notmatch 'VMware|Loopback|vEthernet|VirtualBox' } |
  ForEach-Object { Write-Host "       адрес: $($_.IPAddress)  ($($_.InterfaceAlias))" }

Write-Host '== Управление Pi (SSH) =='
if (Test-Path $ssh) { Ok 'ssh.exe найден' } else { Bad 'нет OpenSSH-клиента (Параметры -> Приложения -> Дополнительные компоненты -> OpenSSH-клиент)' }
if (Test-Path $key) { Ok "ключ есть: $key" } else { Bad 'нет ключа sm_key -> запусти install-windows.ps1' }
$pubs = @(Get-ChildItem (Join-Path $root 'keys') -Filter '*.pub')
if ($pubs.Count -gt 0) { Ok "открытых ключей в keys\: $($pubs.Count)" } else { Warn 'в keys\ нет *.pub - Pi не узнает этот компьютер (install-windows.ps1, затем install-pi.sh)' }
if (Get-Module -ListAvailable -Name VirtualDesktop) { Ok 'модуль VirtualDesktop установлен' } else { Warn 'нет модуля VirtualDesktop (автозакрепление окон не работает): Install-Module VirtualDesktop -Scope CurrentUser' }

Write-Host '== Процессы =='
$ps = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'"
if ($ps | Where-Object { $_.CommandLine -like '*second-monitor-tray.ps1*' }) { Ok 'трей запущен' } else { Warn 'трей не запущен -> second-monitor-run.ps1' }
if ($ps | Where-Object { $_.CommandLine -like '*second-monitor-pin.ps1*' }) { Ok 'закрепление окон работает' } else { Warn 'скрипт закрепления окон не запущен (его стартует трей)' }

Write-Host '== Адреса Pi (порядок проверки) =='
$list = @(Read-List (Join-Path $hostsDir 'pi.auto.txt')) + @(Read-List (Join-Path $hostsDir 'pi.manual.txt')) | Select-Object -Unique
if (-not $list) { Bad "списки пусты -> впиши адрес Pi в $hostsDir\pi.manual.txt" }
$good = $null
foreach ($h in $list) {
  if (-not (Test-Path $key) -or -not (Test-Path $ssh)) { break }
  $out = & $ssh -i $key -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new "$piUser@$h" ping 2>&1
  $code = $LASTEXITCODE
  if ($code -eq 0) { Ok "$h : Pi отвечает ($out)"; $good = $h }
  elseif ($code -eq 255) { Warn "$h : нет соединения ($(($out | Select-Object -First 1)))" }
  else { Warn "$h : SSH отвечает, но ключ не принят или скрипт не установлен (код $code) -> install-pi.sh на Pi" }
}
if ($list -and -not $good) { Bad 'ни один адрес Pi не ответил. Pi включена? В той же сети / ZeroTier? Адрес сменился? -> добавь в pi.manual.txt' }

Write-Host ''
if ($script:fails -eq 0) { Write-Host 'Итог: критичных проблем не найдено.' -ForegroundColor Green } else { Write-Host "Итог: проблем найдено: $($script:fails) (см. [FAIL] выше)." -ForegroundColor Red }
Write-Host 'Журнал трея: ' (Join-Path $env:APPDATA 'SecondMonitor\tray.log')
