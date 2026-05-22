import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:app_links/app_links.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:wireguard_flutter/wireguard_flutter.dart';
import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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

// Top-level FCM background handler - must be defined here at the top level
// of main.dart so the Android background isolate can find it.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Delegate all handling to the NotificationService
  await notificationBackgroundHandler(message);
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
        ChangeNotifierProvider(create: (_) => VPNProvider()),
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
    // if (state == AppLifecycleState.resumed) {
    //   AdManager.showAppOpenAdIfAvailable();
    // }
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
        '/login': (context) => const LoginScreen(),
        '/signup': (context) => const SignupScreen(),
        '/verify-email': (context) => const EmailVerificationScreen(),
        // ── App (post-login, responsive) ───────────────────────────
        '/home': (context) => const DashboardScreen(),
        '/dashboard': (context) => const DashboardScreen(),
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
  int _remainingSeconds = 0; // Safe default — real value loaded from backend in _syncSessionTime()
  bool _isSessionTimeLoaded = false; // False until first backend sync completes
  Timer? _sessionTimer;
  Timer? _notifTimer;
  int _unreadCount = 0;
  final Set<String> _notifiedIds = {};
  bool _wgInitialized = false;
  StreamSubscription<VpnStage>? _vpnStageSub;
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

  bool get isConnected => _isConnected;
  String get status => _status;
  String get currentServer => _currentServer;
  bool get isFreeUser => _isFreeUser;
  int get remainingSeconds => _remainingSeconds;
  int get remainingMinutes => _remainingSeconds ~/ 60;
  bool get hasUpgraded => _hasUpgraded;
  bool get isSessionTimeLoaded => _isSessionTimeLoaded;
  int get unreadCount => _unreadCount;
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
      }
    } catch (_) {
      // On network failure keep 0 — safer than showing wrong time
    } finally {
      _isSessionTimeLoaded = true;
      notifyListeners();
    }
  }

  VPNProvider() {
    _init();
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isConnected && _isFreeUser) {
        final reqPlan =
            _selectedServer?['required_plan']?.toString().toLowerCase() ??
                'free';
        final isStarterServer = reqPlan == 'starter';
        if (isStarterServer) {
          if (_remainingSeconds > 0) {
            _remainingSeconds--;
            notifyListeners();
          } else {
            _handleSessionExpiry();
          }
        }
      }
    });
    _notifTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      fetchNotifications();
    });
  }

  Future<void> _init() async {
    await _initWireGuard();
    await fetchProfile();
    await NotificationService.registerToken();
    await _syncSessionTime(); // Get real time from backend
    await fetchServers();
    await fetchSecuritySettings();
    await checkConnectionStatus();
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

  // ── WireGuard engine init ──────────────────────────────────────────────────
  Future<void> _initWireGuard() async {
    if (kIsWeb) return;
    try {
      await WireGuardFlutter.instance.initialize(interfaceName: 'wg0');
      _wgInitialized = true;
      _vpnStageSub =
          WireGuardFlutter.instance.vpnStageSnapshot.listen(_handleVpnStage);
    } catch (e) {
      print('[WireGuard] init error: $e');
    }
  }

  void _handleVpnStage(VpnStage stage) {
    print('[WireGuard] stage: $stage');
    switch (stage) {
      case VpnStage.connected:
        _isConnected = true;
        _status = 'Connected';
        _lastError = null;
        break;
      case VpnStage.disconnected:
      case VpnStage.noConnection:
      case VpnStage.exiting:
        _isConnected = false;
        _status = 'Disconnected';
        _currentServer = 'None';
        break;
      case VpnStage.connecting:
      case VpnStage.waitingConnection:
      case VpnStage.preparing:
      case VpnStage.reconnect:
      case VpnStage.authenticating:
        _status = 'Connecting...';
        break;
      case VpnStage.denied:
        _isConnected = false;
        _status = 'Disconnected';
        _lastError = 'VPN permission denied by user.';
        break;
      default:
        break;
    }
    notifyListeners();
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
    final legacyKey = prefs.getString('wg_private_key');
    if (legacyKey != null && legacyKey.length != 44) {
      debugPrint(
          '[WG] Clearing legacy incompatible keys (length: ${legacyKey.length}).');
      await prefs.remove('wg_private_key');
      await prefs.remove('wg_public_key');
    }

    String? priv = prefs.getString('wg_private_key');
    String? pub = prefs.getString('wg_public_key');

    if (priv == null || pub == null) {
      // Generate a raw 32-byte Curve25519 private key
      final algorithm = X25519();
      final keyPair = await algorithm.newKeyPair();
      final rawPrivBytes =
          Uint8List.fromList(await keyPair.extractPrivateKeyBytes());

      // Apply WireGuard's REQUIRED Curve25519 bit-clamping to the private key.
      // Without this, the key exchange produces a wrong shared secret.
      // Ref: https://cr.yp.to/ecdh/curve25519-20060209.pdf
      rawPrivBytes[0] &= 248; // Clear bits 0, 1, 2
      rawPrivBytes[31] &= 127; // Clear bit 255
      rawPrivBytes[31] |= 64; // Set bit 254

      // Derive the correct public key from the clamped private key
      final clampedKeyPair = await algorithm.newKeyPairFromSeed(rawPrivBytes);
      final publicKeyObj = await clampedKeyPair.extractPublicKey();

      priv = base64Encode(rawPrivBytes);
      pub = base64Encode(publicKeyObj.bytes);

      await prefs.setString('wg_private_key', priv);
      await prefs.setString('wg_public_key', pub);
      debugPrint('[WG] Generated new WireGuard-compliant key pair.');
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

    // 3. Determine DNS
    final adBlocker = _securityFeatures['ad_blocker_enabled'] == true;
    String dnsToInject =
        adBlocker ? '94.140.14.14, 94.140.15.15' : '1.1.1.1, 8.8.8.8';

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
    // We use a split default route to avoid Android routing table conflicts.
    // CRITICAL: We MUST include ::/1 and 8000::/1 to route IPv6 traffic, otherwise mobile carriers will stall.
    const allowedIPs = '0.0.0.0/1, 128.0.0.0/1, ::/1, 8000::/1';
    if (!finalConfig.contains('AllowedIPs')) {
      finalConfig = finalConfig.replaceFirst('[Peer]',
          '[Peer]\nAllowedIPs = $allowedIPs\nPersistentKeepalive = 25');
    } else {
      finalConfig = finalConfig.replaceAll(
          RegExp(r'AllowedIPs\s*=\s*[^\n]*'), 'AllowedIPs = $allowedIPs');
      if (!finalConfig.contains('PersistentKeepalive')) {
        finalConfig = finalConfig.replaceFirst(
            '[Peer]', '[Peer]\nPersistentKeepalive = 25');
      }
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

        // Check for new notifications to push
        if (!kIsWeb) {
          for (var n in notifs) {
            final id = n['id']?.toString() ?? '';
            final isRead = n['is_read'] ?? true;
            if (!isRead && !_notifiedIds.contains(id)) {
              _notifiedIds.add(id);
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

  void updateServers(List<dynamic> servers) {
    _servers = servers;
    notifyListeners();
  }

  void setSelectedServer(Map<String, dynamic> server) {
    _selectedServer = server;
    _lastError = null;
    notifyListeners();
  }

  Future<void> checkConnectionStatus() async {
    try {
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
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _handleSessionExpiry() async {
    await disconnect();
    _remainingSeconds = 0;
    triggerSessionExpiredDialog();
  }

  Future<void> watchAd() async {
    if (_isFreeUser) {
      try {
        final response = await ApiService.claimAdReward();
        if (response['success'] == true) {
          _remainingSeconds = response['data']['remaining_seconds'] ?? 0;
          notifyListeners();
        }
      } catch (_) {}
    }
  }

  // ── Connect ────────────────────────────────────────────────────────────────
  Future<void> connect(String serverId, {String mode = 'standard'}) async {
    final server = _servers.firstWhere(
      (s) => s['id']?.toString() == serverId,
      orElse: () => _selectedServer,
    );
    final reqPlan =
        server?['required_plan']?.toString().toLowerCase() ?? 'free';
    final userPlan = _userData?['plan']?.toString().toLowerCase() ?? 'free';

    final isStarterServer = reqPlan == 'starter';
    final bool needsAd =
        userPlan == 'free' && isStarterServer && _remainingSeconds <= 0;

    if (needsAd) {
      // Do not auto-reward. Trigger the popup event.
      triggerSessionExpiredDialog();
      return;
    }

    return _actualConnect(serverId, mode: mode);
  }

  Future<void> _actualConnect(String serverId,
      {String mode = 'standard'}) async {
    _userManuallyDisconnected = false; // Reset the manual disconnect flag
    // 1. Force a clean state by disconnecting any existing session
    await disconnect();

    _status = 'Provisioning...';
    _lastError = null;
    notifyListeners();

    try {
      // 1. Generate (or load) real WireGuard keypair on-device
      String privateKey = '';
      String publicKey = 'placeholder_key=';
      final bool useRealTunnel = !kIsWeb && _wgInitialized;

      if (useRealTunnel) {
        final kp = await _getOrCreateKeyPair();
        privateKey = kp.$1;
        publicKey = kp.$2;
      }

      // 2. Revoke any existing stale config for this server
      //    This forces the backend to generate a fresh config with real keys
      //    instead of returning the old cached PENDING_SERVER_KEY config.
      try {
        final existingConfigs = await ApiService.getVpnConfigs();
        List<dynamic> configs = [];
        if (existingConfigs['success'] == true &&
            existingConfigs['data'] != null) {
          final data = existingConfigs['data'];
          if (data is List) {
            configs = data;
          } else if (data is Map && data['configs'] is List) {
            configs = data['configs'];
          }
        }
        for (final cfg in configs) {
          final cfgServerId = cfg['server_id']?.toString();
          final cfgId = cfg['config_id']?.toString();
          if (cfgServerId == serverId && cfgId != null) {
            await ApiService.revokeVpnConfig(cfgId);
          }
        }
      } catch (e) {}

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
      final jobId = provData?['job_id']?.toString();
      if (jobId != null) {
        _status = 'Configuring...';
        notifyListeners();
        bool done = false;
        for (int i = 0; i < 20 && !done; i++) {
          await Future.delayed(const Duration(seconds: 1));
          final jr = await ApiService.getVpnJob(jobId);
          final js = jr['data']?['status']?.toString();
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

          // Parse server address + port from Endpoint line
          String serverAddress = serverId; // fallback
          final epMatch = RegExp(r'Endpoint\s*=\s*([^:\n\r]+):(\d+)')
              .firstMatch(fullConfig);
          if (epMatch != null) {
            serverAddress = (epMatch.group(1) ?? serverAddress).trim();
          }

          if (!fullConfig.contains('Address')) {
            // Missing address line
          }

          // Ensure clean private key
          final cleanPrivateKey = privateKey.trim();
          final configToUse =
              fullConfig.replaceAll(privateKey, cleanPrivateKey);

          // 4b. Notify Backend to ACTIVATE the session and add peer to server
          try {
            await ApiService.connect(serverId, mode: mode);
            await Future.delayed(const Duration(
                seconds: 2)); // Give server time to update iptables/wg
          } catch (e) {}

          // 5. Start the Native Tunnel
          // Retry loop: on Android, the first call may show the VPN permission dialog.
          // If the user grants it, the second call will succeed.
          bool vpnStarted = false;
          for (int attempt = 1; attempt <= 2 && !vpnStarted; attempt++) {
            try {
              await WireGuardFlutter.instance.startVpn(
                serverAddress: serverAddress,
                wgQuickConfig: configToUse,
                providerBundleIdentifier: 'com.atmosvpn.app.network-extension',
              );
              vpnStarted = true;
            } on Exception catch (e) {
              final msg = e.toString();
              if (msg.contains('Permissions are not given') ||
                  msg.contains('permission')) {
                if (attempt == 1) {
                  // The Android "Allow VPN" dialog was shown. Give the user
                  // 5 seconds to approve it, then retry.
                  // 5 seconds to approve it, then retry.
                  _status = 'Awaiting Permission...';
                  notifyListeners();
                  await Future.delayed(const Duration(seconds: 5));
                } else {
                  // User denied the permission dialog.
                  _status = 'Permission Denied';
                  _lastError =
                      'VPN permission is required. Please tap Connect and approve the VPN permission dialog when it appears.';
                  _isConnected = false;
                  notifyListeners();
                }
              } else {
                _status = 'Disconnected';
                _lastError = 'Failed to start VPN tunnel. Please try again.';
                _isConnected = false;
                notifyListeners();
                break;
              }
            }
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
    } catch (e) {
      _status = 'Connection Failed';
      _lastError = e.toString().replaceAll('Exception: ', '');
      _isConnected = false;
      notifyListeners();
    }
  }

  // ── Disconnect ─────────────────────────────────────────────────────────────
  Future<void> disconnect() async {
    _status = 'Disconnecting...';
    notifyListeners();
    try {
      if (!kIsWeb && _wgInitialized) {
        await WireGuardFlutter.instance.stopVpn();
      }
      await ApiService.disconnect();
    } catch (_) {}
    _isConnected = false;
    _status = 'Disconnected';
    _currentServer = 'None';
    notifyListeners();
  }

  void toggleConnection() {
    if (_isConnected) {
      _userManuallyDisconnected = true;
      if (_isFreeUser) {
        AdManager.showInterstitialAd(onAdDismissed: () {
          disconnect();
        });
      } else {
        disconnect();
      }
    } else {
      final reqPlan =
          _selectedServer?['required_plan']?.toString().toLowerCase() ?? 'free';
      final isStarterServer = reqPlan == 'starter';

      if (_isFreeUser && isStarterServer && _remainingSeconds <= 0) {
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
          AdManager.showInterstitialAd(onAdDismissed: () {
            connect(serverId);
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
    _vpnStageSub?.cancel();
    _sessionTimer?.cancel();
    _notifTimer?.cancel();
    _connectivitySub?.cancel();
    super.dispose();
  }
}
