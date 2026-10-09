# Arbeitszeitrechner für iPhone

Die iPhone-Version des Arbeitszeitrechners. Sie rechnet genau wie die Android-App: gleiche Pausenregeln
(§ 4 ArbZG), gleiche 20-Stunden-Grenze, gleiche Texte. Sicherungen und Stundenzettel sind mit der
Android-App kompatibel. Voraussetzung ist iOS 17 oder neuer.

**Schnellstart:** [Mit dem Mac installieren](#installation-mit-dem-mac-xcode) oder
[unter Windows mit Sideloadly](#installation-unter-windows-mit-sideloadly) → [Funktionen](#funktionen)

## Funktionen

- **Wochenübersicht** (Mo–So) mit Kalenderwoche und Pfeilen zum Blättern, *Zur aktuellen Woche* springt zurück
- **Wochensumme** mit Fortschrittsbalken, Abstand zur Grenze (rot, wenn überschritten) bzw. offenen
  Stunden und Überstunden sowie der Summe der abgezogenen Pausen
- **Kommen / Gehen** auf der Karte von heute. Während der Arbeit zeigt die App die laufende Zeit und
  z. B. „20 h voll um 18:15“ oder „Tagessoll um 18:45“. Ist die Grenze erreicht, warnt sie rot:
  „20 h voll – jetzt ausstempeln“.
- **Tag bearbeiten:** auf einen Tag tippen. Art (Arbeit, Urlaub, Krank, Feiertag), Beginn, Ende und die
  tatsächliche Pause. Die App zeigt direkt die Rechnung: Anwesenheit − Pause = Arbeitszeit.
- **Automatischer Pausenabzug** (mehr als 6 h → 30 min, mehr als 9 h → 45 min), auf Wunsch gestaffelt
- **Tageshöchstgrenze:** Tage mit mehr als 10 h Arbeitszeit werden markiert (§ 3 ArbZG).
- **Einstellungen:** Wochenstunden (z. B. `20`, `38,5` oder `38:30`), Arbeitstage, Obergrenze an/aus, eigene Pausenregeln
- **Woche teilen** (Teilen-Symbol oben) als Text per Mail, WhatsApp usw.
- **Stundenzettel** (Kalender-Symbol oben): ein Monat als CSV-Datei für Excel, Numbers oder Google Tabellen,
  zum Teilen oder Speichern in „Dateien“
- **Widgets, Kontrollzentrum und Siri** zum Stempeln, ohne die App zu öffnen
- **Automatische Sicherung** nach jeder Änderung in eine selbst gewählte Datei, z. B. in iCloud Drive,
  dazu Backup speichern und wiederherstellen (Einstellungen → *Daten sichern*)
- Alle Daten bleiben lokal auf dem iPhone.

## Installation mit dem Mac (Xcode)

Du brauchst einen Mac, ein USB-Kabel und eine Apple-ID. Eine kostenlose Apple-ID reicht.

1. **Xcode** aus dem Mac App Store installieren und einmal starten (zusätzliche Komponenten installieren lassen).
2. **XcodeGen** installieren. Es erzeugt das Xcode-Projekt aus `project.yml`. Mit [Homebrew](https://brew.sh):
   ```bash
   brew install xcodegen
   ```
3. **Apple-ID in Xcode anmelden:** Xcode → Settings → Accounts → „+“ → Apple ID.
4. **Eigene Einstellungen anlegen:** Im Ordner `ios` die Datei `Local.xcconfig.example` kopieren und
   `Local.xcconfig` nennen. Darin `DEVELOPMENT_TEAM` auf deine Team-ID setzen. Die Team-ID findest du in
   Xcode unter Settings → Accounts → deine Apple-ID → Team, oder in einem beliebigen Projekt unter
   *Signing & Capabilities*.
   Meldet Xcode später, dass die Bundle-ID schon vergeben ist, dort zusätzlich eine eigene setzen, z. B.
   `AZ_BUNDLE_ID = de.deinname.arbeitszeitrechner`.
5. **Projekt erzeugen und öffnen:**
   ```bash
   cd ios
   xcodegen
   open Arbeitszeit.xcodeproj
   ```
6. iPhone per Kabel anschließen und entsperren, oben in Xcode das iPhone als Ziel wählen und auf
   **Run** (▶) klicken.
7. **Entwicklermodus am iPhone aktivieren** (nur beim ersten Mal): Einstellungen → Datenschutz &
   Sicherheit → Entwicklermodus → einschalten, iPhone neu starten und bestätigen.
8. Beim ersten Start meldet das iPhone evtl. „Nicht vertrauenswürdiger Entwickler“: Einstellungen →
   Allgemein → VPN & Geräteverwaltung → deine Apple-ID → *Vertrauen*.

**Kostenlose Apple-ID:** Die App läuft dann 7 Tage. Danach startet sie nicht mehr, bis du sie wieder
über Xcode aufspielst (Schritt 6). Deine Einträge bleiben dabei erhalten, solange du die App nicht löschst.
Schalte trotzdem die [automatische Sicherung](#daten-und-backup) ein.

**Updates:** Neue Version holen (`git pull`), `xcodegen` ausführen und in Xcode wieder auf Run klicken.
Die Daten bleiben erhalten.

## Installation unter Windows mit Sideloadly

1. Auf GitHub unter **Releases** die neueste Datei `Arbeitszeitrechner-iOS-….ipa` herunterladen.
   Alternativ: **Actions** → letzter erfolgreicher Lauf → Artefakt `Arbeitszeitrechner-ipa` (ZIP mit der IPA).
2. [Sideloadly](https://sideloadly.io) und iTunes (Version von der Apple-Website, nicht aus dem
   Microsoft Store) installieren.
3. iPhone per Kabel anschließen, Sideloadly öffnen, die IPA hineinziehen, Apple-ID eingeben und **Start** klicken.
4. Am iPhone den Entwicklermodus einschalten und dem Entwickler vertrauen (siehe Schritte 7 und 8 oben).

Die IPA ist unsigniert, Sideloadly signiert sie mit deiner Apple-ID. Mit einer kostenlosen Apple-ID muss
die App alle 7 Tage neu aufgespielt werden; die Daten bleiben erhalten, wenn du sie dabei nicht löschst.
Schalte trotzdem die [automatische Sicherung](#daten-und-backup) ein.

**Hinweis:** Widgets und Kontrollzentrum brauchen eine *App Group*, über die App und Widgets ihre Daten
teilen. Sideloadly richtet sie nicht immer ein. Dann funktioniert die App ganz normal, die Widgets zeigen
aber „Keine Daten“, und in den Einstellungen erscheint ein Hinweis. Stempeln geht dann nur in der App
(und per Siri); der Knopf im Kontrollzentrum öffnet die App. Mit Xcode installiert funktionieren die Widgets.

## Widgets, Kontrollzentrum und Siri

- **Widget „Stempeln“ (klein):** Status von heute, z. B. „seit 08:00“ und „20 h voll um 18:15“, und ein
  Knopf **Kommen** bzw. **Gehen**.
- **Widget „Woche“ (mittel):** „KW 40 · Arbeitszeit“, Stunden der Woche mit Grenze, Fortschrittsbalken,
  Wochenstatus (rot bei Überschreitung), Status von heute und Kommen/Gehen-Knopf.

  Hinzufügen: lange auf den Homescreen drücken → *Bearbeiten* → *Widget hinzufügen* → *Arbeitszeit*.
  Die Widgets zeigen die Summe der abgeschlossenen Zeiten und aktualisieren sich bei jedem Stempeln,
  bei Änderungen in der App, zum Zeitpunkt „Woche voll“ und um Mitternacht.
- **Kontrollzentrum (ab iOS 18):** Kontrollzentrum öffnen → „+“ oben links → *Steuerelement hinzufügen* →
  *Arbeitszeit* → *Stempeln*. Der Knopf lässt sich auch auf den Sperrbildschirm oder die Aktionstaste legen.
  Ist heute nichts mehr zu stempeln (Feierabend, Urlaub …), öffnet er die App.
- **Siri und Kurzbefehle:** „Stempeln in Arbeitszeit“ oder „Arbeitszeit stempeln“. Die Aktion *Stempeln*
  steht auch in der Kurzbefehle-App, z. B. für eine Automation beim Erreichen des Arbeitsorts.

## Daten und Backup

Die Einträge liegen nur auf dem iPhone. Sie bleiben bei Updates erhalten, solange die App nicht gelöscht wird.

- **Einfachster Weg – automatische Sicherung:** Einstellungen → *Daten sichern* → *Automatische Sicherung*
  einschalten und einen Ort wählen, am besten iCloud Drive. Die Datei `Arbeitszeit-Backup.json` wird nach
  jeder Änderung in der App neu geschrieben. Änderungen über Widgets, Kontrollzentrum und Siri werden
  gesichert, sobald du die App das nächste Mal öffnest. Unter dem Schalter steht, wann zuletzt gesichert
  wurde. Ist die Datei nicht mehr erreichbar, erscheint ein Hinweis mit *Neue Sicherungsdatei wählen*.
- **Backup jetzt speichern:** Einstellungen → *Daten sichern* → *Backup jetzt speichern*, z. B. in „Dateien“
  oder iCloud Drive. Die Datei heißt `Arbeitszeit-Backup-JJJJ-MM-TT.json`.
- **Backup wiederherstellen:** Einstellungen → *Daten sichern* → *Backup wiederherstellen* und die Datei wählen.
  Einträge für dieselben Tage werden überschrieben, alle anderen bleiben erhalten. Die Einstellungen
  werden übernommen. Ist die automatische Sicherung noch aus, kann die gewählte Datei gleich dafür
  verwendet werden (*Diese Datei für die automatische Sicherung verwenden*).
- **Wechsel zwischen Android und iPhone:** Das Format ist dasselbe. Ein Backup aus der Android-App lässt
  sich auf dem iPhone wiederherstellen und umgekehrt.

Vor dem Löschen der App immer ein Backup speichern bzw. die automatische Sicherung einschalten.

**Wechsel der Installationsart (Xcode ↔ Sideloadly):** Mit und ohne App Group liegen die Daten an
verschiedenen Orten. Kommt die App Group dazu, übernimmt die App die bisherigen Daten beim ersten Start
selbst (bei gleichem Tag gilt der Eintrag aus der App Group). Fällt die App Group weg, zeigt die App
keine Einträge mehr an: Dann das Backup bzw. die Datei der automatischen Sicherung wiederherstellen.

## Selbst bauen und testen

Das Skript `ci/build.sh` wird auch von GitHub Actions benutzt (Mac mit Xcode 16):

```bash
bash ios/ci/build.sh kit-test      # Tests der Rechenlogik (gleiche Testfälle wie Android)
bash ios/ci/build.sh generate      # Xcode-Projekt erzeugen (installiert XcodeGen bei Bedarf)
bash ios/ci/build.sh build         # App für den Simulator bauen (erzeugt das Projekt bei Bedarf neu)
bash ios/ci/build.sh screenshots   # UI-Test im Simulator, Bildschirmfotos nach ios/build/screenshots
bash ios/ci/build.sh ipa           # unsignierte IPA nach ios/build/Arbeitszeitrechner-iOS.ipa
```

Für eigene Bildschirmfotos kann die App mit Startargumenten gestartet werden (Xcode → Scheme → Run →
Arguments). Im normalen Betrieb haben sie keine Wirkung. Mit `-AZDemoData` oder `-AZFixedNow` arbeitet
die App in einem eigenen Speicher, der bei jedem Start zurückgesetzt wird; deine echten Einträge bleiben
unberührt und erscheinen wieder, sobald die App ohne diese Argumente startet.

| Argument | Wirkung |
|----------|---------|
| `-AZDemoData YES` | zeigt Beispieldaten |
| `-AZFixedNow 2026-09-30T15:00` | feste Uhrzeit für „jetzt“ |
| `-AZWidgetPreview YES` | zeigt eine Seite mit den Widgets in Originalgröße |

## Aufbau

| Pfad | Inhalt |
|------|--------|
| `ArbeitszeitKit/` | Swift-Paket mit der Rechenlogik (Pausen, Wochen, Texte, CSV, Backup-Format), getestet mit denselben Testfällen wie Android (`shared/test-vectors.json`) |
| `App/` | Oberfläche mit SwiftUI: Wochenansicht, Tag bearbeiten, Einstellungen, Backup und automatische Sicherung, Monatsexport, Siri-Kurzbefehl |
| `Shared/` | Gemeinsam für App und Widgets: Speicherung (App Group), Stempeln (`ToggleClockIntent`), Widget-Ansichten, Farben |
| `Widgets/` | Widgets und Steuerelement für das Kontrollzentrum |
| `UITests/` | UI-Test, der Bildschirmfotos macht |
| `project.yml`, `Config.xcconfig` | Projektbeschreibung für XcodeGen, Bundle-ID, App Group und Version |
| `ci/build.sh` | Bauen, Testen, Bildschirmfotos und IPA |

## Hinweis

Die App ist ein privates Hilfsmittel zum Erfassen der eigenen Arbeitszeit und **keine Rechtsberatung**.
Die Pausenregeln (§ 4 ArbZG), die Tageshöchstgrenze von 10 Stunden (§ 3 ArbZG) und die
20-Stunden-Grenze für Werkstudenten sind vereinfacht umgesetzt. Verbindlich sind der Arbeitsvertrag,
die Angaben des Arbeitgebers und bei Fragen zur Sozialversicherung die Krankenkasse. Alle Angaben ohne Gewähr.
