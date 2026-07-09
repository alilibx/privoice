#!/usr/bin/env bash
set -euo pipefail
# Downloads the Parakeet-TDT v3 INT8 model bundle from the sherpa-onnx model
# releases and pushes it into the app's files dir on a connected Android device.
#
# IMPORTANT: confirm the exact asset name/URL on the releases page before running:
#   https://github.com/k2-fsa/sherpa-onnx/releases  (tag: asr-models)
# The four files we need (transducer layout): encoder / decoder / joiner / tokens.
#
# The app reads from getExternalStorageDirectory() -> /sdcard/Android/data/<app>/files
# Keep DEST below in sync with spike_screen.dart _modelDir().

MODEL="sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8"
URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/${MODEL}.tar.bz2"
APP_ID="com.privoice.mobile"
DEST="/sdcard/Android/data/${APP_ID}/files/models/parakeet-tdt-v3-int8"

if ! command -v adb >/dev/null 2>&1; then
  echo "ERROR: adb not found on PATH. Finish Task 0 (Android SDK install) first." >&2
  exit 1
fi

if [ "$(adb devices | grep -c 'device$')" -eq 0 ]; then
  echo "ERROR: no Android device detected by adb. Plug in a phone (USB debugging on)." >&2
  exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "Downloading $MODEL ..."
curl -L "$URL" -o "$work/model.tar.bz2"
echo "Extracting ..."
tar xjf "$work/model.tar.bz2" -C "$work"

echo "Pushing to device: $DEST"
adb shell mkdir -p "$DEST"
for f in encoder.int8.onnx decoder.int8.onnx joiner.int8.onnx tokens.txt; do
  src="$work/$MODEL/$f"
  if [ ! -f "$src" ]; then
    echo "WARN: expected file missing: $f — check the tarball's actual filenames." >&2
    echo "      Contents:"; ls -1 "$work/$MODEL" >&2
    exit 1
  fi
  adb push "$src" "$DEST/$f"
done
echo "Done. Model at $DEST"
