# B-Guard Entwicklungs-Journey

Dieses Journal hält Entscheidungen, Änderungen, Belege und offene Punkte für spätere Reviews fest. Anhängen statt alte Prüfergebnisse umzuschreiben. Einträge unterscheiden Codeprüfung, Simulation, CI, physische Hardware und Kurzbefehle-Systemtests. Entwickler-Journey und private Nutzermessungen sind getrennt.

## 2026-10-05 — Ausgangsreview von 0.3.7

- Basis-Commit: `06288623f1b8462bef94a691a26bd40c297cb447`.
- Geprüft: README/Roadmap, Paketaufbau, Controller, ScheduleRunner, ConfigServer, Sonderaktionsmodell, Batterie-Reader, App Intents, Diagnoseexport und Build-/Notarisierungsskripte.
- Beobachtung: App/Shared/Dienst getrennt; typisierte atomare Aktionen und Peer-UID-Prüfung vorhanden; erneuerte Sonderaufträge werden über Request-IDs geschützt.
- [macOS-CI-Lauf 37266672125](https://github.com/darkspike1988/BatteryGuard/actions/runs/37266672125): Tests, Shellsyntax, Release-Bundle, App-Intents-Metadaten, Bundle-Signaturprüfung und DMG erfolgreich. Das belegt genau diesen Commit und den Community-Build.
- Release v0.3.7 veröffentlicht; Community-App nicht notarisiert.
- Offene Abnahme: physische Modell-/Anschlussmatrix, echte Kurzbefehle-App, Developer-ID-Pfad und frischer Download-/Installationslauf.
- Historischer Gerätebaseline aus ACCEPTANCE.md: MacBookPro18,3, macOS 27.0/26A428, App 0.3.7, laufender Dienst damals 0.3.2, keine separate Ladesperre nachgewiesen, keine gültige Codesign-Identität. Vor jedem Test neu ermitteln.
- Einschränkung: kein macOS-Gerätezugriff in dieser Sitzung; keine neue Hardwarewirkung geprüft. Frühere lokal berichtete Messungen sind historische Angaben, keine neuen Sessiontests.

## 2026-10-05 — Reproduzierbare Abnahme und zukünftige Diagnostik

Auslöser: Nutzer möchte die offenen Abnahmeschritte einbauen, eine später auswertbare Doku-Journey und einen weiteren Plan für Akku-/Mac-Gesundheit.

Entscheidungen:

- Bestehende sicherheitsrelevante Hardwarefreigaben bleiben unverändert; ohne physische Belege keine neuen Steueraktionen freischalten.
- 25 definierte Abnahmefälle mit eigener Umgebung, Sollverhalten, Durchführung, Beobachtung und Belegreferenzen.
- Lokales JSON-Journal mit gesperrten/ungeprüften Fällen, separaten Simulationen und angehängten Wiederholungen. Keine automatische Sammlung oder Übermittlung.
- Markdown-Auswertung zeigt letzte fallbezogene Ergebnisse und alle früheren Fehlversuche. Sie bewertet Beleginhalte nicht selbst und erzeugt keine universelle Freigabe.
- Roadmap-Paketübersicht an 0.3.7 angepasst; bestehende Zielbeschreibungen und Historie erhalten.
- Praktische Kurzbefehle-Journey und Notarisierungs-/Installationsabnahme dokumentiert. Vorhandener Notarisierungsablauf wiederverwendet; kein Zertifikat erzeugt, kein Release veröffentlicht.
- [Diagnostikplan D0–D6](DIAGNOSTICS_PLAN.md): Qualität/Einheiten zuerst, danach Akku-Zustand, Langzeitverlauf und lesende Ressourcen; erklärbare Hinweise erst mit validierter Datengrundlage. Vorschläge sind nicht als implementiert gekennzeichnet.

Änderungen: `docs/validation/`, `scripts/validation-journal.py`, Journaltests, CI-Testschritt, README, ROADMAP, Kurzbefehle-/Release-Dokumentation und Diagnostikplan.

Validierung dieser Änderung: Acht Python-Tests auf Linux bestanden (leeres Journal, Simulationstrennung, Fehlerhistorie, ungültige Belege/Nachweisarten/Fälle, unbekannte Umgebung, Zeitstempel, CLI-Schreiben mit unveränderten Bytes bei Fehler und Fallkatalog). Journal-CLI nutzt nur die Python-Standardbibliothek. Neue macOS-CI und physische Abnahme bleiben bis zum jeweiligen erfolgreichen Lauf offen.

Nächste Schritte: Erste reale Journalsession auf einem verfügbaren Mac; Kurzbefehle S01–S08; Zertifikat vorbereiten und R02–R04 durchführen. Danach D0 als isolierte Implementierung starten.

## 2026-10-05 — Erster Diagnoseausbau 0.4.0

Nutzerauftrag: den Ausbauplan schrittweise ausführen. Ausgangspunkt: Merge von Pull Request #1, Commit `0f9ca24b919f24ad67897b3d002e14d560adbb02`. Der Dokumentations-PR hatte eine erfolgreiche macOS-CI (Lauf 37331621506).

- D0: Additiver Messvertrag mit festen Quellen, normierten Einheiten, Frische, Datenqualität und validiertem Decoding. Alte Status-/API-Einheiten bleiben erhalten. Akku-Reader ergänzt Diagnosewerte ohne neue Hardwaresteuerung.
- D1: Kapazitätsquote klar benannt; oberhalb 100 % sichtbar; unbekannte Temperatur nicht als grün/0 °C dargestellt. Schmale belegte Zyklusreferenz für das bekannte 2021er MacBook-Pro-Modellpaar; andere Modelle unbekannt.
- D2, erste Stufe: freiwillige lokale Tagesaggregate für Kapazität, standardmäßig aus, bis zu 365 Tage. Quellen-/Design-/OS-Wechsel verhindern eine unzulässige Trendbehauptung. Raw-Siebentageverlauf bleibt erhalten; SQLite-/30-Tage-Ausbau bleibt geplant.
- D3, erste Stufe: sichtbare lesende Diagnose für öffentlichen Thermalzustand, CPU-Intervalllast, definierte RAM-Kategorien, Swap und Volumekapazität. Höchstens alle zehn Sekunden über den bestehenden Poller; beim Schließen zurückgesetzt. Kein Speicherdruck, SSD-Verschleiß, Lüfter-/GPU- oder Prozessurteil.
- D4, erste Stufe: Version-1-Hinweise unterscheiden Datenlücken, Quellenlimits, erhöhte macOS-Thermik und momentane CPU-Last. Keine dauerhaften Warnungen oder allgemeine grüne Gesundheitsnote; Fehlalarm-/Pilotabnahme bleibt offen.
- D5, erste Stufe: auswählbare Prüffragen, transparente Quellenanzeige, benutzergewählter Messbericht und authentifizierter REST-Leseendpunkt. Keine automatischen Belastungszyklen oder Kausalitätsbehauptungen. Zeitlich geführte Vorher-/Nachher-Journeys bleiben geplant.
- D6: neue Logik-/Datei-/API-Tests und CI-Vorschauen. Lokal bestanden 22 Swift-Tests (Messvertrag, Analyse, Kapazitätsablage und bestehende Verlaufsablage) sowie acht Python-Journaltests. Vollständige App-/API-Tests und Release-Build werden separat in macOS-CI geprüft. Physische Sensor-, Performance- und Notarisierungsabnahme bleiben offen.

Unter Linux wurde Swift 6.0.3 für den plattformunabhängigen Kern verwendet. Der SwiftPM-Kindprozess stürzte in dieser Umgebung beim Modulaufbau ab; direkter Swift-Compiler-Aufruf und derselbe Swift-Testing-Runner funktionierten. Das ist eine Umgebungseinschränkung, kein bestandener macOS-App-Build.

Prüfbeleg für Implementierungscommit `b6e143dfe29bff393c51959ca9de4191d4f491bb`: [macOS-CI 37336587918](https://github.com/darkspike1988/BatteryGuard/actions/runs/37336587918) erfolgreich. 210 Swift-Testing-Tests in 30 Suiten und 96 XCTest-Tests bestanden (306 insgesamt), außerdem acht Journaltests, Shellsyntax, Release-Build, App-Intents-Metadaten, Bundle-Signaturprüfung und Community-DMG. Gerenderte Diagnoseansichten in Hell/Dunkel visuell geprüft: alle fünf Panels lesbar, keine abgeschnittenen Inhalte in der 840 × 1600-Vorschau. Kein Nachweis für native Bedienung auf kleinen Displays oder VoiceOver.

Bei der Abschlussprüfung korrigiert: UTC-Tageslabel verwendet nun ausdrücklich UTC; Quellen-/Qualitätsbegriffe in der Oberfläche sind auf Deutsch erklärt. Exakte Quellenkennungen bleiben im Bericht. Diese Abschlussänderung benötigt ihren eigenen erfolgreichen CI-Lauf.

Nächste Schritte: (1) gleichzeitiger Sensor-/Ressourcenvergleich auf dem Referenz-Mac samt Eigenverbrauch; (2) Vergleich auf weiteren Modellen und dokumentierter Messabdeckung; (3) auf dieser Basis Mindestdauer/Hysterese und geführte Vorher-/Nachher-Journeys ausbauen. Ohne diese Belege keine allgemeine Gerätegesundheit oder Alterungsprognose behaupten.

Weitere Informationen und Datenvertrag: [diagnostics-0.4.md](diagnostics-0.4.md).

## Vorlage für den nächsten Eintrag (Fortsetzung)

- Datum und konkreter Ausgangscommit/Version:
- Nutzerziel und Entscheidung:
- Geänderte Dateien/Funktionen:
- Tatsächlich ausgeführte Prüfungen und Beleglinks:
- Befunde und korrigierte Fehler:
- Offene Abnahmen/Blocker:
- Nächste drei Schritte:
