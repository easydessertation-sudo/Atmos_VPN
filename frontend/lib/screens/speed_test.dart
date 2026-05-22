import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../utils/design_system.dart';
import '../widgets/app_container.dart';
import '../utils/api_service.dart';
import '../utils/ad_manager.dart';
import '../main.dart';

class SpeedTestScreen extends StatefulWidget {
  const SpeedTestScreen({super.key});

  @override
  State<SpeedTestScreen> createState() => _SpeedTestScreenState();
}

class _SpeedTestScreenState extends State<SpeedTestScreen> with TickerProviderStateMixin {
  bool _isTesting = false;
  double _speed = 0.0;      // displayed Mbps number
  double _progress = 0.0;  // arc fill 0.0 → 1.0
  double _maxSpeed = 200.0; // gauge max — auto-scaled after test
  String _uploadSpeed = '--';
  String _ping = '--';
  String _jitter = '--';
  String? _error;
  late AnimationController _gaugeController;

  @override
  void initState() {
    super.initState();
    _gaugeController = AnimationController(vsync: this, duration: 1.seconds);
  }

  @override
  void dispose() {
    _gaugeController.dispose();
    super.dispose();
  }

  /// Smoothly animate _speed and _progress from current to target
  Future<void> _animateTo(double targetSpeed, {int steps = 30, int msPerStep = 16}) async {
    final startSpeed = _speed;
    final startProgress = _progress;
    final targetProgress = (targetSpeed / _maxSpeed).clamp(0.0, 1.0);
    for (int i = 1; i <= steps; i++) {
      if (!mounted) return;
      await Future.delayed(Duration(milliseconds: msPerStep));
      final t = i / steps;
      // ease-out curve
      final ease = 1 - (1 - t) * (1 - t);
      setState(() {
        _speed = startSpeed + (targetSpeed - startSpeed) * ease;
        _progress = startProgress + (targetProgress - startProgress) * ease;
      });
    }
  }

  void _runTest() async {
    final vpn = context.read<VPNProvider>();
    final plan = vpn.userData?['plan']?.toString() ?? 'free';

    void startRealTest() async {
      setState(() {
        _isTesting = true;
        _speed = 0.0;
        _progress = 0.0;
        _maxSpeed = 200.0;
        _uploadSpeed = '--';
        _ping = '--';
        _jitter = '--';
        _error = null;
      });

    // Start API call immediately (runs in background)
    final apiFuture = ApiService.runSpeedTest();

    // --- Phase 1: Ramp up to simulate testing (0 → ~60% of max) ---
    await _animateTo(_maxSpeed * 0.60, steps: 60, msPerStep: 25);

    // --- Phase 2: Fluctuate while waiting for real result ---
    bool apiDone = false;
    apiFuture.then((_) => apiDone = true);
    for (int i = 0; i < 40 && !apiDone; i++) {
      if (!mounted) return;
      final fluctuation = _maxSpeed * 0.60 + (20.0 * ((i % 6) - 3));
      await _animateTo(fluctuation, steps: 8, msPerStep: 20);
    }

    try {
      final response = await apiFuture;
      if (response['success'] == true) {
        final data = response['data'];
        final realSpeed = (data['download_mbps'] as num? ?? 0).toDouble();

        // Auto-scale max to fit real result with headroom
        if (realSpeed > _maxSpeed * 0.85) {
          setState(() => _maxSpeed = (realSpeed * 1.3).ceilToDouble());
        }

        // --- Phase 3: Animate to real speed ---
        await _animateTo(realSpeed, steps: 50, msPerStep: 20);

        // Set final values
        if (mounted) {
          setState(() {
            _speed = realSpeed;
            _progress = (realSpeed / _maxSpeed).clamp(0.0, 1.0);
            _uploadSpeed = ((data['upload_mbps'] as num?) ?? 0).toDouble().toStringAsFixed(1);
            _ping = (data['ping_ms'] ?? data['latency_ms'] ?? '--').toString();
            _jitter = ((data['jitter_ms'] as num?) ?? (data['latency_ms'] as num?) ?? 0).toDouble().toStringAsFixed(1);
          });
        }
      } else {
        throw Exception(response['message'] ?? 'Speed test failed');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _progress = 0.0;
          _speed = 0.0;
          _uploadSpeed = '--';
          _ping = '--';
          _jitter = '--';
          _error = e.toString().replaceAll('Exception: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
    } // End startRealTest

    if (plan == 'free') {
      AdManager.showInterstitialAd(onAdDismissed: startRealTest);
    } else {
      startRealTest();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('Speed Test', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
      ),
      body: AppContainer(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompactHeight = constraints.maxHeight < 760;

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  children: [
                    SizedBox(height: isCompactHeight ? 20 : 40),
                    Center(
                      child: _buildHighTechGauge(isCompact: isCompactHeight),
                    ),
                    SizedBox(height: isCompactHeight ? 32 : 60),
                    _buildMetricsRow(),
                    SizedBox(height: isCompactHeight ? 24 : 32),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.cardBackground,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, color: AppColors.primaryBlue),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Text(
                              'This test measures the connection between your device and our nearest server location.',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.2, end: 0),
                    SizedBox(height: isCompactHeight ? 20 : 32),
                    MouseRegion(
                      cursor: _isTesting ? SystemMouseCursors.basic : SystemMouseCursors.click,
                      child: ElevatedButton(
                        onPressed: _isTesting ? null : _runTest,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                          minimumSize: const Size(double.infinity, 60),
                        ),
                        child: _isTesting
                            ? const Text('TESTING...', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5))
                            : const Text('START SPEED TEST', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                      ),
                    ).animate().fadeIn(delay: 500.ms),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, color: AppColors.warning, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(_error!, style: const TextStyle(color: AppColors.warning, fontSize: 13)),
                            ),
                          ],
                        ),
                      ),
                    ],
                    SizedBox(height: isCompactHeight ? 24 : 40),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
//////////////////////////////////////////////////
  Widget _buildHighTechGauge({bool isCompact = false}) {
    final outerGlowSize = isCompact ? 240.0 : 280.0;
    final gaugeSize = isCompact ? 220.0 : 260.0;

    // Dynamic color based on speed
    final Color arcColor;
    final String qualityLabel;
    if (_speed == 0 && !_isTesting) {
      arcColor = AppColors.divider;
      qualityLabel = 'TAP TO TEST';
    } else if (_speed < 10) {
      arcColor = AppColors.warning;
      qualityLabel = 'SLOW';
    } else if (_speed < 50) {
      arcColor = Colors.amber;
      qualityLabel = 'GOOD';
    } else if (_speed < 100) {
      arcColor = AppColors.primaryBlue;
      qualityLabel = 'FAST';
    } else {
      arcColor = AppColors.success;
      qualityLabel = 'EXCELLENT';
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        // Glow
        Container(
          width: outerGlowSize,
          height: outerGlowSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: arcColor.withValues(alpha: _isTesting ? 0.25 : 0.08),
                blurRadius: 50,
                spreadRadius: 15,
              ),
            ],
          ),
        ),
        // Gauge arc
        SizedBox(
          width: gaugeSize,
          height: gaugeSize,
          child: CircularProgressIndicator(
            value: _progress,
            strokeWidth: 14,
            strokeCap: StrokeCap.round,
            backgroundColor: AppColors.divider,
            valueColor: AlwaysStoppedAnimation<Color>(arcColor),
          ),
        ),
        // Center content
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _speed.toStringAsFixed(1),
              style: TextStyle(
                fontSize: isCompact ? 52 : 64,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: -2,
              ),
            ).animate(target: _isTesting ? 1 : 0).shimmer(duration: 1.seconds),
            Text(
              'Mbps',
              style: TextStyle(
                fontSize: isCompact ? 18 : 20,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: arcColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _isTesting ? 'TESTING...' : qualityLabel,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: arcColor, letterSpacing: 1),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricsRow() {
    return Row(
      children: [
        Expanded(child: _buildMetric('UPLOAD', _uploadSpeed, 'Mbps', Icons.upload_rounded, AppColors.accentPurple)),
        const SizedBox(width: 12),
        Expanded(child: _buildMetric('PING', _ping, 'ms', Icons.timer_rounded, AppColors.success)),
        const SizedBox(width: 12),
        Expanded(child: _buildMetric('JITTER', _jitter, 'ms', Icons.trending_up_rounded, Colors.amber)),
      ],
    ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildMetric(String label, String value, String unit, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 12),
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20)),
                const SizedBox(width: 2),
                Text(unit, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
