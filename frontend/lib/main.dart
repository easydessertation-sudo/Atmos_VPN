import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:app_links/app_links.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'services/vpn_service.dart';
import 'package:upgrader/upgrader.dart';
import 'package:flutter/services.dart';
import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:in_app_review/in_app_review.dart';
import 'utils/design_system.dart';
import 'utils/api_service.dart';
import 'utils/ad_manager.dart';
import 'services/notification_service.dart';
import 'screens/web/web_landing_page.dart';
import 'screens/web/content_pages.dart';
import 'screens/web/more_pages.dart';
import 'screens/web/footer_content.dart';
import 'screens/server_list.dart';
import 'screens/map_view_screen.dart';
import 'screens/mode_selection.dart';
import 'screens/security_center.dart';
import 'screens/speed_test.dart';
import 'screens/account_screen.dart';
import 'screens/support_screen.dart';
import 'screens/pricing_screen.dart';
import 'screens/app_pricing_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/email_verification_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/trial_offer_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/device_management_screen.dart';
import 'screens/billing_screen.dart';
import 'screens/notification_screen.dart';
import 'screens/privacy_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// The native AtmosVpnFirebaseService.kt handles ALL FCM messages natively.
// This Dart handler is kept as a no-op so Firebase plugin doesn't complain,
// but the native service shows the actual notification (works even when killed).
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // No-op: handled natively in AtmosVpnFirebaseService.kt
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    await Firebase.initializeApp();
    // CRITICAL: Must be registered here in main() — before runApp() —
    // so Android can spin up the background isolate when the app is killed.
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    await MobileAds.instance.initialize();
    AdManager.loadAppOpenAd();
    AdManager.loadInterstitialAd();
    await NotificationService.init();
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => VPNProvider(),
          lazy: false, // Eagerly load all data (servers, profile) in the background during the splash screen/app open ad
        ),
      ],
      child: const AtmosVPNApp(),
    ),
  );
}

class AtmosVPNApp extends StatefulWidget {
  const AtmosVPNApp({super.key});

  @override
  State<AtmosVPNApp> createState() => _AtmosVPNAppState();
}

class _AtmosVPNAppState extends State<AtmosVPNApp> with WidgetsBindingObserver {
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();

    // Handle incoming links while the app is running in background
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (Uri? uri) {
        if (uri != null) {
          _handleDeepLink(uri);
        }
      },
      onError: (err) {
        debugPrint('Failsafe: Ignored invalid deep link error: $err');
      },
    );

    // Handle initial link if the app was completely closed
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleDeepLink(initialUri);
      }
    } catch (e) {
      // Ignore
    }
  }

  void _handleDeepLink(Uri uri) {
    if (uri.scheme == 'atmosvpn' && (uri.path.contains('/payment/success') || uri.path.contains('/payment-success'))) {
      final context = navigatorKey.currentContext;
      if (context != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment Successful! Premium Unlocked.',
                style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
        // Refresh profile to get the new plan status
        context.read<VPNProvider>().fetchProfile();
        // Redirect back to dashboard
        Navigator.pushNamedAndRemoveUntil(
            context, '/dashboard', (route) => false);
      }
    }
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Only show the app open ad for free users who are actually logged in
      final vpn = navigatorKey.currentContext?.read<VPNProvider>();
      if (vpn != null && vpn.isFreeUser && vpn.userData != null) {
        AdManager.showAppOpenAdIfAvailable();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Atmos VPN',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppDesign.darkTheme,
      initialRoute: '/',
      routes: {
        '/': (context) => kIsWeb ? const WebLandingPage() : const SplashScreen(),
        '/splash': (context) => const SplashScreen(),
        '/trial': (context) => const TrialOfferScreen(),
        // ── Web Marketing ──────────────────────────────────────────
        '/features': (context) => const FeaturesPage(),
        '/how-vpn-works': (context) => const HowVpnWorksPage(),
        '/why': (context) => const HowVpnWorksPage(),
        '/servers': (context) => const ServersPage(),
        '/blog': (context) => const BlogPage(),
        '/about': (context) => const AboutPage(),
        '/contact': (context) => const ContactPage(),
        '/careers': (context) => const CareersPage(),
        // Use cases
        '/use-cases/streaming': (context) =>
            const FooterContentPage(data: FooterContentCatalog.streaming),
        '/use-cases/gaming': (context) =>
            const FooterContentPage(data: FooterContentCatalog.gaming),
        '/use-cases/crypto': (context) =>
            const FooterContentPage(data: FooterContentCatalog.crypto),
        '/use-cases/torrenting': (context) =>
            const FooterContentPage(data: FooterContentCatalog.torrenting),
        '/use-cases/privacy': (context) =>
            const FooterContentPage(data: FooterContentCatalog.privacy),
        // Legal
        '/privacy': (context) => const PrivacyScreen(),
        '/privacy-policy': (context) => const PrivacyPolicyPage(),
        '/terms': (context) => const TermsPage(),
        '/no-logs-audit': (context) =>
            const FooterContentPage(data: FooterContentCatalog.noLogsAudit),
        '/cookie-policy': (context) => const CookiePolicyPage(),
        '/gdpr': (context) =>
            const FooterContentPage(data: FooterContentCatalog.gdpr),
        // Download / Pricing
        '/download': (context) => const _PlaceholderPage('Download App'),
        '/pricing': (context) => const PricingScreen(),
        // ── Auth ───────────────────────────────────────────────────
        '/onboarding': (context) => const OnboardingScreen(),
        '/login': (context) => _UpgradeWrapper(child: const LoginScreen()),
        '/signup': (context) => const SignupScreen(),
        '/verify-email': (context) => const EmailVerificationScreen(),
        // ── App (post-login, responsive) ───────────────────────────
        '/home': (context) => _UpgradeWrapper(child: const DashboardScreen()),
        '/dashboard': (context) => _UpgradeWrapper(child: const DashboardScreen()),
        '/server-list': (context) => const ServerListScreen(),
        '/map': (context) => const MapViewScreen(),
        '/modes': (context) => const ModeSelectionScreen(),
        '/security': (context) => const SecurityCenterScreen(),
        '/speed': (context) => const SpeedTestScreen(),
        '/account': (context) => const AccountScreen(),
        '/account/pricing': (context) => const AppPricingScreen(),
        '/account/devices': (context) => const DeviceManagementScreen(),
        '/account/billing': (context) => const BillingScreen(),
        '/notifications': (context) => const NotificationScreen(),
        '/support': (context) => const SupportScreen(),
        // Learn / Company footer content
        '/learn/how-vpn-works': (context) =>
            const FooterContentPage(data: FooterContentCatalog.howVpnWorks),
        '/learn/why-vpn': (context) =>
            const FooterContentPage(data: FooterContentCatalog.whyVpn),
        '/learn/vpn-guide-2024': (context) =>
            const FooterContentPage(data: FooterContentCatalog.vpnGuide),
        // '/blog': (context) => const FooterContentPage(data: FooterContentCatalog.blog),
        '/company/press': (context) =>
            const FooterContentPage(data: FooterContentCatalog.press),
        '/company/affiliates': (context) =>
            const FooterContentPage(data: FooterContentCatalog.affiliates),
      },
    );
  }
}

class _UpgraderMessages extends UpgraderMessages {
  @override
  String get buttonTitleIgnore => 'Cancel';
}

class _UpgradeWrapper extends StatelessWidget {
  final Widget child;
  const _UpgradeWrapper({required this.child});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return child;
    return UpgradeAlert(
      upgrader: Upgrader(
        messages: _UpgraderMessages(),
        durationUntilAlertAgain: const Duration(seconds: 0), // Force it to show again even if route replaces
      ),
      showIgnore: true,         // We changed 'Ignore' to 'Cancel' via _UpgraderMessages
      showLater: false,         // Hide 'Later' button
      showReleaseNotes: false,  // Hide the "What's new" release notes section
      onIgnore: () {
        SystemNavigator.pop();  // Exit the app if they cancel
        return false;           // Return false so the dialog doesn't just dismiss normally
      },
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Placeholder for pages being built
// ─────────────────────────────────────────────────────────────────
class _PlaceholderPage extends StatelessWidget {
  final String title;
  const _PlaceholderPage(this.title);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.black54,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(title,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800)),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.construction_rounded,
                color: AppColors.primaryBlue, size: 64),
            const SizedBox(height: 24),
            Text(title,
                style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Colors.white)),
            const SizedBox(height: 12),
            const Text('This page is coming soon.',
                style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// VPN State Provider
// ─────────────────────────────────────────────────────────────────

class VPNProvider with ChangeNotifier {
  bool _isConnected = false;
  String _status = 'Disconnected';
  String _currentServer = 'None';
  bool _isFreeUser = true;
  bool _hasUpgraded = false;
  Map<String, dynamic>? _userData;
  Map<String, dynamic>? _selectedServer;
  List<dynamic> _servers = [];
  String? _lastError;
  String? _realIp;
  int _remainingSeconds = 0; // Safe default — real value loaded from backend in _syncSessionTime()
  bool _isSessionTimeLoaded = false; // False until first backend sync completes
  Timer? _sessionTimer;
  Timer? _notifTimer;
  int _unreadCount = 0;
  List<dynamic> _cachedNotifications = [];
  final Set<String> _notifiedIds = {};
  Timer? _vpnStatusPoller;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Map<String, bool> _securityFeatures = {
    'kill_switch_enabled': false,
    'dns_leak_protection': true,
    'ad_blocker_enabled': false,
    'tracker_blocker_enabled': false,
    'malware_protection': true,
    'auto_connect_wifi': false,
  };
  bool _isFetchingSecurity = false;
  bool _triggerSessionExpired = false;
  int _starterAdsWatched = 0;

  bool get isConnected => _isConnected;
  String get status => _status;
  String get currentServer => _currentServer;
  String? get realIp => _realIp;
  bool get isFreeUser => _isFreeUser;
  int get remainingSeconds => _remainingSeconds;
  int get remainingMinutes => _remainingSeconds ~/ 60;
  bool get hasUpgraded => _hasUpgraded;
  bool get isSessionTimeLoaded => _isSessionTimeLoaded;
  int get unreadCount => _unreadCount;
  List<dynamic> get cachedNotifications => _cachedNotifications;
  int get starterAdsWatched => _starterAdsWatched;
  void optimisticallyIncrementStarterAds() {
    _starterAdsWatched++;
    notifyListeners();
  }
  Map<String, dynamic>? get userData => _userData;
  Map<String, dynamic>? get selectedServer => _selectedServer;
  List<dynamic> get servers => _servers;
  String? get lastError => _lastError;
  Map<String, bool> get securityFeatures => _securityFeatures;
  bool get isFetchingSecurity => _isFetchingSecurity;
  bool get triggerSessionExpired => _triggerSessionExpired;

  void triggerSessionExpiredDialog() {
    _triggerSessionExpired = true;
    notifyListeners();
    Future.microtask(() {
      _triggerSessionExpired = false;
    });
  }

  Future<void> _syncSessionTime() async {
    if (!_isFreeUser) {
      _isSessionTimeLoaded = true;
      notifyListeners();
      return;
    }
    try {
      final response = await ApiService.getSessionTime();
      if (response['success'] == true) {
        _remainingSeconds = response['data']['remaining_seconds'] ?? 0;
        // Cache the real value for next reopen
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('cached_remaining_seconds', _remainingSeconds);
        await prefs.setInt('cached_timestamp', DateTime.now().millisecondsSinceEpoch);
      }
    } catch (_) {
      // On network failure, keep the cached value already shown
    } finally {
      _isSessionTimeLoaded = true;
      notifyListeners();
    }
  }

  VPNProvider() {
    _init();
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      // IMPORTANT: Do NOT tick down until we've loaded the real session time
      // from the server. Without this guard, the timer fires with _remainingSeconds=0
      // on every app reopen, immediately calling _handleSessionExpiry() and
      // disconnecting the VPN before the API has a chance to respond.
      if (!_isSessionTimeLoaded) return;
      
      if (_isConnected && _isFreeUser) {
        final reqPlan =
            _selectedServer?['required_plan']?.toString().toLowerCase() ??
                'free';
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
          // Keep the cache reasonably fresh so a force-kill doesn't lose too much time
          if (_remainingSeconds % 5 == 0) {
            SharedPreferences.getInstance().then((prefs) {
              prefs.setInt('cached_remaining_seconds', _remainingSeconds);
              prefs.setInt('cached_timestamp', DateTime.now().millisecondsSinceEpoch);
            });
          }
          notifyListeners();
        } else {
          _handleSessionExpiry();
        }
      }
    });
    _notifTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      fetchNotifications();
    });
  }

  Future<void> _init() async {
    _startVpnStatusPoller();
    
    // Load previously notified IDs to prevent duplicate alerts across app restarts
    final prefs = await SharedPreferences.getInstance();
    final savedIds = prefs.getStringList('notified_ids') ?? [];
    _notifiedIds.addAll(savedIds);

    // ── Instant session time restore ──────────────────────────────────────────
    // Calculate exact real time passed since app was closed, so there is ZERO delay.
    final cachedSeconds = prefs.getInt('cached_remaining_seconds');
    final cachedTimestamp = prefs.getInt('cached_timestamp');
    if (cachedSeconds != null && cachedSeconds > 0) {
      if (cachedTimestamp != null) {
        final elapsedSeconds = (DateTime.now().millisecondsSinceEpoch - cachedTimestamp) ~/ 1000;
        final calculated = cachedSeconds - elapsedSeconds;
        _remainingSeconds = calculated > 0 ? calculated : 0;
      } else {
        _remainingSeconds = cachedSeconds;
      }
      _isSessionTimeLoaded = true; // Let the timer tick immediately!
      notifyListeners();
    }
    
    // Run network requests simultaneously to drastically speed up startup time
    await Future.wait([
      fetchProfile().then((_) async {
        // These depend on fetchProfile finishing first (to know _isFreeUser)
        await NotificationService.registerToken();
        await _syncSessionTime();
      }),
      fetchServers(),
      fetchSecuritySettings(),
      checkConnectionStatus(),
      fetchRealIp(),
      fetchNotifications(), // Instantly check for new notifications on launch
    ]);
    
    // Remove the previous _servers.firstWhere wait block, 
    // because we now INSTANTLY restore the JSON in checkConnectionStatus()

    if (_selectedServer == null && _servers.isNotEmpty) {
      final random = math.Random();
      if (_isFreeUser) {
        final freeServers = _servers.where((s) {
          final reqPlan = s['required_plan']?.toString().toLowerCase() ?? 'free';
          return reqPlan == 'free' || reqPlan == 'starter';
        }).toList();
        if (freeServers.isNotEmpty) {
          _selectedServer = freeServers[random.nextInt(freeServers.length)] as Map<String, dynamic>;
        } else {
          _selectedServer = _servers[random.nextInt(_servers.length)] as Map<String, dynamic>;
        }
      } else {
        _selectedServer = _servers[random.nextInt(_servers.length)] as Map<String, dynamic>;
      }
      notifyListeners();
    }

    _initConnectivity();
  }

  bool _userManuallyDisconnected = false;
  bool _wasOnWifi = false;

  void _initConnectivity() {
    bool _isFirstEvent =
        true; // Ignore the first event which fires immediately on startup
    _connectivitySub = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      final isOnWifi = results.contains(ConnectivityResult.wifi);
      final hasInternet = results.any((r) => r != ConnectivityResult.none);

      // If we completely lost WiFi and went to mobile data or no connection,
      // reset the manual disconnect override. This ensures that the NEXT time
      // we join a WiFi network, auto-connect works again.
      if (!isOnWifi) {
        _userManuallyDisconnected = false;
      }

      _wasOnWifi = isOnWifi;

      if (_isFirstEvent) {
        _isFirstEvent = false;
        return;
      }

      // Retry loading crucial data if we started the app offline and just got internet
      if (hasInternet && _userData == null) {
        fetchProfile();
        fetchServers();
        _syncSessionTime();
        fetchSecuritySettings();
      }

      // Auto-connect if:
      // 1. Feature is ON
      // 2. We are not connected
      // 3. We are on WiFi
      // 4. The user hasn't explicitly clicked "Disconnect" on this current WiFi session
      if (_securityFeatures['auto_connect_wifi'] == true &&
          !_isConnected &&
          isOnWifi &&
          !_userManuallyDisconnected) {
        _autoConnectWifi();
      }
    });
  }

  Future<void> fetchRealIp() async {
    try {
      final resp = await ApiService.getIp();
      _realIp = resp['data']?['ip']?.toString() ?? resp['ip']?.toString();
    } catch (_) {
      // Silently fail
    }
  }

  Future<void> _autoConnectWifi() async {
    if (_isConnected ||
        _status == 'Connecting...' ||
        _status == 'Provisioning...') return;

    // Connect to selected server if available
    if (_selectedServer != null) {
      final serverId = _selectedServer!['id']?.toString();
      if (serverId != null) {
        connect(serverId, mode: 'standard');
        return;
      }
    }

    // Fallback: connect to best server
    try {
      final response = await ApiService.getBestServer();
      if (response['success'] == true && response['data'] != null) {
        final server = response['data'] as Map<String, dynamic>;
        _selectedServer = server;
        connect(server['id'].toString(), mode: 'standard');
      } else if (_servers.isNotEmpty) {
        _selectedServer = _servers.first;
        connect(_servers.first['id'].toString(), mode: 'standard');
      }
    } catch (_) {}
  }

  // ── Native VPN status poller ──────────────────────────────────────────────
  /// Polls the native VPN service every 2 seconds to detect if the tunnel
  /// was brought up or torn down by the OS (e.g. Kill Switch recovery).
  int _connectingTicks = 0;

  void _startVpnStatusPoller() {
    if (kIsWeb) return;
    _vpnStatusPoller?.cancel();
    _vpnStatusPoller = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final nativeConnected = await VpnService.isConnected();
        final nativeError = await VpnService.getError();
        
        // Handle native errors
        if (nativeError != null && nativeError.isNotEmpty) {
           if (_status == 'Connecting...' || _status == 'Connected') {
              _isConnected = false;
              _status = 'Connection Failed';
              _lastError = nativeError;
              notifyListeners();
           }
           return;
        }

        if (nativeConnected && !_isConnected) {
          // Native tunnel came up
          _isConnected = true;
          _status = 'Connected';
          _lastError = null;
          _connectingTicks = 0;
          notifyListeners();
        } else if (!nativeConnected && _isConnected && _status == 'Connected') {
          // Native tunnel dropped unexpectedly (Kill Switch or system close)
          _isConnected = false;
          _status = 'Disconnected';
          _currentServer = 'None';
          _connectingTicks = 0;
          _remainingSeconds = 0; // Clear reward time (Use it or lose it)
          ApiService.disconnect(); // Tell backend to clear the session!
          notifyListeners();
        } else if (!nativeConnected && !_isConnected && _status == 'Connecting...') {
          // Track timeout
          _connectingTicks++;
          if (_connectingTicks >= 8) {
             _isConnected = false;
             _status = 'Connection Failed';
             
             // Print exception error in that time out section so we can find the right error
             final errorMsg = nativeError != null && nativeError.isNotEmpty 
                 ? nativeError 
                 : 'Tunnel failed to establish (No native error provided by OS)';
             print('Exception error in connection timeout section: $errorMsg');
             
             _lastError = 'Connection timed out while waiting for tunnel to establish.\nError: $errorMsg';
             _connectingTicks = 0;
             notifyListeners();
          }
        } else {
          _connectingTicks = 0; // reset if in any other state
        }
      } catch (_) {}
    });
  }

  // ── Keypair helpers ────────────────────────────────────────────────────────
  /// Returns (privateKey, publicKey) — generates once, stores in prefs.
  ///
  /// Uses proper WireGuard-compliant Curve25519 key generation with the
  /// required bit-clamping. Without clamping, the derived shared secret
  /// is wrong and internet traffic silently fails.
  Future<(String, String)> _getOrCreateKeyPair() async {
    final prefs = await SharedPreferences.getInstance();

    // Clear any old keys that may have been generated without proper clamping.
    // Standard WireGuard base64 keys are always exactly 44 characters.
    // Also clear keys generated with the old double-clamping bug (version key check).
    final legacyKey = prefs.getString('wg_private_key');
    final legacyVersion = prefs.getString('wg_key_version');
    if (legacyKey != null && legacyKey.length != 44) {
      debugPrint(
          '[WG] Clearing legacy incompatible keys (length: ${legacyKey.length}).');
      await prefs.remove('wg_private_key');
      await prefs.remove('wg_public_key');
    } else if (legacyVersion != 'v2') {
      // v2 = fixed key generation without double-clamping
      debugPrint('[WG] Clearing old keys generated with buggy double-clamping algorithm.');
      await prefs.remove('wg_private_key');
      await prefs.remove('wg_public_key');
    }

    String? priv = prefs.getString('wg_private_key');
    String? pub = prefs.getString('wg_public_key');

    if (priv == null || pub == null) {
      // Use the X25519 library to generate a key pair.
      // IMPORTANT: Do NOT manually clamp and then call newKeyPairFromSeed —
      // the library clamps internally in newKeyPairFromSeed, which causes
      // double-clamping and a mismatch between the stored private key and the
      // public key sent to the server.
      // Instead, generate a full keypair in one call and extract both keys
      // from the SAME object so they are guaranteed to be a matched pair.
      final algorithm = X25519();
      final keyPair = await algorithm.newKeyPair();

      final privateKeyBytes =
          Uint8List.fromList(await keyPair.extractPrivateKeyBytes());
      final publicKeyObj = await keyPair.extractPublicKey();

      priv = base64Encode(privateKeyBytes);
      pub = base64Encode(publicKeyObj.bytes);

      await prefs.setString('wg_private_key', priv);
      await prefs.setString('wg_public_key', pub);
      await prefs.setString('wg_key_version', 'v2');
      debugPrint('[WG] Generated new WireGuard key pair (matched pair).');
      debugPrint('[WG] Public Key: $pub');
    } else {
      debugPrint('[WG] Using cached key pair. Public Key: $pub');
    }

    return (priv, pub);
  }

  /// Injects the device private key and security settings into the WireGuard config.
  String _applySecuritySettings(String config, String privateKey) {
    String finalConfig = config.trim();
    debugPrint('[VPN] RAW BACKEND CONFIG: $finalConfig');

    // 1. Ensure [Interface] exists
    if (!finalConfig.contains('[Interface]')) {
      finalConfig = '[Interface]\n$finalConfig';
    }

    // 2. Ensure Address exists (CRITICAL: Handshake fails without this)
    if (!finalConfig.contains('Address')) {
      debugPrint(
          '[VPN] WARNING: Missing Address line. Injecting fallback 10.0.0.2/32');
      finalConfig = finalConfig.replaceFirst(
          '[Interface]', '[Interface]\nAddress = 10.0.0.2/32');
    }

    // 3. Determine DNS based on smart priority
    final adBlocker = _securityFeatures['ad_blocker_enabled'] == true;
    final trackerBlocker = _securityFeatures['tracker_blocker_enabled'] == true;
    final malwareProtection = _securityFeatures['malware_protection'] == true;
    
    String dnsToInject;
    if (adBlocker || trackerBlocker) {
      // AdGuard DNS Default (Blocks Ads, Trackers, and Malware)
      dnsToInject = '94.140.14.14, 94.140.15.15';
    } else if (malwareProtection) {
      // Cloudflare Malware-Blocking DNS
      dnsToInject = '1.1.1.2, 1.0.0.2';
    } else {
      // Cloudflare Standard Secure DNS (No blocking)
      dnsToInject = '1.1.1.1, 8.8.8.8';
    }

    // 4. Clean up existing lines
    finalConfig = finalConfig.replaceAll(RegExp(r'DNS\s*=\s*[^\n]*\n?'), '');
    finalConfig = finalConfig.replaceAll(RegExp(r'MTU\s*=\s*[^\n]*\n?'), '');
    finalConfig =
        finalConfig.replaceAll(RegExp(r'PrivateKey\s*=\s*[^\n]*\n?'), '');
    finalConfig = finalConfig.replaceAll(
        RegExp(r'PersistentKeepalive\s*=\s*[^\n]*\n?'), '');

    // 5. Inject Interface settings
    // MTU 1280 is the absolute safest MTU because it is the exact minimum required for IPv6.
    finalConfig = finalConfig.replaceFirst('[Interface]',
        '[Interface]\nPrivateKey = ${privateKey.trim()}\nDNS = $dnsToInject\nMTU = 1280');

    // 6. Inject Peer settings
    // Force AllowedIPs to 0.0.0.0/0 to prevent IPv6 blackholing on mobile networks.
    finalConfig = finalConfig.replaceAll(RegExp(r'AllowedIPs\s*=\s*[^\n]*\n?'), '');
    const allowedIPs = '0.0.0.0/0';
    
    if (!finalConfig.contains('PersistentKeepalive')) {
      finalConfig = finalConfig.replaceFirst(
          '[Peer]', '[Peer]\nAllowedIPs = $allowedIPs\nPersistentKeepalive = 25');
    } else {
      finalConfig = finalConfig.replaceFirst(
          '[Peer]', '[Peer]\nAllowedIPs = $allowedIPs');
    }

    // 7. Check for Ngrok
    if (finalConfig.contains('ngrok')) {
      debugPrint('[VPN] ERROR: Ngrok detected. Use a real IP for WireGuard!');
    }

    finalConfig = finalConfig.split(', status:').first.trim();

    debugPrint('--- [Diagnostic WireGuard Config] ---');
    debugPrint(finalConfig);
    debugPrint('-------------------------------------');

    return finalConfig;
  }

  // ── Security Management ────────────────────────────────────────────────────
  Future<void> fetchSecuritySettings() async {
    _isFetchingSecurity = true;
    notifyListeners();
    try {
      final response = await ApiService.getSecuritySettings();
      if (response['success'] == true) {
        final rawData = response['data'] as Map<String, dynamic>;

        // connection_security group
        final connSec = rawData['connection_security'];
        if (connSec is Map) {
          connSec.forEach((key, value) {
            if (value is bool) _securityFeatures[key] = value;
          });
        }

        // privacy_tools group
        final privTools = rawData['privacy_tools'];
        if (privTools is Map) {
          privTools.forEach((key, value) {
            if (value is bool) _securityFeatures[key] = value;
          });
        }
      }
    } catch (e) {
      print('[Security] fetchSecuritySettings error: $e');
    } finally {
      _isFetchingSecurity = false;
      notifyListeners();
    }
  }

  // Maps each feature key to its backend group
  static const Map<String, String> _featureGroups = {
    'kill_switch_enabled': 'connection_security',
    'auto_connect_wifi': 'connection_security',
    'dns_leak_protection': 'connection_security',
    'ad_blocker_enabled': 'privacy_tools',
    'tracker_blocker_enabled': 'privacy_tools',
    'malware_protection': 'privacy_tools',
  };

  Future<void> toggleSecurityFeature(String key, bool value) async {
    final oldVal = _securityFeatures[key];
    _securityFeatures[key] = value;
    notifyListeners();

    try {
      // Send correctly nested payload to backend
      final group = _featureGroups[key];
      final Map<String, dynamic> payload = group != null
          ? {
              group: {key: value}
            }
          : {key: value};
      print('[Security] PATCH payload: $payload');
      final response = await ApiService.updateSecuritySettings(payload);
      print('[Security] PATCH response: $response');

      if (response['success'] != true) {
        _securityFeatures[key] = oldVal ?? !value;
        notifyListeners();
      }

      // If they just turned ON Auto WiFi, and they are currently on WiFi, connect them instantly
      if (key == 'auto_connect_wifi' && value == true) {
        _userManuallyDisconnected = false; // Reset the manual override
        if (_wasOnWifi && !_isConnected) {
          _autoConnectWifi();
        }
      }
    } catch (e) {
      print('[Security] toggleSecurityFeature error: $e');
      _securityFeatures[key] = oldVal ?? !value;
      notifyListeners();
    }
  }

  // ── Profile / Servers ──────────────────────────────────────────────────────
  Future<void> fetchProfile() async {
    try {
      // Print token for Postman testing
      final prefs = await SharedPreferences.getInstance();
      debugPrint('====================================');
      debugPrint('POSTMAN ACCESS TOKEN:');
      debugPrint(prefs.getString('access_token'));
      debugPrint('====================================');

      final response = await ApiService.getMe();
      if (response['success'] == true) {
        _userData = response['data']['user'];
        _isFreeUser = _userData?['plan'] == 'free';
        notifyListeners();

        // Ensure push notification token is registered with this account
        if (!kIsWeb) {
          NotificationService.registerToken();
        }
      }
    } catch (_) {}
  }

  Future<void> fetchServers() async {
    try {
      _servers = await ApiService.getServers();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> fetchNotifications() async {
    try {
      final response = await ApiService.getNotifications(unreadOnly: false);
      if (response['success'] == true) {
        final data = response['data'];
        final int newUnreadCount = data['unread_count'] ?? 0;
        final List<dynamic> notifs = data['notifications'] ?? [];

        if (_unreadCount != newUnreadCount || _cachedNotifications.isEmpty) {
          _unreadCount = newUnreadCount;
          _cachedNotifications = notifs;
          notifyListeners();
        }

        // Check for new notifications to push
        if (!kIsWeb) {
          for (var n in notifs) {
            final id = n['id']?.toString() ?? '';
            final isRead = n['is_read'] ?? true;
            if (!isRead && !_notifiedIds.contains(id)) {
              _notifiedIds.add(id);
              _saveNotifiedIds();
              // Re-enabled after fixing the native icon crash failsafe
              NotificationService.showNotification(
                id: id.hashCode.abs() % 100000,
                title: n['title'] ?? 'New Notification',
                body: n['message'] ?? '',
              );
            }
          }
        }

        if (_unreadCount != newUnreadCount) {
          _unreadCount = newUnreadCount;
          notifyListeners();
        }
      }
    } catch (_) {}
  }

  Future<void> _saveNotifiedIds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('notified_ids', _notifiedIds.toList());
  }

  void updateServers(List<dynamic> servers) {
    _servers = servers;
    notifyListeners();
  }

  void setSelectedServer(Map<String, dynamic> server) {
    if (_selectedServer?['id'] != server['id']) {
      _starterAdsWatched = 0; // Reset ad progress if switching servers
    }
    _selectedServer = server;
    _lastError = null;
    notifyListeners();
  }

  Future<void> checkConnectionStatus() async {
    try {
      // IMPORTANT: Check native tunnel FIRST.
      // If the native WireGuard tunnel is still UP (survived a swipe/kill),
      // we must trust it, even if the backend API says "disconnected".
      bool nativeUp = false;
      try {
        nativeUp = await VpnService.isConnected();
      } catch (_) {}

      final prefs = await SharedPreferences.getInstance();
      final savedServerId = prefs.getString('last_connected_server_id');
      final savedConfig = prefs.getString('last_vpn_config');
      final savedServerName = prefs.getString('last_connected_server_name');

      if (nativeUp) {
        if (!_isConnected) {
          _isConnected = true;
          _status = 'Connected';
          _lastError = null;
          
          if (savedServerName != null) {
            _currentServer = savedServerName;
          }
          final savedServerJson = prefs.getString('last_connected_server_json');
          if (savedServerJson != null) {
            try {
              _selectedServer = jsonDecode(savedServerJson) as Map<String, dynamic>;
            } catch (_) {}
          } else if (savedServerId != null && _servers.isNotEmpty) {
            _selectedServer = _servers.firstWhere(
              (s) => s['id']?.toString() == savedServerId,
              orElse: () => _selectedServer,
            );
          }
          
          notifyListeners();
        }
        return; // Tunnel is alive — do not ask backend.
      }

      // Native tunnel is down. Check if we have a saved session to restore.
      if (savedServerId != null && savedConfig != null) {
        // We were connected before — silently reconnect without going through Provisioning.
        debugPrint('[VPN] App reopened with saved session. Silently reconnecting...');
        _silentReconnect(savedConfig, savedServerId, savedServerName ?? '');
        return;
      }

      // No saved session — check backend for any active sessions from other devices.
      final response = await ApiService.getStatus();
      if (response['success'] == true &&
          response['data']['connected'] == true) {
        _isConnected = true;
        _status = 'Connected';
        final server = response['data']['server'];
        _currentServer = '${server['city']}, ${server['country']}';
        if (_isFreeUser) {
          await ApiService.getBandwidthUsage();
        }
      } else {
        _isConnected = false;
        _status = 'Disconnected';
        _currentServer = 'None';
        _selectedServer = null;
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Silently re-establishes the WireGuard tunnel using a saved config,
  /// without going through the full Provisioning flow or showing ads.
  Future<void> _silentReconnect(String config, String serverId, String serverName) async {
    if (_isConnected || _status == 'Connecting...') return;
    _status = 'Connecting...';
    _connectingTicks = 0;
    _lastError = null;
    notifyListeners();
    try {
      await VpnService.connect(config, serverName: 'AtmosVPN - $serverName');
    } catch (e) {
      debugPrint('[VPN] Silent reconnect failed: $e');
      _status = 'Disconnected';
      _isConnected = false;
      // Clear saved session so we don't retry forever on a bad config.
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_connected_server_id');
      await prefs.remove('last_vpn_config');
      await prefs.remove('last_connected_server_name');
      notifyListeners();
    }
  }

  Future<void> _handleSessionExpiry() async {
    await disconnect(); // disconnect() already clears cached_remaining_seconds via prefs.remove
    _remainingSeconds = 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cached_remaining_seconds');
    triggerSessionExpiredDialog();
  }

  Future<bool> watchAd({String tier = 'free'}) async {
    if (_isFreeUser) {
      try {
        final response = await ApiService.claimAdReward(tier: tier);
        if (response['success'] == true) {
          final data = response['data'] ?? {};
          
          if (tier == 'starter') {
            _starterAdsWatched = data['ads_watched'] ?? 0;
            notifyListeners();
            
            // Check if we hit the required number of ads
            if (data.containsKey('reward_minutes') && data['reward_minutes'] > 0) {
              _remainingSeconds = (data['reward_minutes'] as num).toInt() * 60;
              SharedPreferences.getInstance().then((prefs) {
                prefs.setInt('cached_remaining_seconds', _remainingSeconds);
                prefs.setInt('cached_timestamp', DateTime.now().millisecondsSinceEpoch);
              });
              _starterAdsWatched = 0; // Reset upon successful claim
              notifyListeners();
              return true; // Reward claimed!
            }
            
            if (data.containsKey('remaining_seconds') && data['remaining_seconds'] > 0) {
              _remainingSeconds = (data['remaining_seconds'] as num).toInt();
              SharedPreferences.getInstance().then((prefs) {
                prefs.setInt('cached_remaining_seconds', _remainingSeconds);
                prefs.setInt('cached_timestamp', DateTime.now().millisecondsSinceEpoch);
              });
              _starterAdsWatched = 0;
              notifyListeners();
              return true;
            }
            
            return false; // Ad recorded, but need more to claim reward
          } else {
            // Free tier instantly grants time
            _remainingSeconds = (data['remaining_seconds'] as num?)?.toInt() ?? (30 * 60);
            SharedPreferences.getInstance().then((prefs) {
              prefs.setInt('cached_remaining_seconds', _remainingSeconds);
              prefs.setInt('cached_timestamp', DateTime.now().millisecondsSinceEpoch);
            });
            notifyListeners();
            return true; // Reward claimed!
          }
        }
      } catch (e) {
        debugPrint('Error claiming ad reward: $e');
      }
    }
    return false;
  }

  // ── Connect ────────────────────────────────────────────────────────────────
  Future<void> connect(String serverId, {String mode = 'standard'}) async {
    // GUARANTEE instant UI feedback before any Dart Event Loop yields
    _status = 'Provisioning...';
    _lastError = null;
    notifyListeners();

    final server = _servers.firstWhere(
      (s) => s['id']?.toString() == serverId,
      orElse: () => _selectedServer,
    );
    final reqPlan =
        server?['required_plan']?.toString().toLowerCase() ?? 'free';
    final userPlan = _userData?['plan']?.toString().toLowerCase() ?? 'free';

    // BOTH Free and Starter servers require an ad if remaining seconds is 0!
    final bool needsAd = userPlan == 'free' && _remainingSeconds <= 0;

    if (needsAd) {
      _status = 'Disconnected';
      notifyListeners();
      // Do not auto-reward. Trigger the popup event.
      triggerSessionExpiredDialog();
      return;
    }

    // --- PROMINENT DISCLOSURE CHECK ---
    final prefs = await SharedPreferences.getInstance();
    final hasAccepted = prefs.getBool('has_accepted_vpn_disclosure') ?? false;

    if (!hasAccepted) {
      final context = navigatorKey.currentContext;
      if (context != null) {
        bool? accepted = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.shield_rounded, color: Color(0xFF3B82F6)),
                SizedBox(width: 8),
                Text('VPN Permission', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            content: const Text(
              'AtmosVPN requires the use of the Android VpnService to create a secure tunnel and protect your internet traffic.\n\n'
              'We do NOT collect, store, or share your browsing history or traffic data. This permission is strictly used to encrypt your connection.\n\n'
              'Do you agree to proceed?',
              style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Agree', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
        
        if (accepted == true) {
          await prefs.setBool('has_accepted_vpn_disclosure', true);
          _status = 'Provisioning...'; // Restore loading animation
          notifyListeners();
        } else {
          _status = 'Disconnected';
          _lastError = 'VPN permission denied by user.';
          notifyListeners();
          return; // Cancelled
        }
      }
    }
    // ---------------------------------

    return _actualConnect(serverId, mode: mode);
  }

  Future<void> _actualConnect(String serverId,
      {String mode = 'standard'}) async {
    _userManuallyDisconnected = false; // Reset the manual disconnect flag
    
    // 1. Force a clean state by disconnecting any existing active session
    if (_isConnected) {
      await disconnect();
    }

    // Now safely give the user visual feedback that the loading has started
    _status = 'Provisioning...';
    _lastError = null;
    notifyListeners();

    try {
      // 1 + 2. Run keypair loading and stale config cleanup IN PARALLEL
      //        Both are independent, so no need to wait for one before the other.
      final bool useRealTunnel = !kIsWeb;
      String privateKey = '';
      String publicKey = 'placeholder_key=';

      // Task A: Get or generate the WireGuard keypair
      if (useRealTunnel) {
        final kp = await _getOrCreateKeyPair();
        privateKey = kp.$1;
        publicKey = kp.$2;
        debugPrint('[KEY-CHECK] Private Key (first 8 chars): ${privateKey.substring(0, 8)}...');
        debugPrint('[KEY-CHECK] Public Key being sent to /provision: $publicKey');
      }

      // Task B: Revoke any stale configs for this server (FIRE-AND-FORGET CLEANUP)
      // Do NOT await this, let it run in the background so it doesn't block connecting!
      () async {
        try {
          final existingConfigs = await ApiService.getVpnConfigs();
          List<dynamic> configs = [];
          if (existingConfigs['success'] == true && existingConfigs['data'] != null) {
            final data = existingConfigs['data'];
            if (data is List) {
              configs = data;
            } else if (data is Map && data['configs'] is List) {
              configs = data['configs'];
            }
          }
          final staleConfigIds = configs
              .where((cfg) => cfg['server_id']?.toString() == serverId && cfg['config_id'] != null)
              .map((cfg) => cfg['config_id'].toString())
              .toList();
          if (staleConfigIds.isNotEmpty) {
            await Future.wait(
              staleConfigIds.map((cfgId) => ApiService.revokeVpnConfig(cfgId))
            );
          }
        } catch (_) {}
      }();

      // 3. Provision — backend returns WireGuard .conf
      final provResponse = await ApiService.provisionVpn(
        serverId: serverId,
        publicKey: publicKey,
        mode: mode,
        platform: kIsWeb
            ? 'web'
            : Platform.isAndroid
                ? 'android'
                : Platform.isIOS
                    ? 'ios'
                    : 'unknown',
      );

      if (provResponse['success'] != true) {
        _status = 'Provisioning Failed';
        _lastError =
            provResponse['message']?.toString() ?? 'Failed to provision VPN.';
        _isConnected = false;
        notifyListeners();
        return;
      }

      final provData = provResponse['data'] as Map<String, dynamic>?;

      // 3. Poll job if backend is async
      final provStatus = provData?['status']?.toString();
      final jobId = provData?['job_id']?.toString();

      if (provStatus == 'provisioning' && jobId != null) {
        _status = 'Configuring...';
        notifyListeners();
        bool done = false;
        // Poll every 200ms instead of 1000ms (up to 20 seconds max)
        for (int i = 0; i < 100 && !done; i++) {
          await Future.delayed(const Duration(milliseconds: 200));
          final jr = await ApiService.getVpnJob(jobId);
          final js = jr['data']?['status']?.toString() ?? jr['status']?.toString();
          if (js == 'completed') done = true;
          if (js == 'failed') throw Exception('Server provisioning failed.');
        }
        if (!done) throw Exception('Provisioning timeout.');
      } else if (provStatus == 'active') {
        // Active immediately! Skip polling.
        debugPrint('[VPN] Provision returned active instantly. Skipping poll.');
      } else if (jobId != null) {
        // Fallback polling if status is missing but job_id is present
        _status = 'Configuring...';
        notifyListeners();
        bool done = false;
        for (int i = 0; i < 100 && !done; i++) {
          await Future.delayed(const Duration(milliseconds: 200));
          final jr = await ApiService.getVpnJob(jobId);
          final js = jr['data']?['status']?.toString() ?? jr['status']?.toString();
          if (js == 'completed') done = true;
          if (js == 'failed') throw Exception('Server provisioning failed.');
        }
        if (!done) throw Exception('Provisioning timeout.');
      }

      _status = 'Finalizing...';
      notifyListeners();

      _status = 'Connecting...';
      notifyListeners();

      // 4a. Real WireGuard tunnel (Android / iOS)
      if (useRealTunnel) {
        // Extract WireGuard config — backend may use different field names
        final rawConfig = (provData?['config'] ??
            provData?['wg_config'] ??
            provData?['wireguard_config'] ??
            provData?['config_file'] ??
            '') as String;

        if (rawConfig.isNotEmpty) {
          // Apply security settings and private key to the config string
          final fullConfig = _applySecuritySettings(rawConfig, privateKey);

          // KEY MISMATCH CHECK — confirm private key is in the final config
          final privKeyInConfig = fullConfig.contains(privateKey.trim());
          debugPrint('[KEY-CHECK] Private key present in final tunnel config: $privKeyInConfig');
          if (!privKeyInConfig) {
            debugPrint('[KEY-CHECK] ⚠️ MISMATCH: Private key NOT found in config! Tunnel will fail handshake.');
          }

          // Pass the friendly server name so the Android notification can display it
          final srvData = provData?['server'] as Map<String, dynamic>? ?? _selectedServer;
          String serverAddressToPass = 'Unknown Server';
          if (srvData != null && srvData['city'] != null) {
            serverAddressToPass = '${srvData['city']}, ${srvData['country']}';
          } else {
            // Fallback to serverId if no name found
            serverAddressToPass = serverId;
          }

          if (!fullConfig.contains('Address')) {
            // Missing address line
          }

          // Ensure clean private key
          final cleanPrivateKey = privateKey.trim();
          final configToUse =
              fullConfig.replaceAll(privateKey, cleanPrivateKey);

          // 4b. Notify Backend to ACTIVATE the session and add peer to server
          // BACKEND DEV UPDATE: provisionVpn() already activates it instantly.
          // Calling connect() here may conflict or reset the peer!
          /*
          try {
            await ApiService.connect(serverId, mode: mode);
            await Future.delayed(const Duration(
                seconds: 2)); // Give server time to update iptables/wg
          } catch (e) {}
          */

          // 5. Start the Native Tunnel
          // Retry loop: on Android, the first call may show the VPN permission dialog.
          // If the user grants it, the second call will succeed.
          try {
            final vpnStarted = await VpnService.connect(configToUse, serverName: 'AtmosVPN - $serverAddressToPass', killSwitch: _securityFeatures['kill_switch_enabled'] == true);
            if (vpnStarted) {
              _isConnected = false; // The poller will flip this to true when native confirms
              _status = 'Connecting...';
              _lastError = null;
              // Save session for silent reconnect after app is killed & reopened
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('last_vpn_config', configToUse);
              await prefs.setString('last_connected_server_id', serverId);
              await prefs.setString('last_connected_server_name', serverAddressToPass);
              if (_selectedServer != null) {
                await prefs.setString('last_connected_server_json', jsonEncode(_selectedServer));
              }
            } else {
              _status = 'Connection Failed';
              _lastError = 'VPN tunnel failed to start.';
              _isConnected = false;
            }
            notifyListeners();
          } on Exception catch (e, stacktrace) {
            final msg = e.toString();
            print('Exception error in VpnService.connect: $msg\n$stacktrace');
            if (msg.contains('permission') || msg.contains('denied')) {
              _status = 'Permission Denied';
              _lastError = 'VPN permission is required. Please tap Connect and approve the VPN permission dialog when it appears.';
            } else {
              _status = 'Disconnected';
              _lastError = 'Failed to start VPN tunnel. Please try again.\nError: $msg';
            }
            _isConnected = false;
            notifyListeners();
          }

          final serverData = provData?['server'] as Map<String, dynamic>?;
          if (serverData != null) {
            _currentServer =
                '${serverData['city'] ?? ''}, ${serverData['country'] ?? ''}';
          }
          return;
        }
      }

      // 4b. Fallback (web or no WireGuard config returned) — API-only session
      final connectResp = await ApiService.connect(
        serverId,
        mode: mode,
        protocol: 'wireguard',
      );
      if (connectResp['success'] == true) {
        final sd = connectResp['data']?['server'];
        _isConnected = true;
        _status = 'Connected';
        if (sd != null) {
          _currentServer = '${sd['city'] ?? ''}, ${sd['country'] ?? ''}';
        }
        notifyListeners();
        checkConnectionStatus();
      } else {
        _status = 'Connection Failed';
        _lastError = connectResp['message']?.toString() ?? 'Connection failed.';
        _isConnected = false;
        notifyListeners();
      }
    } catch (e, stacktrace) {
      _status = 'Connection Failed';
      String errorText = e.toString();
      
      print('Exception error in main connect block: $errorText\n$stacktrace');
      
      // Sanitize ugly system/network errors so they don't show on the UI
      if (errorText.contains('errno = 103') || errorText.contains('Software caused connection abort')) {
        _lastError = 'Connection interrupted while switching servers. Please try again.';
      } else if (errorText.contains('SocketException') || errorText.contains('ClientException')) {
        _lastError = 'Network connection failed. Please check your internet.';
      } else {
        _lastError = errorText.replaceAll('Exception: ', '');
      }
      
      _isConnected = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    if (!_isConnected && _status == 'Disconnected') {
      return; // Already cleanly disconnected, skip native teardown to save UI lag
    }
    
    _status = 'Disconnecting...';
    notifyListeners();
    // Run the native IPC calls off the main UI thread
    // so they cannot block the UI and cause an ANR.
    await Future.microtask(() async {
      try {
        if (!kIsWeb) {
          await VpnService.disconnect();
        }
        ApiService.disconnect(); // Fire-and-forget to drastically speed up reconnections
      } catch (_) {}
    });
    // Clear the saved session so silent reconnect doesn't fire after a manual disconnect
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_vpn_config');
      await prefs.remove('last_connected_server_id');
      await prefs.remove('last_connected_server_name');
      await prefs.remove('last_connected_server_json');
      await prefs.remove('last_connected_server_json');
      await prefs.remove('cached_remaining_seconds');
    } catch (_) {}
    _isConnected = false;
    _status = 'Disconnected';
    _currentServer = 'None';
    _remainingSeconds = 0; // NEW RULE: Use it or lose it
    notifyListeners();
  }

  Future<void> checkAndRequestReview() async {
    if (kIsWeb) return;
    try {
      debugPrint('[REVIEW] Checking review status...');
      final prefs = await SharedPreferences.getInstance();
      final lastPromptStr = prefs.getString('last_review_prompt_date');
      final now = DateTime.now();

      bool shouldPrompt = false;
      if (lastPromptStr == null) {
        shouldPrompt = true; // First time
      } else {
        final lastPromptDate = DateTime.parse(lastPromptStr);
        if (now.difference(lastPromptDate).inDays >= 5) {
          shouldPrompt = true; // 5 days passed
        }
      }

      if (shouldPrompt) {
        debugPrint('[REVIEW] shouldPrompt is true. Checking isAvailable...');
        final InAppReview inAppReview = InAppReview.instance;
        final isAvailable = await inAppReview.isAvailable();
        debugPrint('[REVIEW] isAvailable: $isAvailable');
        
        if (isAvailable) {
          debugPrint('[REVIEW] Requesting review from native API...');
          final context = navigatorKey.currentContext;
          if (context != null && context.mounted) {
            showDialog(
              context: context,
              builder: (context) {
                final isIOS = Theme.of(context).platform == TargetPlatform.iOS;
                final storeName = isIOS ? 'App Store' : 'Play Store';
                
                return Dialog(
                  backgroundColor: AppColors.cardBackground,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // "Rate Us" bubble
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                          ),
                          child: const Text('Rate Us', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(height: 16),
                        // 5 Stars
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(5, (index) => const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4.0),
                            child: Icon(Icons.star_rounded, color: Colors.orange, size: 36),
                          )),
                        ),
                        const SizedBox(height: 24),
                        // Title
                        const Text(
                          'Enjoying AtmosVPN?',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Subtitle
                        Text(
                          'Rate us on the $storeName and show your support!',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 32),
                        // Primary Button
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryBlue,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              elevation: 0,
                            ),
                            onPressed: () {
                              Navigator.pop(context);
                              inAppReview.openStoreListing();
                            },
                            child: Text('Rate on $storeName', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Secondary Button
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                            splashFactory: NoSplash.splashFactory,
                          ),
                          child: const Text('Maybe later', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          }
          await prefs.setString('last_review_prompt_date', now.toIso8601String());
        } else {
          debugPrint('[REVIEW] InAppReview is NOT available on this device (No Play Store / unsupported).');
        }
      }
    } catch (e) {
      debugPrint('[REVIEW] checkAndRequestReview exception: $e');
    }
  }

  void toggleConnection() {
    if (_isConnected) {
      _userManuallyDisconnected = true;
      if (_isFreeUser) {
        // Disconnect instantly so the user isn't stuck waiting
        disconnect();
        
        // Show review dialog BEFORE the ad so it's waiting underneath
        checkAndRequestReview();
        
        // Show ad shortly after initiating disconnect so the UI doesn't stutter
        Future.delayed(const Duration(milliseconds: 150), () {
          AdManager.showInterstitialAd(
            context: navigatorKey.currentContext,
          );
        });
      } else {
        disconnect();
        checkAndRequestReview();
      }
    } else {
      final reqPlan =
          _selectedServer?['required_plan']?.toString().toLowerCase() ?? 'free';

      if (_isFreeUser && _remainingSeconds <= 0) {
        triggerSessionExpiredDialog();
        return;
      }

      if (_selectedServer == null) {
        _lastError = 'Please select a server';
        _status = 'Disconnected';
        notifyListeners();
        return;
      }

      final serverId = _selectedServer!['id']?.toString();
      if (serverId != null) {
        if (_isFreeUser) {
          // Connect instantly in the background!
          connect(serverId);
          
          // Pop the ad over the UI while it is provisioning
          Future.delayed(const Duration(milliseconds: 150), () {
            AdManager.showInterstitialAd(context: navigatorKey.currentContext);
          });
        } else {
          connect(serverId);
        }
      } else {
        _status = 'No servers available';
        notifyListeners();
        fetchServers();
      }
    }
  }

  void setUpgrade(bool val) {
    _hasUpgraded = val;
    notifyListeners();
  }

  void updateProfileLocal({String? fullName, String? avatarUrl}) {
    if (_userData != null) {
      final updatedData = Map<String, dynamic>.from(_userData!);
      if (fullName != null) {
        updatedData['full_name'] = fullName;
      }
      if (avatarUrl != null) {
        updatedData['avatar_url'] = avatarUrl;
      }
      _userData = updatedData;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _vpnStatusPoller?.cancel();
    _sessionTimer?.cancel();
    _notifTimer?.cancel();
    _connectivitySub?.cancel();
    super.dispose();
  }
}
