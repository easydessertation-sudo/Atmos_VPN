import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/design_system.dart';
import '../widgets/app_container.dart';
import '../main.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  Future<void> _handleLogout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    if (context.mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vpn = context.watch<VPNProvider>();
    final user = vpn.userData;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        title: const Text('My Account', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
      ),
      body: AppContainer(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            children: [
              _buildProfileHeader(user).animate().fadeIn().scale(begin: const Offset(0.9, 0.9)),
              const SizedBox(height: 32),
              _buildSubscriptionCard(context, vpn.isFreeUser).animate().fadeIn(delay: 200.ms).slideX(begin: 0.1, end: 0),
              const SizedBox(height: 32),
              _buildMenuSection(
                'PERSONAL SETTINGS',
                [
                  _menuItem('Device Management', Icons.devices_rounded,
                      () => Navigator.pushNamed(context, '/account/devices')),
                  _menuItem('Billing & Subscriptions', Icons.credit_card_rounded,
                      () => Navigator.pushNamed(context, '/account/billing')),
                  _menuItem('Security Checkup', Icons.verified_user_rounded,
                      () => Navigator.pushNamed(context, '/security')),
                ],
              ).animate().fadeIn(delay: 400.ms),
              const SizedBox(height: 24),
              _buildMenuSection(
                'PREFERENCES',
                [
                  _menuItem('App Appearance', Icons.palette_rounded, () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Theme settings coming soon!')),
                    );
                  }),
                  _menuItem('Notifications', Icons.notifications_rounded, () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Notification settings coming soon!')),
                    );
                  }),
                  _menuItem('Privacy Settings', Icons.fingerprint_rounded,
                      () => Navigator.pushNamed(context, '/privacy-policy')),
                ],
              ).animate().fadeIn(delay: 500.ms),
              const SizedBox(height: 48),
              _buildLogoutButton(context).animate().fadeIn(delay: 600.ms),
              const SizedBox(height: 20),
              const Text(
                'SecureVPN Version 1.0.0 (Build 45)',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader(Map<String, dynamic>? user) {
    final name = user?['username'] ?? user?['email']?.split('@')[0] ?? 'User';
    final email = user?['email'] ?? 'No email associated';
    
    return Column(
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [AppColors.primaryBlue, AppColors.neonCyan]),
              ),
              child: const CircleAvatar(
                radius: 50,
                backgroundColor: AppColors.background,
                child: Icon(Icons.person_rounded, size: 50, color: Colors.white),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
              child: const Icon(Icons.edit_rounded, size: 12, color: Colors.white),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          name,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5),
        ),
        Text(email, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildSubscriptionCard(BuildContext context, bool isFree) {
    final color = isFree ? AppColors.primaryBlue : AppColors.success;
    
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(isFree ? Icons.star_outline_rounded : Icons.verified_rounded, color: color, size: 28),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isFree ? 'FREE PLAN' : 'PREMIUM PRO',
                  style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.5),
                ),
                Text(
                  isFree ? 'Limited Access' : 'Full Protection Active',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ],
            ),
          ),
          if (isFree)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: ElevatedButton(
                onPressed: () => Navigator.pushNamed(context, '/pricing'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  minimumSize: Size.zero,
                  elevation: 0,
                ),
                child: const Text('UPGRADE', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMenuSection(String title, List<Widget> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            title,
            style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(children: items),
        ),
      ],
    );
  }

  Widget _menuItem(String title, IconData icon, VoidCallback onTap) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Icon(icon, color: AppColors.textSecondary, size: 22),
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary, size: 20),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: TextButton.icon(
        onPressed: () => _handleLogout(context),
        icon: const Icon(Icons.logout_rounded, color: AppColors.warning, size: 18),
        label: const Text('LOG OUT', style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1)),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          backgroundColor: AppColors.warning.withValues(alpha: 0.05),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
}
