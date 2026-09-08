#Requires -Version 3.0
<#
.SYNOPSIS
    DiagMailer - Hitelesítő adatok kezelése
.DESCRIPTION
    Lekérdezi, frissíti vagy törli a DiagMailer által tárolt SMTP jelszót.
    Hívható a Launcher.ps1 menüjéből, vagy önállóan is futtatható.
    A tárolt fájl helye: %LOCALAPPDATA%\DiagMailer\credential.xml
    (DPAPI titkosítás: csak ez a Windows-felhasználó olvashatja)
.PARAMETER Action
    Query  - Megmutatja a tárolt jelszó állapotát (felhasználónév, hely)
    Update - Törli a régit, bekéri az újat, elmenti
    Delete - Törli a tárolt jelszót és a munkamenet-memóriát
.EXAMPLE
    .\ManageCredential.ps1 -Action Query
    .\ManageCredential.ps1 -Action Update
    .\ManageCredential.ps1 -Action Delete
#>

param(
    [ValidateSet("Query","Update","Delete")]
    [string]$Action = "Query"
)

# ===========================================================
#  BEÁLLÍTÁSOK
# ===========================================================

$script:Version       = "3.4.0"

$script:CredStorePath = "$env:LOCALAPPDATA\DiagMailer\credential.xml"

function Write-Step { param([string]$Msg) Write-Host "  -> $Msg" -ForegroundColor White }
function Write-OK   { param([string]$Msg) Write-Host "  OK $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "  !! $Msg" -ForegroundColor Yellow }
function Write-Fail { param([string]$Msg) Write-Host "  XX $Msg" -ForegroundColor Red }
function Write-Tip  { param([string]$Msg) Write-Host "     $Msg" -ForegroundColor DarkGray }
function Write-Sep  { Write-Host "  ------------------------------------------" -ForegroundColor DarkGray }

# ===========================================================
#  QUERY - Tárolt jelszó állapotának lekérdezése
# ===========================================================

function Invoke-CredQuery {
    Write-Host ""
    Write-Host "  Jelszo allapota:" -ForegroundColor Cyan
    Write-Sep

    # Munkamenet memória
    if ($null -ne $Global:DiagMailerCred) {
        Write-OK "Munkamenet memoria: aktiv"
        Write-Tip  "Felhasznalo: $($Global:DiagMailerCred.UserName)"
    }
    else {
        Write-Warn "Munkamenet memoria: ures (PS ablak ujrainditasa utan mindig ures)"
    }

    Write-Host ""

    # Tartós tárolás
    if (Test-Path $script:CredStorePath) {
        try {
            $stored = Import-Clixml -Path $script:CredStorePath
            Write-OK "Tartos tarolas: mentett adat talalhato"
            Write-Tip  "Felhasznalo : $($stored.UserName)"
            Write-Tip  "Fajl helye  : $script:CredStorePath"
            $fileDate = (Get-Item $script:CredStorePath).LastWriteTime.ToString("yyyy.MM.dd HH:mm")
            Write-Tip  "Mentve      : $fileDate"
        }
        catch {
            Write-Warn "Tartos tarolas: fajl letezik, de nem olvashato (serult?)"
            Write-Tip  "Fajl helye: $script:CredStorePath"
            Write-Tip  "Javasolt: ManageCredential.ps1 -Action Update"
        }
    }
    else {
        Write-Warn "Tartos tarolas: nincs mentett jelszo"
        Write-Tip  "Fajl helye lenne: $script:CredStorePath"
        Write-Tip  "Elso SendReport.ps1 futaskor kerdezi, keri-e menteni"
    }

    Write-Host ""
}

# ===========================================================
#  UPDATE - Jelszó frissítése (törlés + új bekérése + mentés)
# ===========================================================

function Invoke-CredUpdate {
    Write-Host ""
    Write-Host "  Jelszo ujrakonfiguralas:" -ForegroundColor Cyan
    Write-Sep

    # Régi törlése memóriából
    if ($null -ne $Global:DiagMailerCred) {
        $Global:DiagMailerCred = $null
        Write-OK "Munkamenet memoria torolve"
    }

    # Régi fájl törlése
    if (Test-Path $script:CredStorePath) {
        Remove-Item $script:CredStorePath -Force
        Write-OK "Regi tarolt jelszo torolve: $script:CredStorePath"
    }
    else {
        Write-Tip "Nem volt tarolt jelszo, uj beallitas kovetkezik"
    }

    Write-Host ""

    # Új bekérése
    Write-Host "  +--------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  |  Uj SMTP hitelesites beallitasa             |" -ForegroundColor Cyan
    Write-Host "  |  Gmail: App-jelszo kell, nem a rendes!      |" -ForegroundColor Cyan
    Write-Host "  |  https://myaccount.google.com/apppasswords  |" -ForegroundColor Cyan
    Write-Host "  +--------------------------------------------+" -ForegroundColor Cyan
    Write-Host ""

    $cred = Get-Credential -Message "Uj SMTP hitelesites - add meg a kuldo fiok adatait"
    if ($null -eq $cred) {
        Write-Fail "Bekeres megszakitva - jelszo nem lett mentve."
        return
    }

    # Munkamenetbe
    $Global:DiagMailerCred = $cred
    Write-OK "Uj jelszo elmentve a munkamenet idejere"

    # Tartós mentés kérdése
    Write-Host ""
    $save = Read-Host "  Tartosan mentsem erre a gepre is? [I/N]"
    if ($save -match "^[Ii]") {
        $dir = Split-Path $script:CredStorePath -Parent
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $cred | Export-Clixml -Path $script:CredStorePath -Force
        Write-OK "Uj jelszo tartosan elmentve: $script:CredStorePath"
    }
    else {
        Write-Step "Jelszo csak a PS ablak bezarasaig el"
    }

    Write-Host ""
}

# ===========================================================
#  DELETE - Tárolt jelszó törlése
# ===========================================================

function Invoke-CredDelete {
    Write-Host ""
    Write-Host "  Tarolt jelszo torlese:" -ForegroundColor Cyan
    Write-Sep

    $deleted = $false

    # Munkamenet memória törlése
    if ($null -ne $Global:DiagMailerCred) {
        $Global:DiagMailerCred = $null
        Write-OK "Munkamenet memoria torolve"
        $deleted = $true
    }
    else {
        Write-Tip "Munkamenet memoriabol nem volt torolnivalo"
    }

    # Fájl törlése
    if (Test-Path $script:CredStorePath) {
        Remove-Item $script:CredStorePath -Force
        Write-OK "Tarolt jelszo fajl torolve: $script:CredStorePath"
        $deleted = $true
    }
    else {
        Write-Tip "Nem volt tartosan mentett jelszo fajl"
    }

    Write-Host ""

    if ($deleted) {
        Write-OK "Torles kesz - kovetkezo SendReport futaskor ujra keri a jelszo!"
    }
    else {
        Write-Warn "Nem volt mit torolni"
    }

    Write-Host ""
}

# ===========================================================
#  FŐPROGRAM - Action alapján elágazás
# ===========================================================

switch ($Action) {
    "Query"  { Invoke-CredQuery }
    "Update" { Invoke-CredUpdate }
    "Delete" { Invoke-CredDelete }
}
