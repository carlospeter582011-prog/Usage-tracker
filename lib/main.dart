import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MissingPluginException, PlatformException;

import 'usage.dart';

const background = Color(0xFF0C1624);
const panel = Color(0xFF14263A);
const ink = Color(0xFFF2F6FF);
const muted = Color(0xFFA9B9D0);
const mint = Color(0xFF5DE3BB);
const sky = Color(0xFF9DB7FF);

void main() => runApp(const TrackerApp());

class TrackerApp extends StatelessWidget {
  const TrackerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Data Usage Tracker',
    theme: ThemeData(
      colorScheme: const ColorScheme.dark(
        primary: mint,
        onPrimary: background,
        secondary: sky,
        surface: panel,
        onSurface: ink,
      ),
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(backgroundColor: background),
      useMaterial3: true,
    ),
    home: const Dashboard(),
  );
}

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> with WidgetsBindingObserver {
  final usage = UsageService();
  DateTime today = calendarDay(DateTime.now());
  late DateTime day = today;
  late DateTime week = mondayOf(today);
  Network network = Network.mobile;
  bool weekly = false;
  bool? hasAccess;
  bool busy = true;
  String? error;
  int goal = 0;
  int request = 0;
  Map<Network, NetworkUsage>? dailyData;
  List<UsageTotals?>? weeklyData;

  DateTime get earliest => calendarDay(mondayOf(today), -364);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) load();
  }

  Future<void> load() async {
    if (!mounted) return;
    final ticket = ++request;
    setState(() {
      final now = calendarDay(DateTime.now());
      if (day == today) day = now;
      if (week == mondayOf(today)) week = mondayOf(now);
      today = now;
      busy = true;
      error = null;
    });
    try {
      final allowed = await usage.hasAccess();
      if (!mounted || ticket != request) return;
      if (!allowed) {
        setState(() {
          hasAccess = false;
          busy = false;
        });
        return;
      }
      final showWeek = weekly;
      final weekData = showWeek ? await usage.weekly(week) : null;
      final dayData = showWeek ? null : await usage.daily(day);
      final savedGoal = showWeek ? await usage.goal() : null;
      if (!mounted || ticket != request) return;
      setState(() {
        hasAccess = true;
        busy = false;
        dailyData = dayData;
        weeklyData = weekData;
        if (savedGoal != null) goal = savedGoal;
      });
    } on PlatformException catch (exception) {
      if (!mounted || ticket != request) return;
      setState(() {
        busy = false;
        if (exception.code == 'permission') {
          hasAccess = false;
        } else {
          error = exception.message ?? 'Could not read usage. Try again.';
        }
      });
    } on MissingPluginException {
      if (!mounted || ticket != request) return;
      setState(() {
        busy = false;
        error = 'Usage tracking is available on Android.';
      });
    }
  }

  void selectDay(DateTime value) {
    setState(() {
      day = value;
      week = mondayOf(value);
      weekly = false;
    });
    load();
  }

  Future<void> chooseDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: day,
      firstDate: earliest,
      lastDate: today,
    );
    if (selected != null && mounted) selectDay(selected);
  }

  Future<void> openSettings() async {
    try {
      await usage.openSettings();
    } on PlatformException catch (exception) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(exception.message ?? 'Could not open settings.')),
      );
    }
  }

  Future<void> editGoal() async {
    final updated = await showDialog<int>(
      context: context,
      builder: (_) => GoalDialog(initialBytes: goal),
    );
    if (updated == null || !mounted) return;
    try {
      await usage.saveGoal(updated);
      if (mounted) load();
    } on PlatformException catch (exception) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(exception.message ?? 'Could not save limit.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Usage Tracker'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: busy ? null : load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      bottomNavigationBar: hasAccess != true
          ? null
          : NavigationBar(
              selectedIndex: weekly ? 1 : 0,
              onDestinationSelected: (index) {
                if (weekly == (index == 1)) return;
                setState(() => weekly = index == 1);
                load();
              },
              destinations: const [
                NavigationDestination(icon: Icon(Icons.today_outlined), label: 'Daily'),
                NavigationDestination(icon: Icon(Icons.bar_chart_rounded), label: 'Weekly'),
              ],
            ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: busy
                ? const Center(child: CircularProgressIndicator())
                : error != null
                ? notice(Icons.error_outline_rounded, error!, 'Retry', load)
                : hasAccess != true
                ? notice(
                    Icons.lock_outline_rounded,
                    'Enable Usage access for Data Usage Tracker in Android settings to read your network usage.',
                    'Open Usage access settings',
                    openSettings,
                  )
                : weekly
                ? weeklyView(context)
                : dailyView(context),
          ),
        ),
      ),
    );
  }

  Widget notice(IconData icon, String message, String action, VoidCallback onTap) =>
      Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 42, color: mint),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: onTap, child: Text(action)),
            ],
          ),
        ),
      );

  Widget dailyView(BuildContext context) {
    final dates = MaterialLocalizations.of(context);
    final data = dailyData![network]!;
    final color = network == Network.mobile ? mint : sky;
    return ListView.builder(
      key: const PageStorageKey('daily'),
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
      itemCount: data.apps.isEmpty ? 3 : data.apps.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  ChoiceChip(
                    label: const Text('Today'),
                    selected: day == today,
                    onSelected: (_) => selectDay(today),
                  ),
                  ChoiceChip(
                    label: const Text('Yesterday'),
                    selected: day == calendarDay(today, -1),
                    onSelected: (_) => selectDay(calendarDay(today, -1)),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.calendar_month_outlined, size: 18),
                    label: const Text('Pick date'),
                    onPressed: chooseDate,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(dates.formatFullDate(day), style: const TextStyle(color: muted)),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final cards = Network.values.map((type) {
                    return totalCard(type, dailyData![type]!.total);
                  }).toList();
                  if (constraints.maxWidth < 310 ||
                      MediaQuery.textScalerOf(context).scale(16) > 23) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [cards[0], const SizedBox(height: 8), cards[1]],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: cards[0]),
                      const SizedBox(width: 8),
                      Expanded(child: cards[1]),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
            ],
          );
        }
        if (index == 1) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              network == Network.mobile ? 'Mobile data by app' : 'Wi-Fi usage by app',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          );
        }
        if (data.apps.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Android has no per-app records for this date and network.',
              style: TextStyle(color: muted),
            ),
          );
        }
        final app = data.apps[index - 2];
        return AppRow(
          key: ValueKey('$index:${app.package}:${app.name}'),
          app: app,
          color: color,
          maximum: data.apps.first.bytes,
          service: usage,
        );
      },
    );
  }

  Widget totalCard(Network type, int bytes) {
    final mobile = type == Network.mobile;
    final color = mobile ? mint : sky;
    return Semantics(
      selected: network == type,
      child: Material(
        color: panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: network == type ? color : Colors.transparent),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => setState(() => network = type),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(mobile ? Icons.signal_cellular_alt : Icons.wifi, color: color),
                const SizedBox(height: 8),
                Text(mobile ? 'Mobile data' : 'Wi-Fi', style: const TextStyle(color: muted)),
                Text(
                  formatBytes(bytes),
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget weeklyView(BuildContext context) {
    final dates = MaterialLocalizations.of(context);
    final data = weeklyData!;
    final mobile = data.fold<int>(0, (sum, day) => sum + (day?.mobile ?? 0));
    final wifi = data.fold<int>(0, (sum, day) => sum + (day?.wifi ?? 0));
    final peak = data.fold<int>(1, (max, day) => math.max(max, day?.combined ?? 0));
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
      children: [
        Row(
          children: [
            IconButton.outlined(
              tooltip: 'Previous week',
              onPressed: week.isAfter(mondayOf(earliest))
                  ? () {
                      setState(() => week = calendarDay(week, -7));
                      load();
                    }
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                '${dates.formatShortDate(week)} – ${dates.formatShortDate(calendarDay(week, 6))}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton.outlined(
              tooltip: 'Next week',
              onPressed: week.isBefore(mondayOf(today))
                  ? () {
                      setState(() => week = calendarDay(week, 7));
                      load();
                    }
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Weekly total', style: TextStyle(color: muted)),
                Text(formatBytes(mobile + wifi), style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    Text('Mobile ${formatBytes(mobile)}', style: const TextStyle(color: mint)),
                    Text('Wi-Fi ${formatBytes(wifi)}', style: const TextStyle(color: sky)),
                  ],
                ),
                const SizedBox(height: 12),
                if (goal > 0) ...[
                  Text('${formatBytes(mobile)} of ${formatBytes(goal)} mobile limit'),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: math.min(mobile / goal, 1.0),
                    color: mobile > goal ? Colors.orangeAccent : mint,
                  ),
                  if (mobile > goal)
                    Text('${formatBytes(mobile - goal)} over limit', style: const TextStyle(color: Colors.orangeAccent)),
                  const SizedBox(height: 8),
                ],
                OutlinedButton.icon(
                  onPressed: editGoal,
                  icon: const Icon(Icons.flag_outlined),
                  label: Text(goal == 0 ? 'Set weekly mobile limit' : 'Edit weekly mobile limit'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        Text('Compare days', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        for (var index = 0; index < data.length; index++)
          dayComparison(dates, calendarDay(week, index), data[index], peak),
      ],
    );
  }

  Widget dayComparison(MaterialLocalizations dates, DateTime date, UsageTotals? totals, int peak) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        onTap: totals == null ? null : () => selectDay(date),
        title: Text(dates.formatMediumDate(date)),
        trailing: totals == null ? null : const Icon(Icons.chevron_right),
        subtitle: totals == null
            ? const Text('Upcoming')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${formatBytes(totals.combined)} total'),
                  Wrap(
                    spacing: 12,
                    children: [
                      Text('Mobile ${formatBytes(totals.mobile)}', style: const TextStyle(color: mint)),
                      Text('Wi-Fi ${formatBytes(totals.wifi)}', style: const TextStyle(color: sky)),
                    ],
                  ),
                  const SizedBox(height: 5),
                  LayoutBuilder(
                    builder: (_, size) => ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: ColoredBox(
                        color: background,
                        child: Row(
                          children: [
                            SizedBox(
                              width: size.maxWidth * (totals.mobile / peak),
                              height: 8,
                              child: const ColoredBox(color: mint),
                            ),
                            SizedBox(
                              width: size.maxWidth * (totals.wifi / peak),
                              height: 8,
                              child: const ColoredBox(color: sky),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class AppRow extends StatefulWidget {
  const AppRow({
    super.key,
    required this.app,
    required this.color,
    required this.maximum,
    required this.service,
  });

  final AppUsage app;
  final Color color;
  final int maximum;
  final UsageService service;

  @override
  State<AppRow> createState() => _AppRowState();
}

class _AppRowState extends State<AppRow> {
  late final Future<Uint8List?>? icon = switch (widget.app.package) {
    final String name when !name.contains(',') => widget.service.icon(name),
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    const fallback = Icon(Icons.apps_rounded, color: muted);
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: FutureBuilder<Uint8List?>(
                future: icon,
                builder: (_, snapshot) => snapshot.data == null
                    ? fallback
                    : Image.memory(snapshot.data!, errorBuilder: (_, _, _) => fallback),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.app.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (widget.app.package case final String name)
                    Text(name, style: const TextStyle(fontSize: 12, color: muted)),
                  const SizedBox(height: 4),
                  Text(formatBytes(widget.app.bytes), style: TextStyle(color: widget.color)),
                  const SizedBox(height: 5),
                  LinearProgressIndicator(
                    value: widget.app.bytes / widget.maximum,
                    minHeight: 3,
                    color: widget.color,
                    backgroundColor: background,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GoalDialog extends StatefulWidget {
  const GoalDialog({super.key, required this.initialBytes});

  final int initialBytes;

  @override
  State<GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends State<GoalDialog> {
  late final controller = TextEditingController(
    text: widget.initialBytes == 0 ? '' : (widget.initialBytes / 1000000000).toString(),
  );
  String? error;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Weekly mobile limit'),
    content: TextField(
      controller: controller,
      autofocus: true,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: 'Limit (GB)', errorText: error),
    ),
    actions: [
      if (widget.initialBytes > 0)
        TextButton(onPressed: () => Navigator.pop(context, 0), child: const Text('Remove')),
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        onPressed: () {
          final gb = double.tryParse(controller.text.trim().replaceAll(',', '.'));
          if (gb == null || !gb.isFinite || gb < 0.001 || gb > 100000) {
            setState(() => error = 'Enter 0.001–100000 GB.');
            return;
          }
          Navigator.pop(context, (gb * 1000000000).round());
        },
        child: const Text('Save'),
      ),
    ],
  );
}
