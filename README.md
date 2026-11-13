# iPad Workstation (Sunshine + Moonlight)

Touchscreen-first Windows 11 workstation for Apple iPad Air 4 (2360×1640 @ 60Hz) via Sunshine + Moonlight.

## Files

- `iPad-Session.ps1` — Session lifecycle manager (`-Mode Start` / `-Mode Stop` / `-Mode Recover`).
  - Saves & restores full cursor scheme (`Bibata-Modern-Classic-Regular Cursors`), live cursor size (`32` ↔ `48` via `SPI_SETMOUSECURSORSIZE` + `Accessibility\CursorSize`), and Windows Touch Keyboard (`TabletTip\1.7`) settings.
  - Backs up active `DisplayConfig` topology (`display_topology_backup.json`), isolates `VDD by MTT` (`MTT1337`) when permitted, sweeps off-screen windows onto the virtual display, and restores the original multi-monitor topology on disconnect/stop.
  - Launches/stops the Touch Dock (`touchdock.pid`) and focuses/launches Brave.
- `iPad-TouchDock.ps1` — Floating liquid-glass WPF overlay (`WS_EX_NOACTIVATE`) with adaptive DPI/work-area sizing, `Home` App Launcher (with real extracted app icons & live running-window switcher), `⋯` Quick Actions drawer, `Gather` off-screen windows action, and collapse toggle (`iPad ▸`).
- `Update-AppIcons.ps1` — Extracts 128×128 transparent PNG logos from local executables into `assets/icons/` (works offline).
- `Launch-Brave-iPad.cmd` — Launches Brave (default profile preserved) with `--top-chrome-touch-ui=enabled --touch-events=enabled --enable-features=TouchpadOverscrollHistoryNavigation,OverscrollHistoryNavigation --start-maximized` (inheriting Windows' native 200% DPI scaling).
- `sunshine.conf.proposed` / `apps.json.proposed` / `Apply-SunshineConfig.ps1` — Sunshine configuration templates and elevated installer.

## Touch Dock & Home Launcher

**Primary Bar:**
- `⋮⋮` Drag handle | `Home` (App Launcher & Running Apps) | `Apps` (`Win+Tab`) | `Desk` (`Win+D`) | `Brave` | `←` Back | `+ Tab` | `Next` (`Ctrl+Tab`) | `Close` (`Ctrl+W`) | `Copy` | `Paste` | `Undo` | `Menu` (`Shift+F10`) | `⋯` Quick Actions | `◀` Collapse to `iPad ▸`

**Quick Actions (`⋯`) Drawer:**
- **Clipboard & Edit**: `Clipboard` (`Win+V`), `Cut` (`Ctrl+X`), `Redo` (`Ctrl+Y`), `Enter`
- **Browser & Zoom**: `Select All`, `Find`, `Prev Tab`, `Forward`, `Reload`, `Reopen`, `Zoom -`, `Zoom +`, `Fullscreen`
- **Window Management**: `Last App` (`Alt+Tab`), `Gather` (pull off-screen windows onto iPad display), `Snap Left`, `Snap Right`, `Maximize`, `Minimize`, `Close App` (`Alt+F4`)
- **System & Audio**: `Files`, `Screenshot` (`Win+Shift+S`), `Vol -`, `Mute`, `Vol +`, `Settings`

## Recommended Moonlight iPad Configuration & Gestures

Use **Trackpad Mode** in Moonlight for iPadOS (recommended for desktop & browser use):
- **One-finger drag:** Move cursor
- **Single tap:** Left click
- **Two-finger tap:** Right click (or use dock `Menu`)
- **Two-finger vertical drag:** Scroll (works in Brave, File Explorer, menus, and file lists)
- **Long press + drag:** Click-and-drag / text selection
- **Three-finger tap:** Moonlight built-in iPadOS keyboard (includes `Esc`, `Tab`, `Shift`, `Ctrl`, `Alt`, `Del`, `Win`)

*(Note: Moonlight's Direct Touchscreen mode maps two-finger drag to pan/pinch-to-zoom instead of vertical scroll-wheel events; switch to Trackpad Mode if scrolling in Brave or File Explorer does not trigger.)*

## Recovery

If a session ever terminates unexpectedly, run:
```powershell
powershell -ExecutionPolicy Bypass -File "C:\PC\Dev_Tools\iPad_Workstation\iPad-Session.ps1" -Mode Recover
```
