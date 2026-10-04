# BatteryGuard 0.2 – Funktions- und Designprüfung

## Ziel und Ergebnis

Zusätzlicher Nutzen gegenüber einem einzelnen macOS-Ladelimit: drei Ladeprofile, Reiseplanung, zeitlich begrenzte Ausnahmen, lokaler Messverlauf, Datenexport und konfigurierbare Hinweise. Die Anwendung nutzt eine kompakte Menüleistenansicht und ein eigenständiges macOS-Fenster mit Übersicht, Verlauf und Einstellungen.

## Nachweise

| Anforderung | Nachweis |
| --- | --- |
| Profile | Shared-Profilemodell; AppActionsTests für Aktion und Dateispeicherung; gerenderter Profilzustand |
| Schutzpause mit Wiederaufnahme | Zeitauflösung im Daemon; Test an der Ablaufgrenze; gespeicherte Grundlimits bleiben erhalten |
| Reiseplanung | Tests vor, innerhalb und nach dem Ladefenster; thermischer Vorrang; gerenderter Reiseplan |
| Begrenztes manuelles Vollladen | Ablaufprüfung ohne Benutzeroberfläche; Test für Vollladeabschluss und Rückkehr |
| Lokaler Verlauf | Reale Messpunkte in Benutzer-Datei nach Installation; 0600; Fortschreibung über mehrere Minuten |
| Verlaufsauswertung | Tests für Duplikate, veraltete Daten, Sieben-Tage-Aufbewahrung und ausgeschlossene Schlaflücken |
| CSV | Acht Spalten, stabile Datumswerte, negative Leistung und leere optionale Werte getestet; NSSavePanel als native Exportoberfläche |
| Native Limit-Erkennung | Lesende lokale Diagnose liefert 80 %; unbekanntes CHLT-Layout wird ignoriert |
| UI/UX | Echte SwiftUI-Views in Hell und Dunkel gerendert; zusätzlich native Steuerung, Mindestgröße, fehlende Daten und geplante Reise mit Hitzeschutz geprüft |
| Versionssicherheit | Zeitfunktionen verlangen einen aktiven Dienst ab 0.2; Test für alten Dienst und Verbindungsverlust |
| Betrieb | App läuft nach Installation ohne neuen Absturzbericht; lokaler Verlauf wird fortgeschrieben |

`swift test`: **26 Tests in drei Suites erfolgreich**. Release-Build und ad-hoc signiertes Bundle erfolgreich.

## Designentscheidungen

- Ein Akzent, neutrale Systemfarben, Systemtypografie und klare Abstände.
- Keine permanent animierten Hintergründe.
- Profile sind benannte Handlungsoptionen, technische Details stehen in den Einstellungen.
- Native Steuerelemente für Formulare, Datum, Navigation, Diagramme und Export.
- Messwerte werden ohne aktuelle Daten nicht erfunden; leere Zustände erklären, wie Daten entstehen.
- Nur tatsächlich geänderte Daten lösen Aktualisierungen aus; Verlaufsschreiben und Laden laufen über einen separaten Actor.

## Betriebsgrenzen

App und Root-Dienst sind auf Version 0.2.0 aktualisiert. Die installierten Binärdateien stimmen mit der signierten Distribution überein. Der Dienst liefert frische Messwerte einschließlich des erkannten nativen Limits von 80 %. Der lokale Benutzerverlauf wird fortgeschrieben. Die Versionsvoraussetzung der Zeitfunktionen ist erfüllt. Der Benutzer hat weiterhin den macOS-Beobachtungsmodus gewählt; aktive Ladefunktionen werden erst nach einer ausdrücklichen Moduswahl in der Oberfläche ausgeführt.

Zeitpläne arbeiten bei wachem Mac am Netzteil. Schlaf-/Aufwach-Automation, authentifizierte IPC und vollständige physische Ladezyklus-Tests sind nicht Bestandteil dieser Version. Ein natives macOS-Limit kann höhere Ladeziele verhindern und wird nicht automatisch geändert. Die visuelle Prüfung erfolgte über isoliertes Rendering der echten Views; externe UI-Automation war nicht freigegeben.

Die gerenderten Ansichten unter `docs/previews` verwenden ausgewiesene Beispieldaten, keine Bildschirmaufnahmen des Benutzers.

## Ergänzungen vom 4. Oktober 2026

- Grauweißes App-Icon mit expliziten Bitmap-Größen unabhängig von Retina-Skalierung.
- Fehlgeschlagene Konfigurationsspeicherung behält ungespeicherte Änderungen bis zum erfolgreichen Wiederholen. Regressionstest mit absichtlich blockiertem Dateipfad.
- Menüleiste: Profil-Dropdown, eigene Ladegrenzen, Schutz starten/pausieren, App beenden. Profilwahl beendet laufendes Vollladen und aktiviert bei Bedarf Auto.
- Erststart-Assistent und DMG mit Programme-Link; kein Terminal für die Installation nötig. Administratorfreigabe für den Root-Dienst bleibt erforderlich.
- Keine Developer-ID auf diesem Mac vorhanden: Release ist ad-hoc signiert, nicht notarisiert. Gatekeeper-Freigabe kann beim ersten Download erforderlich sein.
- Bekannte technische Grenzen bleiben: dateibasierte, für lokale Benutzer beschreibbare Konfiguration; Schlafverhinderung beim aktiven Entladen; keine vollständige Hardwareprüfung über Schlaf-/Aufwachzyklen. Diese Punkte werden nicht als erledigt ausgegeben.
