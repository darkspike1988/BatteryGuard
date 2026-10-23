# B-Guard 0.8.0 (Arbeitsstand, unveröffentlicht)

0.8.0 bringt Automatisierung und mehr persönliche Einstellungen. App und Hintergrunddienst haben Version 0.8.0.

## Zeitpläne (R11)

- **Vorlagen:** „Montag früh voll laden“ (Montag 5:00, Top Up vier Stunden), „Wochenende voll laden“ (Samstag 7:00, Top Up bis zum Abstecken, höchstens 24 Stunden) und „Spitzenlastzeit“ (werktags 17:00 Schreibtisch-Profil, 21:00 Alltag). Vorlagen erzeugen gewöhnliche Zeitpläne, die sich danach bearbeiten lassen. Eine jährliche Wiederholung gab es bereits.
- **Aufgabenverlauf löschen** mit Rückfrage; neue Aktion `clear-schedule-history`.

## Befehle, Kurzbefehle, Tastenkürzel (R12, R13)

- **URL-Schema `bguard://`:** `profile/desk|everyday|mobile`, `limit/60?lower=50`, `pause?minutes=60`, `resume`, `top-up`, `full-charge`, `cancel-full-charge`, `protection/on|off`, `power-mode?low=…&high=…`, `led/system|indicate|off`. Alle Befehle laufen über dieselbe validierte Aktionslogik wie UI, REST und Kurzbefehle.
- **Terminal:** `B-Guard.app/Contents/MacOS/BatteryGuard --run "bguard://limit/60"` gibt die gespeicherte Konfiguration als JSON aus oder beendet sich mit Fehler.
- **Kurzbefehle:** neu „Ladelimit setzen“ (20–100 %, optional untere Grenze) und „MagSafe-LED setzen“; neue Aktion `magsafe-led` auch in der lokalen API.
- **Globale Tastenkürzel** (abschaltbar, standardmäßig aus): ⌃⌥⌘F Vollladen ein/aus, ⌃⌥⌘P Pause eine Stunde/Fortsetzen, ⌃⌥⌘L Low Power Mode immer/aus. Carbon-Hotkeys benötigen keine Bedienungshilfe-Freigabe.

## Regeln nach WLAN (R14)

Ladeprofile je WLAN-Name, zum Beispiel Büro → Schreibtisch. Beim Wechsel in ein WLAN mit Regel wählt die App das Profil; wie eine manuelle Wahl pausiert das Zeitpläne für zwei Stunden. macOS nennt den WLAN-Namen nur mit Standortfreigabe; B-Guard fragt sie erst beim Aktivieren an, speichert keinen Standort und vergleicht den Namen nur lokal. Funktioniert, solange die App läuft.

## Menüleiste und Menüfenster (R15, R16)

- Eigene Anzeige auf Akku (zum Beispiel Restlaufzeit statt Prozent), Menüleistensymbol ausblendbar (nur mit Dock-Symbol; erneutes Öffnen aus Programme blendet es wieder ein), Hardware-Ladestand als Zusatzwert.
- Stile für das Menüfenster (Minimal, Gesundheit, Profi) setzen die Karten auf einen Schlag; die Reihenfolge bleibt.
- Darstellung hell, dunkel oder wie macOS; Akzentfarbe für Menüfenster und Hauptfenster.
- Karten verschieben bleibt bei den Pfeiltasten statt Drag-and-drop, damit es mit Tastatur und VoiceOver bedienbar bleibt.

## Einrichtung und Restlaufzeit (R17, R18)

- Nach erfolgreicher Dienst-Einrichtung fragt B-Guard, wie der Mac meist genutzt wird, und schlägt Schreibtisch, Alltag oder Unterwegs vor; übernommen wird nur nach Klick.
- Die Übersicht zeigt eine Restlaufzeit aus dem durchschnittlichen Entladefluss der letzten 5, 15 oder 60 Minuten (mindestens fünf Messpunkte auf Akku) neben dem Momentanwert von macOS.

## Prüfstand

280 Tests in 44 Suiten (Swift Testing) bestanden, neu: Vorlagen und Validierung, Verlauf löschen, alle URL-Befehle und Fehlerfälle, LED-Aktion, WLAN-Regelwechsel, Restlaufzeit, Tastenkürzel-Befehle, Menüfenster-Stile.
