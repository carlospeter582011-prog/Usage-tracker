import 'package:data_usage_tracker/usage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('renewal day rolls to the end of shorter months', () {
    expect(billingCycle(DateTime(2026, 2, 27), 31),
      (DateTime(2026, 1, 31), DateTime(2026, 2, 28)));
    expect(billingCycle(DateTime(2026, 2, 28), 31),
      (DateTime(2026, 2, 28), DateTime(2026, 3, 31)));
    expect(billingCycle(DateTime(2026, 1, 1), 20),
      (DateTime(2025, 12, 20), DateTime(2026, 1, 20)));
  });

  test('CSV includes separate traffic directions and escapes app labels', () {
    final wifi = NetworkUsage({
      'total': 40,
      'apps': [
        {'name': '=SUM(1,2)', 'package': 'example.app', 'rx': 17, 'tx': 23, 'bytes': 40},
      ],
    });
    final csv = usageCsv({Network.wifi: wifi}, '2026-11-01', '2026-11-02');
    expect(csv, contains('"download_bytes","upload_bytes","total_bytes"'));
    expect(csv, contains('"example.app","17","23","40"'));
    expect(csvField('=SUM(1,2)'), "\"'=SUM(1,2)\"");
    expect(csvField('An "app"'), '"An ""app"""');
  });

  test('combined usage merges app traffic and requires both networks', () {
    NetworkUsage traffic(int rx, int tx) => NetworkUsage({
      'total': rx + tx,
      'apps': [
        {'name': 'Example', 'package': 'example.app', 'rx': rx, 'tx': tx, 'bytes': rx + tx},
      ],
    });
    final data = {Network.wifi: traffic(20, 5), Network.mobile: traffic(7, 3)};
    final both = data.forNetwork(Network.both)!;
    expect(both.total, 35);
    expect(both.apps.single.rx, 27);
    expect(both.apps.single.tx, 8);
    expect({Network.wifi: data[Network.wifi]}.forNetwork(Network.both), isNull);
    expect(UsageTotals({'wifi': 25, 'mobile': 10}).forNetwork(Network.both), 35);
  });

  test('saving pins preserves plan and alert preferences', () {
    final settings = MonitorSettings.fromJson({
      'limit': 500, 'renewal': 18, 'thresholds': true, 'spikes': true, 'pinned': ['old'],
    }).withPins({'new'});
    expect(settings.toJson(), {
      'limit': 500, 'renewal': 18, 'thresholds': true, 'spikes': true, 'pinned': ['new'],
    });
  });
}
