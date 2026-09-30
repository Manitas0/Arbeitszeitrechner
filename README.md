# Arbeitszeitrechner (Android)

Android-App zum Erfassen der täglichen Arbeitszeit und zur Berechnung der Wochenarbeitszeit.
Pausen werden automatisch nach dem Arbeitszeitgesetz abgezogen.

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
- Alle Daten bleiben lokal auf dem Gerät.

## App installieren

1. Auf GitHub unter **Releases** die neueste Datei `Arbeitszeitrechner-….apk` auf dem Handy
   herunterladen.
   Alternativ: **Actions** → letzter erfolgreicher Lauf → Artefakt `Arbeitszeitrechner-apk`.
   Das Artefakt ist eine ZIP-Datei mit der APK.
2. Die APK öffnen. Beim ersten Mal fragt Android, ob der Browser bzw. Dateimanager
   „Apps aus unbekannten Quellen installieren“ darf. Das einmal erlauben.
3. Installieren. Die App heißt auf dem Homescreen **Arbeitszeit**.

Voraussetzung ist Android 8.0 oder neuer.

### Updates ohne Datenverlust (empfohlen)

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

## Selbst bauen

Mit Android Studio das Projekt öffnen und starten, oder auf der Kommandozeile:

```bash
./gradlew testDebugUnitTest   # Tests der Berechnungslogik
./gradlew assembleDebug       # APK unter app/build/outputs/apk/debug/
```

## Aufbau

| Pfad | Inhalt |
|------|--------|
| `app/src/main/java/de/arbeitszeitrechner/calc/` | Berechnung: Pausenabzug, Tages- und Wochensummen (ohne Android-Abhängigkeiten, mit Unit-Tests) |
| `app/src/main/java/de/arbeitszeitrechner/model/` | Datenmodell: Tageseintrag, Einstellungen, Pausenregeln |
| `app/src/main/java/de/arbeitszeitrechner/data/` | Lokale Speicherung (SharedPreferences) |
| `app/src/main/java/de/arbeitszeitrechner/ui/` | Oberfläche mit Jetpack Compose und Material 3 |
| `.github/workflows/android.yml` | Baut bei jedem Push Tests und APK und erstellt auf dem Standard-Branch ein Release |
