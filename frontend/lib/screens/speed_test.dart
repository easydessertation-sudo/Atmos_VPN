import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../utils/design_system.dart';
import '../widgets/app_container.dart';

class SpeedTestScreen extends StatefulWidget {
  const SpeedTestScreen({super.key});

  @override
  State<SpeedTestScreen> createState() => _SpeedTestScreenState();
}

class _SpeedTestScreenState extends State<SpeedTestScreen> with TickerProviderStateMixin {
  bool _isTesting = false;
  double _speed = 0.0;
  double _progress = 0.0;
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

  void _runTest() async {
    setState(() {
      _isTesting = true;
      _speed = 0.0;
      _progress = 0.0;
    });

    // Simulate download test
    for (int i = 0; i <= 100; i++) {
      if (!mounted) return;
      await Future.delayed(50.ms);
      setState(() {
        _progress = i / 100;
        // Random-looking speed curve
        if (i < 30) _speed = i * 4.5 + (10 * (i % 3));
        if (i >= 30 && i < 70) _speed = 135 + (20 * (i % 5));
        if (i >= 70) _speed = 158 + (5 * (i % 2));
      });
    }

    setState(() => _isTesting = false);
  }

  @override
  Widget build(BuildContext context) {
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

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: outerGlowSize,
          height: outerGlowSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryBlue.withValues(alpha: _isTesting ? 0.2 : 0.05),
                blurRadius: 40,
                spreadRadius: 10,
              ),
            ],
          ),
        ),
        SizedBox(
          width: gaugeSize,
          height: gaugeSize,
          child: CircularProgressIndicator(
            value: _progress,
            strokeWidth: 12,
            backgroundColor: AppColors.divider,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primaryBlue),
          ),
        ),
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
                color: AppColors.primaryBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'DOWNLOAD',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppColors.primaryBlue, letterSpacing: 1),
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
        Expanded(child: _buildMetric('UPLOAD', '42.8', 'Mbps', Icons.upload_rounded, AppColors.accentPurple)),
        const SizedBox(width: 12),
        Expanded(child: _buildMetric('PING', '18', 'ms', Icons.timer_rounded, AppColors.success)),
        const SizedBox(width: 12),
        Expanded(child: _buildMetric('JITTER', '2', 'ms', Icons.trending_up_rounded, Colors.amber)),
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
