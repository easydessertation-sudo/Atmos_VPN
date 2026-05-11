import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/design_system.dart';
import '../utils/api_service.dart';
import '../widgets/password_text_field.dart';
import '../main.dart';
import '../widgets/app_container.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  Future<void> _handleLogout(BuildContext context) async {
    try {
      await ApiService.logout();
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    if (context.mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  void _showChangePasswordDialog(BuildContext context) {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    bool isSubmitting = false;
    String? dialogError;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (context, setState) {
        return AlertDialog(
          backgroundColor: AppColors.cardBackground,
          title: const Text('Change Password',
              style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dialogError != null)
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppColors.warning.withValues(alpha: 0.3)),
                  ),
                  child: Text(dialogError!,
                      style: const TextStyle(
                          color: AppColors.warning, fontSize: 12)),
                ),
              PasswordTextField(
                controller: oldCtrl,
                label: 'Current Password',
                icon: Icons.lock_outline_rounded,
                isPassword: true,
              ),
              const SizedBox(height: 12),
              PasswordTextField(
                controller: newCtrl,
                label: 'New Password (min 8 chars)',
                icon: Icons.lock_reset_rounded,
                isPassword: true,
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      // --- Validation ---
                      if (oldCtrl.text.isEmpty) {
                        setState(() => dialogError =
                            'Please enter your current password.');
                        return;
                      }
                      if (newCtrl.text.isEmpty) {
                        setState(
                            () => dialogError = 'Please enter a new password.');
                        return;
                      }
                      if (newCtrl.text.length < 8) {
                        setState(() => dialogError =
                            'New password must be at least 8 characters.');
                        return;
                      }
                      if (oldCtrl.text == newCtrl.text) {
                        setState(() => dialogError =
                            'New password must be different from current password.');
                        return;
                      }
                      // --- End Validation ---

                      setState(() {
                        isSubmitting = true;
                        dialogError = null;
                      });
                      final resp = await ApiService.changePassword(
                          oldCtrl.text, newCtrl.text);
                      if (resp['success'] == true) {
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Row(children: [
                                Icon(Icons.check_circle_outline_rounded,
                                    color: Colors.white, size: 18),
                                SizedBox(width: 10),
                                Text('Password updated successfully!',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                              ]),
                              backgroundColor: AppColors.success,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      } else {
                        // Parse specific backend error messages
                        final msg =
                            (resp['message'] ?? '').toString().toLowerCase();
                        String friendlyError;
                        if (msg.contains('incorrect') ||
                            msg.contains('wrong') ||
                            msg.contains('invalid') ||
                            msg.contains('current')) {
                          friendlyError =
                              'Current password is incorrect. Please try again.';
                        } else if (msg.contains('same') ||
                            msg.contains('match')) {
                          friendlyError =
                              'New password cannot be the same as the current password.';
                        } else if (msg.contains('weak') ||
                            msg.contains('short')) {
                          friendlyError =
                              'New password is too weak. Use at least 8 characters.';
                        } else {
                          friendlyError = resp['message'] ??
                              'Failed to update password. Please try again.';
                        }
                        setState(() {
                          isSubmitting = false;
                          dialogError = friendlyError;
                        });
                      }
                    },
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: Colors.white),
              child: isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Update'),
            ),
          ],
        );
      }),
    );
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
        title: const Text('My Account',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
      ),
      body: AppContainer(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            children: [
              _buildProfileHeader(user)
                  .animate()
                  .fadeIn()
                  .scale(begin: const Offset(0.9, 0.9)),
              const SizedBox(height: 32),
              _buildSubscriptionCard(context, user)
                  .animate()
                  .fadeIn(delay: 200.ms)
                  .slideX(begin: 0.1, end: 0),
              const SizedBox(height: 32),
              _buildMenuSection(
                'PERSONAL SETTINGS',
                [
                  _menuItem('Device Management', Icons.devices_rounded,
                      () => Navigator.pushNamed(context, '/account/devices')),
                  _menuItem(
                      'Billing & Subscriptions',
                      Icons.credit_card_rounded,
                      () => Navigator.pushNamed(context, '/account/billing')),
                  _menuItem('Security Checkup', Icons.verified_user_rounded,
                      () => Navigator.pushNamed(context, '/security')),
                  _menuItem('Change Password', Icons.password_rounded,
                      () => _showChangePasswordDialog(context)),
                ],
              ).animate().fadeIn(delay: 400.ms),
              const SizedBox(height: 24),
              _buildMenuSection(
                'PREFERENCES',
                [
                  _menuItem('Notifications', Icons.notifications_rounded,
                      () => Navigator.pushNamed(context, '/notifications')),
                  _menuItem('Privacy Settings', Icons.fingerprint_rounded,
                      () => Navigator.pushNamed(context, '/privacy-policy')),
                ],
              ).animate().fadeIn(delay: 500.ms),
              const SizedBox(height: 48),
              _buildLogoutButton(context).animate().fadeIn(delay: 600.ms),
              const SizedBox(height: 20),
              const Text(
                'Atmos VPN Version 1.0.0 (Build 45)',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
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
                gradient: LinearGradient(
                    colors: [AppColors.primaryBlue, AppColors.neonCyan]),
              ),
              child: const CircleAvatar(
                radius: 50,
                backgroundColor: AppColors.background,
                child:
                    Icon(Icons.person_rounded, size: 50, color: Colors.white),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                  color: AppColors.success, shape: BoxShape.circle),
              child:
                  const Icon(Icons.edit_rounded, size: 12, color: Colors.white),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          name,
          style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -0.5),
        ),
        Text(email,
            style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildSubscriptionCard(
      BuildContext context, Map<String, dynamic>? user) {
    final plan = user?['plan']?.toString() ?? 'free';
    final isFree = plan == 'free';
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
            child: Icon(
                isFree ? Icons.star_outline_rounded : Icons.verified_rounded,
                color: color,
                size: 28),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${plan.toUpperCase()} PLAN',
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      letterSpacing: 1.5),
                ),
                Text(
                  isFree ? 'Limited Access' : 'Full Protection Active',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  minimumSize: Size.zero,
                  elevation: 0,
                ),
                child: const Text('UPGRADE',
                    style:
                        TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
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
            style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w900,
                fontSize: 12,
                letterSpacing: 1),
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
      title: Text(title,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
      trailing: const Icon(Icons.chevron_right_rounded,
          color: AppColors.textSecondary, size: 20),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: TextButton.icon(
        onPressed: () => _handleLogout(context),
        icon: const Icon(Icons.logout_rounded,
            color: AppColors.warning, size: 18),
        label: const Text('LOG OUT',
            style: TextStyle(
                color: AppColors.warning,
                fontWeight: FontWeight.w900,
                fontSize: 14,
                letterSpacing: 1)),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          backgroundColor: AppColors.warning.withValues(alpha: 0.05),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
}
