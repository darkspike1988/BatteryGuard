# Release-Abnahme und Notarisierung

Stand: 5. Oktober 2026. Die Community-Version 0.3.7 ist ad-hoc signiert. Ein grüner Community-Build ist keine Developer-ID- oder Gatekeeper-Abnahme.

## Bereits vorhandener Ablauf

`scripts/build-notarized.sh` baut mit Developer-ID und Hardened Runtime, reicht das App-ZIP bei notarytool ein, heftet das App-Ticket an und prüft es. Danach wird die DMG gebaut, signiert, eingereicht, geheftet und geprüft; abschließend werden die finalen Prüfsummen erstellt.

Voraussetzungen auf einem eigenen Test-Mac: vollständiges Xcode 27, gültige Developer-ID-Application-Identität samt privatem Schlüssel, vorbereiteter notarytool-Schlüsselbundeintrag. Diese Sitzung besitzt weder macOS-Testzugriff noch ein Zertifikat; sie führt diesen Ablauf nicht aus.

```sh
export BGUARD_SIGN_IDENTITY='Developer ID Application: DEINE IDENTITÄT (TEAMID)'
export BGUARD_NOTARY_PROFILE='DEIN-SCHLUESSELBUND-PROFIL'
./scripts/build-notarized.sh
```

Die Platzhalter durch vorhandene eigene Einträge ersetzen. Passwörter und API-Schlüssel gehören in den Schlüsselbund, nicht in das Repository oder das Journal. Das Skript veröffentlicht nichts und installiert keinen Dienst.

## Abnahmefälle

| Fall | Prüfung | Erfolgsbeleg |
| --- | --- | --- |
| R01 | Community-Tests, Release-Bundle, Intent-Metadaten, codesign, DMG | Exakter Commit, CI-Lauf und erfolgreiche Schritte |
| R02 | Developer-ID-Pfad vollständig ausführen | Apple-Akzeptanz für App und DMG, stapler validate, spctl und hdiutil erfolgreich |
| R03 | Finale DMG über Browser herunterladen, sauberes Testkonto, Quarantäne erhalten | App-Start ohne manuelle Gatekeeper-Ausnahme; Dienstinstallation und Version geprüft |
| R04 | Vorversion aktualisieren, anschließend Entfernung prüfen | Einstellungen/Verlauf erhalten; Dienstversion korrekt; Rückkehr zu macOS-Ladesteuerung |

Für R03 die Freigabe nicht durch Entfernen der Quarantäne oder „Dennoch öffnen“ ersetzen. Ein Problem als fehlgeschlagen erfassen und konkrete Fehlermeldung bereinigt sichern. Eine bestehende Installation oder lokale Build-Datei ersetzt den Download-Test nicht.

Prüfsummen müssen zum final gehefteten Artefakt passen. Notarisierung belegt den Apple-Prüfprozess, keine physische Ladefunktion. Veröffentlichung erst mit belegtem Status; offene Hardware-/Kurzbefehletests weiter sichtbar halten.

Ergebnisse manuell im [Abnahmejournal](validation/README.md) erfassen. Rohlogs können Identitäts-/Kontodaten enthalten; nur geprüfte Auszüge weitergeben.
