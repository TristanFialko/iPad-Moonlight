@echo off
rem Launch Brave for the iPad session.
rem IMPORTANT: Chromium ignores command-line flags when a Brave process for the same user-data-dir is
rem already running (session.log shows "Focused existing Brave window" on every start, so these flags
rem have never actually applied). Persistent alternative: set the equivalents once in brave://flags
rem (see docs/TECHNICAL_REVIEW.md, section M2). Set IPAD_BRAVE_SEPARATE_PROFILE=1 below to use a
rem dedicated iPad profile directory so the flags always apply (separate logins/extensions).
set "IPAD_BRAVE_SEPARATE_PROFILE=0"
set "BRAVE=C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe"
set "FLAGS=--top-chrome-touch-ui=enabled --touch-events=enabled --enable-features=TouchpadOverscrollHistoryNavigation,OverscrollHistoryNavigation --start-maximized"
if "%IPAD_BRAVE_SEPARATE_PROFILE%"=="1" (
  start "" "%BRAVE%" --user-data-dir="%LOCALAPPDATA%\BraveSoftware\Brave-iPad" %FLAGS%
) else (
  start "" "%BRAVE%" %FLAGS%
)
