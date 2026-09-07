#Requires -Version 3.0
<#
.SYNOPSIS
    DiagMailer Launcher – Közvetlen belépési pont, automatikus jogosultság emelés
.DESCRIPTION
    Önálló futtatáshoz: automatikusan emeli a jogosultságot, majd meghívja a SendReport.ps1-et.
    A SendReport.ps1 saját maga is elvégzi az emelést, de a Launcher ezt ELŐBB csinálja meg,
    így a felhasználónak elegendő csak a Launcher.ps1-et futtatni.
    Más REPÓ-kból való híváshoz az Invoke-DiagMailer.ps1-t érdemes használni.
.PARAMETER ConfigPath
    A config.json elérési útja.
.PARAMETER ForceCredential
    Újra bekéri a jelszót, figyelmen kívül hagyja a tároltat.
.PARAMETER DeleteLogsAfterSend
    Küldés után törli a LOG fájlokat.
.EXAMPLE
    .\Launcher.ps1
    .\Launcher.ps1 -ForceCredential
    .\Launcher.ps1 -ConfigPath "D:\sajat\config.json" -DeleteLogsAfterSend
#>

param(
    [string]$ConfigPath        = "$PSScriptRoot\config.json",
    [switch]$ForceCredential,
    [switch]$DeleteLogsAfterSend
)

# ===========================================================
#  AUTOMATIKUS JOGOSULTSÁG EMELÉS
#  Mindig elvégzi, nem függ a config requireAdmin mezőjétől.
#  Ha már admin, átugorja és rögtön hívja a SendReport.ps1-et.
# ===========================================================

$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin          = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host ""
    Write-Host "  [Launcher] Emelt jogosultsag szukseges - ujrainditom..." -ForegroundColor Yellow

    # Paraméterek átadása az emelt folyamatnak
    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -ConfigPath `"$ConfigPath`""
    if ($ForceCredential)     { $argList += " -ForceCredential" }
    if ($DeleteLogsAfterSend) { $argList += " -DeleteLogsAfterSend" }

    Start-Process powershell.exe -ArgumentList $argList -Verb RunAs
    exit 0
}

# ===========================================================
#  SENDREPORT.PS1 ELLENŐRZÉSE
# ===========================================================

$SendReportScript = Join-Path $PSScriptRoot "SendReport.ps1"

if (-not (Test-Path $SendReportScript)) {
    Write-Host ""
    Write-Host "  [Launcher] XX SendReport.ps1 nem talalhato!" -ForegroundColor Red
    Write-Host "     Vart hely: $SendReportScript" -ForegroundColor DarkGray
    Write-Host "     A DiagMailer telepitese hianyos lehet." -ForegroundColor DarkGray
    Write-Host ""
    exit 1
}

# ===========================================================
#  SENDREPORT.PS1 MEGHÍVÁSA
#  Az emelés már megtörtént, a SendReport saját emelése nem fut le újra.
# ===========================================================

$scriptArgs = @{ ConfigPath = $ConfigPath }
if ($ForceCredential)     { $scriptArgs.ForceCredential     = $true }
if ($DeleteLogsAfterSend) { $scriptArgs.DeleteLogsAfterSend = $true }

& $SendReportScript @scriptArgs
exit $LASTEXITCODE
