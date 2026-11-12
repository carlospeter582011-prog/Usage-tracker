import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException, SystemUiOverlayStyle;

import 'usage.dart';

const background = Color(0xFFF6F6F9);
const panel = Colors.white;
const ink = Color(0xFF202237);
const muted = Color(0xFF68738B);
const track = Color(0xFFE9EBF2);
const blue = Color(0xFF3B73DF);
const colors = [
  Color(0xFF4585F5), Color(0xFF4861F5), Color(0xFF6446F5),
  Color(0xFF9545F4), Color(0xFFD543F0), Color(0xFFF241CC),
];

void main() => runApp(const TrackerApp());

class TrackerApp extends StatelessWidget {
  const TrackerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Data Usage Tracker',
    theme: ThemeData(
      colorScheme: const ColorScheme.light(primary: blue, surface: panel, onSurface: ink),
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: ink,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
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
  Network network = Network.wifi;
  bool details = false;
  bool monthly = false;
  bool hasAccess = false;
  bool busy = true;
  bool needsPhonePermission = false;
  String? error;
  int goal = 0;
  int request = 0;
  Map<Network, NetworkUsage?>? dailyData;
  List<UsageTotals?>? periodData;
  DateTime? loadedPeriod;

  bool get mobile => network == Network.mobile;
  String get networkName => mobile ? 'Mobile data' : 'Wi-Fi';
  DateTime get earliest => calendarDay(mondayOf(today), -364);
  DateTime get periodStart {
    final selected = details ? day : today;
    return details && monthly
        ? DateTime(selected.year, selected.month)
        : mondayOf(selected);
  }

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

  Future<void> load({bool reusePeriod = false}) async {
    if (!mounted) return;
    final ticket = ++request;
    setState(() {
      final now = calendarDay(DateTime.now());
      if (day == today || day.isAfter(now)) day = now;
      today = now;
      if (day.isBefore(earliest)) day = earliest;
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
          dailyData = null;
          periodData = null;
          loadedPeriod = null;
        });
        return;
      }
      final selected = details ? day : today;
      final start = periodStart;
      final month = details && monthly;
      final cached = reusePeriod && loadedPeriod == start ? periodData : null;
      final phonePermission = await usage.needsPhonePermission();
      if (!mounted || ticket != request) return;
      final data = await usage.daily(selected);
      final period = cached ??
          (month ? await usage.monthly(start) : await usage.weekly(start));
      final savedGoal = await usage.goal();
      if (!mounted || ticket != request) return;
      setState(() {
        hasAccess = true;
        needsPhonePermission = phonePermission;
        busy = false;
        dailyData = data;
        periodData = period;
        loadedPeriod = start;
        goal = savedGoal;
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

  void openDetails() {
    if (details || busy) return;
    setState(() {
      day = today;
      details = true;
      monthly = false;
    });
  }

  void closeDetails() {
    setState(() => details = false);
    load();
  }

  void selectDay(DateTime value) {
    if (value == day || value.isBefore(earliest) || value.isAfter(today)) return;
    setState(() => day = value);
    load(reusePeriod: true);
  }

  void movePeriod(int direction) {
    final target = monthly
        ? DateTime(day.year, day.month + direction)
        : calendarDay(day, direction * 7);
    selectDay(target.isAfter(today) ? today : (target.isBefore(earliest) ? earliest : target));
  }

  Future<void> chooseDate() async {
    final selected = await showDatePicker(
      context: context, initialDate: day, firstDate: earliest, lastDate: today,
    );
    if (selected != null && mounted) selectDay(selected);
  }

  Future<void> platformAction(Future<void> Function() action, {bool reload = false}) async {
    try {
      await action();
      if (reload && mounted) load();
    } on PlatformException catch (exception) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(exception.message ?? 'Could not complete this action.')),
      );
    }
  }

  void requestPhonePermission() => platformAction(usage.requestPhonePermission, reload: true);

  Future<void> editGoal() async {
    final updated = await showDialog<int>(
      context: context, builder: (_) => GoalDialog(initialBytes: goal),
    );
    if (updated == null || !mounted) return;
    await platformAction(() => usage.saveGoal(updated), reload: true);
  }

  void showSettings() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Weekly mobile limit'),
              onTap: () {
                Navigator.pop(sheetContext);
                editGoal();
              },
            ),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('Refresh usage'),
              onTap: () {
                Navigator.pop(sheetContext);
                load();
              },
            ),
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: const Text('Usage access settings'),
              onTap: () {
                Navigator.pop(sheetContext);
                platformAction(usage.openSettings);
              },
            ),
          ],
        ),
      ),
    );
  }

  void switchNetwork() => setState(() {
    network = mobile ? Network.wifi : Network.mobile;
  });

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !details,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && details) closeDetails();
    },
    child: Scaffold(
      appBar: AppBar(
        toolbarHeight: details ? 56 : 72,
        centerTitle: details,
        leading: details
            ? IconButton(tooltip: 'Back to overview', onPressed: closeDetails,
                icon: const Icon(Icons.arrow_downward))
            : null,
        title: details
            ? Text(networkName, style: const TextStyle(fontWeight: FontWeight.w800))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Data Usage Tracker', style: TextStyle(fontWeight: FontWeight.w800)),
                  if (hasAccess)
                    Text('$networkName usage', style: const TextStyle(fontSize: 13, color: muted)),
                ],
              ),
        actions: [
          if (hasAccess)
            IconButton(
              tooltip: details ? 'Switch network' : 'Settings',
              onPressed: details ? switchNetwork : showSettings,
              icon: Icon(details ? (mobile ? Icons.wifi : Icons.signal_cellular_alt) : Icons.settings),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 940),
            child: error != null
                ? notice(Icons.error_outline, error!, 'Retry', load)
                : !hasAccess && !busy
                ? notice(
                    Icons.lock_outline,
                    'Enable Usage access for Data Usage Tracker to see network usage.',
                    'Open Usage access settings',
                    () => platformAction(usage.openSettings),
                  )
                : busy
                ? const Center(child: CircularProgressIndicator())
                : details ? detailsView(context) : overview(context),
          ),
        ),
      ),
    ),
  );

  Widget notice(IconData icon, String text, String label, VoidCallback action) =>
      Center(child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: blue, size: 42),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton(onPressed: action, child: Text(label)),
          ],
        ),
      ));

  Widget mobileAccessNotice() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      children: [
        Text(
          needsPhonePermission
              ? 'Android 6–9 needs Phone permission to read mobile data usage.'
              : 'Android could not read mobile data for an active SIM.',
          style: const TextStyle(color: muted),
          textAlign: TextAlign.center,
        ),
        if (needsPhonePermission)
          TextButton(onPressed: requestPhonePermission, child: const Text('Allow mobile data access')),
      ],
    ),
  );

  List<int?> get series => periodData!.map((day) => day?.forNetwork(network)).toList();
  int? get periodTotal {
    final available = series.whereType<int>();
    return available.isEmpty ? null : available.fold<int>(0, (total, bytes) => total + bytes);
  }

  Widget overview(BuildContext context) {
    final bytes = dailyData![network]?.total;
    final weekTotal = periodTotal;
    final size = (MediaQuery.sizeOf(context).width * .55).clamp(158.0, 252.0).toDouble();
    return NotificationListener<OverscrollNotification>(
      onNotification: (event) {
        if (event.overscroll > 3 && event.dragDetails != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) openDetails();
          });
        }
        return false;
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  surface(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: openDetails,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 20, 14, 18),
                        child: Column(
                          children: [
                            SizedBox.square(
                              dimension: size,
                              child: CustomPaint(
                                painter: UsageRing(weekTotal ?? 0, mobile ? goal : 0),
                                child: Center(child: Padding(
                                  padding: EdgeInsets.all(size * .17),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(usageLabel(weekTotal), style: const TextStyle(
                                          fontSize: 33, fontWeight: FontWeight.w800, color: ink)),
                                      ),
                                      const FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text('Used this week', style: TextStyle(color: muted)),
                                      ),
                                    ],
                                  ),
                                )),
                              ),
                            ),
                            const SizedBox(height: 13),
                            const Text('Used today', style: TextStyle(color: muted)),
                            Text(usageLabel(bytes), style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w800, color: ink)),
                            if (bytes == null) mobileAccessNotice(),
                            if (mobile && goal > 0 && weekTotal != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  weekTotal > goal
                                      ? '${formatBytes(weekTotal - goal)} over weekly limit'
                                      : '${formatBytes(goal - weekTotal)} left this week',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: muted),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: switchNetwork,
                      child: Text(mobile ? 'Show Wi-Fi statistics' : 'Show mobile data statistics'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextButton.icon(
                  onPressed: openDetails,
                  icon: const Icon(Icons.keyboard_double_arrow_up),
                  label: const Text('Swipe up for details'),
                  style: TextButton.styleFrom(foregroundColor: ink),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget detailsView(BuildContext context) {
    final data = dailyData![network];
    final amounts = series;
    final total = periodTotal;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 5, 16, 24),
      itemCount: (data?.apps.length ?? 0) + 1,
      itemBuilder: (context, index) {
        if (index > 0) {
          final app = data!.apps[index - 1];
          return AppRow(
            key: ValueKey('${network.name}:${app.package}:${app.name}:$index'),
            app: app, color: colors[colors.length - 1 - ((index - 1) % colors.length)],
            total: math.max(data.total, data.apps.first.bytes),
            service: usage,
          );
        }
        final dates = MaterialLocalizations.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Used  ${usageLabel(total)} ${monthly ? 'this month' : 'this week'}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: muted),
            ),
            const SizedBox(height: 8),
            const UsageStripe(),
            const SizedBox(height: 16),
            surface(child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: Column(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(color: track, borderRadius: BorderRadius.circular(28)),
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: Row(
                        children: [
                          Expanded(child: periodButton('Weekly', !monthly)),
                          Expanded(child: periodButton('Monthly', monthly)),
                          IconButton(tooltip: 'Pick date', onPressed: chooseDate,
                            icon: const Icon(Icons.calendar_month_outlined)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      IconButton(
                        tooltip: monthly ? 'Previous month' : 'Previous week',
                        icon: const Icon(Icons.chevron_left),
                        onPressed: periodStart.isAfter(monthly
                            ? DateTime(earliest.year, earliest.month) : earliest)
                            ? () => movePeriod(-1) : null,
                      ),
                      Expanded(child: Column(
                        children: [
                          Text(dates.formatMediumDate(day), textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                          Text(usageLabel(data?.total), style: const TextStyle(color: muted)),
                        ],
                      )),
                      IconButton(
                        tooltip: monthly ? 'Next month' : 'Next week',
                        icon: const Icon(Icons.chevron_right),
                        onPressed: periodStart.isBefore(monthly
                            ? DateTime(today.year, today.month) : mondayOf(today))
                            ? () => movePeriod(1) : null,
                      ),
                    ],
                  ),
                  PeriodChart(
                    start: periodStart, day: day, amounts: amounts,
                    monthly: monthly, earliest: earliest, today: today, onDay: selectDay,
                  ),
                ],
              ),
            )),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                ActionChip(label: const Text('Today'), onPressed: () => selectDay(today)),
                ActionChip(label: const Text('Yesterday'),
                  onPressed: () => selectDay(calendarDay(today, -1))),
              ],
            ),
            const SizedBox(height: 10),
            Text('$networkName usage by app', style: Theme.of(context).textTheme.titleMedium),
            if (data == null)
              mobileAccessNotice()
            else if (data.apps.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('Android has no per-app records for this date and network.',
                  style: TextStyle(color: muted)),
              ),
          ],
        );
      },
    );
  }

  Widget periodButton(String label, bool selected) => Semantics(
    selected: selected,
    child: TextButton(
      style: TextButton.styleFrom(
        backgroundColor: selected ? panel : Colors.transparent,
        foregroundColor: selected ? ink : muted,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      ),
      onPressed: () {
        if (selected) return;
        setState(() => monthly = !monthly);
        load();
      },
      child: Text(label, textAlign: TextAlign.center),
    ),
  );
}

String usageLabel(int? bytes) => bytes == null ? 'Unavailable' : formatBytes(bytes);

Widget surface({required Widget child}) => Card(
  margin: EdgeInsets.zero,
  color: panel,
  surfaceTintColor: Colors.transparent,
  elevation: 1,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(22),
    side: const BorderSide(color: track),
  ),
  clipBehavior: Clip.antiAlias,
  child: child,
);

class UsageRing extends CustomPainter {
  UsageRing(this.bytes, this.goal);

  final int bytes;
  final int goal;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.shortestSide * .105;
    final circle = Offset.zero & size;
    final rect = circle.deflate(width / 2 + 2);
    final paint = Paint()..style = PaintingStyle.stroke
      ..strokeWidth = width..strokeCap = StrokeCap.round..color = track;
    canvas.drawOval(rect, paint);
    if (bytes <= 0) return;
    const start = -math.pi / 2 + .10;
    const length = 2 * math.pi - .34;
    final progress = goal > 0 ? math.min(bytes / goal, 1.0) : 1.0;
    final sweep = length * progress;
    for (var index = 0; index < colors.length; index++) {
      final offset = length * index / colors.length;
      if (offset >= sweep) break;
      paint.color = colors[colors.length - 1 - index];
      canvas.drawArc(rect, start + offset, math.min(length / colors.length, sweep - offset), false, paint);
    }
  }

  @override
  bool shouldRepaint(UsageRing oldDelegate) =>
      bytes != oldDelegate.bytes || goal != oldDelegate.goal;
}

class UsageStripe extends StatelessWidget {
  const UsageStripe({super.key});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(99),
    child: SizedBox(
      height: 20,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: blue),
          for (var index = 0; index < colors.length; index++)
            FractionallySizedBox(
              alignment: Alignment.centerRight,
              widthFactor: (colors.length - index) / colors.length,
              child: DecoratedBox(decoration: BoxDecoration(
                color: colors[index], borderRadius: BorderRadius.circular(99))),
            ),
        ],
      ),
    ),
  );
}

class PeriodChart extends StatefulWidget {
  const PeriodChart({
    super.key, required this.start, required this.day, required this.amounts,
    required this.monthly, required this.earliest, required this.today, required this.onDay,
  });

  final DateTime start;
  final DateTime day;
  final List<int?> amounts;
  final bool monthly;
  final DateTime earliest;
  final DateTime today;
  final ValueChanged<DateTime> onDay;

  @override
  State<PeriodChart> createState() => _PeriodChartState();
}

class _PeriodChartState extends State<PeriodChart> {
  final controller = ScrollController();
  static const dayWidth = 42.0;

  @override
  void initState() {
    super.initState();
    if (widget.monthly) WidgetsBinding.instance.addPostFrameCallback((_) => centerDay());
  }

  @override
  void didUpdateWidget(PeriodChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.monthly && (widget.day != oldWidget.day || !oldWidget.monthly)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => centerDay());
    }
  }

  void centerDay() {
    if (!mounted || !controller.hasClients) return;
    final position = controller.position;
    final offset = dayWidth * (widget.day.day - .5) - position.viewportDimension / 2;
    controller.jumpTo(offset.clamp(0.0, position.maxScrollExtent).toDouble());
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final peak = widget.amounts.whereType<int>().fold<int>(1, math.max);
    final dates = MaterialLocalizations.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final height = constraints.maxWidth >= 560 ? 158.0 : 117.0;
      final columns = List.generate(widget.amounts.length, (index) {
        final date = calendarDay(widget.start, index);
        final bytes = widget.amounts[index];
        final selected = date == widget.day;
        final enabled = !date.isAfter(widget.today) && !date.isBefore(widget.earliest);
        final barHeight = bytes == null || bytes == 0 ? 3.0 : math.max(4.0, (height - 22) * bytes / peak);
        final label = widget.monthly
            ? '${date.day}'
            : dates.narrowWeekdays[date.weekday % 7];
        final bar = Semantics(
          button: true, selected: selected, enabled: enabled,
          label: '${dates.formatFullDate(date)}, ${usageLabel(bytes)}',
          child: InkWell(
            key: ValueKey('chart-day-${date.toIso8601String()}'),
            onTap: enabled ? () => widget.onDay(date) : null,
            borderRadius: BorderRadius.circular(8),
            child: ExcludeSemantics(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: height,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: widget.monthly ? 17 : 30,
                        height: barHeight,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(5),
                          color: bytes == null || bytes == 0 ? track : null,
                          gradient: bytes != null && bytes > 0 ? LinearGradient(
                            begin: Alignment.topCenter, end: Alignment.bottomCenter,
                            colors: selected
                                ? const [Color(0xFF27B3DE), Color(0xFF4784F5)]
                                : const [Color(0xFFF02D91), Color(0xFFFF8066)],
                          ) : null,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(label, style: TextStyle(
                    fontSize: 12, color: selected ? blue : muted,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w400,
                  )),
                ],
              ),
            ),
          ),
        );
        return widget.monthly ? SizedBox(width: dayWidth, child: bar) : Expanded(child: bar);
      });
      return widget.monthly
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal, controller: controller,
              child: Row(children: columns))
          : Row(children: columns);
    });
  }
}

class AppRow extends StatefulWidget {
  const AppRow({
    super.key, required this.app, required this.color,
    required this.total, required this.service,
  });

  final AppUsage app;
  final Color color;
  final int total;
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ColoredBox(
              color: panel,
              child: SizedBox.square(
                dimension: 38,
                child: FutureBuilder<Uint8List?>(
                  future: icon,
                  builder: (_, snapshot) => snapshot.data == null
                      ? fallback
                      : Image.memory(snapshot.data!, errorBuilder: (_, _, _) => fallback),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(widget.app.name, style: const TextStyle(
                    color: ink, fontWeight: FontWeight.w700))),
                  const SizedBox(width: 8),
                  Flexible(child: Text(formatBytes(widget.app.bytes),
                    textAlign: TextAlign.end, style: const TextStyle(
                      color: ink, fontSize: 13, fontWeight: FontWeight.w600))),
                ],
              ),
              if (widget.app.package case final String name)
                Text(name, style: const TextStyle(fontSize: 11, color: muted)),
              const SizedBox(height: 7),
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: LinearProgressIndicator(
                  value: widget.app.bytes / widget.total,
                  minHeight: 4, color: widget.color, backgroundColor: track,
                ),
              ),
            ],
          )),
        ],
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
