#Requires -Version 3.0
<#
.SYNOPSIS
    DiagMailer - Automatikus konfiguráció beállító
.DESCRIPTION
    Interaktívan bekéri az SMTP beállításokat, teszteli a kapcsolatot,
    majd csak sikeres teszt után menti a config.json fájlt.
    Ha config.json.example megtalálható, azt használja sablonként.

    Folyamat:
      1. Email/SMTP adatok bekérése (SMTP preset menüvel)
      2. Jelszó bekérése
      3. Teszt email küldése - ha sikertelen, nem ment semmit
      4. Sikeres teszt után: config.json mentése, jelszó tárolás
      5. Launcher.ps1 visszahívása (clear + friss indítás)
.PARAMETER ConfigPath
    A config.json mentési helye.
.EXAMPLE
    .\Config.ps1
    .\Config.ps1 -ConfigPath "D:\DiagMailer\config.json"
#>

param(
    [string]$ConfigPath = "$PSScriptRoot\config.json"
)

# ===========================================================
#  AUTOMATIKUS JOGOSULTSÁG EMELÉS
# ===========================================================

$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin          = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath, "-ConfigPath", $ConfigPath)
    Start-Process powershell.exe -ArgumentList $argList -Verb RunAs
    exit 0
}

# ===========================================================
#  BEÁLLÍTÁSOK
# ===========================================================

$script:Version       = "3.5.0"
$script:ConfigDir     = Split-Path $ConfigPath -Parent
$script:ExamplePath   = Join-Path $script:ConfigDir "config.json.example"
$script:CredStorePath = "$env:LOCALAPPDATA\DiagMailer\credential.xml"
$script:LauncherPath  = Join-Path $PSScriptRoot "Launcher.ps1"

# SMTP előbeállítások - megkíméli a felhasználót a kereséstől
$script:SmtpPresets = [ordered]@{
    "1" = @{ Display = "Gmail";             Server = "smtp.gmail.com";        Port = 587; SSL = $true;
             Note = "App-jelszo kell! google.com/myaccount > Biztonsag > Appjelszavak" }
    "2" = @{ Display = "Office 365";        Server = "smtp.office365.com";    Port = 587; SSL = $true;
             Note = "Munkahelyi/iskolai Microsoft fiok" }
    "3" = @{ Display = "Outlook.com";       Server = "smtp-mail.outlook.com"; Port = 587; SSL = $true;
             Note = "Szemelyes Microsoft/Hotmail fiok" }
    "4" = @{ Display = "Brevo (ingyenes)";  Server = "smtp-relay.brevo.com";  Port = 587; SSL = $true;
             Note = "300 email/nap ingyenesen - brevo.com fiok kell" }
    "5" = @{ Display = "Egyedi SMTP...";    Server = "";                      Port = 587; SSL = $true;
             Note = "Sajat/cegi SMTP szerver" }
}

# ===========================================================
#  MEGJELENÍTÉSI SEGÉDFÜGGVÉNYEK
# ===========================================================

function Write-Step  { param([string]$Msg) Write-Host "  -> $Msg" -ForegroundColor White }
function Write-OK    { param([string]$Msg) Write-Host "  OK $Msg" -ForegroundColor Green }
function Write-Warn  { param([string]$Msg) Write-Host "  !! $Msg" -ForegroundColor Yellow }
function Write-Fail  { param([string]$Msg) Write-Host "  XX $Msg" -ForegroundColor Red }
function Write-Tip   { param([string]$Msg) Write-Host "     $Msg" -ForegroundColor DarkGray }
function Write-Sep   { Write-Host "  ------------------------------------------" -ForegroundColor DarkGray }
function Write-Title { param([string]$Msg)
    Write-Host ""
    Write-Host "  [ $Msg ]" -ForegroundColor Cyan
    Write-Sep
}

function Read-NonEmpty {
    # Bekér egy sort, nem engedi üresen hagyni, opcionális alapérték
    param([string]$Prompt, [string]$Default = "", [switch]$AllowEmpty)
    do {
        $display = if ($Default) { "$Prompt [$Default]" } else { $Prompt }
        $val = Read-Host "  $display"
        if ([string]::IsNullOrWhiteSpace($val) -and $Default) { $val = $Default }
        if ($AllowEmpty -or -not [string]::IsNullOrWhiteSpace($val)) { return $val }
        Write-Warn "Nem hagyhato uresen!"
    } while ($true)
}

function Test-EmailFormat {
    param([string]$Email)
    return $Email -match "^[^@\s]+@[^@\s]+\.[^@\s]+$"
}

# ===========================================================
#  SMTP BEÁLLÍTÁS BEKÉRÉSE
# ===========================================================

function Get-SmtpConfig {
    Write-Title "SMTP Szerver beallitas"

    Write-Host "  Valaszd ki a levelezoszolgatalatodat:" -ForegroundColor White
    Write-Host ""
    foreach ($key in $script:SmtpPresets.Keys) {
        $p = $script:SmtpPresets[$key]
        Write-Host "  [$key]  $($p.Display)" -ForegroundColor White
        if ($p.Note) { Write-Tip "       $($p.Note)" }
    }
    Write-Host ""

    $choice = Read-Host "  Valasztas [1-5]"
    while ($choice -notin $script:SmtpPresets.Keys) {
        Write-Warn "Ervenytelen valasztas!"
        $choice = Read-Host "  Valasztas [1-5]"
    }

    $preset = $script:SmtpPresets[$choice]

    if ($preset.Server) {
        Write-OK "SMTP: $($preset.Server):$($preset.Port)"
        return @{
            Server = $preset.Server
            Port   = $preset.Port
            SSL    = $preset.SSL
        }
    }

    # Egyedi beallitas
    Write-Host ""
    $server = Read-NonEmpty -Prompt "SMTP szerver neve (pl. mail.sajatceg.hu)"
    $portStr = Read-NonEmpty -Prompt "SMTP port" -Default "587"
    $port = [int]$portStr
    $sslStr = Read-Host "  SSL/TLS hasznalata? [I/N, alapertelmezett: I]"
    $ssl = $sslStr -notmatch "^[Nn]"

    return @{
        Server = $server
        Port   = $port
        SSL    = $ssl
    }
}

# ===========================================================
#  KAPCSOLAT TESZT
# ===========================================================

function Test-SmtpConnection {
    param(
        [hashtable]$Smtp,
        [string]$FromEmail,
        [string]$FromName,
        [string]$ToEmail,
        [System.Management.Automation.PSCredential]$Credential
    )

    Write-Title "Kapcsolat teszt"
    Write-Step "Teszt email kuldese: $ToEmail ..."
    Write-Tip  "SMTP: $($Smtp.Server):$($Smtp.Port)  SSL: $($Smtp.SSL)"

    $subject = "DiagMailer v$($script:Version) - Kapcsolat teszt"
    $body    = @(
        "DiagMailer konfiguracio teszt",
        "==============================",
        "Ez egy automatikus teszt uzenet.",
        "Ha ezt latod, az SMTP beallitas helyes!",
        "",
        "Felado   : $FromName <$FromEmail>",
        "SMTP     : $($Smtp.Server):$($Smtp.Port)",
        "Datum    : $(Get-Date -Format 'yyyy.MM.dd HH:mm:ss')"
    ) -join "`r`n"

    $mailParams = @{
        From       = "$FromName <$FromEmail>"
        To         = $ToEmail
        Subject    = $subject
        Body       = $body
        SmtpServer = $Smtp.Server
        Port       = $Smtp.Port
        Credential = $Credential
        Encoding   = [System.Text.Encoding]::UTF8
    }
    if ($Smtp.SSL) { $mailParams.UseSsl = $true }

    try {
        Send-MailMessage @mailParams
        Write-OK "Teszt email sikeresen elkuldve!"
        Write-Tip  "Ellenorizd a beerkezett leveleid: $ToEmail"
        return $true
    }
    catch {
        Write-Fail "Kuldes sikertelen: $($_.Exception.Message)"
        Write-Host ""
        Write-Tip "Hibaelaritas:"
        Write-Tip "  Gmail      -> App-jelszo kell, nem a Google-fiok jelszava"
        Write-Tip "               https://myaccount.google.com/apppasswords"
        Write-Tip "  Office365  -> Lehet, hogy App-jelszo vagy OAuth kell"
        Write-Tip "  Port       -> Probald 465-os porttal es SSL=true"
        Write-Tip "  Jelszo     -> Biztos helyes? Probalj ujra!"
        return $false
    }
}

# ===========================================================
#  CONFIG MENTÉS
# ===========================================================

function Save-Config {
    param([hashtable]$Settings)

    # Sablon beolvasasa ha letezik (megorizheti a megjegyzes strukturat)
    if (Test-Path $script:ExamplePath) {
        try {
            $template = Get-Content $script:ExamplePath -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch { $template = [PSCustomObject]@{} }
    } else {
        $template = [PSCustomObject]@{}
    }

    # Beállítások felülírása
    $fields = @("reportEmail","fromEmail","fromName","smtpServer","smtpPort","useSSL","subject","logFolder")
    foreach ($f in $fields) {
        if ($Settings.ContainsKey($f)) {
            $template | Add-Member -Force -NotePropertyName $f -NotePropertyValue $Settings[$f]
        }
    }

    # Megjegyzés mezők törlése (ha maradtak az example-ból)
    $toRemove = $template.PSObject.Properties.Name | Where-Object { $_ -like "_*" }
    foreach ($r in $toRemove) { $template.PSObject.Properties.Remove($r) }

    try {
        $template | ConvertTo-Json -Depth 5 | Set-Content $ConfigPath -Encoding UTF8 -Force
        Write-OK "Konfiguracio mentve: $ConfigPath"
        return $true
    }
    catch {
        Write-Fail "Mentes sikertelen: $($_.Exception.Message)"
        return $false
    }
}

function Save-Credential {
    param([System.Management.Automation.PSCredential]$Cred)

    $dir = Split-Path $script:CredStorePath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $Cred | Export-Clixml -Path $script:CredStorePath -Force
    Write-OK "Jelszo tartosan elmentve (DPAPI): $script:CredStorePath"
}

# ===========================================================
#  FŐPROGRAM
# ===========================================================

Clear-Host
Write-Host ""
Write-Host "  +==========================================+" -ForegroundColor Cyan
Write-Host "  |   DiagMailer v$($script:Version)  -  Beallitas varazslo  |" -ForegroundColor Cyan
Write-Host "  +==========================================+" -ForegroundColor Cyan
Write-Host ""

# Meglévő config figyelmeztetes
if (Test-Path $ConfigPath) {
    Write-Warn "Letezik mar config.json: $ConfigPath"
    $overwrite = Read-Host "  Felulirjuk az ujj beallitasokkal? [I/N]"
    if ($overwrite -notmatch "^[Ii]") {
        Write-Step "Kilepes, meglevo konfig marad."
        exit 0
    }
    Write-Host ""
}

# ── 1. Cél email (ahova a riportok mennek) ────────────────────────────
Write-Title "Riport cel email cim (TO:)"
Write-Tip   "Ide fognak erkezni az elemzesre kuldott ZIP mellekletek"
Write-Host ""

do {
    $reportEmail = Read-NonEmpty -Prompt "Cel email cim (pl. szerviz@pelda.hu)"
    if (-not (Test-EmailFormat $reportEmail)) { Write-Warn "Ervenytelen email format!" }
} while (-not (Test-EmailFormat $reportEmail))
Write-OK "Cel: $reportEmail"

# ── 2. Küldő email (SMTP fiók) ────────────────────────────────────────
Write-Title "Kuldo email cim (FROM: / SMTP felhasznalonev)"
Write-Tip   "Ez az a fiok, aminek az SMTP-vel kuldjuk az emailt"
Write-Tip   "Lehet ugyanaz mint a cel, vagy egy dedikalt kuldo fiok"
Write-Host ""

do {
    $fromEmail = Read-NonEmpty -Prompt "Kuldo email cim" -Default $reportEmail
    if (-not (Test-EmailFormat $fromEmail)) { Write-Warn "Ervenytelen email format!" }
} while (-not (Test-EmailFormat $fromEmail))
Write-OK "Kuldo: $fromEmail"

# ── 3. SMTP beállítás ─────────────────────────────────────────────────
$smtpCfg = Get-SmtpConfig

# ── 4. Opcionális mezők ───────────────────────────────────────────────
Write-Title "Opcionalis beallitasok (Enter = alapertelmezett)"

$fromName  = Read-NonEmpty -Prompt "Kuldo neve (megjeleno nev az emailben)" -Default "DiagMailer"
$subject   = Read-NonEmpty -Prompt "Email targy elotag"                     -Default "DiagMailer Jelentes"
$logFolder = Read-NonEmpty -Prompt "LOG mappa eleresi ut"                   -Default "..\LOG"

# ── 5. Jelszó bekérése ────────────────────────────────────────────────
Write-Title "SMTP jelszo"

if ($smtpCfg.Server -eq "smtp.gmail.com") {
    Write-Warn "Gmail eseten APP-JELSZO kell, nem a Google-fiok rendes jelszava!"
    Write-Tip  "Generalas: https://myaccount.google.com/apppasswords"
    Write-Tip  "(2-lepeses azonositas bekapcsolt allapotban kell)"
    Write-Host ""
}

$cred = Get-Credential -Message "SMTP hitelesites: $fromEmail" -UserName $fromEmail
if (-not $cred) {
    Write-Fail "Jelszo bekeres megszakitva. Kilepes."
    exit 1
}

# ── 6. Kapcsolat teszt ────────────────────────────────────────────────
$testOk = $false
$attempt = 0

do {
    $attempt++
    $testOk = Test-SmtpConnection -Smtp $smtpCfg -FromEmail $fromEmail -FromName $fromName -ToEmail $reportEmail -Credential $cred

    if (-not $testOk) {
        Write-Host ""
        Write-Host "  Mit szeretnel tenni?" -ForegroundColor Yellow
        Write-Host "  [1]  Ujra probalom (mas jelszo)"             -ForegroundColor White
        Write-Host "  [2]  Mas SMTP beallitas"                     -ForegroundColor White
        Write-Host "  [0]  Kilepes (nem ment el semmi)"            -ForegroundColor DarkGray
        Write-Host ""
        $retry = Read-Host "  Valasztas"

        switch ($retry) {
            "1" {
                $cred = Get-Credential -Message "Uj SMTP jelszo: $fromEmail" -UserName $fromEmail
                if (-not $cred) { $retry = "0" }
            }
            "2" {
                $smtpCfg = Get-SmtpConfig
                $cred = Get-Credential -Message "SMTP hitelesites: $fromEmail" -UserName $fromEmail
                if (-not $cred) { $retry = "0" }
            }
            "0" {
                Write-Step "Kilepes - config.json NEM lett letrehozva."
                exit 1
            }
        }
    }
} while (-not $testOk -and $attempt -lt 5)

if (-not $testOk) {
    Write-Fail "5 kiserletet utan sem sikerult - kilepes."
    exit 1
}

# ── 7. Mentés ─────────────────────────────────────────────────────────
Write-Title "Mentes"

$settings = @{
    reportEmail = $reportEmail
    fromEmail   = $fromEmail
    fromName    = $fromName
    smtpServer  = $smtpCfg.Server
    smtpPort    = $smtpCfg.Port
    useSSL      = $smtpCfg.SSL
    subject     = $subject
    logFolder   = $logFolder
}

$saved = Save-Config -Settings $settings
if (-not $saved) { exit 1 }

# Jelszó mentése
Write-Host ""
Write-Host "  Jelszot tartosan mentem erre a gepre?" -ForegroundColor Yellow
Write-Tip  "DPAPI titkositas: csak ez a Windows-felhasznalo olvashatja vissza"
Write-Tip  "Allando gepen ajanlott - nem kell minden inditasnal beirni"
$savePw = Read-Host "  [I = Igen | N = Nem, minden indulasnal keri]"
if ($savePw -match "^[Ii]") {
    Save-Credential -Cred $cred
} else {
    # Munkamenet memoria
    $Global:DiagMailerCred = $cred
    Write-OK "Jelszo a munkamenet idejere elmentve"
}

# Example fájl törlése (opcionális)
if (Test-Path $script:ExamplePath) {
    Write-Host ""
    $delExample = Read-Host "  Toroljuk a config.json.example fajlt? [I/N]"
    if ($delExample -match "^[Ii]") {
        Remove-Item $script:ExamplePath -Force
        Write-OK "config.json.example torolve"
    }
}

# ── 8. Siker - Launcher friss indítása ────────────────────────────────
Write-Host ""
Write-Host "  ===========================================" -ForegroundColor Green
Write-Host "  Beallitas kesz! DiagMailer indulas..." -ForegroundColor Green
Write-Host "  ===========================================" -ForegroundColor Green
Write-Host ""
Start-Sleep -Seconds 1

# Ha Launcher.ps1 elerheto, frissen inditjuk
if (Test-Path $script:LauncherPath) {
    Clear-Host
    & $script:LauncherPath
} else {
    Write-OK "Config.json letrehozva: $ConfigPath"
    Write-Tip "Inditsd el a Launcher.ps1-et a folytatashoz."
}

exit 0
