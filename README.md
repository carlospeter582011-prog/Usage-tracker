# Data Usage Tracker

An Android 6+ app built with Flutter and Dart. A Kotlin bridge reads Android's NetworkStatsManager and resolves installed app names, packages and icons.

## Daily and weekly usage

- **Daily** shows device-wide mobile and Wi-Fi totals. Tap either card to switch the ranked app list. Use Today, Yesterday or the date picker to open a day.
- **Weekly** compares Monday through Sunday using mobile and Wi-Fi totals, with proportional bars and links to the daily breakdown. Navigate to earlier weeks and set an optional recurring mobile data limit.
- On Android 6–9, tap **Allow mobile data access** to grant the Phone permission used to look up active SIMs. Wi-Fi usage is available without this permission. On Android 6, cellular history is limited to the default subscription.
- On first launch, open Android's **Usage access** screen, allow access for **Data Usage Tracker**, then return to the app.

Usage includes download and upload. Android controls how often data refreshes and how much history is available, including usage recorded before installation. The device total may differ from the app list because Android provides device-wide totals and user-scoped app breakdowns separately. Shared UIDs are displayed as a single entry to avoid counting the same traffic more than once. Usage stays on the device.

## Build and publish with GitHub Actions

Each push to the default branch starts **Build and Release Android**. After the tests and Android 6 launch check pass, the workflow publishes `Data-Usage-Tracker.apk` and `Data-Usage-Tracker.aab` together in [GitHub Releases](../../releases). Pull requests build and test both files and leave them in Actions artifacts. You can also run the workflow manually from the default branch. The release tag identifies its commit, so a rerun uses the same release.

Install the APK directly on Android. The workflow uses development signing. A persistent signing key is needed for reliable in-place updates and Play Store submission.

For a local Android build with Flutter 3.32.8 and JDK 17:

```sh
bash scripts/prepare-android.sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release
flutter build appbundle --release
```

The preparation script regenerates the Android project from the pinned Flutter template and applies the Android manifest, launcher icon, and Kotlin bridge from `android_overlay`. The application ID is `com.carlos.data_usage_tracker`.
