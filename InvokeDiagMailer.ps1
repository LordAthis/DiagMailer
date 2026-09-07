#Requires -Version 3.2
<#
.SYNOPSIS
    DiagMailer integráció – más REPÓ-kba kerülő hívó script

.DESCRIPTION
    Ez a script kerül a többi REPÓ-ba (pl. a menübe beépítve).
    Megkeresi a ../DiagMailer/ mappát, szükség esetén letölti
    GitHub-ról, ellenőrzi a konfigot, majd elindítja a küldést.

    TESTRESZABÁS (mielőtt a repódba teszed):
      1. Írd át a $DiagMailerRepoUrl-t a saját GitHub repo URL-edre
      2. A script helye: a REPÓ gyökerében, vagy scripts/ mappájában

    ELVÁRT MAPPASZERKEZET (mindkét eset működik):

    A) DiagMailer a REPÓ-n belül:
       MegRendeloGep/
       ├── LOG/
       ├── DiagMailer/        ← itt van
       │   └── SendReport.ps1
       └── Invoke-DiagMailer.ps1  ← ez a script

    B) DiagMailer önálló REPÓ a szomszédban:
       Projektek/
       ├── MegRendeloGep/
       │   ├── LOG/
       │   └── scripts/
       │       └── Invoke-DiagMailer.ps1  ← ez a script
       └── DiagMailer/        ← a szomszédban
           └── SendReport.ps1

.PARAMETER ForceCredential
    Újra bekéri az email jelszót.

.PARAMETER DeleteLogsAfterSend
    Küldés után törli a LOG fájlokat.

.PARAMETER DiagMailerRepoUrl
    GitHub clone URL – felülírja a scriptben lévő alapértelmezést.

.EXAMPLE
    .\Invoke-DiagMailer.ps1
    .\Invoke-DiagMailer.ps1 -ForceCredential
    # Menüből hívva:
    & "$PSScriptRoot\Invoke-DiagMailer.ps1" -DeleteLogsAfterSend
#>

param(
    [string]$DiagMailerRepoUrl  = "https://github.com/GITHUB_FELHASZNALO/DiagMailer.git",
    [switch]$ForceCredential,
    [switch]$DeleteLogsAfterSend
)

# ════════════════════════════════════════════════════════════════════
#  ÚTVONALAK – a script helye határozza meg, hol keressük DiagMailert
# ════════════════════════════════════════════════════════════════════

# Egy szinttel feljebb keressük (scripts/ → repo gyökér, vagy repo gyökér → szomszéd mappa)
$ParentDir         = Split-Path $PSScriptRoot -Parent
$DiagMailerRoot    = Join-Path $ParentDir "DiagMailer"

# Ha ez a script MAGA van a DiagMailer mappában, ne önmagát hívja
if ((Split-Path $PSScriptRoot -Leaf) -eq "DiagMailer") {
    $DiagMailerRoot = $PSScriptRoot
}

$SendReportScript  = Join-Path $DiagMailerRoot "SendReport.ps1"
$LauncherScript    = Join-Path $DiagMailerRoot "Launcher.ps1"
$ConfigPath        = Join-Path $DiagMailerRoot "config.json"
$ConfigExample     = Join-Path $DiagMailerRoot "config.json.example"

# ════════════════════════════════════════════════════════════════════
#  SEGÉDFÜGGVÉNYEK
# ════════════════════════════════════════════════════════════════════

function Write-DiagInfo { param([string]$Msg) Write-Host "  [DiagMailer] $Msg" -ForegroundColor Cyan }
function Write-DiagOK   { param([string]$Msg) Write-Host "  [DiagMailer] ✓ $Msg" -ForegroundColor Green }
function Write-DiagWarn { param([string]$Msg) Write-Host "  [DiagMailer] ⚠ $Msg" -ForegroundColor Yellow }
function Write-DiagFail { param([string]$Msg) Write-Host "  [DiagMailer] ✗ $Msg" -ForegroundColor Red }
function Write-DiagTip  { param([string]$Msg) Write-Host "  [DiagMailer]   $Msg" -ForegroundColor DarkGray }

# ════════════════════════════════════════════════════════════════════
#  1. DIAGMAILER LETÖLTÉSE (ha szükséges)
# ════════════════════════════════════════════════════════════════════

Write-Host ""
Write-DiagInfo "Ellenőrzés: $DiagMailerRoot"

if (-not (Test-Path $SendReportScript)) {

    Write-DiagWarn "DiagMailer nem található!"
    Write-DiagTip  "Várt hely: $DiagMailerRoot"
    Write-Host ""

    $install = Read-Host "  [DiagMailer] Letöltöm GitHub-ról most? (I/N)"
    if ($install -notmatch "^[Ii]") {
        Write-DiagInfo "Letöltés kihagyva – kilépés."
        exit 0
    }

    # Git elérhetőség
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitCmd) {
        Write-DiagFail "Git nem elérhető a PATH-ban!"
        Write-DiagTip  "Kézi letöltés: $DiagMailerRepoUrl"
        Write-DiagTip  "Cél mappa legyen: $DiagMailerRoot"
        exit 1
    }

    Write-DiagInfo "git clone → $DiagMailerRepoUrl"
    Write-DiagInfo "Célmappa  → $DiagMailerRoot"
    Write-Host ""

    try {
        git clone $DiagMailerRepoUrl $DiagMailerRoot 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "git clone sikertelen (exitcode: $LASTEXITCODE)"
        }
        Write-DiagOK "DiagMailer sikeresen letöltve!"
    }
    catch {
        Write-DiagFail "Letöltés sikertelen: $($_.Exception.Message)"
        exit 1
    }
}
else {
    Write-DiagOK "DiagMailer megtalálva"
}

# ════════════════════════════════════════════════════════════════════
#  2. KONFIG ELLENŐRZÉS
# ════════════════════════════════════════════════════════════════════

if (-not (Test-Path $ConfigPath)) {

    Write-DiagWarn "config.json hiányzik!"

    if (Test-Path $ConfigExample) {
        Write-DiagInfo "config.json.example megtalálva – másolom..."
        Copy-Item $ConfigExample $ConfigPath -Force
        Write-DiagOK  "config.json létrehozva: $ConfigPath"
        Write-Host ""
        Write-DiagWarn "Töltsd ki a config.json-t (email cím, SMTP stb.), majd futtasd újra!"
        Write-DiagTip  "Kötelező mezők: reportEmail, fromEmail, smtpServer, smtpPort, logFolder"

        $edit = Read-Host "  [DiagMailer] Megnyitom most szerkesztésre? (I/N)"
        if ($edit -match "^[Ii]") {
            Start-Process notepad.exe -ArgumentList $ConfigPath
        }
    }
    else {
        Write-DiagFail "config.json.example sem található – a telepítés hiányos lehet"
        Write-DiagTip  "Hozd létre kézzel: $ConfigPath"
    }

    exit 1
}

Write-DiagOK "config.json OK"

# ════════════════════════════════════════════════════════════════════
#  3. FUTTATÁS
# ════════════════════════════════════════════════════════════════════

# Launcher.ps1 preferált (kezeli az elevációt is), SendReport.ps1 fallback
$scriptToRun = if (Test-Path $LauncherScript) { $LauncherScript } else { $SendReportScript }

Write-DiagInfo "Indítás: $(Split-Path $scriptToRun -Leaf)"
Write-Host ""

$scriptArgs = @{ ConfigPath = $ConfigPath }
if ($ForceCredential)    { $scriptArgs.ForceCredential    = $true }
if ($DeleteLogsAfterSend){ $scriptArgs.DeleteLogsAfterSend = $true }

# Ha Launchert hívjuk, adjuk meg a SkipElevation kapcsolót
# (az elevációt az Invoke-DiagMailer nem kezeli, a Launcher döntse el)
if ($scriptToRun -eq $LauncherScript) {
    # Launcher maga dönt az elevációról a config alapján
}

& $scriptToRun @scriptArgs
exit $LASTEXITCODE
