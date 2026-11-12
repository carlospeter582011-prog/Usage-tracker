import 'dart:async';

import 'package:data_usage_tracker/main.dart';
import 'package:data_usage_tracker/test_ads.dart';
import 'package:flutter/material.dart' show Key, Text, Widget;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';

class FakeAds implements TrackerAds {
  final result = Completer<LaunchAd?>();
  int loads = 0;

  @override
  Future<LaunchAd?> loadLaunchAd() {
    loads++;
    return result.future;
  }

  @override
  Widget banner() => const Text('Fake top banner');
}

class FakeLaunchAd implements LaunchAd {
  final dismissed = Completer<void>();
  bool shown = false;
  bool disposed = false;

  @override
  Future<void> show() {
    shown = true;
    return dismissed.future;
  }

  @override
  void dispose() => disposed = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('data_usage_tracker/usage');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final loading = find.byKey(const Key('launch-loading'));

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  void mockStartup({required bool returning, required Future<bool> hasAccess}) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'returningLaunch':
          return returning;
        case 'hasAccess':
          return hasAccess;
        case 'daily':
          return {
            'mobile': null,
            'wifi': {'total': 0, 'apps': []},
          };
        case 'weekly':
          return List.generate(7, (_) => {'mobile': null, 'wifi': 0});
        default:
          return null;
      }
    });
  }

  testWidgets('first launch skips app-open ads and places the banner above usage', (tester) async {
    final ads = FakeAds();
    final access = Completer<bool>();
    mockStartup(returning: false, hasAccess: access.future);

    await tester.pumpWidget(TrackerApp(ads: ads));
    await tester.pump();
    expect(loading, findsNothing);
    expect(ads.loads, 0);
    access.complete(true);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Fake top banner')).dy,
      lessThan(tester.getTopLeft(find.text('Used this week')).dy));
  });

  testWidgets('discards an ad that arrives after the dashboard is ready', (tester) async {
    final ads = FakeAds();
    final access = Completer<bool>();
    mockStartup(returning: true, hasAccess: access.future);

    await tester.pumpWidget(TrackerApp(ads: ads));
    await tester.pump();
    expect(loading, findsOneWidget);
    expect(ads.loads, 1);
    access.complete(true);
    await tester.pumpAndSettle();
    expect(loading, findsNothing);

    final ad = FakeLaunchAd();
    ads.result.complete(ad);
    await tester.pumpAndSettle();
    expect(ad.shown, isFalse);
    expect(ad.disposed, isTrue);
  });

  testWidgets('ends the ad window at two seconds and skips late ads', (tester) async {
    final ads = FakeAds();
    final access = Completer<bool>();
    mockStartup(returning: true, hasAccess: access.future);

    await tester.pumpWidget(TrackerApp(ads: ads));
    await tester.pump();
    expect(loading, findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(loading, findsNothing);

    final ad = FakeLaunchAd();
    ads.result.complete(ad);
    access.complete(true);
    await tester.pumpAndSettle();
    expect(ad.shown, isFalse);
    expect(ad.disposed, isTrue);
  });

  testWidgets('shows an early ad over loading and clears it after dismissal', (tester) async {
    final ads = FakeAds();
    final access = Completer<bool>();
    mockStartup(returning: true, hasAccess: access.future);

    await tester.pumpWidget(TrackerApp(ads: ads));
    await tester.pump();
    final ad = FakeLaunchAd();
    ads.result.complete(ad);
    await tester.pump();
    expect(ad.shown, isTrue);

    access.complete(true);
    await tester.pump();
    expect(loading, findsOneWidget);
    expect(find.text('Fake top banner'), findsNothing);
    ad.dismissed.complete();
    await tester.pumpAndSettle();
    expect(ad.disposed, isTrue);
    expect(loading, findsNothing);
    expect(find.text('Fake top banner'), findsOneWidget);
  });
}
