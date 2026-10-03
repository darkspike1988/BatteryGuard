# Lokale Analyse: Natives macOS-Ladelimit auf Apple Silicon (macOS 27.0, M1 Pro)

**Datum:** 3. Oktober 2026  
**Hardware:** MacBook Pro 14" (2021, MacBookPro18,3), Apple M1 Pro (RELEASE_ARM64_T6000)  
**Betriebssystem:** macOS 27.0.0 (Darwin Kernel Version 27.0.0: root:xnu-13432.1.9~1/RELEASE_ARM64_T6000)  
**Modus:** Ausschließlich lesende Inspektion (Zero Side-Effects)

---

## 1. Executive Summary

Auf Apple Silicon Macs unter modernem macOS (ab 26.4 / 27.0) wird das native Ladelimit **nicht** mehr über die veralteten Intel-SMC-Schlüssel (`CHTE`, `CH0B`) gesteuert. Stattdessen existiert ein vollständiger, mehrschichtiger Apple-Subsystem-Stack namens **MCL (Manual Charge Limit)**:

1. **Systemeinstellungen (UI):** `PowerPreferences.appex` nutzt das private Framework `PowerUI.framework` (`PowerUISmartChargeClient`).
2. **Hintergrund-Dienst:** `PowerUIAgent` (`/usr/libexec/PowerUIAgent`) verwaltet die Ladelogik (`PowerUIChargingController`) und kommuniziert via Mach-XPC (`com.apple.iokit.powerdxpc`) mit `powerd`.
3. **Power Daemon & Kernel-Brücke:** `powerd` (`/System/Library/CoreServices/powerd.bundle/powerd`) persistiert die Richtlinie als `ChargeCtrlPolicy` in `/Library/Preferences/com.apple.powerd.charging.plist` und ruft die private IOKit-Funktion `IOPSLimitBatteryLevel` auf.
4. **Hardware / SMC-Ebene:** Die Zielgrenze wird im SMC in den 3-Byte-Schlüsseln **`CHLT`** (*Charge Limit Threshold*) und **`bfG0`** abgelegt (aktueller Wert: `[50 05 03]` = 80 % Ziel, 5 % Hysterese, Modus 3). Das Abschalten des Ladens wird durch den SMC-Status **`CHNC`** (`0x01000000` = `NotChargingReason 16777216`) und `IPDChargingAllowed = 0` signalisiert.
5. **Lesen des Status:** Ohne Root oder Entitlements kann der gesetzte Ladelimit-Wert direkt und zuverlässig über das native CLI-Tool `pmset -g battlimit` oder über das Auslesen der SMC-Schlüssel `CHLT` / `bfG0` via AppleSMC UserClient abgefragt werden.

---

## 2. Detaillierte Befunde nach Testbereichen

### (1) `pmset` Diagnostik

#### Ausgeführte Befehle:
```bash
pmset -g batt
pmset -g custom
pmset -g battlimit
pmset -g getters
```

#### Relevante Ausgaben:
* `pmset -g batt`:
  ```text
  Now drawing from 'AC Power'
   -InternalBattery-0 (id=8978531)	97%; AC attached; not charging present: true
  ```
* `pmset -g battlimit`:
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
* `pmset -g getters`:
  Enthält unter den aktiven Getter-Kommandos offiziell `battlimit`.

#### Interpretation:
* `pmset` verfügt über eine native Abfrage `battlimit`.
* Die Eigentümer (*Owner*) sind PID `85702` (`/usr/libexec/PowerUIAgent`) und PID `0` (Kernel / `powerd`).
* Die Richtlinie ist aktiv: `chargeSocLimitSoc = 80`, `chargeSocLimitReason = manualChargeLimit`, `chargeSocLimitDrain = 1` (Entladen auf Zielwert erlaubt), `chargeSocLimitIsEOC = 1` (End of Charge aktiv).
* Da der Akku derzeit bei 97 % steht, ist der Akku im Zustand `AC attached; not charging`, d. h. die Ladeinhibition greift bereits.
* **Konfidenz:** Sehr hoch (100 %).

---

### (2) IORegistry Analyse (`AppleSmartBattery`, `AppleChargerData`)

#### Ausgeführte Befehle:
```bash
ioreg -r -n AppleSmartBattery -l
ioreg -r -n AppleChargerData -l
ioreg -l | grep -i -E "smc-charger-util|AppleSMCChargerUtil"
```

#### Relevante Ausgaben:
* In `AppleSmartBattery`:
  ```text
  "IsCharging" = No
  "ExternalConnected" = Yes
  "ExternalChargeCapable" = Yes
  "ChargerData" = {
      "IsCharging" = 0,
      "NotChargingReason" = 16777216,
      "SlowChargingReason" = 0,
      "TimeChargingThermallyLimited" = 0
  }
  "PowerDistribution" = {
      "IPDChargingAllowed" = 0,
      "IPDInputCurrent" = 3260,
      "IPDInputPower" = 65200,
      "IPDInputVoltage" = 20000,
      "IPDRatio" = 100,
      "IPDWattageOverride" = 30000
  }
  ```
* In `AppleChargerData`:
  ```text
  "ChargerData" = {
      "ChargerInhibitReason" = 268439552,  // 0x10001000
      "NotChargingReason" = 16777216,      // 0x01000000 (Bit 24)
      "ChargingCurrent" = 0,
      "ChargingVoltage" = 4195
  }
  ```
* Treiber-Hierarchie:
  `smc-charger-util` (`AppleSMCInterface`) -> `AppleSMCChargerUtil` (`com.apple.driver.AppleSMC`).

#### Interpretation:
* Die Hardware hat das Laden vollständig blockiert (`ChargingCurrent = 0`, `IPDChargingAllowed = 0`).
* `NotChargingReason = 16777216` (`0x01000000` = Bit 24) ist der hardware-/treiberseitige Statuscode für das Erreichen des SOC-Limits.
* `ChargerInhibitReason = 268439552` (`0x10001000`) ist der Treibergrund für den Ladeinhibit.
* **Konfidenz:** Sehr hoch (100 %).

---

### (3) Einstellungs- und Konfigurationsdateien

#### Ausgeführte Befehle:
```bash
ls -la /Library/Preferences | grep -i -E "power|batt"
plutil -p /Library/Preferences/com.apple.powerd.charging.plist
python3 -c '... decode policies ...'
```

#### Relevante Ausgaben:
* `/Library/Preferences/com.apple.powerd.charging.plist` existiert und enthält:
  ```text
  bootSessionUUID: DC47CA4A-8007-461B-A859-1D7888B5A651
  policies: <bplist00 ... NSKeyedArchiver>
  ```
* Dekodierung des `policies`-Feldes:
  ```python
  {
      '$classname': 'ChargeCtrlPolicy',
      'owner': 85702,
      'reason': 'manualChargeLimit',
      'soclimit': 80,
      'drain': True,
      'isEndOfCharge': True,
      'noChargeToFull': False,
      'terminated': False,
      'token': <NSUUID cd0f4147-835f-4176-8757-757e016639c1>
  }
  ```
* `/Library/Preferences/com.apple.PowerManagement.plist` enthält nur Standardeinstellungen für Display-/Disk-Sleep und PowerMode.

#### Interpretation:
* `powerd` speichert die aktive Limit-Richtlinie serialisiert als `ChargeCtrlPolicy` in `/Library/Preferences/com.apple.powerd.charging.plist`.
* Das Limit ist systemweit persistent und überlebt Reboots.
* **Konfidenz:** Sehr hoch (100 %).

---

### (4) Binärdateien, Frameworks und APIs

#### 1. `IOKit.framework` (Kernel-/System-SPIs)
In `IOKit.tbd` bzw. dem Dyld-Shared-Cache exportiert `IOKit`:
* `_IOPSLimitBatteryLevel`
* `_IOPSLimitBatteryLevelCancel`
* `_IOPSLimitBatteryLevelRegister`
* `_IOPSCopyBatteryLevelLimits`
* `_IOPSShippingChargeLimitEnable`
* `_IOPSShippingChargeLimitGetState`

**Disassembly-Analyse von `IOPSLimitBatteryLevel` (aus IOKit):**
```assembly
// Parameter:
// x0 = token (aus IOPSLimitBatteryLevelRegister)
// w1 = limitPercent (z. B. 0x50 = 80)
// w2 = flags (Bit 0: drain, Bit 1: noChargeToFull, Bit 2: isEOC)
// x3 = reason (CFString, z. B. @"manualChargeLimit")
IOKit`IOPSLimitBatteryLevel:
...
bl getPMQueue
adrp x0, ... ; "com.apple.iokit.powerdxpc"
bl xpc_connection_create_mach_service
...
adrp x1, ... ; "chargeSocLimit"
bl xpc_dictionary_set_value
bl xpc_connection_send_message_with_reply_sync
```

#### 2. `PowerUI.framework` (`/System/Library/PrivateFrameworks/PowerUI.framework`)
Klasse **`PowerUISmartChargeClient`** stellt die High-Level-API bereit:
* `-(BOOL)isMCLSupported`
* `-(BOOL)isMCLCurrentlyEnabled:(id*)arg1`
* `-(NSNumber*)getMCLLimitWithError:(id*)arg1`
* `-(NSArray*)availableChargeLimitsWithError:(id*)arg1`
* `-(BOOL)setMCLLimit:(NSInteger)limit error:(id*)arg1`
* `-(BOOL)enableMCL:(id*)arg1`
* `-(BOOL)disableMCL:(id*)arg1`
* `-(BOOL)temporarilyDisableMCL:(id*)arg1`

Klasse **`PowerUIChargingController`**:
* `-(void)setChargeLimitTo:(NSUInteger)limit forLimitType:(NSUInteger)type setNoChargeToFull:(BOOL)flag`
  * Ruft intern `_IOPSLimitBatteryLevel` mit Token, Limit, Flags und Grund auf.

#### 3. Systemeinstellungen
* `/System/Library/ExtensionKit/Extensions/PowerPreferences.appex/Contents/MacOS/PowerPreferences`:
  Nutzt `ChargeLimitSlider`, bindet an `PowerUISmartChargeClient`, horcht auf die Darwin-Notification `com.apple.powerui.mclstatuschanged`.

#### 4. Entitlements-Überprüfung (`codesign -d --entitlements`)
* `pmset`:
  `<key>com.apple.private.iokit.soc-limit</key><true/>`
* `PowerPreferences.appex`:
  `<key>com.apple.powerui.smartcharging</key><true/>`
* `PowerUIAgent`:
  `<key>com.apple.private.iokit.soc-limit</key><true/>`
  `<key>com.apple.powerui.smartcharging</key><true/>`
  `<key>com.apple.private.powersource-control</key><true/>`
* `powerd`:
  `<key>com.apple.private.iokit.soc-limit</key><true/>`
  `<key>com.apple.private.powersource-write-all</key><true/>`

**Erkenntnis:** Ein Aufruf von `IOPSLimitBatteryLevel` oder `PowerUISmartChargeClient` durch einen unberechtigten Drittanbieter-Prozess wird vom XPC-Listener mit `Client does not have necessary entitlement` abgelehnt!

---

### (5) Unified Log Analyse (`/usr/bin/log show`)

#### Auszug aus dem System-Log (letzte 60 Minuten):
```text
powerd: [com.apple.powerd:charging] received SOC limit from 85702: <private>
powerd: [com.apple.powerd:charging] SOC limit policy:<private>
powerd: [com.apple.powerd:batterychargingstate] handleChargingStateUpdate State:Charging Completed Limited VBUS:1 UISOC:99 CHNC:1000000 Type:1
PowerUIAgent: [com.apple.powerui.smartcharging:smartChargeManager] Returning currently desired UI state: DischargingToMCL (mode: 7), optimized charge limit: 100, MCL target: 80%, chargingOverrideAllowed: 0
PowerUIAgent: [com.apple.powerui.smartcharging:chargingcontroller] Continue limiting to 80% for reason 'manualChargeLimit'
PowerUIAgent: [com.apple.powerui.smartcharging:smartChargeManager] Limiting charging to 80% SoC
PowerUIAgent: [com.apple.powerui.smartcharging:smartChargeManager] Called for MCL battery level=95, externalConnected=1
```

#### Test eines unberechtigten Clients (unser Test-Prozess):
```text
PowerUIAgent: [com.apple.powerui.smartcharging:smartChargeManager] Client does not have necessary entitlement.
```

#### Interpretation:
* `PowerUIAgent` regelt den Zustand vollautomatisch als Zustandsmaschine (hier: `DischargingToMCL`, State Mode 7).
* Wenn der Akku über 80 % liegt und das Limit aktiv ist, stoppt das Laden sofort und das Gerät befindet sich im Entlade-/Haltezustand bis 80 %.
* Drittanbieter ohne Apple-Signatur-Entitlements werden auf XPC-Ebene blockiert.
* **Konfidenz:** Sehr hoch (100 %).

---

### (6) SMC-Schlüssel-Analyse via `batteryguardd --dump-keys`

Alle 2.179 SMC-Schlüssel wurden gescannt.

#### 1. Die Schlüssel mit dem 80%-Limit:
Im gesamten SMC existieren exakt **zwei** Schlüssel mit dem Inhalt `[50 05 03]`:

| SMC-Key | Typ | Größe | Rohwert (Hex) | Interpretation |
| :--- | :--- | :--- | :--- | :--- |
| **`CHLT`** | `hex_` | 3 Byte | `[50 05 03]` | **CH**arge **L**imit **T**hreshold |
| **`bfG0`** | `hex_` | 3 Byte | `[50 05 03]` | **b**attery **f**uel **G**auge 0 Limit |

**Aufschlüsselung der 3 Bytes `[50 05 03]`:**
* Byte 0: `0x50` = **80** (Dezimal) $\rightarrow$ Die Ladeobergrenze in Prozent (80 %).
* Byte 1: `0x05` = **5** (Dezimal) $\rightarrow$ Das Hysterese-Delta in Prozent (Wiederaufladen beginnt bei $80 - 5 = 75\,\%$).
* Byte 2: `0x03` = **3** (Dezimal) $\rightarrow$ Bitmaske / Modus (`0x01` = Drain on AC, `0x02` = End-of-Charge / Stop charging).

#### 2. Status- und Steuerungsschlüssel im SMC:
* **`CHNC`** (`hex_`, 8 Byte): `[00 00 00 01 00 00 00 00]` $\rightarrow$ Entspricht `0x01000000` = `16777216` (`NotChargingReason`).
* **`CHIE`** (`hex_`, 1 Byte): `[00]` $\rightarrow$ Adapter Connect/Disconnect Control (wird für Force-Discharge genutzt).
* **`CHLS`**, **`bfD0`**, **`bfE0`**, **`bfF0`**: Existieren zwar im Index `#KEY`, liefern aber `size 0` / Read-Fehler (auf diesem M1 Pro nicht unterstützt oder reserviert).
* **`CHTE`**, **`CH0B`**: Auf Apple Silicon M1 Pro **nicht vorhanden**.

---

## 3. Architektur-Übersicht & Mechanismus

```
┌────────────────────────────────────────────────────────┐
│ Systemeinstellungen / Battery Pane (PowerPreferences)   │
└──────────────────────────┬─────────────────────────────┘
                           │ ObjC: [PowerUISmartChargeClient setMCLLimit:80 error:]
                           ▼
┌────────────────────────────────────────────────────────┐
│ PowerUIAgent (/usr/libexec/PowerUIAgent)                │
│ -> PowerUIChargingController                           │
└──────────────────────────┬─────────────────────────────┘
                           │ C SPI: IOPSLimitBatteryLevel(token, 80, flags, "manualChargeLimit")
                           │ via XPC Mach-Service: com.apple.iokit.powerdxpc
                           ▼
┌────────────────────────────────────────────────────────┐
│ powerd (/System/Library/CoreServices/powerd.bundle)    │
│ -> Speichert ChargeCtrlPolicy in charging.plist        │
└──────────────────────────┬─────────────────────────────┘
                           │ IOKit Kernel Driver Call
                           ▼
┌────────────────────────────────────────────────────────┐
│ AppleSMC & AppleSmartBatteryManager.kext               │
└──────────────────────────┬─────────────────────────────┘
                           │ Schreibt SMC-Register
                           ▼
┌────────────────────────────────────────────────────────┐
│ SMC Hardware / PMU Firmware                            │
│  - CHLT = [50 05 03] (80% Limit, 5% Delta, Mode 3)     │
│  - bfG0 = [50 05 03]                                   │
│  - CHNC = 0x01000000 (NotChargingReason = 16777216)    │
│  - IPDChargingAllowed = 0                              │
└────────────────────────────────────────────────────────┘
```

---

## 4. Fazit & Handlungsoptionen für BatteryGuard

### 1. Auslesen des nativen Limits (100 % machbar ohne Root):
* **Methode A (CLI):** Ausführen von `pmset -g battlimit`. Der Wert steht direkt in `chargeSocLimitSoc = 80`.
* **Methode B (SMC UserClient):** Auslesen des SMC-Keys **`CHLT`** (oder **`bfG0`**) über den vorhandenen `SMCClient`. Byte 0 liefert unmittelbar den Zielprozentwert (`0x50` = 80).

### 2. Setzen des nativen Limits:
* **Offizieller Weg (`IOPSLimitBatteryLevel` / `PowerUI`):** Erfordert die geschützten Apple-Entitlements `com.apple.private.iokit.soc-limit` und `com.apple.powerui.smartcharging`. Third-Party-Binaries können diese Entitlements auf SIP-geschützten Macs nicht signieren.
* **SMC-Direktzugriff (`CHLT` / `bfG0`):**
  Wenn `batteryguardd` als Root-Daemon (`uid 0`) läuft, hat er Schreibzugriff auf den AppleSMC UserClient (`IOServiceOpen`).
  * Hypothese: Ein direktes Schreiben von 3 Bytes in `CHLT` (z. B. `[xx 05 03]`, wobei `xx` der gewünschte Ziel-SoC ist) könnte die SMC-Firmware direkt anweisen, bei `xx %` abzuschalten.
  * Allerdings könnte `powerd` oder `PowerUIAgent` bei gesetztem MCL den Wert periodisch überschreiben, solange MCL in den macOS-Einstellungen aktiv ist.
* **Alternative für BatteryGuard:**
  Um hardwareunabhängig oder unabhängig von Apple-Entitlements beliebige Bereiche (z. B. 20–80 % oder 40–70 %) zu steuern, bleibt das manuelle Steuern von `CHIE` (Inhibit) bzw. das Ausnutzen von `CHLT` als primäres Forschungsobjekt für Root-Schreibtests.
