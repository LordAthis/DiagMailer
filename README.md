# DiagMailer v3.5.1

A **DiagMailer** egy Windows környezetre tervezett, hordozható (nulla telepítést igénylő) rendszergazdai és szerviz céleszköz. Elsődleges feladata, hogy a diagnosztikai és hibanaplókat (LOG fájlokat) egyetlen kattintással vagy automatizáltan összegyűjtse, ZIP archívumba tömörítse, majd titkosított SMTP kapcsolaton keresztül elküldje a megadott szerviz e-mail címre.

Ideális MSP-k (Managed Service Provider), rendszergazdák és távoli ügyfélszolgálatok számára a hibafeltárás gyorsítására.

---

## Mappaszerkezet

```
DiagMailer/
├── Config.ps1                ← Interaktív beállítás varázsló. Bekéri az SMTP és küldési
│                               adatokat, leteszteli az összeköttetést, és csak sikeres
│                               teszt után hozza létre a végleges config.json-t.
├── ContextMenuInstaller.ps1  ← Jobb klikkes Windows menü telepítője és eltávolítója.
│                               MotwCleaner-szerű architektúra: fix helyre (C:\Windows\Scripts\)
│                               telepít, szóközös útvonalaktól független.
├── ContextMenuSend.ps1       ← A jobb klikkes menüből induló híd-script. Megkeresi a
│                               LOG mappát, majd átadja a SendReport.ps1-nek.
├── InvokeDiagMailer.ps1      ← Más REPÓ-kba beépíthető hívó script. Ellenőrzi a DiagMailer
│                               meglétét, szükség esetén letölti GitHub-ról, majd elindítja.
├── Launcher.ps1              ← Fő belépési pont és interaktív főmenü. Ellenőrzi a config
│                               meglétét, szükség esetén meghívja a Config.ps1 varázslót.
├── ManageCredential.ps1      ← SMTP jelszó kezelő modul: lekérdezés, frissítés, törlés.
├── SendReport.ps1            ← A program magja. Összegyűjti a LOG-okat, ZIP-be tömöríti,
│                               és elküldi az SMTP szerveren keresztül.
├── config.json.example       ← Konfigurációs sablon – lásd az Első indítás fejezetet.
├── .gitignore                ← Biztonsági szűrő: a config.json és credential.xml sosem
│                               kerülhet a repóba!
└── README.md                 ← Ez a leíró fájl.
```

**Integrált REPÓ-ban a várt szerkezet:**

```
BármelyRepó/
├── LOG/                          ← ide gyűjti a többi script a logokat
├── DiagMailer/                   ← ez a mappa (vagy szimlink)
│   ├── SendReport.ps1
│   └── config.json               ← kitöltve, GITIGNORE-ban!
└── InvokeDiagMailer.ps1          ← menüből hívható integráció
```

---

## ✨ Főbb funkciók és jellemzők

- **Automatikus Rendszergazda Mód (UAC):** Minden script észleli, ha emelt szintű jogosultság szükséges, és automatikusan rendszergazdaként indítja újra magát — a felhasználónak csak az UAC ablakot kell jóváhagyni.
- **Biztonságos hitelesítés (Windows DPAPI):** Az SMTP jelszót nem kell sima szövegként tárolni. A Windows Data Protection API segítségével a jelszó felhasználóhoz és géphez kötötten, visszafejthetetlenül titkosítva tárolódik a `%LOCALAPPDATA%\DiagMailer\credential.xml` fájlban.
- **Háromszintű jelszómemória:** Munkamenet → tartós DPAPI tár → interaktív bekérés. Csak akkor kér jelszót, ha valóban szükséges.
- **Jobb klikkes (helyi menü) integráció:** Az ügyfélnek el sem kell indítania a PowerShellt. Mappán, mappa hátterén, fájlon és közvetlenül a LOG mappán is működik.
- **MotwCleaner-szerű fix telepítés:** A kontextusmenüs fájlok a `C:\Windows\Scripts\DiagMailer\` mappába kerülnek — szóközös felhasználónévtől, munkakönyvtártól teljesen független.
- **Robusztus hibakezelés:** Kezeli a szóközt tartalmazó útvonalakat (pl. `C:\Users\Vermis- PC\...`), ellenőrzi a hálózati kapcsolatot és a konfiguráció érvényességét.
- **Zero-Configuration indítás:** Ha hiányzik a konfiguráció, a `Launcher.ps1` automatikusan elindítja a beépített varázslót (`Config.ps1`), amely bekéri az adatokat, SMTP preset menüből választható a szolgáltató, leteszteli a működést, majd élesíti a rendszert.
- **Más REPÓ-kba beépíthető:** Az `InvokeDiagMailer.ps1` bármely meglévő PowerShell projektbe beilleszthető — megkeresi vagy letölti a DiagMailert, és meghívja.

---

## 📂 A projekt felépítése és a fájlok szerepe

| Fájlnév | Típus | Feladatkör és működési logika |
|---|---|---|
| **`Launcher.ps1`** | Fő belépési pont | A felhasználó által indított elsődleges script. Ellenőrzi a `config.json` meglétét, szükség esetén meghívja a `Config.ps1` varázslót, majd interaktív főmenüt jelenít meg (Jelentés küldése, Jelszókezelés, Kontextusmenü telepítés). |
| **`Config.ps1`** | Konfigurációs varázsló | Interaktív, lépésről lépésre vezető beállítófelület. SMTP preset menüből választható (Gmail, Office 365, Brevo stb.), bekéri az email- és SMTP-adatokat, élő tesztet végez, és csak sikeres kapcsolat esetén menti a `config.json`-t. |
| **`SendReport.ps1`** | Core / Motor | A program tényleges végrehajtója. Beolvassa a konfigurációt, megkeresi a LOG mappát, létrehozza az egyedi névvel ellátott ZIP archívumot, összeállítja az e-mailt, és elvégzi a kiküldést SMTP-n keresztül. |
| **`ManageCredential.ps1`** | Biztonsági modul | Az SMTP jelszó kezeléséért felelős modul. Három működési mód: `Query` (állapot és tárolt felhasználónév lekérdezése), `Update` (jelszó frissítése), `Delete` (tárolt jelszó törlése). A `Launcher.ps1` főmenüjéből is elérhető. |
| **`ContextMenuInstaller.ps1`** | Telepítő/eltávolító | Rendszergazdaként futtatva bejegyzi a DiagMailert a Windows Registry-be. A szükséges fájlokat a `C:\Windows\Scripts\DiagMailer\` mappába másolja (fix, szóközöktől mentes hely). Tartalmazza az eltávolítást és az állapot lekérdezést is. |
| **`ContextMenuSend.ps1`** | Helyi menü hívó | A Windows Intézőből induló híd-script. Megkapja a jobb klikkel megnyitott mappa útvonalát, megkeresi a LOG (vagy log, Logs stb.) almappát — ha a kattintott mappa maga a LOG, azt használja közvetlenül. Majd átadja a `SendReport.ps1`-nek. |
| **`InvokeDiagMailer.ps1`** | Integráció | Más REPÓ-kba beépíthető hívó script. Megkeresi a DiagMailer mappát egy szinttel feljebb, ha nem találja, felajánlja a letöltést GitHub-ról, ellenőrzi a `config.json` meglétét, majd elindítja a küldést. |

---

## Első indítás

### 1.a. ⚙️ Automatikus konfiguráció (`Config.ps1` varázsló) — Ajánlott

A **DiagMailer v3.5.0** óta a beállítás teljesen automatizált, nem szükséges kézzel szerkeszteni semmit.

**A. Egyszerűen indítsd el a fő scriptet:**

```powershell
.\Launcher.ps1
```

**B. Automatikus ellenőrzés:** A `Launcher.ps1` induláskor megvizsgálja, hogy létezik-e érvényes `config.json`.

**C. Konfigurációs varázsló:** Ha nem találja, meghívja a `Config.ps1` scriptet, amely lépésről lépésre végigvezet:

```
[1] Cél email cím   → Ide érkeznek a ZIP mellékletek (TO:)
[2] Küldő email cím → SMTP felhasználónév (FROM:)
[3] SMTP szolgáltató választó:
      [1] Gmail         (smtp.gmail.com:587)    ← App-jelszó figyelmeztetéssel
      [2] Office 365    (smtp.office365.com:587)
      [3] Outlook.com   (smtp-mail.outlook.com:587)
      [4] Brevo         (smtp-relay.brevo.com:587)  ← 300 email/nap ingyenesen
      [5] Egyedi SMTP...
[4] Megjelenítési név, email tárgy, LOG mappa (opcionális, alapértelmezettekkel)
[5] Jelszó bekérése (Get-Credential ablak)
[6] ÉLŐ TESZT EMAIL küldése → Ha sikertelen: új jelszó / más SMTP / kilépés
[7] Sikeres teszt után: config.json mentése, jelszó tárolás, Launcher újraindítás
```

**D. Éles SMTP teszt:** A megadott adatokkal azonnal lefut egy valódi tesztküldés.
- **Ha sikeres:** Elmenti a `config.json`-t, tárolja a jelszót (DPAPI), opcionálisan törli az `.example` fájlt.
- **Ha sikertelen:** Nem ment hibás adatot. Lehetőség: új jelszó, más SMTP beállítás, vagy kilépés.

---

### 1.b. ⚙️ Manuális konfiguráció (`config.json`)

Ha mégis kézzel szeretnéd beállítani, másold le a sablont és töltsd ki:

```powershell
Copy-Item config.json.example config.json
notepad config.json
```

A `config.json` struktúrája és kötelező mezői:

```json
{
  "reportEmail":  "szerviz@pelda.hu",
  "fromEmail":    "kuldo@gmail.com",
  "smtpServer":   "smtp.gmail.com",
  "smtpPort":     587,
  "useSSL":       true,
  "fromName":     "DiagMailer",
  "subject":      "DiagMailer Jelentes",
  "logFolder":    "..\\LOG"
}
```

| Mező | Kötelező | Leírás |
|---|---|---|
| `reportEmail` | ✅ | Cél email cím — ide érkeznek a ZIP mellékletek (TO:) |
| `fromEmail` | ✅ | Küldő email cím — egyben az SMTP felhasználónév (FROM:) |
| `smtpServer` | ✅ | SMTP kiszolgáló hostname |
| `smtpPort` | ✅ | SMTP port (587 = TLS/STARTTLS, 465 = SSL) |
| `useSSL` | ✅ | Titkosított kapcsolat (`true` ajánlott) |
| `fromName` | ❌ | Megjelenítési név az emailben (alapértelmezett: "DiagMailer") |
| `subject` | ❌ | Email tárgy előtag (alapértelmezett: "DiagMailer Jelentes") |
| `logFolder` | ✅ | LOG mappa elérési útja — relatív vagy abszolút |

> ⚠️ **Fontos:** A `config.json` sosem kerülhet a repóba! A `.gitignore` alapból kizárja, de ellenőrizd!
> Az SMTP jelszó **nem** tárolódik a `config.json`-ban — azt a DPAPI kezeli biztonságosan.

---

### 2. Futtatás

```powershell
# Fő belépési pont (ajánlott):
.\Launcher.ps1

# SendReport közvetlen hívása (ha már van config + jelszó):
.\SendReport.ps1

# Más REPÓ-ból (automatikus DiagMailer-keresés + letöltés):
.\InvokeDiagMailer.ps1
```

---

## Paraméterek

### SendReport.ps1

| Kapcsoló | Leírás |
|---|---|
| `-ConfigPath "C:\..."` | Egyedi config.json elérési út (alapértelmezett: script melletti mappa) |
| `-LogFolder "C:\..."` | LOG mappa felülírása (config.json `logFolder` mezőjét írja felül) |
| `-ForceCredential` | Figyelmen kívül hagyja a tárolt jelszót, újra bekéri |
| `-DeleteLogsAfterSend` | Küldés után törli a LOG fájlokat |

### Launcher.ps1

| Kapcsoló | Leírás |
|---|---|
| `-ConfigPath "C:\..."` | Egyedi config.json elérési út |
| `-ForceCredential` | Átadja a SendReport.ps1-nek |
| `-DeleteLogsAfterSend` | Átadja a SendReport.ps1-nek |

### InvokeDiagMailer.ps1

| Kapcsoló | Leírás |
|---|---|
| `-DiagMailerRepoUrl "..."` | Felülírja a beégetett GitHub clone URL-t |
| `-ForceCredential` | Átadja a SendReport.ps1-nek |
| `-DeleteLogsAfterSend` | Átadja a SendReport.ps1-nek |

### ManageCredential.ps1

| Kapcsoló | Leírás |
|---|---|
| `-Action Query` | Tárolt jelszó állapota, felhasználónév, fájl helye és dátuma |
| `-Action Update` | Régi jelszó törlése, új bekérése és mentése |
| `-Action Delete` | Tárolt jelszó törlése (munkamenet + fájl) |

---

## Jelszókezelés

A DiagMailer háromszintű, automatikus jelszómemóriát használ:

```
1. Munkamenet memória ($Global:DiagMailerCred)
      ↓ ha nem találja
2. DPAPI titkosított fájl (%LOCALAPPDATA%\DiagMailer\credential.xml)
      ↓ ha nem találja
3. Interaktív bekérés (Get-Credential ablak)
      ↓ megkérdezi: tartósan mentsük-e?
```

**A tárolás első beállításakor** (vagy `ManageCredential.ps1 -Action Update` futtatásakor) a rendszer megkérdezi:
- `[I]` → DPAPI titkosítással elmenti a `%LOCALAPPDATA%\DiagMailer\credential.xml` fájlba — csak ez a Windows-felhasználó olvashatja vissza, géphez kötött
- `[N]` → Csak a munkamenet memóriájában él (PowerShell ablak bezárásáig)

**Jelszókezelés a Launcher főmenüből:**

```
[2]  Jelszó állapota (lekérdezés)
[3]  Jelszó újrakonfigurálás
[4]  Tárolt jelszó törlése
```

**Fontos tudnivalók:**
- A DPAPI titkosítás **gépenként és felhasználónként egyedi** — más gépen/felhasználón nem olvasható vissza
- A `credential.xml` soha ne kerüljön a repóba (`.gitignore` kizárja)
- Az emelt jogosultságú (RunAs) folyamat **nem örökli** a munkamenet memóriát — tartós mentés ajánlott állandó gépeken
- Jelszócsere esetén: `Launcher.ps1` → `[3] Jelszó újrakonfigurálás`

---

## SMTP beállítások

### Gmail

```json
"smtpServer": "smtp.gmail.com",
"smtpPort": 587,
"useSSL": true
```

> ⚠️ **Gmail App-jelszó szükséges** — nem a Google-fiók rendes jelszava!
> Generálás (2FA bekapcsolt állapotban): https://myaccount.google.com/apppasswords

### Office 365 / Microsoft munkahelyi fiók

```json
"smtpServer": "smtp.office365.com",
"smtpPort": 587,
"useSSL": true
```

### Outlook.com / Hotmail (személyes Microsoft fiók)

```json
"smtpServer": "smtp-mail.outlook.com",
"smtpPort": 587,
"useSSL": true
```

### Brevo (ingyenes 300 email/nap)

```json
"smtpServer": "smtp-relay.brevo.com",
"smtpPort": 587,
"useSSL": true
```

> Felhasználónév: a Brevo-fiókon generált SMTP API-kulcs (nem a belépési jelszó)

### Saját/céges SMTP szerver

```json
"smtpServer": "mail.sajatceg.hu",
"smtpPort": 587,
"useSSL": true
```

---

## Jobb klikkes (helyi menü) integráció

### Telepítés

```powershell
.\Launcher.ps1
# → [5] Jobb klikk menü telepítése / eltávolítása
# → [1] Telepítés
```

A telepítő (`ContextMenuInstaller.ps1`) a következőket végzi el:
- Létrehozza a `C:\Windows\Scripts\DiagMailer\` mappát
- Átmásolja a `SendReport.ps1`-et és a `config.json`-t
- Regisztrálja a Windows helyi menübe
- Beállítja a Registry bejegyzéseket (`HKCR\Directory\shell` és `HKCR\Directory\Background\shell` és `HKCR\*\shell`)

### Használat telepítés után

Jobb klikk működik:
- **Mappán** (pl. `Micsi Pisti\`) → megkeresi a `LOG` almappát, és elküldi tartalmát
- **Mappa hátterén** (üres területen) → az aktuális mappa `LOG` almappáját küldi
- **Fájlon** (bármely fájlra jobb klikk) → a szülőmappa `LOG` almappáját keresi
- **Magán a LOG mappán** → felismeri, hogy ő maga a LOG mappa, és közvetlenül azt küldi

### Frissítés

Ha a DiagMailer fájljai frissülnek, a kontextusmenüt újra kell telepíteni (a `SendReport.ps1` másolata is frissül):

```powershell
.\Launcher.ps1 → [5] → [1] Telepítés (felülírja a régieket)
```

### Eltávolítás

```powershell
.\Launcher.ps1 → [5] → [2] Eltávolítás
```

---

## Más REPÓ-kba való beépítés

### 1. Másold be az `InvokeDiagMailer.ps1`-t a REPÓ gyökerébe

### 2. Írd át a GitHub URL-t benne:

```powershell
[string]$DiagMailerRepoUrl = "https://github.com/TE_NEVED/DiagMailer.git"
```

### 3. Hívd meg a menüdből:

```powershell
# Menü egyik pontja:
"5" {
    Write-Host "Jelentes kuldese..."
    & "$PSScriptRoot\InvokeDiagMailer.ps1"
}

# Vagy egy script végén automatikusan:
& "$PSScriptRoot\InvokeDiagMailer.ps1" -DeleteLogsAfterSend
```

### 4. Vedd fel a `.gitignore`-ba:

```
DiagMailer/config.json
DiagMailer/credential.xml
```

Az `InvokeDiagMailer.ps1` automatikusan:
- Megkeresi a `../DiagMailer/` mappát
- Ha nem találja: felajánlja a `git clone`-t a megadott URL-ről
- Ha a `config.json` hiányzik: átmásolja az `.example` sablont és megnyitja szerkesztésre
- Elindítja a `Launcher.ps1`-et vagy közvetlenül a `SendReport.ps1`-et

---

## 🚀 Használati módok

### 1. Interaktív futtatás (manuális indítás)

```powershell
.\Launcher.ps1
```

A főmenüből minden funkció elérhető: jelentés küldése, jelszókezelés, kontextusmenü telepítés.

### 2. Közvetlen küldés (azonnali, menü nélkül)

```powershell
# Alap küldés (config.json logFolder alapján):
.\SendReport.ps1

# Más LOG mappa küldése:
.\SendReport.ps1 -LogFolder "C:\Projektek\MasikRepo\LOG"

# Küldés után LOG fájlok törlése:
.\SendReport.ps1 -DeleteLogsAfterSend

# Jelszócsere kényszerítése:
.\SendReport.ps1 -ForceCredential
```

### 3. Jobb klikkes mód — az ügyfélbarát megoldás

1. Futtasd egyszer a `ContextMenuInstaller.ps1`-et rendszergazdaként az ügyfél gépén
2. Ezután az ügyfélnek csak **jobb klikkel** rá kell kattintania a projekt mappára, és ki kell választania a **"LOG kuldese (DiagMailer)"** opciót
3. A háttérben lefut a teljes folyamat, nincs szükség konzolos interakcióra

### 4. Automatizált / ütemezett futtatás

```powershell
# Feladatütemezőből, más scriptből hívva:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\DiagMailer\SendReport.ps1"

# Más REPÓ scriptjéből:
& "$PSScriptRoot\..\DiagMailer\SendReport.ps1" -DeleteLogsAfterSend
```

---

## 🛠️ Követelmények

- **Operációs rendszer:** Windows 7 / 8 / 10 / 11 vagy Windows Server
- **Környezet:** Windows PowerShell 3.0 vagy újabb (alapértelmezetten kompatibilis a beépített PowerShell 5.1-gyel)
- **Jogosultság:** Rendszergazda jogosultság szükséges a kontextusmenü telepítéséhez (az UAC automatikusan kéri)
- **Hálózat:** Kimenő SMTP forgalom engedélyezése a megadott porton (587 vagy 465)
- **Git:** Csak az `InvokeDiagMailer.ps1` automatikus letöltési funkciójához szükséges

## Windows verzió kompatibilitás

| Verzió | PowerShell | Állapot |
|---|---|---|
| Windows 11 | 5.1 beépített | ✅ Teljes |
| Windows 10 | 5.1 beépített | ✅ Teljes |
| Windows 7 | 2.0–5.1 (frissíthető) | ⚠ Részleges* |

*Win7: `Compress-Archive` csak PS 5.0+, `Send-MailMessage` TLS 1.2 korlátai lehetnek.
Modern SMTP szolgáltatók (Gmail, O365) **megkövetelnek TLS 1.2-t** — Win7-en ez nem mindig elérhető alapból.

---

## Biztonsági megjegyzések

- `config.json` mindig **GITIGNORE-ban** legyen — tartalmaz email-cím adatokat
- Az SMTP jelszó **soha** nem kerül a `config.json`-ba — a DPAPI `credential.xml` tárolja
- A `credential.xml` gépenként és felhasználónként egyedi — nem lehet "ellopni" és más gépen használni
- A DPAPI nem jelent abszolút védelmet — admin jogosultságú helyi támadó visszafejtheti
- Érzékeny ügyfél adatokat ne küldj titkosítatlan emailben (useSSL: true ajánlott)
- Nyilvános gépen ne használj tartós jelszótárolást (válaszd az `[N]` opciót)

---

## Verzió történet

| Verzió | Változás |
|---|---|
| **v3.5.1** | README dokumentáció javítás (config mezőnevek, fájlnév korrekciók) |
| **v3.5.0** | Config.ps1 varázsló — automatikus beállítás SMTP teszttel |
| **v3.4.0** | MotwCleaner-szerű kontextusmenü architektúra (C:\Windows\Scripts\DiagMailer\) |
| **v3.3.x** | Kontextusmenü (jobb klikk), fájlra/LOG mappára klikk támogatás, számos hibajavítás |

---

## Licenc

MIT – Szabad használat, módosítás, terjesztés, forrásmegjelöléssel.
