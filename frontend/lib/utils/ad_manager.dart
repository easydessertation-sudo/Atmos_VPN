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
    if (Platform.isAndroid || Platform.isIOS) {
      return 'ca-app-pub-4377728206732134/3476657293';
    }
    throw UnsupportedError('Unsupported platform');
  }

  static String get interstitialAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/1033173712'
          : 'ca-app-pub-3940256099942544/4411468910'; // iOS test ID
    }
    if (Platform.isAndroid || Platform.isIOS) {
      return 'ca-app-pub-4377728206732134/8359342524';
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

  static void showAppOpenAdIfAvailable() {
    if (kIsWeb) return;
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
    if (_isInterstitialAdLoaded && _interstitialAd != null) {
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          _isInterstitialAdLoaded = false;
          _interstitialAd = null;
          loadInterstitialAd();
          if (onAdDismissed != null) onAdDismissed();
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          ad.dispose();
          _isInterstitialAdLoaded = false;
          _interstitialAd = null;
          loadInterstitialAd();
          if (onAdDismissed != null) onAdDismissed();
        },
      );
      _interstitialAd!.show();
    } else {
      if (onAdDismissed != null) onAdDismissed();
      loadInterstitialAd();
    }
  }
}
