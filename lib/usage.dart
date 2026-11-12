import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show MethodChannel;

enum Network { mobile, wifi, both }

const individualNetworks = [Network.mobile, Network.wifi];

DateTime calendarDay(DateTime date, [int offset = 0]) =>
    DateTime(date.year, date.month, date.day + offset);

DateTime mondayOf(DateTime date) => calendarDay(date, 1 - date.weekday);

String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000;
    unit++;
  }
  final precision = unit == 0 || value >= 100 ? 0 : (value >= 10 ? 1 : 2);
  return '${value.toStringAsFixed(precision)} ${units[unit]}';
}

class AppUsage {
  AppUsage(Map<Object?, Object?> json)
    : name = json['name'] as String,
      package = json['package'] as String?,
      bytes = json['bytes'] as int,
      uid = json['uid'] as int?,
      system = json['system'] as bool?,
      rx = json['rx'] as int? ?? 0,
      tx = json['tx'] as int? ?? 0;

  final String name;
  final String? package;
  final int bytes;
  final int? uid;
  final bool? system;
  final int rx;
  final int tx;

  String get identity => package ?? 'uid:$uid';
}

class NetworkUsage {
  NetworkUsage(Map<Object?, Object?> json)
    : total = json['total'] as int,
      apps = (json['apps'] as List<Object?>)
          .cast<Map<Object?, Object?>>()
          .map(AppUsage.new)
          .toList(growable: false);

  final int total;
  final List<AppUsage> apps;

  late final int appTotal = apps.fold(0, (sum, app) => sum + app.bytes);
}

class UsageTotals {
  UsageTotals(Map<Object?, Object?> json)
    : mobile = json['mobile'] as int?,
      wifi = json['wifi'] as int;

  final int? mobile;
  final int wifi;
  int? forNetwork(Network network) => switch (network) {
    Network.wifi => wifi,
    Network.mobile => mobile,
    Network.both => null,
  };
}

class UsagePeriod {
  UsagePeriod(Map<Object?, Object?> result)
    : total = UsageTotals(result['total'] as Map<Object?, Object?>),
      days = (result['days'] as List<Object?>)
          .map((day) => day == null ? null : UsageTotals(day as Map<Object?, Object?>))
          .toList(growable: false);

  final UsageTotals total;
  final List<UsageTotals?> days;
}

class UsageService {
  static const _channel = MethodChannel('data_usage_tracker/usage');

  Future<bool> hasAccess() async =>
      await _channel.invokeMethod<bool>('hasAccess') ?? false;

  Future<bool> needsPhonePermission() async =>
      await _channel.invokeMethod<bool>('needsPhonePermission') ?? false;

  Future<void> requestPhonePermission() =>
      _channel.invokeMethod<void>('requestPhonePermission');

  Future<void> openSettings() => _channel.invokeMethod<void>('openSettings');

  Future<Map<Network, NetworkUsage?>> daily(DateTime day) =>
      range(calendarDay(day), calendarDay(day, 1), wholeDays: true);

  Future<Map<Network, NetworkUsage?>> range(DateTime start, DateTime end, {
    bool wholeDays = false,
  }) async {
    final result = (await _channel.invokeMapMethod<Object?, Object?>('daily', {
      'wholeDays': wholeDays,
      'bounds': [
        start.millisecondsSinceEpoch,
        end.millisecondsSinceEpoch,
      ],
    }))!;
    return {
      for (final network in individualNetworks)
        network: result[network.name] == null
            ? null
            : NetworkUsage(result[network.name] as Map<Object?, Object?>),
    };
  }

  Future<UsagePeriod> weekly(DateTime monday) =>
      _series('weekly', monday, 7);

  Future<UsagePeriod> monthly(DateTime firstDay) =>
      _series('monthly', firstDay, DateTime(firstDay.year, firstDay.month + 1, 0).day);

  Future<UsagePeriod> _series(String method, DateTime start, int days) async {
    final result = (await _channel.invokeMapMethod<Object?, Object?>(method, {
      'bounds': List.generate(
        days + 1,
        (index) => calendarDay(start, index).millisecondsSinceEpoch,
      ),
    }))!;
    return UsagePeriod(result);
  }

  Future<int?> mobileTotal(DateTime start, DateTime end) =>
      _channel.invokeMethod<int>('mobileTotal', {
        'bounds': [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
      });

  Future<List<Object?>> appHistory(int uid, DateTime start, int days) async =>
      await _channel.invokeListMethod<Object?>('appHistory', {
        'uid': uid,
        'bounds': List.generate(days + 1,
            (index) => calendarDay(start, index).millisecondsSinceEpoch),
      }) ?? const [];

  Future<MonitorSettings> settings() async {
    final value = await _channel.invokeMethod<String>('monitorSettings');
    return value == null ? const MonitorSettings() :
        MonitorSettings.fromJson(jsonDecode(value) as Map<String, dynamic>);
  }

  Future<void> saveSettings(MonitorSettings settings) =>
      _channel.invokeMethod<void>('saveMonitorSettings', {'value': jsonEncode(settings.toJson())});

  Future<String?> language() => _channel.invokeMethod<String>('language');

  Future<void> saveLanguage(String value) =>
      _channel.invokeMethod<void>('saveLanguage', {'value': value});

  Future<bool> pinWidget(Network network) async =>
      await _channel.invokeMethod<bool>('pinWidget', {'network': network.name}) ?? false;

  Future<Network?> widgetNetwork() async {
    final name = await _channel.invokeMethod<String>('widgetNetwork');
    return Network.values.asNameMap()[name];
  }

  void onWidgetNavigation(Future<void> Function()? onOpen) {
    _channel.setMethodCallHandler(onOpen == null ? null : (call) async {
      if (call.method == 'widgetNavigation') await onOpen();
    });
  }

  Future<bool> notificationPermission() async =>
      await _channel.invokeMethod<bool>('notificationPermission') ?? false;

  Future<bool> exportCsv(String csv) async =>
      await _channel.invokeMethod<bool>('exportCsv', {'csv': csv}) ?? false;

  Future<Uint8List?> icon(String package) =>
      _channel.invokeMethod<Uint8List>('icon', {'package': package});

  Future<bool> returningLaunch() async =>
      await _channel.invokeMethod<bool>('returningLaunch') ?? false;

  Future<String?> appearance() => _channel.invokeMethod<String>('appearance');

  Future<void> saveAppearance(String mode) =>
      _channel.invokeMethod<void>('saveAppearance', {'mode': mode});

  Future<int> goal() async => await _channel.invokeMethod<int>('goal') ?? 0;

  Future<void> saveGoal(int bytes) =>
      _channel.invokeMethod<void>('saveGoal', {'bytes': bytes});
}

class MonitorSettings {
  const MonitorSettings({
    this.limit = 0, this.renewal = 1, this.thresholds = false,
    this.spikes = false, this.pinned = const {},
  });

  MonitorSettings.fromJson(Map<String, dynamic> json)
    : limit = json['limit'] as int? ?? 0,
      renewal = json['renewal'] as int? ?? 1,
      thresholds = json['thresholds'] as bool? ?? false,
      spikes = json['spikes'] as bool? ?? false,
      pinned = ((json['pinned'] as List?) ?? const []).cast<String>().toSet();

  final int limit;
  final int renewal;
  final bool thresholds;
  final bool spikes;
  final Set<String> pinned;

  MonitorSettings withPins(Set<String> pins) => MonitorSettings(
    limit: limit, renewal: renewal, thresholds: thresholds, spikes: spikes, pinned: pins,
  );

  Map<String, Object> toJson() => {
    'limit': limit, 'renewal': renewal, 'thresholds': thresholds,
    'spikes': spikes, 'pinned': pinned.toList(),
  };
}

(DateTime, DateTime) billingCycle(DateTime date, int renewal) {
  DateTime inMonth(int month) {
    final days = DateTime(date.year, month + 1, 0).day;
    return DateTime(date.year, month, renewal.clamp(1, days));
  }

  final day = calendarDay(date);
  final current = inMonth(day.month);
  return day.isBefore(current)
      ? (inMonth(day.month - 1), current)
      : (current, inMonth(day.month + 1));
}

String csvField(Object value) {
  var cell = value.toString();
  if (value is String && RegExp(r'^\s*[=+@-]').hasMatch(cell)) {
    cell = "'$cell";
  }
  return '"${cell.replaceAll('"', '""')}"';
}

String usageCsv(
  Map<Network, NetworkUsage?> data,
  String start,
  String end,
) {
  final rows = <List<Object>>[
    ['start_date', 'end_date', 'network', 'app', 'package', 'download_bytes',
      'upload_bytes', 'total_bytes'],
    for (final network in individualNetworks)
      if (data[network] case final NetworkUsage values) ...[
        [start, end, network.name, 'Device total', '', '', '', values.total],
        for (final app in values.apps)
          [start, end, network.name, app.name, app.package ?? '', app.rx, app.tx, app.bytes],
      ],
  ];
  final csv = StringBuffer();
  for (final row in rows) {
    csv.writeln(row.map(csvField).join(','));
  }
  return csv.toString();
}
