import 'dart:io';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter/foundation.dart';

class AdManager {
  static const String appId = 'ca-app-pub-4377728206732134~7527582947';
  
  static String get appOpenAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/9257395921'
          : 'ca-app-pub-3940256099942544/5533782606'; // iOS test ID
    }
    if (Platform.isAndroid) {
      return 'ca-app-pub-4377728206732134/3476657293';
    }
    if (Platform.isIOS) {
      return 'ca-app-pub-4377728206732134/9111893241';
    }
    throw UnsupportedError('Unsupported platform');
  }

  static String get bannerAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/6300978111'
          : 'ca-app-pub-3940256099942544/2934735716'; // iOS test ID
    }
    if (Platform.isAndroid) {
      return 'ca-app-pub-4377728206732134/1518602976';
    }
    if (Platform.isIOS) {
      return 'ca-app-pub-4377728206732134/6501584925';
    }
    throw UnsupportedError('Unsupported platform');
  }

  static String get interstitialAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/1033173712'
          : 'ca-app-pub-3940256099942544/4411468910'; // iOS test ID
    }
    if (Platform.isAndroid) {
      return 'ca-app-pub-4377728206732134/8359342524';
    }
    if (Platform.isIOS) {
      return 'ca-app-pub-4377728206732134/1233403224';
    }
    throw UnsupportedError('Unsupported platform');
  }

  static AppOpenAd? _appOpenAd;
  static bool _isShowingAppOpenAd = false;
  static InterstitialAd? _interstitialAd;
  static bool _isInterstitialAdLoaded = false;

  static void loadAppOpenAd() {
    if (kIsWeb) return;
    AppOpenAd.load(
      adUnitId: appOpenAdUnitId,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _appOpenAd = ad;
        },
        onAdFailedToLoad: (error) {},
      ),
    );
  }

  static DateTime? _lastInterstitialDismissedAt;

  static void showAppOpenAdIfAvailable() {
    if (kIsWeb) return;
    if (_lastInterstitialDismissedAt != null && 
        DateTime.now().difference(_lastInterstitialDismissedAt!).inSeconds < 5) {
      return;
    }
    if (_appOpenAd == null) {
      loadAppOpenAd();
      return;
    }
    if (_isShowingAppOpenAd) return;

    _appOpenAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        _isShowingAppOpenAd = true;
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        _isShowingAppOpenAd = false;
        ad.dispose();
        _appOpenAd = null;
        loadAppOpenAd();
      },
      onAdDismissedFullScreenContent: (ad) {
        _isShowingAppOpenAd = false;
        ad.dispose();
        _appOpenAd = null;
        loadAppOpenAd();
      },
    );
    _appOpenAd!.show();
  }

  static void loadInterstitialAd() {
    if (kIsWeb) return;
    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isInterstitialAdLoaded = true;
        },
        onAdFailedToLoad: (error) {},
      ),
    );
  }

  static void showInterstitialAd({Function? onAdDismissed}) {
    if (kIsWeb) {
      if (onAdDismissed != null) onAdDismissed();
      return;
    }

    void _doShow() {
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          _lastInterstitialDismissedAt = DateTime.now();
          ad.dispose();
          _isInterstitialAdLoaded = false;
          _interstitialAd = null;
          loadInterstitialAd();
          if (onAdDismissed != null) onAdDismissed();
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          _lastInterstitialDismissedAt = DateTime.now();
          ad.dispose();
          _isInterstitialAdLoaded = false;
          _interstitialAd = null;
          loadInterstitialAd();
          if (onAdDismissed != null) onAdDismissed();
        },
      );
      _interstitialAd!.show();
    }

    if (_isInterstitialAdLoaded && _interstitialAd != null) {
      // Ad is ready — show immediately
      _doShow();
    } else {
      // Ad is not ready yet (still loading from previous reload).
      // Poll every 250ms for up to 3 seconds, then give up.
      int attempts = 0;
      const maxAttempts = 12; // 12 × 250ms = 3 seconds

      Future<void> _poll() async {
        if (_isInterstitialAdLoaded && _interstitialAd != null) {
          _doShow();
          return;
        }
        if (attempts >= maxAttempts) {
          // Timed out — proceed without showing an ad
          loadInterstitialAd();
          if (onAdDismissed != null) onAdDismissed();
          return;
        }
        attempts++;
        await Future.delayed(const Duration(milliseconds: 250));
        _poll();
      }

      _poll();
    }
  }
}
