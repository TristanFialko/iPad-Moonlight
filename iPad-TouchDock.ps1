# Touch Dock & Home Launcher for iPad Moonlight sessions (Phase 5 Liquid-Glass Edition)
# Uses WS_EX_NOACTIVATE so tapping dock controls never steals focus from active apps.
param()

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class TouchDockNative {
    public const int GWL_EXSTYLE = -20;
    public const int WS_EX_NOACTIVATE = 0x08000000;
    public const int WS_EX_TOOLWINDOW = 0x00000080;

    public const uint INPUT_KEYBOARD = 1;
    public const uint KEYEVENTF_EXTENDEDKEY = 0x0001;
    public const uint KEYEVENTF_KEYUP = 0x0002;
    public const int SW_RESTORE = 9;

    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public INPUTUNION u; }
    [StructLayout(LayoutKind.Explicit)] public struct INPUTUNION {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
        [FieldOffset(0)] public HARDWAREINPUT hi;
    }
    [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT {
        public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr dwExtraInfo;
    }
    [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT {
        public ushort wVk, wScan; public uint dwFlags, time; public IntPtr dwExtraInfo;
    }
    [StructLayout(LayoutKind.Sequential)] public struct HARDWAREINPUT {
        public uint uMsg; public ushort wParamL, wParamH;
    }

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)] public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll", SetLastError = true)] public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
    [DllImport("user32.dll", SetLastError = true)] public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, System.Text.StringBuilder lpClassName, int nMaxCount);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);

    private static bool IsExtendedKey(ushort vk) {
        switch (vk) {
            case 0x21: case 0x22: case 0x23: case 0x24:
            case 0x25: case 0x26: case 0x27: case 0x28:
            case 0x2D: case 0x2E: case 0x5B: case 0x5C: case 0x5D:
                return true;
            default:
                return false;
        }
    }

    public static void SendCombo(params ushort[] keys) {
        var inputs = new List<INPUT>(keys.Length * 2);
        foreach (ushort k in keys) {
            uint flags = IsExtendedKey(k) ? KEYEVENTF_EXTENDEDKEY : 0;
            inputs.Add(new INPUT {
                type = INPUT_KEYBOARD,
                u = new INPUTUNION { ki = new KEYBDINPUT { wVk = k, dwFlags = flags } }
            });
        }
        for (int i = keys.Length - 1; i >= 0; i--) {
            ushort k = keys[i];
            uint flags = KEYEVENTF_KEYUP | (IsExtendedKey(k) ? KEYEVENTF_EXTENDEDKEY : 0);
            inputs.Add(new INPUT {
                type = INPUT_KEYBOARD,
                u = new INPUTUNION { ki = new KEYBDINPUT { wVk = k, dwFlags = flags } }
            });
        }
        SendInput((uint)inputs.Count, inputs.ToArray(), Marshal.SizeOf(typeof(INPUT)));
    }

    public static void EnsureWindowOnArea(IntPtr hWnd, int waLeft, int waTop, int waWidth, int waHeight) {
        RECT r;
        if (!GetWindowRect(hWnd, out r)) return;
        int w = r.Right - r.Left;
        int hgt = r.Bottom - r.Top;
        if (w <= 40 || hgt <= 40) return;
        int cx = r.Left + w / 2;
        int cy = r.Top + hgt / 2;
        if (cx < waLeft || cx >= waLeft + waWidth || cy < waTop || cy >= waTop + waHeight) {
            int newW = Math.Min(w, waWidth - 24);
            int newH = Math.Min(hgt, waHeight - 24);
            int newX = waLeft + Math.Max(12, (waWidth - newW) / 2);
            int newY = waTop + Math.Max(12, (waHeight - newH) / 2);
            SetWindowPos(hWnd, IntPtr.Zero, newX, newY, newW, newH, 0x0004 | 0x0010);
        }
    }

    public static int GatherAllWindows(int waLeft, int waTop, int waWidth, int waHeight) {
        int moved = 0;
        EnumWindows((h, l) => {
            if (!IsWindowVisible(h) || IsIconic(h)) return true;
            if ((GetWindowLong(h, -20) & 0x00000080) != 0) return true;
            var cls = new System.Text.StringBuilder(64);
            GetClassName(h, cls, 64);
            string c = cls.ToString();
            if (c == "Shell_TrayWnd" || c == "Progman" || c == "WorkerW" || c == "Windows.UI.Core.CoreWindow") return true;
            var title = new System.Text.StringBuilder(128);
            GetWindowText(h, title, 128);
            if (title.Length == 0 || title.ToString() == "iPadTouchDock") return true;
            RECT r;
            if (!GetWindowRect(h, out r)) return true;
            int w = r.Right - r.Left, hgt = r.Bottom - r.Top;
            if (w <= 40 || hgt <= 40) return true;
            int cx = r.Left + w / 2, cy = r.Top + hgt / 2;
            if (cx < waLeft || cx >= waLeft + waWidth || cy < waTop || cy >= waTop + waHeight) {
                EnsureWindowOnArea(h, waLeft, waTop, waWidth, waHeight);
                moved++;
            }
            return true;
        }, IntPtr.Zero);
        return moved;
    }
}
"@

# Write PID file so iPad-Session.ps1 -Mode Stop can close us cleanly
$pidFile = Join-Path $PSScriptRoot "touchdock.pid"
$PID | Out-File -LiteralPath $pidFile -Force -Encoding ascii

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="iPadTouchDock"
        WindowStyle="None"
        AllowsTransparency="True"
        Background="Transparent"
        Topmost="True"
        ShowInTaskbar="False"
        SizeToContent="WidthAndHeight"
        ResizeMode="NoResize"
        Opacity="0">
    <Window.Resources>
        <Style x:Key="IconText" TargetType="TextBlock">
            <Setter Property="FontFamily" Value="Segoe Fluent Icons"/>
            <Setter Property="FontSize" Value="15"/>
            <Setter Property="HorizontalAlignment" Value="Center"/>
            <Setter Property="VerticalAlignment" Value="Center"/>
            <Setter Property="Foreground" Value="#F3F4F6"/>
        </Style>

        <Style x:Key="LabelText" TargetType="TextBlock">
            <Setter Property="FontFamily" Value="Segoe UI Variable Text, Segoe UI"/>
            <Setter Property="FontSize" Value="10.5"/>
            <Setter Property="FontWeight" Value="Medium"/>
            <Setter Property="HorizontalAlignment" Value="Center"/>
            <Setter Property="Foreground" Value="#D1D5DB"/>
            <Setter Property="Margin" Value="0,2,0,0"/>
        </Style>

        <Style x:Key="SectionTitle" TargetType="TextBlock">
            <Setter Property="FontFamily" Value="Segoe UI Variable Text, Segoe UI"/>
            <Setter Property="FontSize" Value="10.5"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Foreground" Value="#9CA3AF"/>
            <Setter Property="Margin" Value="4,2,0,6"/>
        </Style>

        <Style x:Key="DockDivider" TargetType="Border">
            <Setter Property="Width" Value="1"/>
            <Setter Property="Height" Value="28"/>
            <Setter Property="Background" Value="#24FFFFFF"/>
            <Setter Property="Margin" Value="5,0"/>
            <Setter Property="VerticalAlignment" Value="Center"/>
        </Style>

        <Style x:Key="DockBtn" TargetType="Button">
            <Setter Property="Focusable" Value="False"/>
            <Setter Property="Background" Value="#16FFFFFF"/>
            <Setter Property="Foreground" Value="#F9FAFB"/>
            <Setter Property="BorderBrush" Value="#22FFFFFF"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontFamily" Value="Segoe UI Variable Text, Segoe UI"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="Medium"/>
            <Setter Property="Height" Value="50"/>
            <Setter Property="MinWidth" Value="52"/>
            <Setter Property="Padding" Value="9,4"/>
            <Setter Property="Margin" Value="2.5,0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="15"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="#2EFFFFFF"/>
                                <Setter TargetName="bd" Property="BorderBrush" Value="#48FFFFFF"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="#D90A84FF"/>
                                <Setter TargetName="bd" Property="BorderBrush" Value="#88FFFFFF"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="DrawerBtn" TargetType="Button" BasedOn="{StaticResource DockBtn}">
            <Setter Property="Height" Value="44"/>
            <Setter Property="MinWidth" Value="92"/>
            <Setter Property="Margin" Value="3"/>
            <Setter Property="Padding" Value="11,4"/>
            <Setter Property="Background" Value="#14FFFFFF"/>
        </Style>

        <Style x:Key="LauncherTile" TargetType="Button" BasedOn="{StaticResource DockBtn}">
            <Setter Property="Width" Value="114"/>
            <Setter Property="Height" Value="100"/>
            <Setter Property="Margin" Value="6"/>
            <Setter Property="Padding" Value="8"/>
            <Setter Property="Background" Value="#14FFFFFF"/>
            <Setter Property="BorderBrush" Value="#20FFFFFF"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="20"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Stretch" VerticalAlignment="Stretch"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="#2AFFFFFF"/>
                                <Setter TargetName="bd" Property="BorderBrush" Value="#4CFFFFFF"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="#CC0A84FF"/>
                                <Setter TargetName="bd" Property="BorderBrush" Value="#90FFFFFF"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="RunningPill" TargetType="Button" BasedOn="{StaticResource DockBtn}">
            <Setter Property="Height" Value="40"/>
            <Setter Property="MinWidth" Value="120"/>
            <Setter Property="MaxWidth" Value="210"/>
            <Setter Property="Margin" Value="4"/>
            <Setter Property="Padding" Value="10,4"/>
            <Setter Property="Background" Value="#1EFFFFFF"/>
            <Setter Property="BorderBrush" Value="#30FFFFFF"/>
        </Style>
    </Window.Resources>

    <StackPanel x:Name="RootStack" Orientation="Vertical" HorizontalAlignment="Center" Margin="18,16,18,18">
        <StackPanel.LayoutTransform>
            <ScaleTransform x:Name="DockScale" ScaleX="1" ScaleY="1"/>
        </StackPanel.LayoutTransform>

        <!-- Home Launcher Overlay -->
        <Border x:Name="LauncherOverlay"
                Visibility="Collapsed"
                Opacity="0"
                Background="#EC12151C"
                BorderBrush="#40FFFFFF"
                BorderThickness="1"
                CornerRadius="26"
                Padding="20,18"
                Margin="0,0,0,12"
                HorizontalAlignment="Center">
            <Border.Effect>
                <DropShadowEffect BlurRadius="32" ShadowDepth="10" Opacity="0.55" Color="#000000"/>
            </Border.Effect>
            <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                <StackPanel Orientation="Vertical" MaxWidth="528">
                    <DockPanel Margin="4,0,4,12">
                        <StackPanel Orientation="Vertical">
                            <TextBlock Text="iPad Workstation"
                                       FontFamily="Segoe UI Variable Display, Segoe UI"
                                       FontSize="18" FontWeight="SemiBold" Foreground="#F9FAFB"/>
                            <TextBlock Text="Tap an app to launch or switch windows"
                                       FontFamily="Segoe UI Variable Text, Segoe UI"
                                       FontSize="11.5" Foreground="#9CA3AF" Margin="0,2,0,0"/>
                        </StackPanel>
                        <Button x:Name="BtnCloseLauncher" DockPanel.Dock="Right" Style="{StaticResource DockBtn}"
                                Height="36" MinWidth="36" Padding="6" HorizontalAlignment="Right" ToolTip="Close Launcher">
                            <TextBlock Text="&#xE711;" Style="{StaticResource IconText}" FontSize="12"/>
                        </Button>
                    </DockPanel>

                    <!-- Running Now (Dynamic with real app icons) -->
                    <TextBlock x:Name="RunningHeader" Text="RUNNING NOW" Style="{StaticResource SectionTitle}"/>
                    <WrapPanel x:Name="RunningAppsPanel" Orientation="Horizontal" Margin="0,0,0,12"/>

                    <!-- Favorite Apps (4x2 Grid with real extracted logos) -->
                    <TextBlock Text="FAVORITES" Style="{StaticResource SectionTitle}"/>
                    <UniformGrid Columns="4" HorizontalAlignment="Center">
                        <Button x:Name="LaunchBrave" Style="{StaticResource LauncherTile}" ToolTip="Brave Browser">
                            <Grid>
                                <Ellipse x:Name="DotBrave" Width="7" Height="7" Fill="#34D399" HorizontalAlignment="Right" VerticalAlignment="Top" Visibility="Collapsed"/>
                                <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
                                    <Image x:Name="ImgBrave" Width="46" Height="46" Margin="0,0,0,7" RenderOptions.BitmapScalingMode="HighQuality"/>
                                    <TextBlock Text="Brave" FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="12.5" FontWeight="SemiBold" Foreground="#F3F4F6" HorizontalAlignment="Center"/>
                                </StackPanel>
                            </Grid>
                        </Button>
                        <Button x:Name="LaunchFiles" Style="{StaticResource LauncherTile}" ToolTip="File Explorer">
                            <Grid>
                                <Ellipse x:Name="DotFiles" Width="7" Height="7" Fill="#34D399" HorizontalAlignment="Right" VerticalAlignment="Top" Visibility="Collapsed"/>
                                <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
                                    <Image x:Name="ImgFiles" Width="46" Height="46" Margin="0,0,0,7" RenderOptions.BitmapScalingMode="HighQuality"/>
                                    <TextBlock Text="Files" FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="12.5" FontWeight="SemiBold" Foreground="#F3F4F6" HorizontalAlignment="Center"/>
                                </StackPanel>
                            </Grid>
                        </Button>
                        <Button x:Name="LaunchSettings" Style="{StaticResource LauncherTile}" ToolTip="Windows Settings">
                            <Grid>
                                <Ellipse x:Name="DotSettings" Width="7" Height="7" Fill="#34D399" HorizontalAlignment="Right" VerticalAlignment="Top" Visibility="Collapsed"/>
                                <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
                                    <Image x:Name="ImgSettings" Width="46" Height="46" Margin="0,0,0,7" RenderOptions.BitmapScalingMode="HighQuality"/>
                                    <TextBlock Text="Settings" FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="12.5" FontWeight="SemiBold" Foreground="#F3F4F6" HorizontalAlignment="Center"/>
                                </StackPanel>
                            </Grid>
                        </Button>
                        <Button x:Name="LaunchSteam" Style="{StaticResource LauncherTile}" ToolTip="Steam">
                            <Grid>
                                <Ellipse x:Name="DotSteam" Width="7" Height="7" Fill="#34D399" HorizontalAlignment="Right" VerticalAlignment="Top" Visibility="Collapsed"/>
                                <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
                                    <Image x:Name="ImgSteam" Width="46" Height="46" Margin="0,0,0,7" RenderOptions.BitmapScalingMode="HighQuality"/>
                                    <TextBlock Text="Steam" FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="12.5" FontWeight="SemiBold" Foreground="#F3F4F6" HorizontalAlignment="Center"/>
                                </StackPanel>
                            </Grid>
                        </Button>
                        <Button x:Name="LaunchVLC" Style="{StaticResource LauncherTile}" ToolTip="VLC Media Player">
                            <Grid>
                                <Ellipse x:Name="DotVLC" Width="7" Height="7" Fill="#34D399" HorizontalAlignment="Right" VerticalAlignment="Top" Visibility="Collapsed"/>
                                <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
                                    <Image x:Name="ImgVLC" Width="46" Height="46" Margin="0,0,0,7" RenderOptions.BitmapScalingMode="HighQuality"/>
                                    <TextBlock Text="VLC" FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="12.5" FontWeight="SemiBold" Foreground="#F3F4F6" HorizontalAlignment="Center"/>
                                </StackPanel>
                            </Grid>
                        </Button>
                        <Button x:Name="LaunchNotepad" Style="{StaticResource LauncherTile}" ToolTip="Notepad">
                            <Grid>
                                <Ellipse x:Name="DotNotepad" Width="7" Height="7" Fill="#34D399" HorizontalAlignment="Right" VerticalAlignment="Top" Visibility="Collapsed"/>
                                <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
                                    <Image x:Name="ImgNotepad" Width="46" Height="46" Margin="0,0,0,7" RenderOptions.BitmapScalingMode="HighQuality"/>
                                    <TextBlock Text="Notepad" FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="12.5" FontWeight="SemiBold" Foreground="#F3F4F6" HorizontalAlignment="Center"/>
                                </StackPanel>
                            </Grid>
                        </Button>
                        <Button x:Name="LaunchTaskMgr" Style="{StaticResource LauncherTile}" ToolTip="Task Manager">
                            <Grid>
                                <Ellipse x:Name="DotTaskMgr" Width="7" Height="7" Fill="#34D399" HorizontalAlignment="Right" VerticalAlignment="Top" Visibility="Collapsed"/>
                                <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
                                    <Image x:Name="ImgTaskMgr" Width="46" Height="46" Margin="0,0,0,7" RenderOptions.BitmapScalingMode="HighQuality"/>
                                    <TextBlock Text="Task Mgr" FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="12.5" FontWeight="SemiBold" Foreground="#F3F4F6" HorizontalAlignment="Center"/>
                                </StackPanel>
                            </Grid>
                        </Button>
                        <Button x:Name="LaunchDesktop" Style="{StaticResource LauncherTile}" ToolTip="Show Desktop">
                            <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
                                <Image x:Name="ImgDesktop" Width="46" Height="46" Margin="0,0,0,7" RenderOptions.BitmapScalingMode="HighQuality"/>
                                <TextBlock Text="Desktop" FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="12.5" FontWeight="SemiBold" Foreground="#F3F4F6" HorizontalAlignment="Center"/>
                            </StackPanel>
                        </Button>
                    </UniformGrid>
                </StackPanel>
            </ScrollViewer>
        </Border>

        <!-- Secondary Quick Actions Drawer -->
        <Border x:Name="MoreDrawer"
                Visibility="Collapsed"
                Opacity="0"
                Background="#EC12151C"
                BorderBrush="#40FFFFFF"
                BorderThickness="1"
                CornerRadius="22"
                Padding="16,14"
                Margin="0,0,0,12"
                HorizontalAlignment="Center">
            <Border.Effect>
                <DropShadowEffect BlurRadius="28" ShadowDepth="8" Opacity="0.52" Color="#000000"/>
            </Border.Effect>
            <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                <StackPanel Orientation="Vertical">
                    <!-- Section 1: Clipboard & Edit -->
                    <TextBlock Text="CLIPBOARD &amp; EDIT" Style="{StaticResource SectionTitle}"/>
                    <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                        <Button x:Name="BtnClipHist" Style="{StaticResource DrawerBtn}" ToolTip="Clipboard History (Win+V)">
                            <StackPanel Orientation="Horizontal">
                                <TextBlock Text="&#xF0E3;" Style="{StaticResource IconText}" Margin="0,0,7,0"/>
                                <TextBlock Text="Clipboard" VerticalAlignment="Center"/>
                            </StackPanel>
                        </Button>
                        <Button x:Name="BtnCut" Style="{StaticResource DrawerBtn}" MinWidth="76" ToolTip="Cut (Ctrl+X)">
                            <StackPanel Orientation="Horizontal">
                                <TextBlock Text="&#xE8C6;" Style="{StaticResource IconText}" Margin="0,0,6,0"/>
                                <TextBlock Text="Cut" VerticalAlignment="Center"/>
                            </StackPanel>
                        </Button>
                        <Button x:Name="BtnRedo" Style="{StaticResource DrawerBtn}" MinWidth="78" ToolTip="Redo (Ctrl+Y)">
                            <StackPanel Orientation="Horizontal">
                                <TextBlock Text="&#xE7A6;" Style="{StaticResource IconText}" Margin="0,0,6,0"/>
                                <TextBlock Text="Redo" VerticalAlignment="Center"/>
                            </StackPanel>
                        </Button>
                        <Button x:Name="BtnEnter" Style="{StaticResource DrawerBtn}" MinWidth="80" ToolTip="Enter / Confirm">
                            <StackPanel Orientation="Horizontal">
                                <TextBlock Text="&#xE751;" Style="{StaticResource IconText}" Margin="0,0,6,0"/>
                                <TextBlock Text="Enter" VerticalAlignment="Center"/>
                            </StackPanel>
                        </Button>
                    </StackPanel>

                    <!-- Section 2: Browser & Zoom -->
                    <TextBlock Text="BROWSER &amp; ZOOM" Style="{StaticResource SectionTitle}"/>
                    <WrapPanel Orientation="Horizontal" MaxWidth="680" Margin="0,0,0,8">
                        <Button x:Name="BtnSelAll" Style="{StaticResource DrawerBtn}" ToolTip="Select All (Ctrl+A)">
                            <StackPanel Orientation="Horizontal">
                                <TextBlock Text="&#xE8B3;" Style="{StaticResource IconText}" Margin="0,0,7,0"/>
                                <TextBlock Text="Select All" VerticalAlignment="Center"/>
                            </StackPanel>
                        </Button>
                        <Button x:Name="BtnFind" Style="{StaticResource DrawerBtn}" ToolTip="Find (Ctrl+F)">
                            <StackPanel Orientation="Horizontal">
                                <TextBlock Text="&#xE721;" Style="{StaticResource IconText}" Margin="0,0,7,0"/>
                                <TextBlock Text="Find" VerticalAlignment="Center"/>
                            </StackPanel>
                        </Button>
                        <Button x:Name="BtnPrevTab" Style="{StaticResource DrawerBtn}" ToolTip="Previous Tab (Ctrl+Shift+Tab)">
                            <StackPanel Orientation="Horizontal">
                                <TextBlock Text="&#xE892;" Style="{StaticResource IconText}" Margin="0,0,7,0"/>
                                <TextBlock Text="Prev Tab" VerticalAlignment="Center"/>
                            </StackPanel>
                        </Button>
                        <Button x:Name="BtnForward" Style="{StaticResource DrawerBtn}" ToolTip="Forward (Alt+Right)">
                            <StackPanel Orientation="Horizontal">
                                <TextBlock Text="&#xE72A;" Style="{StaticResource IconText}" Margin="0,0,7,0"/>
                                <TextBlock Text="Forward" VerticalAlignment="Center"/>
                            </StackPanel>
                        </Button>
                        <Button x:Name="BtnRefresh" Style="{StaticResource DrawerBtn}" ToolTip="Reload (Ctrl+R)">
                            <StackPanel Orientation="Horizontal">
                                <TextBlock Text="&#xE72C;" Style="{StaticResource IconText}" Margin="0,0,7,0"/>
                                <TextBlock Text="Reload" VerticalAlignment="Center"/>
                            </StackPanel>
                        </Button>
                        <Button x:Name="BtnReopenTab" Style="{StaticResource DrawerBtn}" ToolTip="Reopen Closed Tab (Ctrl+Shift+T)">
                            <StackPanel Orientation="Horizontal">
                                <TextBlock Text="&#xE81C;" Style="{StaticResource IconText}" Margin="0,0,7,0"/>
                                <TextBlock Text="Reopen" VerticalAlignment="Center"/>
                            </StackPanel>
                        </Button>
                        <Button x:Name="BtnZoomOut" Style="{StaticResource DrawerBtn}" MinWidth="82" ToolTip="Zoom Out (Ctrl+-)">
                            <StackPanel Orientation="Horizontal">
                                <TextBlock Text="&#xE71F;" Style="{StaticResource IconText}" Margin="0,0,6,0"/>
                                <TextBlock Text="Zoom -" VerticalAlignment="Center"/>
                            </StackPanel>
                        </Button>
                        <Button x:Name="BtnZoomIn" Style="{StaticResource DrawerBtn}" MinWidth="82" ToolTip="Zoom In (Ctrl++)">
                            <StackPanel Orientation="Horizontal">
                                <TextBlock Text="&#xE8A3;" Style="{StaticResource IconText}" Margin="0,0,6,0"/>
                                <TextBlock Text="Zoom +" VerticalAlignment="Center"/>
                            </StackPanel>
                        </Button>
                        <Button x:Name="BtnFullscreen" Style="{StaticResource DrawerBtn}" ToolTip="Fullscreen (F11)">
                            <StackPanel Orientation="Horizontal">
                                <TextBlock Text="&#xE740;" Style="{StaticResource IconText}" Margin="0,0,7,0"/>
                                <TextBlock Text="Fullscreen" VerticalAlignment="Center"/>
                            </StackPanel>
                        </Button>
                    </WrapPanel>

                    <!-- Section 3: Window Management -->
                    <TextBlock Text="WINDOW MANAGEMENT" Style="{StaticResource SectionTitle}"/>
                    <WrapPanel Orientation="Horizontal" MaxWidth="680" Margin="0,0,0,8">
                        <Button x:Name="BtnAltTab" Style="{StaticResource DrawerBtn}" ToolTip="Switch to Last App (Alt+Tab)">
                            <StackPanel Orientation="Horizontal">
                                <TextBlock Text="&#xE8AB;" Style="{StaticResource IconText}" Margin="0,0,7,0"/>
                                <TextBlock Text="Last App" VerticalAlignment="Center"/>
                            </StackPanel>
                        </Button>
                        <Button x:Name="BtnGather" Style="{StaticResource DrawerBtn}" ToolTip="Move all windows onto iPad display">
                            <StackPanel Orientation="Horizontal">
                                <TextBlock Text="&#xE8A7;" Style="{StaticResource IconText}" Margin="0,0,7,0"/>
                                <TextBlock Text="Gather" VerticalAlignment="Center"/>
                            </StackPanel>
                        </Button>
                        <Button x:Name="BtnSnapL" Style="{StaticResource DrawerBtn}" ToolTip="Snap Window Left (Win+Left)">
                            <StackPanel Orientation="Horizontal">
                                <TextBlock Text="&#xE90C;" Style="{StaticResource IconText}" Margin="0,0,7,0"/>
                                <TextBlock Text="Snap Left" VerticalAlignment="Center"/>
                            </StackPanel>
                        </Button>
                        <Button x:Name="BtnSnapR" Style="{StaticResource DrawerBtn}" ToolTip="Snap Window Right (Win+Right)">
                            <StackPanel Orientation="Horizontal">
                                <TextBlock Text="&#xE90D;" Style="{StaticResource IconText}" Margin="0,0,7,0"/>
                                <TextBlock Text="Snap Right" VerticalAlignment="Center"/>
                            </StackPanel>
                        </Button>
                        <Button x:Name="BtnMax" Style="{StaticResource DrawerBtn}" ToolTip="Maximize Window (Win+Up)">
                            <StackPanel Orientation="Horizontal">
                                <TextBlock Text="&#xE922;" Style="{StaticResource IconText}" Margin="0,0,7,0"/>
                                <TextBlock Text="Maximize" VerticalAlignment="Center"/>
                            </StackPanel>
                        </Button>
                        <Button x:Name="BtnMin" Style="{StaticResource DrawerBtn}" ToolTip="Minimize Window (Win+Down)">
                            <StackPanel Orientation="Horizontal">
                                <TextBlock Text="&#xE921;" Style="{StaticResource IconText}" Margin="0,0,7,0"/>
                                <TextBlock Text="Minimize" VerticalAlignment="Center"/>
                            </StackPanel>
                        </Button>
                        <Button x:Name="BtnCloseApp" Style="{StaticResource DrawerBtn}" Background="#38EF4444" BorderBrush="#66EF4444" ToolTip="Close Active Window (Alt+F4)">
                            <StackPanel Orientation="Horizontal">
                                <TextBlock Text="&#xE8BB;" Style="{StaticResource IconText}" Margin="0,0,7,0"/>
                                <TextBlock Text="Close App" VerticalAlignment="Center"/>
                            </StackPanel>
                        </Button>
                    </WrapPanel>

                    <!-- Section 4: System & Audio -->
                    <TextBlock Text="SYSTEM &amp; AUDIO" Style="{StaticResource SectionTitle}"/>
                    <StackPanel Orientation="Horizontal">
                        <Button x:Name="BtnFiles" Style="{StaticResource DrawerBtn}" ToolTip="Open File Explorer">
                            <StackPanel Orientation="Horizontal">
                                <TextBlock Text="&#xE8B7;" Style="{StaticResource IconText}" Margin="0,0,7,0"/>
                                <TextBlock Text="Files" VerticalAlignment="Center"/>
                            </StackPanel>
                        </Button>
                        <Button x:Name="BtnSnip" Style="{StaticResource DrawerBtn}" ToolTip="Screenshot (Win+Shift+S)">
                            <StackPanel Orientation="Horizontal">
                                <TextBlock Text="&#xE722;" Style="{StaticResource IconText}" Margin="0,0,7,0"/>
                                <TextBlock Text="Screenshot" VerticalAlignment="Center"/>
                            </StackPanel>
                        </Button>
                        <Button x:Name="BtnVolDown" Style="{StaticResource DrawerBtn}" MinWidth="60" ToolTip="Volume Down">
                            <StackPanel Orientation="Horizontal">
                                <TextBlock Text="&#xE993;" Style="{StaticResource IconText}" Margin="0,0,5,0"/>
                                <TextBlock Text="-" VerticalAlignment="Center" FontWeight="Bold"/>
                            </StackPanel>
                        </Button>
                        <Button x:Name="BtnVolMute" Style="{StaticResource DrawerBtn}" MinWidth="56" ToolTip="Mute / Unmute">
                            <TextBlock Text="&#xE74F;" Style="{StaticResource IconText}"/>
                        </Button>
                        <Button x:Name="BtnVolUp" Style="{StaticResource DrawerBtn}" MinWidth="60" ToolTip="Volume Up">
                            <StackPanel Orientation="Horizontal">
                                <TextBlock Text="&#xE995;" Style="{StaticResource IconText}" Margin="0,0,5,0"/>
                                <TextBlock Text="+" VerticalAlignment="Center" FontWeight="Bold"/>
                            </StackPanel>
                        </Button>
                        <Button x:Name="BtnSettings" Style="{StaticResource DrawerBtn}" ToolTip="Windows Settings">
                            <StackPanel Orientation="Horizontal">
                                <TextBlock Text="&#xE713;" Style="{StaticResource IconText}" Margin="0,0,7,0"/>
                                <TextBlock Text="Settings" VerticalAlignment="Center"/>
                            </StackPanel>
                        </Button>
                    </StackPanel>
                </StackPanel>
            </ScrollViewer>
        </Border>

        <!-- Primary Floating Liquid-Glass Dock -->
        <Border Background="#D812151C"
                BorderBrush="#40FFFFFF"
                BorderThickness="1"
                CornerRadius="24"
                Padding="9,8"
                HorizontalAlignment="Center">
            <Border.Effect>
                <DropShadowEffect BlurRadius="28" ShadowDepth="8" Opacity="0.50" Color="#000000"/>
            </Border.Effect>
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                <!-- Drag Handle -->
                <Border x:Name="DragHandle"
                        Background="#12FFFFFF"
                        CornerRadius="14"
                        Width="32" Height="50"
                        Margin="0,0,5,0"
                        Cursor="SizeAll"
                        ToolTip="Drag Dock">
                    <TextBlock Text="&#xE76F;" FontFamily="Segoe Fluent Icons" FontSize="14"
                               Foreground="#9CA3AF" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>

                <StackPanel x:Name="ButtonsPanel" Orientation="Horizontal" VerticalAlignment="Center">
                    <!-- System & Apps -->
                    <Button x:Name="BtnHome" Style="{StaticResource DockBtn}" MinWidth="58"
                            Background="#CC0A84FF" BorderBrush="#55FFFFFF" ToolTip="iPad App Launcher &amp; Running Apps">
                        <StackPanel>
                            <TextBlock Text="&#xE80F;" Style="{StaticResource IconText}"/>
                            <TextBlock Text="Home" Style="{StaticResource LabelText}" Foreground="#FFFFFF"/>
                        </StackPanel>
                    </Button>
                    <Button x:Name="BtnSwitch" Style="{StaticResource DockBtn}" ToolTip="Task View (Switch Apps)">
                        <StackPanel>
                            <TextBlock Text="&#xE7C4;" Style="{StaticResource IconText}"/>
                            <TextBlock Text="Apps" Style="{StaticResource LabelText}"/>
                        </StackPanel>
                    </Button>
                    <Button x:Name="BtnDesk" Style="{StaticResource DockBtn}" ToolTip="Show Desktop (Win+D)">
                        <StackPanel>
                            <TextBlock Text="&#xE7F4;" Style="{StaticResource IconText}"/>
                            <TextBlock Text="Desk" Style="{StaticResource LabelText}"/>
                        </StackPanel>
                    </Button>
                    <Button x:Name="BtnBrave" Style="{StaticResource DockBtn}" ToolTip="Focus or Launch Brave">
                        <StackPanel>
                            <TextBlock Text="&#xE774;" Style="{StaticResource IconText}"/>
                            <TextBlock Text="Brave" Style="{StaticResource LabelText}"/>
                        </StackPanel>
                    </Button>

                    <Border Style="{StaticResource DockDivider}"/>

                    <!-- Browser & Tabs -->
                    <Button x:Name="BtnBack" Style="{StaticResource DockBtn}" MinWidth="48" ToolTip="Back (Alt+Left)">
                        <TextBlock Text="&#xE72B;" Style="{StaticResource IconText}" FontSize="16"/>
                    </Button>
                    <Button x:Name="BtnNewTab" Style="{StaticResource DockBtn}" ToolTip="New Tab (Ctrl+T)">
                        <StackPanel>
                            <TextBlock Text="&#xE710;" Style="{StaticResource IconText}"/>
                            <TextBlock Text="Tab" Style="{StaticResource LabelText}"/>
                        </StackPanel>
                    </Button>
                    <Button x:Name="BtnNextTab" Style="{StaticResource DockBtn}" ToolTip="Next Tab (Ctrl+Tab)">
                        <StackPanel>
                            <TextBlock Text="&#xE726;" Style="{StaticResource IconText}"/>
                            <TextBlock Text="Next" Style="{StaticResource LabelText}"/>
                        </StackPanel>
                    </Button>
                    <Button x:Name="BtnCloseTab" Style="{StaticResource DockBtn}" ToolTip="Close Tab (Ctrl+W)">
                        <StackPanel>
                            <TextBlock Text="&#xE711;" Style="{StaticResource IconText}"/>
                            <TextBlock Text="Close" Style="{StaticResource LabelText}"/>
                        </StackPanel>
                    </Button>

                    <Border Style="{StaticResource DockDivider}"/>

                    <!-- Edit & Context -->
                    <Button x:Name="BtnCopy" Style="{StaticResource DockBtn}" ToolTip="Copy (Ctrl+C)">
                        <StackPanel>
                            <TextBlock Text="&#xE8C8;" Style="{StaticResource IconText}"/>
                            <TextBlock Text="Copy" Style="{StaticResource LabelText}"/>
                        </StackPanel>
                    </Button>
                    <Button x:Name="BtnPaste" Style="{StaticResource DockBtn}" ToolTip="Paste (Ctrl+V)">
                        <StackPanel>
                            <TextBlock Text="&#xE77F;" Style="{StaticResource IconText}"/>
                            <TextBlock Text="Paste" Style="{StaticResource LabelText}"/>
                        </StackPanel>
                    </Button>
                    <Button x:Name="BtnUndo" Style="{StaticResource DockBtn}" ToolTip="Undo (Ctrl+Z)">
                        <StackPanel>
                            <TextBlock Text="&#xE7A7;" Style="{StaticResource IconText}"/>
                            <TextBlock Text="Undo" Style="{StaticResource LabelText}"/>
                        </StackPanel>
                    </Button>
                    <Button x:Name="BtnMenu" Style="{StaticResource DockBtn}" ToolTip="Context Menu (Shift+F10)">
                        <StackPanel>
                            <TextBlock Text="&#xE700;" Style="{StaticResource IconText}"/>
                            <TextBlock Text="Menu" Style="{StaticResource LabelText}"/>
                        </StackPanel>
                    </Button>

                    <Border Style="{StaticResource DockDivider}"/>

                    <!-- More Actions -->
                    <Button x:Name="BtnMore" Style="{StaticResource DockBtn}" MinWidth="48" ToolTip="More Actions">
                        <TextBlock Text="&#xE712;" Style="{StaticResource IconText}" FontSize="17"/>
                    </Button>
                </StackPanel>

                <!-- Collapse / Expand -->
                <Button x:Name="BtnCollapse" Style="{StaticResource DockBtn}" MinWidth="46" Background="#24FFFFFF" ToolTip="Collapse / Expand Dock">
                    <TextBlock Text="&#xE76B;" Style="{StaticResource IconText}"/>
                </Button>
            </StackPanel>
        </Border>
    </StackPanel>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$win = [Windows.Markup.XamlReader]::Load($reader)

$iconDir = Join-Path $PSScriptRoot "assets\icons"
$iconCache = @{}

function Get-CachedBitmapSource([string]$pngPath) {
    if (-not (Test-Path -LiteralPath $pngPath)) { return $null }
    if ($iconCache.ContainsKey($pngPath)) { return $iconCache[$pngPath] }
    try {
        $bi = New-Object System.Windows.Media.Imaging.BitmapImage
        $bi.BeginInit()
        $bi.UriSource = New-Object Uri($pngPath, [UriKind]::Absolute)
        $bi.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bi.EndInit()
        $bi.Freeze()
        $iconCache[$pngPath] = $bi
        return $bi
    } catch {
        return $null
    }
}

function Get-ProcessBitmapSource($proc) {
    $pname = $proc.ProcessName.ToLowerInvariant()
    $map = @{
        'brave'       = 'brave.png'
        'explorer'    = 'files.png'
        'systemsettings' = 'settings.png'
        'steam'       = 'steam.png'
        'steamwebhelper' = 'steam.png'
        'vlc'         = 'vlc.png'
        'notepad'     = 'notepad.png'
        'taskmgr'     = 'taskmgr.png'
    }
    if ($map.ContainsKey($pname)) {
        $src = Get-CachedBitmapSource (Join-Path $iconDir $map[$pname])
        if ($src) { return $src }
    }
    try {
        $exe = $proc.MainModule.FileName
        if ($exe -and (Test-Path -LiteralPath $exe)) {
            $ico = [System.Drawing.Icon]::ExtractAssociatedIcon($exe)
            if ($ico) {
                $bs = [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon(
                    $ico.Handle, [System.Windows.Int32Rect]::Empty,
                    [System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions())
                $ico.Dispose()
                $bs.Freeze()
                return $bs
            }
        }
    } catch {}
    return $null
}

# Load favorite app PNGs into Launcher tiles
foreach ($pair in @(
    @{ Ctrl = 'ImgBrave';    File = 'brave.png' },
    @{ Ctrl = 'ImgFiles';    File = 'files.png' },
    @{ Ctrl = 'ImgSettings'; File = 'settings.png' },
    @{ Ctrl = 'ImgSteam';    File = 'steam.png' },
    @{ Ctrl = 'ImgVLC';      File = 'vlc.png' },
    @{ Ctrl = 'ImgNotepad';  File = 'notepad.png' },
    @{ Ctrl = 'ImgTaskMgr';  File = 'taskmgr.png' },
    @{ Ctrl = 'ImgDesktop';  File = 'desktop.png' }
)) {
    $img = $win.FindName($pair.Ctrl)
    $src = Get-CachedBitmapSource (Join-Path $iconDir $pair.File)
    if ($img -and $src) { $img.Source = $src }
}

$dockScale = $win.FindName("DockScale")
$launcherOverlay = $win.FindName("LauncherOverlay")
$moreDrawer = $win.FindName("MoreDrawer")

function Update-AdaptiveLayout {
    $wa = [System.Windows.SystemParameters]::WorkArea
    # Reference design target is 1180x772 DIPs (2360x1640 @ 200%)
    $scaleX = $wa.Width / 1180.0
    $scaleY = $wa.Height / 772.0
    $s = [Math]::Min($scaleX, $scaleY)
    $s = [Math]::Max(0.78, [Math]::Min(1.12, $s))
    $dockScale.ScaleX = $s
    $dockScale.ScaleY = $s
    $launcherOverlay.MaxWidth  = [Math]::Max(360, ($wa.Width - 40) / $s)
    $launcherOverlay.MaxHeight = [Math]::Max(260, ($wa.Height - 130) / $s)
    $moreDrawer.MaxWidth       = [Math]::Max(360, ($wa.Width - 40) / $s)
    $moreDrawer.MaxHeight      = [Math]::Max(260, ($wa.Height - 130) / $s)
}

function Position-DockBottomCenter {
    param([switch]$ForceCenter)
    Update-AdaptiveLayout
    $wa = [System.Windows.SystemParameters]::WorkArea
    $w = if ($win.ActualWidth -gt 0) { $win.ActualWidth } else { 885 }
    $h = if ($win.ActualHeight -gt 0) { $win.ActualHeight } else { 102 }

    if ($ForceCenter -or [double]::IsNaN($win.Left) -or [double]::IsNaN($win.Top)) {
        $win.Left = $wa.Left + [Math]::Max(8, ($wa.Width - $w) / 2)
        $win.Top  = $wa.Top + $wa.Height - $h + 4
    } else {
        $win.Left = [Math]::Min([Math]::Max($wa.Left + 4, $win.Left), $wa.Left + $wa.Width - $w - 4)
        $win.Top  = [Math]::Min([Math]::Max($wa.Top + 4, $win.Top),  $wa.Top + $wa.Height - $h + 4)
    }
}

function Animate-Opacity($element, [double]$from, [double]$to, [int]$ms) {
    $anim = New-Object System.Windows.Media.Animation.DoubleAnimation
    $anim.From = $from
    $anim.To = $to
    $anim.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds($ms))
    $ease = New-Object System.Windows.Media.Animation.QuadraticEase
    $ease.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
    $anim.EasingFunction = $ease
    $element.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $anim)
}

$win.Add_SourceInitialized({
    $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper $win).Handle
    $ex = [TouchDockNative]::GetWindowLong($hwnd, [TouchDockNative]::GWL_EXSTYLE)
    [TouchDockNative]::SetWindowLong($hwnd, [TouchDockNative]::GWL_EXSTYLE, $ex -bor [TouchDockNative]::WS_EX_NOACTIVATE -bor [TouchDockNative]::WS_EX_TOOLWINDOW) | Out-Null
})

$win.Add_Loaded({
    Position-DockBottomCenter -ForceCenter
    Animate-Opacity $win 0.0 1.0 180
})

$displayChangedHandler = [EventHandler]{
    $win.Dispatcher.BeginInvoke([Action]{
        Position-DockBottomCenter -ForceCenter
    }, [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null
}
[Microsoft.Win32.SystemEvents]::add_DisplaySettingsChanged($displayChangedHandler)

$drag = $win.FindName("DragHandle")
$drag.Add_MouseLeftButtonDown({ $win.DragMove() })

$panel = $win.FindName("ButtonsPanel")
$runningPanel = $win.FindName("RunningAppsPanel")
$runningHeader = $win.FindName("RunningHeader")
$btnHome = $win.FindName("BtnHome")
$btnMore = $win.FindName("BtnMore")
$btnCollapse = $win.FindName("BtnCollapse")
$runningPillStyle = $win.FindResource("RunningPill")

function Focus-WindowOnVirtualDisplay([IntPtr]$hwnd) {
    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    if ([TouchDockNative]::IsIconic($hwnd)) {
        [TouchDockNative]::ShowWindow($hwnd, [TouchDockNative]::SW_RESTORE) | Out-Null
    }
    [TouchDockNative]::EnsureWindowOnArea($hwnd, $wa.Left, $wa.Top, $wa.Width, $wa.Height)
    [TouchDockNative]::SetForegroundWindow($hwnd) | Out-Null
}

function Focus-OrLaunchApp([string]$procName, [scriptblock]$launchAction) {
    $existing = Get-Process -Name $procName -ErrorAction SilentlyContinue |
                Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } |
                Select-Object -First 1
    if ($existing) {
        Focus-WindowOnVirtualDisplay $existing.MainWindowHandle
    } else {
        & $launchAction
    }
}

function Close-Popups {
    $moreDrawer.Visibility = 'Collapsed'
    $moreDrawer.Opacity = 0
    $btnMore.Background = '#16FFFFFF'
    $launcherOverlay.Visibility = 'Collapsed'
    $launcherOverlay.Opacity = 0
    $btnHome.Background = '#CC0A84FF'
}

function Update-RunningApps {
    $runningPanel.Children.Clear()
    $allWinProcs = Get-Process -ErrorAction SilentlyContinue |
                   Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero -and -not [string]::IsNullOrWhiteSpace($_.MainWindowTitle) -and $_.MainWindowTitle -ne 'iPadTouchDock' }

    $runningNames = @{}
    foreach ($p in $allWinProcs) { $runningNames[$p.ProcessName.ToLowerInvariant()] = $true }

    # Update live green dots on Favorite tiles
    $dotMap = @{
        'DotBrave'    = 'brave'
        'DotFiles'    = 'explorer'
        'DotSettings' = 'systemsettings'
        'DotSteam'    = 'steam'
        'DotVLC'      = 'vlc'
        'DotNotepad'  = 'notepad'
        'DotTaskMgr'  = 'taskmgr'
    }
    foreach ($kv in $dotMap.GetEnumerator()) {
        $dot = $win.FindName($kv.Key)
        if ($dot) {
            $dot.Visibility = if ($runningNames.ContainsKey($kv.Value)) { 'Visible' } else { 'Collapsed' }
        }
    }

    $wins = $allWinProcs | Select-Object -First 6
    $count = 0
    foreach ($proc in $wins) {
        $count++
        $btn = New-Object System.Windows.Controls.Button
        $btn.Style = $runningPillStyle

        $sp = New-Object System.Windows.Controls.StackPanel
        $sp.Orientation = 'Horizontal'
        $sp.VerticalAlignment = 'Center'

        $bmp = Get-ProcessBitmapSource $proc
        if ($bmp) {
            $img = New-Object System.Windows.Controls.Image
            $img.Source = $bmp
            $img.Width = 18
            $img.Height = 18
            $img.Margin = '0,0,7,0'
            [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($img, [System.Windows.Media.BitmapScalingMode]::HighQuality)
            $sp.Children.Add($img) | Out-Null
        }

        $title = $proc.MainWindowTitle
        if ($title.Length -gt 18) { $title = $title.Substring(0, 17) + "…" }
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = $title
        $tb.VerticalAlignment = 'Center'
        $tb.FontSize = 12
        $sp.Children.Add($tb) | Out-Null

        $btn.Content = $sp
        $btn.ToolTip = $proc.MainWindowTitle
        $hwndTarget = $proc.MainWindowHandle
        $btn.Add_Click({
            Close-Popups
            Focus-WindowOnVirtualDisplay $hwndTarget
            $win.Dispatcher.BeginInvoke([Action]{ Position-DockBottomCenter }, [System.Windows.Threading.DispatcherPriority]::Loaded) | Out-Null
        }.GetNewClosure())
        $runningPanel.Children.Add($btn) | Out-Null
    }
    $vis = if ($count -gt 0) { 'Visible' } else { 'Collapsed' }
    $runningHeader.Visibility = $vis
    $runningPanel.Visibility = $vis
}

$btnCollapse.Add_Click({
    if ($panel.Visibility -eq 'Visible') {
        Close-Popups
        $panel.Visibility = 'Collapsed'

        $sp = New-Object System.Windows.Controls.StackPanel
        $sp.Orientation = 'Horizontal'
        $lbl = New-Object System.Windows.Controls.TextBlock
        $lbl.Text = 'iPad'
        $lbl.Margin = '0,0,6,0'
        $lbl.VerticalAlignment = 'Center'
        $ico = New-Object System.Windows.Controls.TextBlock
        $ico.Text = [char]0xE76C
        $ico.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe Fluent Icons')
        $ico.FontSize = 13
        $ico.VerticalAlignment = 'Center'
        $sp.Children.Add($lbl) | Out-Null
        $sp.Children.Add($ico) | Out-Null

        $btnCollapse.Content = $sp
        $btnCollapse.MinWidth = 74
    } else {
        $panel.Visibility = 'Visible'
        $ico = New-Object System.Windows.Controls.TextBlock
        $ico.Text = [char]0xE76B
        $ico.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe Fluent Icons')
        $ico.FontSize = 15
        $ico.VerticalAlignment = 'Center'
        $btnCollapse.Content = $ico
        $btnCollapse.MinWidth = 46
    }
    $win.Dispatcher.BeginInvoke([Action]{ Position-DockBottomCenter }, [System.Windows.Threading.DispatcherPriority]::Loaded) | Out-Null
})

$btnMore.Add_Click({
    if ($moreDrawer.Visibility -eq 'Visible') {
        Close-Popups
    } else {
        Close-Popups
        $moreDrawer.Visibility = 'Visible'
        $btnMore.Background = '#CC0A84FF'
        Animate-Opacity $moreDrawer 0.0 1.0 140
    }
    $win.Dispatcher.BeginInvoke([Action]{ Position-DockBottomCenter }, [System.Windows.Threading.DispatcherPriority]::Loaded) | Out-Null
})

$btnHome.Add_Click({
    if ($launcherOverlay.Visibility -eq 'Visible') {
        Close-Popups
    } else {
        Close-Popups
        Update-RunningApps
        $launcherOverlay.Visibility = 'Visible'
        $btnHome.Background = '#FF0066CC'
        Animate-Opacity $launcherOverlay 0.0 1.0 150
    }
    $win.Dispatcher.BeginInvoke([Action]{ Position-DockBottomCenter }, [System.Windows.Threading.DispatcherPriority]::Loaded) | Out-Null
})

$win.FindName("BtnCloseLauncher").Add_Click({
    Close-Popups
    $win.Dispatcher.BeginInvoke([Action]{ Position-DockBottomCenter }, [System.Windows.Threading.DispatcherPriority]::Loaded) | Out-Null
})

# Primary bar actions
$win.FindName("BtnSwitch").Add_Click({   [TouchDockNative]::SendCombo(0x5B, 0x09) })       # Win+Tab
$win.FindName("BtnDesk").Add_Click({     [TouchDockNative]::SendCombo(0x5B, 0x44) })       # Win+D
$win.FindName("BtnBack").Add_Click({     [TouchDockNative]::SendCombo(0x12, 0x25) })       # Alt+Left
$win.FindName("BtnNewTab").Add_Click({   [TouchDockNative]::SendCombo(0x11, 0x54) })       # Ctrl+T
$win.FindName("BtnNextTab").Add_Click({  [TouchDockNative]::SendCombo(0x11, 0x09) })       # Ctrl+Tab
$win.FindName("BtnCloseTab").Add_Click({ [TouchDockNative]::SendCombo(0x11, 0x57) })       # Ctrl+W
$win.FindName("BtnCopy").Add_Click({     [TouchDockNative]::SendCombo(0x11, 0x43) })       # Ctrl+C
$win.FindName("BtnPaste").Add_Click({    [TouchDockNative]::SendCombo(0x11, 0x56) })       # Ctrl+V
$win.FindName("BtnUndo").Add_Click({     [TouchDockNative]::SendCombo(0x11, 0x5A) })       # Ctrl+Z
$win.FindName("BtnMenu").Add_Click({     [TouchDockNative]::SendCombo(0x10, 0x79) })       # Shift+F10

$win.FindName("BtnBrave").Add_Click({
    Focus-OrLaunchApp 'brave' {
        $launcher = Join-Path $PSScriptRoot "Launch-Brave-iPad.cmd"
        if (Test-Path -LiteralPath $launcher) { Start-Process -FilePath $launcher -WindowStyle Hidden }
    }
})

# Home Launcher Favorite tiles (focus existing window if running, else launch)
$win.FindName("LaunchBrave").Add_Click({
    Close-Popups
    Focus-OrLaunchApp 'brave' {
        $launcher = Join-Path $PSScriptRoot "Launch-Brave-iPad.cmd"
        if (Test-Path -LiteralPath $launcher) { Start-Process -FilePath $launcher -WindowStyle Hidden }
    }
    $win.Dispatcher.BeginInvoke([Action]{ Position-DockBottomCenter }, [System.Windows.Threading.DispatcherPriority]::Loaded) | Out-Null
})
$win.FindName("LaunchFiles").Add_Click({
    Close-Popups
    Start-Process "explorer.exe"
    $win.Dispatcher.BeginInvoke([Action]{ Position-DockBottomCenter }, [System.Windows.Threading.DispatcherPriority]::Loaded) | Out-Null
})
$win.FindName("LaunchSettings").Add_Click({
    Close-Popups
    Start-Process "ms-settings:"
    $win.Dispatcher.BeginInvoke([Action]{ Position-DockBottomCenter }, [System.Windows.Threading.DispatcherPriority]::Loaded) | Out-Null
})
$win.FindName("LaunchSteam").Add_Click({
    Close-Popups
    Focus-OrLaunchApp 'steam' { Start-Process "steam://open/main" }
    $win.Dispatcher.BeginInvoke([Action]{ Position-DockBottomCenter }, [System.Windows.Threading.DispatcherPriority]::Loaded) | Out-Null
})
$win.FindName("LaunchVLC").Add_Click({
    Close-Popups
    Focus-OrLaunchApp 'vlc' {
        $vlc = "C:\Program Files\VideoLAN\VLC\vlc.exe"
        if (Test-Path -LiteralPath $vlc) { Start-Process $vlc }
    }
    $win.Dispatcher.BeginInvoke([Action]{ Position-DockBottomCenter }, [System.Windows.Threading.DispatcherPriority]::Loaded) | Out-Null
})
$win.FindName("LaunchNotepad").Add_Click({
    Close-Popups
    Focus-OrLaunchApp 'notepad' { Start-Process "notepad.exe" }
    $win.Dispatcher.BeginInvoke([Action]{ Position-DockBottomCenter }, [System.Windows.Threading.DispatcherPriority]::Loaded) | Out-Null
})
$win.FindName("LaunchTaskMgr").Add_Click({
    Close-Popups
    Focus-OrLaunchApp 'taskmgr' { Start-Process "taskmgr.exe" }
    $win.Dispatcher.BeginInvoke([Action]{ Position-DockBottomCenter }, [System.Windows.Threading.DispatcherPriority]::Loaded) | Out-Null
})
$win.FindName("LaunchDesktop").Add_Click({
    Close-Popups
    [TouchDockNative]::SendCombo(0x5B, 0x44)
    $win.Dispatcher.BeginInvoke([Action]{ Position-DockBottomCenter }, [System.Windows.Threading.DispatcherPriority]::Loaded) | Out-Null
})

# Secondary Quick Actions drawer
$win.FindName("BtnEnter").Add_Click({      [TouchDockNative]::SendCombo(0x0D) })             # Enter
$win.FindName("BtnClipHist").Add_Click({   [TouchDockNative]::SendCombo(0x5B, 0x56) })       # Win+V
$win.FindName("BtnCut").Add_Click({        [TouchDockNative]::SendCombo(0x11, 0x58) })       # Ctrl+X
$win.FindName("BtnRedo").Add_Click({       [TouchDockNative]::SendCombo(0x11, 0x59) })       # Ctrl+Y
$win.FindName("BtnSelAll").Add_Click({     [TouchDockNative]::SendCombo(0x11, 0x41) })       # Ctrl+A
$win.FindName("BtnFind").Add_Click({       [TouchDockNative]::SendCombo(0x11, 0x46) })       # Ctrl+F
$win.FindName("BtnPrevTab").Add_Click({    [TouchDockNative]::SendCombo(0x11, 0x10, 0x09) }) # Ctrl+Shift+Tab
$win.FindName("BtnForward").Add_Click({    [TouchDockNative]::SendCombo(0x12, 0x27) })       # Alt+Right
$win.FindName("BtnRefresh").Add_Click({    [TouchDockNative]::SendCombo(0x11, 0x52) })       # Ctrl+R
$win.FindName("BtnReopenTab").Add_Click({  [TouchDockNative]::SendCombo(0x11, 0x10, 0x54) }) # Ctrl+Shift+T
$win.FindName("BtnZoomOut").Add_Click({    [TouchDockNative]::SendCombo(0x11, 0xBD) })       # Ctrl+-
$win.FindName("BtnZoomIn").Add_Click({     [TouchDockNative]::SendCombo(0x11, 0xBB) })       # Ctrl++
$win.FindName("BtnFullscreen").Add_Click({ [TouchDockNative]::SendCombo(0x7A) })             # F11
$win.FindName("BtnAltTab").Add_Click({     [TouchDockNative]::SendCombo(0x12, 0x09) })       # Alt+Tab
$win.FindName("BtnGather").Add_Click({
    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    [TouchDockNative]::GatherAllWindows($wa.Left, $wa.Top, $wa.Width, $wa.Height) | Out-Null
})
$win.FindName("BtnSnapL").Add_Click({      [TouchDockNative]::SendCombo(0x5B, 0x25) })       # Win+Left
$win.FindName("BtnSnapR").Add_Click({      [TouchDockNative]::SendCombo(0x5B, 0x27) })       # Win+Right
$win.FindName("BtnMax").Add_Click({        [TouchDockNative]::SendCombo(0x5B, 0x26) })       # Win+Up
$win.FindName("BtnMin").Add_Click({        [TouchDockNative]::SendCombo(0x5B, 0x28) })       # Win+Down
$win.FindName("BtnCloseApp").Add_Click({   [TouchDockNative]::SendCombo(0x12, 0x73) })       # Alt+F4
$win.FindName("BtnSnip").Add_Click({       [TouchDockNative]::SendCombo(0x5B, 0x10, 0x53) }) # Win+Shift+S
$win.FindName("BtnVolDown").Add_Click({    [TouchDockNative]::SendCombo(0xAE) })             # VK_VOLUME_DOWN
$win.FindName("BtnVolMute").Add_Click({    [TouchDockNative]::SendCombo(0xAD) })             # VK_VOLUME_MUTE
$win.FindName("BtnVolUp").Add_Click({      [TouchDockNative]::SendCombo(0xAF) })             # VK_VOLUME_UP
$win.FindName("BtnFiles").Add_Click({      Start-Process "explorer.exe" })
$win.FindName("BtnSettings").Add_Click({   Start-Process "ms-settings:" })

$win.Add_Closed({
    [Microsoft.Win32.SystemEvents]::remove_DisplaySettingsChanged($displayChangedHandler)
    if (Test-Path -LiteralPath $pidFile) { Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue }
})

$win.ShowDialog() | Out-Null
