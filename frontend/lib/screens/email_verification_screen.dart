import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../utils/design_system.dart';
import '../utils/api_service.dart';
import '../main.dart';

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  // 6 individual controllers + focus nodes for each digit box
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _isVerifying = false;
  bool _isResending = false;
  String? _error;
  String? _successMessage;

  // Resend countdown — 60 seconds
  int _resendCountdown = 60;
  Timer? _countdownTimer;

  late String _email;
  bool _routeArgsParsed = false;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_routeArgsParsed) {
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      _email = args?['email'] as String? ?? '';
      _routeArgsParsed = true;
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    setState(() => _resendCountdown = 60);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_resendCountdown > 0) {
          _resendCountdown--;
        } else {
          t.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _code => _controllers.map((c) => c.text).join();

  void _onDigitChanged(int index, String value) {
    setState(() => _error = null);

    if (value.length == 6) {
      // User pasted the full code — distribute digits
      for (int i = 0; i < 6; i++) {
        _controllers[i].text = value[i];
      }
      _focusNodes[5].requestFocus();
      _verify();
      return;
    }

    if (value.isNotEmpty && index < 5) {
      // Move forward
      _focusNodes[index + 1].requestFocus();
    }

    if (_code.length == 6) {
      _verify();
    }
  }

  void _onKeyEvent(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      // Move back on backspace when box is empty
      _focusNodes[index - 1].requestFocus();
      _controllers[index - 1].clear();
    }
  }

  Future<void> _verify() async {
    final code = _code;
    if (code.length < 6) {
      setState(() => _error = 'Please enter all 6 digits.');
      return;
    }

    setState(() {
      _isVerifying = true;
      _error = null;
    });

    try {
      final response = await ApiService.verifyEmail(_email, code);

      if (response['success'] == true) {
        if (mounted) {
          await context.read<VPNProvider>().fetchProfile();
          if (mounted) {
            Navigator.pushNamedAndRemoveUntil(
                context, '/dashboard', (route) => false);
          }
        }
      } else {
        // Clear all boxes on failure
        for (final c in _controllers) {
          c.clear();
        }
        _focusNodes[0].requestFocus();
        setState(
          () => _error =
              response['message'] ?? 'Invalid code. Please try again.',
        );
      }
    } catch (e) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _resend() async {
    if (_resendCountdown > 0 || _isResending) return;

    setState(() {
      _isResending = true;
      _error = null;
      _successMessage = null;
    });

    try {
      final response = await ApiService.resendVerification(_email);
      if (mounted) {
        if (response['success'] == true) {
          setState(() =>
              _successMessage = 'A new code has been sent to your email.');
          _startCountdown();
          // Clear boxes for the new code
          for (final c in _controllers) {
            c.clear();
          }
          _focusNodes[0].requestFocus();
        } else {
          setState(() => _error =
              response['message'] ?? 'Could not resend. Try again later.');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Failed to resend. Check your connection.');
      }
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isSmallScreen = screenHeight < 700;

    // Responsive horizontal padding: less on small screens
    final hPad = screenWidth < 360 ? 16.0 : (screenWidth < 420 ? 24.0 : 32.0);
    // Responsive vertical spacing
    final vGap = isSmallScreen ? 16.0 : 28.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      // SingleChildScrollView must be DIRECT child of SafeArea.
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 16),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Icon ──────────────────────────────────────────────────
                  Center(
                    child: Container(
                      width: isSmallScreen ? 68 : 84,
                      height: isSmallScreen ? 68 : 84,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primaryBlue.withValues(alpha: 0.08),
                        border: Border.all(
                          color: AppColors.primaryBlue.withValues(alpha: 0.25),
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        Icons.mark_email_unread_rounded,
                        color: AppColors.primaryBlue,
                        size: isSmallScreen ? 30 : 38,
                      ),
                    ),
                  )
                      .animate()
                      .scale(
                          duration: 500.ms,
                          curve: Curves.elasticOut,
                          begin: const Offset(0.6, 0.6),
                          end: const Offset(1, 1))
                      .fadeIn(),

                  SizedBox(height: vGap),

                  // ── Heading ───────────────────────────────────────────────
                  Text(
                    'Check Your Email',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: isSmallScreen ? 24 : 28,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -1,
                    ),
                  ).animate().fadeIn(delay: 150.ms).moveY(begin: 10, end: 0),

                  const SizedBox(height: 8),

                  Text(
                    'We sent a 6-digit code to',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                  ).animate().fadeIn(delay: 200.ms),

                  const SizedBox(height: 2),

                  Text(
                    _email,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ).animate().fadeIn(delay: 220.ms),

                  SizedBox(height: vGap),

                  // ── Error Banner ───────────────────────────────────────────
                  if (_error != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: AppColors.warning.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              color: AppColors.warning, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(_error!,
                                style: const TextStyle(
                                    color: AppColors.warning,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13)),
                          ),
                        ],
                      ),
                    ).animate().shake().fadeIn(),

                  // ── Success Banner ─────────────────────────────────────────
                  if (_successMessage != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: AppColors.success.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_outline_rounded,
                              color: AppColors.success, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(_successMessage!,
                                style: const TextStyle(
                                    color: AppColors.success,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13)),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(),

                  // ── 6-digit OTP boxes via LayoutBuilder ───────────────────
                  LayoutBuilder(
                    builder: (context, constraints) {
                      // Each box has EdgeInsets.symmetric(horizontal: 4)
                      // = 4px left + 4px right = 8px per box × 6 boxes = 48px
                      // Total consumed space = 48px (padding) only.
                      // The padding already acts as the gap between boxes.
                      const boxPadding = 8.0; // per box (left+right)
                      const numBoxes = 6;
                      final boxWidth =
                          ((constraints.maxWidth - (boxPadding * numBoxes)) /
                                  numBoxes)
                              .clamp(32.0, 56.0);
                      final boxHeight = (boxWidth * 1.22).clamp(40.0, 66.0);
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(
                          6,
                          (i) => _buildDigitBox(i, boxWidth, boxHeight),
                        ),
                      );
                    },
                  ).animate().fadeIn(delay: 300.ms),

                  SizedBox(height: vGap),

                  // ── Verify Button ──────────────────────────────────────────
                  ElevatedButton(
                    onPressed: _isVerifying ? null : _verify,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                          vertical: isSmallScreen ? 14 : 18),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: _isVerifying
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white),
                          )
                        : const Text(
                            'VERIFY EMAIL',
                            style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                                letterSpacing: 1),
                          ),
                  ).animate().fadeIn(delay: 400.ms),

                  SizedBox(height: isSmallScreen ? 16 : 22),

                  // ── Resend ─────────────────────────────────────────────────
                  Center(
                    child: _isResending
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.primaryBlue),
                          )
                        : _resendCountdown > 0
                            ? RichText(
                                textAlign: TextAlign.center,
                                text: TextSpan(
                                  style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 13),
                                  children: [
                                    const TextSpan(
                                        text: "Didn't receive it? Resend in "),
                                    TextSpan(
                                      text: '${_resendCountdown}s',
                                      style: const TextStyle(
                                          color: AppColors.primaryBlue,
                                          fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                              )
                            : GestureDetector(
                                onTap: _resend,
                                child: const Text(
                                  'Resend verification code',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: AppColors.primaryBlue,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    decoration: TextDecoration.underline,
                                    decorationColor: AppColors.primaryBlue,
                                  ),
                                ),
                              ),
                  ).animate().fadeIn(delay: 500.ms),

                  SizedBox(height: isSmallScreen ? 16 : 24),

                  // ── Wrong email hint ───────────────────────────────────────
                  Center(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Text(
                        'Wrong email? Go back',
                        style: TextStyle(
                          color: AppColors.textSecondary.withValues(alpha: 0.6),
                          fontSize: 13,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ).animate().fadeIn(delay: 600.ms),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDigitBox(int index, double boxWidth, double boxHeight) {
    final fontSize = (boxWidth * 0.44).clamp(14.0, 24.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: (event) => _onKeyEvent(index, event),
        child: SizedBox(
          width: boxWidth,
          height: boxHeight,
          child: TextFormField(
            controller: _controllers[index],
            focusNode: _focusNodes[index],
            autofocus: index == 0,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(index == 0 ? 6 : 1),
            ],
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
            ),
            decoration: InputDecoration(
              counterText: '',
              // Zero content padding centres the digit inside the box
              contentPadding: EdgeInsets.zero,
              filled: true,
              fillColor: _controllers[index].text.isNotEmpty
                  ? AppColors.primaryBlue.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.05),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: _controllers[index].text.isNotEmpty
                      ? AppColors.primaryBlue.withValues(alpha: 0.6)
                      : Colors.white.withValues(alpha: 0.12),
                  width: 1.5,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: AppColors.primaryBlue, width: 2),
              ),
              errorBorder: OutlineInputBorder(
                borderSide: const BorderSide(
                    color: AppColors.warning, width: 1.5),
              ),
            ),
            onChanged: (val) => _onDigitChanged(index, val),
          ),
        ),
      ),
    );
  }
}
