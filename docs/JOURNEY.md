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

## Vorlage für den nächsten Eintrag

- Datum und konkreter Ausgangscommit/Version:
- Nutzerziel und Entscheidung:
- Geänderte Dateien/Funktionen:
- Tatsächlich ausgeführte Prüfungen und Beleglinks:
- Befunde und korrigierte Fehler:
- Offene Abnahmen/Blocker:
- Nächste drei Schritte:
