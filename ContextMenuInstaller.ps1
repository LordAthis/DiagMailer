#Requires -Version 3.3
<#
.SYNOPSIS
    DiagMailer - Jobb klikk kontextusmenü telepítő / eltávolító
.DESCRIPTION
    Telepíti vagy eltávolítja a Windows Explorer jobb klikk menübe a
    "LOG kuldese (DiagMailer)" bejegyzést mappán és mappa hátterén.
    Telepítés után a DiagMailer elérési útját a rendszerleíróban tárolja,
    hogy a ContextMenuSend.ps1 megtalálja.

    Telepítési logika (a MotwCleaner mintájára):
      - ContextMenuSend.ps1 másolva: C:\Windows\Scripts\DiagMailerSend.ps1
      - DiagMailer elérési útja: HKCU\Software\DiagMailer\InstallPath
      - Kontextusmenü bejegyzések: HKCR\Directory\shell\DiagMailer
                                   HKCR\Directory\Background\shell\DiagMailer
.PARAMETER Action
    Install   - Telepítés (alapértelmezett)
    Uninstall - Eltávolítás
    Status    - Jelenlegi állapot lekérdezése
.EXAMPLE
    .\ContextMenuInstaller.ps1
    .\ContextMenuInstaller.ps1 -Action Uninstall
    .\ContextMenuInstaller.ps1 -Action Status
#>

param(
    [ValidateSet("Install","Uninstall","Status","Menu")]
    [string]$Action = "Menu"
)

# ===========================================================
#  AUTOMATIKUS JOGOSULTSÁG EMELÉS
#  Registry HKCR íráshoz rendszergazda jog szükséges!
# ===========================================================

$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin          = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host ""
    Write-Host "  [ContextMenuInstaller] Emelt jogosultsag szukseges..." -ForegroundColor Yellow
    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Action `"$Action`""
    Start-Process powershell.exe -ArgumentList $argList -Verb RunAs
    exit 0
}

# ===========================================================
#  BEÁLLÍTÁSOK
# ===========================================================

$script:Version       = "3.3.0"
$script:ScriptDir     = $PSScriptRoot
$script:SourceScript  = Join-Path $PSScriptRoot "ContextMenuSend.ps1"
$script:TargetDir     = "$env:SystemRoot\Scripts"
$script:TargetScript  = Join-Path $script:TargetDir "DiagMailerSend.ps1"
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
    Write-Host "  |   DiagMailer - Kontextusmenu Telepito   |" -ForegroundColor Cyan
    Write-Host "  |   v$($script:Version)                               |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
}

# ===========================================================
#  STATUS - Jelenlegi állapot lekérdezése
# ===========================================================

function Get-InstallStatus {
    $status = @{
        ScriptExists  = Test-Path $script:TargetScript
        RegPathExists = Test-Path $script:RegHive
        InstallPath   = ""
        MenuKeys      = @{}
    }

    if ($status.RegPathExists) {
        $val = (Get-ItemProperty -Path $script:RegHive -Name "InstallPath" -ErrorAction SilentlyContinue).InstallPath
        $status.InstallPath = if ($val) { $val } else { "" }
    }

    $HKCR = [Microsoft.Win32.Registry]::ClassesRoot
    foreach ($key in $script:RegKeys) {
        try {
            $k = $HKCR.OpenSubKey($key)
            $status.MenuKeys[$key] = ($null -ne $k)
            if ($null -ne $k) { $k.Close() }
        } catch {
            $status.MenuKeys[$key] = $false
        }
    }

    return $status
}

function Invoke-Status {
    Write-Host ""
    Write-Host "  Kontextusmenu allapota:" -ForegroundColor Cyan
    Write-Sep

    $s = Get-InstallStatus

    # Script fájl
    if ($s.ScriptExists) {
        Write-OK "Script fajl: $script:TargetScript"
    } else {
        Write-Warn "Script fajl: NEM talalhato ($script:TargetScript)"
    }

    # Registry telepítési útvonal
    if ($s.InstallPath) {
        Write-OK "DiagMailer ut: $($s.InstallPath)"
        if (-not (Test-Path (Join-Path $s.InstallPath "SendReport.ps1"))) {
            Write-Warn "SendReport.ps1 nem talalhato az ut alapjan - DiagMailer atvette?"
        }
    } else {
        Write-Warn "DiagMailer ut: nincs mentve a rendszerleloban"
    }

    # Kontextusmenü kulcsok
    Write-Host ""
    foreach ($key in $script:RegKeys) {
        if ($s.MenuKeys[$key]) {
            Write-OK "HKCR\$key  [TELEPITVE]"
        } else {
            Write-Warn "HKCR\$key  [NINCS]"
        }
    }

    Write-Host ""

    $allOk = $s.ScriptExists -and $s.InstallPath -and ($s.MenuKeys.Values -notcontains $false)
    if ($allOk) {
        Write-OK "Allapot: TELEPITVE es mukodokesz"
    } else {
        Write-Warn "Allapot: HIANYOS vagy NINCS TELEPITVE"
    }

    Write-Host ""
}

# ===========================================================
#  INSTALL - Telepítés
# ===========================================================

function Invoke-Install {
    Write-Host ""
    Write-Host "  Kontextusmenu telepitese:" -ForegroundColor Cyan
    Write-Sep

    # ContextMenuSend.ps1 forrás ellenőrzése
    if (-not (Test-Path $script:SourceScript)) {
        Write-Fail "ContextMenuSend.ps1 nem talalhato: $script:SourceScript"
        Write-Tip  "A ContextMenuSend.ps1-nek ugyanabban a mappaban kell lennie!"
        return $false
    }

    # C:\Windows\Scripts mappa létrehozása (ha nem létezik)
    if (-not (Test-Path $script:TargetDir)) {
        Write-Step "Mappa letrehozasa: $script:TargetDir"
        New-Item -Path $script:TargetDir -ItemType Directory -Force | Out-Null
        Write-OK "Mappa letrehozva"
    }

    # Script másolása
    Write-Step "Script masolasa: $script:TargetScript"
    try {
        Copy-Item -Path $script:SourceScript -Destination $script:TargetScript -Force
        Write-OK "Script masolva"
    } catch {
        Write-Fail "Masolas sikertelen: $($_.Exception.Message)"
        return $false
    }

    # DiagMailer elérési út mentése registry-be (HKCU - nem kell HKLM/admin)
    Write-Step "DiagMailer ut mentese: HKCU\Software\DiagMailer"
    try {
        if (-not (Test-Path $script:RegHive)) {
            New-Item -Path $script:RegHive -Force | Out-Null
        }
        Set-ItemProperty -Path $script:RegHive -Name "InstallPath" -Value $script:ScriptDir -Force
        Write-OK "Ut elmentve: $script:ScriptDir"
    } catch {
        Write-Fail "Registry mentes sikertelen: $($_.Exception.Message)"
        return $false
    }

    # Registry kontextusmenü bejegyzések (.NET API - MotwCleaner minta alapjan)
    # HKCR direkt .NET-tel erhetjük el, nem fagyna be, mint a PS provider
    $HKCR = [Microsoft.Win32.Registry]::ClassesRoot

    $commands = @{
        "Directory\shell\DiagMailer"            = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script:TargetScript`" -TargetDir `"%1`""
        "Directory\Background\shell\DiagMailer" = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script:TargetScript`" -TargetDir `"%V`""
    }

    $allOk = $true
    foreach ($keyPath in $commands.Keys) {
        Write-Step "Registry: HKCR\$keyPath"
        try {
            # Régi kulcs törlése ha létezik
            try { $HKCR.DeleteSubKeyTree($keyPath, $false) } catch {}

            # Szülő kulcs létrehozása, felirat és ikon beállítása
            $key = $HKCR.CreateSubKey($keyPath)
            $key.SetValue("", $script:MenuLabel)
            $key.SetValue("Icon", $script:MenuIcon)
            $key.Close()

            # command alkulcs
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
        Write-Tip  "Mappa jobb klikken megjelenik: '$($script:MenuLabel)'"
        Write-Tip  "Mappa hatter jobb klikken is megjelenik"
    } else {
        Write-Warn "Telepites reszben sikertelen - ellenorizd a hibakat!"
    }

    Write-Host ""
    return $allOk
}

# ===========================================================
#  UNINSTALL - Eltávolítás
# ===========================================================

function Invoke-Uninstall {
    Write-Host ""
    Write-Host "  Kontextusmenu eltavolitasa:" -ForegroundColor Cyan
    Write-Sep

    $HKCR = [Microsoft.Win32.Registry]::ClassesRoot
    $anyRemoved = $false

    # Registry bejegyzések törlése
    foreach ($keyPath in $script:RegKeys) {
        Write-Step "Torles: HKCR\$keyPath"
        try {
            $HKCR.DeleteSubKeyTree($keyPath, $false)
            Write-OK "Torolve"
            $anyRemoved = $true
        } catch {
            Write-Tip "Nem volt torolnivalo (nem volt telepitve)"
        }
    }

    # Script fájl törlése C:\Windows\Scripts-ből
    if (Test-Path $script:TargetScript) {
        Write-Step "Script fajl torlese: $script:TargetScript"
        try {
            Remove-Item $script:TargetScript -Force
            Write-OK "Script fajl torolve"
        } catch {
            Write-Warn "Script fajl torles sikertelen: $($_.Exception.Message)"
        }
    }

    # Registry telepítési útvonal törlése
    if (Test-Path $script:RegHive) {
        Write-Step "Registry bejegyzes torlese: HKCU\Software\DiagMailer"
        try {
            Remove-Item -Path $script:RegHive -Recurse -Force
            Write-OK "Registry bejegyzes torolve"
        } catch {
            Write-Warn "Registry torles sikertelen: $($_.Exception.Message)"
        }
    }

    Write-Host ""
    Write-OK "Eltavolitvas kesz! A jobb klikk menubejegyzes megszunt."
    Write-Host ""
}

# ===========================================================
#  MENÜ (alapértelmezett mód)
# ===========================================================

function Show-InstallerMenu {
    do {
        Show-Header
        $s = Get-InstallStatus
        $allOk = $s.ScriptExists -and $s.InstallPath -and ($s.MenuKeys.Values -notcontains $false)
        $statusText = if ($allOk) { "TELEPITVE" } else { "NINCS TELEPITVE" }
        $statusColor = if ($allOk) { "Green" } else { "Yellow" }
        Write-Host "  Allapot: $statusText" -ForegroundColor $statusColor
        Write-Host ""
        Write-Sep
        Write-Host "  [1]  Telepites (kontextusmenu hozzaadasa)" -ForegroundColor White
        Write-Host "  [2]  Eltavolitasz (kontextusmenu torlese)" -ForegroundColor White
        Write-Host "  [3]  Allapot reszletei" -ForegroundColor White
        Write-Sep
        Write-Host "  [0]  Vissza a Launcher menuhoz" -ForegroundColor DarkGray
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
                Write-Host "  !! Biztosan eltavolitod a jobb klikk menubejegyzest?" -ForegroundColor Yellow
                $confirm = Read-Host "  [I = Igen | N = Nem]"
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
                Write-Host "  Ervenytelen valasztas!" -ForegroundColor Yellow
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
