#!/usr/bin/env bash
set -euo pipefail

# -----------------------------
# CONFIG
# -----------------------------
APK_PATH="build/app/outputs/flutter-apk/app-debug.apk"
CONFIG_FILE="config.json"

# -----------------------------
# 1. Build the Flutter APK
# -----------------------------
echo "🔨 Building Flutter APK with config from $CONFIG_FILE..."
flutter build apk --debug --dart-define-from-file=$CONFIG_FILE

# -----------------------------
# 2. Extract package name from AndroidManifest
# -----------------------------
PKG=$(grep -oP 'package="\K[^"]+' android/app/src/main/AndroidManifest.xml)
echo "📦 Detected package name: $PKG"

# -----------------------------
# 3. Push the APK to /data/local/tmp
# -----------------------------
echo "📤 Pushing APK to device..."
adb push "$APK_PATH" /data/local/tmp/app-debug.apk

# -----------------------------
# 4. Install using root bypass
# -----------------------------
echo "📲 Installing APK as root..."
if adb shell su -c "pm install -r /data/local/tmp/app-debug.apk"; then
    echo "✅ Installation successful"
else
    echo "⚠️ Install failed, trying uninstall + reinstall..."
    adb shell su -c "pm uninstall $PKG" || true
    adb shell su -c "pm install -r /data/local/tmp/app-debug.apk"
fi

# -----------------------------
# 5. Launch the app
# -----------------------------
echo "🚀 Launching app..."
adb shell am start -n "$PKG/.MainActivity" || adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1

# -----------------------------
# 6. Attach Flutter for hot reload
# -----------------------------
echo "🔗 Attaching Flutter for hot reload..."
flutter attach
