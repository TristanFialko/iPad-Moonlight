#Requires -RunAsAdministrator
# Run as Administrator to back up and apply Sunshine iPad Workstation config
$ErrorActionPreference = 'Stop'

$sunshineCfg  = 'C:\Program Files\Sunshine\config'
$proposedConf = Join-Path $PSScriptRoot 'sunshine.conf.proposed'
$proposedApps = Join-Path $PSScriptRoot 'apps.json.proposed'

if (-not (Test-Path -LiteralPath $proposedConf)) { throw "Missing: $proposedConf" }
if (-not (Test-Path -LiteralPath $proposedApps)) { throw "Missing: $proposedApps" }

# Validate JSON before touching live Sunshine config
$null = Get-Content -LiteralPath $proposedApps -Raw | ConvertFrom-Json

$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupDir = Join-Path $sunshineCfg "backups\$ts"
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

foreach ($f in @('sunshine.conf', 'apps.json')) {
    $src = Join-Path $sunshineCfg $f
    if (Test-Path -LiteralPath $src) {
        Copy-Item -LiteralPath $src -Destination $backupDir -Force
    }
}
Write-Output "Backed up existing Sunshine config to: $backupDir"

Copy-Item -LiteralPath $proposedConf -Destination (Join-Path $sunshineCfg 'sunshine.conf') -Force
Copy-Item -LiteralPath $proposedApps -Destination (Join-Path $sunshineCfg 'apps.json') -Force
Write-Output "Applied updated sunshine.conf and apps.json"

$svc = Get-Service -Name 'SunshineService' -ErrorAction SilentlyContinue
if ($svc) {
    if ($svc.Status -eq 'Running') {
        Restart-Service -Name 'SunshineService' -Force
        Write-Output "Restarted SunshineService"
    } else {
        Start-Service -Name 'SunshineService'
        Write-Output "Started SunshineService"
    }
} else {
    Write-Warning "SunshineService not found; start Sunshine manually if running portable/user mode."
}
