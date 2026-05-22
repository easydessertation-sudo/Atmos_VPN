import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import '../utils/design_system.dart';
import '../utils/api_service.dart';
import '../widgets/app_container.dart';
import '../widgets/password_text_field.dart';
import '../main.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  bool _googleInitialized = false;

  static const _googleServerClientId =
      '371315886913-fueubrgdbdj61oilt7jeh2kqid3vs4il.apps.googleusercontent.com';
  static const _iosClientId =
      '371315886913-gftksk78hcd6r9dlkvba96mjk93d7ng6.apps.googleusercontent.com';

  @override
  void initState() {
    super.initState();
    _initGoogleSignIn();
  }

  void _initGoogleSignIn() {
    try {
      GoogleSignIn.instance.initialize(
        serverClientId: _googleServerClientId,
        clientId: Theme.of(context).platform == TargetPlatform.iOS ? _iosClientId : null,
      );
      _googleInitialized = true;
    } catch (_) {
      // Already initialized — safe to ignore
      _googleInitialized = true;
    }
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    // --- Client-side validation ---
    final emailRegex = RegExp(r'^[\w\-.+]+@[\w\-]+\.[a-zA-Z]{2,}$');
    if (email.isEmpty) {
      setState(() => _error = 'Please enter your email address.');
      return;
    }
    if (!emailRegex.hasMatch(email)) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = 'Please enter your password.');
      return;
    }
    if (password.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }
    // --- End validation ---

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await ApiService.login(email, password);

      if (response['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle_outline_rounded,
                      color: Colors.white, size: 20),
                  SizedBox(width: 12),
                  Text('Login Successful! Welcome back.',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
          await context.read<VPNProvider>().fetchProfile();
          if (mounted) {
            Navigator.pushNamedAndRemoveUntil(context, '/dashboard', (route) => false);
          }
        }
      } else {
        setState(() => _error = response['detail'] ??
            response['message'] ??
            'Login failed. Please try again.');
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSocialLogin(String provider) async {
    if (provider != 'Google') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Apple Sign In coming soon!'),
          backgroundColor: Colors.black54,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Ensure GoogleSignIn is fully initialized before authenticating
      try {
        await GoogleSignIn.instance.initialize(
          serverClientId: _googleServerClientId,
        );
      } catch (e) {
        // Initialization warning — non-fatal, continue
      }

      final account = await GoogleSignIn.instance.authenticate();

      if (account == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Google Sign-In failed: App certificate not authorised. Please use Email & Password.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 8),
            ),
          );
        }
        setState(() {
          _isLoading = false;
          _error = 'Google Sign-In failed: App certificate not registered in Google Cloud Console.\n\nDebug SHA-256: e2780eda94bcb1ea5e376519dcdbe853977121aa225d5cc2bbfde58fc7a0038d\n\nPlease use Email & Password to log in.';
        });
        return;
      }

      final idToken = account.authentication.idToken;
      if (idToken == null) {
        setState(() {
          _isLoading = false;
          _error = 'Could not get Google ID token. Please try again.';
        });
        return;
      }

      // Send ID token to our backend
      final response = await ApiService.googleVerify(idToken);

      if (response['success'] == true) {
        if (mounted) {
          final name = response['data']?['user']?['full_name'] ?? 'back';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_outline_rounded,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  Text('Welcome, $name!',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
          await context.read<VPNProvider>().fetchProfile();
          if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/dashboard', (route) => false);
        }
      } else {
        // Check if the backend returned a 500-style message
        final msg = response['message'] as String? ?? '';
        final isServerError = msg.contains('500') ||
            msg.toLowerCase().contains('malformed') ||
            msg.toLowerCase().contains('unreachable');
        setState(() => _error = isServerError
            ? 'Google Sign-In is temporarily unavailable on the server. Please use email & password to log in.'
            : (msg.isNotEmpty
                ? msg
                : 'Google sign-in failed. Please try again.'));
      }
    } catch (e) {
      final msg = e.toString();
      // User cancelled the Google picker — don't show an error
      if (msg.contains('cancel') || msg.contains('sign_in_canceled')) {
        setState(() => _isLoading = false);
        return;
      }
      setState(() => _error = 'Google sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showForgotPasswordDialog(BuildContext context) {
    final emailCtrl = TextEditingController(text: _emailController.text);
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (context, setState) {
        return AlertDialog(
          backgroundColor: AppColors.cardBackground,
          title: const Text('Reset Password',
              style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  'Enter your email address to receive a password reset link.',
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 16),
              TextField(
                controller: emailCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Email Address',
                  labelStyle: TextStyle(color: AppColors.textSecondary),
                  enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: AppColors.divider)),
                  focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: AppColors.primaryBlue)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel',
                    style: TextStyle(color: AppColors.textSecondary))),
            ElevatedButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      if (emailCtrl.text.isEmpty) return;
                      setState(() => isSubmitting = true);
                      final resp =
                          await ApiService.forgotPassword(emailCtrl.text);

                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(resp['success'] == true
                                  ? 'Reset link sent! Check your email.'
                                  : (resp['message'] ??
                                      'Failed to send link'))),
                        );
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
                  : const Text('Send Link'),
            ),
          ],
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: AppContainer(
        maxWidth: 450,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 60.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),

              // Logo/Icon
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      padding: const EdgeInsets.all(10),
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
                    ).animate().scale(curve: Curves.easeOutBack),
                    if (!kIsWeb && MediaQuery.of(context).size.width > 900) ...[
                      const SizedBox(height: 40),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(30),
                        child: Image.network(
                          'https://img.freepik.com/free-vector/shield-with-circuit-lines-digital-security-background_1017-31362.jpg',
                          height: 220,
                          fit: BoxFit.contain,
                          errorBuilder: (c, e, s) => Container(),
                        ),
                      )
                          .animate()
                          .fadeIn(duration: 800.ms)
                          .scale(begin: const Offset(0.9, 0.9)),
                    ] else if (kIsWeb &&
                        MediaQuery.of(context).size.width > 800) ...[
                      const SizedBox(height: 40),
                      // Premium 3D-like Animation for Web
                      Container(
                        height: 220,
                        width: 220,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              AppColors.primaryBlue.withValues(alpha: 0.2),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(
                              Icons.security_rounded,
                              size: 140,
                              color:
                                  AppColors.primaryBlue.withValues(alpha: 0.8),
                            )
                                .animate(onPlay: (c) => c.repeat())
                                .shimmer(duration: 2.seconds)
                                .scale(
                                    duration: 2.seconds,
                                    begin: const Offset(1, 1),
                                    end: const Offset(1.1, 1.1)),
                            Icon(
                              Icons.lock_rounded,
                              size: 40,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ],
                        ),
                      ).animate().fadeIn(duration: 1.seconds),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 32),

              const Text(
                'Welcome Back',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -1),
              ).animate().fadeIn().moveY(begin: 10, end: 0),

              const SizedBox(height: 8),

              const Text(
                'Sign in to continue your secure browsing',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
              ).animate().fadeIn(delay: 200.ms),

              const SizedBox(height: 48),

              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: AppColors.warning.withValues(alpha: 0.2)),
                  ),
                  child: Text(_error!,
                      style: const TextStyle(
                          color: AppColors.warning,
                          fontWeight: FontWeight.w600)),
                ).animate().shake(),

              // Email Field
              _buildTextField(
                controller: _emailController,
                label: 'Email Address',
                icon: Icons.alternate_email_rounded,
              ),

              const SizedBox(height: 20),

              // Password Field
              _buildTextField(
                controller: _passwordController,
                label: 'Password',
                icon: Icons.lock_outline_rounded,
                isPassword: true,
              ),

              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _showForgotPasswordDialog(context),
                  child: const Text('Forgot Password?',
                      style: TextStyle(
                          color: AppColors.primaryBlue,
                          fontWeight: FontWeight.w700)),
                ),
              ),

              const SizedBox(height: 32),

              // Sign In Button
              ElevatedButton(
                onPressed: _isLoading ? null : _login,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 3, color: Colors.white))
                    : const Text('SIGN IN',
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            letterSpacing: 1)),
              ).animate().fadeIn(delay: 400.ms),

              const SizedBox(height: 32),

              // Divider
              Row(
                children: [
                  Expanded(child: Divider(color: AppColors.divider)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text("OR",
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ),
                  Expanded(child: Divider(color: AppColors.divider)),
                ],
              ),

              const SizedBox(height: 32),

              // Social Logins
              _buildSocialButton(
                  'Continue with Google',
                  Icons.g_mobiledata_rounded,
                  () => _handleSocialLogin('Google')),
              const SizedBox(height: 16),
              _buildSocialButton('Continue with Apple', Icons.apple_rounded,
                  () => _handleSocialLogin('Apple')),

              const SizedBox(height: 48),

              // Footer
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Don't have an account?",
                      style: TextStyle(color: AppColors.textSecondary)),
                  TextButton(
                    onPressed: () => Navigator.pushNamed(context, '/signup'),
                    child: const Text('Sign Up',
                        style: TextStyle(
                            color: AppColors.primaryBlue,
                            fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
  }) {
    return PasswordTextField(
      controller: controller,
      label: label,
      icon: icon,
      isPassword: isPassword,
    );
  }

  Widget _buildSocialButton(String label, IconData icon, VoidCallback onTap) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 28),
        label: Text(label,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          side: BorderSide(color: AppColors.divider),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
}
