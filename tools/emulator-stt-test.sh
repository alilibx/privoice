#!/usr/bin/env bash
set -euo pipefail
# Headless on-device STT proof for the S1 spike.
#
# Drives the app's built-in self-test (see SpikeScreen._maybeSelfTest): with a
# `.selftest` sentinel present, the app auto-transcribes test_wavs/en.wav on
# launch and logs the result. We control the install lifecycle here (plain adb),
# so the app's external-storage model dir is NOT wiped — unlike `flutter test`,
# which clean-installs and clears the sandbox.
#
# Prereq: an Android device/emulator connected (adb), the model downloaded &
# extracted under .cache/models/ (see below), and a debug APK built:
#   flutter build apk --debug   (from apps/mobile)
#
# NOTE: on an emulator the timing is functional only — NOT a real-phone verdict.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_ID="com.privoice.mobile"
MODEL_NAME="sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8"
SRC="$ROOT/.cache/models/$MODEL_NAME"
APK="$ROOT/apps/mobile/build/app/outputs/flutter-apk/app-debug.apk"
DEST="/sdcard/Android/data/$APP_ID/files/models/parakeet-tdt-v3-int8"
EXT="/sdcard/Android/data/$APP_ID/files"

command -v adb >/dev/null || { echo "adb not on PATH"; exit 1; }
[ -f "$APK" ] || { echo "APK missing — run: (cd apps/mobile && flutter build apk --debug)"; exit 1; }

if [ ! -f "$SRC/encoder.int8.onnx" ]; then
  echo "Model not found under $SRC"
  echo "Download it with:"
  echo "  mkdir -p $ROOT/.cache/models && curl -L \\"
  echo "    https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/$MODEL_NAME.tar.bz2 \\"
  echo "    | tar xj -C $ROOT/.cache/models"
  exit 1
fi

echo "== install app (persistent; we own the lifecycle) =="
adb install -r "$APK"

echo "== push model + sample wav + sentinel =="
adb shell mkdir -p "$DEST/test_wavs"
adb push "$SRC/encoder.int8.onnx" "$SRC/decoder.int8.onnx" "$SRC/joiner.int8.onnx" "$SRC/tokens.txt" "$DEST/" >/dev/null
adb push "$SRC/test_wavs/en.wav" "$DEST/test_wavs/" >/dev/null
adb shell 'touch '"$EXT"'/.selftest'

echo "== launch app; capture self-test log =="
adb logcat -c
adb shell am start -n "$APP_ID/.MainActivity" >/dev/null
echo "waiting for ITEST_STT (up to 60s)…"
for i in $(seq 1 60); do
  line="$(adb logcat -d 2>/dev/null | grep -E 'ITEST_STT|SPIKE_BENCH' | tail -3 || true)"
  if [ -n "$line" ]; then echo "$line"; break; fi
  sleep 1
done
echo "== done =="
