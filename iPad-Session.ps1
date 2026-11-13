param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('Start','Stop','Recover')]
    [string]$Mode
)

$ErrorActionPreference = 'Stop'
$statePath   = Join-Path $PSScriptRoot "session_state.json"
$dispBakPath = Join-Path $PSScriptRoot "display_topology_backup.json"
$pidFile     = Join-Path $PSScriptRoot "touchdock.pid"
$logFile     = Join-Path $PSScriptRoot "session.log"

function Write-SessionLog([string]$msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$ts [$Mode] $msg" | Out-File -LiteralPath $logFile -Append -Encoding utf8 -ErrorAction SilentlyContinue
}

Add-Type -AssemblyName System.Windows.Forms

Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public class SessionNative {
    public const uint SPI_SETCURSORS = 0x0057;
    public const uint SPI_GETMOUSECURSORSIZE = 0x2028;
    public const uint SPI_SETMOUSECURSORSIZE = 0x2029;
    public const uint SPIF_UPDATEINIFILE = 0x01;
    public const uint SPIF_SENDCHANGE = 0x02;

    public const uint QDC_ONLY_ACTIVE_PATHS = 2;
    public const uint SDC_APPLY = 0x00000080;
    public const uint SDC_VALIDATE = 0x00000040;
    public const uint SDC_USE_SUPPLIED_DISPLAY_CONFIG = 0x00000020;
    public const uint SDC_ALLOW_CHANGES = 0x00000400;
    public const uint DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME = 2;
    public const uint DISPLAYCONFIG_MODE_INFO_TYPE_SOURCE = 1;

    [StructLayout(LayoutKind.Sequential)] public struct LUID { public uint LowPart; public int HighPart; }
    [StructLayout(LayoutKind.Sequential)] public struct DISPLAYCONFIG_RATIONAL { public uint Numerator; public uint Denominator; }
    [StructLayout(LayoutKind.Sequential)] public struct DISPLAYCONFIG_PATH_SOURCE_INFO {
        public LUID adapterId; public uint id; public uint modeInfoIdx; public uint statusFlags;
    }
    [StructLayout(LayoutKind.Sequential)] public struct DISPLAYCONFIG_PATH_TARGET_INFO {
        public LUID adapterId; public uint id; public uint modeInfoIdx;
        public uint outputTechnology; public uint rotation; public uint scaling;
        public DISPLAYCONFIG_RATIONAL refreshRate; public uint scanLineOrdering;
        public bool targetAvailable; public uint statusFlags;
    }
    [StructLayout(LayoutKind.Sequential)] public struct DISPLAYCONFIG_PATH_INFO {
        public DISPLAYCONFIG_PATH_SOURCE_INFO sourceInfo;
        public DISPLAYCONFIG_PATH_TARGET_INFO targetInfo;
        public uint flags;
    }
    [StructLayout(LayoutKind.Sequential)] public struct DISPLAYCONFIG_MODE_INFO {
        public uint infoType; public uint id; public LUID adapterId;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst=48)] public byte[] data;
    }
    [StructLayout(LayoutKind.Sequential)] public struct DISPLAYCONFIG_DEVICE_INFO_HEADER {
        public uint type; public uint size; public LUID adapterId; public uint id;
    }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    public struct DISPLAYCONFIG_TARGET_DEVICE_NAME {
        public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
        public uint flags; public uint outputTechnology;
        public ushort edidManufactureId; public ushort edidProductCodeId;
        public uint connectorInstance;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=64)] public string monitorFriendlyDeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string monitorDevicePath;
    }

    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, IntPtr pvParam, uint fWinIni);
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, ref int pvParam, uint fWinIni);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")] public static extern int GetDisplayConfigBufferSizes(uint flags, out uint numPathArrayElements, out uint numModeInfoArrayElements);
    [DllImport("user32.dll")] public static extern int QueryDisplayConfig(uint flags, ref uint numPathArrayElements, [Out] DISPLAYCONFIG_PATH_INFO[] pathArray, ref uint numModeInfoArrayElements, [Out] DISPLAYCONFIG_MODE_INFO[] modeInfoArray, IntPtr currentTopologyId);
    [DllImport("user32.dll")] public static extern int SetDisplayConfig(uint numPathArrayElements, [In] DISPLAYCONFIG_PATH_INFO[] pathArray, uint numModeInfoArrayElements, [In] DISPLAYCONFIG_MODE_INFO[] modeInfoArray, uint flags);
    [DllImport("user32.dll")] public static extern int DisplayConfigGetDeviceInfo(ref DISPLAYCONFIG_TARGET_DEVICE_NAME requestPacket);

    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    public static int FindMttPathIndex(DISPLAYCONFIG_PATH_INFO[] paths) {
        for (int i = 0; i < paths.Length; i++) {
            var tn = new DISPLAYCONFIG_TARGET_DEVICE_NAME();
            tn.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME;
            tn.header.size = (uint)Marshal.SizeOf(typeof(DISPLAYCONFIG_TARGET_DEVICE_NAME));
            tn.header.adapterId = paths[i].targetInfo.adapterId;
            tn.header.id = paths[i].targetInfo.id;
            if (DisplayConfigGetDeviceInfo(ref tn) == 0) {
                if (tn.monitorFriendlyDeviceName == "VDD by MTT" ||
                    (tn.monitorDevicePath != null && tn.monitorDevicePath.IndexOf("MTT1337", StringComparison.OrdinalIgnoreCase) >= 0)) {
                    return i;
                }
            }
        }
        return -1;
    }

    public static int GetLiveCursorSize() {
        int val = 32;
        SystemParametersInfo(SPI_GETMOUSECURSORSIZE, 0, ref val, 0);
        return val;
    }

    public static void SetLiveCursorSize(int pixelSize) {
        SystemParametersInfo(SPI_SETMOUSECURSORSIZE, 0, (IntPtr)pixelSize, SPIF_UPDATEINIFILE | SPIF_SENDCHANGE);
        SystemParametersInfo(SPI_SETCURSORS, 0, IntPtr.Zero, SPIF_UPDATEINIFILE | SPIF_SENDCHANGE);
    }

    public static int MoveOffscreenWindowsToArea(int waLeft, int waTop, int waWidth, int waHeight) {
        int moved = 0;
        EnumWindows((h, l) => {
            if (!IsWindowVisible(h) || IsIconic(h)) return true;
            int ex = GetWindowLong(h, -20);
            if ((ex & 0x00000080) != 0) return true; // skip WS_EX_TOOLWINDOW
            var cls = new StringBuilder(64);
            GetClassName(h, cls, 64);
            string c = cls.ToString();
            if (c == "Shell_TrayWnd" || c == "Progman" || c == "WorkerW" || c == "Windows.UI.Core.CoreWindow") return true;
            var title = new StringBuilder(128);
            GetWindowText(h, title, 128);
            if (title.Length == 0 || title.ToString() == "iPadTouchDock") return true;

            RECT r;
            if (!GetWindowRect(h, out r)) return true;
            int w = r.Right - r.Left;
            int hgt = r.Bottom - r.Top;
            if (w <= 40 || hgt <= 40) return true;

            int cx = r.Left + w / 2;
            int cy = r.Top + hgt / 2;
            bool inside = (cx >= waLeft && cx < waLeft + waWidth && cy >= waTop && cy < waTop + waHeight);
            if (!inside) {
                int newW = Math.Min(w, waWidth - 24);
                int newH = Math.Min(hgt, waHeight - 24);
                int newX = waLeft + Math.Max(12, (waWidth - newW) / 2);
                int newY = waTop + Math.Max(12, (waHeight - newH) / 2);
                SetWindowPos(h, IntPtr.Zero, newX, newY, newW, newH, 0x0004 | 0x0010); // SWP_NOZORDER | SWP_NOACTIVATE
                moved++;
            }
            return true;
        }, IntPtr.Zero);
        return moved;
    }
}
"@

$cursorRoles = @(
    'AppStarting','Arrow','Crosshair','Hand','Help','IBeam','No','NWPen',
    'SizeAll','SizeNESW','SizeNS','SizeNWSE','SizeWE','UpArrow','Wait',
    'precisionhair','Person','Pin','Grab','Pan','Grabbing','Zoom-in','Zoom-out'
)

function Apply-BibataClassicScheme {
    $bibataDir = 'C:\Windows\Cursors\Bibata-Modern-Classic-Regular Cursors'
    if (-not (Test-Path -LiteralPath $bibataDir)) {
        Write-SessionLog "Bibata folder not found at $bibataDir; keeping existing cursor scheme"
        return
    }
    $curPath = 'HKCU:\Control Panel\Cursors'
    $map = @{
        '(default)'     = 'Bibata-Modern-Classic-Regular Cursors'
        'AppStarting'   = Join-Path $bibataDir 'Work.ani'
        'Arrow'         = Join-Path $bibataDir 'Pointer.cur'
        'Crosshair'     = Join-Path $bibataDir 'Cross.cur'
        'Hand'          = Join-Path $bibataDir 'Link.cur'
        'Help'          = Join-Path $bibataDir 'Help.cur'
        'IBeam'         = Join-Path $bibataDir 'Text.cur'
        'No'            = Join-Path $bibataDir 'Unavailable.cur'
        'NWPen'         = Join-Path $bibataDir 'Handwriting.cur'
        'SizeAll'       = Join-Path $bibataDir 'Move.cur'
        'SizeNESW'      = Join-Path $bibataDir 'Dgn2.cur'
        'SizeNS'        = Join-Path $bibataDir 'Vert.cur'
        'SizeNWSE'      = Join-Path $bibataDir 'Dgn1.cur'
        'SizeWE'        = Join-Path $bibataDir 'Horz.cur'
        'UpArrow'       = Join-Path $bibataDir 'Alternate.cur'
        'Wait'          = Join-Path $bibataDir 'Busy.ani'
    }
    foreach ($kv in $map.GetEnumerator()) {
        if ($kv.Key -eq '(default)' -or (Test-Path -LiteralPath $kv.Value)) {
            Set-ItemProperty -Path $curPath -Name $kv.Key -Value $kv.Value -Force -ErrorAction SilentlyContinue
        }
    }
    Write-SessionLog "Applied Bibata-Modern-Classic-Regular Cursors scheme"
}

function Set-CursorSizeImmediate([int]$pixelSize) {
    $curPath = 'HKCU:\Control Panel\Cursors'
    $accPath = 'HKCU:\Software\Microsoft\Accessibility'
    Set-ItemProperty -Path $curPath -Name 'CursorBaseSize' -Value $pixelSize -Type DWord -Force
    if (Test-Path $accPath) {
        # Windows 11 Accessibility CursorSize: 1=32px, 2=48px, 3=64px
        $accLevel = [Math]::Max(1, [int][Math]::Round(($pixelSize - 16) / 16))
        Set-ItemProperty -Path $accPath -Name 'CursorSize' -Value $accLevel -Type DWord -Force
    }
    [SessionNative]::SetLiveCursorSize($pixelSize)
}

function Save-And-IsolateMttDisplay {
    try {
        [uint32]$pc = 0; [uint32]$mc = 0
        $rc = [SessionNative]::GetDisplayConfigBufferSizes([SessionNative]::QDC_ONLY_ACTIVE_PATHS, [ref]$pc, [ref]$mc)
        if ($rc -ne 0 -or $pc -eq 0) {
            Write-SessionLog "DisplayConfig buffer query failed (rc=$rc, paths=$pc)"
            return
        }
        $paths = New-Object SessionNative+DISPLAYCONFIG_PATH_INFO[] $pc
        $modes = New-Object SessionNative+DISPLAYCONFIG_MODE_INFO[] $mc
        $rc = [SessionNative]::QueryDisplayConfig([SessionNative]::QDC_ONLY_ACTIVE_PATHS, [ref]$pc, $paths, [ref]$mc, $modes, [IntPtr]::Zero)
        if ($rc -ne 0) {
            Write-SessionLog "QueryDisplayConfig failed (rc=$rc)"
            return
        }

        $mttIdx = [SessionNative]::FindMttPathIndex($paths)

        if ($mttIdx -lt 0) {
            Write-SessionLog "MTT virtual display not found in active paths ($pc active); skipping display isolation"
            return
        }

        if (-not (Test-Path -LiteralPath $dispBakPath)) {
            $serPaths = foreach ($p in $paths) {
                @{
                    srcAdapterLow  = $p.sourceInfo.adapterId.LowPart
                    srcAdapterHigh = $p.sourceInfo.adapterId.HighPart
                    srcId          = $p.sourceInfo.id
                    srcModeIdx     = $p.sourceInfo.modeInfoIdx
                    srcStatus      = $p.sourceInfo.statusFlags
                    tgtAdapterLow  = $p.targetInfo.adapterId.LowPart
                    tgtAdapterHigh = $p.targetInfo.adapterId.HighPart
                    tgtId          = $p.targetInfo.id
                    tgtModeIdx     = $p.targetInfo.modeInfoIdx
                    outputTech     = $p.targetInfo.outputTechnology
                    rotation       = $p.targetInfo.rotation
                    scaling        = $p.targetInfo.scaling
                    rrNum          = $p.targetInfo.refreshRate.Numerator
                    rrDen          = $p.targetInfo.refreshRate.Denominator
                    scanLine       = $p.targetInfo.scanLineOrdering
                    tgtAvail       = $p.targetInfo.targetAvailable
                    tgtStatus      = $p.targetInfo.statusFlags
                    flags          = $p.flags
                }
            }
            $serModes = foreach ($m in $modes) {
                @{
                    infoType    = $m.infoType
                    id          = $m.id
                    adapterLow  = $m.adapterId.LowPart
                    adapterHigh = $m.adapterId.HighPart
                    dataB64     = [Convert]::ToBase64String($m.data)
                }
            }
            @{ paths = $serPaths; modes = $serModes } | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $dispBakPath -Encoding utf8 -Force
            Write-SessionLog "Saved display topology backup ($pc paths, $mc modes) to display_topology_backup.json"
        } else {
            Write-SessionLog "display_topology_backup.json already exists; preserving original topology"
        }

        if ($pc -le 1) {
            Write-SessionLog "MTT virtual display is already the only active display"
            return
        }

        $singlePath = New-Object SessionNative+DISPLAYCONFIG_PATH_INFO[] 1
        $singlePath[0] = $paths[$mttIdx]
        $singleModes = $modes.Clone()
        $srcModeIdx = $singlePath[0].sourceInfo.modeInfoIdx
        if ($srcModeIdx -lt $singleModes.Length -and $singleModes[$srcModeIdx].infoType -eq [SessionNative]::DISPLAYCONFIG_MODE_INFO_TYPE_SOURCE) {
            for ($b = 8; $b -lt 16; $b++) { $singleModes[$srcModeIdx].data[$b] = 0 }
        }
        $flags = [SessionNative]::SDC_APPLY -bor [SessionNative]::SDC_USE_SUPPLIED_DISPLAY_CONFIG -bor [SessionNative]::SDC_ALLOW_CHANGES
        $sdcRc = [SessionNative]::SetDisplayConfig(1, $singlePath, [uint32]$singleModes.Length, $singleModes, $flags)
        if ($sdcRc -eq 0) {
            Write-SessionLog "Isolated active display to MTT virtual display only (SetDisplayConfig rc=0)"
        } else {
            Write-SessionLog "SetDisplayConfig MTT-only returned rc=$sdcRc (non-zero); continuing with window relocation fallback"
        }
    } catch {
        Write-SessionLog "Display isolation warning: $_"
    }
}

function Restore-DisplayTopology {
    if (-not (Test-Path -LiteralPath $dispBakPath)) { return }
    try {
        $bak = Get-Content -LiteralPath $dispBakPath -Raw | ConvertFrom-Json
        $pList = @($bak.paths)
        $mList = @($bak.modes)
        if ($pList.Count -eq 0) { return }

        $paths = New-Object SessionNative+DISPLAYCONFIG_PATH_INFO[] $pList.Count
        for ($i = 0; $i -lt $pList.Count; $i++) {
            $sp = $pList[$i]
            $p = New-Object SessionNative+DISPLAYCONFIG_PATH_INFO
            $p.sourceInfo.adapterId.LowPart  = [uint32]$sp.srcAdapterLow
            $p.sourceInfo.adapterId.HighPart = [int]$sp.srcAdapterHigh
            $p.sourceInfo.id                 = [uint32]$sp.srcId
            $p.sourceInfo.modeInfoIdx        = [uint32]$sp.srcModeIdx
            $p.sourceInfo.statusFlags        = [uint32]$sp.srcStatus
            $p.targetInfo.adapterId.LowPart  = [uint32]$sp.tgtAdapterLow
            $p.targetInfo.adapterId.HighPart = [int]$sp.tgtAdapterHigh
            $p.targetInfo.id                 = [uint32]$sp.tgtId
            $p.targetInfo.modeInfoIdx        = [uint32]$sp.tgtModeIdx
            $p.targetInfo.outputTechnology   = [uint32]$sp.outputTech
            $p.targetInfo.rotation           = [uint32]$sp.rotation
            $p.targetInfo.scaling            = [uint32]$sp.scaling
            $p.targetInfo.refreshRate.Numerator   = [uint32]$sp.rrNum
            $p.targetInfo.refreshRate.Denominator = [uint32]$sp.rrDen
            $p.targetInfo.scanLineOrdering   = [uint32]$sp.scanLine
            $p.targetInfo.targetAvailable    = [bool]$sp.tgtAvail
            $p.targetInfo.statusFlags        = [uint32]$sp.tgtStatus
            $p.flags                         = [uint32]$sp.flags
            $paths[$i] = $p
        }

        $modes = New-Object SessionNative+DISPLAYCONFIG_MODE_INFO[] $mList.Count
        for ($i = 0; $i -lt $mList.Count; $i++) {
            $sm = $mList[$i]
            $m = New-Object SessionNative+DISPLAYCONFIG_MODE_INFO
            $m.infoType           = [uint32]$sm.infoType
            $m.id                 = [uint32]$sm.id
            $m.adapterId.LowPart  = [uint32]$sm.adapterLow
            $m.adapterId.HighPart = [int]$sm.adapterHigh
            $m.data               = [Convert]::FromBase64String($sm.dataB64)
            $modes[$i] = $m
        }

        $flags = [SessionNative]::SDC_APPLY -bor [SessionNative]::SDC_USE_SUPPLIED_DISPLAY_CONFIG -bor [SessionNative]::SDC_ALLOW_CHANGES
        $rc = [SessionNative]::SetDisplayConfig([uint32]$paths.Length, $paths, [uint32]$modes.Length, $modes, $flags)
        Write-SessionLog "Restored display topology from backup (rc=$rc, paths=$($paths.Length))"
        if ($rc -eq 0) {
            Remove-Item -LiteralPath $dispBakPath -Force -ErrorAction SilentlyContinue
        }
    } catch {
        Write-SessionLog "ERROR restoring display topology: $_"
    }
}

function Get-RunningDockPids {
    $pids = @()
    if (Test-Path -LiteralPath $pidFile) {
        $raw = (Get-Content -LiteralPath $pidFile -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($raw -match '^\d+$') {
            $p = Get-Process -Id ([int]$raw) -ErrorAction SilentlyContinue
            if ($p) { $pids += $p.Id }
        }
    }
    try {
        $wmi = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" -ErrorAction SilentlyContinue |
               Where-Object {
                   $_.ProcessId -ne $PID -and
                   $_.CommandLine -match '-File\s+["'']?[^"'']*iPad-TouchDock\.ps1'
               }
        foreach ($proc in $wmi) {
            if ($pids -notcontains $proc.ProcessId) { $pids += [int]$proc.ProcessId }
        }
    } catch {}
    return $pids
}

$ttPath = 'HKCU:\Software\Microsoft\TabletTip\1.7'

if ($Mode -eq 'Start') {
    Write-SessionLog "Starting iPad Workstation session"
    try {
        if (-not (Test-Path $ttPath)) {
            New-Item -Path $ttPath -Force | Out-Null
        }

        # Save original state once (do not overwrite if Start is called twice without Stop)
        if (-not (Test-Path -LiteralPath $statePath)) {
            $cur = Get-ItemProperty 'HKCU:\Control Panel\Cursors' -ErrorAction SilentlyContinue
            $acc = Get-ItemProperty 'HKCU:\Software\Microsoft\Accessibility' -ErrorAction SilentlyContinue
            $tt  = Get-ItemProperty $ttPath -ErrorAction SilentlyContinue
            $schemeBackup = @{ '(default)' = if ($cur) { [string]$cur.'(default)' } else { '' } }
            foreach ($role in $cursorRoles) {
                if ($cur -and $null -ne $cur.$role) { $schemeBackup[$role] = [string]$cur.$role }
            }
            @{
                CursorBaseSize              = [SessionNative]::GetLiveCursorSize()
                AccessibilityCursorSize     = if ($acc -and $null -ne $acc.CursorSize) { [int]$acc.CursorSize } else { 1 }
                CursorScheme                = $schemeBackup
                TipbandDesiredVisibility    = if ($tt -and $null -ne $tt.TipbandDesiredVisibility) { [int]$tt.TipbandDesiredVisibility } else { 0 }
                TouchKeyboardTapInvoke      = if ($tt -and $null -ne $tt.TouchKeyboardTapInvoke) { [int]$tt.TouchKeyboardTapInvoke } else { 0 }
                EnableDesktopModeAutoInvoke = if ($tt -and $null -ne $tt.EnableDesktopModeAutoInvoke) { [int]$tt.EnableDesktopModeAutoInvoke } else { 0 }
            } | ConvertTo-Json -Depth 4 | Out-File -LiteralPath $statePath -Encoding utf8 -Force
            Write-SessionLog "Saved original state to session_state.json"
        } else {
            Write-SessionLog "session_state.json already exists; preserving original backup"
        }

        # Isolate display to MTT virtual display (when permitted) and sweep off-screen windows
        Save-And-IsolateMttDisplay
        $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
        $movedCount = [SessionNative]::MoveOffscreenWindowsToArea($wa.Left, $wa.Top, $wa.Width, $wa.Height)
        Write-SessionLog "Moved $movedCount off-screen window(s) onto primary virtual display ($($wa.Width)x$($wa.Height))"

        # Apply Bibata-Modern-Classic-Regular and enlarge live cursor to 48px
        Apply-BibataClassicScheme
        Set-CursorSizeImmediate 48
        Write-SessionLog "Live cursor size set to 48 (SPI_GETMOUSECURSORSIZE=$([SessionNative]::GetLiveCursorSize()))"

        # Enable Windows 11 Touch Keyboard tray button & tap invoke
        Set-ItemProperty -Path $ttPath -Name 'TipbandDesiredVisibility' -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $ttPath -Name 'TouchKeyboardTapInvoke' -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $ttPath -Name 'EnableDesktopModeAutoInvoke' -Value 1 -Type DWord -Force
        Write-SessionLog "TabletTip registry enabled"

        # Start Touch Dock if not already running
        $runningPids = Get-RunningDockPids
        if ($runningPids.Count -eq 0) {
            if (Test-Path -LiteralPath $pidFile) { Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue }
            $dockScript = Join-Path $PSScriptRoot "iPad-TouchDock.ps1"
            Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$dockScript`"" -WindowStyle Hidden
            for ($i = 0; $i -lt 30; $i++) {
                if (Test-Path -LiteralPath $pidFile) { break }
                Start-Sleep -Milliseconds 100
            }
            Write-SessionLog "TouchDock started (pidFile exists: $(Test-Path -LiteralPath $pidFile))"
        } else {
            Write-SessionLog "TouchDock already running (PIDs: $($runningPids -join ', '))"
        }

        # Focus existing visible Brave window or launch Brave in Touch UI mode
        $braveWin = Get-Process -Name 'brave' -ErrorAction SilentlyContinue |
                    Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } |
                    Select-Object -First 1
        if ($braveWin) {
            $h = $braveWin.MainWindowHandle
            if ([SessionNative]::IsIconic($h)) { [SessionNative]::ShowWindow($h, 9) | Out-Null }
            [SessionNative]::SetForegroundWindow($h) | Out-Null
            Write-SessionLog "Focused existing Brave window (PID $($braveWin.Id))"
        } else {
            $braveLauncher = Join-Path $PSScriptRoot "Launch-Brave-iPad.cmd"
            if (Test-Path -LiteralPath $braveLauncher) {
                Start-Process -FilePath $braveLauncher -WindowStyle Hidden
                Write-SessionLog "Launched Brave via Launch-Brave-iPad.cmd"
            }
        }
    } catch {
        Write-SessionLog "ERROR during Start: $_"
        throw
    }
}
elseif ($Mode -eq 'Stop' -or $Mode -eq 'Recover') {
    Write-SessionLog "Stopping/recovering iPad Workstation session"
    try {
        $runningPids = Get-RunningDockPids
        foreach ($dpid in $runningPids) {
            Stop-Process -Id $dpid -Force -ErrorAction SilentlyContinue
            Write-SessionLog "Stopped TouchDock PID $dpid"
        }
        if (Test-Path -LiteralPath $pidFile) {
            Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
        }

        Restore-DisplayTopology

        if (Test-Path -LiteralPath $statePath) {
            $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
            if ($state.CursorScheme) {
                $curPath = 'HKCU:\Control Panel\Cursors'
                foreach ($prop in $state.CursorScheme.PSObject.Properties) {
                    Set-ItemProperty -Path $curPath -Name $prop.Name -Value ([string]$prop.Value) -Force -ErrorAction SilentlyContinue
                }
            }
            $origCursor = if ($null -ne $state.CursorBaseSize) { [int]$state.CursorBaseSize } else { 32 }
            Set-CursorSizeImmediate $origCursor
            if ($null -ne $state.AccessibilityCursorSize -and (Test-Path 'HKCU:\Software\Microsoft\Accessibility')) {
                Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Accessibility' -Name 'CursorSize' -Value ([int]$state.AccessibilityCursorSize) -Type DWord -Force
            }
            if (Test-Path $ttPath) {
                Set-ItemProperty -Path $ttPath -Name 'TipbandDesiredVisibility' -Value ([int]$state.TipbandDesiredVisibility) -Type DWord -Force
                Set-ItemProperty -Path $ttPath -Name 'TouchKeyboardTapInvoke' -Value ([int]$state.TouchKeyboardTapInvoke) -Type DWord -Force
                Set-ItemProperty -Path $ttPath -Name 'EnableDesktopModeAutoInvoke' -Value ([int]$state.EnableDesktopModeAutoInvoke) -Type DWord -Force
            }
            Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
            Write-SessionLog "Restored original state (LiveCursorSize=$([SessionNative]::GetLiveCursorSize())) and removed session_state.json"
        } else {
            Set-CursorSizeImmediate 32
            Write-SessionLog "No session_state.json found; reset CursorBaseSize to 32"
        }
    } catch {
        Write-SessionLog "ERROR during Stop/Recover: $_"
        throw
    }
}
