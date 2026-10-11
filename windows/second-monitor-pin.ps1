# Автозакрепление окон на втором мониторе.
# Окно, ушедшее на второй (не основной) монитор, закрепляется "на всех рабочих столах",
# и остаётся на месте при переключении рабочих столов на основном мониторе.
# Окно, вернувшееся на основной монитор, открепляется. Чужие закрепления не трогает.
# Нужен модуль VirtualDesktop (его ставит install-windows.ps1). Остановка: Ctrl+C.
Import-Module VirtualDesktop -WarningAction SilentlyContinue
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class WinApi2 {
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out int v, int s);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@
$plog = Join-Path $env:APPDATA 'SecondMonitor\pin.log'
New-Item -ItemType Directory -Force (Split-Path $plog) | Out-Null
if ((Test-Path $plog) -and ((Get-Item $plog).Length -gt 200KB)) { Remove-Item $plog }
function Plog([string]$m) { try { Add-Content $plog -Encoding UTF8 -Value ((Get-Date -Format 'HH:mm:ss') + ' ' + $m) } catch {} }
Plog 'pin watcher started'
$skipClasses = @('Shell_TrayWnd','Shell_SecondaryTrayWnd','Progman','WorkerW')
$self = 0; try { $self = ([IntPtr](Get-ConsoleHandle)).ToInt64() } catch {}
$mine = @{}
Write-Host 'Watching. Ctrl+C to stop.'
while ($true) {
  $others = @([System.Windows.Forms.Screen]::AllScreens | Where-Object { -not $_.Primary })
  if ($others.Count -eq 0) {
    # второго монитора нет: снимаем свои закрепления и ждём
    foreach ($k in @($mine.Keys)) { try { Unpin-Window ([IntPtr]$k) } catch {}; $mine.Remove($k) }
    Start-Sleep -Seconds 2; continue
  }
  $alive = @{}
  foreach ($w in (Find-WindowHandle *)) {
    try {
      $h = [IntPtr]$w.Handle
      $k = $h.ToInt64()
      $alive[$k] = $true
      if ($k -eq $self) { continue }
      if (-not [WinApi2]::IsWindowVisible($h) -or [WinApi2]::IsIconic($h)) { continue }
      $cloak = 0
      [void][WinApi2]::DwmGetWindowAttribute($h, 14, [ref]$cloak, 4)
      if ($cloak -ne 0) { continue }
      $sb = New-Object System.Text.StringBuilder 256
      [void][WinApi2]::GetClassName($h, $sb, 256)
      if ($skipClasses -contains $sb.ToString()) { continue }
      $r = New-Object WinApi2+RECT
      if (-not [WinApi2]::GetWindowRect($h, [ref]$r)) { continue }
      $cx = [int](($r.L + $r.R) / 2); $cy = [int](($r.T + $r.B) / 2)
      $onOther = $false
      foreach ($s in $others) { if ($s.Bounds.Contains($cx, $cy)) { $onOther = $true } }
      if ($onOther -and -not $mine.ContainsKey($k)) {
        if (-not (Test-WindowPinned $h)) { Pin-Window $h; $mine[$k] = $true; Write-Host ("PIN   " + $w.Title); Plog ("PIN   " + $w.Title) }
      } elseif (-not $onOther -and $mine.ContainsKey($k)) {
        Unpin-Window $h; $mine.Remove($k); Write-Host ("UNPIN " + $w.Title); Plog ("UNPIN " + $w.Title)
      }
    } catch { }
  }
  foreach ($k in @($mine.Keys)) { if (-not $alive.ContainsKey($k)) { $mine.Remove($k) } }
  Start-Sleep -Milliseconds 700
}
