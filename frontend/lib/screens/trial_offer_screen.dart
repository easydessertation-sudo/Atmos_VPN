import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/design_system.dart';
import '../widgets/app_container.dart';

class TrialOfferScreen extends StatelessWidget {
  const TrialOfferScreen({super.key});

  Future<void> _navigateNext(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    if (context.mounted) {
      if (token != null && token.isNotEmpty) {
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: AppContainer(
        child: Stack(
          children: [
            // Close Button
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                onPressed: () => _navigateNext(context),
              ),
            ),

            SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 60.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                  const SizedBox(height: 40),
                  
                  // Title
                  Text(
                    "Secure Your Internet\nin One Tap",
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ).animate().fadeIn().moveY(begin: -20, end: 0),

                  const SizedBox(height: 40),

                  // Hero Animation (Shield)
                  Center(
                    child: Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primaryBlue.withValues(alpha: 0.1),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryBlue.withValues(alpha: 0.2),
                            blurRadius: 50,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.verified_user_rounded,
                        size: 90,
                        color: AppColors.primaryBlue,
                      ),
                    ),
                  ).animate().scale(delay: 200.ms, duration: 600.ms, curve: Curves.easeOutBack).shimmer(delay: 1.seconds, duration: 2.seconds),

                  const SizedBox(height: 50),

                  // Benefits
                  _buildBenefit(Icons.lock_outline_rounded, "AES-256 Encryption"),
                  _buildBenefit(Icons.public_rounded, "90+ Global Servers"),
                  _buildBenefit(Icons.bolt_rounded, "Ultra-Fast Speed"),

                  const SizedBox(height: 40),

                  // Action Buttons
                  ElevatedButton(
                    onPressed: () {
                      // Trigger Trial Start
                      _navigateNext(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 60),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: const Text(
                      "START 7-DAY FREE TRIAL",
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                  ).animate().fadeIn(delay: 800.ms).scale(delay: 800.ms),

                  const SizedBox(height: 16),

                  Text(
                    "₹450/month billed yearly",
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),

                  const SizedBox(height: 24),

                  TextButton(
                    onPressed: () => _navigateNext(context),
                    child: const Text(
                      "Continue with free version",
                      style: TextStyle(color: AppColors.primaryBlue, decoration: TextDecoration.underline),
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                ],
              ),
            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBenefit(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.primaryBlue, size: 24),
          const SizedBox(width: 16),
          Text(
            text,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 500.ms).moveX(begin: -20, end: 0);
  }
}
