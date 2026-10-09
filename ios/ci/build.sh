#!/usr/bin/env bash
# Baut und testet die iPhone-App (auf dem Mac und in GitHub Actions).
#
#   bash ios/ci/build.sh kit-test      Tests der Rechenlogik (Swift-Paket ArbeitszeitKit)
#   bash ios/ci/build.sh generate      Xcode-Projekt mit XcodeGen erzeugen
#   bash ios/ci/build.sh build         App für den Simulator bauen (ohne Signatur)
#   bash ios/ci/build.sh screenshots   UI-Test im Simulator, Bildschirmfotos nach ios/build/screenshots
#   bash ios/ci/build.sh ipa           Unsignierte IPA für Sideloadly nach ios/build/Arbeitszeitrechner-iOS.ipa
#
# Versionsnummer der IPA optional über AZ_VERSION (z. B. 1.0.42) und AZ_BUILD (z. B. 42).
set -euo pipefail

IOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$IOS_DIR/build"
PROJECT="$IOS_DIR/Arbeitszeit.xcodeproj"
SCHEME="Arbeitszeit"
DERIVED_DATA="$BUILD_DIR/DerivedData"

log() {
  echo "==> $*"
}

kit_test() {
  log "Swift-Paket testen"
  swift test --package-path "$IOS_DIR/ArbeitszeitKit"
}

# $1 (optional): "--use-cache" – nur neu erzeugen, wenn sich project.yml oder die Dateiliste geändert hat.
generate() {
  if ! command -v xcodegen >/dev/null 2>&1; then
    log "XcodeGen installieren"
    HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install xcodegen
  fi
  log "Xcode-Projekt erzeugen"
  mkdir -p "$IOS_DIR/Supporting"
  (cd "$IOS_DIR" && xcodegen generate ${1:+"$1"})
}

# Vor jedem Bauen: XcodeGen trägt jede Quelldatei einzeln ins Projekt ein. Ein vorhandenes Projekt
# wäre nach einem "git pull" mit neuen, umbenannten oder gelöschten Dateien sonst veraltet.
ensure_project() {
  if [ -d "$PROJECT" ]; then
    generate --use-cache
  else
    generate
  fi
}

build() {
  ensure_project
  log "App für den Simulator bauen"
  xcodebuild build \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO
}

# Gibt die UDID eines verfügbaren iPhone-Simulators aus (neueste iOS-Version, bevorzugt ein "Pro").
pick_simulator() {
  xcrun simctl list devices available -j | python3 -c '
import json
import re
import sys

data = json.load(sys.stdin)
best = None
for runtime, devices in data.get("devices", {}).items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not match:
        continue
    version = (int(match.group(1)), int(match.group(2)))
    for device in devices:
        name = device.get("name", "")
        if not name.startswith("iPhone") or not device.get("isAvailable", True):
            continue
        score = (version, "Pro" in name and "Max" not in name, name)
        if best is None or score > best[0]:
            best = (score, device["udid"], name, runtime)
if best is None:
    sys.exit("Kein iPhone-Simulator gefunden")
print(best[1])
print("Simulator: %s (%s)" % (best[2], best[3]), file=sys.stderr)
'
}

screenshots() {
  ensure_project
  local device_id
  device_id="$(pick_simulator)"

  local host_shots="$HOME/az-screenshots"
  local out="$BUILD_DIR/screenshots"
  local result="$BUILD_DIR/UITests.xcresult"
  rm -rf "$host_shots" "$out" "$result"
  mkdir -p "$out"

  log "Simulator starten"
  xcrun simctl boot "$device_id" 2>/dev/null || true
  xcrun simctl bootstatus "$device_id" -b >/dev/null 2>&1 || true
  # Gleiche Uhrzeit in der Statusleiste wie die feste Zeit der Beispieldaten.
  xcrun simctl status_bar "$device_id" override --time "15:00" \
    --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 2>/dev/null || true

  log "UI-Test mit Bildschirmfotos"
  local status=0
  xcodebuild test \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination "id=$device_id" \
    -derivedDataPath "$DERIVED_DATA" \
    -resultBundlePath "$result" \
    -only-testing:ArbeitszeitUITests \
    CODE_SIGNING_ALLOWED=NO || status=$?

  if ls "$host_shots"/*.png >/dev/null 2>&1; then
    cp "$host_shots"/*.png "$out"/
  elif [ -d "$result" ]; then
    # Notlösung: Anhänge aus dem Testergebnis holen (Xcode 16 und neuer).
    xcrun xcresulttool export attachments --path "$result" --output-path "$out" >/dev/null 2>&1 || true
  fi
  log "Bildschirmfotos:"
  ls -1 "$out" || true
  return "$status"
}

ipa() {
  ensure_project
  local archive="$BUILD_DIR/Arbeitszeit.xcarchive"
  local payload="$BUILD_DIR/Payload"
  local output="$BUILD_DIR/Arbeitszeitrechner-iOS.ipa"
  local versions=()
  if [ -n "${AZ_VERSION:-}" ]; then
    versions+=("MARKETING_VERSION=$AZ_VERSION")
  fi
  if [ -n "${AZ_BUILD:-}" ]; then
    versions+=("CURRENT_PROJECT_VERSION=$AZ_BUILD")
  fi
  rm -rf "$archive" "$payload" "$output"

  log "Archiv bauen (Release, ohne Signatur)"
  # ${versions[@]+...}: leeres Array auch mit "set -u" unter Bash 3.2 (macOS) erlaubt.
  xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$archive" \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    ${versions[@]+"${versions[@]}"}

  local app="$archive/Products/Applications/Arbeitszeit.app"
  if [ ! -d "$app" ]; then
    echo "App nicht im Archiv gefunden: $app" >&2
    exit 1
  fi

  log "IPA packen"
  mkdir -p "$payload"
  cp -R "$app" "$payload/"
  (cd "$BUILD_DIR" && zip -qry "$(basename "$output")" Payload)
  rm -rf "$payload"
  log "Fertig: $output"
}

usage() {
  sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

case "${1:-}" in
  kit-test) kit_test ;;
  generate) generate ;;
  build) build ;;
  screenshots) screenshots ;;
  ipa) ipa ;;
  -h|--help|help|"") usage ;;
  *)
    echo "Unbekannter Befehl: $1" >&2
    usage >&2
    exit 2
    ;;
esac
