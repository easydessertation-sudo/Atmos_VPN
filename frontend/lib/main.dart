import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'utils/design_system.dart';
import 'utils/api_service.dart';
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
import 'screens/onboarding_screen.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/trial_offer_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/device_management_screen.dart';
import 'screens/billing_screen.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => VPNProvider()),
      ],
      child: const SecureVPNApp(),
    ),
  );
}

class SecureVPNApp extends StatelessWidget {
  const SecureVPNApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SecureVPN',
      debugShowCheckedModeBanner: false,
      theme: AppDesign.darkTheme,
      initialRoute: '/splash',
      routes: {
        '/splash': (context) => const SplashScreen(),
        '/trial': (context) => const TrialOfferScreen(),
        // ── Web Marketing ──────────────────────────────────────────
        '/': (context) => const WebLandingPage(),
        '/features': (context) => const FeaturesPage(),
        '/how-vpn-works': (context) => const HowVpnWorksPage(),
        '/why': (context) => const HowVpnWorksPage(),
        '/servers': (context) => const ServersPage(),
        '/blog': (context) => const BlogPage(),
        '/about': (context) => const AboutPage(),
        '/contact': (context) => const ContactPage(),
        '/careers': (context) => const CareersPage(),
        // Use cases
        '/use-cases/streaming': (context) => const FooterContentPage(data: FooterContentCatalog.streaming),
        '/use-cases/gaming': (context) => const FooterContentPage(data: FooterContentCatalog.gaming),
        '/use-cases/crypto': (context) => const FooterContentPage(data: FooterContentCatalog.crypto),
        '/use-cases/torrenting': (context) => const FooterContentPage(data: FooterContentCatalog.torrenting),
        '/use-cases/privacy': (context) => const FooterContentPage(data: FooterContentCatalog.privacy),
        // Legal
        '/privacy-policy': (context) => const PrivacyPolicyPage(),
        '/terms': (context) => const TermsPage(),
        '/no-logs-audit': (context) => const FooterContentPage(data: FooterContentCatalog.noLogsAudit),
        '/cookie-policy': (context) => const CookiePolicyPage(),
        '/gdpr': (context) => const FooterContentPage(data: FooterContentCatalog.gdpr),
        // Download / Pricing
        '/download': (context) => const _PlaceholderPage('Download App'),
        '/pricing': (context) => const PricingScreen(),
        // ── Auth ───────────────────────────────────────────────────
        '/onboarding': (context) => const OnboardingScreen(),
        '/login': (context) => const LoginScreen(),
        '/signup': (context) => const SignupScreen(),
        // ── App (post-login, responsive) ───────────────────────────
        '/home': (context) => const DashboardScreen(),
        '/dashboard': (context) => const DashboardScreen(),
        '/server-list': (context) => const ServerListScreen(),
        '/map': (context) => const MapViewScreen(),
        '/modes': (context) => const ModeSelectionScreen(),
        '/security': (context) => const SecurityCenterScreen(),
        '/speed': (context) => const SpeedTestScreen(),
        '/account': (context) => const AccountScreen(),
        '/account/pricing': (context) => const PricingScreen(),
        '/account/devices': (context) => const DeviceManagementScreen(),
        '/account/billing': (context) => const BillingScreen(),
        '/support': (context) => const SupportScreen(),
        // Learn / Company footer content
        '/learn/how-vpn-works': (context) => const FooterContentPage(data: FooterContentCatalog.howVpnWorks),
        '/learn/why-vpn': (context) => const FooterContentPage(data: FooterContentCatalog.whyVpn),
        '/learn/vpn-guide-2024': (context) => const FooterContentPage(data: FooterContentCatalog.vpnGuide),
        '/blog': (context) => const FooterContentPage(data: FooterContentCatalog.blog),
        '/company/press': (context) => const FooterContentPage(data: FooterContentCatalog.press),
        '/company/affiliates': (context) => const FooterContentPage(data: FooterContentCatalog.affiliates),
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
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.construction_rounded, color: AppColors.primaryBlue, size: 64),
            const SizedBox(height: 24),
            Text(title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white)),
            const SizedBox(height: 12),
            const Text('This page is coming soon.', style: TextStyle(color: AppColors.textSecondary)),
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
  int _remainingSeconds = 45 * 60; // 45 minutes in seconds
  bool _hasUpgraded = false;
  Map<String, dynamic>? _userData;
  List<dynamic> _servers = [];
  String? _lastError;
  Timer? _countdownTimer;

  bool get isConnected => _isConnected;
  String get status => _status;
  String get currentServer => _currentServer;
  bool get isFreeUser => _isFreeUser;
  int get remainingSeconds => _remainingSeconds;
  int get remainingMinutes => _remainingSeconds ~/ 60;
  bool get hasUpgraded => _hasUpgraded;
  Map<String, dynamic>? get userData => _userData;
  List<dynamic> get servers => _servers;
  String? get lastError => _lastError;

  VPNProvider() {
    _init();
  }

  Future<void> _init() async {
    await fetchProfile();
    await fetchServers();
    await checkConnectionStatus();
  }

  Future<void> fetchProfile() async {
    try {
      final response = await ApiService.getMe();
      if (response['success'] == true) {
        _userData = response['data']['user'];
        _isFreeUser = _userData?['plan'] == 'free';
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> fetchServers() async {
    try {
      _servers = await ApiService.getServers();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> checkConnectionStatus() async {
    try {
      final response = await ApiService.getStatus();
      if (response['success'] == true && response['data']['connected'] == true) {
        _isConnected = true;
        _status = 'Connected';
        final server = response['data']['server'];
        _currentServer = '${server['city']}, ${server['country_code'].toString().toUpperCase()}';
        final remaining = response['data']['remaining_seconds'];
        if (remaining != null) {
          _remainingSeconds = remaining as int;
        }
        if (_isFreeUser) _startCountdown();
      } else {
        _isConnected = false;
        _status = 'Disconnected';
        _currentServer = 'None';
        _stopCountdown();
      }
      notifyListeners();
    } catch (_) {}
  }

  void _startCountdown() {
    _stopCountdown();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isConnected) {
        timer.cancel();
        return;
      }
      if (_remainingSeconds > 0) {
        _remainingSeconds--;
        notifyListeners();
      } else {
        timer.cancel();
        _handleSessionExpiry();
      }
    });
  }

  void _stopCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  Future<void> _handleSessionExpiry() async {
    await disconnect();
    _remainingSeconds = 0;
    notifyListeners();
  }

  /// Free users can watch an ad to gain 30 extra minutes
  void watchAd() {
    if (_isFreeUser) {
      _remainingSeconds += 30 * 60;
      _hasUpgraded = true; // Hide the ad banner for this session
      notifyListeners();
    }
  }

  Future<void> connect(String serverId, {String mode = 'standard'}) async {
    _status = 'Connecting...';
    _lastError = null;
    notifyListeners();
    
    try {
      final response = await ApiService.connect(serverId, mode: mode);
      if (response['success'] == true) {
        await checkConnectionStatus();
      } else {
        _status = 'Connection Failed';
        _lastError = response['message'] ?? 'Connection failed. Please try again.';
        _isConnected = false;
        notifyListeners();
      }
    } catch (e) {
      _status = 'Connection Failed';
      _lastError = 'Cannot reach server. Check your connection.';
      _isConnected = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    _status = 'Disconnecting...';
    notifyListeners();
    _stopCountdown();
    try {
      await ApiService.disconnect();
    } catch (_) {}
    _isConnected = false;
    _status = 'Disconnected';
    _currentServer = 'None';
    notifyListeners();
  }

  void toggleConnection() {
    if (_isConnected) {
      disconnect();
    } else {
      if (_servers.isNotEmpty) {
        // Connect to the best/first server if none selected
        connect(_servers[0]['id'].toString());
      } else {
        _status = 'No servers available';
        notifyListeners();
        // Maybe trigger a fetch
        fetchServers();
      }
    }
  }

  void setUpgrade(bool val) {
    _hasUpgraded = val;
    notifyListeners();
  }
}
