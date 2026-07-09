# macOS toolchain bootstrap (Privoice)

Recorded from the actual S0 run on 2026-07-09 (Apple Silicon, macOS 26.5.1).

## What got installed

```bash
# Flutter + Dart (Homebrew cask — no sudo)
brew install --cask flutter          # -> Flutter 3.44.5 / Dart 3.12.2

# JDK 17 via FORMULA, not the temurin cask.
# The temurin@17 cask uses a .pkg installer that needs sudo (fails headless).
brew install openjdk@17              # keg-only, no sudo

# Android command-line tools + SDK packages (no sudo)
brew install --cask android-commandlinetools
export JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
export ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"
yes | sdkmanager --sdk_root="$ANDROID_HOME" "platform-tools" "platforms;android-36" "build-tools;36.0.0"
yes | sdkmanager --sdk_root="$ANDROID_HOME" --licenses
```

> Note: Flutter 3.44.5 requires **Android API 36** (not 35). `compileSdk`/`targetSdk` are set to 36 in the app.

## Point Flutter at the JDK + SDK

```bash
flutter config --jdk-dir="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
flutter config --android-sdk "/opt/homebrew/share/android-commandlinetools"
flutter doctor
```

Result: `[✓] Flutter`, `[✓] Android toolchain (SDK 36.0.0, licenses accepted)`, `[✓] Xcode 26.5`.

## Shell PATH for adb (needed for the model-push script later)

Add to `~/.zshrc` (or export per-shell):

```bash
export PATH="/opt/homebrew/bin:/opt/homebrew/share/android-commandlinetools/platform-tools:$PATH"
export JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
export ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"
```

## Devices

`flutter devices` at bootstrap time showed a wireless iPhone (out of scope for the Android-first spike), macOS, and Chrome. **An Android device or emulator is still required** for the Task 5 measurement (deferred: "build now, device later").
