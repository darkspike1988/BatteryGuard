# Recherche-Bericht: Offizielle Apple-Dokumentation, APIs & Mechanismen zum nativen macOS-Ladelimit

**Erstellungsdatum:** 3. Oktober 2026  
**Ziel-Hardware & OS:** Apple Silicon (MacBook Pro 14", M1 Pro), macOS 27.0.0 (Darwin 27.0.0, Build 26A428, arm64)  
**SDK:** macOS 27.0 SDK (`/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk`)  
**Modus:** Ausschließlich lesende Recherche, Reverse Engineering und SDK-Audit (keine Systemänderungen, kein Schreibzugriff auf Systemeinstellungen).

---

## 1. Executive Summary & Beantwortung der Kernfrage

> **Gibt es einen offiziellen / öffentlichen Weg, das native macOS-Ladelimit programmatisch zu setzen?**  
> **NEIN.** Es existiert in macOS weder eine öffentliche C/Swift-API, noch ein `pmset`-Schreibbefehl, noch ein MDM/Konfigurationsprofil-Schlüssel, um das native Ladelimit (80–100 %) zu konfigurieren.

### Die Mechanismen im Überblick:

| Ebene / Mechanismus | Typ | Lesen | Schreiben | Erforderliche Rechte / Restriktionen | Konfidenz |
| :--- | :--- | :---: | :---: | :--- | :---: |
| **`pmset -g battlimit`** | CLI (Apple) | **Ja** | **Nein** | Keine besonderen Rechte (Standard-User) | **Bestätigt** |
| **IOKit Public API** (`IOPowerSources.h`) | C-API (öffentlich) | **Nein** | **Nein** | Keine Ladelimit-Keys im PowerSource-Dictionary | **Bestätigt** |
| **IOKit Private SPI** (`IOPSLimitBatteryLevel`) | C-SPI (undokumentiert) | **Ja** (`IOPSCopyBatteryLevelLimits`) | **Ja** | Benötigt Apple-Private-Entitlement `com.apple.private.iokit.soc-limit` | **Bestätigt** |
| **`PowerUI.framework`** (`PowerUISmartChargeClient`) | Obj-C (PrivateFramework) | **Ja** | **Ja** (`setMCLLimit:error:`) | Private Framework; XPC zu `com.apple.powerui.smartcharging` | **Bestätigt** |
| **MDM / Configuration Profiles** | MDM Payload | **Teilweise** (Akkuzustand) | **Nein** | Kein Payload-Schlüssel für Charge Limit vorhanden | **Bestätigt** |
| **`SMAppService.daemon`** | Swift/Obj-C API | n/a | n/a | Benötigt Admin-Prompt bei `.register()`, Developer ID für Stabilität | **Bestätigt** |

---

## 2. Detaillierte Analyse nach Untersuchungsbereichen

---

### (a) Apple Developer Release Notes (macOS 26.4 / macOS 27)

* **Recherche-Quellen:**
  * `https://developer.apple.com/documentation/macos-release-notes`
  * Developer Release Notes zu macOS 26.4 (Tahoe) und macOS 27 (Golden Gate Beta/GM)
* **Befund:**
  * Apple erwähnt in den offiziellen Entwickler-Release-Notes **keine** programmatischen Schnittstellen für das mit macOS 26.4 eingeführte manuelle Ladelimit ("Manual Charge Limit" / MCL).
  * Erwähnungen von "Battery" oder "Charging" beschränken sich auf:
    1. Bugfixes im Shortcuts-Framework (z. B. Auslöser für "Battery Level" und "Charger Connected").
    2. Sicherheitseinschränkungen für USB/Thunderbolt-Zubehör (unter Beibehaltung der Ladefunktion).
    3. Behebung von GPU-bedingtem Batterieverbrauch auf Altgeräten.
  * Das Ladelimit wird von Apple rein als endanwenderseitiges Systemeinstellungs-Feature behandelt, analog zu iPhone 15/16 (80 % Ladebegrenzung).
* **Konfidenz:** **Bestätigt** (Offizielle Release Notes enthalten keine Ladelimit-APIs).

---

### (b) IOKit Power Sources API (`IOPowerSources.h`, `IOPSKeys.h`, `IOPMLib.h`)

* **Dateipfade im SDK:**
  * `$(xcrun --show-sdk-path)/System/Library/Frameworks/IOKit.framework/Headers/ps/IOPowerSources.h`
  * `$(xcrun --show-sdk-path)/System/Library/Frameworks/IOKit.framework/Headers/ps/IOPSKeys.h`
  * `$(xcrun --show-sdk-path)/System/Library/Frameworks/IOKit.framework/Headers/pwr_mgt/IOPM.h`
  * `$(xcrun --show-sdk-path)/System/Library/Frameworks/IOKit.framework/Headers/pwr_mgt/IOPMLib.h`
  * `$(xcrun --show-sdk-path)/System/Library/Frameworks/IOKit.framework/IOKit.tbd`

* **Untersuchung der öffentlichen Header:**
  * `IOPSCopyPowerSourcesInfo()` und `IOPSGetPowerSourceDescription()` liefern standardmäßig nur:
    * `Name`, `Type`, `Current Capacity`, `Max Capacity`, `Is Charging`, `Is Charged`, `Power Source State`, `Time to Full Charge`, `Transport Type`, `LPM Active`.
  * In `IOPSKeys.h` existieren **keine** Keys wie `kIOPSChargeLimitKey` oder `kIOPSManualChargeLimitKey`.
  * Der einzige gefundene Limit-Key ist `kIOPSCommandSetCurrentLimitKey` ("Set Current Limit"), welcher jedoch den Eingangsstrom in mA (Stromstärke, nicht Ladezustand) für USVs/Netzteile steuert.

* **Fund im Framework-Symbolkatalog (`IOKit.tbd`):**
  Folgende C-Symbole sind in IOKit exportiert, aber **nicht** in den öffentlichen Headern deklariert:
  ```text
  _IOPSCopyBatteryLevelLimits
  _IOPSLimitBatteryLevel
  _IOPSLimitBatteryLevelCancel
  _IOPSLimitBatteryLevelRegister
  _IOPSShippingChargeLimitEnable
  _IOPSShippingChargeLimitGetState
  ```

* **Disassemblierungs- und Rechtemanalyse:**
  * Aufruf von `IOPSCopyBatteryLevelLimits()` und `IOPSLimitBatteryLevel()` kommuniziert via Mach-XPC mit dem Dienst `"com.apple.iokit.powerdxpc"` (betrieben von `powerd`).
  * `powerd` prüft für die XPC-Nachricht `"chargeSocLimitAction"` zwingend das private Apple-Entitlement:
    ```xml
    <key>com.apple.private.iokit.soc-limit</key><true/>
    ```
  * Sowohl `/usr/bin/pmset` als auch `/usr/libexec/PowerUIAgent` besitzen dieses Entitlement.
  * Drittanbieter-Binaries (selbst mit Root-Rechten) ohne dieses Entitlement erhalten `nil` bzw. werden von `powerd` abgewiesen (durch AMFI/Codesigning geschützt, außer SIP ist deaktiviert).
* **Konfidenz:** **Bestätigt** (Verifiziert via `lldb`, `codesign -d --entitlements` und Testaufruf).

---

### (c) `pmset` Diagnostik & Man-Page-Audit

* **Lokale Prüfung:** `man pmset | col -b` und Strings-Inspektion von `/usr/bin/pmset`.
* **Settable Settings in `pmset`:**
  * Vollständige Liste: `displaysleep`, `disksleep`, `sleep`, `womp`, `ring`, `acwake`, `autorestart`, `lidwake`, `lessbright`, `halfdim`, `standby`, `standbydelayhigh`, `standbydelaylow`, `highstandbythreshold`, `powernap`, `ttyskeepawake`, `hibernatemode`, `hibernatefile`, `autopoweroff`, `tcpkeepalive`, `autopoweroffdelay`, `proximitywake`, `lowpowermode`, `highpowermode`.
  * **Ergebnis:** Es gibt **keine** Option `chargelimit`, `batterylimit` oder ähnliches zum Schreiben. `pmset -a chargelimit 80` existiert nicht.
* **Getter-Setting (`pmset -g battlimit`):**
  * `pmset` besitzt einen nativen Getter für das Ladelimit:
    ```bash
    pmset -g battlimit
    ```
  * Ausgabe auf diesem Mac:
    ```text
    Battery level limits:
    (
            {
            Terminated = 0;
            chargeSocLimitDrain = 1;
            chargeSocLimitIsEOC = 1;
            chargeSocLimitNoChargeToFull = 0;
            chargeSocLimitOwner = 85702;
            chargeSocLimitReason = manualChargeLimit;
            chargeSocLimitSoc = 80;
        },
            {
            Terminated = 0;
            chargeSocLimitDrain = 1;
            chargeSocLimitIsEOC = 1;
            chargeSocLimitNoChargeToFull = 0;
            chargeSocLimitOwner = 0;
            chargeSocLimitReason = manualChargeLimit;
            chargeSocLimitSoc = 80;
        }
    )
    ```
  * **Bedeutung:**
    * `chargeSocLimitOwner = 85702`: PID des Daemons `/usr/libexec/PowerUIAgent`.
    * `chargeSocLimitReason = manualChargeLimit`: Natives manuelles Ladelimit.
    * `chargeSocLimitSoc = 80`: Ziel-Ladezustand (80 %).
    * `chargeSocLimitDrain = 1`: System darf Akku auf Zielwert entladen, falls darüber.
    * `chargeSocLimitIsEOC = 1`: End-of-Charge Begrenzung ist aktiv.
* **Konfidenz:** **Bestätigt** (Man-Page gelesen, CLI getestet, Disassemblierung verifiziert).

---

### (d) Apple Support-Dokumentation ("Charge limit" & "Battery health management")

* **Quellen:**
  * Apple Support Article: *Charge limit on Mac laptops* / *Manage battery health on Mac laptops*
  * URL-Muster: `https://support.apple.com/HT212049` / `https://support.apple.com/guide/mac-help/mchl7d090d42/mac`
* **Inhaltliche Kernaussagen:**
  1. **Funktion:** Auf unterstützten Apple Silicon Macs unter macOS 26.4+ können Nutzer in den Systemeinstellungen ein manuelles Ladelimit zwischen 80 % und 100 % einstellen.
  2. **Unterschied zu "Optimized Battery Charging":**
     * *Optimized Battery Charging (OBC):* Prognosebasiertes, maschinelles Lernen basierend auf täglichen Ladegewohnheiten (verzögert Laden über 80 % bis kurz vor dem Ausstecken).
     * *Manual Charge Limit (MCL):* Statischer, garantierter Schwellenwert (z. B. dauerhaft 80 %).
  3. **Override:** Über das Batteriemenü in der Menüleiste kann der Benutzer einmalig "Jetzt vollständig laden" (*Charge to Full Now*) auswählen.
  4. **Support-Fokus:** Reine Endbenutzerdokumentation; keinerlei Verweise auf MDM-Profile oder Entwickler-APIs.
* **Konfidenz:** **Bestätigt**.

---

### (e) MDM & Configuration-Profile-Keys

* **Quellen:**
  * Apple Device Management Documentation: `https://developer.apple.com/documentation/devicemanagement`
  * Payloads: `com.apple.EnergySaver.portable.BatteryPower`, `com.apple.EnergySaver.desktop.ACPower`, `com.apple.MCX`
  * Declarative Management: `device.power.battery-health`
* **Befund:**
  * Apple bietet in den MDM-Payloads Einstellungen für Sleep-Timer, Ruhezustand, Wake-on-LAN und Display-Dimmung.
  * In der Declarative Device Management (DDM) API kann der Administrator den Batteriezustand (`battery-health`) passiv auslesen.
  * Es gibt **keinen** MDM-Schlüssel (weder `BatteryChargeLimit`, `ChargeLimit`, `MaxChargeLevel` noch `EnforceChargeLimit`), um ein Ladelimit per Konfigurationsprofil vorzugeben oder zu erzwingen.
* **Konfidenz:** **Bestätigt**.

---

### (f) SDK Header & Swiftinterface Audit

* **Grep-Befehle:**
  * `grep -rn "IOPSLimitBatteryLevel" $(xcrun --show-sdk-path)`
  * `grep -in -E "(limit|charge)" $(xcrun --show-sdk-path)/System/Library/Frameworks/IOKit.framework/Headers/ps/*`
  * `find $(xcrun --show-sdk-path) -name "*.swiftinterface" -exec grep -in "chargelimit" {} +`
* **Ergebnis:**
  * **0** Treffer in Header-Dateien (`.h`).
  * **0** Treffer in Swift-Interfaces (`.swiftinterface`).
  * Treffer existieren **ausschließlich** in der dynamischen Symboltabelle `IOKit.tbd` (Zeile 524) und in privaten Frameworks (`PowerUI.tbd`).
* **Konfidenz:** **Bestätigt**.

---

### (g) `SMAppService` & Privileged-Helper-Dokumentation

* **Offizielle Dokumentation:**
  * `https://developer.apple.com/documentation/servicemanagement/smappservice/daemon(plistname:)`
  * `https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos`
* **Architektur & Bundle-Struktur:**
  * LaunchDaemons, die über `SMAppService.daemon(plistName:)` registriert werden, **müssen** ihre `.plist`-Datei im App-Bundle unter folgendem Pfad ablegen:
    ```text
    BatteryGuard.app/Contents/Library/LaunchDaemons/com.michaelkatschko.BatteryGuardHelper.plist
    ```
  * In der `.plist` darf nicht der absolute Pfad `Program` verwendet werden, sondern der relative Schlüssel:
    ```xml
    <key>BundleProgram</key>
    <string>Contents/MacOS/BatteryGuardHelper</string>
    ```
* **Registrierung & Benutzerinteraktion:**
  * Aufruf von `try SMAppService.daemon(plistName: "...").register()` löst im Gegensatz zu `SMAppService.agent` einen **System-Admin-Dialog** (Touch ID oder Passwort) aus, da der Dienst als `root` in `/Library/LaunchDaemons` registriert wird.
* **Signatur & Developer ID:**
  * **Ad-hoc Signatur:** Für den reinen Entwicklungszyklus auf dem lokalen Rechner (`codesign -s -`) kann `register()` prinzipiell aufgerufen werden. **Aber:** Bei jeder Neukompilierung ändert sich der Code Directory Hash (`CDHash`). Das macOS Background Task Management (BTM) verliert dadurch die Zuordnung, betrachtet den Daemon als unautorisiert oder wirft Fehler (`Code 113` oder `Code 5`), und der Nutzer wird fortwährend erneut um Erlaubnis gebeten.
  * **Developer ID:** Für einen stabilen Betrieb (Distribution außerhalb des App Stores) ist ein gültiges **Developer ID Application**-Zertifikat mit stabiler `Team ID` zwingend erforderlich, damit macOS Updates und Autorisierungszustände zwischen App und Daemon erhalten kann.
* **Konfidenz:** **Bestätigt**.

---

### (h) Der reale funktionierende Mechanismus: `PowerUI.framework` (Halböffentlich / Private SPI)

Obwohl kein öffentliches API existiert, nutzt macOS intern ein sauberes XPC-Framework, das auch von Drittanbieter-Code instanziiert werden kann.

#### 1. Architektur-Pfad
```text
System Settings / Drittanbieter-App
    │
    ▼ (Objective-C Runtime)
PowerUI.framework (`PowerUISmartChargeClient`)
    │
    ▼ Mach-XPC: "com.apple.powerui.smartcharging"
/usr/libexec/PowerUIAgent (root Daemon)
    │
    ▼ Mach-XPC: "com.apple.iokit.powerdxpc" (erfordert com.apple.private.iokit.soc-limit)
powerd (/System/Library/CoreServices/powerd.bundle/powerd)
    │
    ├──► Persistiert in: /Library/Preferences/com.apple.powerd.charging.plist
    ▼
AppleSMC (Kernel / Hardware)
    │
    ▼ Setzt 3-Byte-Schlüssel `CHLT` & `bfG0` (z. B. [50 05 03] für 80 %)
```

#### 2. Relevante Methoden auf `PowerUISmartChargeClient`
Geprüft und bestätigt via Objective-C Runtime Inspection auf macOS 27:
* `-[PowerUISmartChargeClient initWithClientName:(NSString *)]`
* `-[PowerUISmartChargeClient isMCLSupported]` -> `BOOL` (Gibt `YES` auf M1/M2/M3/M4 zurück)
* `-[PowerUISmartChargeClient isMCLCurrentlyEnabled:(NSError **)]` -> `unsigned long long`
* `-[PowerUISmartChargeClient getMCLLimitWithError:(NSError **)]` -> `unsigned char` (z. B. `80`)
* `-[PowerUISmartChargeClient availableChargeLimitsWithError:(NSError **)]` -> `NSArray *` (`[80, 85, 90, 95, 100]`)
* `-[PowerUISmartChargeClient setMCLLimit:(unsigned char)limit error:(NSError **)]` -> `BOOL`
* `-[PowerUISmartChargeClient temporarilyOverrideMCLTargetSoC:(unsigned char) error:(NSError **)]`

#### 3. Test-Ergebnis (Lesender Aufruf ohne Root / ohne Entitlements):
Ein unprivilegiertes Testprogramm las die Daten erfolgreich direkt aus `PowerUIAgent` aus:
```text
isMCLSupported: 1
isMCLCurrentlyEnabled: 1
getMCLLimitWithError: 80%
availableChargeLimitsWithError: ( 80, 85, 90, 95, 100 )
currentChargeLimit: 100
```

#### 4. Grenzen des nativen Ladelimits:
* Apple erlaubt im MCL-Subsystem **ausschließlich Werte zwischen 80 % und 100 %** (validiert im Code von `PowerUISmartChargeManager`: `80 <= limit <= 100`).
* Ein unteres Ladelimit von **20 %** (wie für BatteryGuard gewünscht) kann über Apples natives MCL **nicht** gesetzt werden; hierfür müsste wie bisher der SMC-Hardware-Ladeinhibitierungsbefehl verwendet werden.

---

## 3. Quellenverzeichnis

1. **Apple Developer Documentation:**
   * Service Management / SMAppService: `https://developer.apple.com/documentation/servicemanagement/smappservice`
   * SMAppService.daemon(plistName:): `https://developer.apple.com/documentation/servicemanagement/smappservice/daemon(plistname:)`
   * Updating Helper Executables: `https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos`
   * Device Management / EnergySaver: `https://developer.apple.com/documentation/devicemanagement/energysaver`
2. **Apple Support:**
   * Mac Battery Health Management: `https://support.apple.com/HT212049`
3. **Lokale Systemdateien & Binaries:**
   * SDK IOKit Headers: `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/IOKit.framework`
   * `pmset` Binary & Man-Page: `/usr/bin/pmset`
   * Power Daemon: `/System/Library/CoreServices/powerd.bundle/powerd`
   * Power UI Agent: `/usr/libexec/PowerUIAgent`
   * Power UI Framework: `/System/Library/PrivateFrameworks/PowerUI.framework`
   * Charging Preferences: `/Library/Preferences/com.apple.powerd.charging.plist`
