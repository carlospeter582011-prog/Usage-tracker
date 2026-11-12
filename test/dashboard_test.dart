import 'package:data_usage_tracker/main.dart';
import 'package:data_usage_tracker/usage.dart';
import 'package:flutter/services.dart';
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

  testWidgets('opens the Android usage access screen when permission is missing', (tester) async {
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

  testWidgets('switches network and loads weekly totals with eight date boundaries', (tester) async {
    tester.view.physicalSize = const Size(390, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    List<Object?>? weeklyBounds;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'hasAccess':
          return true;
        case 'daily':
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
          weeklyBounds = (call.arguments as Map)['bounds'] as List<Object?>;
          return List.generate(7, (_) => {'mobile': 10000000, 'wifi': 20000000});
        case 'goal':
          return 1000000000;
        default:
          return null;
      }
    });
    await tester.pumpWidget(const TrackerApp());
    await tester.pumpAndSettle();
    expect(find.text('com.example.browser'), findsOneWidget);
    await tester.tap(find.text('Wi-Fi'));
    await tester.pumpAndSettle();
    expect(find.text('com.example.video'), findsOneWidget);
    await tester.tap(find.text('Weekly'));
    await tester.pumpAndSettle();
    expect(weeklyBounds, hasLength(8));
    expect(find.text('210 MB'), findsOneWidget);
    expect(find.text('Edit weekly mobile limit'), findsOneWidget);
  });
  testWidgets('keeps Wi-Fi available when Android 6–9 Phone permission is off', (tester) async {
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
        case 'requestPhonePermission':
          requested = true;
          return null;
        default:
          return null;
      }
    });
    await tester.pumpWidget(const TrackerApp());
    await tester.pumpAndSettle();
    expect(find.text('Unavailable'), findsOneWidget);
    await tester.tap(find.text('Allow mobile data access'));
    await tester.pumpAndSettle();
    expect(requested, isTrue);
    await tester.tap(find.text('Wi-Fi'));
    await tester.pumpAndSettle();
    expect(find.text('Wi-Fi usage by app'), findsOneWidget);
    expect(find.text('12.0 MB'), findsOneWidget);
  });

}
