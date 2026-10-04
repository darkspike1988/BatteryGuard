# B-Guard 0.3.3 — Deine Menüleiste

- Anzeige neben dem Ladering wählen: Symbol, Prozent, Akkutemperatur oder Akku-Leistung.
- Temperatur, Akku-Leistung und Akkugesundheit optional im Menüfenster anzeigen.
- Niedrigakku-Warnung unabhängig vom Ladeprofil konfigurieren: 5–50 %, standardmäßig 20 %. Hysterese vermeidet wiederholte Warnungen.
- Akku-Leistung zeigt den Lade-/Entladefluss. 0 W am Netzteil bedeutet nicht 0 W Mac-Verbrauch; dieser Fall wird sichtbar erklärt.
- REST-Steuerbefehle akzeptieren `application/json; charset=utf-8`.
- Update-Downloads werden bei Überschreiten der veröffentlichten Dateigröße bereits während des Transfers abgebrochen. SHA-256-Prüfung und Bereinigung bleiben erhalten.

Appupdate genügt, wenn Hintergrunddienst 0.3.2 installiert ist. Einstellungen und Verlauf bleiben erhalten. Community-DMG weiterhin ad-hoc signiert, nicht notarisiert.

Gemini 3.8 Flash High über die lokale agy-CLI lieferte vier begrenzte Implementierungen. Codex prüfte die Änderungen und korrigierte unter anderem geratene Einheitenumrechnung, Headerbehandlung und Swift-6-Testzustand. Hardwaresteuerung unverändert.

Validierung: 109 Tests (100 Swift Testing und 9 XCTest) erfolgreich; Release-Build und Bundle-Signaturprüfung erfolgreich.
DMG-Prüfsumme und gerenderte Hell-/Dunkelansichten einschließlich aller Menüleistenmodi geprüft.
