# Test-InputDiagnostics.ps1
# Run INSIDE a Moonlight session (from the dock, Explorer, or a terminal):
#   powershell -NoProfile -ExecutionPolicy Bypass -File "C:\PC\Dev_Tools\iPad_Workstation\tools\Test-InputDiagnostics.ps1"
# Shows what Windows actually receives from the iPad: real touch, pen, or emulated mouse; wheel deltas;
# and whether a touch digitizer (Sunshine's synthetic pointer device) is present.
# Writes a log to tools\input-diagnostics.log. No admin rights needed. Close the window to exit.

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class InputDiag {
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int n);
    [DllImport("user32.dll")] public static extern IntPtr GetMessageExtraInfo();
}
"@

$log = Join-Path $PSScriptRoot 'input-diagnostics.log'
function W([string]$m) {
    $line = "{0:HH:mm:ss.fff}  {1}" -f (Get-Date), $m
    $line | Out-File -LiteralPath $log -Append -Encoding utf8
    $script:list.Items.Insert(0, $line)
    if ($script:list.Items.Count -gt 300) { $script:list.Items.RemoveAt(300) }
}

$win = New-Object System.Windows.Window
$win.Title = 'iPad Input Diagnostics'
$win.Width = 900; $win.Height = 640
$win.WindowStartupLocation = 'CenterScreen'
$grid = New-Object System.Windows.Controls.Grid
$r1 = New-Object System.Windows.Controls.RowDefinition; $r1.Height = '170'
$r2 = New-Object System.Windows.Controls.RowDefinition
$grid.RowDefinitions.Add($r1); $grid.RowDefinitions.Add($r2)

$pad = New-Object System.Windows.Controls.Border
$pad.Background = '#FF1F2937'; $pad.Margin = '10'; $pad.CornerRadius = '12'
$padText = New-Object System.Windows.Controls.TextBlock
$padText.Text = "Test pad: tap, long-press, one-finger drag, two-finger scroll, pinch here`n(scroll inside the list below as well)"
$padText.Foreground = 'White'; $padText.FontSize = 18; $padText.Margin = '16'; $padText.TextWrapping = 'Wrap'
$pad.Child = $padText
$pad.IsManipulationEnabled = $true
[System.Windows.Controls.Grid]::SetRow($pad, 0)

$script:list = New-Object System.Windows.Controls.ListBox
$list.FontFamily = 'Consolas'; $list.FontSize = 13; $list.Margin = '10'
[System.Windows.Controls.Grid]::SetRow($list, 1)
$grid.Children.Add($pad) | Out-Null; $grid.Children.Add($list) | Out-Null
$win.Content = $grid

# MI_WP_SIGNATURE: mouse messages synthesized from pen/touch carry 0xFF5157xx in extra info
function Src {
    $x = [int64][InputDiag]::GetMessageExtraInfo()
    if (($x -band 0xFFFFFF00) -eq 0xFF515700) { if ($x -band 0x80) { 'touch-promoted' } else { 'pen-promoted' } } else { 'mouse' }
}

$pad.Add_TouchDown({ param($s,$e) $p = $e.GetTouchPoint($pad).Position; W ("TOUCH DOWN   id={0} at {1:N0},{2:N0}  => REAL TOUCH reaches Windows" -f $e.TouchDevice.Id, $p.X, $p.Y) })
$pad.Add_TouchUp({ param($s,$e) W ("TOUCH UP     id={0}" -f $e.TouchDevice.Id) })
$pad.Add_StylusDown({ param($s,$e) W ("STYLUS DOWN  device={0} tablet={1}" -f $e.StylusDevice.Name, $e.StylusDevice.TabletDevice.Type) })
$pad.Add_ManipulationDelta({ param($s,$e) $d = $e.DeltaManipulation; if ([math]::Abs($d.Scale.X - 1) -gt 0.01) { W ("PINCH scale={0:N3}" -f $d.Scale.X) } elseif ([math]::Abs($d.Translation.Y) -gt 2) { W ("PAN dy={0:N1}" -f $d.Translation.Y) } })
$win.Add_PreviewMouseDown({ param($s,$e) W ("MOUSE DOWN   button={0} source={1} stylusDevice={2}" -f $e.ChangedButton, (Src), ($null -ne $e.StylusDevice)) })
$win.Add_PreviewMouseUp({ param($s,$e) W ("MOUSE UP     button={0}" -f $e.ChangedButton) })
$win.Add_PreviewMouseWheel({ param($s,$e) W ("WHEEL        delta={0}  {1}" -f $e.Delta, $(if ([math]::Abs($e.Delta) % 120 -ne 0) { '(high-resolution / fractional delta)' } else { '(standard notch)' })) })

$win.Add_Loaded({
    $dig = [InputDiag]::GetSystemMetrics(94)   # SM_DIGITIZER
    $max = [InputDiag]::GetSystemMetrics(95)   # SM_MAXIMUMTOUCHES
    $flags = @()
    if ($dig -band 0x01) { $flags += 'INTEGRATED_TOUCH' }
    if ($dig -band 0x02) { $flags += 'EXTERNAL_TOUCH' }
    if ($dig -band 0x04) { $flags += 'INTEGRATED_PEN' }
    if ($dig -band 0x08) { $flags += 'EXTERNAL_PEN' }
    if ($dig -band 0x40) { $flags += 'NID_READY' }
    W ("SM_DIGITIZER=0x{0:X} [{1}]  SM_MAXIMUMTOUCHES={2}" -f $dig, ($flags -join ','), $max)
    $routing = (Get-ItemProperty 'HKCU:\Control Panel\Desktop' -Name MouseWheelRouting -ErrorAction SilentlyContinue).MouseWheelRouting
    W ("MouseWheelRouting={0} (2 = scroll inactive windows on hover, Windows default)" -f $routing)
    W ("Screen: {0}x{1} DIP" -f [System.Windows.SystemParameters]::PrimaryScreenWidth, [System.Windows.SystemParameters]::PrimaryScreenHeight)
    W "Interpretation: only MOUSE lines while touching = Moonlight is emulating a mouse (no native touch)."
})

"===== session {0} =====" -f (Get-Date) | Out-File -LiteralPath $log -Append -Encoding utf8
$win.ShowDialog() | Out-Null
