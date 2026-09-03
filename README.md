# DiagMailer

**Automatikus LOG összegyűjtő és emailben küldő – PowerShell, nulla telepítés**

Szervizes/MSP eszköz: bármely diagnosztikai/karbantartó REPÓ mellé téve összegyűjti a LOG mappát, ZIP-be csomagolja, és elküldi a konfigurált email címre. Minden beállítás JSON fájlban, jelszó DPAPI-titkosítva a helyi gépen.

---

## Mappaszerkezet

```
DiagMailer/
├── SendReport.ps1        ← fő logika (hívható közvetlenül is)
├── Launcher.ps1          ← közvetlen belépési pont, jogosultság kezelés
├── Invoke-DiagMailer.ps1 ← más REPÓ-kba kerülő hívó script
├── config.json.example   ← sablon – ezt töltsd ki → config.json
├── .gitignore            ← config.json KIMARAD a repóból!
└── README.md
```

**Integrált REPÓ-ban a várt szerkezet:**
```
BármelyRepó/
├── LOG/                      ← ide gyűjti a többi script a logokat
├── DiagMailer/               ← ez a mappa
│   ├── SendReport.ps1
│   └── config.json           ← kitöltve, GITIGNORE-ban!
└── Invoke-DiagMailer.ps1     ← menüből hívható integráció
```

---

## Első indítás

### 1. Config létrehozása
```powershell
Copy-Item DiagMailer\config.json.example DiagMailer\config.json
notepad DiagMailer\config.json
```
Kötelező kitölteni: `reportEmail`, `fromEmail`, `smtpServer`, `smtpPort`

### 2. Futtatás
```powershell
# Közvetlen futtatás:
.\DiagMailer\Launcher.ps1

# Vagy SendReport közvetlenül:
.\DiagMailer\SendReport.ps1

# Más REPÓ-ból (automatikus letöltéssel):
.\Invoke-DiagMailer.ps1
```

Első futtatáskor bekéri az SMTP-jelszót, és rákérdez: **tartósan menti-e** (DPAPI-titkosítással, csak ez a Windows-felhasználó olvashatja vissza).

---

## Paraméterek

### SendReport.ps1 / Launcher.ps1

| Kapcsoló | Leírás |
|---|---|
| `-ConfigPath "C:\..."` | Egyedi config.json hely |
| `-ForceCredential` | Figyelmen kívül hagyja a tárolt jelszót, újra bekéri |
| `-DeleteLogsAfterSend` | Küldés után törli a LOG fájlokat |

### Invoke-DiagMailer.ps1

| Kapcsoló | Leírás |
|---|---|
| `-DiagMailerRepoUrl "..."` | Felülírja a beégetett GitHub URL-t |
| `-ForceCredential` | Átadja a SendReport-nak |
| `-DeleteLogsAfterSend` | Átadja a SendReport-nak |

---

## Jelszókezelés

A DiagMailer háromszintű jelszókezelést használ:

```
1. Munkamenet memória ($Global:DiagMailerCred)
      ↓ ha nem találja
2. DPAPI titkosított fájl (%LOCALAPPDATA%\DiagMailer\credential.xml)
      ↓ ha nem találja
3. Interaktív bekérés (Get-Credential ablak)
      ↓ megkérdezi: tartósan mentsük-e?
```

**Fontos tudnivalók:**
- A DPAPI titkosítás **gépenként és felhasználónként egyedi** – más gépen/felhasználón nem olvasható vissza
- A tárolt fájl (`credential.xml`) soha ne kerüljön a repóba
- Jelszócsere vagy hibás jelszó esetén: `.\SendReport.ps1 -ForceCredential`
- Az emelt jogosultságú (RunAs) folyamat **nem örökli** a munkamenet memóriát – tartós mentés ajánlott állandó gépeken

---

## SMTP beállítások

### Gmail (ajánlott teszteléshez)
```json
"smtpServer": "smtp.gmail.com",
"smtpPort": 587,
"useSSL": true
```
⚠ **Gmail App-jelszó szükséges**, nem a Google-fiók rendes jelszava!
Generálás: Google-fiók → Biztonság → 2-lépéses azonosítás → Appjelszavak
https://myaccount.google.com/apppasswords

### Office 365 / Microsoft
```json
"smtpServer": "smtp.office365.com",
"smtpPort": 587,
"useSSL": true
```

### Brevo (ingyenes 300 email/nap, megbízható)
```json
"smtpServer": "smtp-relay.brevo.com",
"smtpPort": 587,
"useSSL": true
```
Felhasználónév: a Brevo-fiókon generált SMTP API-kulcs

---

## Más REPÓ-kba való beépítés

### 1. Másold be az Invoke-DiagMailer.ps1-t a REPÓ-ba

### 2. Írd át a GitHub URL-t benne:
```powershell
[string]$DiagMailerRepoUrl = "https://github.com/TE_NEVED/DiagMailer.git"
```

### 3. Hívd meg a menüdből:
```powershell
# Menü egyik menüpontja:
"5" {
    Write-Host "Jelentés küldése..."
    & "$PSScriptRoot\Invoke-DiagMailer.ps1"
}

# Vagy egy script végén automatikusan:
& "$PSScriptRoot\Invoke-DiagMailer.ps1" -DeleteLogsAfterSend
```

### 4. Vedd fel a .gitignore-ba:
```
DiagMailer/config.json
```

---

## Windows verzió kompatibilitás

| Verzió | PowerShell | Állapot |
|---|---|---|
| Windows 11 | 5.1 beépített | ✅ Teljes |
| Windows 10 | 5.1 beépített | ✅ Teljes |
| Windows 7 | 2.0–5.1 (frissíthető) | ⚠ Részleges* |

*Win7: `Compress-Archive` csak PS 5.0+, `Send-MailMessage` TLS 1.2 korlátai lehetnek.
Modern SMTP szolgáltatók (Gmail, O365) **megkövetelnek TLS 1.2-t** – Win7-en ez nem mindig elérhető alapból.

---

## Biztonsági megjegyzések

- `config.json` mindig **GITIGNORE-ban** legyen
- Jelszó soha ne kerüljön sima szövegként sehova
- A DPAPI titkosítás nem jelent teljes biztonságot – admin jogosultságú támadó visszafejtheti
- Érzékeny ügyfél adatokat ne küldj titkosítatlan emailben

---

## Licenc

MIT – Szabad használat, módosítás, terjesztés, forrásmegjelöléssel.
