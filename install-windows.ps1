# Установка/обновление стороны Windows. Можно запускать повторно.
#   powershell -ExecutionPolicy Bypass -File install-windows.ps1
# Делает: проверяет OpenSSH, создаёт ключ sm_key и кладёт открытую часть в keys\,
# ставит модуль VirtualDesktop, создаёт автозапуск трея, запускает трей.
$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot
$win = Join-Path $root 'windows'
function Say([string]$m) { Write-Host "== $m" -ForegroundColor Cyan }

Say "Папка скриптов: $root"
if (-not (Test-Path $win)) { Write-Host "Нет папки $win - папка Second_monitor скопирована не полностью?" -ForegroundColor Red; exit 1 }

Say 'OpenSSH-клиент'
$ssh = Join-Path $env:SystemRoot 'System32\OpenSSH\ssh.exe'
if (-not (Test-Path $ssh)) {
  Write-Host 'Нет ssh.exe: Параметры -> Приложения -> Дополнительные компоненты -> Добавить -> OpenSSH-клиент' -ForegroundColor Red
  exit 1
}
Write-Host 'найден'

Say 'Ключ SSH для управления Pi'
$sshDir = Join-Path $env:USERPROFILE '.ssh'
New-Item -ItemType Directory -Force $sshDir | Out-Null
$key = Join-Path $sshDir 'sm_key'
if (-not (Test-Path $key)) {
  & "$env:SystemRoot\System32\cmd.exe" /c 'ssh-keygen -t ed25519 -f "%USERPROFILE%\.ssh\sm_key" -N ""' | Out-Null
}
if (Test-Path "$key.pub") {
  New-Item -ItemType Directory -Force (Join-Path $root 'keys') | Out-Null
  $dst = Join-Path $root ("keys\windows-{0}.pub" -f $env:COMPUTERNAME)
  Copy-Item "$key.pub" $dst -Force
  Write-Host "открытый ключ: $dst"
} else { Write-Host 'Ключ не создался - создай вручную: ssh-keygen -t ed25519 -f "%USERPROFILE%\.ssh\sm_key" -N ""' -ForegroundColor Red }

Say 'Модуль VirtualDesktop (закрепление окон на втором мониторе)'
if (Get-Module -ListAvailable -Name VirtualDesktop) { Write-Host 'уже установлен' }
else {
  try { Install-Module VirtualDesktop -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop; Write-Host 'установлен' }
  catch { Write-Host "Не удалось установить: $($_.Exception.Message)`nРучная установка: Install-Module VirtualDesktop -Scope CurrentUser" -ForegroundColor Yellow }
}

Say 'Старые копии скриптов в корне папки'
$old = Join-Path $root 'old'
Get-ChildItem $root -Filter 'second-monitor-*.ps1' -File | ForEach-Object {
  New-Item -ItemType Directory -Force $old | Out-Null
  Move-Item $_.FullName (Join-Path $old $_.Name) -Force
  Write-Host "перенесён в old\: $($_.Name)"
}

Say 'Автозапуск при входе в Windows'
$lnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'SecondMonitor.lnk'
$wsh = New-Object -ComObject WScript.Shell
$sc = $wsh.CreateShortcut($lnk)
$sc.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$sc.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$win\second-monitor-run.ps1`""
$sc.WorkingDirectory = $win
$sc.WindowStyle = 7
$sc.Description = 'Второй монитор на Raspberry Pi (трей)'
$sc.Save()
Write-Host "ярлык: $lnk"

Say 'Запуск трея'
Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$win\second-monitor-run.ps1`""
Write-Host 'запущен (значок в трее, может быть под стрелкой ^)'

Write-Host ''
Write-Host 'Дальше:' -ForegroundColor Green
Write-Host '  1) передай папку Second_monitor на Pi (Syncthing подойдёт, либо скопируй keys\ и hosts\ вручную)'
Write-Host '  2) на Pi: bash <папка Second_monitor>/install-pi.sh'
Write-Host '  3) в Apollo (https://localhost:47990 -> Applications) создай приложение "Second Monitor"'
Write-Host '     с галочкой "Always create Virtual Display" и пустой командой'
Write-Host '  4) спаривание Pi с Apollo (см. README.md), затем проверка: меню трея -> Диагностика'
