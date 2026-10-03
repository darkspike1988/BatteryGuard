# Open-Source-Konkurrenzanalyse & Architekturstudie für BatteryGuard

> **Status:** Analysiert im Oktober 2026 für `BatteryGuard` (macOS 15–27 / Apple Silicon & Intel).  
> **Fokus:** Open-Source-Tools zur Ladebegrenzung und Akkusteuerung auf macOS, Architekturvergleiche (XPC vs. JSON), SMC-Mechaniken, reale Bugs/Fallen aus GitHub-Issues und konkrete Swift-Machbarkeitsbewertungen.

---

## 1. Executive Summary & Ausgangslage von BatteryGuard

`BatteryGuard` verfügt aktuell über eine modulare Architektur:
* **UI-Layer:** Native Swift/SwiftUI Menüleisten-App mit modernem Liquid-Glass-Design, Live-Tiles und Benachrichtigungen.
* **Privileged Layer:** Root-`LaunchDaemon` (`batteryguardd`), der periodisch (20 s) und ereignisgesteuert (`IOPSNotificationCreateRunLoopSource`) läuft.
* **IPC-Vertrag:** Zwei JSON-Dateien (`config.json` 0666, `status.json` 0644 in `/Library/Application Support/BatteryGuard/`).
* **SMC-Engine:** Direkter IOKit-Client (`AppleSMC`), der `CHTE` (4-Byte), `CH0B`/`CH0C` (1-Byte) für Ladestopp sowie `CHIE`/`CH0J`/`CH0I` für Adapter-Abschaltung (aktives Entladen / Pendel-Modus) ansteuert.

Mit dem Erscheinen von **macOS 26.4+ und macOS 27 (Golden Gate)** hat Apple fundamentale Änderungen an der SMC-Schnittstelle vorgenommen:
1. Native Ladebegrenzung (80–100%) in den Systemeinstellungen.
2. In macOS 27 (ab Firmware `20457.0.125.0.2` / Beta 4) wurden die direkten Ladeschlüssel (`CHTE`, `CH0B`, `CH0C` sowie `bfF0`/`bfD0`/`bfE0`) durch die private Entitlement-Prüfung `com.apple.private.iokit.soc-limit` für Drittanbieter-Root-Prozesse mit `kIOReturnNotPrivileged` blockiert.
3. Der Netzteil-Schalter (`CHIE` / `CH0J` / `CH0I`) bleibt weiterhin schreibbar – der von BatteryGuard bereits implementierte **Pendel-Modus** ist daher zukunftssicher, bringt aber spezifische physikalische und logische Herausforderungen mit sich (Clamshell-Sleep, Entladeströme, Display-Sleep).

Diese Analyse untersucht die führenden Open-Source-Projekte, extrahiert deren Best Practices, Sicherheitskonzepte und Fehlerbehebungen und übersetzt sie in konkrete Handlungsempfehlungen für BatteryGuard.

---

## 2. Detaillierte Einzelanalyse der Open-Source-Projekte

### 2.1 `charlie0129/batt`
* **Repository:** [github.com/charlie0129/batt](https://github.com/charlie0129/batt)
* **Technologie:** Go (CLI & Daemon) + Swift (Menüleisten-GUI), IOKit, Apple Silicon fokusiert.
* **Architektur:** Client-Server-Modell über **Unix Domain Socket** (`/var/run/batt.sock` bzw. HTTP/JSON-RPC). Der Root-Daemon kapselt SMC-Zugriffe und Powermanagement.
* **Herausragende Features:**
  * **MagSafe-LED-Steuerung (`ACLC`):** Ändert die LED-Farbe des MagSafe-3-Steckers (`03` = Grün bei Erreichen des Ladelimits, `04` = Orange beim Laden, `01` = Aus beim aktiven Entladen, `00` = System-Automatik).
  * **Umfangreiches Sleep-Handling:** Verhindert Sleep-Probleme über `pmset disablesleep 1` und `IOPMAssertionCreateWithName`.
  * **Adapter-Mode für macOS 27:** Automatische Erkennung geschützter SMC-Keys und Umschaltung auf Hysterese-gesteuertes Trennen des Netzteils (`CHIE 08` / `CHIE 00`).
  * **Auto-Kalibrierung (Experimental):** Entlädt kontrolliert auf einen Minimalwert, lädt auf 100%, hält diesen Zustand für 1–3 Stunden und kehrt dann zum Limit zurück.
  * **DarkWake-Filterung:** Fängt periodische macOS DarkWake-Events ab, um ein versehentliches Wiederanlaufen des Ladevorgangs im Ruhezustand zu verhindern.

### 2.2 `actuallymentor/battery`
* **Repository:** [github.com/actuallymentor/battery](https://github.com/actuallymentor/battery)
* **Technologie:** Bash-Skripting (`battery.sh`) + vorkompilierte SMC-Binary (`smcFanControl`-Fork) + Node.js/Electron/Swift Tray Wrapper.
* **Architektur:** Privilegien-Verwaltung über `sudoers.d`-Eintrag (`/private/etc/sudoers.d/battery`) mit `NOPASSWD` für spezifische SMC-Schreibaufrufe.
* **Herausragende Features:**
  * **Maintain Range (Hysterese):** `battery maintain 70-80` erlaubt freie Wahl von unterem und oberem Schwellenwert.
  * **Spannungs-Modus (`voltage mode`):** Erlaubt Definition des Ladelimits in Millivolt/Volt (z. B. `11.4V` mit Hysterese `0.2V`), um physikalische Zellspannung direkt zu überwachen anstelle des driftenden Prozentsatzes.
  * **Discharge & Calibrate:** Script-gesteuerte Entladung auch bei geschlossenem Deckel.
  * **Einfache CLI-Schnittstelle:** Sehr eingängige Befehle (`battery maintain 80`, `battery charging on/off`, `battery adapter on/off`, `battery status`).

### 2.3 `mhaeuser/Battery-Toolkit`
* **Repository:** [github.com/mhaeuser/Battery-Toolkit](https://github.com/mhaeuser/Battery-Toolkit)
* **Technologie:** 100% Native Swift/Objective-C, Cocoa, Apple Silicon.
* **Architektur:** Modernster Apple-Standard via **`SMAppService.daemon`** und **XPC** (`NSXPCConnection`).
* **Herausragende Features & Sicherheitsmodell:**
  * **`BTXPCValidation.swift` (Gold-Standard für XPC-Sicherheit):** Überprüft jede eingehende XPC-Verbindung im Daemon mittels Audit-Token (`SecCodeCopyGuestWithAttributes`) und `connection.setCodeSigningRequirement`. Schützt vollständig gegen unbefugte lokale Privilege Escalation.
  * **Power-Adapter-Disable & Sleep-Sperre:** Verhindert System-Sleep, während das Netzteil softwareseitig deaktiviert ist, um unbeabsichtigtes Ausschalten von Peripheriegeräten und Displays zu vermeiden.
  * **Saubere Deinstallation:** Integrierte Funktionen zum vollständigen Deregistrieren des Daemons und Wiederherstellen der SMC-Hardware-Defaults.

### 2.4 `Ednk-1312/BatteryControl`
* **Repository:** [github.com/Ednk-1312/BatteryControl](https://github.com/Ednk-1312/BatteryControl)
* **Technologie:** Swift, SwiftUI, separater LaunchDaemon via `SMAppService` oder Paket-Installer, CLI-Binary `batterycontrol`.
* **Herausragende Features:**
  * **Readback-Verifikation:** Jeder Schreibvorgang auf SMC-Register wird unmittelbar zurückgelesen und validiert. Schlägt das Schreiben fehl oder überschreibt `powerd` den Wert, meldet die App ehrlich den Zustand "Unverified".
  * **Sicherheits-Floor beim Entladen:** Verhindert aktives Entladen unter 20%, es sei denn, der Nutzer bestätigt explizit einen Sicherheitsdialog ("Remove safety floor").
  * **Feste Presets:** "Daily (80/70)", "Battery Saver (70/60)", "Chronically Plugged In (50/48)" (ideal für Desktop-Dauerbetrieb), "Full Charge".
  * **Ablaufender 100%-Override:** Ein temporäres Vollladen endet nicht nur bei 100%, sondern besitzt einen Timeout (1h oder 2h), falls der Akku die 100% nicht erreicht.
  * **Sanitized Support-Bundle:** Bündelt anonymisierte SMC-Dumps und Logs als JSON für Fehlerberichte.

### 2.5 `TY-teo/ChargeWatching` (ChargeWatch)
* **Repository:** [github.com/TY-teo/ChargeWatching](https://github.com/TY-teo/ChargeWatching)
* **Technologie:** Swift 5.9 / SwiftUI, Menüleisten-App, LaunchDaemon (`com.chenran.chargewatch.helper`).
* **Herausragende Features:**
  * **Echtzeit-Leistungsmessung (3-Wege-Splitting):** Berechnet aus IOKit-Rohdaten die Momentanleistung in Watt:
    1. *Batterieleistung:* Ladung (+) oder Entladung (-).
    2. *System-Eigenverbrauch:* Momentane Last des Macs.
    3. *Netzteil-Ausgangsleistung:* Tatsächlich aus der Steckdose gezogene Leistung (nicht Nennwert des Adapters).
  * **Konsequentes "Stop Charging without Discharging":** Priorisiert klares Halten via `CHTE` gegenüber dem netzteil-trennenden Pendeln.
  * **7-Tage-Vollade-Kalibrierungs-Timer:** Schlägt nach 7 Tagen statischem 80%-Betrieb automatisch eine Vollladung vor, um die De-Kalibrierung des SoC-Messchips zu verhindern.
  * **Lokale SQLite-Historie:** Speichert Watt- und Ladeverläufe lokal für Diagramme ohne Telemetrie.

### 2.6 `exelban/stats` (Battery-Modul)
* **Repository:** [github.com/exelban/stats](https://github.com/exelban/stats)
* **Technologie:** Swift, Menüleisten-Allrounder.
* **Architektur-Erkenntnisse:**
  * Nutzt IOKit für Standard-Akkutelemetrie und einen privilegierten Helper (`eu.exelban.Stats.SMC.Helper`) für Lüfter/SMC-Schreibzugriffe.
  * **Sicherheitsfallstrick (CVE-2025-23202):** Unzureichende Prüfung in `shouldAcceptNewConnection` erlaubte beliebigen lokalen Prozessen die Verbindung zum Helper. Zeigt drastisch, dass ein schlecht konfigurierter XPC-Dienst unsicherer ist als eine strikte JSON-Datei mit Root-Rechten.

### 2.7 Weitere beachtenswerte Projekte
* **`srimanachanta/Stasis`:** Swift/SwiftUI Menubar-App für Apple Silicon mit animiertem Power-Flow-Diagramm, "Sailing Mode" (Hysterese-Band) und automatischem Entladen.
* **`MagHue`:** Fokussiert sich ausschließlich auf die MagSafe-LED-Steuerung (`ACLC`) und zeigt die saubere Integration als Background-Agent.
* **`zackelia/bclm`:** C/Swift CLI für Intel-Macs (`BCLM`-Key, 1 Byte Hex-Prozentwert).

---

## 3. Umfassende Feature-Matrix

| Feature / Fähigkeit | BatteryGuard | batt | battery | Battery-Toolkit | BatteryControl | ChargeWatch | stats |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Plattform / GUI** | Swift Menubar | Go CLI + Swift | Bash + Tray | Swift Menubar | SwiftUI + CLI | SwiftUI Menubar | Swift Menubar |
| **Apple Silicon Support** | Ja (M1–M5) | Ja | Ja | Ja | Ja | Ja | Ja |
| **Intel Mac Support** | Teilweise | Nein | Nein | Nein | Nein | Nein | Ja (BCLM/SMC) |
| **Ladebegrenzung (Upper Limit)** | Ja (5–100%) | Ja | Ja | Ja (min 50%) | Ja (Presets/Custom)| Ja (Presets) | Nein (nur Monitor) |
| **Unteres Limit (Hysterese)** | Ja (Lower Limit)| Ja (Delta) | Ja (Range) | Ja (min 20%) | Ja (Resume-Wert)| Ja (fest 5%) | — |
| **Aktives Entladen (CHIE)** | Ja | Ja | Ja | Ja | Ja | Nein | — |
| **macOS 27 Pendel-Fallback** | Ja (Auto) | Ja (Adapter Mode)| Nein | Eingeschränkt | Eingeschränkt | Nein | — |
| **MagSafe-LED-Steuerung (`ACLC`)** | **Nein** | Ja | Ja | Nein | Nein | Nein | — |
| **Kalibrierungs-Routine** | **Nein** | Ja (Auto) | Ja | Nein | Ja (3-Phasen) | Ja (7-Tage-Erinnerung)| — |
| **Clamshell Sleep-Prevention** | **Nein** | Ja (`pmset`) | Teilweise | Ja (IOPM) | Ja (Abbruch vor Sleep)| Nein | — |
| **Zeitpläne / Scheduler** | **Nein** | Nein | Nein | Nein | Nein | Nein | — |
| **Readback-Verifikation** | **Nein** | Teilweise | Nein | Teilweise | **Ja (strikt)** | Teilweise | — |
| **3-Wege-Leistungsmonitor (W)** | Teilweise (W) | Nein | Nein | Nein | Nein | **Ja (Akku/System/Wall)**| Ja (Standard) |
| **Spannungs-Modus (mV / V)** | **Nein** | Nein | Ja | Nein | Nein | Nein | — |
| **Historie / Trend-Graph** | **Nein** | Nein | Nein | Nein | Lokal JSON | Lokal SQLite | Graph im Menü |
| **Sicherheits-Floor (z.B. <20%)** | Implizit (5%) | Nein | Nein | 20% Hard Limit | Expliziter Toggle | Fest | — |
| **CLI-Interface** | Nur Daemon-Flags| Vollständig | Vollständig | Eingeschränkt | Vollständig | Nein | — |
| **Siri Shortcuts / AppIntents** | **Nein** | Nein | Nein | Nein | Nein | Nein | — |
| **IPC-Architektur** | JSON-Dateien | Unix Domain Sock| Sudoers / Files | XPC + SMAppService| XPC + SMAppService| Launchd Helper | XPC Helper |

---

## 4. Architektur-Vergleich: Privileged Helper / XPC vs. JSON-Dateien

### 4.1 Detailanalyse: BatteryGuards aktueller JSON-Ansatz
* **Ablauf:**
  * GUI schreibt `/Library/Application Support/BatteryGuard/config.json` (Dateirechte `0666`).
  * Daemon liest `config.json`, validiert Werte (`sanitized()`), steuert SMC und schreibt `status.json` (`0644`).
* **Vorteile:**
  * **Keine Apple Developer ID / Code-Signing-Zwang:** Läuft sofort in jeder Entwicklungsumgebung, bei Open-Source-Forks und lokalen Builds ohne Ad-Hoc-Zertifikatsprobleme.
  * **Einfaches Debugging:** Status und Konfiguration können direkt mit `cat`, `jq` oder Shell-Skripten inspiziert und manipuliert werden.
  * **Geringe Komplexität:** Keine Mach-Ports, keine XPC-Stubs, kein Objective-C-Runtime-Bridging nötig.
* **Sicherheits- & Robustheitsrisiken:**
  * **World-Writable Config (`0666`):** Jeder lokale Prozess (auch unprivilegierte Malware im User-Kontext) kann die `config.json` überschreiben. Zwar sanitisiert BatteryGuard die Werte (Bereichs-Clamping), aber Denial-of-Service (dauerhaftes Entladen des Akkus) ist theoretisch möglich.
  * **Dateisystem-Race-Conditions:** Paralleles Schreiben ohne atomare Locks kann zu fehlerhaftem JSON führen (`loadConfig()` greift dann auf Defaults zurück).
  * **Keine synchrone Befehlsausführung:** Die App erfährt erst beim nächsten Tick (bis zu 20 s Verzögerung) oder über einen `DispatchSourceFileSystemObject`-Watcher, ob die Hardware den Befehl akzeptiert hat.

### 4.2 Detailanalyse: Privileged Helper via XPC (`SMAppService.daemon`)
* **Ablauf:**
  * Die App bindet den Daemon als embedded Helper im Bundle ein (`Contents/Library/LaunchDaemons`).
  * Installation über modernen macOS-API-Aufruf: `try SMAppService.daemon(plistName: "com.batteryguard.daemon.plist").register()`.
  * Kommunikation über bidirektionalen `NSXPCConnection` mit striktem Protokoll (`BatteryGuardXPCProtocol`).
* **Vorteile:**
  * **Maximale Sicherheit:** Mittels `connection.setCodeSigningRequirement("anchor apple generic and identifier \"com.batteryguard.app\"")` oder Überprüfung des Audit-Tokens (`kSecGuestAttributeAudit`) kann der Daemon garantieren, dass **ausschließlich die signierte BatteryGuard-App** Befehle senden darf.
  * **Synchrone Methoden & Callbacks:** `remoteObjectProxy.setUpperLimit(80) { success, error in ... }` liefert sofortige Bestätigung inklusive Fehlercode.
  * **Kein Sudoers / Kein Root-Passwort bei jedem Start:** Eine einmalige Autorisierung über das macOS-Sicherheits-Popup bei Installation genügt.
* **Herausforderungen:**
  * Benötigt zwingend konsistentes Code-Signing zwischen App und Daemon (selbe Team-ID). Für reine Ad-Hoc Open-Source-Entwicklung ohne Developer-Account oft fehleranfällig.

### 4.3 Empfehlung für BatteryGuard: Der pragmatische 2-Stufen-Evolutionspfad

1. **Stufe 1 (Sofortmaßnahme – "Hardened File/Socket IPC"):**
   * Behalte die dateibasierte Einfachheit bei, aber härte sie ab:
   * Ändere die Rechte von `config.json` von `0666` auf `0644` (Owner: `root`, Group: `wheel` oder dedizierte User-Gruppe).
   * Die GUI sendet Schreibbefehle über einen **Unix Domain Socket** (`/var/run/batteryguard.sock`), der vom Daemon bereitgestellt wird. Der Daemon prüft über `getpeereid()` die UID des aufrufenden Prozesses (muss der aktuell angemeldete Konsolen-Benutzer sein).
   * Alternativ: Wenn JSON-Dateien bleiben sollen, schreibe atomar über temporäre Dateien (`replaceItemAt`) und schränke die Schreibberechtigung auf den aktuellen Konsolen-User ein (`fchmod`).

2. **Stufe 2 (Produktiv-Release / V1.0 – "SMAppService + XPC"):**
   * Sobald ein Signierungs-Zertifikat vorliegt, migriere den Daemon auf `SMAppService.daemon`.
   * Implementiere `BTXPCValidation` (wie von Battery-Toolkit vorgemacht), um CVE-Sicherheitslücken wie in `stats` auszuschließen.
   * Behalte die `status.json` als read-only Datei (`0644`) als Fallback für externe CLI-Tools und Skripte bei!

---

## 5. Konkrete Bugs & Fallen aus Issues (mit technischen Ursachen)

### Fallstrick 1: Clamshell Sleep-Crash bei CHIE / Force-Discharge
* **Referenz:** [actuallymentor/battery #20](https://github.com/actuallymentor/battery/issues/20), [charlie0129/batt README](https://github.com/charlie0129/batt)
* **Problem:** Wird bei geschlossenem MacBook-Deckel (Clamshell-Modus an externem Monitor) das Netzteil softwareseitig via `CHIE 08` getrennt, erkennt macOS sofort "AC disconnected" und schickt das MacBook augenblicklich in den Tiefschlaf. Externe Monitore werden schwarz.
* **Lösung:** Vor dem Setzen von `CHIE 08` muss eine Power-Assertion erstellt werden:
  ```swift
  IOPMAssertionCreateWithName(
      kIOPMAssertionTypePreventSystemSleep as CFString,
      IOPMAssertionLevel(kIOPMAssertionLevelOn),
      "BatteryGuard Clamshell Discharge" as CFString,
      &assertionID
  )
  ```
  Zusätzlich muss `batt`-analog geprüft werden, ob der Nutzer das Verhalten wünscht (`preventSleepOnAdapterDisable`).

### Fallstrick 2: Sofortiger Ruhezustand beim Wiedereinschalten des Netzteils
* **Referenz:** [mhaeuser/Battery-Toolkit Limitations](https://github.com/mhaeuser/Battery-Toolkit#limitations)
* **Problem:** Auf bestimmten Apple Silicon Firmware-Versionen führt das Zurückschalten von `CHIE 08` auf `CHIE 00` (Netzteil wieder verbinden) zu einem Kernel-Event, das den Mac direkt nach dem Reaktivieren schlafen legt ("Instant Sleep Bug").
* **Lösung:** Eine künstliche Verzögerung von 500 ms zwischen dem SMC-Schreibvorgang und der Freigabe von Power-Assertions schützt vor dem Kernel-Race.

### Fallstrick 3: SMC-Reset bei Shutdown & Cold Boot
* **Referenz:** [mhaeuser/Battery-Toolkit #15](https://github.com/mhaeuser/Battery-Toolkit/issues/15), [Ednk-1312/BatteryControl](https://github.com/Ednk-1312/BatteryControl)
* **Problem:** Beim vollständigen Herunterfahren oder Neustarten setzt der Apple-Silicon-Bootrom alle SMC-Register auf Werkseinstellungen zurück. Der Mac beginnt im ausgeschalteten Zustand *immer* sofort bis 100% zu laden.
* **Lösung:**
  * Der Daemon kann im ausgeschalteten Zustand softwareseitig nichts ausrichten.
  * Beim Booten muss `batteryguardd` jedoch mit `RunAtLoad = true` so früh wie möglich starten und die persistierte Konfiguration vor allen anderen Benutzerprozessen durchdrücken.
  * Verhindern von Micro-Bursts: War der Akku beim Booten bei 78% und das Limit liegt bei 80%, sollte der Daemon das Laden nicht panisch abbrechen, sondern bis zum Upper Limit durchladen lassen (wie in Battery-Toolkit gelöst).

### Fallstrick 4: DarkWake & Sleep-Wake Drift
* **Referenz:** [charlie0129/batt Sleep Docs](https://github.com/charlie0129/batt)
* **Problem:** Während des Ruhezustands wacht macOS periodisch im Hintergrund auf (DarkWake für Power Nap, Find My, Mail). Manche macOS-Versionen setzen dabei die SMC-Register zurück, wodurch der Akku unbemerkt auf 100% vollgepumpt wird.
* **Lösung:** Registrierung für `kIOMessageSystemWillPowerOn` / `kIOMessageSystemHasPoweredOn` via `IORegisterForSystemPower`. Bei jedem Aufwachen erzwingt der Daemon sofort einen erneuten SMC-Schreibzyklus.

### Fallstrick 5: Private Entitlement Sperre auf macOS 27 Beta 4+
* **Referenz:** [charlie0129/batt #152](https://github.com/charlie0129/batt/issues/152)
* **Problem:** Apple hat ab macOS 27 Beta 4 die Keys `CHTE`, `CH0B`, `CH0C`, `bfF0`, `bfD0`, `bfE0` hinter die private Entitlement `com.apple.private.iokit.soc-limit` gesperrt. Selbst `root` erhält `kIOReturnNotPrivileged`.
* **Lösung:**
  * Runtime-Probing: Bei Start testen, ob ein Schreibversuch auf `CHTE` erfolgreich ist.
  * Wenn nein: Nahtloser Fallback auf den **Adapter-Modus** (`CHIE`), wie BatteryGuard ihn im Pendel-Modus bereits vorbereitet hat.
  * Wenn der Nutzer im Bereich 80–100% bleiben möchte: Optionaler Fallback über `powerd` / Apple System Settings Limit.

### Fallstrick 6: Voltage Sag im Spannungs-Modus
* **Referenz:** [actuallymentor/battery #71](https://github.com/actuallymentor/battery)
* **Problem:** Im Spannungs-Modus bricht die gemessene Batteriespannung unter CPU/GPU-Volllast kurzfristig um bis zu 300–500 mV ein (Innenwiderstand der Zellen). Dies führt zu ständigem hektischem Ein- und Ausschalten des Netzteils ("Flatter-Effekt").
* **Lösung:** Niemals unverzögerte Momentanspannung als Schaltschwelle nutzen! Immer einen gleitenden Mittelwert (Exponential Moving Average, Alpha = 0.1 über 30–60 Sekunden) berechnen oder den Laststrom mit einrechnen ($U_{leer} = U_{klemm} + I \cdot R_i$).

### Fallstrick 7: XPC Privilege Escalation (CVE-2025-23202)
* **Referenz:** [exelban/stats CVE-2025-23202](https://github.com/exelban/stats)
* **Problem:** Der privilegierte SMC-Helper akzeptierte jede Verbindung in `shouldAcceptNewConnection`, wodurch unberechtigte lokale Apps beliebig SMC-Register manipulieren konnten.
* **Lösung:** Strikte Überprüfung des Audit-Tokens via `SecCodeCopyGuestWithAttributes` oder `connection.setCodeSigningRequirement`.

### Fallstrick 8: Silent Write Failures ohne Readback-Verifikation
* **Referenz:** [Ednk-1312/BatteryControl](https://github.com/Ednk-1312/BatteryControl)
* **Problem:** `IOConnectCallStructMethod` meldet `kIOReturnSuccess`, aber der SMC-Controller hat den Wert verworfen (z. B. weil die Firmware den Wert im selben CPU-Zyklus überschrieben hat). Die UI zeigt "80% Limit aktiv", der Akku lädt aber weiter.
* **Lösung:** Nach jedem Schreibvorgang muss der Key nach 50 ms erneut gelesen (`readKey`) und bitweise verglichen werden. Stimmt der Wert nicht, muss der Zustand als `unverified` gemeldet werden.

### Fallstrick 9: Gauge-Drift bei dauerhafter 80%-Limitierung
* **Referenz:** [TY-teo/ChargeWatching](https://github.com/TY-teo/ChargeWatching), [Apple Support Community](https://support.apple.com)
* **Problem:** Steht der Akku über Wochen permanent bei 80%, de-kalibriert sich der Coulomb-Counter (Gas Gauge) des Akkus. Der Akku "vergisst", wo 100% und 0% liegen. Folge: Plötzliches Abschalten bei 15% oder falsche Kapazitätsanzeigen.
* **Lösung:** Automatische Erinnerung oder Kalibrierungs-Scheduler (z. B. alle 14 oder 30 Tage einmalig kontrolliert auf 100% laden).

### Fallstrick 10: MagSafe-LED Desynchronisation
* **Referenz:** [MagHue](https://github.com), [charlie0129/batt](https://github.com/charlie0129/batt)
* **Problem:** Wird die LED via `ACLC` auf Grün (`03`) gesetzt, bleibt sie auch grün, wenn das MacBook in den Ruhezustand geht oder der Nutzer das Ladekabel abzieht und wieder ansteckt – es sei denn, der Daemon setzt die Farbe vor Sleep oder beim Beenden sauber auf `00` (System-Automatik) zurück.
* **Lösung:** Handler bei SIGTERM/SIGINT sowie Pre-Sleep-Notification müssen `ACLC = 00` schreiben.

---

## 6. Machbarkeitstabelle je Feature für BatteryGuard

Legende:
* **Aufwand:** **S** (Small, 1–2 Tage) | **M** (Medium, 3–5 Tage) | **L** (Large, > 1 Woche)
* **Risiko macOS 27:** **Gering** (Kein Entitlement nötig) | **Mittel** (Verhalten abhängig von Firmware) | **Hoch** (Entitlement-Gefahr)
* **Priorität:** **Must** (Kernwert / Stabilität) | **Should** (Wesentliche Aufwertung) | **Nice** (Komfort / Nische)

| Feature | Aufwand | Technik & SMC-Keys | Risiko macOS 27 | Priorität | Umsetzungsskizze in Swift (Stichpunkte) |
| :--- | :---: | :--- | :---: | :---: | :--- |
| **1. Readback-Verifikation** | **S** | SMC Read nach Write | Gering | **Must** | • Nach `writeKey(key, bytes)` in `SMCClient` direkt `readKey(key)` aufrufen.<br>• Bytes vergleichen; bei Mismatch Flag `isVerified = false` in `BGStatus` setzen.<br>• UI zeigt Warn-Badge, wenn Limit nicht von Hardware bestätigt ist. |
| **2. Clamshell & Sleep Protection** | **S** | `IOPMAssertionCreateWithName` | Gering | **Must** | • In `batteryguardd`: Wenn `adapterConnected == false` (aktives Entladen), Assertion `kIOPMAssertionTypePreventSystemSleep` anfordern.<br>• Bei Wiederverbinden des Adapters oder bei `percent <= lowerLimit` Assertion freigeben.<br>• Verhindert sofortigen Display-/Systemausfall am externen Monitor. |
| **3. MagSafe-LED-Steuerung** | **S** | SMC `ACLC` (1 Byte: `00` Auto, `01` Off, `03` Grün, `04` Orange) | Gering | **Should** | • In `SMCClient`: Funktion `setMagSafeLED(_ state: MagSafeColor)`.<br>• Controller: Wenn `state == .holding` → `03` (Grün). Wenn `state == .charging` → `04` (Orange). Bei Daemon-Exit oder `disabled` → `00` (Auto).<br>• User-Toggle in Settings: "MagSafe LED an Ladelimit anpassen". |
| **4. Feste Presets** | **S** | `BGConfig` Erweiterung | Gering | **Should** | • Enum `BGPreset`: `daily` (80/75), `saver` (70/65), `desk` (50/45), `travel` (100).<br>• Menüleisten-Schnellauswahl mit einem Klick in der UI.<br>• Besonders `desk` (50%) bietet enormen Mehrwert für stationäre MacBooks. |
| **5. 100%-Override mit Auto-Deadline** | **S** | `BGConfig.chargeToFullOnce` + Timer | Gering | **Should** | • Feld `chargeToFullDeadline: Date?` in `BGConfig`.<br>• Wenn nach 2 Stunden 100% nicht erreicht oder erreicht: Automatischer Reset auf `false`.<br>• Verhindert, dass der Mac tagelang auf 100% verweilt, falls der Nutzer es vergisst. |
| **6. Kalibrierungs-Assistent** | **M** | State-Machine im Controller | Gering (Adapter-Mode) | **Should** | • Neuer Zustand `BGChargeState.calibrating(phase)`: Phase 1 Entladen auf 15% (via `CHIE 08`), Phase 2 Laden auf 100%, Phase 3 2 Stunden Halten, Phase 4 Zurückkehren auf Upper Limit.<br>• Integrierte Sicherheitsabbrüche (z. B. Temperatur, Nutzerinteraktion). |
| **7. 3-Wege-Leistungsmonitor** | **M** | IOKit `AppleSmartBattery` | Gering | **Should** | • Auslesen von `Voltage`, `Amperage`, `AdapterDetails.Watts`.<br>• Berechnung: $P_{bat} = U \cdot I$, $P_{wall} = \text{Adapter Watts}$, $P_{sys} = P_{wall} - P_{bat}$.<br>• Visualisierung in UI als dynamisches Flussdiagramm (Netzteil ➔ Mac ➔ Akku). |
| **8. CLI-Tool (`batteryguard`)** | **S** | Swift ArgumentParser / Symlink | Gering | **Should** | • Separates oder kombiniertes Target `batteryguard`.<br>• Befehle: `status`, `set-limit 80`, `discharge 70`, `charge-once`, `restore`.<br>• Schreibt direkt in `config.json` oder ruft Daemon-Socket auf. Installierbar via Homebrew. |
| **9. Zeitpläne / Scheduler** | **M** | Foundation `Calendar` / BackgroundTimer | Gering | **Nice** | • Struktur `BGScheduleRule`: Wochentage, Startzeit, Endzeit, Ziel-Limit.<br>• Bsp.: Mo–Fr ab 07:00 Uhr auf 100% laden (für Pendler), sonst 80%.<br>• Controller evaluiert vor jedem Tick die aktuell gültige Regel. |
| **10. Low-Power-Mode-Automatik** | **S** | `pmset` / IOKit Private API | Gering | **Nice** | • Automatische Aktivierung von macOS Stromsparmodus, wenn Akku unter x% fällt oder wenn im Pendelmodus entladen wird.<br>• Reduziert Entladedauer und thermische Last beim aktiven Entladen. |
| **11. Akku-Historie & CSV/SQLite** | **M** | SQLite.swift / CSV Writer | Gering | **Nice** | • Daemon oder UI loggt stündlich: Kapazität, Zyklen, Health %, Temperatur.<br>• SwiftUI Charts Ansicht: Verlauf über 30/90 Tage.<br>• Export-Button für Support & Diagnose. |
| **12. Shortcuts / AppIntents** | **S** | `AppIntents` Framework | Gering | **Nice** | • Definition von Intents: `SetChargeLimitIntent`, `ChargeToFullIntent`, `GetBatteryGuardStatusIntent`.<br>• Erlaubt Steuerung via Siri, Fokus-Modi und macOS Kurzbefehle-Automation. |
| **13. Spannungs-Modus (mV)** | **M** | SMC / IOKit `Voltage` | Mittel | **Nice** | • Steuerung nach Millivolt (z. B. 11.500 mV) statt %.<br>• Erfordert Moving-Average-Filter zur Glättung von Lastspitzen (Spannungseinbrüchen). |
| **14. Migration auf SMAppService/XPC** | **L** | `SMAppService` + `NSXPCConnection` | Gering | **Should (V2)**| • Implementierung von `BTXPCValidation` (Audit Token Verification).<br>• Erfordert Developer ID Signierung für reibungslosen Betrieb.<br>• Status.json bleibt als lesbarer Spiegel erhalten. |

---

## 7. Zusammenfassende Handlungsempfehlungen

1. **Sofort-Schritt (Quick Wins in V1.x):**
   * **Readback-Verifikation** einbauen, um stille SMC-Schreibfehler sofort zu erkennen.
   * **Clamshell-Sleep-Prevention** via `IOPMAssertion` implementieren, um das Abschalten externer Monitore beim aktiven Entladen / Pendeln zu stoppen.
   * **MagSafe-LED-Steuerung (`ACLC`)** aktivieren (Grün = Limit gehalten, Orange = Laden).
   * **Sicherheits-Floor (20%)** beim aktiven Entladen und Timeout für `chargeToFullOnce` ergänzen.
   * Vordefinierte **Presets** (50% Desk, 70% Saver, 80% Daily) in der UI anbieten.

2. **Mittelfristig (V1.5):**
   * Vollwertiges **CLI-Tool** bereitstellen (sehr beliebt bei Entwicklern, siehe `batt` und `battery`).
   * **3-Wege-Leistungsanzeige (Watt)** wie in ChargeWatch integrieren, um den Netzteilstrom vs. Akkustrom transparent zu visualisieren.
   * Einen geführten **Kalibrierungs-Modus** anbieten.

3. **Langfristig (V2.0 – Architektur & macOS 27):**
   * Den bestehenden Pendel-Modus als Standard für macOS 27 beibehalten, da Apple CHTE/CH0B schützt.
   * Die IPC-Schicht für signierte Releases auf **`SMAppService.daemon` + XPC mit Audit-Token-Validierung** heben, während unprivilegierte Skripte weiterhin über eine read-only `status.json` abgeholt werden.
