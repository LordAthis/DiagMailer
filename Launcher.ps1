#Requires -Version 3.0
<#
.SYNOPSIS
    DiagMailer Launcher – Főmenü és belépési pont
.DESCRIPTION
    Automatikusan emeli a jogosultságot, majd menüt jelenít meg:
      1. Jelentés küldése (SendReport.ps1)
      2. Jelszó állapota (ManageCredential.ps1 -Action Query)
      3. Jelszó újrakonfigurálás (ManageCredential.ps1 -Action Update)
      4. Tárolt jelszó törlése (ManageCredential.ps1 -Action Delete)
      0. Kilépés
.PARAMETER ConfigPath
    A config.json elérési útja.
.PARAMETER ForceCredential
    Újra bekéri a jelszót (1-es menüpont közvetlen hívása esetén).
.PARAMETER DeleteLogsAfterSend
    Küldés után törli a LOG fájlokat.
.EXAMPLE
    .\Launcher.ps1
    .\Launcher.ps1 -ForceCredential
    .\Launcher.ps1 -ConfigPath "D:\sajat\config.json"
#>

param(
    [string]$ConfigPath        = "$PSScriptRoot\config.json",
    [switch]$ForceCredential,
    [switch]$DeleteLogsAfterSend
)

# ===========================================================
#  AUTOMATIKUS JOGOSULTSÁG EMELÉS
#  Mindig elvégzi, mielőtt bármi más futna.
# ===========================================================

$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin          = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host ""
    Write-Host "  [Launcher] Emelt jogosultsag szukseges - ujrainditom..." -ForegroundColor Yellow
    # Tombot hasznalunk - egyszeru string szokoznél rosszul darabolja az utvonalakat!
    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath, "-ConfigPath", $ConfigPath)
    if ($ForceCredential)     { $argList += "-ForceCredential" }
    if ($DeleteLogsAfterSend) { $argList += "-DeleteLogsAfterSend" }
    Start-Process powershell.exe -ArgumentList $argList -Verb RunAs
    exit 0
}

# ===========================================================
#  BEÁLLÍTÁSOK
# ===========================================================

$script:Version        = "3.4.0"
$SendReportScript      = Join-Path $PSScriptRoot "SendReport.ps1"
$ManageCredScript      = Join-Path $PSScriptRoot "ManageCredential.ps1"
$ContextMenuScript     = Join-Path $PSScriptRoot "ContextMenuInstaller.ps1"
$ConfigScript          = Join-Path $PSScriptRoot "Config.ps1"
$ConfigPath            = Join-Path $PSScriptRoot "config.json"
$ConfigExample         = Join-Path $PSScriptRoot "config.json.example"

function Write-Sep { Write-Host "  ------------------------------------------" -ForegroundColor DarkGray }
function Write-Fail { param([string]$Msg) Write-Host "  XX $Msg" -ForegroundColor Red }
function Write-Tip  { param([string]$Msg) Write-Host "     $Msg" -ForegroundColor DarkGray }
function Write-OK   { param([string]$Msg) Write-Host "  OK $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "  !! $Msg" -ForegroundColor Yellow }

# ===========================================================
#  FÁJLOK MEGLÉTÉNEK ELLENŐRZÉSE
# ===========================================================

$missing = @()
if (-not (Test-Path $SendReportScript))  { $missing += "SendReport.ps1" }
if (-not (Test-Path $ManageCredScript))  { $missing += "ManageCredential.ps1" }

if ($missing.Count -gt 0) {
    Write-Host ""
    foreach ($m in $missing) {
        Write-Fail "$m nem talalhato! (Vart hely: $PSScriptRoot)"
    }
    Write-Tip "A DiagMailer telepitese hianyos lehet."
    Write-Host ""
    exit 1
}

# ===========================================================
#  CONFIG.JSON ELLENŐRZÉSE - hiány esetén Config.ps1 felajánlása
# ===========================================================

if (-not (Test-Path $ConfigPath)) {
    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Yellow
    Write-Host "  |   DiagMailer - Konfig nem talalhato!    |" -ForegroundColor Yellow
    Write-Host "  +==========================================+" -ForegroundColor Yellow
    Write-Host ""
    Write-Warn "config.json nem talalhato: $ConfigPath"

    if (Test-Path $ConfigExample) {
        Write-OK "config.json.example megtalalhato - automatikus beallitas elerheto"
        Write-Host ""
        $doSetup = Read-Host "  Futtassuk az automatikus beallito varazslot? [I/N]"
        if ($doSetup -match "^[Ii]") {
            if (Test-Path $ConfigScript) {
                & $ConfigScript -ConfigPath $ConfigPath
                # Config.ps1 Launcher-t is indit sikeres vegzodes utan - itt befejezzuk
                exit 0
            }
            else {
                Write-Fail "Config.ps1 nem talalhato: $ConfigScript"
                Write-Tip  "Masold at a config.json.example fajlt config.json-ra es toltsd ki!"
                exit 1
            }
        }
        else {
            Write-Tip "Masold at kezzel: config.json.example -> config.json"
            Write-Tip "Toltsd ki az email- es SMTP-adatokat, majd futtasd ujra."
            exit 0
        }
    }
    else {
        Write-Fail "config.json.example sem talalhato!"
        Write-Tip  "Toltsd le ujra a DiagMailer csomagot."
        exit 1
    }
}

# ===========================================================
#  MENÜ MEGJELENÍTŐ FÜGGVÉNY
# ===========================================================

function Show-Menu {
    Clear-Host
    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   DiagMailer v$($script:Version)  -  Fomenu           |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""

    # Jelszó állapot gyors kijelzés a menüben
    if ($null -ne $Global:DiagMailerCred) {
        Write-Host "  Jelszo: munkamenet-memoriabol ($($Global:DiagMailerCred.UserName))" -ForegroundColor Green
    }
    elseif (Test-Path "$env:LOCALAPPDATA\DiagMailer\credential.xml") {
        Write-Host "  Jelszo: tartosan mentett adat elerheto" -ForegroundColor Green
    }
    else {
        Write-Host "  Jelszo: nincs mentett adat - elso kuldesznel keri" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Sep
    Write-Host "  [1]  Jelentes kuldese" -ForegroundColor White
    Write-Sep
    Write-Host "  [2]  Jelszo allapota (lekerdezese)" -ForegroundColor White
    Write-Host "  [3]  Jelszo ujrakonfiguralas" -ForegroundColor White
    Write-Host "  [4]  Tarolt jelszo torlese" -ForegroundColor White
    Write-Sep
    Write-Host "  [5]  Jobb klikk menu telepitese / eltavolitasa" -ForegroundColor White
    Write-Sep
    Write-Host "  [0]  Kilepes" -ForegroundColor DarkGray
    Write-Host ""
}

# ===========================================================
#  ENTER VÁRAKOZÁS (menüpontonként visszatérés előtt)
# ===========================================================

function Wait-Enter {
    Write-Host ""
    Write-Host "  [Enter] a menuhoz valo visszatereshez..." -ForegroundColor DarkGray
    $null = Read-Host
}

# ===========================================================
#  FŐMENÜ CIKLUS
# ===========================================================

do {
    Show-Menu
    $choice = Read-Host "  Valasztas"

    switch ($choice) {

        "1" {
            # Jelentés küldése
            $args1 = @{ ConfigPath = $ConfigPath }
            if ($ForceCredential)     { $args1.ForceCredential     = $true }
            if ($DeleteLogsAfterSend) { $args1.DeleteLogsAfterSend = $true }
            & $SendReportScript @args1
            Wait-Enter
        }

        "2" {
            # Jelszó állapota
            & $ManageCredScript -Action Query
            Wait-Enter
        }

        "3" {
            # Jelszó újrakonfigurálás
            & $ManageCredScript -Action Update
            Wait-Enter
        }

        "4" {
            # Tárolt jelszó törlése - megerősítés kérdése
            Write-Host ""
            Write-Host "  !! Biztosan torlod a tarolt jelszo adatait?" -ForegroundColor Yellow
            $confirm = Read-Host "  [I = Igen, torles | N = Nem, vissza a menuhoz]"
            if ($confirm -match "^[Ii]") {
                & $ManageCredScript -Action Delete
            }
            else {
                Write-Host "  Torles megszakitva." -ForegroundColor DarkGray
            }
            Wait-Enter
        }

        "5" {
            # Jobb klikk kontextusmenu telepito
            if (Test-Path $ContextMenuScript) {
                & $ContextMenuScript -Action Menu
            } else {
                Write-Host ""
                Write-Host "  !! ContextMenuInstaller.ps1 nem talalhato!" -ForegroundColor Yellow
                Write-Host "     Vart hely: $ContextMenuScript" -ForegroundColor DarkGray
            }
            Wait-Enter
        }

        "0" {
            Write-Host ""
            Write-Host "  Viszlat!" -ForegroundColor Cyan
            Write-Host ""
        }

        default {
            Write-Host ""
            Write-Host "  Ervenytelen valasztas. Probalj 0-4 kozott!" -ForegroundColor Yellow
            Start-Sleep -Seconds 1
        }
    }

} while ($choice -ne "0")

exit 0
