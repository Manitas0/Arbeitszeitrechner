# Arbeitszeitrechner (Android)

Android-App zum Erfassen der täglichen Arbeitszeit und zur Berechnung der Wochenarbeitszeit.
Pausen werden automatisch nach dem Arbeitszeitgesetz abgezogen. Voreingestellt ist sie für
Werkstudenten mit 20 Stunden an 2 Tagen pro Woche, lässt sich aber für jede Stelle anpassen.

**Schnellstart:** [App installieren](#app-installieren) → [Erste Schritte](#erste-schritte)

## Funktionen

- **Wochenübersicht** (Mo–So) mit Kalenderwoche, Blättern zwischen den Wochen
- **Wochensumme** mit Fortschrittsbalken und der Summe der abgezogenen Pausen
- **Werkstudenten-Modus** (Standard: 20 h an 2 Tagen): Die Wochenstunden gelten als Obergrenze.
  Die App zeigt, wie viel bis zur Grenze fehlt, und warnt rot, wenn sie überschritten ist.
  Ausgeschaltet zeigt sie Sollzeit, offene Stunden und Überstunden wie bei einer normalen Stelle.
- **Tageshöchstgrenze:** Tage mit mehr als 10 h Arbeitszeit werden markiert (§ 3 ArbZG).
- **Pro Tag:** Beginn, Ende und optional die tatsächlich gemachte Pause
- **Automatischer Pausenabzug** nach § 4 ArbZG:
  - mehr als 6 Stunden Arbeit → 30 Minuten Pause
  - mehr als 9 Stunden Arbeit → 45 Minuten Pause
  - Ist eine längere Pause eingetragen, wird diese abgezogen.
- **Gestaffelter Abzug** (Standard): Es wird nur so viel Pause abgezogen, dass die Arbeitszeit nicht
  unter die Schwelle fällt. Beispiel: 6:15 h anwesend → 15 min Pause → 6:00 h Arbeitszeit.
  Abschaltbar, dann wird die volle Pause abgezogen, sobald die Schwelle überschritten ist.
- **Kommen / Gehen:** Mit einem Tipp für heute ein- und ausstempeln. Während der Arbeit zeigt die App
  die laufende Zeit und die Uhrzeit, zu der das Tagessoll erreicht ist.
- **Urlaub, Krank, Feiertag:** Diese Tage werden mit dem Tagessoll gutgeschrieben.
- **Nachtschichten:** Liegt das Ende vor dem Beginn, wird über Mitternacht gerechnet.
- **Einstellungen:** Wochenstunden (z. B. `20`, `38,5` oder `38:30`), Arbeitstage pro Woche,
  Obergrenze an/aus und eigene Pausenregeln
- **Woche teilen:** Die Übersicht lässt sich als Text per Mail, WhatsApp usw. verschicken.
- **Stundenzettel exportieren** (Kalender-Symbol oben): ein Monat als CSV-Datei für Excel, Numbers
  oder Google Tabellen. Enthalten sind Kalenderwoche, Datum, Beginn, Ende, Pause und Stunden
  (h:mm und dezimal) pro Tag sowie die Monatssumme. Die Datei lässt sich teilen oder speichern.
- **Backup:** automatische Sicherung in eine selbst gewählte Datei sowie Backup speichern und
  wiederherstellen (Einstellungen → *Daten sichern*).
- Alle Daten bleiben lokal auf dem Gerät.

## Widgets und Schnelleinstellung

- **Widget „Arbeitszeit – Woche“ (4×2):** Stunden dieser Woche mit Grenze, Fortschrittsbalken,
  Status von heute („Seit 08:00 · Tagessoll um 18:45“) und ein **Kommen/Gehen-Knopf**.
  Ein Tipp auf das Widget öffnet die App.
- **Widget „Arbeitszeit – Stempeln“ (2×1):** Ein Tipp stempelt ein bzw. aus.
- **Kachel „Stempeln“ in den Schnelleinstellungen:** Ein- und Ausstempeln direkt aus der
  Benachrichtigungsleiste, ohne die App zu öffnen.

Hinzufügen: lange auf den Homescreen tippen → *Widgets* → *Arbeitszeit*. Die Kachel: Schnelleinstellungen
ganz herunterziehen → Stift-Symbol → *Stempeln* in die aktiven Kacheln ziehen.

Die Widgets zeigen die Wochensumme der abgeschlossenen Zeiten und aktualisieren sich bei jedem
Stempeln, bei Änderungen in der App und automatisch alle 30 Minuten. Mit Android 12 oder neuer
übernehmen sie die Farben des Hintergrundbilds.

## App installieren

1. Auf GitHub unter **Releases** die neueste Datei `Arbeitszeitrechner-….apk` auf dem Handy
   herunterladen.
   Alternativ: **Actions** → letzter erfolgreicher Lauf → Artefakt `Arbeitszeitrechner-apk`.
   Das Artefakt ist eine ZIP-Datei mit der APK.
2. Die APK öffnen. Beim ersten Mal fragt Android, ob der Browser bzw. Dateimanager
   „Apps aus unbekannten Quellen installieren“ darf. Das einmal erlauben.
3. Installieren. Die App heißt auf dem Homescreen **Arbeitszeit**.

Voraussetzung ist Android 8.0 oder neuer.

### Updates ohne Datenverlust

**Einfachster Weg – automatische Sicherung:** In den Einstellungen unter *Daten sichern* die
*Automatische Sicherung* einschalten und eine Datei wählen, z. B. in „Downloads“ oder Google Drive.
Die App aktualisiert die Datei nach jeder Änderung. Nach einer Neuinstallation zeigt die App einen
Hinweis, dann *Backup wiederherstellen* wählen und dieselbe Datei öffnen. Den Haken *Diese Datei für
die automatische Sicherung verwenden* setzen, dann läuft die Sicherung direkt weiter.

**Ohne Neuinstallation – eigener Signaturschlüssel:**

Android installiert ein Update nur, wenn es mit demselben Schlüssel signiert ist wie die installierte
App. Ohne eigenen Schlüssel signiert GitHub jede APK mit einem neuen Debug-Schlüssel. Die App muss
dann für ein Update deinstalliert werden, und die gespeicherten Zeiten gehen verloren.

Einmalig einen eigenen Schlüssel anlegen (auf einem Rechner mit Java):

```bash
keytool -genkeypair -v -keystore release.keystore -storetype PKCS12 \
  -alias arbeitszeitrechner -keyalg RSA -keysize 2048 -validity 10000
base64 -w0 release.keystore > release.keystore.base64
```

Dann im GitHub-Repository unter **Settings → Secrets and variables → Actions** diese Secrets anlegen:

| Secret                    | Inhalt                                   |
|---------------------------|------------------------------------------|
| `SIGNING_KEYSTORE_BASE64` | Inhalt von `release.keystore.base64`     |
| `SIGNING_STORE_PASSWORD`  | das bei `keytool` gewählte Passwort      |
| `SIGNING_KEY_ALIAS`       | `arbeitszeitrechner`                     |
| `SIGNING_KEY_PASSWORD`    | dasselbe Passwort wie oben (bei PKCS12)  |

Die Keystore-Datei gut aufbewahren und **nicht** ins Repository einchecken.

## Erste Schritte

### 1. Einmal einrichten

1. **Einstellungen prüfen:** oben rechts auf das Zahnrad tippen.
   - *Wochenarbeitszeit* und *Arbeitstage pro Woche* eintragen, voreingestellt sind 20 Stunden an 2 Tagen.
     Daraus ergibt sich das Tagessoll, hier 10 Stunden.
   - *Wochenstunden sind Obergrenze* eingeschaltet lassen, wenn du als Werkstudent unter 20 Stunden
     bleiben musst. Bei einer normalen Stelle ausschalten, dann zeigt die App Überstunden an.
   - Auf **Speichern** tippen. Der Knopf steht unter den Pausenregeln.
2. **Automatische Sicherung einschalten:** in den Einstellungen unter *Daten sichern* den Schalter
   *Automatische Sicherung* antippen und einen Speicherort wählen, z. B. „Downloads“ oder Google Drive.
   Ab jetzt ist jede Änderung gesichert.
3. **Optional Widget und Kachel hinzufügen,** siehe [Widgets und Schnelleinstellung](#widgets-und-schnelleinstellung).

### 2. Arbeitszeit erfassen

Es gibt zwei Wege, die du beliebig mischen kannst:

- **Stempeln:** Zu Arbeitsbeginn auf **Kommen** tippen, am Ende auf **Gehen**. Das geht auf der Karte
  von heute in der App, im Widget oder über die Kachel in den Schnelleinstellungen. Solange du
  eingestempelt bist, zeigt die App, wann dein Tagessoll erreicht ist,
  z. B. „Tagessoll erreicht um 18:45“.
- **Nachtragen:** auf einen Tag in der Wochenübersicht tippen. Dann *Beginn* und *Ende* wählen und
  **Speichern** tippen. Die App zeigt direkt die Rechnung: Anwesenheit − Pause = Arbeitszeit.

Die Pause musst du nicht eintragen, die gesetzliche Mindestpause zieht die App automatisch ab. Das
Feld *Tatsächliche Pause* brauchst du nur, wenn du länger Pause gemacht hast.

Bei **Urlaub, Krankheit oder Feiertag** den Tag antippen und oben die passende Art wählen. Der Tag
zählt dann mit dem Tagessoll.

Zum Korrigieren den Tag antippen und ändern. Mit **Löschen** entfernst du den Eintrag.

### 3. Überblick behalten

- Die Karte oben zeigt die Stunden der Woche und wie viel bis zur Grenze fehlt. Ist die Grenze
  überschritten, wird sie rot.
- Mit den Pfeilen neben „KW …“ blätterst du durch die Wochen, *Zur aktuellen Woche* springt zurück.
- Das Teilen-Symbol oben verschickt die Woche als Text.

### 4. Stundenzettel am Monatsende

Oben auf das **Kalender-Symbol** tippen und mit den Pfeilen den Monat wählen. Dann:

- **Teilen:** die CSV-Datei direkt per Mail oder Messenger verschicken, z. B. an den Arbeitgeber.
- **Speichern:** die Datei ablegen, z. B. in „Downloads“ oder Google Drive.

Die Datei öffnet sich in Excel, Numbers oder Google Tabellen. Die Spalte *Stunden (dezimal)* ist
praktisch für die Lohnabrechnung: Stunden × Stundenlohn.

### 5. Semesterferien

In den Semesterferien dürfen Werkstudenten in der Regel mehr als 20 Stunden arbeiten. Dafür in den
Einstellungen *Wochenstunden sind Obergrenze* ausschalten und nach den Ferien wieder einschalten.

### 6. Neue Version installieren

1. Neue APK unter **Releases** herunterladen.
2. Alte App deinstallieren und die neue installieren. Der Zwischenschritt entfällt mit eigenem
   Signaturschlüssel, siehe [Updates ohne Datenverlust](#updates-ohne-datenverlust).
3. Die App zeigt „Noch keine Einträge“. Dort auf **Backup wiederherstellen** tippen. Das öffnet die
   Einstellungen, dort unter *Daten sichern* noch einmal **Backup wiederherstellen** wählen.
4. Deine Sicherungsdatei öffnen. Den Haken *Diese Datei für die automatische Sicherung verwenden*
   gesetzt lassen und **Wiederherstellen** tippen.

Danach sind alle Einträge und Einstellungen wieder da, und die automatische Sicherung läuft weiter.

## Selbst bauen

Mit Android Studio das Projekt öffnen und starten, oder auf der Kommandozeile:

```bash
./gradlew testDebugUnitTest   # Tests der Berechnungslogik
./gradlew assembleDebug       # APK unter app/build/outputs/apk/debug/
```

## Aufbau

| Pfad | Inhalt |
|------|--------|
| `app/src/main/java/de/arbeitszeitrechner/calc/` | Berechnung: Pausenabzug, Tages- und Wochensummen, Stempel-Logik, Statustexte, Stundenzettel-Export (CSV); ohne Android-Abhängigkeiten, mit Unit-Tests |
| `app/src/main/java/de/arbeitszeitrechner/model/` | Datenmodell: Tageseintrag, Einstellungen, Pausenregeln |
| `app/src/main/java/de/arbeitszeitrechner/backup/` | JSON-Format für gespeicherte Einträge und Sicherungsdateien, mit Unit-Tests |
| `app/src/main/java/de/arbeitszeitrechner/data/` | Lokale Speicherung (SharedPreferences), automatische Sicherung, Stempeln (`TimeClock`), Dateien lesen, schreiben und teilen |
| `app/src/main/java/de/arbeitszeitrechner/ui/` | Oberfläche mit Jetpack Compose und Material 3: Wochenansicht, Tag bearbeiten, Einstellungen, Backup, Monatsexport |
| `app/src/main/java/de/arbeitszeitrechner/widget/` | Homescreen-Widgets und Schnelleinstellungs-Kachel |
| `app/src/test/` | Unit-Tests für Berechnung, Stempeln, Export und Sicherungsformat |
| `.github/workflows/android.yml` | Baut bei jedem Push Tests und APK und erstellt auf dem Standard-Branch ein Release |

## Hinweis

Die App ist ein privates Hilfsmittel zum Erfassen der eigenen Arbeitszeit und **keine Rechtsberatung**.
Die Pausenregeln (§ 4 ArbZG), die Tageshöchstgrenze von 10 Stunden (§ 3 ArbZG) und die
20-Stunden-Grenze für Werkstudenten sind vereinfacht umgesetzt. Ausnahmen, etwa durch Tarifverträge,
Betriebsvereinbarungen, Semesterferien oder Arbeit am Abend und Wochenende, berücksichtigt die App nicht.
Verbindlich sind der Arbeitsvertrag, die Angaben des Arbeitgebers und bei Fragen zur
Sozialversicherung die Krankenkasse. Alle Angaben ohne Gewähr.

## Lizenz

[MIT](LICENSE) – der Code darf frei verwendet, verändert und weitergegeben werden, solange der
Lizenzhinweis erhalten bleibt.
