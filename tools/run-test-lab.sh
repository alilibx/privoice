#!/usr/bin/env bash
set -euo pipefail
# Run Privoice across the Firebase Test Lab real-device matrix (low/mid/high).
#
# Uses a ROBO crawl on the app APK — it auto-explores the UI on each real device
# and reports crashes/ANRs/performance. No instrumentation APK needed, so it
# sidesteps the Flutter-plugin + native-assets androidTest build friction.
# (Scripted integration_test assertions run on a connected device via
#  `flutter test integration_test/...`; wiring them into Test Lab is a T3
#  follow-up once the assembleAndroidTest task graph is resolved.)
#
# Prereqs: gcloud authed; Test Lab API enabled + billing on the project.
# Usage:  FTL_PROJECT=your-project-id tools/run-test-lab.sh
# Devices: gcloud firebase test android models list

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/apps/mobile"
PROJECT="${FTL_PROJECT:-}"
[ -n "$PROJECT" ] || { echo "Set FTL_PROJECT to your Firebase project id"; exit 1; }

APK="$APP/build/app/outputs/apk/debug/app-debug.apk"
[ -f "$APK" ] || { echo "Build first: (cd $APP && flutter build apk --debug)"; exit 1; }

echo "== Robo crawl on Test Lab device matrix (project: $PROJECT) =="
gcloud firebase test android run \
  --project="$PROJECT" \
  --type robo \
  --app "$APK" \
  --timeout 4m \
  --device model=MediumPhone.arm,version=34,locale=en,orientation=portrait \
  --device model=oriole,version=33,locale=en,orientation=portrait \
  --device model=redfin,version=30,locale=en,orientation=portrait
