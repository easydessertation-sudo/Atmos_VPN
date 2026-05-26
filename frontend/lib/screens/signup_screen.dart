import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../utils/design_system.dart';
import '../utils/api_service.dart';
import '../widgets/password_text_field.dart';
import '../widgets/app_container.dart';
import '../main.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  Future<void> _signup() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    // --- Client-side validation ---
    final emailRegex = RegExp(r'^[\w\-.+]+@[\w\-]+\.[a-zA-Z]{2,}$');
    if (name.isEmpty) {
      setState(() => _error = 'Please enter your name.');
      return;
    }
    if (email.isEmpty) {
      setState(() => _error = 'Please enter your email address.');
      return;
    }
    if (!emailRegex.hasMatch(email)) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = 'Please enter a password.');
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
      final response = await ApiService.register(email, password, name);

      if (response['success'] == true &&
          response['data']?['requires_verification'] == true) {
        if (mounted) {
          // Navigate to email verification screen — account not created yet
          Navigator.pushNamed(
            context,
            '/verify-email',
            arguments: {'email': email},
          );
        }
      } else if (response['success'] == true) {
        // Fallback: backend returned success without verification step
        if (mounted) {
          await context.read<VPNProvider>().fetchProfile();
          Navigator.pushNamedAndRemoveUntil(
              context, '/dashboard', (route) => false);
        }
      } else {
        setState(() => _error = response['detail'] ??
            response['message'] ??
            'Signup failed. Please try again.');
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSocialLogin(String provider) async {
    if (provider == 'Apple') {
      setState(() {
        _isLoading = true;
        _error = null;
      });
      try {
        final credential = await SignInWithApple.getAppleIDCredential(
          scopes: [
            AppleIDAuthorizationScopes.email,
            AppleIDAuthorizationScopes.fullName,
          ],
        );

        final idToken = credential.identityToken;
        if (idToken == null) {
          setState(() {
            _isLoading = false;
            _error = 'Could not get Apple ID token. Please try again.';
          });
          return;
        }

        final email = credential.email;
        final fullName = credential.givenName != null ? '${credential.givenName} ${credential.familyName ?? ''}'.trim() : null;

        final response = await ApiService.appleVerify(idToken, email: email, fullName: fullName);

        if (response['success'] == true) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.check_circle_outline_rounded,
                        color: Colors.white, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        response['data']?['is_new_user'] == true
                            ? 'Account created! Welcome to AtmosVPN.'
                            : 'Welcome back, ${response['data']?['user']?['full_name'] ?? ''}!',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
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
          final msg = response['message'] as String? ?? '';
          setState(() => _error = msg.isNotEmpty ? msg : 'Apple sign-up failed. Please try again.');
        }
      } catch (e) {
        if (e is SignInWithAppleAuthorizationException && e.code == AuthorizationErrorCode.canceled) {
           setState(() => _isLoading = false);
           return;
        }
        setState(() => _error = 'Apple sign-up failed: $e');
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      const serverClientId = '371315886913-fueubrgdbdj61oilt7jeh2kqid3vs4il.apps.googleusercontent.com';
      const iosClientId = '371315886913-gftksk78hcd6r9dlkvba96mjk93d7ng6.apps.googleusercontent.com';
      try {
        await GoogleSignIn.instance.initialize(
          serverClientId: serverClientId,
          clientId: Theme.of(context).platform == TargetPlatform.iOS ? iosClientId : null,
        );
      } catch (e) {
        // Initialization warning — non-fatal, continue
      }

      final account = await GoogleSignIn.instance.authenticate();

      if (account == null) {
        setState(() {
          _isLoading = false;
          _error = 'Google Sign-In returned no account. This usually happens if the user cancelled or if there is a SHA-1 fingerprint mismatch in Firebase Console (check oauth_client in google-services.json).';
        });
        return;
      }

      final idToken = account.authentication.idToken;

      if (idToken == null) {
        setState(() {
          _isLoading = false;
          _error = 'Google sign-up failed. Please try again.';
        });
        return;
      }

      final response = await ApiService.googleVerify(idToken);

      if (response['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_outline_rounded,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      response['data']['is_new_user'] == true
                          ? 'Account created! Welcome to AtmosVPN.'
                          : 'Welcome back, ${response['data']['user']['full_name'] ?? ''}!',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
          await context.read<VPNProvider>().fetchProfile();
          if (mounted)
            Navigator.pushNamedAndRemoveUntil(
                context, '/dashboard', (route) => false);
        }
      } else {
        setState(() => _error =
            response['message'] ?? 'Google sign-up failed. Please try again.');
      }
    } catch (e) {
      setState(() => _error = 'Google sign-up failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: AppContainer(
        maxWidth: 450,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              const Text(
                'Create Account',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -1),
              ).animate().fadeIn().moveY(begin: 10, end: 0),

              const SizedBox(height: 8),

              const Text(
                'Join the premium secure network today',
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

              // Name Field
              _buildTextField(
                controller: _nameController,
                label: 'Full Name',
                icon: Icons.person_outline_rounded,
              ),

              const SizedBox(height: 20),

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

              const SizedBox(height: 40),

              // Create Account Button
              ElevatedButton(
                onPressed: _isLoading ? null : _signup,
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
                    : const Text('CREATE ACCOUNT',
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            letterSpacing: 1)),
              ).animate().fadeIn(delay: 400.ms),

              const SizedBox(height: 32),

              const Text(
                "By signing up, you agree to our Terms of Service and Privacy Policy.",
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),

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
                  'Sign up with Google',
                  Icons.g_mobiledata_rounded,
                  () => _handleSocialLogin('Google')),
              if (Theme.of(context).platform != TargetPlatform.android) ...[
                const SizedBox(height: 16),
                _buildSocialButton('Sign up with Apple', Icons.apple_rounded,
                    () => _handleSocialLogin('Apple')),
              ],

              const SizedBox(height: 48),

              // Footer
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Already have an account?",
                      style: TextStyle(color: AppColors.textSecondary)),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Sign In',
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
