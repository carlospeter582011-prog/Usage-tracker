# Data Usage Tracker

An Android 10+ app built with Flutter and Dart. A Kotlin bridge reads Android's NetworkStatsManager and resolves installed app names, packages and icons.

## Daily and weekly usage

- **Daily** shows device-wide mobile and Wi-Fi totals. Tap either card to switch the ranked app list. Use Today, Yesterday or the date picker to open a day.
- **Weekly** compares Monday through Sunday using mobile and Wi-Fi totals, with proportional bars and links to the daily breakdown. Navigate to earlier weeks and set an optional recurring mobile data limit.
- On first launch, open Android's **Usage access** screen, allow access for **Data Usage Tracker**, then return to the app.

Usage includes download and upload. Android controls how often data refreshes and how much history is available, including usage recorded before installation. The device total may differ from the app list because Android provides device-wide totals and user-scoped app breakdowns separately. Shared UIDs are displayed as a single entry to avoid counting the same traffic more than once. Usage stays on the device.

## Build the APK with GitHub Actions

Commit the project to the repository root, including the hidden `.github` folder. A push to `main` or `master` starts **Build Android APK**, or run it manually from **Actions**. After a successful run, download **Data-Usage-Tracker** from **Artifacts**, extract the ZIP, and install `Data-Usage-Tracker.apk`. The workflow uses the Flutter template's development signing configuration for sideloading. A stable signing key is needed for reliably installing subsequent builds over an existing copy.

For a local Android build with Flutter 3.41.9 and JDK 17:

```sh
bash scripts/prepare-android.sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

The preparation script regenerates the Android project from the pinned Flutter template and applies the Android manifest, launcher icon, and Kotlin bridge from `android_overlay`. The application ID is `com.carlos.data_usage_tracker`.
