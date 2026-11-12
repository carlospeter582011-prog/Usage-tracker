# Data Usage Tracker

An Android 7+ app built with Flutter and Dart. A Kotlin bridge reads Android's NetworkStatsManager and resolves installed app names, packages and icons.

## Daily and weekly usage

- **Overview** shows this week's usage alongside a network gauge and today's total in its own card. Switch between Wi-Fi and mobile data without leaving the screen.
- **Details** compares days with a tappable chart for the selected week or month. Use Today, Yesterday, the chart, or the date picker to open a day. The app list shows names, package names, icons, and usage for that date and network.
- **Settings** includes the recurring weekly mobile data limit, Android Usage access settings, and a saved Automatic, Light, or Dark appearance. Automatic follows the system and is the default.
- On Android 7–9, tap **Allow mobile data access** to grant the Phone permission used to look up active SIMs. Wi-Fi usage is available without this permission.
- On first launch, open Android's **Usage access** screen, allow access for **Data Usage Tracker**, then return to the app.

Usage includes download and upload. Android controls how often data refreshes and how much history is available, including usage recorded before installation. The device total may differ from the app list because Android provides device-wide totals and user-scoped app breakdowns separately. Shared UIDs are displayed once with one representative package. The usage shown is the total for the shared UID. Usage stays on the device.

## Test advertisements

The app uses Google's sample IDs with the Google Mobile Ads Flutter plugin and GMA Next-Gen Android SDK. A banner can appear above the dashboard after Usage access is granted. The app-open test ad is eligible on returning cold launches. It is skipped if the dashboard becomes ready, the ad fails, or the two-second loading window closes. First launch and foreground resumes do not show an app-open ad.

## Build and publish with GitHub Actions

Each push to the default branch starts **Build and Release Android**. After the tests and Android 7 launch check pass, the workflow publishes `Data-Usage-Tracker.apk` and `Data-Usage-Tracker.aab` together in [GitHub Releases](../../releases). Pull requests build and test both files and leave them in Actions artifacts. You can also run the workflow manually from the default branch. The release tag identifies its commit, so a rerun uses the same release.

Install the APK directly on Android. The workflow uses development signing. A persistent signing key is needed for reliable in-place updates and Play Store submission.

For a local Android build with Flutter 3.50.0, JDK 21, and Android SDK 37:

```sh
bash scripts/prepare-android.sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release --dart-define=USE_NEXT_GEN_SDK=true
flutter build appbundle --release --dart-define=USE_NEXT_GEN_SDK=true
```

The preparation script regenerates the Android project from the pinned Flutter template and applies the Android manifest, launcher icon, and Kotlin bridge from `android_overlay`. The application ID is `com.carlos.data_usage_tracker`.
