# Funktionsrecherche: Was B-Guard noch fehlt

Stand: 23. Oktober 2026, Arbeitsstand 0.6.0 (Branch `release/0.6.0`). Grundlage: Webrecherche zu AlDente, batt, Battery Toolkit, BatFi, coconutBattery, iStat Menus und Apples eigenen Funktionen; GitHub-Issues und -Discussions (👍 = Reaktionen, c = Kommentare); statische Bundle-Analyse von AlDente 1.39.4 mit REA. Reddit lieferte bei drei Suchen keine Treffer und ist nicht berücksichtigt.

**Grenze der AlDente-Analyse:** AlDentes Lizenz schließt das Dekompilieren aus. Mit REA wurden nur Info.plist, Signatur, gelinkte Bibliotheken, Importtabellen, Interface-Builder-Archive und mitgelieferte Texte gelesen; kein Code wurde übersetzt oder übernommen. Alle B-Guard-Funktionen bleiben eigenständig implementiert.

## 1. AlDente 1.39.4 laut Bundle (REA)

| Beobachtung | Beleg | Bedeutung für B-Guard |
|---|---|---|
| 15 Siri/Kurzbefehl-Intents: Limit setzen, Laden starten/stoppen, Entladen, Kalibrieren, MagSafe-LED, Low/High Power Mode, Status/Temperatur/Limit lesen | Info.plist `INIntentsSupported`, `NSUserActivityTypes` (Evidence `ev_71615e27…`) | B-Guard hat Profil, Top Up, Pause, Energiemodus und Lesen; es fehlen Limit setzen, Laden stoppen/starten, LED, Temperatur |
| URL-Schema `aldente://` | Info.plist `CFBundleURLTypes` | Automatisierung ohne Kurzbefehle/REST |
| Developer-ID-signiert, Hardened Runtime, Sparkle-Updates mit EdDSA-Schlüssel, Setapp-Vertrieb | `inspect_signature` (`ev_ffaf4a69…`), Info.plist `SUFeedURL`, `SUPublicEDKey` | Notarisierung und signierte Auto-Updates fehlen in B-Guard |
| Universal-Binary (x86_64 + arm64), „Intel Mode“ | Signatur, UI-Texte | B-Guard bleibt bewusst Apple Silicon |
| Privates `DisplayServices`, `CGDisplayIsBuiltin` | Abhängigkeiten (`ev_65d98c5f…`), Importe | „Display aus bei Inaktivität“, wenn der Schlaf deaktiviert ist |
| Helper: `IOPMSetSystemPowerSetting`, `IOPMSleepSystem`, `IOPMAssertionCreateWithName`, `IOPMCopyAssertionsStatus`, `NSTask` | Importtabelle des Helpers | Schlaf vollständig deaktivieren (auch zugeklappt), sofort schlafen bei zugeklapptem Deckel ohne Netzteil, Assertion-Prüfung |
| SQLCipher + SQLite | Abhängigkeiten | Verschlüsselte lokale Statistik; B-Guard speichert JSON mit 0600 |
| UI fast vollständig SwiftUI; Popover-Widgets per Drag-and-drop, Stile „Minimalist / Health Focused / Power User“, Graphen im Popover, Akzentfarbe, Hell/Dunkel | Interface-Builder-Archive (nur Hauptmenü, `ev_f800bdc8…`), UI-Texte | Oberflächenkomfort |
| Zeitplan-Vorlagen (Montag 5 Uhr Top Up, Samstag voll, zweiwöchentlich/monatlich kalibrieren), jährliches Intervall, Verlauf löschen | UI-Texte `dsc*`, `txt*Calibration` | B-Guard hat Zeitpläne, keine Vorlagen |
| Einstellungen per Systemadministrator sperrbar, Einstellungen sichern/wiederherstellen, Debug-Export | `hlpSettingsLock`, `ttlSettingsBackup`, `lblDebugExport` | IT-Funktion fehlt in B-Guard |
| Mitteilungen: über das Limit geladen beim Start, externer Monitor liefert keinen Strom, Ladezustand aktualisiert verzögert | `txtMacOverchargedNotice`, `hlpMonitorAttachedCannotCharge`, `ttlDelayedChargeStateBackend` | Fehlen in B-Guard |
| Einrichtungsumfrage („meist zuhause / unterwegs“), Popover-Stil mit Live-Vorschau | `ttlSetupSurvey`, `txtPresetInfo` | Einrichtung |
| Restlaufzeit aus Durchschnitt oder Momentanwert | `hlpPowerGraphTime`, `hlpPowerGraphValue` | B-Guard zeigt nur den macOS-Wert |
| 30 Sprachen | `*.lproj` | B-Guard: 3 |

## 2. Wettbewerb und Nutzerwünsche (Webrecherche)

| Funktion | Wer hat es | B-Guard | Quelle |
|---|---|---|---|
| Limit unter 80 % auf macOS 27 | AlDente 1.39 (Schalter), BatFi 4 (50–100 %, Weg unbekannt), batt (adapter-mode, nur wach) | teilweise (Pendel) | AlDente-Releases, micropixels.software/batfi, github.com/charlie0129/batt |
| Umgang mit Apples Zwangskalibrierung (`ChargingUpForGauging`), danach zurück aufs Limit | AlDente 1.40 Beta | nein | AlDente-Issue #1846 (43c, angeheftet), #1840 |
| Energiefluss mit USB/Display | AlDente 1.38 | teilweise (SoC) | AlDente-Releases |
| Ladegrenze nach Ort/WLAN, globale Tastenkürzel | BatFi | nein | micropixels.software/batfi |
| Warnung „externer Monitor lädt trotz Limit / liefert keinen Strom“ | AlDente 1.37 | teilweise (Panel, keine Mitteilung) | AlDente-Releases |
| Kälteschutz (Laden unter Frost sperren) | Wunsch AlDente #675, #1392 | nein | AlDente-Issues |
| Ladeton abschalten | Wunsch batt #77 | nein | batt-Issue #77 |
| Akkus von Bluetooth-Geräten | iStat Menus, coconutBattery, Juicy | nein | bjango.com, coconut-flavour.com |
| Lebensdauer-Analyse, Druckbericht | coconutBattery Plus | teilweise | coconut-flavour.com |
| Menüleiste je Zustand, Symbol ausblenden | iStat Menus; Wünsche AlDente #59 (8👍), battery #283 (17👍) | nein | Issues |
| Desktop-Widgets | Wunsch AlDente #1418 (6👍) | nein | AlDente-Issue #1418 |
| Kommandozeile, AppleScript | batt; Wünsche AlDente #637, #638 (je 6👍) | teilweise (REST, Intents) | AlDente-Issues |
| Einstellungen exportieren | Wunsch AlDente #1103 | teilweise (Profile) | AlDente-Issue #1103 |
| Limit zu Spitzenlastzeiten senken | Wunsch AlDente #445 (19c) | teilweise (Zeitpläne) | AlDente-Issue #445 |
| Homebrew-Cask | Wünsche batt #9, #81; Battery Toolkit #12 | nein | Issues |

**Größte Beschwerden:** Brüche nach macOS-/Firmware-Updates (actuallymentor/battery #386 81👍, #477; batt #34 64c; AlDente #1529 140c), Apples Kalibrierung lädt trotz Limit auf 100 % (AlDente #1846), Laden über das Limit und im Schlaf (batt #115, #127, #147), Clamshell-/Dock-Konflikte beim Netzteil-Schalten (batt #151, AlDente #1854). Vertrauensthemen (Telemetrie, Auto-Update, wiederholte Passwortabfrage) sprechen für B-Guards Offline- und Open-Source-Ansatz.

## 3. Technische Befunde zu macOS 26/27

- **Apple-Limit:** ab macOS 26.4, nur Apple Silicon, 80–100 %, Nachladen nach mehr als 5 % Abfall, gelegentliche Vollladung zur Ladestandsschätzung (support.apple.com/102338). B-Guards Messung auf MacBookPro18,3: PowerUI bietet 80/85/90/95/100 an, Server akzeptiert jede Zahl 80–100 (eigene REA-Analyse, siehe [release-notes-0.6.0](../release-notes-0.6.0.md)).
- **Firmware statt macOS-Version entscheidet:** Ab macOS-27-Beta-4-Firmware sind die SMC-Ladesperren gesperrt; die Sperre kam auch mit Firmware-Updates in macOS 26.7 und 15.8 (batt-README, batt #151, battery #482). Ein Downgrade setzt die Firmware nicht zurück.
- **Natives Limit und Netzteil-Schalter (zu prüfen):** Laut actuallymentor/battery PR #480 ignoriert die Firmware `CHIE` bei aktivem nativem Limit und **entlädt selbst am Netzteil**, wenn der Akku über dem Limit liegt. Das betrifft B-Guards Pendel-Modus und eröffnet einen Weg für „Einmal entladen“ auf 80–95 %.
- **Unter 80 % ohne Netzteil-Schalten:** angeblich über root-Werte `MCLFeatureState`/`mclLimitValue` in `com.apple.smartcharging.topoffprotection` (PR #480, ungetestet). Unter 80 % lässt `setMCLLimit` laut PR abstürzen; B-Guard sendet nur angebotene Stufen.
- **Gauging-Kalibrierung:** Log-Hinweise „Battery mitigations are in place, MCL will be ignored“ und `ChargingUpForGauging`; nach etwa drei Tagen ohne Entladetiefenänderung fordert macOS eine Vollladung an (Community/AlDente-Maintainer, keine Apple-Aussage). Kein Tool kann das verhindern; erkennen und erklären ist möglich.
- **macOS 27.2-Beta:** Darstellungsfehler bei SwiftUI-Popovers (AlDente #1831, #1832) – B-Guards Menüfenster beobachten.

## Quellen

- https://github.com/AppHouseKitchen/AlDente-Battery_Care_and_Monitoring/releases und Issues #1846, #1840, #1418, #637, #638, #1103, #445, #675, #1392, #59
- https://apphousekitchen.com/aldente-overview/pricing/
- https://github.com/charlie0129/batt (README, Issues #34, #77, #151)
- https://github.com/actuallymentor/battery/pull/480 und Issues #283, #386, #477, #482
- https://github.com/mhaeuser/Battery-Toolkit (archiviert seit 21.03.2026)
- https://micropixels.software/batfi
- https://www.coconut-flavour.com/coconutbattery/
- https://bjango.com/help/istatmenus7/power/
- https://support.apple.com/102338
