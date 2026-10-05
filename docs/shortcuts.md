# Experimentelle macOS-Kurzbefehle

Ab 0.3.6 sind zwei experimentelle App Intents enthalten: **Akkustatus lesen** und **Energiefluss lesen**. Beide liefern JSON-Text. Sie benötigen keinen API-Token und ändern keine Ladeeinstellungen. Der vorhandene Dienst 0.3.2 genügt; für den Energiefluss wird direkt eine lesende IOKit-Abfrage verwendet.

In **Kurzbefehle** einen neuen Kurzbefehl anlegen, in der Aktionssuche nach **B-Guard** suchen, eine der beiden Aktionen hinzufügen und ausführen. Die JSON-Ausgabe lässt sich mit der Aktion „Wörterbuch aus Eingabe abrufen“ weiterverarbeiten.

Der Status muss höchstens 60 Sekunden, der Power-Flow-Snapshot höchstens 10 Sekunden alt sein; maximal 5 Sekunden Zukunftstoleranz. Fehlende oder veraltete Daten liefern `{"available":false}`. Beschädigte Statusdaten führen zu einem Fehler. Die Frische bezieht sich auf die Erfassung, nicht auf einen garantierten Sensor-Refresh. `systemWatts` ist geschätzte Mac-Leistung, `adapterRatedWatts` die Netzteil-Nennleistung.

Die Aktionen verlangen mit `openAppWhenRun = false` kein Öffnen im Vordergrund; die App kann im Hintergrund gestartet werden. Ihre normale Startlogik ist davon getrennt.

**Abnahme:** Metadaten und beide automatischen App Shortcuts sind im signierten Bundle enthalten. Beide `perform()`-Methoden wurden mit echten lesenden Daten aufgerufen. Die Erkennung und Ausführung in der systemweiten Kurzbefehle-App wurde noch nicht bestätigt; P2 bleibt daher teilweise umgesetzt. Ab 0.3.7 sind weitere experimentelle Aktionen enthalten: Ladeprofil und Aufträge lesen, Ladeaktion ausführen sowie gespeichertes Ladeprofil anwenden. Steueraktionen benötigen Dienst 0.3.7 und werden erst nach dessen atomarer Speicherbestätigung erfolgreich. Profil-Entities werden aus den eigenen gespeicherten Profilen gelesen; ein gelöschtes Profil führt zu einem Fehler. Nur passende Parameter zur gewählten Aktion ausfüllen. Halten, Einmalentladung und Kalibrierung bleiben ohne physisch bestätigte Hardware abgelehnt.

Entwickler-Build: vollständiges Xcode 27 für den geprüften Metadaten-Schritt. `scripts/build-app.sh` extrahiert und kontrolliert die Metadaten vor der Signierung. Die fertige DMG benötigt beim Nutzer kein Xcode.

[Apple: AppIntent](https://developer.apple.com/documentation/appintents/appintent) · [Apple: AppShortcutsProvider](https://developer.apple.com/documentation/appintents/appshortcutsprovider)

## Systemtest am 5. Oktober 2026

Ein isolierter Harness mit Apples öffentlichem AppIntentsTesting-Framework wurde gebaut und ad-hoc signiert. Die Ausführung scheiterte vor den beiden lesenden Intent-Testfällen mit „Timed out while enabling automation mode“ (xcodebuild Exit 65). Das ist eine Grenze des XCTest-Runners, kein nachgewiesener Intent-Fehler. Kein UI-Zugriff, keine Berechtigungsänderung und keine Veränderung der Kurzbefehle-Bibliothek. Systemausführung und Suchdarstellung bleiben offen; die neuen Schreibaktionen wurden nicht live ausgeführt.

[Apple: AppIntentsTesting](https://developer.apple.com/documentation/appintentstesting/testing-your-app-intents-code)

## Reproduzierbare Journey in Apples Kurzbefehle-App

Vorbereitung: B-Guard aus Programme starten, Dienstversion prüfen, Ausgangsprofil privat notieren und eine neue [Journalsession](validation/README.md) anlegen. REST API darf ausgeschaltet bleiben. Testergebnisse nicht aus einem direkten `perform()`-Aufruf ableiten.

| Fall | Schritte | Erwartung |
| --- | --- | --- |
| S01 | Neuen Kurzbefehl anlegen; nach B-Guard und den exakten Aktionstiteln suchen | Akkustatus lesen, Energiefluss lesen, Ladeprofil und Aufträge lesen, Ladeaktion ausführen, Gespeichertes Ladeprofil anwenden auffindbar |
| S02 | Lesende Aktionen einzeln ausführen; anschließend B-Guard-Oberfläche schließen und erneut ausführen | JSON oder erklärbarer Fehler; keine Vordergrundöffnung erforderlich; fehlende Daten nicht als Nullwerte interpretieren |
| S03 | Ladeaktion ausführen → Profil wählen → Schreibtisch; alle unpassenden optionalen Parameter leer lassen | Dienst bestätigt gespeichertes Profil; danach mit Leseaktion gegenprüfen; Hardwarewirkung separat als H01/H02 testen; Ausgangsprofil wiederherstellen |
| S04 | Schutz pausieren, Dauer 1 Minute; anschließend Schutz fortsetzen, ohne zusätzliche Parameter | Speicherung und Rückkehr nachvollziehbar; Schutzpause setzt auch Hitzeschutz aus; Ausgangszustand wiederherstellen |
| S05 | Halten, Einmalentladung oder Kalibrierung mit passenden Parametern anfragen | Noch nicht physisch freigegebene Aktion wird abgelehnt; keine erfolgreiche Hardwareausführung behaupten |
| S06 | In isolierter Testumgebung ohne aktuellen Dienst Schreibaktion ausführen | Konkreter Fehler; keine fingierte Erfolgsantwort; ohne Testumgebung blocked |
| S07 | UI-/API-/Kurzbefehle-Aufträge kontrolliert überlappen; Reihenfolge und finale Konfiguration notieren | Keine veralteten Abschlüsse löschen erneuerte Anforderungen; API nur für diesen Test ausdrücklich aktivieren und danach zurücksetzen |
| S08 | Temporäres eigenes Profil in Kurzbefehl wählen, in B-Guard löschen, Kurzbefehl erneut ausführen | Fehlermeldung statt Anwendung gelöschter Profildaten |

Die Ausführung kann B-Guard im Hintergrund starten. „Oberfläche geschlossen“ bedeutet daher nicht „kein App-Prozess“. Profilwahl kann den Auto-Modus aktivieren und einen laufenden Vollladeauftrag beenden; Tests bei ruhigem Ausgangszustand durchführen.

Pro Fall Uhrzeit, Schritte, beobachtete Ausgabe und geprüften Beleg im Journal erfassen. Konfigurations-JSON nicht ungeprüft veröffentlichen: Es kann genaue Reisezeiten enthalten. Nach jedem Schreibtest Ausgangsprofil und Ausnahmezustände wiederherstellen. Wenn Aktionen nicht auftauchen, App/Dienstversion, Build und Screenshot dokumentieren; keine Berechtigungsumgehung. Der Systemabnahmestand bleibt offen, bis echte Ergebnisse vorliegen.
