import 'dart:convert';

import 'package:data_usage_tracker/main.dart';
import 'package:data_usage_tracker/reports.dart';
import 'package:data_usage_tracker/usage.dart';
import 'package:material_ui/material_ui.dart' show Brightness, Image, MaterialApp, SizedBox, Theme, ThemeMode;
import 'package:flutter/services.dart' show MethodChannel, Offset, Size;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('data_usage_tracker/usage');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('uses decimal units and local calendar boundaries', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(1500000000), '1.50 GB');
    expect(calendarDay(DateTime(2026, 12, 31), 1), DateTime(2027, 1, 1));
    expect(mondayOf(DateTime(2026, 11, 15)), DateTime(2026, 11, 9));
  });

  testWidgets('opens Android Usage access settings when permission is missing', (tester) async {
    var opened = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'hasAccess') return false;
      if (call.method == 'openSettings') opened = true;
      return null;
    });
    await tester.pumpWidget(const TrackerApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Usage access settings'));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
  });

  testWidgets('defaults to automatic and persists a manual appearance', (tester) async {
    String? saved;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'appearance':
          return saved;
        case 'saveAppearance':
          saved = (call.arguments as Map)['mode'] as String;
          return null;
        case 'hasAccess':
          return false;
        default:
          return null;
      }
    });

    ThemeMode? appMode() => tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode;

    await tester.pumpWidget(const TrackerApp());
    await tester.pumpAndSettle();
    expect(appMode(), ThemeMode.system);
    final dispatcher = tester.binding.platformDispatcher;
    addTearDown(dispatcher.clearPlatformBrightnessTestValue);
    dispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.byType(Dashboard))).brightness, Brightness.dark);
    dispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.byType(Dashboard))).brightness, Brightness.light);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Automatic'), findsOneWidget);
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(saved, 'dark');
    expect(appMode(), ThemeMode.dark);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const TrackerApp());
    await tester.pumpAndSettle();
    expect(appMode(), ThemeMode.dark);

    for (final choice in {'Light': ThemeMode.light, 'Automatic': ThemeMode.system}.entries) {
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Appearance'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(choice.key));
      await tester.pumpAndSettle();
      expect(saved, choice.value.name);
      expect(appMode(), choice.value);
    }
  });

  testWidgets('shows a weekly overview and the selected network in details', (tester) async {
    tester.view.physicalSize = const Size(390, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final queries = <String, List<Object?>>{};
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'hasAccess':
          return true;
        case 'daily':
          queries['daily'] = (call.arguments as Map)['bounds'] as List<Object?>;
          return {
            'mobile': {
              'total': 24000000,
              'apps': [
                {'name': 'Browser', 'package': 'com.example.browser', 'bytes': 12000000},
              ],
            },
            'wifi': {
              'total': 90000000,
              'apps': [
                {'name': 'Video', 'package': 'com.example.video', 'bytes': 84000000},
              ],
            },
          };
        case 'weekly':
        case 'monthly':
          final bounds = (call.arguments as Map)['bounds'] as List<Object?>;
          queries[call.method] = bounds;
          return List.generate(bounds.length - 1, (_) => {'mobile': 10000000, 'wifi': 20000000});
        case 'goal':
          return 1000000000;
        default:
          return null;
      }
    });

    await tester.pumpWidget(const TrackerApp());
    await tester.pumpAndSettle();
    expect(queries['weekly'], isNull);
    expect(find.text('90.0 MB'), findsOneWidget);
    expect(find.text('24.0 MB'), findsOneWidget);
    expect(find.text('Both'), findsNothing);
    await tester.drag(find.text('Today’s usage'), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('Weekly'), findsNothing);
    await tester.tap(find.text('Analyze mobile data'));
    await tester.pumpAndSettle();
    expect(queries['weekly'], hasLength(8));
    expect(find.text('70.0 MB · Weekly total'), findsOneWidget);
    expect(find.text('com.example.browser'), findsOneWidget);
    await tester.tap(find.byTooltip('Back to overview'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Analyze Wi-Fi'));
    await tester.pumpAndSettle();
    expect(find.text('com.example.video'), findsOneWidget);

    await tester.tap(find.text('Monthly'));
    await tester.pumpAndSettle();
    final today = DateTime.now();
    final monthDays = DateTime(today.year, today.month + 1, 0).day;
    expect(queries['monthly'], hasLength(monthDays + 1));
    await tester.tap(find.text('Yesterday'));
    await tester.pumpAndSettle();
    expect(queries['daily']!.first, calendarDay(today, -1).millisecondsSinceEpoch);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps Wi-Fi available without Android 7–9 Phone permission', (tester) async {
    tester.view.physicalSize = const Size(390, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var requested = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'hasAccess':
        case 'needsPhonePermission':
          return true;
        case 'daily':
          return {
            'mobile': null,
            'wifi': {'total': 12000000, 'apps': []},
          };
        case 'weekly':
          return List.generate(7, (_) => {'mobile': null, 'wifi': 12000000});
        case 'requestPhonePermission':
          requested = true;
          return null;
        default:
          return null;
      }
    });

    await tester.pumpWidget(const TrackerApp());
    await tester.pumpAndSettle();
    expect(find.text('12.0 MB'), findsOneWidget);
    await tester.tap(find.text('Analyze mobile data'));
    await tester.pumpAndSettle();
    expect(find.text('Unavailable'), findsOneWidget);
    await tester.tap(find.text('Allow mobile data access'));
    await tester.pumpAndSettle();
    expect(requested, isTrue);
    await tester.tap(find.byTooltip('Back to overview'));
    await tester.pumpAndSettle();
    expect(find.text('12.0 MB'), findsOneWidget);
  });
  testWidgets('shows the selected app icon and identity in usage history', (tester) async {
    final requested = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'icon') return null;
      requested.add((call.arguments as Map)['package'] as String);
      return base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNgWNUBAAHgATPetbznAAAAAElFTkSuQmCC');
    });
    await tester.pumpWidget(MaterialApp(home: AppHistoryPage(
      app: AppUsage({'name': 'Google Play Store', 'package': 'com.android.vending', 'bytes': 0}),
      day: DateTime(2026, 11, 12),
      service: UsageService(),
      pinned: false,
      onPin: () async {},
    )));
    await tester.pumpAndSettle();
    expect(find.text('Google Play Store'), findsOneWidget);
    expect(find.text('com.android.vending'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(requested, ['com.android.vending']);
  });

  testWidgets('adds any of the three widgets from the dashboard', (tester) async {
    final requests = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'hasAccess':
          return true;
        case 'daily':
          return {
            'mobile': {'total': 20, 'apps': []},
            'wifi': {'total': 30, 'apps': []},
          };
        case 'pinWidget':
          requests.add((call.arguments as Map)['network'] as String);
          return true;
        default:
          return null;
      }
    });

    await tester.pumpWidget(const TrackerApp());
    await tester.pumpAndSettle();
    for (final label in ['Wi-Fi', 'Mobile data', 'Wi-Fi + mobile data']) {
      await tester.tap(find.text('Add widget'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a home screen widget'), findsOneWidget);
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }
    expect(requests, ['wifi', 'mobile', 'both']);
  });

  for (final destination in ['wifi', 'mobile', 'both']) {
    testWidgets('opens the correct page for the $destination widget', (tester) async {
      String? pending = destination;
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'widgetNetwork':
            final next = pending;
            pending = null;
            return next;
          case 'hasAccess':
            return true;
          case 'daily':
            return {
              'mobile': {'total': 20, 'apps': []},
              'wifi': {'total': 30, 'apps': []},
            };
          case 'weekly':
            return List.generate(7, (_) => {'mobile': 20, 'wifi': 30});
          default:
            return null;
        }
      });
      await tester.pumpWidget(const TrackerApp());
      await tester.pumpAndSettle();
      if (destination == 'both') {
        expect(find.text('Analyze Wi-Fi'), findsOneWidget);
        expect(find.text('Analyze mobile data'), findsOneWidget);
        expect(find.byTooltip('Back to overview'), findsNothing);
      } else {
        expect(find.byTooltip('Back to overview'), findsOneWidget);
        expect(find.text(destination == 'wifi' ? 'Wi-Fi usage by app' : 'Mobile data usage by app'),
          findsOneWidget);
      }
    });
  }

}
