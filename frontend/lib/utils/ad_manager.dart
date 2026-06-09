import 'dart:io';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter/material.dart';
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
  static bool _isShowingInterstitialAd = false;

  static void showAppOpenAdIfAvailable() {
    if (kIsWeb) return;
    if (_isShowingInterstitialAd) return;
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

  static bool _isInterstitialAdLoading = false;

  static void loadInterstitialAd() {
    if (kIsWeb) return;
    if (_isInterstitialAdLoading) return;
    
    _isInterstitialAdLoading = true;
    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isInterstitialAdLoaded = true;
          _isInterstitialAdLoading = false;
        },
        onAdFailedToLoad: (error) {
          _isInterstitialAdLoaded = false;
          _isInterstitialAdLoading = false;
          // Retry loading after a delay if it fails
          Future.delayed(const Duration(seconds: 15), () {
            loadInterstitialAd();
          });
        },
      ),
    );
  }

  static void showInterstitialAd({BuildContext? context, Function? onAdDismissed, bool continueIfNoAd = false}) {
    if (kIsWeb) {
      if (onAdDismissed != null) onAdDismissed();
      return;
    }

    void _doShow() {
      _isShowingInterstitialAd = true;
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          _isShowingInterstitialAd = false;
          _lastInterstitialDismissedAt = DateTime.now();
          ad.dispose();
          _isInterstitialAdLoaded = false;
          _interstitialAd = null;
          loadInterstitialAd();
          if (onAdDismissed != null) onAdDismissed();
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          _isShowingInterstitialAd = false;
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
      // Ad is not ready yet. 
      // If it's not even loading, trigger a load now!
      if (!_isInterstitialAdLoading) {
        loadInterstitialAd();
      }

      bool dialogShown = false;
      if (context != null && context.mounted) {
        dialogShown = true;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => const Center(child: CircularProgressIndicator(color: Colors.blue)),
        );
      }

      // Poll every 250ms for up to 10 seconds, then give up.
      int attempts = 0;
      const maxAttempts = 40; // 40 x 250ms = 10 seconds

      Future<void> _poll() async {
        if (_isInterstitialAdLoaded && _interstitialAd != null) {
          if (dialogShown && context != null && context.mounted) Navigator.pop(context);
          _doShow();
          return;
        }
        if (attempts >= maxAttempts) {
          if (dialogShown && context != null && context.mounted) Navigator.pop(context);
          // Timed out — no ad available
          if (continueIfNoAd) {
             // Let the user proceed with the feature anyway!
             if (onAdDismissed != null) onAdDismissed();
          } else {
             if (context != null && context.mounted) {
               ScaffoldMessenger.of(context).showSnackBar(
                 const SnackBar(
                   content: Text('No ads available right now, try again later.'),
                   behavior: SnackBarBehavior.floating,
                   backgroundColor: Colors.redAccent,
                   duration: Duration(seconds: 3),
                 ),
               );
             }
          }
          loadInterstitialAd();
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
