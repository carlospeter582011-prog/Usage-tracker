import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'feature_language.dart';
import 'usage.dart';
import 'tracker_ui.dart';

String shownBytes(int? value) => value == null ? '—' : formatBytes(value);

Future<void> showUsageExplanation(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(tr(context, 'How Android counts usage', 'أندرويد بيحسب الاستهلاك إزاي')),
    content: Text(tr(context,
      'Totals include downloads and uploads for the selected dates. Android records traffic in time buckets, so daily values can be approximate and recent traffic can appear later. The device total and the app list use different Android counters. Mobile data may include more than one SIM.',
      'الأرقام بتشمل التنزيل والرفع في التواريخ المختارة. أندرويد بيسجّل الاستهلاك على فترات، فالأرقام اليومية ممكن تبقى تقريبية والاستهلاك الجديد ممكن يظهر متأخر. إجمالي الجهاز وقائمة التطبيقات بييجوا من عدّادات مختلفة، وداتا الموبايل ممكن تشمل أكتر من شريحة.')),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context),
        child: Text(tr(context, 'Done', 'تمام'))),
    ],
  ),
);

class PlanEditor extends StatefulWidget {
  const PlanEditor({super.key, required this.settings});

  final MonitorSettings settings;

  @override
  State<PlanEditor> createState() => _PlanEditorState();
}

class _PlanEditorState extends State<PlanEditor> {
  late final size = TextEditingController(
    text: widget.settings.limit == 0 ? '' : (widget.settings.limit / 1e9).toString(),
  );
  late final day = TextEditingController(text: '${widget.settings.renewal}');
  late bool thresholds = widget.settings.thresholds;
  late bool spikes = widget.settings.spikes;
  String? error;

  @override
  void dispose() {
    size.dispose();
    day.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(tr(context, 'Mobile data plan', 'باقة الموبايل')),
    content: SingleChildScrollView(child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: size,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: tr(context, 'Plan size (GB)', 'حجم الباقة (جيجابايت)')),
        ),
        TextField(
          controller: day,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: tr(context, 'Monthly renewal day (1–31)', 'يوم التجديد الشهري (١–٣١)')),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: thresholds, onChanged: (value) => setState(() => thresholds = value),
          title: Text(tr(context, 'Alerts at 50%, 80% and 100%', 'تنبيهات عند ٥٠٪ و٨٠٪ و١٠٠٪')),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: spikes, onChanged: (value) => setState(() => spikes = value),
          title: Text(tr(context, 'Unusual daily use alert', 'تنبيه عند ارتفاع الاستهلاك اليومي')),
        ),
        if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ],
    )),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(tr(context, 'Cancel', 'إلغاء'))),
      FilledButton(
        onPressed: () {
          final raw = size.text.trim().replaceAll(',', '.');
          final gb = raw.isEmpty ? 0.0 : double.tryParse(raw);
          final renewal = int.tryParse(day.text);
          if (gb == null || !gb.isFinite || gb < 0 || gb > 100000 ||
              renewal == null || renewal < 1 || renewal > 31 || (thresholds && gb < .001)) {
            setState(() => error = tr(context,
              'Enter a valid plan size and a renewal day from 1 to 31.',
              'اكتب حجم باقة صالح ويوم تجديد من ١ لـ٣١.'));
            return;
          }
          Navigator.pop(context, MonitorSettings(
            limit: (gb * 1e9).round(), renewal: renewal,
            thresholds: thresholds, spikes: spikes, pinned: widget.settings.pinned,
          ));
        },
        child: Text(tr(context, 'Save', 'حفظ')),
      ),
    ],
  );
}

class PlanSummary extends StatelessWidget {
  const PlanSummary({super.key, required this.settings, required this.service, required this.today,
    required this.revision, required this.onEdit});

  final MonitorSettings settings;
  final UsageService service;
  final DateTime today;
  final int revision;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final (start, end) = billingCycle(today, settings.renewal);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.donut_large_outlined),
        title: Text(tr(context, 'Mobile data plan', 'باقة الموبايل')),
        subtitle: settings.limit == 0
            ? Text(tr(context, 'Set your allowance and renewal day', 'حدّد حجم الباقة ويوم التجديد'))
            : _PlanBalance(
                key: ValueKey((settings.limit, start, revision)),
                used: () => service.mobileTotal(start, end),
                limit: settings.limit,
                today: today,
                end: end,
              ),
        trailing: const Icon(Icons.edit_outlined),
        onTap: onEdit,
      ),
    );
  }
}

class _PlanBalance extends StatefulWidget {
  const _PlanBalance({super.key, required this.used, required this.limit, required this.today, required this.end});

  final Future<int?> Function() used;
  final int limit;
  final DateTime today;
  final DateTime end;

  @override
  State<_PlanBalance> createState() => _PlanBalanceState();
}

class _PlanBalanceState extends State<_PlanBalance> {
  late final future = widget.used();

  @override
  Widget build(BuildContext context) => FutureBuilder<int?>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return Text(tr(context, 'Checking usage…', 'بنحسب الاستهلاك…'));
      }
      final used = snapshot.data;
      if (used == null) return Text(tr(context, 'Mobile data unavailable', 'بيانات الموبايل غير متاحة'));
      final remaining = math.max(0, widget.limit - used);
      final days = DateTime.utc(widget.end.year, widget.end.month, widget.end.day)
          .difference(DateTime.utc(widget.today.year, widget.today.month, widget.today.day)).inDays;
      final daily = remaining ~/ math.max(1, days);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr(context, '${formatBytes(remaining)} left · $days days until renewal',
            'متبقي ${formatBytes(remaining)} · التجديد بعد $days يوم')),
          Text(tr(context, 'Daily budget: ${formatBytes(daily)}', 'المتاح يوميًا: ${formatBytes(daily)}')),
          Text(tr(context, 'Renews ${MaterialLocalizations.of(context).formatShortDate(widget.end)}',
            'التجديد ${MaterialLocalizations.of(context).formatShortDate(widget.end)}')),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: (used / widget.limit).clamp(0.0, 1.0).toDouble()),
        ],
      );
    },
  );
}

class AppHistoryPage extends StatefulWidget {
  const AppHistoryPage({super.key, required this.app, required this.day, required this.service,
    required this.pinned, required this.onPin});

  final AppUsage app;
  final DateTime day;
  final UsageService service;
  final bool pinned;
  final Future<void> Function() onPin;

  @override
  State<AppHistoryPage> createState() => _AppHistoryPageState();
}

class _AppHistoryPageState extends State<AppHistoryPage> {
  late bool pinned = widget.pinned;
  bool saving = false;
  late DateTime end = widget.day;
  late Future<List<Object?>> history = readHistory();

  Future<List<Object?>> readHistory() => widget.app.uid == null
      ? Future.value(const [])
      : widget.service.appHistory(widget.app.uid!, calendarDay(end, -6), 7);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr(context, 'App usage', 'استهلاك التطبيق')), actions: [
      IconButton(
        tooltip: pinned ? tr(context, 'Unpin', 'إلغاء التثبيت') : tr(context, 'Pin app', 'ثبّت التطبيق'),
        icon: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined),
        onPressed: saving ? null : () async {
          setState(() => saving = true);
          try {
            await widget.onPin();
            if (mounted) setState(() => pinned = !pinned);
          } catch (_) {
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(tr(context, 'Could not save the pin.', 'تعذّر حفظ التثبيت.')),
            ));
          } finally {
            if (mounted) setState(() => saving = false);
          }
        },
      ),
    ]),
    body: SafeArea(child: FutureBuilder<List<Object?>>(
      future: history,
      builder: (context, snapshot) {
        final waiting = snapshot.connectionState != ConnectionState.done;
        final days = waiting ? const <Object?>[] : snapshot.data ?? const [];
        final dates = MaterialLocalizations.of(context);
        final theme = Theme.of(context);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  AppIcon(packageName: widget.app.package, service: widget.service, size: 56),
                  const SizedBox(width: 14),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(displayAppName(context, widget.app.name),
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      if (widget.app.package case final String packageName)
                        Text(packageName, textDirection: TextDirection.ltr,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  )),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              IconButton(
                tooltip: tr(context, 'Previous seven days', 'السبع أيام السابقة'),
                onPressed: () => move(-7), icon: const Icon(Icons.chevron_left),
              ),
              Expanded(child: Text(
                '${dates.formatShortDate(calendarDay(end, -6))} – ${dates.formatShortDate(end)}',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge,
              )),
              IconButton(
                tooltip: tr(context, 'Next seven days', 'السبع أيام التالية'),
                onPressed: end.isBefore(widget.day) ? () => move(7) : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ]),
            const SizedBox(height: 8),
            if (waiting)
              const LinearProgressIndicator()
            else if (days.isEmpty)
              Text(tr(context, 'App history unavailable', 'سجل التطبيق غير متاح')),
            for (var index = days.length - 1; index >= 0; index--)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(dates.formatFullDate(calendarDay(end, index - 6)),
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      for (final network in [Network.wifi, Network.mobile])
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(children: [
                            Icon(network.icon, size: 17, color: network == Network.wifi
                              ? theme.colorScheme.primary : theme.colorScheme.secondary),
                            const SizedBox(width: 8),
                            Expanded(child: Text(network.label(context), style: theme.textTheme.bodySmall)),
                            Flexible(child: Text(trafficLabel((days[index] as Map)[network.name]),
                              textAlign: TextAlign.end, style: theme.textTheme.bodySmall)),
                          ]),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    )),
  );

  void move(int offset) => setState(() {
    end = calendarDay(end, offset);
    if (end.isAfter(widget.day)) end = widget.day;
    history = readHistory();
  });
}

String trafficLabel(Object? value) {
  if (value is! Map) return '—';
  return '↓ ${formatBytes(value['rx'] as int)}  ↑ ${formatBytes(value['tx'] as int)}';
}

class RangeReportPage extends StatefulWidget {
  const RangeReportPage({super.key, required this.service, required this.network, required this.today});

  final UsageService service;
  final Network network;
  final DateTime today;

  @override
  State<RangeReportPage> createState() => _RangeReportPageState();
}

class _RangeReportPageState extends State<RangeReportPage> {
  late DateTimeRange dates = DateTimeRange(start: mondayOf(widget.today), end: widget.today);
  late Network network = widget.network;
  bool compare = false;
  bool exporting = false;
  late Future<List<Map<Network, NetworkUsage?>>> result = load();

  Future<List<Map<Network, NetworkUsage?>>> load() async {
    final now = DateTime.now();
    final start = compare ? mondayOf(widget.today) : dates.start;
    final end = compare ? now : calendarDay(dates.end, 1);
    final current = await widget.service.range(start, end);
    if (!compare) return [current];
    final priorEnd = DateTime(now.year, now.month, now.day - 7, now.hour, now.minute, now.second);
    final previous = await widget.service.range(calendarDay(start, -7), priorEnd);
    return [current, previous];
  }

  void setMode(bool comparing) => setState(() {
    compare = comparing;
    result = load();
  });

  Future<void> chooseRange() async {
    final selected = await showDateRangePicker(
      context: context,
      firstDate: calendarDay(widget.today, -364),
      lastDate: widget.today,
      initialDateRange: dates,
    );
    if (selected == null || !mounted) return;
    setState(() {
      dates = selected;
      compare = false;
      result = load();
    });
  }

  Future<void> export(Map<Network, NetworkUsage?> data) async {
    String iso(DateTime date) => date.toIso8601String().split('T').first;
    setState(() => exporting = true);
    try {
      final saved = await widget.service.exportCsv(usageCsv(data, iso(dates.start), iso(dates.end)));
      if (mounted && saved) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'CSV saved', 'تم حفظ ملف CSV'))),
      );
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'Could not export CSV.', 'تعذّر تصدير ملف CSV.'))),
      );
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr(context, 'Usage reports', 'تقارير الاستهلاك')), actions: [
      IconButton(
        tooltip: tr(context, 'About usage totals', 'عن أرقام الاستهلاك'),
        onPressed: () => showUsageExplanation(context),
        icon: const Icon(Icons.info_outline),
      ),
    ]),
    body: SafeArea(child: FutureBuilder<List<Map<Network, NetworkUsage?>>>(
      future: result,
      builder: (context, snapshot) {
        final waiting = snapshot.connectionState != ConnectionState.done;
        final values = waiting ? null : snapshot.data;
        final current = values?.first[network];
        final prior = compare && values != null ? values.last[network] : null;
        final previousByApp = {for (final app in prior?.apps ?? <AppUsage>[]) app.identity: app.bytes};
        final changes = [
          if (compare && prior != null)
            for (final app in current?.apps ?? <AppUsage>[])
              (app, app.bytes - (previousByApp[app.identity] ?? 0)),
        ]..sort((a, b) => b.$2.compareTo(a.$2));
        final formats = MaterialLocalizations.of(context);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(spacing: 8, runSpacing: 4, children: [
              ChoiceChip(label: Text(tr(context, 'Custom period', 'فترة مخصصة')),
                selected: !compare, onSelected: (_) => setMode(false)),
              ChoiceChip(label: Text(tr(context, 'Compare weeks', 'قارن الأسابيع')),
                selected: compare, onSelected: (_) => setMode(true)),
            ]),
            if (!compare) TextButton.icon(
              onPressed: chooseRange,
              icon: const Icon(Icons.date_range),
              label: Text('${formats.formatShortDate(dates.start)} – ${formats.formatShortDate(dates.end)}'),
            ) else
              Text(tr(context, 'This week so far vs the same elapsed time last week',
                'الأسبوع الحالي لحد دلوقتي مقابل نفس الفترة الأسبوع اللي فات')),
            const SizedBox(height: 8),
            NetworkChoices(selected: network, onChanged: (value) => setState(() => network = value)),
            const SizedBox(height: 12),
            if (waiting) const LinearProgressIndicator()
            else if (values == null) ListTile(
              title: Text(tr(context, 'Could not load usage.', 'تعذّر تحميل الاستهلاك.')),
              trailing: IconButton(onPressed: () => setMode(compare), icon: const Icon(Icons.refresh)),
            ) else ...[
              Card(child: ListTile(
                leading: Icon(network.icon, color: Theme.of(context).colorScheme.primary),
                title: Text(tr(context, compare ? 'Device total this week' : 'Device total',
                  compare ? 'إجمالي الجهاز الأسبوع ده' : 'إجمالي الجهاز')),
                subtitle: Text(shownBytes(current?.total), style: Theme.of(context).textTheme.headlineSmall),
              )),
              if (compare) ListTile(title: Text(tr(context, 'Previous week', 'الأسبوع السابق')),
                trailing: Text(shownBytes(prior?.total))),
              if (!compare) OutlinedButton.icon(
                onPressed: exporting ? null : () => export(values.first),
                icon: const Icon(Icons.download),
                label: Text(tr(context, 'Export both networks to CSV', 'صدّر الشبكتين إلى CSV')),
              ),
              if (compare) ...[
                Text(tr(context, 'Apps with the biggest increases', 'أكبر زيادات حسب التطبيق'),
                  style: Theme.of(context).textTheme.titleMedium),
                for (final entry in changes.where((entry) => entry.$2 > 0).take(10))
                  ListTile(title: Text(displayAppName(context, entry.$1.name)), trailing: Text('+${formatBytes(entry.$2)}')),
                if (!changes.any((entry) => entry.$2 > 0))
                  Text(tr(context, 'No app increases available', 'مفيش زيادات متاحة للتطبيقات')),
              ] else if (current != null && current.apps.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(tr(context, 'Usage by app', 'الاستهلاك حسب التطبيق'),
                  style: Theme.of(context).textTheme.titleMedium),
                for (final (index, app) in current.apps.indexed)
                  AppRow(
                    key: ValueKey((network, index, app.identity)),
                    app: app,
                    service: widget.service,
                    color: Theme.of(context).colorScheme.primary,
                    total: current.appTotal,
                  ),
              ] else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(current == null
                    ? tr(context, 'Usage is unavailable for this selection.', 'بيانات الاستهلاك للاختيار ده مش متاحة.')
                    : tr(context, 'No app activity for this period.', 'مفيش استهلاك للتطبيقات في الفترة دي.')),
                ),
            ],
          ],
        );
      },
    )),
  );
}
