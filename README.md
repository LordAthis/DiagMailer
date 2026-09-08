# DiagMailer v3.5.0

A **DiagMailer** egy Windows környezetre tervezett, hordozható (nulla telepítést igénylő) rendszergazdai és szerviz céleszköz. Elsődleges feladata, hogy a diagnosztikai és hibanaplókat (LOG fájlokat) egyetlen kattintással vagy automatizáltan összegyűjtse, ZIP archívumba tömörítse, majd titkosított SMTP kapcsolaton keresztül elküldje a megadott szerviz e-mail címre.

Ideális MSP-k (Managed Service Provider), rendszergazdák és távoli ügyfélszolgálatok számára a hibafeltárás gyorsítására.

---

## Mappaszerkezet

```
DiagMailer/

├── Config.ps1                ← Az új konfigurációs motor. Interaktívan bekéri az SMTP és küldési adatokat,
│                               validálja a kapcsolatot, létrehozza a végleges JSON-t, majd eltakarítja
│                               a szükségtelen mintafájlokat.
├── ContextMenuInstaller.ps1  ← 
├── ContextMenuSend.ps1       ← 
├── Invoke-DiagMailer.ps1     ← más REPÓ-kba kerülő hívó script
├── Launcher.ps1              ← közvetlen belépési pont, jogosultság kezelés
├── ManageCredential.ps1      ← ...
├── README.md                 ← Ez a leíró fájl
├── SendReport.ps1            ← fő logika (hívható közvetlenül is)
├── config.json.example       ← sablon – ezt töltsd ki → config.json
└── .gitignore                ← Másolásból KIMARADÓ fájlok/mappák listája!
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

## ✨ Főbb funkciók és jellemzők

- **Automatikus Rendszergazda Mód (UAC):** A scriptek észlelik, ha emelt szintű jogosultság szükséges, és automatikusan rendszergazdaként indítják újra magukat.
- **Biztonságos Hitelesítés (Windows DPAPI):** Az SMTP jelszót nem kell sima szövegként tárolni. A Windows Data Protection API segítségével a jelszó felhasználóhoz/géphez kötötten, visszafejthetetlenül titkosítva tárolódik.
- **Környezeti változók támogatása:** A konfigurációs fájlban használhatók a Windows rendszerszintű változói (pl. `%USERPROFILE%`, `%APPDATA%`, `%SystemDrive%`), így a profilok univerzálisan teríthetők.
- **Jobb klikkes (Helyi menü) integráció:** Az ügyfélnek el sem kell indítania a PowerShellt; a mappa felett jobb klikkel kattintva azonnal küldhető a tartalom.
- **Robusztus hibakezelés:** Kezeli a szóközt tartalmazó útvonalakat, ellenőrzi a hálózati kapcsolatot és a konfiguráció érvényességét az indulás előtt.
- **Zero-Configuration indítás:** Nem kell előre kézzel másolgatni és szerkeszteni a JSON-t. Ha hiányzik a konfiguráció, a `Launcher.ps1` automatikusan elindítja a beépített varázslót (`Config.ps1`), amely bekéri az adatokat, leteszteli a működésüket, majd élesíti a rendszert.


---

## 📂 A projekt felépítése és a fájlok szerepe

A repóban található fájlok szorosan együttműködnek a zökkenőmentes futás érdekében:

| Fájlnév | Típus | Leírás és feladatkör |
| :--- | :--- | :--- |
| **`Launcher.ps1`** | Belépési pont | A felhasználó által indított fő script. Ellenőrzi a környezetet, feloldja az útvonalakat, majd átadja a vezérlést a háttérfolyamatnak. |
| **`SendReport.ps1`** | Mag (Core) | A program motorja. Ez végzi a paraméterek feldolgozását, a JSON konfiguráció beolvasását, a naplók tömörítését és a levélküldést (SMTP). |
| **`ContextMenuInstaller.ps1`** | Telepítő | Bejegyzi a DiagMailert a Windows Registry-be (`HKCU\Software\Classes\Directory\shell`), ezzel aktiválva a jobb klikkes küldést. |
| **`ContextMenuUninstaller.ps1`**| Eltávolító | Maradványok nélkül törli a DiagMailer jobb klikkes menüpontját a Windows Registry-ből. |
| **`config.json.example`** | Sablon | Egy előre elkészített konfigurációs minta, amely bemutatja az SMTP szerverek és a célszemélyek beállítási sémáját. |

---
| Fájlnév | Típus | Feladatkör és működési logika |
| :--- | :--- | :--- |
| **`Launcher.ps1`** | Fő belépési pont | A felhasználó vagy a helyi menü által hívott elsődleges script. Ellenőrzi a környezetet (PowerShell verzió, UAC státusz), ellenőrzi a `config.json` meglétét, szükség esetén meghívja a konfigurátort, feloldja a környezeti változókat, majd átadja a vezérlést a küldő magnak. |
| **`Config.ps1`** | Konfigurációs motor | Az új, interaktív beállítófelület. Ha hiányzik a konfiguráció, ez kéri be az SMTP szerver, port, hitelesítési adatok, célemail és alapértelmezett mappa paramétereit. Élő SMTP tesztet végez, és sikeres kapcsolat esetén elmenti a végleges fájlt, miközben biztonsági okokból letörli a szükségtelen mintafájlokat. |
| **`SendReport.ps1`** | Core / Motor | A program tényleges végrehajtója. Beolvassa a finomhangolt beállításokat, ellenőrzi a hálózati kapcsolatot, a célmappa létezését, létrehozza az egyedi névvel ellátott ZIP archívumot, összeállítja a HTML formátumú e-mailt, és elvégzi a kiküldést. |
| **`ManageCredential.ps1`** | Biztonsági modul | A jelszavak biztonságos kezeléséért felelős háttérscript. Ez végzi a nyers jelszavak DPAPI formátumba kódolását a mentéskor, valamint a dekódolást a levélküldés pillanatában. |
| **`ContextMenuInstaller.ps1`** | Telepítő script | Rendszergazdaként futtatva bejegyzi a DiagMailert a Windows Registry-be (`HKCU\Software\Classes\Directory\shell`), beállítja a jobb klikkes menüpont feliratát, ikonját és összeköti azt a végrehajtó scripttel. |
| **`ContextMenuSend.ps1`** | Helyi menü vevő | A jobb klikkes indítás háttérkezelője. Amikor a felhasználó a Windows Intézőben vagy Total Commanderben a menüre kattint, ez a script kapja meg célobjektumként a kiválasztott mappa abszolút útvonalát, amit azonnal továbbít a `Launcher.ps1`-nek feldolgozásra. |
| **`ContextMenuUninstaller.ps1`**| Eltávolító script | Maradványok nélkül tisztítja meg a Windows Registry-t. Törli a helyi menühöz kapcsolódó összes kulcsot és bejegyzést, ha az eszközt el szeretnénk távolítani a gépről. |

---

## Első indítás


### 1.a. ⚙️ Konfiguráció (`config.json`)

A program működését a `config.json` fájl vezérli. Másold le a `config.json.example` fájlt `config.json` néven, majd töltse ki az alábbi struktúra szerint:

```json
{
  "SmtpServer": "://gmail.com",
  "SmtpPort": 587,
  "EnableSsl": true,
  "SmtpUsername": "szerviz.kuldo@gmail.com",
  "SmtpPassword": "TITKOSÍTOTT_VAGY_SIMA_JELSZÓ",
  "IsPasswordEncrypted": false,
  "TargetEmail": "lordathis@gmail.com",
  "DefaultLogFolder": "%USERPROFILE%\\Downloads\\Micsi Pisti",
  "ZipNameTemplate": "DiagLog_{ComputerName}_{Date}_{Time}.zip"
}
```
### 1.b. ⚙️ Első indítás és Automatikus Konfiguráció (`Config.ps1`)

A **DiagMailer v3.5.0**-tól kezdve a beállítás teljesen automatizált. Nem szükséges a `config.json.example` fájlt manuálisan átnevezni vagy szerkeszteni.

A. **Egyszerűen indítsd el a fő scriptet:**
   ```powershell
   .\Launcher.ps1
   ```
B. **Automatikus ellenőrzés:** A `Launcher.ps1` induláskor megnézi, hogy létezik-e már érvényes `config.json`. 
C. **Konfigurációs varázsló:** Ha nem találja, a háttérben meghívja a `Config.ps1` scriptet, ami interaktívan bekéri a szükséges adatokat (SMTP szerver, port, küldő adatok, cél e-mail és alapértelmezett LOG mappa).
D. **Élő SMTP teszt és takarítás:** A megadott adatokkal a script azonnal lefutat egy élő működési tesztet. 
   - **Ha a teszt sikeres:** Menti a beállításokat a végleges `config.json`-ba, biztonsági okokból **automatikusan letörli a mintaként szolgáló `.example` fájlt**, majd zökkenőmentesen folytatja a futást.
   - **Ha a teszt sikertelen:** Nem ment hibás adatot, hanem addig korrigálhatod a beállításokat, amíg a kapcsolat össze nem jön.


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

### Biztonságos jelszókezelés (Opcionális, de ajánlott)
Ha az `IsPasswordEncrypted` értéke `false`, a script az első futás alkalmával beolvassa a sima szöveges jelszót, titkosítja azt a Windows DPAPI segítségével, visszaírja a fájlba a titkosított jelszót, az `IsPasswordEncrypted` értékét pedig automatikusan `true`-ra állítja. Így a jelszó többé nem látható nyers szövegként.

---

## 🚀 Használati módok

A DiagMailer háromféleképpen is használható a rugalmasság érdekében:

### 1. Interaktív futtatás (Manuális indítás)
Ha simán elindítod a `Launcher.ps1`-et, az automatikusan a `config.json`-ban megadott `DefaultLogFolder` útvonalon lévő `LOG` mappát fogja feldolgozni.
```powershell
.\Launcher.ps1
```

### 2. Jobb klikkes (Helyi menü) használat – Az ügyfélbarát mód
1. Futtasd egyszer a `ContextMenuInstaller.ps1` scriptet rendszergazdaként az ügyfél gépén.
2. Ezután az ügyfélnek csak **jobb klikkel** rá kell kattintania arra a mappára (pl. `Micsi Pisti`), aminek a tartalmát el szeretné küldeni, és ki kell választania a **"DiagMailer - LOG Küldés"** opciót.
3. A háttérben lefut a teljes folyamat, nincs szükség konzolos interakcióra.

### 3. Parancssori paraméterezés (Automatizált / MSP környezet)
A `Launcher.ps1` és a `SendReport.ps1` képes külső paramétereket is fogadni, így integrálható meglévő felügyeleti rendszerekbe (RMM) vagy ütemezett feladatokba:

```powershell
# Specifikus mappa küldése a beállított alapértelmezett helyett
.\Launcher.ps1 -logFolder "C:\Különleges\Mappa\Elérési\Útja"

# Küldés egyedi e-mail címre, felülbírálva a config.json-t
.\Launcher.ps1 -targetEmail "masik-szerviz@domain.hu"
```

---

## 🛠️ Követelmények

- **Operációs rendszer:** Windows 7 / 8 / 10 / 11 vagy Windows Server
- **Környezet:** Windows PowerShell 3.0 vagy újabb (alapértelmezetten kompatibilis a beépített PowerShell 5.1-gyel)
- **Hálózat:** Kiinduló SMTP forgalom engedélyezése a megadott porton (587 vagy 465).


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
