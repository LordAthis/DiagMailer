#Requires -Version 3.0
<#
.SYNOPSIS
    DiagMailer - LOG jelentes kuldo
.PARAMETER ConfigPath
    A config.json eleresi utja. Alapertelmezett: script melletti mappa.
.PARAMETER ForceCredential
    Ujra bekeri a jelszot, figyelmen kivul hagyja a taroltat.
.PARAMETER DeleteLogsAfterSend
    Kuldes utan torli a LOG fajlokat.
.EXAMPLE
    .\SendReport.ps1
    .\SendReport.ps1 -ForceCredential
    .\SendReport.ps1 -DeleteLogsAfterSend
#>

param(
    [string]$ConfigPath        = "$PSScriptRoot\config.json",
    [switch]$ForceCredential,
    [switch]$DeleteLogsAfterSend
)

$ErrorActionPreference     = "Stop"
$script:Version            = "1.0.0"
$script:CredStorePath      = "$env:LOCALAPPDATA\DiagMailer\credential.xml"
$script:ZipPath            = $null

# ===========================================================
#  MEGJELENITESI SEGITFUGGVENYEK
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
#  ADMIN JOGOSULTSAG
# ===========================================================

function Test-IsAdmin {
    $id  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pri = [Security.Principal.WindowsPrincipal]$id
    return $pri.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-SelfElevate {
    Write-Warn "Rendszergazdai jogosultsag szukseges - ujrainditom..."
    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -ConfigPath `"$ConfigPath`""
    if ($ForceCredential)     { $argList += " -ForceCredential" }
    if ($DeleteLogsAfterSend) { $argList += " -DeleteLogsAfterSend" }
    Start-Process powershell.exe -ArgumentList $argList -Verb RunAs
    exit 0
}

# ===========================================================
#  KONFIGURACIO
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

    foreach ($field in @("reportEmail","fromEmail","smtpServer","smtpPort","logFolder")) {
        if ([string]::IsNullOrWhiteSpace($cfg.$field)) {
            Write-Fail "Hianyzik a config.json mezobol: '$field'"
            exit 1
        }
    }

    if ($null -eq $cfg.fromName)     { $cfg | Add-Member -Force NotePropertyName fromName     -NotePropertyValue "DiagMailer" }
    if ($null -eq $cfg.subject)      { $cfg | Add-Member -Force NotePropertyName subject      -NotePropertyValue "DiagMailer Jelentes" }
    if ($null -eq $cfg.useSSL)       { $cfg | Add-Member -Force NotePropertyName useSSL       -NotePropertyValue $true }
    if ($null -eq $cfg.requireAdmin) { $cfg | Add-Member -Force NotePropertyName requireAdmin -NotePropertyValue $false }

    return $cfg
}

# ===========================================================
#  HITELESITO ADAT KEZELES
# ===========================================================

function Get-DiagCredential {
    param([switch]$ForcePrompt)

    # 1. Munkamenet memoria
    if ((-not $ForcePrompt) -and ($null -ne $Global:DiagMailerCred)) {
        Write-OK "Jelszó: munkamenet-memoriabol betoltve"
        return $Global:DiagMailerCred
    }

    # 2. Tartosan mentett (DPAPI)
    if ((-not $ForcePrompt) -and (Test-Path $script:CredStorePath)) {
        try {
            $stored = Import-Clixml -Path $script:CredStorePath
            $Global:DiagMailerCred = $stored
            Write-OK "Jelszó: tartosan mentettbol betoltve ($script:CredStorePath)"
            return $stored
        }
        catch {
            Write-Warn "Tarolt hitelesito ervenytelen - ujra szukseges"
            Remove-Item $script:CredStorePath -Force -ErrorAction SilentlyContinue
        }
    }

    # 3. Interaktiv bekeres
    Write-Host ""
    Write-Host "  +--------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  |  Email hitelesites szukseges               |" -ForegroundColor Cyan
    Write-Host "  |  Add meg a kuldo fiok (fromEmail) adatait  |" -ForegroundColor Cyan
    Write-Host "  |  Gmail eseten App-jelszot hasznalj!        |" -ForegroundColor Cyan
    Write-Host "  +--------------------------------------------+" -ForegroundColor Cyan
    Write-Host ""

    $cred = Get-Credential -Message "SMTP hitelesites - kuldo fiok adatai"
    if ($null -eq $cred) {
        Write-Fail "Hitelesites megszakitva."
        exit 1
    }

    $Global:DiagMailerCred = $cred
    Write-OK "Jelszó elmentve a munkamenet idejere (PS ablak bezarasaig)"

    Write-Host ""
    Write-Host "  Tartosan mentsem a jelszot erre a gepre?" -ForegroundColor Yellow
    Write-Tip  "DPAPI titkositas: csak ez a Windows-felhasznalo olvashatja vissza"
    Write-Tip  "Allando ugyfel gepen hasznos - nem kell mindig beirni"
    Write-Host ""
    $save = Read-Host "  [I = Igen, tartosan | N = Nem, csak most]"

    if ($save -match "^[Ii]") {
        $dir = Split-Path $script:CredStorePath -Parent
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        try {
            $cred | Export-Clixml -Path $script:CredStorePath -Force
            Write-OK "Jelszó tartosan elmentve: $script:CredStorePath"
        }
        catch {
            Write-Warn "Tartos mentes sikertelen: $($_.Exception.Message)"
        }
    }
    else {
        Write-Step "Jelszó csak a PowerShell ablak bezarasaig el"
    }

    return $cred
}

# ===========================================================
#  LOG FAJLOK
# ===========================================================

function Get-LogInfo {
    param([string]$LogFolder)

    if ([System.IO.Path]::IsPathRooted($LogFolder)) {
        $resolved = $LogFolder
    }
    else {
        $resolved = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot $LogFolder))
    }

    Write-Step "LOG mappa: $resolved"

    if (-not (Test-Path $resolved)) {
        Write-Warn "LOG mappa nem letezik: $resolved"
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
#  ZIP TOMORITIES
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
#  EMAIL KULDES
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

    $fileLines = $LogInfo.Files | ForEach-Object {
        "  - $($_.Name)  ($([Math]::Round($_.Length/1KB,1)) KB)"
    }

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
    Write-Tip  "SMTP: $($Config.smtpServer):$($Config.smtpPort)  SSL: $($Config.useSSL)"

    try {
        Send-MailMessage @mailParams
        Write-OK "Email sikeresen elkuldve!"
    }
    catch {
        Write-Fail "Kuldes sikertelen: $($_.Exception.Message)"
        Write-Host ""
        Write-Tip "Hibaelaritas:"
        Write-Tip "  Gmail     -> App-jelszot hasznalj, nem a Google-fiok jelszavat"
        Write-Tip "  Gmail App-jelszava: https://myaccount.google.com/apppasswords"
        Write-Tip "  SMTP port -> 587 (TLS) vagy 465 (SSL)"
        Write-Tip "  Jelszó hiba -> futtasd: .\SendReport.ps1 -ForceCredential"
        throw
    }
}

# ===========================================================
#  FOPRORAM
# ===========================================================

try {
    Write-Header

    # 1. Konfig
    Write-Step "Konfiguracio: $ConfigPath"
    $cfg = Get-DiagConfig -Path $ConfigPath
    Write-OK "Cel email: $($cfg.reportEmail)"
    Write-Sep

    # 2. Admin check
    if (($cfg.requireAdmin -eq $true) -and (-not (Test-IsAdmin))) {
        Invoke-SelfElevate
    }

    # 3. Hitelesito adat
    Write-Host ""
    $cred = Get-DiagCredential -ForcePrompt:$ForceCredential
    Write-Sep

    # 4. LOG fajlok
    Write-Host ""
    $logInfo = Get-LogInfo -LogFolder $cfg.logFolder

    if ($null -eq $logInfo) {
        Write-Host ""
        Write-Warn "Nincs kuldenivalo LOG fajl. Kilepes."
        exit 0
    }
    Write-Sep

    # 5. ZIP
    Write-Host ""
    $script:ZipPath = New-LogZip -LogPath $logInfo.Path
    Write-Sep

    # 6. Kuldes
    Write-Host ""
    Send-DiagReport -Config $cfg -Credential $cred -ZipPath $script:ZipPath -LogInfo $logInfo

    # 7. Opcionalis LOG torles
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
    if (($null -ne $script:ZipPath) -and (Test-Path $script:ZipPath)) {
        Remove-Item $script:ZipPath -Force -ErrorAction SilentlyContinue
        Write-Tip "Ideiglenes ZIP torolve"
    }
}
