# Показывает, какие окна лежат на каком мониторе и закреплены ли они на всех рабочих столах.
# Нужна для разбора случая "на втором мониторе что-то переключается вместе с рабочими столами":
# окна SECOND с pinned=False - именно они уезжают при смене рабочего стола.
# Запуск: меню трея -> "Окна на втором мониторе" или
#   powershell -ExecutionPolicy Bypass -File sm-windows.ps1
$ErrorActionPreference = 'SilentlyContinue'
Import-Module VirtualDesktop -WarningAction SilentlyContinue
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class W3 {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RC r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [StructLayout(LayoutKind.Sequential)] public struct RC { public int L, T, Rt, B; }
}
"@
$sc = [System.Windows.Forms.Screen]::AllScreens
Write-Host ("Мониторов: " + $sc.Count + "  (" + (($sc | ForEach-Object { if ($_.Primary) { 'основной ' + $_.Bounds.Width + 'x' + $_.Bounds.Height } else { 'второй ' + $_.Bounds.Width + 'x' + $_.Bounds.Height } }) -join ', ') + ')')
Write-Host ('Текущий рабочий стол: ' + (Get-DesktopIndex (Get-CurrentDesktop)))
Write-Host ''
foreach ($w in (Find-WindowHandle *)) {
  $h = [IntPtr]$w.Handle
  if (-not [W3]::IsWindowVisible($h)) { continue }
  $r = New-Object W3+RC; [void][W3]::GetWindowRect($h, [ref]$r)
  $cx = [int](($r.L + $r.Rt) / 2); $cy = [int](($r.T + $r.B) / 2)
  $mon = $sc | Where-Object { $_.Bounds.Contains($cx, $cy) } | Select-Object -First 1
  if ($mon) { "{0,-8} pinned={1,-5} {2}" -f $(if ($mon.Primary) { 'PRIMARY' } else { 'SECOND' }), (Test-WindowPinned $h), $w.Title }
}
