# Changelog — iPad Workstation

## [Phase 5: Visual Redesign, Touch UX & Display Reliability] - 2026-11-13

### Visual Redesign & Real App Icons (`iPad-TouchDock.ps1`, `Update-AppIcons.ps1`)
- Redesigned dock, Quick Actions drawer, and Home Launcher with a unified Apple/iPadOS liquid-glass aesthetic (`#D812151C` / `#EC12151C`, `CornerRadius="24"`/`"26"`, subtle `#40FFFFFF` glass borders, soft drop shadows).
- Standardized typography on `Segoe UI Variable Display` / `Segoe UI Variable Text` (with `Segoe UI` fallback) and `Segoe Fluent Icons` for system controls.
- Created `Update-AppIcons.ps1` using `PrivateExtractIcons` (`user32.dll`) to extract and cache 128×128 transparent PNG logos locally in `assets/icons/` for **Brave**, **Files**, **Settings**, **Steam**, **VLC**, **Notepad**, **Task Manager**, and **Desktop** (offline-capable, with `ExtractAssociatedIcon` fallback for arbitrary running apps).
- Redesigned **Home Launcher** with:
  - **RUNNING NOW** strip showing live window titles + real app icons; tapping focuses/restores and pulls off-screen windows onto the virtual display.
  - **FAVORITES** 4×2 grid (`114×100` tiles, `46×46` logos) with emerald running-status dots and duplicate-window avoidance (`Focus-OrLaunchApp`).
- Added **Adaptive Dock Sizing** (`Update-AdaptiveLayout`) calculating scale and `MaxWidth`/`MaxHeight` from `[System.Windows.SystemParameters]::WorkArea` at runtime.

### Display Management & Window Relocation (`iPad-Session.ps1`, `iPad-TouchDock.ps1`)
- Added `QueryDisplayConfig` / `SetDisplayConfig` topology backup (`display_topology_backup.json`) and MTT virtual display (`VDD by MTT` / `MTT1337`) isolation on `Start`, with full restoration on `Stop` / `Recover`.
- Added `MoveOffscreenWindowsToArea` on session `Start`, `EnsureWindowOnArea` when focusing running apps, and a `Gather` button in the Quick Actions drawer to pull any off-screen windows onto the active virtual display.

### Cursor Size & Theme Fix (`iPad-Session.ps1`)
- **Root cause identified**: `SPI_SETCURSORS` (`0x0057`) only reloads `.cur` files at the current system cursor size and ignored `CursorBaseSize=48` while `SPI_GETMOUSECURSORSIZE` (`0x2028`) and `HKCU:\Software\Microsoft\Accessibility\CursorSize` remained at `32` (`1`).
- Fixed `Set-CursorSizeImmediate` to call `SPI_SETMOUSECURSORSIZE` (`0x2029`) + `SPI_SETCURSORS` (`0x0057`) and update `Accessibility\CursorSize` (`2` for 48px, `1` for 32px), plus full cursor scheme backup/restoration and `Bibata-Modern-Classic-Regular Cursors` enforcement.

### Moonlight Touch Mode Documentation (`README.md`)
- Documented **Trackpad Mode** as the recommended Moonlight iOS input mode for reliable two-finger vertical scrolling in Brave, File Explorer, and menus, alongside 3-finger-tap keyboard access.

### Post-Milestone Refinement (`iPad-TouchDock.ps1`)
- Removed redundant Windows Touch Keyboard (`KB`) button from the primary bar and `Esc`/`Tab` buttons from the Quick Actions drawer (Moonlight's 3-finger-tap iPad keyboard already provides the iPadOS keyboard plus `Esc`, `Tab`, `Shift`, `Ctrl`, `Alt`, `Del`, and `Win`).
- Promoted `Home` (App Launcher) to the primary Apple-blue accent pill on the dock bar, reducing primary bar width from `940` to `885` DIPs.

## [Milestone 4, 5 & 6] - 2026-11-13

### Milestone 4: Touch-First Home Launcher (`iPad-TouchDock.ps1`)
- Integrated an iPadOS-style **Home Launcher Overlay** (`LauncherOverlay`) directly inside `iPad-TouchDock.ps1` (zero extra background processes/memory overhead), toggled via the new `Home` button on the primary dock bar.
- **Running Now**: Dynamically lists up to 6 active windows with touch-friendly pills; tapping any pill restores/focuses that window and closes the launcher.
- **Favorite Apps Grid**: Large `110x86` squircle tiles with colored icon badges for **Brave**, **Files**, **Settings**, **Steam**, **VLC Media**, **Notepad**, **Task Mgr**, and **Desktop**.
- Made `LauncherOverlay` and `MoreDrawer` mutually exclusive via `Close-Popups`.

### Milestone 5: Brave Optimization (`Launch-Brave-iPad.cmd`)
- Backed up original `Launch-Brave-iPad.cmd` to `backups/Launch-Brave-iPad.cmd.bak`.
- Removed `--force-device-scale-factor=1.15` (which overrode Windows' native 200% DPI scaling on the 2360×1640 display and made Brave's UI smaller than native DIPs).
- Preserved `--top-chrome-touch-ui=enabled --touch-events=enabled --start-maximized` and added `--enable-features=TouchpadOverscrollHistoryNavigation,OverscrollHistoryNavigation`.

### Milestone 6: Verification
- PowerShell parser syntax check passed for `iPad-TouchDock.ps1` and `iPad-Session.ps1`.
- Verified WPF layout dimensions inside `1180 x 772` DIP work area:
  - Primary bar: `940 x 98` DIPs
  - Home Launcher open: `940 x 432.6` DIPs
  - Quick Actions drawer open: `940 x 499.2` DIPs
- Restarted live session via `iPad-Session.ps1 -Mode Start` and confirmed Touch Dock process is running and responding.

## [Milestone 3] - 2026-11-13

### Expanded Dock Functionality (`iPad-TouchDock.ps1`)
- **Keys & Clipboard** section in `MoreDrawer`:
  - Added `Esc`, `Enter`, `Tab`, `Clipboard` (`Win+V`), `Cut` (`Ctrl+X`), and `Redo` (`Ctrl+Y`).
- **Browser & Zoom** section:
  - Added `Prev Tab` (`Ctrl+Shift+Tab`), `Zoom -` (`Ctrl+-`), and `Zoom +` (`Ctrl++`).
  - Wrapped into a `MaxWidth="680"` `WrapPanel` so drawer width stays within the `885` DIP dock footprint.
- **Window Management** section:
  - Added `Last App` (`Alt+Tab`) and `Close App` (`Alt+F4`, styled with subtle red glass tint).
- **Verification**:
  - PowerShell syntax check passed.
  - Verified XAML load and open-drawer dimensions: `885 x 499.2` DIPs (fits comfortably inside `1180 x 772` DIP work area).
  - Restarted Touch Dock via `iPad-Session.ps1 -Mode Start` and confirmed running.

## [Milestone 1 & 2] - 2026-11-13

### Milestone 1: Recovery & Current-State Audit
- Audited `C:\PC\Dev_Tools\iPad_Workstation` and live Sunshine configuration (`C:\Program Files\Sunshine\config\sunshine.conf`, `apps.json`).
- Confirmed live Sunshine config matches proposed files (`2360x1640@60`, MTT virtual display `{9acddf6d-43cc-576e-9aff-0c5fc80b4cc8}`, `ensure_primary`, `dd_config_revert_on_disconnect = enabled`) and left it untouched.
- Identified DPI/coordinate bug in `iPad-TouchDock.ps1`: `[System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea` (`1180x772` at 200% DPI on `\\.\DISPLAY10`) was multiplied by `TransformFromDevice` (`scaleX`/`scaleY`). Replaced with native WPF `[System.Windows.SystemParameters]::WorkArea`.
- Backed up original `iPad-TouchDock.ps1` to `backups/iPad-TouchDock.ps1.bak`.

### Milestone 2: Touch Dock Refinement (`iPad-TouchDock.ps1`)
- **Liquid-Glass Visual Redesign**:
  - Replaced flat dark bar with translucent frosted dark-glass floating pill (`#DC161922`, `CornerRadius="20"`, `#38FFFFFF` luminous border, soft `DropShadowEffect`).
  - Upgraded typography and iconography to Windows 11 `Segoe Fluent Icons` + `Segoe UI Variable Text` (replacing inconsistent color emojis).
  - Enlarged touch targets to `48px` height (`MinWidth="50"`) with `CornerRadius="13"` and clear press/hover states (`#CC0A84FF` Apple-blue press highlight).
  - Added subtle vertical glass dividers grouping **System & Apps**, **Browser & Tabs**, **Edit & Context**, and **Dock Controls**.
- **Organized Quick Actions Drawer (`⋯`)**:
  - Restructured the flat 16-button wrap panel into 3 labeled sections: **BROWSER & EDIT**, **WINDOW MANAGEMENT**, and **SYSTEM & AUDIO**.
  - Verified `Segoe Fluent Icons` glyph availability (replaced missing `0xE9A2` with `0xE90C`/`0xE90D` for Snap Left/Right).
  - Added smooth `140ms` opacity fade-in when opening the drawer and `180ms` fade-in on dock load.
- **Positioning & Collapse Improvements**:
  - Switched positioning/clamping to `[System.Windows.SystemParameters]::WorkArea` (native WPF DIPs) and `Background`-priority dispatch on `DisplaySettingsChanged`.
  - Refined collapsed state to a compact `iPad ▸` pill (`MinWidth="72"`) with `Segoe Fluent Icons` chevron.
- **Verification**:
  - PowerShell parser syntax check passed.
  - Verified XAML load and layout dimensions (`885 x 98` DIPs collapsed drawer, `885 x 366.9` DIPs with drawer open on `1180 x 772` DIP primary work area).
  - Restarted session via `iPad-Session.ps1 -Mode Start` and confirmed Touch Dock process is running.
