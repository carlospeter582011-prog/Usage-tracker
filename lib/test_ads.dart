import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

abstract interface class LaunchAd {
  Future<void> show();
  void dispose();
}

abstract interface class TrackerAds {
  Future<LaunchAd?> loadLaunchAd();
  Widget banner();
}

class AdMobTestAds implements TrackerAds {
  static const appOpenId = 'ca-app-pub-3940256099942544/9257395921';
  static const bannerId = 'ca-app-pub-3940256099942544/6300978111';
  static const request = AdRequest(nonPersonalizedAds: true);

  late final Future<InitializationStatus> initialized =
      MobileAds.instance.initialize();

  @override
  Future<LaunchAd?> loadLaunchAd() async {
    await initialized;
    final loaded = Completer<LaunchAd?>();
    await AppOpenAd.load(
      adUnitId: appOpenId,
      request: request,
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) => loaded.complete(_AdMobLaunchAd(ad)),
        onAdFailedToLoad: (_) => loaded.complete(null),
      ),
    );
    return loaded.future;
  }

  @override
  Widget banner() => _TopBanner(ads: this);
}

class _AdMobLaunchAd implements LaunchAd {
  _AdMobLaunchAd(this.ad);

  final AppOpenAd ad;

  @override
  Future<void> show() async {
    final finished = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback<AppOpenAd>(
      onAdDismissedFullScreenContent: (_) => finished.complete(),
      onAdFailedToShowFullScreenContent: (_, _) => finished.complete(),
    );
    await ad.show();
    await finished.future;
  }

  @override
  void dispose() => unawaited(ad.dispose());
}

class _TopBanner extends StatefulWidget {
  const _TopBanner({required this.ads});

  final AdMobTestAds ads;

  @override
  State<_TopBanner> createState() => _TopBannerState();
}

class _TopBannerState extends State<_TopBanner> {
  BannerAd? banner;
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    loadBanner();
  }

  Future<void> loadBanner() async {
    try {
      await widget.ads.initialized;
      if (!mounted) return;
      final next = BannerAd(
        adUnitId: AdMobTestAds.bannerId,
        request: AdMobTestAds.request,
        size: AdSize.banner,
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            if (mounted && identical(ad, banner)) setState(() => loaded = true);
          },
          onAdFailedToLoad: (ad, _) => discard(ad),
        ),
      );
      banner = next;
      await next.load();
    } catch (_) {
      final current = banner;
      if (current != null) discard(current);
    }
  }

  void discard(Ad ad) {
    if (!identical(ad, banner)) return;
    banner = null;
    unawaited(ad.dispose());
    if (mounted && loaded) setState(() => loaded = false);
  }

  @override
  void dispose() {
    final current = banner;
    banner = null;
    if (current != null) unawaited(current.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = banner;
    if (!loaded || current == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Center(
        heightFactor: 1,
        child: SizedBox(
          width: current.size.width.toDouble(),
          height: current.size.height.toDouble(),
          child: AdWidget(ad: current),
        ),
      ),
    );
  }
}
