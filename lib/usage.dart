import 'dart:typed_data';

import 'package:flutter/services.dart' show MethodChannel;

enum Network { mobile, wifi }

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
      bytes = json['bytes'] as int;

  final String name;
  final String? package;
  final int bytes;
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
}

class UsageTotals {
  UsageTotals(Map<Object?, Object?> json)
    : mobile = json['mobile'] as int?,
      wifi = json['wifi'] as int;

  final int? mobile;
  final int wifi;
  int? forNetwork(Network network) => network == Network.wifi ? wifi : mobile;
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

  Future<Map<Network, NetworkUsage?>> daily(DateTime day) async {
    final result = (await _channel.invokeMapMethod<Object?, Object?>('daily', {
      'bounds': [
        calendarDay(day).millisecondsSinceEpoch,
        calendarDay(day, 1).millisecondsSinceEpoch,
      ],
    }))!;
    return {
      for (final network in Network.values)
        network: result[network.name] == null
            ? null
            : NetworkUsage(result[network.name] as Map<Object?, Object?>),
    };
  }

  Future<List<UsageTotals?>> weekly(DateTime monday) =>
      _series('weekly', monday, 7);

  Future<List<UsageTotals?>> monthly(DateTime firstDay) =>
      _series('monthly', firstDay, DateTime(firstDay.year, firstDay.month + 1, 0).day);

  Future<List<UsageTotals?>> _series(String method, DateTime start, int days) async {
    final result = (await _channel.invokeListMethod<Object?>(method, {
      'bounds': List.generate(
        days + 1,
        (index) => calendarDay(start, index).millisecondsSinceEpoch,
      ),
    }))!;
    return result
        .map((day) => day == null ? null : UsageTotals(day as Map<Object?, Object?>))
        .toList(growable: false);
  }

  Future<Uint8List?> icon(String package) =>
      _channel.invokeMethod<Uint8List>('icon', {'package': package});

  Future<String?> appearance() => _channel.invokeMethod<String>('appearance');

  Future<void> saveAppearance(String mode) =>
      _channel.invokeMethod<void>('saveAppearance', {'mode': mode});

  Future<int> goal() async => await _channel.invokeMethod<int>('goal') ?? 0;

  Future<void> saveGoal(int bytes) =>
      _channel.invokeMethod<void>('saveGoal', {'bytes': bytes});
}
