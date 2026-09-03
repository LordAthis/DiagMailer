#Requires -Version 3.0
<#
.SYNOPSIS
    DiagMailer – Automatikus LOG jelentés küldő

.DESCRIPTION
    Összegyűjti a LOG mappa tartalmát, ZIP-be csomagolja,
    és elküldi a config.json-ban megadott email címre.

    Jelszó kezelési sorrend:
      1. Munkamenet memória ($Global:DiagMailerCred)
      2. DPAPI titkosított tartós tárolás (%LOCALAPPDATA%\DiagMailer\)
      3. Interaktív bekérés + opcionális mentés

.PARAMETER ConfigPath
    A config.json elérési útja. Alapértelmezett: script melletti mappa.

.PARAMETER ForceCredential
    Figyelmen kívül hagyja a tárolt jelszót, újra bekéri.

.PARAMETER DeleteLogsAfterSend
    Küldés után törli a LOG fájlokat.

.EXAMPLE
    .\SendReport.ps1
    .\SendReport.ps1 -ForceCredential
    .\SendReport.ps1 -ConfigPath "D:\sajat\config.json" -DeleteLogsAfterSend

.NOTES
    Verzió: 1.0.0
    Nyílt forráskódú – GitHub: https://github.com/GITHUB_FELHASZNALO/DiagMailer
    config.json SOHA ne kerüljön a repóba! (.gitignore-ba vedd fel!)
#>

param(
    [string]$ConfigPath       = "$PSScriptRoot\config.json",
    [switch]$ForceCredential,
    [switch]$DeleteLogsAfterSend
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:Version       = "1.0.0"
$script:CredStorePath = "$env:LOCALAPPDATA\DiagMailer\credential.xml"
$script:ZipPath       = $null   # finally-blokkban törléshez

# ═══════════════════════════════════════════════════════════════════
#  MEGJELENÍTÉS
# ═══════════════════════════════════════════════════════════════════

function Write-Header {
    Clear-Host
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║   DiagMailer v$($script:Version)  –  LOG Küldő      ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step  { param([string]$Msg) Write-Host "  → $Msg" -ForegroundColor White }
function Write-OK    { param([string]$Msg) Write-Host "  ✓ $Msg" -ForegroundColor Green }
function Write-Warn  { param([string]$Msg) Write-Host "  ⚠ $Msg" -ForegroundColor Yellow }
function Write-Fail  { param([string]$Msg) Write-Host "  ✗ $Msg" -ForegroundColor Red }
function Write-Tip   { param([string]$Msg) Write-Host "  · $Msg" -ForegroundColor DarkGray }
function Write-Sep   {
    Write-Host "  ──────────────────────────────────────────" -ForegroundColor DarkGray
}

# ═══════════════════════════════════════════════════════════════════
#  JOGOSULTSÁG ELLENŐRZÉS
# ═══════════════════════════════════════════════════════════════════

function Test-IsAdmin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-SelfElevate {
    Write-Warn "Rendszergazdai jogosultság szükséges – újraindítás emelt módban..."
    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -ConfigPath `"$ConfigPath`""
    if ($ForceCredential)    { $argList += " -ForceCredential" }
    if ($DeleteLogsAfterSend){ $argList += " -DeleteLogsAfterSend" }
    Start-Process powershell.exe -ArgumentList $argList -Verb RunAs
    exit 0
}

# ═══════════════════════════════════════════════════════════════════
#  KONFIGURÁCIÓ
# ═══════════════════════════════════════════════════════════════════

function Get-DiagConfig {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        Write-Fail "config.json nem találhato: $Path"
        Write-Tip  "Másold át: config.json.example  →  config.json"
        Write-Tip  "Töltsd ki az email- és SMTP-adatokat, majd futtasd újra."
        exit 1
    }

    try {
        $cfg = Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Write-Fail "config.json beolvasási hiba: $($_.Exception.Message)"
        exit 1
    }

    # Kötelező mezők
    foreach ($field in @("reportEmail","fromEmail","smtpServer","smtpPort","logFolder")) {
        if ([string]::IsNullOrWhiteSpace($cfg.$field)) {
            Write-Fail "Hiányzó vagy üres mező a config.json-ban: '$field'"
            exit 1
        }
    }

    # Alapértelmezések, ha nincsenek megadva
    $defaults = @{
        fromName     = "DiagMailer"
        subject      = "DiagMailer Jelentés"
        useSSL       = $true
        requireAdmin = $false
    }
    foreach ($key in $defaults.Keys) {
        if ($null -eq $cfg.$key) {
            $cfg | Add-Member -Force -NotePropertyName $key -NotePropertyValue $defaults[$key]
        }
    }

    return $cfg
}

# ═══════════════════════════════════════════════════════════════════
#  HITELESÍTŐ ADAT KEZELÉS
# ═══════════════════════════════════════════════════════════════════

function Get-DiagCredential {
    param([switch]$ForcePrompt)

    # ── 1. Munkamenet (RAM, ugyanaz a folyamat/session) ──────────────
    if (-not $ForcePrompt -and $Global:DiagMailerCred) {
        Write-OK "Jelszó: munkamenet-memóriából betöltve"
        return $Global:DiagMailerCred
    }

    # ── 2. Tartós tárolás (DPAPI – csak ez a gép + felhasználó) ──────
    if (-not $ForcePrompt -and (Test-Path $script:CredStorePath)) {
        try {
            $stored = Import-Clixml -Path $script:CredStorePath
            $Global:DiagMailerCred = $stored
            Write-OK "Jelszó: tartós tárolóból betöltve ($script:CredStorePath)"
            return $stored
        }
        catch {
            Write-Warn "Tárolt hitelesítő sérült vagy érvénytelen – újra szükséges"
            Remove-Item $script:CredStorePath -Force -ErrorAction SilentlyContinue
        }
    }

    # ── 3. Interaktív bekérés ─────────────────────────────────────────
    Write-Host ""
    Write-Host "  ┌─────────────────────────────────────────────┐" -ForegroundColor Cyan
    Write-Host "  │   Email hitelesítés szükséges                │" -ForegroundColor Cyan
    Write-Host "  │   Adj meg egy SMTP-hozzáférésű email fiókot  │" -ForegroundColor Cyan
    Write-Host "  │   (Gmail: App-jelszó kell, nem a rendes!)    │" -ForegroundColor Cyan
    Write-Host "  └─────────────────────────────────────────────┘" -ForegroundColor Cyan
    Write-Host ""

    $cred = Get-Credential -Message "SMTP hitelesítés – add meg a küldő fiók adatait"
    if (-not $cred) {
        Write-Fail "Hitelesítés megszakítva."
        exit 1
    }

    # Munkamenetbe
    $Global:DiagMailerCred = $cred
    Write-OK "Jelszó elmentve a munkamenet idejére (PS ablak bezárásáig)"

    # ── Tartós mentés kérdése ─────────────────────────────────────────
    Write-Host ""
    Write-Host "  Tartósan mentsem a jelszót erre a gépre?" -ForegroundColor Yellow
    Write-Tip  "DPAPI titkosítás: csak ez a Windows-felhasználó olvashatja vissza"
    Write-Tip  "Állandó ügyfél gépen hasznos – nem kell mindig beírni"
    Write-Host ""
    $save = Read-Host "  [I = Igen, munkamenet végén is megmarad | N = Nem, csak most]"

    if ($save -match "^[Ii]") {
        $dir = Split-Path $script:CredStorePath -Parent
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        try {
            $cred | Export-Clixml -Path $script:CredStorePath -Force
            Write-OK "Jelszó tartósan elmentve: $script:CredStorePath"
        }
        catch {
            Write-Warn "Tartós mentés sikertelen: $($_.Exception.Message)"
            Write-Tip  "A munkamenet memóriában marad, de újraindítás után újra kéri"
        }
    }
    else {
        Write-Step "Jelszó csak a PowerShell ablak bezárásáig él"
    }

    return $cred
}

# Tárolt jelszó törlése (pl. jelszócsere után)
function Remove-DiagCredential {
    $Global:DiagMailerCred = $null
    if (Test-Path $script:CredStorePath) {
        Remove-Item $script:CredStorePath -Force
        Write-OK "Tárolt jelszó törölve: $script:CredStorePath"
    }
    else {
        Write-Tip "Nem volt tartósan tárolt jelszó"
    }
}

# ═══════════════════════════════════════════════════════════════════
#  LOG FÁJLOK ÖSSZEGYŰJTÉSE
# ═══════════════════════════════════════════════════════════════════

function Get-LogInfo {
    param([string]$LogFolder)

    # Relatív út feloldása: PSScriptRoot-hoz képest (..\\LOG = egy szinttel feljebb)
    $resolved = if ([System.IO.Path]::IsPathRooted($LogFolder)) {
        $LogFolder
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot $LogFolder))
    }

    Write-Step "LOG mappa: $resolved"

    if (-not (Test-Path $resolved)) {
        Write-Warn "LOG mappa nem létezik: $resolved"
        return $null
    }

    $files = Get-ChildItem -Path $resolved -File -Recurse -ErrorAction SilentlyContinue

    if (-not $files -or $files.Count -eq 0) {
        Write-Warn "A LOG mappa üres – nincs mit küldeni"
        return $null
    }

    $totalBytes = ($files | Measure-Object -Property Length -Sum).Sum
    $sizeMB     = [Math]::Round($totalBytes / 1MB, 2)

    Write-OK "$($files.Count) fájl találva ($sizeMB MB)"

    return @{
        Path   = $resolved
        Files  = $files
        SizeMB = $sizeMB
    }
}

# ═══════════════════════════════════════════════════════════════════
#  ZIP TÖMÖRÍTÉS
# ═══════════════════════════════════════════════════════════════════

function New-LogZip {
    param([string]$LogPath)

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $hostname  = $env:COMPUTERNAME
    $zipName   = "DiagMailer_${hostname}_${timestamp}.zip"
    $zipPath   = Join-Path $env:TEMP $zipName

    Write-Step "Tömörítés: $zipName"

    try {
        Compress-Archive -Path "$LogPath\*" -DestinationPath $zipPath -Force
        $zipKB = [Math]::Round((Get-Item $zipPath).Length / 1KB, 1)
        Write-OK "ZIP kész: $zipKB KB ($zipPath)"
        return $zipPath
    }
    catch {
        Write-Fail "ZIP tömörítés sikertelen: $($_.Exception.Message)"
        exit 1
    }
}

# ═══════════════════════════════════════════════════════════════════
#  EMAIL KÜLDÉS
# ═══════════════════════════════════════════════════════════════════

function Send-DiagReport {
    param(
        [object]$Config,
        [System.Management.Automation.PSCredential]$Credential,
        [string]$ZipPath,
        [hashtable]$LogInfo
    )

    $timestamp = Get-Date -Format "yyyy.MM.dd HH:mm:ss"
    $hostname  = $env:COMPUTERNAME
    $user      = $env:USERNAME
    $subject   = "$($Config.subject) | $hostname | $(Get-Date -Format 'yyyy-MM-dd HH:mm')"

    $fileList = ($LogInfo.Files | ForEach-Object {
        "  - $($_.Name)  ($([Math]::Round($_.Length/1KB,1)) KB)"
    }) -join "`r`n"

    $body = @"
DiagMailer Automatikus Jelentés
================================
Gepnev     : $hostname
Felhasznalo: $user
Idopont    : $timestamp
LOG fajlok : $($LogInfo.Files.Count) db  ($($LogInfo.SizeMB) MB)
ZIP melleklet: $(Split-Path $ZipPath -Leaf)

Fajllista:
$fileList

---
DiagMailer v$($script:Version) - Automatikus kuldes
GitHub: https://github.com/GITHUB_FELHASZNALO/DiagMailer
"@

    $mailParams = @{
        From        = "$($Config.fromName) <$($Config.fromEmail)>"
        To          = $Config.reportEmail
        Subject     = $subject
        Body        = $body
        SmtpServer  = $Config.smtpServer
        Port        = [int]$Config.smtpPort
        Credential  = $Credential
        Attachments = $ZipPath
        Encoding    = [System.Text.Encoding]::UTF8
    }

    if ($Config.useSSL) { $mailParams.UseSsl = $true }

    Write-Step "Küldés → $($Config.reportEmail)"
    Write-Tip  "SMTP: $($Config.smtpServer):$($Config.smtpPort)  |  SSL: $($Config.useSSL)"

    try {
        Send-MailMessage @mailParams
        Write-OK "Email sikeresen elküldve!"
    }
    catch {
        Write-Fail "Küldés sikertelen: $($_.Exception.Message)"
        Write-Host ""
        Write-Tip "Hibaelhárítás:"
        Write-Tip " Gmail     → App-jelszó kell (Google-fiók / Biztonság / 2FA / App jelszavak)"
        Write-Tip " Office365 → Modern auth esetén App jelszó vagy OAuth szükséges"
        Write-Tip " SMTP port → 587 (TLS/STARTTLS) vagy 465 (SSL) – a szolgáltatótól függ"
        Write-Tip " Jelszó    → Futtasd -ForceCredential kapcsolóval az újrébékéréshez"
        throw
    }
}

# ═══════════════════════════════════════════════════════════════════
#  FŐPROGRAM
# ═══════════════════════════════════════════════════════════════════

try {
    Write-Header

    # ── 1. Konfig betöltés ────────────────────────────────────────────
    Write-Step "Konfiguráció: $ConfigPath"
    $cfg = Get-DiagConfig -Path $ConfigPath
    Write-OK "Cél email: $($cfg.reportEmail)"
    Write-Sep

    # ── 2. Admin jogosultság ellenőrzés ──────────────────────────────
    if ($cfg.requireAdmin -and -not (Test-IsAdmin)) {
        Invoke-SelfElevate
    }

    # ── 3. Hitelesítő adat ────────────────────────────────────────────
    Write-Host ""
    $cred = Get-DiagCredential -ForcePrompt:$ForceCredential
    Write-Sep

    # ── 4. LOG fájlok összegyűjtése ───────────────────────────────────
    Write-Host ""
    $logInfo = Get-LogInfo -LogFolder $cfg.logFolder

    if (-not $logInfo) {
        Write-Host ""
        Write-Warn "Nincs küldenivaló LOG fájl. Kilépés."
        exit 0
    }
    Write-Sep

    # ── 5. ZIP tömörítés ─────────────────────────────────────────────
    Write-Host ""
    $script:ZipPath = New-LogZip -LogPath $logInfo.Path
    Write-Sep

    # ── 6. Email küldés ───────────────────────────────────────────────
    Write-Host ""
    Send-DiagReport -Config $cfg -Credential $cred -ZipPath $script:ZipPath -LogInfo $logInfo

    # ── 7. Opcionális LOG törlés ──────────────────────────────────────
    if ($DeleteLogsAfterSend) {
        Write-Sep
        Write-Step "LOG fájlok törlése (-DeleteLogsAfterSend aktív)..."
        Get-ChildItem -Path $logInfo.Path -File -Recurse | Remove-Item -Force
        Write-OK "LOG mappa kiürítve"
    }

    Write-Host ""
    Write-Host "  ══════════════════════════════════════════" -ForegroundColor Green
    Write-Host "   Kész! Jelentés elküldve: $($cfg.reportEmail)" -ForegroundColor Green
    Write-Host "  ══════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""

}
catch {
    Write-Host ""
    Write-Fail "HIBA: $($_.Exception.Message)"
    Write-Host ""
    exit 1
}
finally {
    # Temp ZIP mindig törlődik, sikeresen küldve vagy sem
    if ($script:ZipPath -and (Test-Path $script:ZipPath)) {
        Remove-Item $script:ZipPath -Force -ErrorAction SilentlyContinue
        Write-Tip "Ideiglenes ZIP törölve: $script:ZipPath"
    }
}
