# Страж: запускает трей скрыто и перезапускает его, если он аварийно завершился.
# Нормальный выход из меню трея ("Выход") завершает и стража.
$dir = $PSScriptRoot
while ($true) {
  $p = Start-Process powershell -WindowStyle Hidden -PassThru -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$dir\second-monitor-tray.ps1`""
  $p.WaitForExit()
  if ($p.ExitCode -eq 0) { break }
  Start-Sleep -Seconds 2
}
