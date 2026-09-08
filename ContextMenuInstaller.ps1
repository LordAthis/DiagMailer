#Requires -Version 3.0
<#
.SYNOPSIS
    DiagMailer - Jobb klikk kontextusmenü telepítő / eltávolító
.DESCRIPTION
    MotwCleaner-szerű telepítési architektúra:
    A szükséges fájlokat C:\Windows\Scripts\DiagMailer\ mappába másolja,
    így a kontextusmenü MINDIG onnan fut - szóközös eredeti mappától független!

    Telepített fájlok:
      C:\Windows\Scripts\DiagMailerSend.ps1        ← menüből hívott kapunyitó
      C:\Windows\Scripts\DiagMailer\SendReport.ps1 ← tényleges küldő logika
      C:\Windows\Scripts\DiagMailer\config.json    ← SMTP beállítások (1x másolja)

    Registry:
      HKCU\Software\DiagMailer\InstallPath = C:\Windows\Scripts\DiagMailer
      HKCR\Directory\shell\DiagMailer\command
      HKCR\Directory\Background\shell\DiagMailer\command

    Frissítéshez futtasd újra a Telepítést - SendReport.ps1 felülíródik,
    config.json NEM íródik felül (megőrzi a beállításokat).
.PARAMETER Action
    Menu      - Interaktív menü (alapértelmezett)
    Install   - Telepítés
    Uninstall - Eltávolítás
    Status    - Jelenlegi állapot
.EXAMPLE
    .\ContextMenuInstaller.ps1
    .\ContextMenuInstaller.ps1 -Action Install
    .\ContextMenuInstaller.ps1 -Action Uninstall
    .\ContextMenuInstaller.ps1 -Action Status
#>

param(
    [ValidateSet("Menu","Install","Uninstall","Status")]
    [string]$Action = "Menu"
)

# ===========================================================
#  AUTOMATIKUS JOGOSULTSÁG EMELÉS
#  Registry HKCR íráshoz és C:\Windows\Scripts\ létrehozáshoz kell!
# ===========================================================

$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin          = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host ""
    Write-Host "  [ContextMenuInstaller] Emelt jogosultsag szukseges..." -ForegroundColor Yellow
    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath, "-Action", $Action)
    Start-Process powershell.exe -ArgumentList $argList -Verb RunAs
    exit 0
}

# ===========================================================
#  BEÁLLÍTÁSOK
#  InstallDir: C:\Windows\Scripts\DiagMailer\ - NINCS SZOKOZ - minden hiba megoldva!
# ===========================================================

$script:Version       = "3.4.0"
$script:ScriptDir     = $PSScriptRoot
$script:InstallDir    = "$env:SystemRoot\Scripts\DiagMailer"
$script:TargetScript  = "$env:SystemRoot\Scripts\DiagMailerSend.ps1"
$script:RegHive       = "HKCU:\Software\DiagMailer"
$script:MenuLabel     = "LOG kuldese (DiagMailer)"
$script:MenuIcon      = "powershell.exe,0"
$script:RegKeys       = @(
    "Directory\shell\DiagMailer",
    "Directory\Background\shell\DiagMailer"
)

function Write-Step { param([string]$Msg) Write-Host "  -> $Msg" -ForegroundColor White }
function Write-OK   { param([string]$Msg) Write-Host "  OK $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "  !! $Msg" -ForegroundColor Yellow }
function Write-Fail { param([string]$Msg) Write-Host "  XX $Msg" -ForegroundColor Red }
function Write-Tip  { param([string]$Msg) Write-Host "     $Msg" -ForegroundColor DarkGray }
function Write-Sep  { Write-Host "  ------------------------------------------" -ForegroundColor DarkGray }

function Show-Header {
    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |  DiagMailer - Kontextusmenu Telepito    |" -ForegroundColor Cyan
    Write-Host "  |  v$($script:Version)  -  C:\Windows\Scripts\DiagMailer\ |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
}

# ===========================================================
#  STATUS - Jelenlegi állapot + tényleges registry parancs
# ===========================================================

function Get-InstallStatus {
    $HKCR = [Microsoft.Win32.Registry]::ClassesRoot
    $status = @{
        SenderExists    = Test-Path $script:TargetScript
        SendReportOK    = Test-Path (Join-Path $script:InstallDir "SendReport.ps1")
        ConfigExists    = Test-Path (Join-Path $script:InstallDir "config.json")
        RegPathExists   = Test-Path $script:RegHive
        InstallPath     = ""
        MenuKeys        = @{}
        MenuCommands    = @{}
    }

    if ($status.RegPathExists) {
        $val = (Get-ItemProperty -Path $script:RegHive -Name "InstallPath" -ErrorAction SilentlyContinue).InstallPath
        $status.InstallPath = if ($val) { $val } else { "" }
    }

    foreach ($key in $script:RegKeys) {
        try {
            $k = $HKCR.OpenSubKey($key)
            $status.MenuKeys[$key] = ($null -ne $k)
            if ($null -ne $k) {
                try {
                    $cmdKey = $HKCR.OpenSubKey("$key\command")
                    if ($cmdKey) {
                        $status.MenuCommands[$key] = $cmdKey.GetValue("")
                        $cmdKey.Close()
                    }
                } catch { $status.MenuCommands[$key] = "(nem olvashato)" }
                $k.Close()
            }
        } catch { $status.MenuKeys[$key] = $false }
    }

    return $status
}

function Invoke-Status {
    Write-Host ""
    Write-Host "  Telepitesi allapot:" -ForegroundColor Cyan
    Write-Sep

    $s = Get-InstallStatus

    # Telepített fájlok
    Write-Host "  Telepitett fajlok ($script:InstallDir):" -ForegroundColor White
    if ($s.SenderExists)   { Write-OK "DiagMailerSend.ps1  (C:\Windows\Scripts\)" }
    else                   { Write-Warn "DiagMailerSend.ps1  HIANYZIK!" }
    if ($s.SendReportOK)   { Write-OK "SendReport.ps1" }
    else                   { Write-Warn "SendReport.ps1  HIANYZIK!" }
    if ($s.ConfigExists)   { Write-OK "config.json" }
    else                   { Write-Warn "config.json  HIANYZIK (telepiteskor masolja)" }

    # Registry
    Write-Host ""
    Write-Host "  Registry:" -ForegroundColor White
    if ($s.InstallPath) {
        Write-OK "InstallPath: $($s.InstallPath)"
        if ($s.InstallPath -ne $script:InstallDir) {
            Write-Warn "InstallPath nem egyezik a celkonytar! Telepitsd ujra!"
        }
    } else {
        Write-Warn "InstallPath: nincs bejegyezve"
    }

    Write-Host ""
    foreach ($key in $script:RegKeys) {
        if ($s.MenuKeys[$key]) {
            Write-OK "HKCR\$key"
            if ($s.MenuCommands[$key]) {
                $cmd = $s.MenuCommands[$key].ToString()
                Write-Tip "  $($cmd.Substring(0, [Math]::Min(85, $cmd.Length)))$(if($cmd.Length -gt 85){'...'})"
            }
        } else {
            Write-Warn "HKCR\$key  [NINCS]"
        }
    }

    Write-Host ""
    $allOk = $s.SenderExists -and $s.SendReportOK -and $s.InstallPath -eq $script:InstallDir -and ($s.MenuKeys.Values -notcontains $false)
    if ($allOk) { Write-OK "Allapot: TELEPITVE es mukodokesz" }
    else        { Write-Warn "Allapot: HIANYOS vagy NINCS TELEPITVE" }
    Write-Host ""
}

# ===========================================================
#  INSTALL - Fájlok másolása + registry bejegyzések
# ===========================================================

function Invoke-Install {
    Write-Host ""
    Write-Host "  Telepites: $script:InstallDir" -ForegroundColor Cyan
    Write-Sep

    # 1. C:\Windows\Scripts\ mappa (ha nincs)
    $scriptsDir = "$env:SystemRoot\Scripts"
    if (-not (Test-Path $scriptsDir)) {
        Write-Step "Mappa letrehozasa: $scriptsDir"
        New-Item -Path $scriptsDir -ItemType Directory -Force | Out-Null
        Write-OK "Letrehozva"
    }

    # 2. C:\Windows\Scripts\DiagMailer\ mappa
    if (-not (Test-Path $script:InstallDir)) {
        Write-Step "Mappa letrehozasa: $script:InstallDir"
        New-Item -Path $script:InstallDir -ItemType Directory -Force | Out-Null
        Write-OK "Letrehozva"
    }

    # 3. ContextMenuSend.ps1 > C:\Windows\Scripts\DiagMailerSend.ps1
    $senderSrc = Join-Path $script:ScriptDir "ContextMenuSend.ps1"
    if (-not (Test-Path $senderSrc)) {
        Write-Fail "ContextMenuSend.ps1 nem talalhato: $senderSrc"
        return $false
    }
    Write-Step "Masolas: DiagMailerSend.ps1 > C:\Windows\Scripts\"
    Copy-Item $senderSrc $script:TargetScript -Force
    Write-OK "Kesz"

    # 4. SendReport.ps1 > C:\Windows\Scripts\DiagMailer\  (mindig frissíti!)
    $sendReportSrc = Join-Path $script:ScriptDir "SendReport.ps1"
    if (-not (Test-Path $sendReportSrc)) {
        Write-Fail "SendReport.ps1 nem talalhato: $sendReportSrc"
        return $false
    }
    Write-Step "Masolas: SendReport.ps1 > $script:InstallDir\"
    Copy-Item $sendReportSrc (Join-Path $script:InstallDir "SendReport.ps1") -Force
    Write-OK "Kesz"

    # 5. config.json > C:\Windows\Scripts\DiagMailer\ (NEM írja felül a meglévőt!)
    $configSrc = Join-Path $script:ScriptDir "config.json"
    $configDst = Join-Path $script:InstallDir "config.json"
    if (Test-Path $configDst) {
        Write-Step "config.json: mar letezik a celhelyen - NEM IRODOTT FELUL (beallitasok megmaradnak)"
        Write-Tip  "Ha ujra be akarod allitani: torold: $configDst"
    } elseif (Test-Path $configSrc) {
        Write-Step "Masolas: config.json > $script:InstallDir\"
        Copy-Item $configSrc $configDst -Force
        Write-OK "Kesz - toltsd ki a cel email cimet: $configDst"
    } else {
        Write-Warn "config.json nem talalhato a forraskonyvarban!"
        Write-Tip  "Masold at: config.json.example > $configDst"
    }

    # 6. Registry - InstallPath (a fix mappara mutat, nincs szokoz!)
    Write-Step "Registry: InstallPath = $script:InstallDir"
    if (-not (Test-Path $script:RegHive)) {
        New-Item -Path $script:RegHive -Force | Out-Null
    }
    Set-ItemProperty -Path $script:RegHive -Name "InstallPath" -Value $script:InstallDir -Force
    Write-OK "Mentve"

    # 7. Registry - kontextusmenü bejegyzések (.NET API)
    # A TargetScript utvonalaban NINCS SZOKOZ - nem kell idezojel!
    $HKCR = [Microsoft.Win32.Registry]::ClassesRoot
    $commands = @{
        "Directory\shell\DiagMailer"            = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -Command `"Set-Location '%1'; & '$script:TargetScript'`""
        "Directory\Background\shell\DiagMailer" = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -Command `"Set-Location '%V'; & '$script:TargetScript'`""
    }

    $allOk = $true
    foreach ($keyPath in $commands.Keys) {
        Write-Step "Registry: HKCR\$keyPath"
        try {
            try { $HKCR.DeleteSubKeyTree($keyPath, $false) } catch {}
            $key = $HKCR.CreateSubKey($keyPath)
            $key.SetValue("", $script:MenuLabel)
            $key.SetValue("Icon", $script:MenuIcon)
            $key.Close()
            $cmdKey = $HKCR.CreateSubKey("$keyPath\command")
            $cmdKey.SetValue("", $commands[$keyPath])
            $cmdKey.Close()
            Write-OK "OK"
        } catch {
            Write-Fail "HIBA: $($_.Exception.Message)"
            $allOk = $false
        }
    }

    Write-Host ""
    if ($allOk) {
        Write-OK "Telepites sikeres!"
        Write-Tip  "Mappa jobb klikken: '$script:MenuLabel'"
        Write-Tip  "Mappa hatter jobb klikken is mukodik"
        Write-Tip  "Frissiteshez futtasd ujra a Telepitest!"
    } else {
        Write-Warn "Telepites reszben sikertelen!"
    }
    Write-Host ""
    return $allOk
}

# ===========================================================
#  UNINSTALL - Eltávolítás
# ===========================================================

function Invoke-Uninstall {
    Write-Host ""
    Write-Host "  Eltavolitas:" -ForegroundColor Cyan
    Write-Sep

    $HKCR = [Microsoft.Win32.Registry]::ClassesRoot

    # Registry kontextusmenü bejegyzések
    foreach ($keyPath in $script:RegKeys) {
        Write-Step "Registry torles: HKCR\$keyPath"
        try {
            $HKCR.DeleteSubKeyTree($keyPath, $false)
            Write-OK "Torolve"
        } catch { Write-Tip "Nem volt torolnivalo" }
    }

    # Registry InstallPath
    if (Test-Path $script:RegHive) {
        Write-Step "Registry torles: HKCU\Software\DiagMailer"
        try {
            Remove-Item -Path $script:RegHive -Recurse -Force
            Write-OK "Torolve"
        } catch { Write-Warn "Torles sikertelen: $($_.Exception.Message)" }
    }

    # C:\Windows\Scripts\DiagMailerSend.ps1
    if (Test-Path $script:TargetScript) {
        Write-Step "Torles: $script:TargetScript"
        Remove-Item $script:TargetScript -Force
        Write-OK "Torolve"
    }

    # C:\Windows\Scripts\DiagMailer\ mappa
    if (Test-Path $script:InstallDir) {
        # config.json megőrzése (van-e értelme?)
        $configInInstall = Join-Path $script:InstallDir "config.json"
        $keepConfig = $false
        if (Test-Path $configInInstall) {
            Write-Host ""
            $keep = Read-Host "  Megorizem a config.json-t (email beallitasok)? [I/N]"
            $keepConfig = ($keep -match "^[Ii]")
        }

        if ($keepConfig) {
            # Csak a SendReport.ps1-et töröljük, config.json marad
            $srInInstall = Join-Path $script:InstallDir "SendReport.ps1"
            if (Test-Path $srInInstall) { Remove-Item $srInInstall -Force }
            Write-OK "SendReport.ps1 torolve, config.json megorzve: $configInInstall"
        } else {
            Write-Step "Torles: $script:InstallDir\"
            Remove-Item $script:InstallDir -Recurse -Force
            Write-OK "Mappa torolve"
        }
    }

    Write-Host ""
    Write-OK "Eltavolitas kesz!"
    Write-Host ""
}

# ===========================================================
#  MENÜ
# ===========================================================

function Show-InstallerMenu {
    do {
        Show-Header
        $s = Get-InstallStatus
        $allOk = $s.SenderExists -and $s.SendReportOK -and ($s.MenuKeys.Values -notcontains $false)
        $stColor = if ($allOk) { "Green" } else { "Yellow" }
        $stText  = if ($allOk) { "TELEPITVE" } else { "NINCS TELEPITVE" }
        Write-Host "  Allapot: $stText" -ForegroundColor $stColor
        Write-Tip  "Telepitesi hely: $script:InstallDir"
        Write-Host ""
        Write-Sep
        Write-Host "  [1]  Telepites / Frissites" -ForegroundColor White
        Write-Host "  [2]  Eltavolitas" -ForegroundColor White
        Write-Host "  [3]  Allapot reszletei" -ForegroundColor White
        Write-Sep
        Write-Host "  [0]  Vissza" -ForegroundColor DarkGray
        Write-Host ""

        $choice = Read-Host "  Valasztas"
        switch ($choice) {
            "1" {
                Invoke-Install
                Write-Host "  [Enter] a folytatashoz..."
                $null = Read-Host
            }
            "2" {
                Write-Host ""
                Write-Host "  !! Biztosan eltavolitod?" -ForegroundColor Yellow
                $confirm = Read-Host "  [I/N]"
                if ($confirm -match "^[Ii]") { Invoke-Uninstall }
                Write-Host "  [Enter] a folytatashoz..."
                $null = Read-Host
            }
            "3" {
                Invoke-Status
                Write-Host "  [Enter] a folytatashoz..."
                $null = Read-Host
            }
            "0" { Write-Host "  Vissza..." -ForegroundColor DarkGray }
            default {
                Write-Host "  Ervenytelen!" -ForegroundColor Yellow
                Start-Sleep -Seconds 1
            }
        }
    } while ($choice -ne "0")
}

# ===========================================================
#  FŐPROGRAM
# ===========================================================

Show-Header

switch ($Action) {
    "Install"   { Invoke-Install;   Write-Host "  [Enter] a bezarashoz..."; $null = Read-Host }
    "Uninstall" { Invoke-Uninstall; Write-Host "  [Enter] a bezarashoz..."; $null = Read-Host }
    "Status"    { Invoke-Status;    Write-Host "  [Enter] a bezarashoz..."; $null = Read-Host }
    "Menu"      { Show-InstallerMenu }
}
