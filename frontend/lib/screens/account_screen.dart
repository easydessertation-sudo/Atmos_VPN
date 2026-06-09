import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../utils/design_system.dart';
import '../utils/api_service.dart';
import '../widgets/password_text_field.dart';
import '../main.dart';
import '../widgets/app_container.dart';
import 'package:in_app_review/in_app_review.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  bool _isSocialLogin = false;

  @override
  void initState() {
    super.initState();
    _checkLoginType();
    _loadAppVersion();
  }

  String _appVersion = 'Loading...';

  Future<void> _loadAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _appVersion = 'AtmosVPN Version ${packageInfo.version} (Build ${packageInfo.buildNumber})';
      });
    }
  }

  Future<void> _checkLoginType() async {
    final prefs = await SharedPreferences.getInstance();
    final provider = prefs.getString('auth_provider');
    if (provider == 'google' || provider == 'apple') {
      if (mounted) setState(() => _isSocialLogin = true);
    }
  }

  Future<void> _handleLogout(BuildContext context) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppColors.divider, width: 1),
        ),
        title: const Text('Log Out', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        content: const Text(
          'Are you sure you want to log out of your account?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx); // Close dialog
              
              // Perform logout
              try {
                await ApiService.logout();
              } catch (_) {}

              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('access_token');
              await prefs.remove('refresh_token');
              await prefs.remove('auth_provider');
              if (context.mounted) {
                Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Log Out', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context, Map<String, dynamic>? user) {
    final provider = user?['auth_provider']?.toString().toLowerCase();
    if (provider == 'google' || provider == 'apple') {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.cardBackground,
          title: const Text('Social Login', style: TextStyle(color: Colors.white)),
          content: Text(
            'You are signed in with ${provider == 'google' ? 'Google' : 'Apple'}. Password changes are managed via your ${provider == 'google' ? 'Google' : 'Apple'} account.',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

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

  ImageProvider? _getAvatarImage(String url) {
    if (url.isEmpty) return null;
    if (kIsWeb || url.startsWith('http') || url.startsWith('blob:')) {
      return NetworkImage(url);
    } else {
      return FileImage(File(url));
    }
  }

  void _showImageSourceSheet(BuildContext context,
      Function(String) onImagePicked, Function(String) onError) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Select Image Source',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded,
                    color: AppColors.primaryBlue),
                title: const Text('Camera',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final picker = ImagePicker();
                  try {
                    final XFile? image = await picker.pickImage(
                      source: ImageSource.camera,
                      imageQuality: 70,
                      maxWidth: 800,
                    );
                    if (image != null) {
                      onImagePicked(image.path);
                    }
                  } catch (e) {
                    onError('Camera error: $e');
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded,
                    color: AppColors.primaryBlue),
                title: const Text('Gallery',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final picker = ImagePicker();
                  try {
                    final XFile? image = await picker.pickImage(
                      source: ImageSource.gallery,
                      imageQuality: 70,
                      maxWidth: 800,
                    );
                    if (image != null) {
                      onImagePicked(image.path);
                    }
                  } catch (e) {
                    onError('Gallery error: $e');
                  }
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  void _showEditProfileDialog(
      BuildContext context, Map<String, dynamic>? user) {
    final vpn = context.read<VPNProvider>();
    final nameCtrl = TextEditingController(text: user?['full_name'] ?? '');
    bool isSubmitting = false;
    String? dialogError;

    String selectedAvatar = user?['avatar_url'] ?? '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (context, setState) {
        return AlertDialog(
          backgroundColor: AppColors.cardBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: AppColors.divider, width: 1),
          ),
          title: const Row(
            children: [
              Icon(Icons.edit_rounded, color: AppColors.primaryBlue, size: 24),
              SizedBox(width: 10),
              Text(
                'Edit Profile',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (dialogError != null)
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 16),
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
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [AppColors.primaryBlue, AppColors.neonCyan],
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 44,
                      backgroundColor: AppColors.background,
                      backgroundImage: _getAvatarImage(selectedAvatar),
                      child: selectedAvatar.isEmpty
                          ? const Icon(Icons.person_rounded,
                              size: 44, color: Colors.white)
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: TextButton.icon(
                      onPressed: () {
                        _showImageSourceSheet(context, (path) {
                          setState(() {
                            selectedAvatar = path;
                          });
                        }, (errorMsg) {
                          setState(() {
                            dialogError = errorMsg;
                          });
                        });
                      },
                      icon: const Icon(Icons.cloud_upload_rounded,
                          color: AppColors.primaryBlue),
                      label: const Text(
                        'Upload Image',
                        style: TextStyle(
                          color: AppColors.primaryBlue,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        backgroundColor:
                            AppColors.primaryBlue.withValues(alpha: 0.1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'FULL NAME',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.person_outline_rounded,
                        color: AppColors.textSecondary, size: 20),
                    hintText: 'Enter your full name',
                    hintStyle: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 14),
                    filled: true,
                    fillColor: AppColors.background,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.divider),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: AppColors.primaryBlue),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actionsPadding:
              const EdgeInsets.only(left: 24, right: 24, bottom: 24),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      if (nameCtrl.text.trim().isEmpty) {
                        setState(
                            () => dialogError = 'Full name cannot be empty.');
                        return;
                      }

                      setState(() {
                        isSubmitting = true;
                        dialogError = null;
                      });

                      // Call the real API
                      final isUrl = selectedAvatar.startsWith('http') || selectedAvatar.startsWith('https');
                      final avatarPath = isUrl ? null : (selectedAvatar.isNotEmpty ? selectedAvatar : null);
                      
                      final resp = await ApiService.updateProfile(
                        fullName: nameCtrl.text.trim(),
                        avatarPath: avatarPath,
                      );

                      if (resp['success'] == true) {
                        // 1. Stop buffering
                        setState(() {
                          isSubmitting = false;
                        });

                        // 2. Pop the dialog immediately while the context is completely safe
                        if (context.mounted) {
                          Navigator.of(context, rootNavigator: true).pop();
                          
                          // Show success message
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Row(
                                children: [
                                  Icon(Icons.check_circle_outline_rounded,
                                      color: Colors.white, size: 18),
                                  SizedBox(width: 10),
                                  Text('Profile updated successfully!',
                                      style:
                                          TextStyle(fontWeight: FontWeight.bold)),
                                ],
                              ),
                              backgroundColor: AppColors.success,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }

                        // 3. Update the global state last (this rebuilds the background UI)
                        final updatedUser = resp['data']?['user'];
                        if (updatedUser != null && updatedUser['avatar_url'] != null) {
                           vpn.updateProfileLocal(
                             fullName: updatedUser['full_name'],
                             avatarUrl: updatedUser['avatar_url'],
                           );
                        } else {
                           vpn.updateProfileLocal(
                             fullName: nameCtrl.text.trim(),
                             avatarUrl: isUrl ? selectedAvatar : '',
                           );
                        }
                      } else {
                        setState(() {
                          isSubmitting = false;
                          dialogError = resp['message'] ?? 'Failed to update profile.';
                        });
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Save Changes',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
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
        automaticallyImplyLeading: false,
        title: const Text('My Account',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
      ),
      body: AppContainer(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            children: [
              _buildProfileHeader(context, user)
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
                      () => _showChangePasswordDialog(context, user)),
                ],
              ).animate().fadeIn(delay: 400.ms),
              const SizedBox(height: 24),
              _buildMenuSection(
                'PREFERENCES',
                [
                  _menuItem('Notifications', Icons.notifications_rounded,
                      () => Navigator.pushNamed(context, '/notifications')),
                  _menuItem('Privacy Settings', Icons.fingerprint_rounded,
                      () => Navigator.pushNamed(context, '/privacy')),
                  _menuItem('Rate Us', Icons.star_rate_rounded, () async {
                    final InAppReview inAppReview = InAppReview.instance;
                    if (await inAppReview.isAvailable()) {
                      // Note: appStoreId is only needed for iOS. Leaving empty defaults to the current app's ID if configured correctly on iOS.
                      inAppReview.openStoreListing();
                    }
                  }),
                ],
              ).animate().fadeIn(delay: 500.ms),
              const SizedBox(height: 48),
              _buildLogoutButton(context).animate().fadeIn(delay: 600.ms),
              const SizedBox(height: 20),
              Text(
                _appVersion,
                style: const TextStyle(
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

  Widget _buildProfileHeader(BuildContext context, Map<String, dynamic>? user) {
    final name = user?['full_name'] ?? user?['email']?.split('@')[0] ?? 'User';
    final email = user?['email'] ?? 'No email associated';
    final avatarUrl = user?['avatar_url']?.toString() ?? '';

    return Column(
      children: [
        GestureDetector(
          onTap: () => _showEditProfileDialog(context, user),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                        colors: [AppColors.primaryBlue, AppColors.neonCyan]),
                  ),
                  child: CircleAvatar(
                    radius: 50,
                    backgroundColor: AppColors.background,
                    backgroundImage: _getAvatarImage(avatarUrl),
                    child: avatarUrl.isEmpty
                        ? const Icon(Icons.person_rounded,
                            size: 50, color: Colors.white)
                        : null,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                      color: AppColors.success, shape: BoxShape.circle),
                  child: const Icon(Icons.edit_rounded,
                      size: 12, color: Colors.white),
                ),
              ],
            ),
          ),
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
                onPressed: () =>
                    Navigator.pushNamed(context, '/account/pricing'),
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
