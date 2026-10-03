# Open-Source-Recherche: Akku-Ladelimitierung auf macOS 26.4 (Tahoe) und macOS 27 (Golden Gate)

**Projekt:** BatteryGuard (`/Users/michaelkatschko/BatteryGuard`)  
**Datum:** Oktober 2026  
**Ziel-Hardware/OS:** Apple Silicon, macOS 27.0 (Build 26A428), Firmware-Generation `20457.x+`  

---

## 1. Executive Summary & Problemursache

Auf diesem Mac fehlen die traditionellen SMC-Keys `CHTE` (macOS 15/26) sowie `CH0B`/`CH0C` (macOS 11–14). Die neuen Firmware-Keys `bfD0`, `bfE0`, `bfF0` und `CHLS` melden `Typ ?, Größe 0`.

### Ursache (Bestätigt):
Ab **macOS 27 Developer Beta 4** (Firmware `20457.0.125.0.2`+, rückportiert in macOS 15.8 / 26.7 Sicherheitsupdates) hat Apple die SMC-Ladekontrolle grundlegend restrukturiert:
1. **Legacy-Direktschlüssel entfernt:** `CH0B`, `CH0C`, `CHTE`, `CH0I`, `CH0J` sind in der SMC-Tabelle nur noch Null-Byte-Platzhalter (`DataSize == 0`).
2. **Entitlement-Gate:** Die Schlüssel für die Firmware-Ladebegrenzung (`bfF0`, `bfD0`, `bfE0`, `CHLS`) sowie die `AppleSmartBattery`-Schreibmethoden im IOKit wurden hinter das private Apple-Entitlement **`com.apple.private.iokit.soc-limit`** gelegt.
3. Jeder SMC-Aufruf (`KeyInfo` [Cmd 9], Read [Cmd 5], Write [Cmd 6]) an diese Keys ohne dieses Entitlement schlägt mit **`kIOReturnNotPrivileged` (`0xe00002c1`)** fehl – **selbst als Benutzer `root` (UID 0)**.
4. Daher liefert eine SMC-Typenabfrage (`KeyInfo`) für `bfD0`/`bfE0`/`bfF0` Fehler `0xe00002c1`, was im Client als `Typ ?, Größe 0` dargestellt wird.
5. Die native Ladelimitierung (80–100%) wird seither exklusiv vom Apple-Daemon **`powerd`** und **`PowerUIAgent`** verwaltet.

---

## 2. Analyse der SMC-Keys & Mechanismen auf macOS 26.4 / 27

### (a) Laden stoppen (Bypass / Pass-Through)
*   **Legacy-Keys (`CHTE`, `CH0B`, `CH0C`):**
    *   *Status:* Nicht funktionsfähig / entfernt (`DataSize == 0`).
    *   *Konfidenz:* **Bestätigt** (Quelle: `charlie0129/batt` Issue #152, `amperebattery.app`, `mhaeuser/Battery-Toolkit`).
*   **Firmware-Range-Keys (`bfD0`, `bfE0`, `bfF0`):**
    *   *Funktionsweise (macOS 27 Beta 1–3):* `bfD0` = Obergrenze, `bfE0` = Untergrenze, `bfF0` = Aktivierung (`0x01`).
    *   *Status ab macOS 27 Beta 4+ / Build 26A428:* Durch `AppleSMC.kext` mit `kIOReturnNotPrivileged` (`0xe00002c1`) blockiert.
    *   *Konfidenz:* **Bestätigt**.
*   **Hardware-Pass-Through ohne Apple-Entitlement:**
    *   Aktuell gibt es **keinen ungeschützten SMC-Key**, der auf Firmware `20457.x+` rein das Laden stoppt, während das Netzteil das MacBook weiter mit Strom versorgt (echter Bypass).
    *   *Konfidenz:* **Bestätigt**.

---

### (b) Ladelimit setzen (z. B. 80 %)
*   **Keys `bfG0` und `CHLT` (vorhanden auf diesem Mac: `[50 05 03]`):**
    *   *Datentyp:* `hex_`, Länge: 3 Bytes.
    *   *Bedeutung der Bytes:*
        *   Byte 0: `0x50` = **80** dezimal (aktuelles Ladelimit in Prozent).
        *   Byte 1: `0x05` = **5** dezimal (Schrittweite / Hysterese-Delta von 5 %, entsprechend Apples 80, 85, 90, 95, 100 %).
        *   Byte 2: `0x03` = **3** dezimal (Status-Flags: Limit aktiv / Enabled).
    *   *Schreibbarkeit:*
        *   `bfG0`: Hard-locked auf `PowerUIAgent`. Externe Schreibzugriffe werden ignoriert oder schlagen fehl.
        *   `CHLT`: SMC-Firmware weist Schreibzugriffe ab (`kIOReturnNotPrivileged` bzw. Bus-Fehler).
    *   *Konfidenz:* **Bestätigt** (Quellen: `scarriffle.com` SMCAccess.swift, r/MacOSBeta, Onyx-Helper).
*   **Natives System-Ladelimit (macOS 26.4 Tahoe / macOS 27):**
    *   Apple unterstützt seit macOS 26.4 Ladelimits von 80 % bis 100 % nativ in *Systemeinstellungen → Batterie*.
    *   Wird von `powerd` via `com.apple.private.iokit.soc-limit` direkt in die Firmware programmiert.
    *   *Konfidenz:* **Bestätigt**.

---

### (c) Netzteil trennen (Inhibit Power Adapter / Force Discharge)
*   **Key `CHIE` (vorhanden auf diesem Mac: `hex_ [00]`):**
    *   *Datentyp:* `hex_`, Länge: 1 Byte.
    *   *Berechtigung:* **Root (UID 0)** reicht aus! Kein privates Entitlement nötig!
    *   *Exakte Byte-Werte:*
        *   **`0x08`**: Netzteil trennen (Adapter Inhibit / Force Discharge on). MacBook wechselt sofort auf Akkubetrieb, Ladung stoppt, Akku entlädt sich.
        *   **`0x00`**: Netzteil wieder zuschalten (Adapter Inhibit off). Normaler AC-Betrieb und Laden wird fortgesetzt.
    *   *Verwendung in OSS-Projekten:*
        *   `charlie0129/batt`: Nutzt `CHIE` im **Adapter-Modus** als primären Fallback für macOS 27 Beta 4+.
        *   `actuallymentor/battery`: `FORCE_DISCHARGE_ON = $smc_binary -k CHIE -w 08`.
        *   `amperebattery.app`: `CHIE = 0x08` für "Discharge to Upper Bound".
    *   *Nebeneffekte:*
        1. Löst USB-C Power Delivery (PD) Renegotiation aus (kann kurzes Flackern an externen Bildschirmen verursachen).
        2. Im Clamshell-Modus (Deckel geschlossen + Monitor) versucht der Mac in Sleep zu gehen, es sei denn, eine `IOPMAssertionCreateWithName` (PreventUserIdleSystemSleep / NoIdleSleepAssertion) verhindert dies.
    *   *Konfidenz:* **Bestätigt**.

---

### (d) Weitere vorhandene Keys auf diesem Mac
*   **`CHCC` / `CHCE` / `CHCR` (`ui8 [01]`):**
    *   *Bedeutung:* Charger Control / Charger Enable / Charger Request. Zeigen an, dass das Ladegerät hardwareseitig aktiv und bereit ist.
    *   *Konfidenz:* **Vermutet**.
*   **`CHCF` (`hex_ [03]`):**
    *   *Bedeutung:* Charger Configuration (Bitmaske für Lademodi).
    *   *Konfidenz:* **Vermutet**.
*   **`CHSC` / `CHSE` / `CHST` (`ui8 [00]`):**
    *   *Bedeutung:* Charger State Control / State Enable / State Status.
    *   *Konfidenz:* **Vermutet**.
*   **`CHFS`, `CHIF`, `CHPS` (`ui32 [1]`):**
    *   *Bedeutung:* Charger Fast-Charge Status, Charger Inhibit Flag, Charger Power Status.
    *   *Konfidenz:* **Vermutet**.
*   **`BFLO` (`ui8`), `BFS0` (`ui64 [02]`):**
    *   *Bedeutung:* Battery Flow / Battery Feature Status.
    *   *Konfidenz:* **Vermutet**.
*   **`bfJ0`, `bfK0` (`ui8 [01]`), `bfI0` (`si8 [5c]` = 92 dezimal):**
    *   *Bedeutung:* Firmware-interne Grenzwerte / Thermische Schwellenwerte.
    *   *Konfidenz:* **Vermutet**.

---

## 3. Berechtigungs- und Signatur-Matrix

| Mechanismus / Key | Root (UID 0) nötig? | Apple-Private-Entitlement nötig? | SIP-Abhängigkeit |
| :--- | :--- | :--- | :--- |
| **`CHIE` (Adapter-Cut)** | **Ja** (via Root-Daemon/XPC) | **Nein** | Funktioniert mit **SIP aktiviert** |
| **`bfD0`/`bfE0`/`bfF0`** | Ja | **Ja** (`com.apple.private.iokit.soc-limit`) | Blockiert bei SIP; nur mit SIP off + Selbstsignatur nutzbar |
| **`AppleSmartBattery` Write** | Ja | **Ja** (`com.apple.private.iokit.soc-limit`) | Blockiert bei SIP |
| **Natives macOS 80% Limit** | Nein (Benutzer-Einstellung) | Wird von `powerd` gehalten | Voll kompatibel |

---

## 4. Code-Referenzen & Zitate aus den OSS-Repositories

### 1. `charlie0129/batt` (Issue #152)
> *"Starting with macOS 27 Developer Beta 4... Apple restructured the interface:*  
> *- The legacy direct-control keys `CH0B`, `CH0C`, `CHTE` still exist in the SMC key table but are zero-size placeholders (`DataSize == 0`).*  
> *- The firmware-limit keys `bfF0`, `bfD0`, `bfE0` still exist... but every IOKit SMC operation against them now fails with `kIOReturnNotPrivileged` (`0xe00002c1`), even when running as root...*  
> *- Where the functionality moved: `powerd` on the affected firmware contains a private 'SOC limit' subsystem... exposed only to clients holding `com.apple.private.iokit.soc-limit`."*  
> *(URL: https://github.com/charlie0129/batt/issues/152)*

### 2. `charlie0129/batt` (Adapter Mode Logik)
> *"To keep charge limiting working, including limits below 80%, batt offers an opt-in adapter mode... The adapter (wall-power) SMC key is not entitlement-gated, so batt runs the same ThinkPad-style hysteresis loop it uses in legacy mode, but toggles wall power instead of the charge state:*  
> *- When the battery reaches the upper limit, batt cuts wall power (`CHIE = 0x08`), so the charge falls.*  
> *- When the battery drops to the lower limit, batt restores wall power (`CHIE = 0x00`) and the Mac charges again."*  
> *(URL: https://github.com/charlie0129/batt)*

### 3. `actuallymentor/battery` (`battery.sh`)
```bash
# Zeilen 158-159 & 291-303 aus battery.sh:
Cmnd_Alias FORCE_DISCHARGE_OFF = $smc_binary -k CH0I -w 00, $smc_binary -k CHIE -w 00, $smc_binary -k CH0J -w 00
Cmnd_Alias FORCE_DISCHARGE_ON  = $smc_binary -k CH0I -w 01, $smc_binary -k CHIE -w 08, $smc_binary -k CH0J -w 01

function enable_discharging() {
    if [[ "$smc_supports_adapter_chie" == "true" ]]; then
        smc_write_hex CHIE 08
    fi
}
function disable_discharging() {
    if [[ "$smc_supports_adapter_chie" == "true" ]]; then
        smc_write_hex CHIE 00
    fi
}
```
*(URL: https://raw.githubusercontent.com/actuallymentor/battery/main/battery.sh)*

### 4. `killerk3emstar/OpenDente` (macOS 26.4 Native Limit Koexistenz)
> *"In macOS 26.4, Apple shipped their own charge limit in System Settings → Battery (80% up to 100% in 5% steps). OpenDente works fine alongside it... OpenDente also detects when it's the system limit that's blocking charging, via `NotChargingReason` bit 24."*  
> *(URL: https://github.com/killerk3emstar/OpenDente)*

### 5. `amperebattery.app` (Dokumentation zu `CHTE` und `CHIE`)
> *"CHTE (Charge Inhibit): A key used to pause (0x01) or allow (0x00) charging. Note that as of macOS 27 and the macOS 26.7 update, this key is no longer available in the firmware; Ampere instead utilizes macOS's built-in charge limit feature.*  
> *CHIE (Active Discharge): A key used to toggle active discharging (0x08) or normal operation (0x00)."*  
> *(URL: https://amperebattery.app)*

### 6. `mhaeuser/Battery-Toolkit` (Archivierungsbegründung)
> *Archiviert am 21. März 2026. Begründung: Durch die Einführung der nativen Ladebegrenzung in macOS 26.4+ und die fortschreitende Abriegelung der SMC-Schlüssel durch Apple ist die Pflege des Low-Level-Treibers nicht mehr sinnvoll fortführbar.*  
> *(URL: https://github.com/mhaeuser/Battery-Toolkit)*

---

## 5. Die 3 vielversprechendsten Lösungswege für BatteryGuard

### Weg 1: Der Adapter-Hysterese-Modus via `CHIE` (Unabhängig von Apple)
*   **Mechanismus:** BatteryGuard Root-Daemon überwacht den Akkustand (z. B. via `IOPSCopyPowerSourcesInfo`).
    *   Wenn Akku $\ge$ Limit (z. B. 80 %): Schreibe `CHIE = 0x08` (Netzteil trennen).
    *   Wenn Akku $\le$ Untergrenze (z. B. 75 %): Schreibe `CHIE = 0x00` (Netzteil verbinden).
*   **Vorteile:** Funktioniert bei 100 % aktiviertem SIP, benötigt keine privaten Entitlements, erlaubt beliebige Zielwerte (auch z. B. 50 % oder 70 %).
*   **Einschränkungen:** Akku wird zyklisch be- und entladen; im Clamshell-Modus muss `IOPMAssertionCreateWithName` gesetzt werden; kurzes Display-Flackern durch USB-PD-Renegotiation möglich.

### Weg 2: Hybrider / Native-Coexistence-Modus (Empfohlen für Endnutzer)
*   **Mechanismus:**
    *   Für das Standard-Limit von **80 %**: Nutzung des nativen macOS-Limits (System Settings).
    *   BatteryGuard liest `bfG0` / `CHLT` (`[50 05 03]`) und `NotChargingReason` (Bit 24) aus, um dem Nutzer im Menübar-Widget transparent den Status anzuzeigen ("Natives 80%-Limit aktiv").
    *   Zusätzlich bietet BatteryGuard die Funktionen, die Apple fehlen: sailing / Hysterese-Entladung bis 75 %, Force Discharge via `CHIE 08`, Benachrichtigungen und Statistiken.
*   **Vorteile:** Null Risiko von Hardwareschäden, absolut stabil, keine Display-Disconnects, nativer Bypass durch macOS-Firmware.

### Weg 3: Privileged Entitlement Injection (Entwickler / Power-User mit SIP off)
*   **Mechanismus:** Wenn der Nutzer SIP deaktiviert (`csrutil disable`), kann der BatteryGuard-Daemon lokal mit dem Entitlement `com.apple.private.iokit.soc-limit` signiert werden.
*   **Ergebnis:** Dadurch werden die Keys `bfD0`, `bfE0`, `bfF0` und `CHLS` sowie `AppleSmartBattery` im IOKit sofort wieder beschreibbar.
*   **Vorteile:** Ermöglicht echte Firmware-Ladekontrolle (Hardware-Bypass) für jeden Prozentwert.
*   **Einschränkung:** Nur für Power-User mit deaktiviertem SIP geeignet, nicht für den Standard-Endanwender.
