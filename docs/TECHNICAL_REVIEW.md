# iPad Workstation — Independent Technical Review & Improvement Plan

Review date: 2026-11-13. Reviewed from the supplied project archive (`iPad_Workstation.7z`).

> **Testing status — read first.** Nothing in this document has been executed on the Windows host or the
> iPad. All findings come from static review of the scripts, configs, `session.log` and
> `display_topology_backup.json`. Every change below lists its own acceptance test, which must be run on
> the real machine. The patched files in this branch are syntax-checked by inspection only.

---

## 0. Executive summary

1. **Scrolling and gestures fail mainly because Windows never receives touch.** The upstream Moonlight iOS
   client converts finger input into *mouse* events (absolute or relative). Windows and every app see a
   mouse, not a touchscreen. So there's no touch panning or inertial scroll, no pinch-zoom, no
   press-and-hold right-click, no touch-keyboard auto-invoke and no edge gestures. No PowerShell button or
   registry key on the host can turn mouse events back into touch.
2. **Which Moonlight mode you use decides what breaks:**
   - *Touchscreen / direct-touch mode*: one-finger drag is sent as **left-button-drag**, so in a browser it
     selects text instead of scrolling. Per the README, two-finger gestures are used by Moonlight's own
     pan/zoom. **Scrolling is effectively impossible in this mode.**
   - *Trackpad mode*: two-finger drag becomes **mouse-wheel** events, and these do reach Windows. This is
     the only scrolling path with upstream Moonlight today.
3. **The real fix is native touch passthrough.** Sunshine already supports injecting real touch and pen
   through Windows' synthetic pointer API (`native_pen_touch`, enabled by default; no config change needed).
   The **client** has to send touch events. Check whether your installed Moonlight iOS build has a
   native-touch option. If it doesn't, evaluate a client that does (see §2.4). This is the single change
   with the largest usability payoff, and it needs no host code.
4. **Our implementation adds several real bugs**, independent of input:
   - **Display restore has never succeeded in the log.** Every `Stop` logs `SetDisplayConfig rc=87`, and the
     backup file has been stale since 05:34. The monitors are probably coming back through Sunshine's own
     display revert or Windows, not through our code.
   - **Mode-data bug.** The isolation code zeroes bytes 8–15 of the source mode, which overwrites
     `pixelFormat` and `position.x` instead of just the position (bytes 12–19).
   - **`Start` can abort the stream.** It re-throws on any error, and a failing Sunshine `do` prep command
     cancels the app launch. This puts the "working Sunshine connection" at risk.
   - **The Brave touch flags have never applied.** Brave is always already running, and the log says
     "Focused existing Brave window" on every start.
   - **The Alt+Tab button only flips to the previous window**, and dock buttons silently fail when an
     elevated window (for example Task Manager) has focus, because of UIPI.
   - **The TabletTip registry changes have no effect** while input is mouse-emulated.
   - **The dock is a topmost overlay that covers app content** (status bars, page bottoms) because it
     doesn't reserve screen space.
5. **Architectural recommendation:** let Sunshine own the display topology (`dd_configuration_option =
   ensure_only_display`) and make our script a fallback only (optional Phase 3; it is a live config change,
   so it must be A/B tested). Keep the dock, but make it a lean app-switcher and command surface that
   reserves its own screen strip. Stop adding shortcut buttons for problems that only native touch solves.

---

## 1. Technical audit

### 1.1 Architecture as built

| Component | File | Role | Runs as |
|---|---|---|---|
| Session lifecycle | `iPad-Session.ps1` | Sunshine prep-cmd `do` (Start) and `undo` (Stop); `Recover` for manual restore | User session, not elevated (`elevated:false`) |
| Dock / launcher | `iPad-TouchDock.ps1` | WPF window hosted in `powershell.exe`; topmost, `WS_EX_NOACTIVATE \| WS_EX_TOOLWINDOW`; sends key combos via `SendInput` | Background PowerShell, one process |
| Browser launch | `Launch-Brave-iPad.cmd` | Brave with touch-UI flags | — |
| Icons | `Update-AppIcons.ps1` + `assets/icons/*.png` | One-off icon extraction | Manual |
| Sunshine config | `sunshine.conf.proposed`, `apps.json.proposed`, `Apply-SunshineConfig.ps1` | Proposed live config; the apply script overwrites both files and restarts the service | Admin |
| Runtime state | `session_state.json`, `display_topology_backup.json`, `touchdock.pid`, `session.log` | Backups and logs | — |

The flow is: Moonlight launches the "iPad Workstation" app. Sunshine applies `ensure_primary` on the MTT
virtual display at 2360×1640@60. The prep command runs `-Mode Start`, which backs up state, isolates the
MTT display with `SetDisplayConfig`, sweeps windows, applies the Bibata 48 px cursor, sets TabletTip keys,
starts the dock and focuses or launches Brave. On disconnect, `-Mode Stop` reverses this, and Sunshine
reverts its own display changes (`dd_config_revert_on_disconnect`).

The architecture is reasonable for a prototype: one process, no polling timers, state saved once and
restored once. The weaknesses are listed below.

### 1.2 Findings by severity

**Critical / correctness**

| # | Finding | Evidence | Fix |
|---|---|---|---|
| A1 | **Display restore fails every time (rc=87, ERROR_INVALID_PARAMETER).** Because rc≠0 the backup is never deleted, so every later `Start` logs "already exists; preserving original topology". That backup comes from 05:34, when isolation itself failed with rc=5. Restoration only appears to work because Sunshine's revert and/or Windows' display database bring the monitors back. | `session.log` 05:37:41, 05:39:25, 05:40:30, 05:42:25 | Patched: retry, then fall back to `SDC_TOPOLOGY_EXTEND` (Windows' persisted extend layout), log clearly, and archive stale backups. See §4, P0-1. |
| A2 | **Wrong bytes zeroed in source mode.** `DISPLAYCONFIG_SOURCE_MODE` = width@0, height@4, pixelFormat@8, position.x@12, position.y@16. The loop `for b=8..15` wipes the pixel format and x, and leaves y. It works today only because `SDC_ALLOW_CHANGES` lets Windows repair it. | `iPad-Session.ps1` L286 | Patched to `12..19`. |
| A3 | **`Start` re-throws on error.** With `$ErrorActionPreference='Stop'`, any failing registry write (for example a missing Accessibility key on a future Windows build) makes the prep command exit non-zero, and Sunshine then aborts the launch. | L457–459 | Patched: log and continue; `exit 0`. |
| A4 | **Race with Sunshine's display setup.** At 05:33:18 the MTT display wasn't yet in the active paths, so isolation was skipped for that session. | `session.log` | Patched: retry up to about 5 s. |
| A5 | **Two systems both own the display topology.** Sunshine (`ensure_primary` + revert on disconnect) and our script (`SetDisplayConfig` MTT-only + our own revert) both change and revert topology, in an order we don't control. This is the most likely root cause of A1: our backup includes the MTT path, which Sunshine may be reconfiguring while our undo runs. | Design | Short term: A1 fallback. Medium term: let Sunshine own it (`ensure_only_display`), §4 P2-1. |

**Input-related (our code)**

| # | Finding | Fix |
|---|---|---|
| B1 | Brave flags never apply: Chromium ignores flags when an instance for that profile is already running, and the log shows Brave already running on every session. | Set them persistently in `brave://flags` (manual, §6), or use the optional separate profile in the patched `Launch-Brave-iPad.cmd`. |
| B2 | `--touch-events` and `OverscrollHistoryNavigation` only react to real touch or touchpad gestures. Under mouse emulation they do nothing. That isn't a bug, but they shouldn't be relied on. | Document; they start working once native touch is in place. |
| B3 | TabletTip `EnableDesktopModeAutoInvoke` / `TouchKeyboardTapInvoke` only respond to touch or pen. With mouse emulation the Windows touch keyboard never appears on its own. Moonlight's keyboard (three-finger tap) is the right path today. | Keep the keys (harmless, restored on Stop) and add a comment (patched). |
| B4 | The **Alt+Tab** button sends Alt down/Tab down/Tab up/Alt up instantly, which only flips to the previous window. | Patched to **Ctrl+Alt+Tab**, which opens the sticky switcher you can tap. |
| B5 | **UIPI:** the non-elevated dock can't send input to, or reliably focus, elevated windows (Task Manager always runs elevated). Buttons silently do nothing while one has focus. | Document. Don't run the dock elevated (every app it launches would be elevated too). `uiAccess` needs a signed exe in Program Files, which is out of scope. |
| B6 | `DragMove()` throws when the primary button isn't down (touch-promoted or synthetic input). | Patched with a guard and try/catch. |
| B7 | Hover styles (`IsMouseOver`) stick after a tap under touch. | Cosmetic; switch to `IsPressed`-only styling when native touch is adopted. |

**Window management / dock**

| # | Finding | Fix |
|---|---|---|
| C1 | The dock is a topmost overlay **on top of** the work area. Maximized windows extend underneath it, hiding the bottom ~100 DIP (status bars, chat inputs, page ends). | Register the dock as an **AppBar** (`SHAppBarMessage`) so Windows shrinks the work area. P1-2. |
| C2 | The Windows taskbar (48 DIP) and the dock both take up the bottom of a 820-DIP-tall screen, about 18% of vertical space. | During the session, auto-hide the taskbar (or rely on it and slim down the dock). P1-3. |
| C3 | "Running now" uses `Get-Process … MainWindowHandle`: one window per process (several Brave windows show as one, every Explorer window shares `explorer.exe`), it can pick "Program Manager", and it's capped at 6. | Enumerate top-level windows with Alt-Tab rules (visible, unowned, not tool window, not DWM-cloaked). P1-4. |
| C4 | Gather / `MoveOffscreenWindowsToArea` is mostly redundant once the MTT display is the only active one, because Windows moves windows itself. Keep it as a safety net; it's cheap. | No change. |
| C5 | 24 shortcut buttons, many browser-specific (tabs, zoom, reload), spread across the dock and drawer. That's high cognitive load and duplicates what native touch plus browser UI provide. | Restructure into context groups (P2-3). Don't add more. |

**Housekeeping**

- `Apply-SunshineConfig.ps1` overwrites the whole live `sunshine.conf`/`apps.json`. Use Sunshine's web UI
  for individual keys instead. Keep the script for disaster recovery only.
- Runtime files (`session.log`, PID, state, backups) live in the code folder. They're now ignored by
  `.gitignore`.
- `Get-RunningDockPids` uses a CIM query (about 0.5–1 s). That's fine.
- The cursor scheme mixes Bibata with the user's original Posy `.ani` files for Wait/AppStarting. Restore
  handles it correctly.
- The cursor size code is correct (`SPI_SETMOUSECURSORSIZE` + `SPI_SETCURSORS` + Accessibility
  `CursorSize`). Under native touch the cursor is hidden while touching, so 48 px matters less.

---

## 2. Touch-input investigation (highest priority)

### 2.1 The input pipeline

```
iPad finger → Moonlight iOS (touch handler) → Moonlight protocol → Sunshine → Windows injection → app
                 │                                                    │
                 ├─ mouse move/button (abs or rel) ──────────────────►│ SendInput (mouse)
                 ├─ scroll (high-res) ───────────────────────────────►│ SendInput MOUSEEVENTF_WHEEL
                 └─ touch/pen events (only if the client sends them) ►│ InjectSyntheticPointerInput (real touch)
```

Whatever leaves Moonlight decides what Windows can do. Sunshine faithfully injects what it's given.

### 2.2 Behaviour by mode (upstream Moonlight iOS, mouse emulation)

| Gesture | Direct-touch / touchscreen mode | Trackpad mode | Native touch passthrough |
|---|---|---|---|
| Tap | Left click at the finger | Left click at the cursor | Touch tap |
| One-finger drag | **Left-button drag**: selects text / drags items, **does not scroll** | Moves the cursor | **Pans / scrolls with inertia** |
| Two-finger drag | Moonlight local pan/zoom (per README) | **Wheel scroll** | Pan / scroll |
| Pinch | Moonlight local zoom | — | App zoom (Brave, Photos, maps) |
| Long-press | Right click (client-dependent) | Long-press then drag = drag | Windows press-and-hold → right click |
| Two-finger tap | — | Right click | — |
| Three-finger tap | Keyboard | Keyboard | Keyboard (client) |
| Text selection | One-finger drag (works) | Double-tap-hold-drag | Long-press handles in touch-aware apps |
| Window move | Drag title bar (works) | Long-press-drag | Touch drag on the title bar |
| Windows touch keyboard | Never auto-appears | Never | Auto-appears on text field tap |

Gestures are client-version dependent. Use `tools/Test-InputDiagnostics.ps1` to confirm on your device.

### 2.3 Where each problem comes from

| Symptom | Origin | Explanation |
|---|---|---|
| One-finger scroll doesn't work | **Moonlight** | Direct mode sends left-drag. Windows correctly treats it as a selection. |
| Two-finger scroll in direct mode | **Moonlight** | Used by the client's own pan/zoom; never sent. |
| Scrolling in trackpad mode is jerky or missing in some apps | **Windows / app** + Sunshine setting | High-res fractional wheel deltas (<120) are ignored or accumulated badly by some legacy Win32 apps. Brave and Explorer handle them. Sunshine's `high_resolution_scrolling = disabled` aggregates to 120-unit notches (live config change; only if diagnostics show the problem). |
| No pinch-zoom, no inertia, no overscroll back | **Moonlight** (no touch sent) | Windows needs WM_POINTER touch; mouse can't express it. |
| Windows touch keyboard never appears | **Windows** behaviour, triggered by Moonlight mouse emulation | Auto-invoke requires touch or pen input. |
| Dock buttons ineffective over Task Manager | **Windows (UIPI)** + **our design** | Non-elevated `SendInput` is blocked toward elevated windows. |
| Brave touch UI flags missing | **Our code** | Flags ignored because Brave is already running (B1). |
| Dock covers content | **Our code** | No AppBar reservation (C1). |
| Alt+Tab button useless | **Our code** | Instant release (B4). |

### 2.4 Getting native touch into Windows (the strategic fix)

- **Host side (already done):** Sunshine on Windows injects touch and pen with
  `CreateSyntheticPointerDevice` / `InjectSyntheticPointerInput` (Windows 10 1809+). The
  `native_pen_touch` setting defaults to enabled; check it in Sunshine Web UI → Configuration → Input
  without changing anything. `SM_DIGITIZER` / `SM_MAXIMUMTOUCHES` in the diagnostics tool show whether a
  touch device is present while streaming.
- **Client side (needs action):**
  1. In Moonlight on the iPad, open Settings and look for a native touch / multi-touch passthrough option.
     Upstream Moonlight iOS has historically offered only *Touchscreen (mouse)* and *Trackpad* modes. Check
     the version you have installed.
  2. If there's no such option, evaluate a Moonlight-protocol client for iOS that sends native multi-touch
     to Sunshine. Community forks of moonlight-ios exist for this, for example "VoidLink" (formerly
     *moonlight-ios-NativeMultiTouchPassthrough*). Check availability, maintenance status and trust before
     installing. **This is a client-side decision for you; nothing on the host changes, and it doesn't
     affect the Sunshine connection.**
  3. With native touch, Windows 11 behaves like a touch laptop: one-finger scroll, pinch, press-and-hold
     right click, touch keyboard, touch-sized context menus in Explorer and Brave, and drag handles for text
     selection.
- **Not viable:** making the dock or a host-side hook convert emulated mouse drags into touch
  (`InjectTouchInput`). It would need a low-level mouse hook to classify every drag as scroll or select,
  which breaks text selection, window dragging and games, adds latency, and is fighting the client.
  Rejected.

### 2.5 If you must stay on upstream Moonlight (fallback strategy)

- Use **Trackpad mode** as the default: two-finger scroll, two-finger-tap right click, three-finger-tap
  keyboard. This is the only mode with working scroll.
- Use direct-touch mode only for precise pointing or text selection, and switch modes in Moonlight's
  overlay when needed.
- Make scroll targets large: Brave `brave://settings/appearance` zoom 110–125%, and Windows text size.
- Optional: an **edge scroll rail** (a thin strip on the right edge where vertical drags send wheel events
  to the window under the last touch point via `PostMessage(WM_MOUSEWHEEL)`). It's feasible but fragile
  (window targeting, DPI, apps that only accept real wheel input), so it's rated P3 and only worth doing if
  native touch can't be used.

---

## 3. Usability improvement plan

Legend: **Admin** = needs elevation · **Term** = needs a terminal / script run on the host ·
**Win** = manual interaction with Windows UI · **Existing** = fits in existing files · **iPad** = must be
verified on the physical iPad.

| ID | Improvement | What it solves | How | Admin | Term | Win | Existing | iPad |
|---|---|---|---|---|---|---|---|---|
| T1 | Native touch passthrough client | Scrolling, pinch, long-press, touch keyboard, inertia | §2.4. Client change; verify `native_pen_touch` in Web UI | No | No | Web UI check | n/a | **Yes** |
| T2 | Standardise Trackpad mode if T1 unavailable | Working scroll today | Moonlight setting; update README | No | No | No | README | Yes |
| T3 | Input diagnostics tool | Objective root-cause data instead of guessing | New `tools/Test-InputDiagnostics.ps1` (included) | No | Yes | No | New file | **Yes** |
| T4 | `high_resolution_scrolling = disabled` (conditional) | Legacy apps ignoring fractional wheel deltas | Sunshine Web UI, single key. Only if T3 shows fractional deltas and an app ignores them | Web UI login | No | Yes | n/a | Yes |
| D1 | Robust display restore | rc=87, stale backups | Patched `iPad-Session.ps1` | No | No | No | Yes | Yes (connect/disconnect) |
| D2 | Let Sunshine own topology (`ensure_only_display`) | Removes dual ownership (A5) | Web UI: Display device → *Deactivate other displays*; then set `$UseScriptIsolation=$false` in the script | Web UI | No | Yes | Small edit | **Yes** |
| W1 | AppBar dock reservation | Dock hides content | `SHAppBarMessage` ABM_NEW/QUERYPOS/SETPOS/REMOVE in `TouchDockNative`; call on Loaded / size change / Closed | No | No | No | Dock | Yes |
| W2 | Taskbar auto-hide during session | Wasted vertical space, duplicate launchers | Save/restore `HKCU\…\Explorer\StuckRects3` byte 8 (`0x03` auto-hide / `0x02` normal) + `SHAppBarMessage(ABM_SETSTATE)` (no Explorer restart) in Start/Stop | No | No | No | Session | Yes |
| W3 | Proper window list | Multi-window apps, Explorer windows, wrong entries | EnumWindows + Alt-Tab filter + `DwmGetWindowAttribute(DWMWA_CLOAKED)` | No | No | No | Dock | Yes |
| W4 | Big-target window actions on the current window | Tiny caption buttons (46×32 px physical) | Dock row: Snap L/R, Maximise, Minimise, Close (exists). Add **Snap Layouts** (Win+Z) | No | No | No | Dock | Yes |
| W5 | Touch-friendly app switching | Win+Tab is fine but small thumbnails | Task View (exists) + sticky Ctrl+Alt+Tab (patched) + W3 list | No | No | No | Dock | Yes |
| W6 | Full-screen app management | Apps leave stray windows; F11 confusion | "Focus mode" button: maximise the foreground window and collapse the dock to the pill; restore on tap | No | No | No | Dock | Yes |
| B1 | Brave persistent touch configuration | Flags never apply | `brave://flags`: *Touch UI Layout* = Enabled, *Overscroll history navigation* = Enabled, *Touch Events API* = Enabled; default zoom 110–125%; enable *Vertical tabs* (bigger targets) | No | No | **Yes** | n/a | Yes |
| B2 | Optional dedicated iPad profile | Flags apply regardless of running Brave | Patched `Launch-Brave-iPad.cmd` (`IPAD_BRAVE_SEPARATE_PROFILE=1`) | No | No | No | Yes | Yes |
| K1 | Keyboard strategy | Typing | Use Moonlight's keyboard (three-finger tap) or a Bluetooth keyboard paired to the **iPad** (it works through Moonlight). Windows touch keyboard only after T1 | No | No | No | README | Yes |
| K2 | Clipboard | iPad ↔ PC copy/paste | Win+V history (exists; enable once in Settings → System → Clipboard). Cross-device: Moonlight doesn't sync clipboard. Use a shared Notes/Drive doc or a LAN tool (e.g. LocalSend) | No | No | Yes | — | Yes |
| F1 | File management | Tiny Explorer rows, no drag-and-drop | Explorer: *View → Compact view* **off**, *Large icons*; enable *Item check boxes* (select without Ctrl); pin common folders to Quick access. Use Cut/Paste (dock) instead of drag-and-drop | No | No | Yes | — | Yes |
| F2 | Drag-and-drop alternative | DnD unreliable under emulation | Standardise on Cut → navigate → Paste; "Move to/Copy to" via Explorer right-click → Show more options | No | No | Yes | — | Yes |
| S1 | System controls | Volume/brightness/Wi-Fi without tiny tray | Volume buttons exist. Add **Quick Settings (Win+A)** and **Notifications (Win+N)** buttons | No | No | No | Dock | Yes |
| S2 | Context menus | Small menus | Shift+F10 exists. With T1, Windows uses touch-spaced menus automatically. Optional: Windows Settings → Accessibility → Text size 110% | No | No | Yes | — | Yes |
| R1 | Resolution & scaling | Target sizes vs. space | Keep 2360×1640 @ 200% (native iPad Air 4 panel, 1:1 pixels, 1180×820 DIP). Don't go below 175%. Avoid per-app `--force-device-scale-factor` | No | No | Maybe | — | Yes |
| P1 | Performance & latency | Lag, artifacts | Moonlight: HEVC, 2360×1640@60, bitrate 30–50 Mbps on 5 GHz Wi-Fi, frame pacing on. Sunshine `nvenc_preset` 3 is fine; try 1–2 for lower latency. Laptop on AC power, Windows "Best performance" power mode | No | No | Yes | — | **Yes** |
| P2 | Dock footprint | ~100–150 MB PowerShell+WPF process | Acceptable for now. Long-term: port the dock to a small compiled .NET app (same XAML) for faster start and less memory | No | Yes (build) | No | New project | Yes |
| N1 | Session-ready notification | Don't know if Start succeeded | Already in `session.log`; optionally show a 2-s toast from the dock on load summarising display/cursor state | No | No | No | Dock | No |
| N2 | One-tap recovery | Stuck on a black laptop screen after a crash | Desktop shortcut + Start-menu entry for `-Mode Recover`; document **Win+P → Extend** and **Win+Ctrl+Shift+B** | No | No | Yes | README | No |

**Not recommended / technically unsuitable**

- **More shortcut buttons to fix gestures.** Buttons can't create scroll, pinch or press-and-hold. Only T1 can.
- **Host-side mouse→touch conversion hook.** See §2.4. Fragile and conflicts with selection and games.
- **Windows "tablet mode".** It doesn't exist as a toggle on Windows 11. Touch optimisations trigger
  automatically when a touch digitizer is present (T1).
- **Running the dock elevated** to beat UIPI. Every app it launches would inherit elevation.
- **`--force-device-scale-factor` for Brave.** Already removed. Use browser zoom instead.

---

## 4. Prioritised roadmap and implementation instructions

### P0 — correctness (this branch; apply first)

**P0-1 `iPad-Session.ps1` (patched in this branch, complete replacement file)**

Changes:
1. `SDC_TOPOLOGY_EXTEND` and `SDC_SAVE_TO_DATABASE` constants.
2. The source-mode position zeroing now covers bytes 12–19 (was 8–15).
3. Waits up to about 5 s for the MTT path to appear before giving up on isolation.
4. Stale backup handling: if the previous Stop completed (no `session_state.json`) but a display backup
   remains, it's renamed `display_topology_backup.json.stale-<timestamp>` and a fresh one is captured,
   provided more than one display is active.
5. Restore: three attempts with `SDC_USE_SUPPLIED_DISPLAY_CONFIG`, then a fallback to `SetDisplayConfig(0,
   null, 0, null, SDC_APPLY|SDC_TOPOLOGY_EXTEND)`. The backup is deleted only on success, with a clear
   warning otherwise.
6. Start and Stop never re-throw. The script ends with `exit 0`.
7. A comment explaining why the TabletTip keys only matter under native touch.

Acceptance:
- Connect from the iPad. The log shows "Isolated active display to MTT virtual display only (rc=0)", and
  only the virtual display is active.
- Disconnect. The log shows either `Restore attempt 1 … rc=0` or `Fallback SDC_TOPOLOGY_EXTEND restore
  rc=0`, followed by "backup removed". The laptop panel and external monitor come back with their original
  arrangement and refresh rates (144 Hz on the external monitor per the backup).
- `display_topology_backup.json` doesn't exist after a clean disconnect.
- Reconnect five times in a row. There are no "already exists; preserving" lines except after a crash.
- Make Start fail on purpose (for example, temporarily rename the Bibata folder). The stream still starts.
- Before applying, delete the current stale `display_topology_backup.json` on the host, while the
  monitors are in their normal state (manual step M1).

**P0-2 `iPad-TouchDock.ps1` (patched, minimal edits)**

- `DragMove` guard (B6).
- The Alt+Tab button sends Ctrl+Alt+Tab (sticky switcher) (B4).

Acceptance: dragging the handle never logs an exception, and the switcher button opens a switcher that
stays visible until a window is tapped.

**P0-3 `Launch-Brave-iPad.cmd` (patched)**: comments, plus an optional separate profile. Acceptance: with
`IPAD_BRAVE_SEPARATE_PROFILE=1`, `brave://version` shows the flags on the command line even while the
main Brave is running.

**P0-4 `tools/Test-InputDiagnostics.ps1` (new)**: run it in each Moonlight mode and save the log. This
decides T1/T2/T4.

Acceptance (and the root-cause proof):
- In direct-touch mode, one-finger drag on the pad gives only `MOUSE DOWN … source=mouse`, which
  confirms mouse emulation.
- In Trackpad mode, two-finger drag gives `WHEEL delta=…` lines, which confirms wheel delivery.
- With a native-touch client, `TOUCH DOWN` lines appear and `SM_MAXIMUMTOUCHES` > 0.

### P1 — biggest usability gains

**P1-1 Native touch client (T1)**: manual, on the iPad. Then re-run P0-4. If touch arrives, set Brave
flags (M2) and verify one-finger scroll, pinch and press-and-hold in Brave and Explorer.

**P1-2 AppBar reservation (W1) in `iPad-TouchDock.ps1`**: add to `TouchDockNative`:

```csharp
[StructLayout(LayoutKind.Sequential)] public struct APPBARDATA {
    public int cbSize; public IntPtr hWnd; public uint uCallbackMessage; public uint uEdge;
    public RECT rc; public IntPtr lParam;
}
[DllImport("shell32.dll")] public static extern UIntPtr SHAppBarMessage(uint dwMessage, ref APPBARDATA pData);
public const uint ABM_NEW = 0, ABM_REMOVE = 1, ABM_QUERYPOS = 2, ABM_SETPOS = 3, ABE_BOTTOM = 3;

// Reserve 'heightPx' physical pixels at the bottom of the monitor (rcMonitor in physical px).
public static void ReserveBottom(IntPtr hwnd, int left, int right, int bottom, int heightPx, bool first) {
    var abd = new APPBARDATA(); abd.cbSize = Marshal.SizeOf(typeof(APPBARDATA)); abd.hWnd = hwnd;
    if (first) { abd.uCallbackMessage = 0x8000 + 77; SHAppBarMessage(ABM_NEW, ref abd); }
    abd.uEdge = ABE_BOTTOM;
    abd.rc.Left = left; abd.rc.Right = right; abd.rc.Bottom = bottom; abd.rc.Top = bottom - heightPx;
    SHAppBarMessage(ABM_QUERYPOS, ref abd);
    abd.rc.Top = abd.rc.Bottom - heightPx;
    SHAppBarMessage(ABM_SETPOS, ref abd);
}
public static void Release(IntPtr hwnd) {
    var abd = new APPBARDATA(); abd.cbSize = Marshal.SizeOf(typeof(APPBARDATA)); abd.hWnd = hwnd;
    SHAppBarMessage(ABM_REMOVE, ref abd);
}
```

Instructions:
- Reserve **only the collapsed bar height** (the `ButtonsPanel` row, about 66 DIP × DPI scale), not the
  launcher overlay.
- Call it from `Add_Loaded` (first=true) and after collapse/expand.
- Call `Release` in `Add_Closed`.
- In `iPad-Session.ps1 -Mode Stop`, send `WM_CLOSE` to the dock window (find it by title `iPadTouchDock`)
  and wait up to 2 s before `Stop-Process -Force`, so `ABM_REMOVE` runs. A force-killed AppBar can leave
  the work area reduced until Explorer recalculates it.
- Position the dock *inside* the reserved strip. Keep the Windows taskbar below or auto-hidden (P1-3).

Acceptance: a maximized Brave window's bottom edge sits directly above the dock, and the work area is
restored after Stop (check with a maximized window on the laptop panel).

**P1-3 Taskbar auto-hide during the session (W2)**: in Start, save the current auto-hide state into
`session_state.json` (`TaskbarAutoHide`) and set auto-hide with `SHAppBarMessage(ABM_SETSTATE=10,
lParam=ABS_AUTOHIDE=1)` (immediate, no Explorer restart). Restore it in Stop. Acceptance: the taskbar
hides during the session, comes back after disconnect, and survives a reboot in the original state.

**P1-4 Window list (W3)**: replace `Update-RunningApps`' `Get-Process` query with a C#
`EnumAltTabWindows()` that returns hwnd, title and pid for windows that are visible, have no owner
(`GetWindow(h, GW_OWNER)==0`), lack `WS_EX_TOOLWINDOW` and aren't cloaked
(`DwmGetWindowAttribute(h, 14, out int cloaked, 4)` → 0). Show up to 12 entries, each with a close (×)
button (`PostMessage(h, WM_CLOSE)`). Acceptance: two Brave windows and two Explorer windows appear as four
entries, and Program Manager never appears.

### P2 — structure

**P2-1 Let Sunshine own topology (D2).** Manual change in Sunshine Web UI: *Audio/Video → Display Device
configuration → Deactivate other displays* (`dd_configuration_option = ensure_only_display`). Keep
`dd_config_revert_on_disconnect = enabled`. Then add a switch at the top of `iPad-Session.ps1`:
`$UseScriptIsolation = $false`, and skip `Save-And-IsolateMttDisplay`/`Restore-DisplayTopology` when it's
false. Keep the window sweep. Roll back by setting the Web UI option back to *ensure_primary* and the switch
to `$true`. This is a live config change. Do it only after P0-1 is verified, and test five
connect/disconnect cycles plus one forced disconnect (iPad Wi-Fi off).

**P2-2 Dock restructure (C5).** The primary bar is Home, Switcher (Task View), Back, Copy, Paste, Keyboard
hint, More, Collapse. The drawer is grouped as *Window* (Snap L/R, Max, Min, Snap Layouts, Close,
Gather), *Browser* (tabs, reload, zoom, fullscreen), *Edit* (Cut, Undo, Redo, Select all, Find, Clipboard
history, Enter) and *System* (Quick Settings Win+A, Notifications Win+N, volume, Snip, Settings, Files).
Add Win+Z, Win+A and Win+N with existing `SendCombo`. Remove nothing without testing first.

**P2-3 Recovery shortcut (N2).** Create a Desktop shortcut "Restore displays" →
`powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\PC\Dev_Tools\iPad_Workstation\iPad-Session.ps1" -Mode Recover`.

### P3 — optional

- Edge scroll rail (§2.5), only if native touch is impossible.
- Port the dock to a compiled .NET 8 WPF app (P2).
- Clipboard bridge tooling (K2).

---

## 5. Files changed / added in this branch

| File | Status | Notes |
|---|---|---|
| `iPad-Session.ps1` | Modified (complete file) | P0-1 |
| `iPad-TouchDock.ps1` | Modified (2 small edits, BOM preserved) | P0-2 |
| `Launch-Brave-iPad.cmd` | Modified | P0-3 |
| `tools/Test-InputDiagnostics.ps1` | New | P0-4 |
| `.gitignore` | New | Runtime artifacts |
| `docs/TECHNICAL_REVIEW.md` | New | This document |

No new dependencies. Everything uses Windows PowerShell 5.1, WPF and Win32 APIs already used by the
project. `assets/icons/*.png` aren't in the repository (binary upload wasn't possible). Regenerate them
with `Update-AppIcons.ps1` or copy them from the original folder.

---

## 6. Manual steps on the Windows host

- **M1** Before deploying P0-1, with all monitors in their normal state and no stream running, delete
  `C:\PC\Dev_Tools\iPad_Workstation\display_topology_backup.json` (stale since 05:34).
- **M2** Brave: open `brave://flags` and enable *Touch UI Layout*, *Overscroll history navigation* and
  *Touch Events API*, then relaunch. Settings → Appearance → Page zoom 110–125%. Optionally enable vertical
  tabs.
- **M3** Sunshine Web UI (read only): confirm *Native Pen/Touch support* is enabled. Change
  `high_resolution_scrolling` only if T4 applies. Change `dd_configuration_option` only for P2-1.
- **M4** Windows: Settings → System → Clipboard → Clipboard history **On**. Settings → Bluetooth & devices
  → Mouse → *Scroll inactive windows when hovering* **On**. Explorer → View → turn off Compact view, and
  Show → Item check boxes.
- **M5** iPad Moonlight: choose the touch mode (native if available, otherwise Trackpad), and set HEVC,
  2360×1640, 60 FPS, a 30–50 Mbps bitrate and frame pacing.
- **M6** Create the recovery shortcut (P2-3).

## 7. Test matrix (run on the physical iPad)

| Test | Expected (native touch) | Expected (trackpad) |
|---|---|---|
| Scroll a long page in Brave | One-finger, inertial | Two-finger, smooth |
| Scroll an Explorer folder | One-finger | Two-finger |
| Pinch-zoom a web page | Zooms | n/a (Ctrl+/− buttons) |
| Right-click | Press-and-hold | Two-finger tap |
| Select text in Notepad | Long-press + handles / drag | Double-tap-hold-drag |
| Move a window | Drag title bar | Long-press-drag title bar |
| Touch keyboard | Appears on text field tap | Three-finger tap (Moonlight keyboard) |
| Dock over Task Manager | Buttons ignored (UIPI, expected) | Same |
| Maximized window vs dock | Not covered (after P1-2) | Same |
| Disconnect | Monitors restored, no backup file left | Same |
