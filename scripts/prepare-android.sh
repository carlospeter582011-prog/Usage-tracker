#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
scaffold="$(mktemp -d)"
trap 'rm -rf "$scaffold"' EXIT
flutter create --platforms=android --org com.carlos --project-name data_usage_tracker --no-pub "$scaffold/data_usage_tracker"
gradle_file="$scaffold/data_usage_tracker/android/app/build.gradle.kts"
grep -q 'compileSdk = flutter.compileSdkVersion' "$gradle_file"
grep -q 'targetSdk = flutter.targetSdkVersion' "$gradle_file"
sed -i -e 's/compileSdk = flutter.compileSdkVersion/compileSdk = 37/' \
  -e 's/targetSdk = flutter.targetSdkVersion/targetSdk = 37/' "$gradle_file"
cat >> "$gradle_file" <<'GRADLE'

dependencies {
    implementation("com.google.android.libraries.ads.mobile.sdk:ads-mobile-sdk:1.6.0")
}
GRADLE
mkdir -p android
cp -R "$scaffold/data_usage_tracker/android/." android/
cp android_overlay/AndroidManifest.xml android/app/src/main/
cp android_overlay/kotlin/MainActivity.kt android/app/src/main/kotlin/com/carlos/data_usage_tracker/
mkdir -p android/app/src/main/res/drawable
cp android_overlay/res/drawable/tracker_icon.xml android/app/src/main/res/drawable/
