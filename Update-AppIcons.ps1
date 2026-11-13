# Extracts high-resolution transparent PNG icons from local Windows executables into assets/icons/
param()

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public static class IconExtractor {
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint PrivateExtractIcons(
        string szFileName, int nIconIndex, int cxIcon, int cyIcon,
        IntPtr[] phicon, uint[] piconid, uint nIcons, uint flags);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyIcon(IntPtr hIcon);

    public static bool SaveIconPng(string sourceFile, int iconIndex, int size, string outPng) {
        IntPtr[] hIcons = new IntPtr[1];
        uint[] ids = new uint[1];
        uint count = PrivateExtractIcons(sourceFile, iconIndex, size, size, hIcons, ids, 1, 0);
        if (count == 0 || hIcons[0] == IntPtr.Zero) return false;
        try {
            using (Icon ico = Icon.FromHandle(hIcons[0]))
            using (Bitmap bmp = ico.ToBitmap()) {
                bmp.Save(outPng, ImageFormat.Png);
            }
            return true;
        } finally {
            DestroyIcon(hIcons[0]);
        }
    }
}
"@

$iconDir = Join-Path $PSScriptRoot "assets\icons"
New-Item -ItemType Directory -Path $iconDir -Force | Out-Null

$targets = @(
    @{ Name = 'brave';    Src = 'C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe'; Idx = 0 },
    @{ Name = 'files';    Src = 'C:\Windows\explorer.exe'; Idx = 0 },
    @{ Name = 'settings'; Src = 'C:\Windows\ImmersiveControlPanel\SystemSettings.exe'; Idx = 0 },
    @{ Name = 'steam';    Src = 'C:\Program Files (x86)\Steam\steam.exe'; Idx = 0 },
    @{ Name = 'vlc';      Src = 'C:\Program Files\VideoLAN\VLC\vlc.exe'; Idx = 0 },
    @{ Name = 'notepad';  Src = 'C:\Windows\System32\notepad.exe'; Idx = 0 },
    @{ Name = 'taskmgr';  Src = 'C:\Windows\System32\Taskmgr.exe'; Idx = 0 },
    @{ Name = 'desktop';  Src = 'C:\Windows\System32\shell32.dll'; Idx = 34 }
)

foreach ($t in $targets) {
    $out = Join-Path $iconDir "$($t.Name).png"
    if (Test-Path -LiteralPath $t.Src) {
        $ok = [IconExtractor]::SaveIconPng($t.Src, $t.Idx, 128, $out)
        if (-not $ok) {
            $ok = [IconExtractor]::SaveIconPng($t.Src, 0, 64, $out)
        }
        Write-Output "$($t.Name): ok=$ok -> $out"
    } else {
        Write-Warning "Missing source for $($t.Name): $($t.Src)"
    }
}
