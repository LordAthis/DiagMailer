#Requires -Version 3.0
<#
.SYNOPSIS
    DiagMailer - Jobb klikk kontextusmenü hívó script
.DESCRIPTION
    Ez a fájl kerül C:\Windows\Scripts\DiagMailerSend.ps1 helyre a telepítő által.
    A Windows Explorer jobb klikk menüjéből hívódik meg automatikusan.

    A célmappa meghatározása: $PWD (munkakönyvtár), amit a registry parancs
    Set-Location segítségével állít be a futtatás előtt. Így teljesen elkerüljük
    a %1/%V paraméter-átadás szóköz-problémáját!

    Registry parancs formátuma (ContextMenuInstaller.ps1 írja):
      powershell.exe -Command "Set-Location '%1'; & 'C:\Windows\Scripts\DiagMailerSend.ps1'"

    UAC emeli a jogosultságot, a WorkingDirectory átadással a könyvtár megmarad.
.EXAMPLE
    (Közvetlenül általában nem hívják, a jobb klikk menü indítja)
    .\ContextMenuSend.ps1
#>

param()

# ===========================================================
#  AUTOMATIKUS JOGOSULTSÁG EMELÉS
#  WorkingDirectory atadasa: emeles utan is jo mappaban indul!
# ===========================================================

$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin          = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    $currentDir = (Get-Location).Path
    $argList    = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath)
    Start-Process powershell.exe -ArgumentList $argList -Verb RunAs -WorkingDirectory $currentDir
    exit 0
}

# ===========================================================
#  BEÁLLÍTÁSOK
# ===========================================================
 
$script:Version        = "3.3.3"

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

# ── 1. Célmappa: $PWD-ből olvassuk (Set-Location-nal lett beállítva) ─
$targetDir = (Get-Location).Path
Write-Step "Cel mappa: $targetDir"

if ([string]::IsNullOrWhiteSpace($targetDir) -or -not (Test-Path $targetDir)) {
    Write-Fail "A cel mappa nem erheto el: $targetDir"
    Write-Tip  "Probald meg kozvetlenul a DiagMailer mappajara jobb klikkelni"
    Write-Host ""
    Read-Host  "  [Enter] a kilepeshez"
    exit 1
}

# ── 2. DiagMailer telepítési út registry-ből ─────────────────────────
$regPath = "HKCU:\Software\DiagMailer"

if (-not (Test-Path $regPath)) {
    Write-Fail "DiagMailer nincs telepitve a rendszerbe!"
    Write-Tip  "Futtasd a ContextMenuInstaller.ps1-et a telepiteshez."
    Write-Host ""
    Read-Host  "  [Enter] a kilepeshez"
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

# ── 3. LOG almappa keresése a célmappában ─────────────────────────────
$logCandidates = @("LOG", "log", "Log", "Logs", "logs", "LOGS")
$logFolder     = $null

foreach ($name in $logCandidates) {
    $candidate = Join-Path $targetDir $name
    if (Test-Path $candidate -PathType Container) {
        $logFolder = $candidate
        break
    }
}

if (-not $logFolder) {
    Write-Warn "Nem talalhato LOG almappa: $targetDir"
    Write-Tip  "Keresett nevek: $($logCandidates -join ', ')"
    Write-Tip  "Jobb klikkeld a projekted gyokermappajat, ahol a LOG mappa van!"
    Write-Host ""
    Read-Host  "  [Enter] a kilepeshez"
    exit 0
}

Write-OK "LOG mappa: $logFolder"
Write-Host ""

# ── 4. SendReport.ps1 meghívása splatting-gal ────────────────────────
Write-Step "SendReport.ps1 indul..."
Write-Host ""

$sendParams = @{
    ConfigPath = $configPath
    LogFolder  = $logFolder
}
& $sendScript @sendParams

# ── 5. Várakozás bezárás előtt ─────────────────────────────────────────
Write-Host ""
Read-Host "  [Enter] a bezarashoz"
