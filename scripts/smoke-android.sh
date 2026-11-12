#!/usr/bin/env bash
set -euo pipefail
app=com.carlos.data_usage_tracker
adb install "$1"
adb shell am start -W -n "$app/.MainActivity"
for attempt in {1..12}; do
  adb shell uiautomator dump /sdcard/window.xml >/dev/null 2>&1 || true
  layout="$(adb shell cat /sdcard/window.xml 2>/dev/null || true)"
  if [[ "$layout" == *"Open Usage access settings"* ]]; then
    echo 'Data Usage Tracker displayed its permission screen on Android 7.'
    exit 0
  fi
  sleep 2
done
adb logcat -d -s AndroidRuntime:E flutter:E
exit 1
