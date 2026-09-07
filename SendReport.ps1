#Requires -Version 3.3
<#
.SYNOPSIS
    DiagMailer - LOG jelentés küldő
.DESCRIPTION
    Összegyűjti a LOG mappa tartalmát, ZIP-be csomagolja és elküldi emailben.
    Első futáskor bekéri az SMTP jelszót, opcionálisan tartósan elmenti (DPAPI).
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
#>

param(
    [string]$ConfigPath        = "$PSScriptRoot\config.json",
    [string]$LogFolder         = "",
    [switch]$ForceCredential,
    [switch]$DeleteLogsAfterSend
)

# ===========================================================
#  AUTOMATIKUS JOGOSULTSÁG EMELÉS
#  Ha nem fut rendszergazdaként, újraindítja emelt módban.
#  A param() blokk után kell lennie, hogy a paraméterek elérhetők legyenek.
# ===========================================================

$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin          = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host ""
    Write-Host "  [DiagMailer] Emelt jogosultsag szukseges - ujrainditom..." -ForegroundColor Yellow
    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -ConfigPath `"$ConfigPath`""
    if ($ForceCredential)     { $argList += " -ForceCredential" }
    if ($DeleteLogsAfterSend) { $argList += " -DeleteLogsAfterSend" }
    Start-Process powershell.exe -ArgumentList $argList -Verb RunAs
    exit 0
}

# ===========================================================
#  GLOBÁLIS BEÁLLÍTÁSOK
# ===========================================================

$ErrorActionPreference = "Stop"
$script:Version        = "1.0.0"
$script:CredStorePath  = "$env:LOCALAPPDATA\DiagMailer\credential.xml"
$script:ZipPath        = $null

# ===========================================================
#  MEGJELENÍTÉSI SEGÉDFÜGGVÉNYEK
#  (ékezet nélkül a kimeneten, hogy minden kódlapon helyes legyen)
# ===========================================================

function Write-Header {
    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   DiagMailer v$($script:Version)  -  LOG Kuldo        |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step { param([string]$Msg) Write-Host "  -> $Msg" -ForegroundColor White }
function Write-OK   { param([string]$Msg) Write-Host "  OK $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "  !! $Msg" -ForegroundColor Yellow }
function Write-Fail { param([string]$Msg) Write-Host "  XX $Msg" -ForegroundColor Red }
function Write-Tip  { param([string]$Msg) Write-Host "     $Msg" -ForegroundColor DarkGray }
function Write-Sep  { Write-Host "  ------------------------------------------" -ForegroundColor DarkGray }

# ===========================================================
#  KONFIGURÁCIÓ BETÖLTÉSE
# ===========================================================

function Get-DiagConfig {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        Write-Fail "config.json nem talalhato: $Path"
        Write-Tip  "Masold at: config.json.example  ->  config.json"
        Write-Tip  "Toltsd ki az email- es SMTP-adatokat, majd futtasd ujra."
        exit 1
    }

    try {
        $cfg = Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Write-Fail "config.json beolvasasi hiba: $($_.Exception.Message)"
        exit 1
    }

    # Kötelező mezők ellenőrzése
    foreach ($field in @("reportEmail","fromEmail","smtpServer","smtpPort","logFolder")) {
        if ([string]::IsNullOrWhiteSpace($cfg.$field)) {
            Write-Fail "Hianyzik a config.json mezobol: '$field'"
            exit 1
        }
    }

    # Alapértelmezések kitöltése, ha hiányoznak
    if ($null -eq $cfg.fromName) { $cfg | Add-Member -Force NotePropertyName fromName -NotePropertyValue "DiagMailer" }
    if ($null -eq $cfg.subject)  { $cfg | Add-Member -Force NotePropertyName subject  -NotePropertyValue "DiagMailer Jelentes" }
    if ($null -eq $cfg.useSSL)   { $cfg | Add-Member -Force NotePropertyName useSSL   -NotePropertyValue $true }

    return $cfg
}

# ===========================================================
#  HITELESÍTŐ ADAT KEZELÉS
#  Sorrend: munkamenet memória → DPAPI tartós tár → interaktív bekérés
# ===========================================================

function Get-DiagCredential {
    param([switch]$ForcePrompt)

    # 1. Munkamenet memória (ugyanaz a PowerShell folyamat)
    if ((-not $ForcePrompt) -and ($null -ne $Global:DiagMailerCred)) {
        Write-OK "Jelszo: munkamenet memoriabol betoltve"
        return $Global:DiagMailerCred
    }

    # 2. Tartósan mentett hitelesítő (DPAPI - csak ez a gép + felhasználó olvashatja)
    if ((-not $ForcePrompt) -and (Test-Path $script:CredStorePath)) {
        try {
            $stored = Import-Clixml -Path $script:CredStorePath
            $Global:DiagMailerCred = $stored
            Write-OK "Jelszo: tartosan mentettbol betoltve"
            Write-Tip  "Hely: $script:CredStorePath"
            return $stored
        }
        catch {
            # Sérült vagy érvénytelen mentett adat - törlés és újrakérés
            Write-Warn "Tarolt hitelesito ervenytelen - ujra szukseges"
            Remove-Item $script:CredStorePath -Force -ErrorAction SilentlyContinue
        }
    }

    # 3. Interaktív bekérés
    Write-Host ""
    Write-Host "  +--------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  |  Email hitelesites szukseges               |" -ForegroundColor Cyan
    Write-Host "  |  Add meg a kuldo fiok adatait (fromEmail)  |" -ForegroundColor Cyan
    Write-Host "  |  Gmail eseten App-jelszo kell, nem a rendes|" -ForegroundColor Cyan
    Write-Host "  +--------------------------------------------+" -ForegroundColor Cyan
    Write-Host ""

    $cred = Get-Credential -Message "SMTP hitelesites - kuldo fiok adatai (fromEmail a configbol)"
    if ($null -eq $cred) {
        Write-Fail "Hitelesites megszakitva."
        exit 1
    }

    # Munkamenetbe mentés
    $Global:DiagMailerCred = $cred
    Write-OK "Jelszo elmentve a munkamenet idejere (PS ablak bezarasaig)"

    # Tartós mentés kérdése
    Write-Host ""
    Write-Host "  Tartosan mentsem a jelszo erre a gepre?" -ForegroundColor Yellow
    Write-Tip  "DPAPI titkositas: csak ez a Windows-felhasznalo olvashatja vissza"
    Write-Tip  "Allando ugyfel gepen ajanlott - nem kell mindig beirni"
    Write-Host ""
    $save = Read-Host "  [I = Igen, marad ujrainditas utan is | N = Nem, csak most]"

    if ($save -match "^[Ii]") {
        $dir = Split-Path $script:CredStorePath -Parent
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        try {
            $cred | Export-Clixml -Path $script:CredStorePath -Force
            Write-OK "Jelszo tartosan elmentve: $script:CredStorePath"
        }
        catch {
            Write-Warn "Tartos mentes sikertelen: $($_.Exception.Message)"
            Write-Tip  "A munkamenet memoriban marad, ujrainditas utan ujra ker"
        }
    }
    else {
        Write-Step "Jelszo csak a PowerShell ablak bezarasaig el"
    }

    return $cred
}

# ===========================================================
#  LOG FÁJLOK ÖSSZEGYŰJTÉSE
# ===========================================================

function Get-LogInfo {
    param([string]$LogFolder)

    # Relatív útvonal feloldása (pl. ..\\LOG a script helyéhez képest)
    if ([System.IO.Path]::IsPathRooted($LogFolder)) {
        $resolved = $LogFolder
    }
    else {
        $resolved = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot $LogFolder))
    }

    Write-Step "LOG mappa: $resolved"

    if (-not (Test-Path $resolved)) {
        Write-Warn "LOG mappa nem letezik: $resolved"
        Write-Tip  "Ellenorizd a logFolder beallitast a config.json-ban"
        return $null
    }

    $files = Get-ChildItem -Path $resolved -File -Recurse -ErrorAction SilentlyContinue

    if (($null -eq $files) -or ($files.Count -eq 0)) {
        Write-Warn "A LOG mappa ures - nincs mit kuldeni"
        return $null
    }

    $totalBytes = ($files | Measure-Object -Property Length -Sum).Sum
    $sizeMB     = [Math]::Round($totalBytes / 1MB, 2)
    Write-OK "$($files.Count) fajl talaltva ($sizeMB MB)"

    return @{
        Path   = $resolved
        Files  = $files
        SizeMB = $sizeMB
    }
}

# ===========================================================
#  ZIP TÖMÖRÍTÉS
# ===========================================================

function New-LogZip {
    param([string]$LogPath)

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $hostname  = $env:COMPUTERNAME
    $zipName   = "DiagMailer_${hostname}_${timestamp}.zip"
    $zipPath   = Join-Path $env:TEMP $zipName

    Write-Step "Tomorites: $zipName"

    try {
        Compress-Archive -Path "$LogPath\*" -DestinationPath $zipPath -Force
        $zipKB = [Math]::Round((Get-Item $zipPath).Length / 1KB, 1)
        Write-OK "ZIP kesz: $zipKB KB"
        return $zipPath
    }
    catch {
        Write-Fail "ZIP tomorites sikertelen: $($_.Exception.Message)"
        exit 1
    }
}

# ===========================================================
#  EMAIL KÜLDÉS
# ===========================================================

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

    # Fájllista szöveg (ékezet nélkül a kódlap-biztonság miatt)
    $fileLines = $LogInfo.Files | ForEach-Object {
        "  - $($_.Name)  ($([Math]::Round($_.Length/1KB,1)) KB)"
    }

    # Email törzs összerakása string tömbbel (here-string kerülendő indentálási hibák miatt)
    $bodyParts = @(
        "DiagMailer Automatikus Jelentes",
        "================================",
        "Gepnev     : $hostname",
        "Felhasznalo: $user",
        "Idopont    : $timestamp",
        "LOG fajlok : $($LogInfo.Files.Count) db  ($($LogInfo.SizeMB) MB)",
        "ZIP melleklet: $(Split-Path $ZipPath -Leaf)",
        "",
        "Fajllista:",
        ($fileLines -join "`r`n"),
        "",
        "---",
        "DiagMailer v$($script:Version) - Automatikus kuldes"
    )
    $body = $bodyParts -join "`r`n"

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

    if ($Config.useSSL -eq $true) {
        $mailParams.UseSsl = $true
    }

    Write-Step "Kuldes -> $($Config.reportEmail)"
    Write-Tip  "SMTP: $($Config.smtpServer):$($Config.smtpPort)  |  SSL: $($Config.useSSL)"

    try {
        Send-MailMessage @mailParams
        Write-OK "Email sikeresen elkuldve!"
    }
    catch {
        Write-Fail "Kuldes sikertelen: $($_.Exception.Message)"
        Write-Host ""
        Write-Tip "Hibaelaritas:"
        Write-Tip "  Gmail      -> App-jelszo kell, nem a Google-fiok jelszava!"
        Write-Tip "               https://myaccount.google.com/apppasswords"
        Write-Tip "  Office365  -> App-jelszo vagy OAuth szukseges"
        Write-Tip "  Port hiba  -> 587 (TLS/STARTTLS) vagy 465 (SSL)"
        Write-Tip "  Jelszo hiba -> Futtasd: .\SendReport.ps1 -ForceCredential"
        throw
    }
}

# ===========================================================
#  FŐPROGRAM
# ===========================================================

try {
    Write-Header
    Write-Step "Rendszergazda mod: OK"

    # 1. Konfiguráció betöltése
    Write-Host ""
    Write-Step "Konfiguracio: $ConfigPath"
    $cfg = Get-DiagConfig -Path $ConfigPath
    Write-OK "Cel email: $($cfg.reportEmail)"

    # Ha -LogFolder parametert kapunk, az felulirja a config.json logFolder mezojet
    # (ContextMenuSend.ps1 adja at a jobb klikkelt mappa LOG almappajat)
    if (-not [string]::IsNullOrWhiteSpace($LogFolder)) {
        $cfg | Add-Member -Force NotePropertyName logFolder -NotePropertyValue $LogFolder
        Write-Step "LOG mappa (parameter altal felulirva): $LogFolder"
    }

    Write-Sep

    # 2. Hitelesítő adat
    Write-Host ""
    $cred = Get-DiagCredential -ForcePrompt:$ForceCredential
    Write-Sep

    # 3. LOG fájlok keresése
    Write-Host ""
    $logInfo = Get-LogInfo -LogFolder $cfg.logFolder

    if ($null -eq $logInfo) {
        Write-Host ""
        Write-Warn "Nincs kuldenivalo LOG fajl. Kilepes."
        exit 0
    }
    Write-Sep

    # 4. ZIP tömörítés
    Write-Host ""
    $script:ZipPath = New-LogZip -LogPath $logInfo.Path
    Write-Sep

    # 5. Email küldés
    Write-Host ""
    Send-DiagReport -Config $cfg -Credential $cred -ZipPath $script:ZipPath -LogInfo $logInfo

    # 6. Opcionális LOG törlés küldés után
    if ($DeleteLogsAfterSend) {
        Write-Sep
        Write-Step "LOG fajlok torlese (-DeleteLogsAfterSend aktiv)..."
        Get-ChildItem -Path $logInfo.Path -File -Recurse | Remove-Item -Force
        Write-OK "LOG mappa kuuritve"
    }

    Write-Host ""
    Write-Host "  ==========================================" -ForegroundColor Green
    Write-Host "  Kesz! Jelentes elkuldve: $($cfg.reportEmail)" -ForegroundColor Green
    Write-Host "  ==========================================" -ForegroundColor Green
    Write-Host ""

}
catch {
    Write-Host ""
    Write-Fail "HIBA: $($_.Exception.Message)"
    Write-Host ""
    exit 1
}
finally {
    # Ideiglenes ZIP mindig törlődik, akár sikerült a küldés, akár nem
    if (($null -ne $script:ZipPath) -and (Test-Path $script:ZipPath)) {
        Remove-Item $script:ZipPath -Force -ErrorAction SilentlyContinue
        Write-Tip "Ideiglenes ZIP torolve"
    }
}
