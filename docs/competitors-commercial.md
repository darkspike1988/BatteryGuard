# Kommerzielle Konkurrenzanalyse: macOS Akku- & Lademanagement

**Projekt:** BatteryGuard (macOS 14+, Apple Silicon)  
**Datum:** Oktober 2026  
**Fokus:** Kommerzielle und Closed-Source Wettbewerber, Feature-Vergleich, technische Machbarkeit & Roadmap für BatteryGuard unter Berücksichtigung von macOS 27.

---

## 1. Executive Summary & Marktlage

Der Markt für macOS Batterietools teilt sich in drei primäre Kategorien:
1. **Aktive Ladekontroll-Tools (Hardware-Eingriff via SMC / PMU):**
   - *AlDente (Pro)* dominiert als De-facto-Standard mit über 1 Mio. Downloads, gefolgt von *Energiza Pro* und *BatFi*.
   - **Preismodelle:** Trend weg vom reinen Einmalkauf hin zu Freemium mit Jahresabo (10–12 €/Jahr) bzw. Lifetime-Preisen (20–24 €) oder Setapp-Bündelung.
   - **Kernherausforderung macOS 27:** Apple hat in macOS 27 (sowie Sequoia/Tahoe) die historischen SMC-Sperr-Keys (`CHTE`, `CH0B`/`CH0C`) entfernt. Ein reines Halten am Netzteil ohne Laden bei beliebigem Prozentwert ist hardwareseitig blockiert; Third-Party-Tools müssen auf den **Pendel-Modus** (Trennen des Netzteils via `CHIE`) oder Apples native 80%-Systemgrenze ausweichen.
2. **Reine Diagnose- & Monitoring-Suiten:**
   - *coconutBattery (Plus)*, *Battery Health 3*, *iStat Menus 7*.
   - Kein Eingriff in die Ladeelektronik, dafür hohe Informationsdichte (Alterung, Coulomb-Historie, iOS/Bluetooth-Zustände, Energieverbraucher).
3. **UI- & Usability-Spezialisten:**
   - *Battery Buddy* beweist, dass ein emotionales, charmantes Design (animiertes Gesicht) enorme virale Verbreitung erzeugt.
   - *Amphetamine* und *Macs Fan Control* adressieren kritische Randbedingungen von Ladewerkzeugen: Ruhezustands-Blockade während Entladevorgängen und aktive thermische Entlastung per Lüftersteuerung.

BatteryGuard verfügt heute bereits über ein stabiles Fundament (Swift 6, SwiftUI MenuBarExtra, Root-LaunchDaemon, dateibasierte IPC, Ladebereich min/max, aktives Entladen via `CHIE`, Hitzeschutz, Einmal-Voll-Laden). Durch gezielte Adaption der besten kommerziellen Features kann BatteryGuard funktional mit AlDente Pro gleichziehen und dieses durch Open-Source-Transparenz und modernes Swift-Design übertreffen.

---

## 2. Profil der analysierten kommerziellen Apps

### 2.1 AlDente (Free vs. Pro) – AppHouseKitchen
- **Entwickler:** AppHouseKitchen GmbH (Österreich)
- **Preismodell:** 
  - Free: Kostenlos (stark beschnitten)
  - Pro Abo: **11,49 € / Jahr**
  - Pro Lifetime: **23,99 €** (Einmalkauf)
  - Setapp: Enthalten im **9,99 $ / Monat** Abo
- **Architektur:** GUI-App (Electron/Swift-Mischung historisch, heute nativer Popover) + Privileged Helper Tool (`com.apphousekitchen.aldente-helper`) mit Root-Rechten für SMC-Zugriffe.
- **Aktueller Stand (v1.39.x, Sept/Okt 2026):**
  - Kompletter Umbau der Ladesteuerung für macOS 27. Limits unter 80 % erfordern Pendel-Mechanismen oder spezielle Toggles.
  - Umfangreichste Featurepalette am Markt: Sailing Mode, Kalibrierung, Shortcuts, Power-Flow, MagSafe-LED-Steuerung, Schlafwächter.
- **Schwächen / Kritik:** Hoher RAM/CPU-Verbrauch im Vergleich zu schlanken Menüleisten-Tools, gelegentliche Konflikte mit dem macOS-Ruhezustand („lädt trotz Limit im Sleep auf 100 %“ in Free), BMS-Dekalibrierung ohne regelmäßige Vollzyklen.

### 2.2 Energiza & Energiza Pro – Appgineers
- **Entwickler:** appgineers.de (Deutschland)
- **Preismodell:**
  - Free: Reines Monitoring
  - Pro Monat: **1,49 $ / Monat** (2 Macs)
  - Pro Jahr: **9,99 $ / Jahr** (3 Macs)
  - Forever Pro (Lifetime): **19,99 $** (5 Macs, 30 Tage Testphase)
- **Architektur:** Native Swift-App + Privileged Helper Tool.
- **Features:** Einstellbare Ladeober- und -untergrenzen, automatisches Entladen am Kabel, Hitzeschutz, manuelle 1-Klick-Pausierung, Benachrichtigungen bei Schwellenwerten.
- **Schwächen:** Weniger Automatisierungs-Features als AlDente (keine Kalibrierungs-Sequenz, keine Shortcuts-Intents, kein Power-Flow-Diagramm).

### 2.3 BatFi – Macked
- **Entwickler:** Macked (macked.app)
- **Preismodell:** Einmalkauf ca. **10,50 $** (Gumroad / Direct), teils via Setapp.
- **Architektur:** Schlanke native Apple Silicon App ab macOS Ventura.
- **Features:** Einfacher 80 % Ladeschutz, 1-Klick "Charge to 100%", Batteriestatus-Kacheln, automatische Ruhezustandserkennung.
- **Fokus:** Minimalistisch, zielt auf Nutzer ab, denen AlDente zu überladen und teuer ist.

### 2.4 Battery Buddy – Neil Sardesai
- **Entwickler:** Neil Sardesai (Indie-Entwickler, Twitter/X: @NeilSardesai)
- **Preismodell:** **100 % Kostenlos** (Freeware).
- **Architektur:** Reines User-Space-Tool ohne Helper, nutzt `IOPSCopyPowerSourcesInfo`.
- **Features:** Ersetzt das Menüleisten-Batterie-Icon durch einen animierten Emoji-Charakter:
  - Lächelndes Gesicht bei vollem/hohem Akku, neutral/besorgt bei mittlerem Stand, traurig/erschöpft bei < 20 %, glücklich mit Blitz beim Laden.
- **Bedeutung für BatteryGuard:** Zeigt die psychologische Kraft von UI-Delight. Die Integration eines optionalen Mascot-Modus erzeugt enorme Nutzerbindung.

### 2.5 Battery Health 3 – FIPLAB
- **Entwickler:** FIPLAB Ltd (UK)
- **Preismodell:** Kostenlose Testversion, Vollversion ca. **9,99 $ – 14,99 $** (Mac App Store / Direkt).
- **Architektur:** Sandboxed AppKit/Swift Menubar-App.
- **Features:** Detaillierte Akkudiagnose (Gesundheit, Zyklen, Alter, Temperatur, Milliamperestunden), historische Ladeverlaufs-Graphen, „Energy Hogs“ (Top-Verbraucher-Prozesse), iOS-Geräteanzeige.
- **Einschränkung:** **Keine** Ladekontrolle (kann das Laden nicht stoppen oder begrenzen).

### 2.6 coconutBattery & coconutBattery Plus – Christoph Sinai
- **Entwickler:** Christoph Sinai (coconut-flavour.com, Deutschland)
- **Preismodell:**
  - Free: Kostenlos (Mac- & USB-iOS-Basisdaten)
  - Plus: **17,95 €** (Lifetime-Lizenz)
- **Architektur:** Native Mac-App, liest tiefe IOKit-Register aus.
- **Features (Plus):** iOS/iPadOS-Überwachung über WLAN, Lifetime Battery History (Langzeit-Datenbank zur Kapazitätsdegradation über Jahre), HTML/PDF-Export von Diagnoseberichten, anpassbare Benachrichtigungen.
- **Einschränkung:** Reines Diagnosewerkzeug; kein Eingriff in Ladevorgänge.

### 2.7 iStat Menus 7 (Battery & Power Modul) – Bjango
- **Entwickler:** Bjango Pty Ltd (Australien)
- **Preismodell:** **11,99 $ – 13,99 $** Einmalkauf, Setapp (9,99 $/Mo).
- **Architektur:** Modulare System-Erweiterung + Daemon für Sensorabfragen.
- **Features:** Extrem anpassbare Menüleisten-Graphen, Watt-Anzeige, Bluetooth-Peripherie-Akkustände (Magic Mouse, Magic Keyboard, AirPods etc.), konfigurierbare Warnregeln (z. B. wenn Watt > Schwellenwert).
- **Einschränkung:** Umfassendes Systemmonitoring, aber keine Ladelimit-Steuerung.

### 2.8 Spezialisten: Macs Fan Control & Amphetamine
- **Macs Fan Control (CrystalIDEA):**
  - Liest Akku-Temperatursensoren via SMC (`TB0T`, `TB1T`, `TB2T`) und kann Gehäuselüfter gezielt hochdrehen, wenn der Akku beim Schnellladen warm wird.
- **Amphetamine (William Gustafson):**
  - Nutzt `IOPMAssertionCreateWithName`, um den Mac gezielt wachzuhalten. Für BatteryGuard kritisch: Verhindert, dass der Mac während eines aktiven Entladevorgangs oder Kalibrierungszyklus einschläft.

---

## 3. (1) Große Feature-Matrix

*Legende:*  
- ✅ = Vollständig vorhanden  
- 🟡 = Eingeschränkt / Nur manuell / Teillösung  
- ❌ = Nicht vorhanden  
- 💲 = Nur in der kostenpflichtigen Pro-Version  

| Feature / Fähigkeit | AlDente Free | AlDente Pro | Energiza Pro | BatFi | Battery Buddy | Battery Health 3 | coconutBattery Plus | iStat Menus 7 | BatteryGuard (Heute) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Kosten / Lizenz** | Kostenlos | 11,49€/J od. 24€ | 9,99$/J od. 20$ | ~10,50$ | Kostenlos | ~10–15$ | 17,95€ | ~12–14$ | **Open Source (MIT)** |
| **Hardware-Ladelimit (Max %)** | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ (`upperLimit`) |
| **Untergrenze / Wiedereinschaltwert** | ❌ | ✅ (Sailing) | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ (`lowerLimit`) |
| **Sailing Mode (Pendel-Laden/Hysterese)**| ❌ | ✅ 💲 | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ (nativ durch min/max) |
| **Manuelles Entladen am Netzteil** | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ (via Script/Toggle) |
| **Automatisches Entladen (> Limit)** | ❌ | ✅ 💲 | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ (`activeDischarge`) |
| **Entladen im Clamshell-Modus (Deckel zu)**| ❌ | ✅ 💲 | 🟡 | ❌ | ❌ | ❌ | ❌ | ❌ | 🟡 (nur bei externem Display) |
| **Akkutemperaturschutz (Heat Protection)**| ❌ | ✅ 💲 | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ (`heatProtectionCelsius`) |
| **Lüftersteuerung bei Akku-Hitze** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ (nur Macs Fan Control) |
| **Einmalig 100 % voll laden (Top-Up)** | ❌ | ✅ 💲 | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ (`chargeToFullOnce`) |
| **Kalibrierungsmodus (100%→10%→100%)** | ❌ | ✅ 💲 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ (Roadmap) |
| **Echte Hardware-% (BMS vs UI-Glättung)**| ❌ | ✅ 💲 | 🟡 | ❌ | ❌ | ✅ | ✅ | ✅ | 🟡 (IOKit-Rohwert im Daemon) |
| **Laden im Sleep stoppen / Schlafwächter**| ❌ | ✅ 💲 | ✅ | 🟡 | ❌ | ❌ | ❌ | ❌ | 🟡 (Pendel-Modus bei AC) |
| **Sleep während Entladen/Kalibrierung blocken**| ❌ | ✅ 💲 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ (Amphetamine-Style nötig) |
| **Zeitsteuerung / Scheduler** | ❌ | ✅ 💲 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **Low Power Mode Automation (pmset)** | ❌ | ✅ 💲 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **Apple Shortcuts / AppIntents / Siri** | ❌ | ✅ 💲 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **Echtzeit Power-Flow Diagramm (Sankey)**| ❌ | ✅ 💲 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **MagSafe 3 LED Status-Steuerung** | ❌ | ✅ 💲 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **macOS Desktop / Sperrbildschirm Widgets**| ❌ | ✅ 💲 | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **Notch / Live Activity Akkuanzeige** | ❌ | ✅ 💲 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **Emotionale Mascot / Buddy-UI** | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **Energy Hogs (Top-Verbraucher Prozesse)**| ❌ | ✅ 💲 | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ |
| **Langzeit-Akkuhistorie & Degradations-Graph**| ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ 💲 | ❌ | ❌ |
| **Peripherie-Akkus (Maus, AirPods, etc.)**| ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ 💲 | ✅ | ❌ |
| **Moderne SMAppService-Registrierung** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ (heute: sudo install.sh) |
| **macOS 27 Kompatibilität (ohne CHTE/CH0B)**| 🟡 (v1.39) | ✅ (v1.39) | 🟡 | 🟡 | ✅ | ✅ | ✅ | ✅ | ✅ (autom. Pendel-Modus) |

---

## 4. (2) Beschreibung jedes sinnvollen Features

1. **Sailing Mode (Pendel-Laden / Schwellenband):**  
   Verhindert schädliche Mikro-Ladezyklen am oberen Limit, indem nach Erreichen des Limits (z. B. 80 %) erst wieder geladen wird, wenn der Akku unter einen unteren Schwellenwert (z. B. 75 %) fällt. Der Mac läuft dazwischen rein vom Netzteil oder Akku.
2. **Calibration Mode (BMS-Rekalibrierungszyklus):**  
   Führt automatisch einen vollständigen Zyklus (auf 100 % laden, 1 h halten, auf 10 % entladen, erneut auf 100 % laden) durch, um die Messgenauigkeit des Batterie-Controllers (Coulomb-Counter) wiederherzustellen, wenn der Mac monatelang nur bis 80 % geladen wurde.
3. **Hardware Battery Percentage (Ungeschönter Ladezustand):**  
   Liest den exakten chemischen Ladestand direkt aus dem Hardware-Register aus, statt der von Apple geglätteten und verzögerten Prozentanzeige der macOS-Menüleiste zu vertrauen.
4. **Automatic Discharge (Automatisches Absenken auf Ziellimit):**  
   Trennt bei eingestecktem Netzteil die Stromzufuhr softwareseitig, sobald der Akku über dem eingestellten Limit liegt (z. B. nach mobilem Einsatz mit 100 %), und stellt die Netzversorgung bei Erreichen des Zielwerts wieder her.
5. **Heat Protection (Temperatur-Ladestopp):**  
   Pausiert den Ladevorgang sofort, sobald die Akkutemperatur einen kritischen Schwellenwert (z. B. 38–42 °C) überschreitet, da das Laden bei hohen Temperaturen die Zellalterung exponentiell beschleunigt.
6. **Lüfter-gestützte Kühlung (Macs Fan Control Integration):**  
   Aktiviert bei Erwärmung des Akkus während des Ladens die internen Lüfter auf eine moderate Drehzahl, um die Temperatur unter dem Abschaltschwellenwert zu halten, ohne das Laden unterbrechen zu müssen.
7. **Top-Up (Einmaliges Vollladen mit Rückfall):**  
   Erlaubt es dem Nutzer per Klick, den Akku vor einer anstehenden Reise einmalig auf 100 % zu laden, und schaltet den Ladeschutz nach Erreichen des vollen Stands oder nach dem Abstecken automatisch wieder scharf.
8. **Stop Charging When Sleeping / Schlafwächter:**  
   Verhindert, dass das MacBook im zugeklappten Ruhezustand heimlich auf 100 % durchlädt, indem vor dem Eintritt in den Schlafzustand der Netzteil-Inhibit aktiviert oder eine periodische Überwachung gehalten wird.
9. **Sleep-Assertion bei Entladung/Kalibrierung (Amphetamine-Prinzip):**  
   Hält das System über `IOPMAssertionCreateWithName` temporär wach, solange eine aktive Entladung oder Kalibrierung läuft, da ein schlafender Mac im Standby mit nur 0,5 Watt sonst Tage für die Entladung bräuchte.
10. **Scheduler (Zeitbasierte Ladepläne):**  
    Ermöglicht zeitgesteuerte Ladezustände (z. B. nachts Schonung bei 60 %, morgens um 07:30 Uhr Top-Up auf 100 % vor der Fahrt ins Büro).
11. **Low Power Mode Automation:**  
    Schaltet den systemweiten macOS-Stromsparmodus beim Abziehen des Netzteils automatisch ein und beim Wiederanstecken aus, um die mobile Laufzeit ohne manuelles Zutun zu maximieren.
12. **Apple Shortcuts & AppIntents / Siri:**  
    Macht Ladebefehle („Lade auf 100 %“, „Aktiviere Entladen“, „Aktueller Akkustand“) als native System-Aktionen für Kurzbefehle, Automatisierungen und Siri-Sprachbefehle verfügbar.
13. **Power-Flow Diagramm (Echtzeit-Sankey):**  
    Visualisiert grafisch, wie viele Watt aktuell vom Ladegerät ins System fließen, wie viel direkt in den Akku wandert oder wie viel Leistung der Mac im Akkubetrieb zieht.
14. **MagSafe 3 LED-Feedback:**  
    Schaltet die LED am MagSafe-Stecker auf Grün, sobald das Ladelimit erreicht ist und das Laden pausiert wird, bzw. auf Orange während aktiver Ladung oder Entladung.
15. **Desktop & Sperrbildschirm Widgets (WidgetKit):**  
    Zeigt Ladezustand, Akkugesundheit und Restzeit direkt auf dem macOS-Schreibtisch oder im Mitteilungszentrum an – inklusive interaktiver Buttons zum Auslösen von Top-Up.
16. **Notch / Live Activity Akkubalken:**  
    Nutzt den Bereich um die MacBook-Kamerakerbe (Notch) für eine dezente, elegante Lade- und Statusanimation bei Zustandsänderungen.
17. **Emotionale Mascot / Buddy-UI (Battery Buddy Stil):**  
    Verleiht der App Charakter durch ein minimales Gesichtssymbol in der Menüleiste, das auf Akkustand und Gesundheit mit sympathischen Ausdrücken reagiert.
18. **Energy Hogs (Top-Verbraucher Prozesse):**  
    Analysiert laufende Programme und zeigt die 3 bis 5 Apps mit dem höchsten aktuellen Energieverbrauch an, um Akkufresser schnell identifizieren zu können.
19. **Langzeit-Degradationshistorie (coconutBattery Stil):**  
    Speichert tägliche Snapshots von Maximalkapazität und Ladezyklen in einer lokalen Datenbank und stellt den Alterungsverlauf in einem Verlaufsdiagramm dar.
20. **Bluetooth-Peripherie Akkuüberwachung:**  
    Liest die Ladestände von verbundenen Apple-Geräten (Magic Keyboard, Magic Mouse, Trackpad, AirPods) aus und zeigt sie übersichtlich im Menü an.
21. **SMAppService (Moderner LaunchDaemon-Installer):**  
    Ersetzt fehleranfällige manuelle Terminal-Skripte (`sudo install-daemon.sh`) durch Apples offizielle macOS 13+ ServiceManagement-API mit nativer Authentifizierungsaufforderung.

---

## 5. (3) Machbarkeitstabelle für BatteryGuard

Die folgende Tabelle analysiert alle identifizierten Features hinsichtlich ihrer Eignung und Umsetzbarkeit in BatteryGuard.

*Kriterien:*
- **Aufwand:** **S** (1–3 Tage), **M** (1–2 Wochen), **L** (3+ Wochen)
- **Risiko macOS 27:** Bewertung der Systemstabilität und Apple-Einschränkungen (speziell SMC-Keys)
- **Priorität:** **Must** (gehört zum Kernprodukt), **Should** (starker Mehrwert/Wettbewerbsvorteil), **Nice** (optischer/ergänzender Bonus)

| Feature | Nutzen für BatteryGuard | Aufwand | Benötigte Technik | Risiko macOS 27 | Priorität | Konkrete Umsetzungsskizze für BatteryGuard |
| :--- | :--- | :---: | :--- | :---: | :---: | :--- |
| **Sailing Mode (Hysterese)** | Kernkompetenz: Schont Zellen vor Mikroladungen am Limit | **S** | SMC (`CHIE`), Shared Config | **Gering** | **Must** | Bereits in `BGConfig` vorhanden (`lowerLimit` & `upperLimit`). UI um intuitiven Hysterese-Regler ergänzen (z. B. „Laden bis 80 %, wieder laden ab 75 %“). Auf macOS 27 läuft dies exakt über den bereits implementierten Pendel-Modus. |
| **Hardware Battery %** | Exaktere Steuerung ohne macOS-UI-Verzögerung | **S** | IOKit-Registry (`AppleSmartBattery`) | **Sehr gering** | **Must** | Im Daemon `AppleSmartBattery` auslesen (`AppleRawCurrentCapacity` / `AppleRawMaxCapacity` oder `CurrentCapacity` / `MaxCapacity`). Rohwert als `hardwarePercent` in `status.json` ablegen; App zeigt optional beide Werte an. |
| **Sleep-Assertion (Amphetamine)** | Verhindert Einschlafen während Entladen / Top-Up | **S** | Public API (`IOPMLib.h` / `IOPMAssertionCreateWithName`) | **Keines** | **Must** | Wenn `activeDischargeAboveUpper == true` oder `chargeToFullOnce == true`, erstellt die Menüleisten-App eine `kIOPMAssertionTypePreventUserIdleSystemSleep`-Assertion. Sobald Zielwert erreicht, Freigabe via `IOPMAssertionRelease`. |
| **Top-Up (Einmal voll)** | Komfortables Vollladen vor Reisen | **S** | Public API, `Shared.swift` | **Keines** | **Must** | Ist als `chargeToFullOnce` im Vertrag definiert. UI erhält prominenten 1-Klick-Button in der Menüleiste. Daemon setzt `chargeToFullOnce = false` nach Erreichen von 100 % in `config.json` zurück. |
| **Automatisches Entladen** | Bringt vollen Akku am Schreibtisch schonend auf Limit | **S** | SMC (`CHIE`), Daemon Logic | **Gering** | **Must** | Im Vertrag als `activeDischargeAboveUpper` vorhanden. Daemon schaltet bei `percent > upperLimit` das Netzteil ab (`CHIE = 1`), bis `upperLimit` erreicht ist, und schaltet dann auf Halten/Pendeln. |
| **Calibration Mode** | Verhindert Drift des Coulomb-Counters bei Dauer-80% | **M** | SMC (`CHIE`), Sleep-Assertion, State Machine | **Gering** | **Should** | Neuer State `calibration` in `BGChargeState`. Daemon steuert Schrittkette: 1. Laden auf 100 %, 2. 60 Min halten, 3. `CHIE = 1` bis 10 %, 4. Laden auf 100 %, 5. Zurück auf konfiguriertes Limit. Statusfortschritt in `status.json`. |
| **Low Power Mode Automation** | Spart mobil Akku, schont Ladezyklen | **S** | Public API / CLI (`pmset -b lowpowermode 1`) | **Gering** | **Should** | Daemon überwacht `pluggedIn`. Bei Wechsel auf Akkubetrieb führt der Daemon (als root) `pmset -b lowpowermode 1` aus, am Netzteil `pmset -c lowpowermode 0`. Konfigurierbar über Boolean in `BGConfig`. |
| **SMAppService Migration** | Installation ohne Terminal-Skripte direkt aus App | **S** | Public API (`ServiceManagement.SMAppService`) | **Gering** | **Should** | Ersetzen des `install-daemon.sh`-Aufrufs durch `SMAppService.daemon(plistName: "com.batteryguard.daemon.plist").register()`. Native macOS-Passwortabfrage, moderner Standard ab macOS 13+. |
| **Apple Shortcuts / AppIntents** | Automatisierung via macOS Kurzbefehle & Siri | **M** | Public API (`AppIntents` Framework) | **Keines** | **Should** | Neue Datei in der App: `BatteryGuardIntents.swift`. Aktionen: `SetChargeLimitIntent`, `TriggerTopUpIntent`, `ToggleActiveDischargeIntent`, `GetBatteryStatusIntent`. Ermöglicht CLI (`shortcuts run`) und Siri-Steuerung ohne Extra-Code. |
| **Energy Hogs Anzeige** | Schneller Überblick über akkufressende Prozesse | **M** | Public API (`IOKit` / `libproc` / `IOPSCopyPowerSourcesInfo`) | **Gering** | **Should** | App liest via `IOPSCopyPowerSourcesInfo` die Liste der `ProcessesUsingSignificantEnergy` aus und zeigt die Top 3 Apps als kleine Liste im Popover an. |
| **Langzeit-Degradations-Graph** | Transparenz über Batterieverschleiß über Monate | **M** | Swift Charts, SQLite / JSON History | **Keines** | **Should** | App oder Daemon speichert 1x täglich einen Datenpunkt (`Date`, `healthPercent`, `cycleCount`, `maxCapacityRaw`) in `history.json`. SwiftUI View stellt die Kurve via Apple Swift Charts dar. |
| **Power-Flow Diagramm (Sankey)** | Veranschaulicht Stromverteilung (Netz→Akku/Mac) | **M** | IOKit-Registry (`AppleSmartBattery`), SwiftUI Canvas | **Gering** | **Should** | Auslesen von `Watts` aus `AdapterDetails` und `InstantAmperage * Voltage` aus `AppleSmartBattery`. Systemverbrauch = `AdapterWatt - LadeWatt`. Animierte Fluss-Grafik im Popover. |
| **Emotionale Mascot / Buddy-UI** | Beliebtes Alleinstellungsmerkmal / Delight | **S** | SwiftUI Vector Animation / SF Symbols | **Keines** | **Should** | Optionales Menüleisten-Icon: Ein kleiner Akku mit Gesicht, der bei 80 % (geschützt) zufrieden lächelt, beim aktiven Entladen schwitzt und bei Hitze ein rotes Thermometer einblendet. |
| **Lüfter-Kühlung bei Hitze** | Verhindert Ladeabbruch an warmen Sommertagen | **M** | SMC (Fan-Keys `F0Tg`, `FS! `) | **Mittel** | **Nice** | Wenn `temperatureCelsius > heatProtectionCelsius - 3`, setzt der Root-Daemon die Lüfter auf 3.500 RPM. Erst wenn Temperatur trotzdem steigt, greift der Ladestopp. Achtung: MacBook Air hat keine Lüfter (Guard nötig). |
| **Schlafwächter (Sleep Inhibit)** | Verhindert Überladen im Ruhezustand | **M** | IOKit Power Management (`IORegisterForSystemPower`) | **Mittel** | **Should** | Daemon registriert Callback für `kIOMessageSystemWillSleep`. Wenn `percent >= upperLimit`, setzt der Daemon unmittelbar vor dem Schlafen `CHIE = 1`, sodass der Mac im Schlaf nicht lädt. |
| **Scheduler (Zeitpläne)** | Automatische Ladeanpassung nach Tageszeit | **M** | Public API (`Foundation.Timer` / BackgroundTasks) | **Keines** | **Nice** | In `BGConfig` Zeitplan-Array hinterlegen (z. B. Mo–Fr ab 07:00 Top-Up). App oder Daemon prüft Uhrzeit und passt `upperLimit` temporär an. |
| **Desktop / Lockscreen Widgets** | Schneller Statusüberblick ohne Klick | **M** | WidgetKit, App Group / Shared File | **Gering** | **Nice** | WidgetKit-Extension erstellen. Da Widgets in der Sandbox laufen, liest das Widget entweder über App-Group-Container oder über einen leichtgewichtigen XPC/File-Zugriff die `status.json`. |
| **Bluetooth-Peripherie Akkus** | Komfort-Feature für Tastatur/Maus/AirPods | **M** | `IOBluetooth` Framework | **Keines** | **Nice** | App fragt gekoppelte Bluetooth-Geräte ab und zeigt Akkustände im unteren Popover-Bereich an. Reines UI-Feature, keine Daemon-Beteiligung nötig. |
| **Notch / Live Activity Balken** | Moderner Hingucker bei Ladestatuswechsel | **M** | AppKit (`NSPanel`), Safe-Area-Screen-Geometrie | **Gering** | **Nice** | Rahmenloses `NSPanel` auf Level `.statusBar` um die Bildschirm-Notch herum platzieren. Zeigt beim Anstecken einen kurzen grünen Puls oder Ladebalken. |
| **MagSafe 3 LED-Steuerung** | Status-Rückmeldung direkt am Stecker | **L** | SMC (undokumentierte LED-Register) | **Sehr hoch** | **Nice** | Auf Apple Silicon (M-Serie) wird die MagSafe-LED maßgeblich vom USB-C-PD-/PMU-Controller gesteuert. Manipulation via SMC ist instabil, führt zu Fehlfunktionen oder Firmware-Resets. Vorläufig verwerfen. |

---

## 6. Spezifische Herausforderungen auf macOS 27

Auf macOS 27 gelten veränderte Spielregeln für die Akkukontrolle:
1. **Verlust der Halte-Keys (`CHTE`, `CH0B`/`CH0C`):**
   - Auf Intel und früheren Apple-Silicon-Versionen konnte die Ladeelektronik über `CHTE = 1` angewiesen werden, den Akku nicht mehr zu laden, während das Netzteil weiterhin das Mainboard versorgte (reiner Bypass).
   - In macOS 27 fehlen diese Keys. Third-Party-Tools (inkl. AlDente 1.39) können das Laden am Kabel nur noch über den Netzteil-Hauptschalter (`CHIE`) stoppen.
   - **Konsequenz für BatteryGuard:** Der bereits eingebaute **Pendel-Modus** ist die einzig verlässliche technische Lösung. Das Entladen erfolgt bewusst in einer Hysterese-Spanne (z. B. von 80 % runter auf 75 %), woraufhin das Netzteil kurz zuschaltet und wieder bis 80 % lädt.
2. **Apples nativer 80 % Ladeschutz:**
   - Apple bietet in macOS 27 in den Systemeinstellungen ein natives Ladelimit (fest auf 80 % oder adaptive Stufen).
   - *Abgrenzung für BatteryGuard:* Apples System schützt nicht vor Hitze, erlaubt kein individuelles Limit (z. B. 60 % oder 70 % für Dauer-Dock-Betrieb), bietet kein aktives Entladen von 100 % auf 80 % und keine Kalibrierungszyklen. Hier liegt das Differenzierungspotenzial.
3. **Ruhezustand & DarkWake:**
   - Im Ruhezustand (Deep Sleep) schläft auch der Root-Daemon teilweise ein oder wird durch DarkWake-Phasen unterbrochen.
   - Wenn `CHIE` vor dem Einschlafen gesetzt wurde, bleibt der Adapter getrennt. Wichtig ist jedoch, die Power-Assertion (`IOPMAssertionCreateWithName`) sauber zu nutzen, damit aktive Prozesse nicht im Tiefschlaf verhungern.

---

## 7. Quellenverzeichnis

1. **AlDente & AppHouseKitchen:**
   - Offizielle Pricing- & Feature-Übersicht: <https://apphousekitchen.com/pricing/>
   - AlDente GitHub Repository & Releases (v1.39): <https://github.com/AppHouseKitchen/AlDente-Battery_Care_and_Monitoring>
   - Sailing Mode Dokumentation: <https://apphousekitchen.com/feature-explanation-sailing-mode/>
   - Calibration Mode Dokumentation: <https://apphousekitchen.com/feature-explanation-calibration-mode/>
   - Hardware Battery Percentage: <https://apphousekitchen.com/hardware-battery-percentage/>
   - MagSafe LED Steuerung: <https://apphousekitchen.com/magsafe-led-control/>
   - Power-Flow Feature: <https://apphousekitchen.com/feature-explanation-power-flow/>
2. **Energiza Pro (appgineers):**
   - Offizielle Produktseite & Preise: <https://appgineers.de/energiza/>
   - Featureübersicht & Support: <https://appgineers.de/energiza/faq/>
3. **BatFi:**
   - Offizielle Produktseite: <https://macked.app/batfi/>
   - BatFi Repository: <https://github.com/macked/batfi>
4. **Battery Buddy:**
   - Projektseite: <https://batterybuddy.app>
   - Entwicklerprofil Neil Sardesai: <https://github.com/NeilSardesai>
5. **Battery Health 3:**
   - FIPLAB Produktseite: <https://fiplab.com/apps/battery-health-3-for-mac>
6. **coconutBattery:**
   - Offizielle Website (Christoph Sinai): <https://www.coconut-flavour.com/coconutbattery/>
7. **iStat Menus:**
   - Bjango iStat Menus 7: <https://bjango.com/mac/istatmenus/>
8. **Ergänzende Tools & System-Dokumentation:**
   - Macs Fan Control (CrystalIDEA): <https://crystalidea.com/macs-fan-control>
   - Amphetamine (William Gustafson): Mac App Store
   - Apple Developer Documentation – `IOPMLib` & `IOPMAssertionCreateWithName`: <https://developer.apple.com/documentation/iokit/iopmlib_h>
   - Apple Developer Documentation – `SMAppService`: <https://developer.apple.com/documentation/servicemanagement/smappservice>
