import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../utils/design_system.dart';
import '../utils/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _handleStartup();
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
        final userData = await ApiService.getMe()
            .timeout(const Duration(seconds: 5));
        if (!mounted) return;
        if (userData['success'] == true) {
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
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primaryBlue.withValues(alpha: 0.2),
                    ),
                  ),
                  child: const Icon(
                    Icons.shield_rounded,
                    size: 80,
                    color: AppColors.primaryBlue,
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
                  "Atmos VPN",
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
            bottom: 40,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Text(
                  "PROTECTING YOUR DIGITAL LIFE",
                  style: TextStyle(
                    color: AppColors.textSecondary.withValues(alpha: 0.3),
                    fontSize: 10,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "v1.0.0",
                  style: TextStyle(
                    color: AppColors.textSecondary.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(delay: 1.5.seconds),
        ],
      ),
    );
  }
}
