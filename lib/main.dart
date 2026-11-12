import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException, SystemUiOverlayStyle;

import 'feature_language.dart';
import 'reports.dart';
import 'test_ads.dart';
import 'tracker_ui.dart';
import 'usage.dart';

void main() => runApp(TrackerApp(ads: AdMobTestAds()));

extension AppearanceLabel on ThemeMode {
  String displayLabel(BuildContext context) => switch (this) {
    ThemeMode.system => tr(context, 'Automatic', 'تلقائي'),
    ThemeMode.light => tr(context, 'Light', 'فاتح'),
    ThemeMode.dark => tr(context, 'Dark', 'داكن'),
  };
}

ThemeData trackerTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF007F77),
    brightness: brightness,
    surface: dark ? const Color(0xFF172424) : Colors.white,
    onSurface: dark ? const Color(0xFFE2F3EE) : const Color(0xFF152D2B),
    primary: dark ? const Color(0xFF74DFC8) : const Color(0xFF006C62),
    secondary: dark ? const Color(0xFFFFCD87) : const Color(0xFF8A500D),
  );
  final background = dark ? const Color(0xFF101919) : const Color(0xFFF1F7F5);
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: scheme.onSurface,
      scrolledUnderElevation: 0,
      systemOverlayStyle: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    ),
    useMaterial3: true,
  );
}

class TrackerApp extends StatefulWidget {
  const TrackerApp({super.key, this.ads});

  final TrackerAds? ads;

  @override
  State<TrackerApp> createState() => _TrackerAppState();
}

class _TrackerAppState extends State<TrackerApp> with WidgetsBindingObserver {
  final usage = UsageService();
  ThemeMode mode = ThemeMode.system;
  String language = 'en';
  int appearanceRevision = 0;
  Timer? startupDeadline;
  bool loadingScreen = false;
  bool dashboardReady = false;
  bool showingAd = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    restoreAppearance();
    restoreLanguage();
    final ads = widget.ads;
    if (ads != null) prepareLaunchAd(ads);
  }

  @override
  void dispose() {
    startupDeadline?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && !showingAd) closeLoadingScreen();
  }

  void closeLoadingScreen() {
    startupDeadline?.cancel();
    if (mounted && loadingScreen) setState(() => loadingScreen = false);
  }

  void finishDashboardStartup() {
    dashboardReady = true;
    if (!showingAd) closeLoadingScreen();
  }

  Future<void> prepareLaunchAd(TrackerAds ads) async {
    LaunchAd? ad;
    try {
      if (!await usage.returningLaunch() || !mounted || dashboardReady) return;
      setState(() => loadingScreen = true);
      startupDeadline = Timer(const Duration(seconds: 2), closeLoadingScreen);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !loadingScreen) return;
      ad = await ads.loadLaunchAd();
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (ad == null || !mounted || !loadingScreen || dashboardReady ||
          (lifecycle != null && lifecycle != AppLifecycleState.resumed)) return;
      startupDeadline?.cancel();
      showingAd = true;
      await ad.show();
    } catch (_) {
      // Ad failures should leave app startup available.
    } finally {
      ad?.dispose();
      showingAd = false;
      closeLoadingScreen();
    }
  }

  Future<void> restoreAppearance() async {
    final revision = appearanceRevision;
    try {
      final stored = await usage.appearance();
      if (!mounted || revision != appearanceRevision) return;
      setState(() => mode = switch (stored) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      });
    } on PlatformException {
      // The system theme remains the default if settings cannot be read.
    } on MissingPluginException {
      // The dashboard reports unsupported platforms separately.
    }
  }

  Future<void> changeAppearance(ThemeMode next) async {
    final revision = ++appearanceRevision;
    await usage.saveAppearance(next.name);
    if (mounted && revision == appearanceRevision) setState(() => mode = next);
  }

  Future<void> restoreLanguage() async {
    try {
      final saved = await usage.language();
      if (mounted && saved == 'ar') setState(() => language = 'ar');
    } on PlatformException {
      // English is the default if preferences are unavailable.
    } on MissingPluginException {
      // The dashboard reports unsupported platforms separately.
    }
  }

  Future<void> changeLanguage(String next) async {
    await usage.saveLanguage(next);
    if (mounted) setState(() => language = next);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Data Usage Tracker',
    theme: trackerTheme(Brightness.light),
    darkTheme: trackerTheme(Brightness.dark),
    themeMode: mode,
    locale: Locale(language),
    supportedLocales: const [Locale('en'), Locale('ar')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(
          excluding: loadingScreen,
          child: Dashboard(
            mode: mode,
            onAppearanceChanged: changeAppearance,
            onLanguageChanged: changeLanguage,
            onInitialLoadFinished: finishDashboardStartup,
            ads: loadingScreen ? null : widget.ads,
          ),
        ),
        if (loadingScreen)
          Scaffold(
            key: const ValueKey('launch-loading'),
            body: SafeArea(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const TrackerLogo(size: 56),
                    const SizedBox(height: 12),
                    Text(language == 'ar' ? 'بنحمّل الاستهلاك' : 'Loading usage'),
                    const SizedBox(height: 18),
                    const CircularProgressIndicator(),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class Dashboard extends StatefulWidget {
  const Dashboard({
    super.key,
    required this.mode,
    required this.onAppearanceChanged,
    required this.onLanguageChanged,
    required this.onInitialLoadFinished,
    this.ads,
  });

  final ThemeMode mode;
  final Future<void> Function(ThemeMode) onAppearanceChanged;
  final Future<void> Function(String) onLanguageChanged;
  final VoidCallback onInitialLoadFinished;
  final TrackerAds? ads;

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
  bool initialLoadFinished = false;
  bool needsPhonePermission = false;
  String? error;
  int goal = 0;
  int request = 0;
  Map<Network, NetworkUsage?>? dailyData;
  List<UsageTotals?>? periodData;
  DateTime? loadedPeriod;

  MonitorSettings monitor = const MonitorSettings();
  bool widgetInstalled = false;
  String filter = 'all';
  String query = '';
  String sort = 'usage';

  bool get mobile => network == Network.mobile;
  String get networkName => network == Network.both
      ? tr(context, 'All networks', 'كل الشبكات') : network.label(context);
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
      final openedNetwork = await usage.widgetNetwork();
      if (!mounted || ticket != request) return;
      if (openedNetwork != null) {
        setState(() {
          network = openedNetwork;
          details = false;
        });
      }
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
      final savedMonitor = await usage.settings();
      final hasWidget = await usage.widgetInstalled();
      if (!mounted || ticket != request) return;
      setState(() {
        hasAccess = true;
        needsPhonePermission = phonePermission;
        busy = false;
        dailyData = data;
        periodData = period;
        loadedPeriod = start;
        goal = savedGoal;
        monitor = savedMonitor;
        widgetInstalled = hasWidget;
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
    } finally {
      if (mounted && ticket == request && !initialLoadFinished) {
        initialLoadFinished = true;
        widget.onInitialLoadFinished();
      }
    }
  }

  void openDetails({bool yesterday = false}) {
    if (details || busy) return;
    setState(() {
      day = yesterday ? calendarDay(today, -1) : today;
      details = true;
      monthly = false;
    });
    if (yesterday) load(reusePeriod: true);
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

  Future<void> chooseAppearance() async {
    final next = await showDialog<ThemeMode>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(tr(context, 'Appearance', 'المظهر')),
        children: [
          for (final mode in ThemeMode.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, mode),
              child: Row(
                children: [
                  Icon(switch (mode) {
                    ThemeMode.system => Icons.brightness_auto_outlined,
                    ThemeMode.light => Icons.light_mode_outlined,
                    ThemeMode.dark => Icons.dark_mode_outlined,
                  }),
                  const SizedBox(width: 14),
                  Expanded(child: Text(mode.displayLabel(context))),
                  if (widget.mode == mode) const Icon(Icons.check, semanticLabel: 'Selected'),
                ],
              ),
            ),
        ],
      ),
    );
    if (next != null && next != widget.mode && mounted) {
      await platformAction(() => widget.onAppearanceChanged(next));
    }
  }

  Future<void> chooseLanguage() async {
    final next = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(tr(context, 'Language', 'اللغة')),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'en'), child: const Text('English')),
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'ar'), child: const Text('العربية')),
        ],
      ),
    );
    if (next != null && mounted) await platformAction(() => widget.onLanguageChanged(next));
  }

  Future<void> editPlan() async {
    var next = await showDialog<MonitorSettings>(
      context: context, builder: (_) => PlanEditor(settings: monitor),
    );
    if (next == null || !mounted) return;
    if ((next.thresholds || next.spikes) && !await usage.notificationPermission()) {
      next = MonitorSettings(limit: next.limit, renewal: next.renewal, pinned: next.pinned);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr(context, 'Notification permission is off.', 'إذن الإشعارات مقفول.')),
      ));
    }
    if (!mounted) return;
    final updated = next;
    await platformAction(() => saveMonitor(updated));
  }

  Future<void> saveMonitor(MonitorSettings settings) async {
    await usage.saveSettings(settings);
    if (mounted) setState(() => monitor = settings);
  }

  Future<void> addWidget() async {
    final selected = await showModalBottomSheet<Network>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Text(tr(context, 'Choose a home screen widget', 'اختار ويدجت للشاشة الرئيسية'),
                  style: Theme.of(context).textTheme.titleLarge),
              ),
              for (final network in [Network.wifi, Network.mobile, Network.both])
                ListTile(
                  leading: Icon(network.icon),
                  title: Text(network == Network.both
                    ? tr(context, 'Wi-Fi + mobile data', 'الواي فاي + داتا الموبايل')
                    : network.label(context)),
                  trailing: const Icon(Icons.add_to_home_screen),
                  onTap: () => Navigator.pop(sheetContext, network),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    var requested = false;
    try {
      requested = await usage.pinWidget(selected);
    } on PlatformException {
      // Some launchers only support adding widgets through their picker.
    }
    if (requested || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, 'Add the home screen widget', 'ضيف الويدجت للشاشة الرئيسية')),
        content: Text(tr(context,
          'Touch and hold an empty spot on your home screen, choose Widgets, then drag Data Usage Tracker onto the screen.',
          'اضغط مطوّل على مكان فاضي في الشاشة الرئيسية، اختار الأدوات (Widgets)، واسحب Data Usage Tracker للشاشة.')),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr(context, 'Done', 'تمام')))],
      ),
    );
  }

  void openReports() => Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => RangeReportPage(service: usage, network: network, today: today),
  ));

  void openApp(AppUsage app, DateTime date) => Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => AppHistoryPage(
      app: app, day: date, service: usage, pinned: monitor.pinned.contains(app.identity),
      onPin: () {
        final pins = {...monitor.pinned};
        if (!pins.remove(app.identity)) pins.add(app.identity);
        return saveMonitor(monitor.withPins(pins));
      },
    ),
  ));

  void showSettings() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: Text(tr(context, 'Appearance', 'المظهر')),
              subtitle: Text(widget.mode.displayLabel(context)),
              onTap: () {
                Navigator.pop(sheetContext);
                chooseAppearance();
              },
            ),
            ListTile(
              leading: const Icon(Icons.translate),
              title: Text(tr(context, 'Language', 'اللغة')),
              onTap: () {
                Navigator.pop(sheetContext);
                chooseLanguage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.widgets_outlined),
              title: Text(tr(context, 'Home screen widget', 'ويدجت الشاشة الرئيسية')),
              onTap: () {
                Navigator.pop(sheetContext);
                addWidget();
              },
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: Text(tr(context, 'Weekly mobile limit', 'الحد الأسبوعي للداتا')),
              onTap: () {
                Navigator.pop(sheetContext);
                editGoal();
              },
            ),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: Text(tr(context, 'Refresh usage', 'حدّث الاستهلاك')),
              onTap: () {
                Navigator.pop(sheetContext);
                load();
              },
            ),
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: Text(tr(context, 'Usage access settings', 'إعدادات إذن الاستخدام')),
              onTap: () {
                Navigator.pop(sheetContext);
                platformAction(usage.openSettings);
              },
            ),
          ],
        )),
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
            ? IconButton(tooltip: tr(context, 'Back to overview', 'ارجع للملخص'), onPressed: closeDetails,
                icon: const Icon(Icons.arrow_back))
            : null,
        title: details
            ? Text(networkName, style: const TextStyle(fontWeight: FontWeight.w800))
            : Row(children: [
                const TrackerLogo(),
                const SizedBox(width: 12),
                Flexible(child: Text('Data Usage Tracker', maxLines: 2,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
              ]),
        actions: [
          if (hasAccess || !details)
            IconButton(
              tooltip: details ? tr(context, 'Switch network', 'بدّل الشبكة') : tr(context, 'Settings', 'الإعدادات'),
              onPressed: details ? switchNetwork : showSettings,
              icon: Icon(details ? (mobile ? Icons.wifi : Icons.signal_cellular_alt) : Icons.settings),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (hasAccess && widget.ads != null)
              LayoutBuilder(builder: (context, constraints) =>
                constraints.maxWidth >= 320
                    ? widget.ads!.banner()
                    : const SizedBox.shrink(),
              ),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 940),
                  child: error != null
                      ? notice(Icons.error_outline, error!, tr(context, 'Retry', 'جرّب تاني'), load)
                      : !hasAccess && !busy
                      ? notice(
                          Icons.lock_outline,
                          tr(context, 'Enable Usage access for Data Usage Tracker to see network usage.', 'فعّل إذن الوصول للاستخدام لتطبيق Data Usage Tracker عشان تشوف استهلاك الشبكة.'),
                          tr(context, 'Open Usage access settings', 'افتح إعدادات إذن الاستخدام'),
                          () => platformAction(usage.openSettings),
                        )
                      : busy
                      ? const Center(child: CircularProgressIndicator())
                      : details ? detailsView(context) : overview(context),
                ),
              ),
            ),
          ],
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
            Icon(icon, color: Theme.of(context).colorScheme.primary, size: 42),
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
              ? tr(context, 'Android 7–9 needs Phone permission to read mobile data usage.',
                  'أندرويد ٧–٩ محتاج إذن الهاتف لقراءة استهلاك الداتا.')
              : tr(context, 'Android could not read mobile data for an active SIM.',
                  'أندرويد مقدرش يقرأ استهلاك الداتا لشريحة مفعّلة.'),
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        if (needsPhonePermission)
          TextButton(onPressed: requestPhonePermission, child: Text(tr(context, 'Allow mobile data access', 'اسمح بقراءة استهلاك الداتا'))),
      ],
    ),
  );

  List<int?> get series => periodData!.map((day) => day?.forNetwork(network)).toList();
  int? get periodTotal {
    final available = series.whereType<int>();
    return available.isEmpty ? null : available.fold<int>(0, (total, bytes) => total + bytes);
  }

  Widget overview(BuildContext context) {
    final data = dailyData!.forNetwork(network);
    final bytes = data?.total;
    final weekTotal = periodTotal;
    final scheme = Theme.of(context).colorScheme;
    final accent = mobile ? scheme.secondary : scheme.primary;
    return NotificationListener<OverscrollNotification>(
      onNotification: (event) {
        if (event.overscroll > 3 && event.dragDetails != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) openDetails();
          });
        }
        return false;
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(tr(context, 'Choose what to analyze', 'اختار عايز تحلّل إيه'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          NetworkChoices(selected: network, onChanged: (value) => setState(() => network = value)),
          const SizedBox(height: 14),
          surface(context, child: Padding(
            padding: const EdgeInsets.all(20),
            child: LayoutBuilder(builder: (context, constraints) {
              final compact = constraints.maxWidth < 250 ||
                  MediaQuery.textScalerOf(context).scale(16) > 22;
              final metric = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tr(context, 'Used this week', 'استهلاك الأسبوع'), style: TextStyle(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  Text(usageLabel(weekTotal), style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
                  if (mobile && goal > 0 && weekTotal != null)
                    Text(
                      weekTotal > goal
                          ? tr(context, '${formatBytes(weekTotal - goal)} over weekly limit',
                          '${formatBytes(weekTotal - goal)} زيادة عن الحد الأسبوعي')
                          : tr(context, '${formatBytes(goal - weekTotal)} left this week',
                              'المتبقي الأسبوع ده ${formatBytes(goal - weekTotal)}'),
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                ],
              );
              final hasLimit = mobile && goal > 0;
              final ring = Tooltip(
                message: hasLimit
                  ? tr(context, 'Weekly mobile limit used', 'المستهلك من الحد الأسبوعي')
                  : tr(context, "Today's share of this week's usage", 'نسبة النهارده من استهلاك الأسبوع'),
                child: SizedBox.square(
                  dimension: compact ? 86 : 104,
                  child: CustomPaint(
                    painter: UsageRing(
                      hasLimit ? weekTotal ?? 0 : bytes ?? 0,
                      hasLimit ? goal : weekTotal ?? 0,
                      accent,
                      scheme.surfaceContainerHighest,
                    ),
                    child: Icon(network.icon, color: accent, size: 32),
                  ),
                ),
              );
              return compact
                  ? Column(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [ring, const SizedBox(height: 12), metric])
                  : Row(children: [Expanded(child: metric), const SizedBox(width: 12), ring]);
            }),
          )),
          const SizedBox(height: 10),
          surface(context, child: ListTile(
            leading: Icon(Icons.today_outlined, color: accent),
            title: Text(tr(context, 'Used today', 'استهلاك النهارده')),
            subtitle: Text(usageLabel(bytes), style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700)),
          )),
          if (network == Network.both)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Wrap(spacing: 16, runSpacing: 4, children: [
                for (final option in [Network.wifi, Network.mobile])
                  Text('${option.label(context)} · ${usageLabel(dailyData![option]?.total)}'),
              ]),
            ),
          if (bytes == null) mobileAccessNotice(),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: openDetails,
            icon: const Icon(Icons.insights_outlined),
            label: Text(tr(context, 'View usage details', 'شوف تفاصيل الاستهلاك')),
          ),
          const SizedBox(height: 8),
          surface(context, child: ListTile(
            leading: const Icon(Icons.widgets_outlined),
            title: Text(tr(context, 'Home screen widget', 'ويدجت الشاشة الرئيسية')),
            subtitle: Text(widgetInstalled
              ? tr(context, 'Widget added to your home screen', 'الويدجت اتضاف للشاشة الرئيسية')
              : tr(context, 'Wi-Fi, mobile data, or both on your home screen', 'الواي فاي أو داتا الموبايل أو الاتنين على الشاشة الرئيسية')),
            trailing: IconButton(
              tooltip: tr(context, 'Add widget', 'ضيف الويدجت'),
              onPressed: addWidget,
              icon: const Icon(Icons.add_to_home_screen),
            ),
            onTap: addWidget,
          )),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => openDetails(yesterday: true),
              icon: const Icon(Icons.history),
              label: Text(tr(context, 'Analyze yesterday', 'حلّل استهلاك امبارح')),
            ),
          ),
          PlanSummary(settings: monitor, service: usage, today: today, revision: request, onEdit: editPlan),
          OutlinedButton.icon(
            onPressed: openReports,
            icon: const Icon(Icons.analytics_outlined),
            label: Text(tr(context, 'Compare, filter by date or export', 'قارن الفترات أو اختار تاريخ أو صدّر تقرير')),
          ),
          if (data != null && data.apps.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(tr(context, 'Where did the data go?', 'الداتا راحت فين؟'),
              style: Theme.of(context).textTheme.titleMedium),
            for (final app in data.apps.take(3))
              ListTile(
                dense: true,
                title: Text(displayAppName(context, app.name)),
                trailing: Text('${formatBytes(app.bytes)} · ${data.total <= 0 ? '—' :
                    '${(app.bytes * 100 / data.total).toStringAsFixed(1)}%'}'),
                onTap: () => openApp(app, today),
              ),
          ],
          if (monitor.pinned.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(tr(context, 'Pinned apps', 'التطبيقات المثبّتة'),
              style: Theme.of(context).textTheme.titleMedium),
            for (final pin in monitor.pinned)
              pinnedTile(context, pin, data),
          ],
        ],
      ),
    );
  }

  Widget pinnedTile(BuildContext context, String pin, NetworkUsage? data) {
    final todayApp = data?.apps.where((app) => app.identity == pin).firstOrNull;
    final recentApp = todayApp ?? dailyData!.values
        .expand((value) => value?.apps ?? <AppUsage>[])
        .where((app) => app.identity == pin).firstOrNull;
    return ListTile(
      dense: true,
      leading: const Icon(Icons.push_pin_outlined),
      title: Text(recentApp?.name ?? pin),
      subtitle: recentApp?.package == null ? null : Text(recentApp!.package!),
      trailing: Text(data == null ? '—' : formatBytes(todayApp?.bytes ?? 0)),
      onTap: recentApp == null ? null : () => openApp(recentApp, today),
      onLongPress: () => platformAction(() =>
        saveMonitor(monitor.withPins({...monitor.pinned}..remove(pin)))),
    );
  }

  Widget detailsView(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = mobile ? scheme.secondary : scheme.primary;
    final data = dailyData!.forNetwork(network);
    final amounts = series;
    final total = periodTotal;
    final needle = query.trim().toLowerCase();
    final apps = (data?.apps ?? <AppUsage>[]).where((app) =>
        (filter == 'all' || (filter == 'system' && app.system == true) ||
          (filter == 'user' && app.system == false)) &&
        (app.name.toLowerCase().contains(needle) ||
          (app.package?.toLowerCase().contains(needle) ?? false))).toList();
    if (sort == 'name') apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (sort == 'low') apps.sort((a, b) => a.bytes.compareTo(b.bytes));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 5, 16, 24),
      itemCount: apps.length + 1,
      itemBuilder: (context, index) {
        if (index > 0) {
          final app = apps[index - 1];
          return InkWell(
            onTap: () => openApp(app, day),
            child: AppRow(
            key: ValueKey('${network.name}:${app.package}:${app.name}:$index'),
            app: app, color: accent,
            total: math.max(data!.total, data.apps.first.bytes),
            service: usage,
          ));
        }
        final dates = MaterialLocalizations.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            surface(context, child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Text('${usageLabel(total)} · ${monthly ? tr(context, 'Monthly total', 'إجمالي الشهر') : tr(context, 'Weekly total', 'إجمالي الأسبوع')}',
                      style: TextStyle(fontWeight: FontWeight.w700, color: accent)),
                  ),
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      periodButton(tr(context, 'Weekly', 'أسبوعي'), !monthly),
                      periodButton(tr(context, 'Monthly', 'شهري'), monthly),
                      IconButton(tooltip: tr(context, 'Pick date', 'اختار تاريخ'), onPressed: chooseDate,
                        icon: const Icon(Icons.calendar_month_outlined)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      IconButton(
                        tooltip: monthly ? tr(context, 'Previous month', 'الشهر السابق') : tr(context, 'Previous week', 'الأسبوع السابق'),
                        icon: const Icon(Icons.chevron_left),
                        onPressed: periodStart.isAfter(monthly
                            ? DateTime(earliest.year, earliest.month) : earliest)
                            ? () => movePeriod(-1) : null,
                      ),
                      Expanded(child: Column(
                        children: [
                          Text(dates.formatMediumDate(day), textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                          Text(usageLabel(data?.total), style: TextStyle(color: scheme.onSurfaceVariant)),
                        ],
                      )),
                      IconButton(
                        tooltip: monthly ? tr(context, 'Next month', 'الشهر التالي') : tr(context, 'Next week', 'الأسبوع التالي'),
                        icon: const Icon(Icons.chevron_right),
                        onPressed: periodStart.isBefore(monthly
                            ? DateTime(today.year, today.month) : mondayOf(today))
                            ? () => movePeriod(1) : null,
                      ),
                    ],
                  ),
                  PeriodChart(
                    start: periodStart, day: day, amounts: amounts,
                    monthly: monthly, earliest: earliest, today: today, onDay: selectDay, accent: accent,
                  ),
                ],
              ),
            )),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                ActionChip(label: Text(tr(context, 'Today', 'النهارده')), onPressed: () => selectDay(today)),
                ActionChip(label: Text(tr(context, 'Yesterday', 'امبارح')),
                  onPressed: () => selectDay(calendarDay(today, -1))),
              ],
            ),
            const SizedBox(height: 10),
            Text(tr(context, '$networkName usage by app', 'استهلاك التطبيقات · $networkName'),
              style: Theme.of(context).textTheme.titleMedium),
            if (data != null && data.apps.isNotEmpty) ...[
              const SizedBox(height: 8),
              TextFormField(
                initialValue: query,
                onChanged: (value) => setState(() => query = value),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: tr(context, 'Search apps or packages', 'ابحث عن اسم تطبيق أو حزمة'),
                ),
              ),
              Wrap(spacing: 8, children: [
                DropdownButton<String>(
                  value: filter, onChanged: (value) => setState(() => filter = value ?? 'all'),
                  items: [
                    DropdownMenuItem(value: 'all', child: Text(tr(context, 'All apps', 'كل التطبيقات'))),
                    DropdownMenuItem(value: 'user', child: Text(tr(context, 'Installed apps', 'تطبيقات المستخدم'))),
                    DropdownMenuItem(value: 'system', child: Text(tr(context, 'System apps', 'تطبيقات النظام'))),
                  ],
                ),
                DropdownButton<String>(
                  value: sort, onChanged: (value) => setState(() => sort = value ?? 'usage'),
                  items: [
                    DropdownMenuItem(value: 'usage', child: Text(tr(context, 'Most used', 'الأعلى استهلاكًا'))),
                    DropdownMenuItem(value: 'low', child: Text(tr(context, 'Least used', 'الأقل استهلاكًا'))),
                    DropdownMenuItem(value: 'name', child: Text(tr(context, 'Name', 'الاسم'))),
                  ],
                ),
              ]),
              if (apps.isEmpty) Text(tr(context, 'No matching apps', 'مفيش تطبيقات مطابقة')),
            ],
            if (data == null)
              mobileAccessNotice()
            else if (data.apps.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(tr(context, 'Android has no per-app records for this date and network.', 'أندرويد معندوش سجلات للتطبيقات على الشبكة دي في التاريخ ده.'),
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              ),
          ],
        );
      },
    );
  }

  Widget periodButton(String label, bool selected) => ChoiceChip(
    label: Text(label),
    selected: selected,
    onSelected: (_) {
      if (selected) return;
      setState(() => monthly = !monthly);
      load();
    },
  );
}

String usageLabel(int? bytes) => bytes == null ? 'Unavailable' : formatBytes(bytes);

Widget surface(BuildContext context, {required Widget child}) {
  final scheme = Theme.of(context).colorScheme;
  return Card(
    margin: EdgeInsets.zero,
    color: scheme.surface,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: scheme.outlineVariant),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

class UsageRing extends CustomPainter {
  UsageRing(this.bytes, this.goal, this.accent, this.track);

  final int bytes;
  final int goal;
  final Color accent;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 8.0;
    final rect = (Offset.zero & size).deflate(stroke / 2 + 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    const start = math.pi * .75;
    const length = math.pi * 1.5;
    canvas.drawArc(rect, start, length, false, paint);
    if (bytes <= 0 || goal <= 0) return;
    paint.color = accent;
    final progress = math.min(bytes / goal, 1.0);
    canvas.drawArc(rect, start, length * progress, false, paint);
  }

  @override
  bool shouldRepaint(UsageRing oldDelegate) =>
      bytes != oldDelegate.bytes || goal != oldDelegate.goal ||
      accent != oldDelegate.accent || track != oldDelegate.track;
}

class PeriodChart extends StatefulWidget {
  const PeriodChart({
    super.key, required this.start, required this.day, required this.amounts,
    required this.monthly, required this.earliest, required this.today, required this.onDay,
    required this.accent,
  });

  final DateTime start;
  final DateTime day;
  final List<int?> amounts;
  final bool monthly;
  final DateTime earliest;
  final DateTime today;
  final ValueChanged<DateTime> onDay;
  final Color accent;

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
    final scheme = Theme.of(context).colorScheme;
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
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                          color: bytes == null || bytes == 0
                              ? scheme.surfaceContainerHighest
                              : selected ? widget.accent : widget.accent.withValues(alpha: .42),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(label, style: TextStyle(
                    fontSize: 12, color: selected ? widget.accent : scheme.onSurfaceVariant,
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
    title: Text(tr(context, 'Weekly mobile limit', 'الحد الأسبوعي للداتا')),
    content: TextField(
      controller: controller,
      autofocus: true,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: tr(context, 'Limit (GB)', 'الحد (جيجابايت)'), errorText: error),
    ),
    actions: [
      if (widget.initialBytes > 0)
        TextButton(onPressed: () => Navigator.pop(context, 0), child: Text(tr(context, 'Remove', 'إزالة'))),
      TextButton(onPressed: () => Navigator.pop(context), child: Text(tr(context, 'Cancel', 'إلغاء'))),
      FilledButton(
        onPressed: () {
          final gb = double.tryParse(controller.text.trim().replaceAll(',', '.'));
          if (gb == null || !gb.isFinite || gb < 0.001 || gb > 100000) {
            setState(() => error = tr(context, 'Enter 0.001–100000 GB.', 'اكتب قيمة من ٠٫٠٠١ لـ١٠٠٠٠٠ جيجابايت.'));
            return;
          }
          Navigator.pop(context, (gb * 1000000000).round());
        },
        child: Text(tr(context, 'Save', 'حفظ')),
      ),
    ],
  );
}
