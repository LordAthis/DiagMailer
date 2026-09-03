#Requires -Version 3.0
<#
.SYNOPSIS
    DiagMailer Launcher – Közvetlen belépési pont, jogosultság kezelés

.DESCRIPTION
    Önálló futtatáshoz: kicsit körülnéz, emeli a jogosultságot ha kell,
    majd meghívja a SendReport.ps1-et.

    Más REPÓ-kból való automatizált híváshoz inkább az Invoke-DiagMailer.ps1-t
    vagy közvetlenül a SendReport.ps1-t érdemes hívni.

.PARAMETER ConfigPath
    A config.json elérési útja.

.PARAMETER ForceCredential
    Újra bekéri a jelszót, figyelmen kívül hagyja a tároltat.

.PARAMETER DeleteLogsAfterSend
    Küldés után törli a LOG fájlokat.

.PARAMETER SkipElevation
    Nem próbálja meg emelni a jogosultságot (pl. már admin kontextusból hívva).

.EXAMPLE
    .\Launcher.ps1
    .\Launcher.ps1 -ForceCredential
    .\Launcher.ps1 -DeleteLogsAfterSend -SkipElevation
#>

param(
    [string]$ConfigPath       = "$PSScriptRoot\config.json",
    [switch]$ForceCredential,
    [switch]$DeleteLogsAfterSend,
    [switch]$SkipElevation
)

# ── Útvonalak ─────────────────────────────────────────────────────
$SendReportScript = Join-Path $PSScriptRoot "SendReport.ps1"

# ── SendReport.ps1 meglétének ellenőrzése ─────────────────────────
if (-not (Test-Path $SendReportScript)) {
    Write-Host ""
    Write-Host "  ✗ SendReport.ps1 nem található!" -ForegroundColor Red
    Write-Host "    Várt helye: $SendReportScript" -ForegroundColor DarkGray
    Write-Host "    A DiagMailer telepítése hiányos lehet." -ForegroundColor DarkGray
    Write-Host ""
    exit 1
}

# ── Admin ellenőrzés ──────────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

# Config-ból nézzük meg, kell-e admin (ha a config olvasható)
$requireAdmin = $false
if (Test-Path $ConfigPath) {
    try {
        $cfgQuick = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $cfgQuick.requireAdmin) { $requireAdmin = [bool]$cfgQuick.requireAdmin }
    }
    catch { <# config hiba esetén a SendReport.ps1 kezeli #> }
}

if ($requireAdmin -and -not $isAdmin -and -not $SkipElevation) {
    Write-Host ""
    Write-Host "  ⚠ Rendszergazdai jogosultság szükséges." -ForegroundColor Yellow
    Write-Host "  → Újraindítás emelt módban (UAC ablak jelenik meg)..." -ForegroundColor White
    Write-Host ""

    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$SendReportScript`" -ConfigPath `"$ConfigPath`""
    if ($ForceCredential)    { $argList += " -ForceCredential" }
    if ($DeleteLogsAfterSend){ $argList += " -DeleteLogsAfterSend" }

    Start-Process powershell.exe -ArgumentList $argList -Verb RunAs
    exit 0
}

# ── Közvetlen futtatás ────────────────────────────────────────────
#    (már admin vagyunk, vagy requireAdmin = false)

$scriptArgs = @{ ConfigPath = $ConfigPath }
if ($ForceCredential)    { $scriptArgs.ForceCredential    = $true }
if ($DeleteLogsAfterSend){ $scriptArgs.DeleteLogsAfterSend = $true }

& $SendReportScript @scriptArgs
exit $LASTEXITCODE
