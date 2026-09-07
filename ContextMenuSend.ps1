#Requires -Version 3.0
<#
.SYNOPSIS
    DiagMailer - Jobb klikk kontextusmenü hívó script
.DESCRIPTION
    Ez a fájl kerül C:\Windows\Scripts\DiagMailerSend.ps1 helyre a telepítő által.
    A Windows Explorer jobb klikk menüjéből hívódik meg automatikusan.

    Működés:
      1. Megkapja a kattintott mappa elérési útját (%1 vagy %V)
      2. A rendszerleíróból olvassa a DiagMailer telepítési helyét
      3. Megkeresi a LOG vagy log almappát a kattintott mappában
      4. Meghívja a SendReport.ps1-et a talált LOG mappával

    Registry kulcs (ContextMenuInstaller.ps1 írja): HKCU\Software\DiagMailer\InstallPath
.PARAMETER TargetDir
    A jobb klikkel megnyitott mappa elérési útja (%1 mappára, %V háttérre).
.EXAMPLE
    .\ContextMenuSend.ps1 -TargetDir "C:\Projektek\UgyfelGep"
#>

param(
    [string]$TargetDir
)

# ===========================================================
#  AUTOMATIKUS JOGOSULTSÁG EMELÉS
# ===========================================================

$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin          = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    # Tombot hasznalunk - egyszeru string szokoznél rosszul darabolja az utvonalakat!
    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath, "-TargetDir", $TargetDir)
    Start-Process powershell.exe -ArgumentList $argList -Verb RunAs
    exit 0
}

# ===========================================================
#  BEÁLLÍTÁSOK
# ===========================================================
 
$script:Version        = "3.3.1"

# ===========================================================
#  SEGÉDFÜGGVÉNYEK
# ===========================================================

function Write-Step { param([string]$Msg) Write-Host "  -> $Msg" -ForegroundColor White }
function Write-OK   { param([string]$Msg) Write-Host "  OK $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "  !! $Msg" -ForegroundColor Yellow }
function Write-Fail { param([string]$Msg) Write-Host "  XX $Msg" -ForegroundColor Red }
function Write-Tip  { param([string]$Msg) Write-Host "     $Msg" -ForegroundColor DarkGray }

# ===========================================================
#  FŐPROGRAM
# ===========================================================

Write-Host ""
Write-Host "  +==========================================+" -ForegroundColor Cyan
Write-Host "  |   DiagMailer - LOG Kuldes (jobb klikk)  |" -ForegroundColor Cyan
Write-Host "  +==========================================+" -ForegroundColor Cyan
Write-Host ""

# ── 1. DiagMailer telepítési út olvasása a registry-ből ──────────
$regPath = "HKCU:\Software\DiagMailer"

if (-not (Test-Path $regPath)) {
    Write-Fail "DiagMailer nincs telepitve a rendszerbe!"
    Write-Tip  "Futtasd a ContextMenuInstaller.ps1-et a telepiteshez."
    Write-Host ""
    Read-Host "  [Enter] a kilepeshez"
    exit 1
}

$diagMailerRoot = (Get-ItemProperty -Path $regPath -Name "InstallPath" -ErrorAction SilentlyContinue).InstallPath

if ([string]::IsNullOrWhiteSpace($diagMailerRoot)) {
    Write-Fail "DiagMailer telepitesi ut nem talalhato a registry-ben!"
    Write-Tip  "Telepitsd ujra: ContextMenuInstaller.ps1 -Action Install"
    Write-Host ""
    Read-Host  "  [Enter] a kilepeshez"
    exit 1
}

$sendScript = Join-Path $diagMailerRoot "SendReport.ps1"
$configPath = Join-Path $diagMailerRoot "config.json"

if (-not (Test-Path $sendScript)) {
    Write-Fail "SendReport.ps1 nem talalhato: $sendScript"
    Write-Warn "DiagMailer atvette a helyet? Telepitsd ujra a ContextMenuInstaller.ps1-el."
    Write-Host ""
    Read-Host  "  [Enter] a kilepeshez"
    exit 1
}

Write-OK "DiagMailer: $diagMailerRoot"

# ── 2. Célmappa tisztítása (idézőjelek, szóközök) ──────────────────
$targetClean = $TargetDir.Trim().Trim('"').Trim("'")

# Ha fájlra kattintottak (nem mappára), a szülőmappát használjuk
if (Test-Path $targetClean -PathType Leaf) {
    $targetClean = Split-Path -Parent $targetClean
}

if (-not (Test-Path $targetClean)) {
    Write-Fail "A cel mappa nem letezik: $targetClean"
    Write-Host ""
    Read-Host  "  [Enter] a kilepeshez"
    exit 1
}

Write-Step "Cel mappa: $targetClean"

# ── 3. LOG almappa keresése a kattintott mappában ─────────────────
# Több névvariációt próbál, kis/nagybetű érzékeny rendszerek miatt
$logCandidates = @("LOG", "log", "Log", "Logs", "logs", "LOGS")
$logFolder = $null

foreach ($name in $logCandidates) {
    $candidate = Join-Path $targetClean $name
    if (Test-Path $candidate -PathType Container) {
        $logFolder = $candidate
        break
    }
}

if (-not $logFolder) {
    Write-Warn "Nem talalhato LOG almappa: $targetClean"
    Write-Tip  "Keresett nevek: $($logCandidates -join ', ')"
    Write-Tip  "Ellenorizd, hogy a jobb klikk a megfelelo mappan tortent-e!"
    Write-Host ""
    Read-Host  "  [Enter] a kilepeshez"
    exit 0
}

Write-OK "LOG mappa: $logFolder"
Write-Host ""

# ── 4. SendReport.ps1 meghívása a talált LOG mappával ────────────
Write-Step "SendReport.ps1 indul..."
Write-Host ""

# Splatting: szokos utvonalaknal biztonságos, nem darabolja fel a parametereket
$sendParams = @{
    ConfigPath = $configPath
    LogFolder  = $logFolder
}
& $sendScript @sendParams

# ── 5. Várakozás bezárás előtt ────────────────────────────────────
Write-Host ""
Read-Host "  [Enter] a bezarashoz"
