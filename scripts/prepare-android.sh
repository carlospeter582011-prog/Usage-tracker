#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
scaffold="$(mktemp -d)"
trap 'rm -rf "$scaffold"' EXIT
flutter create --platforms=android --org com.carlos --project-name data_usage_tracker --no-pub "$scaffold/data_usage_tracker"
gradle_file="$scaffold/data_usage_tracker/android/app/build.gradle.kts"
grep -q 'minSdk = flutter.minSdkVersion' "$gradle_file"
sed -i 's/minSdk = flutter.minSdkVersion/minSdk = 29/' "$gradle_file"
mkdir -p android
cp -R "$scaffold/data_usage_tracker/android/." android/
cp android_overlay/AndroidManifest.xml android/app/src/main/
cp android_overlay/kotlin/MainActivity.kt android/app/src/main/kotlin/com/carlos/data_usage_tracker/
mkdir -p android/app/src/main/res/drawable
cp android_overlay/res/drawable/tracker_icon.xml android/app/src/main/res/drawable/
