import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../utils/design_system.dart';
import '../utils/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';
import '../utils/ad_manager.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    _handleStartup();
  }

  Future<void> _loadAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _appVersion = 'V ${packageInfo.version}';
      });
    }
  }

  Future<void> _handleStartup() async {
    // 1. Minimum delay for branding
    await Future.delayed(const Duration(seconds: 2));

    // 2. Load configurations or check auth
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');

    if (!mounted) return;

    if (token != null) {
      try {
        final userData =
            await ApiService.getMe().timeout(const Duration(seconds: 5));
        if (!mounted) return;
        if (userData['success'] == true) {
          final plan =
              userData['data']?['user']?['plan']?.toString().toLowerCase() ?? 'free';
          if (plan == 'free' && !kIsWeb) {
            AdManager.showAppOpenAdIfAvailable();
          }
          Navigator.pushReplacementNamed(context, '/home');
          return;
        }
      } catch (e) {
        // Token invalid or network error
        // If we catch an exception here, it means there's no internet connection
        // (SocketException or TimeoutException). Since the user has a token,
        // we should route them to the home screen instead of forcing a login.
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/home');
          return;
        }
      }
    }

    // Default: Web goes to Landing Page (/), Mobile goes to Login
    if (kIsWeb) {
      Navigator.pushReplacementNamed(context, '/');
    } else {
      Navigator.pushReplacementNamed(context, '/onboarding');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            // Background Glow
            Center(
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryBlue.withValues(alpha: 0.15),
                      blurRadius: 100,
                      spreadRadius: 50,
                    ),
                  ],
                ),
              ),
            ),

            // Content
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Animated Logo
                  Container(
                    width: 130,
                    height: 130,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withValues(alpha: 0.05),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.primaryBlue.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Image.asset(
                      'assets/images/app_logo.png',
                      fit: BoxFit.contain,
                    ),
                  )
                      .animate(onPlay: (controller) => controller.repeat())
                      .scale(
                          duration: 1.seconds,
                          curve: Curves.easeInOut,
                          begin: const Offset(1, 1),
                          end: const Offset(1.1, 1.1))
                      .then()
                      .scale(
                          duration: 1.seconds,
                          curve: Curves.easeInOut,
                          begin: const Offset(1.1, 1.1),
                          end: const Offset(1, 1))
                      .shimmer(delay: 800.ms, duration: 1200.ms),

                  const SizedBox(height: 32),

                  // Branding
                  Text(
                    "AtmosVPN",
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1.5,
                          color: Colors.white,
                        ),
                  ).animate().fadeIn(delay: 400.ms).moveY(begin: 20, end: 0),

                  const SizedBox(height: 12),

                  Text(
                    "FAST • PRIVATE • GLOBAL",
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          letterSpacing: 3,
                          fontWeight: FontWeight.bold,
                        ),
                  ).animate().fadeIn(delay: 600.ms),

                  const SizedBox(height: 60),

                  // Loading Indicator
                  const SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AppColors.primaryBlue),
                    ),
                  ).animate().fadeIn(delay: 1.seconds),
                ],
              ),
            ),

            // Version hint at bottom
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  _appVersion,
                  style: const TextStyle(
                    color: Colors.white24,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ).animate().fadeIn(delay: 1.5.seconds),
          ],
        ),
      ),
    );
  }
}
