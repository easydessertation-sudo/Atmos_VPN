import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../utils/design_system.dart';
import '../widgets/app_container.dart';

class SecurityCenterScreen extends StatefulWidget {
  const SecurityCenterScreen({super.key});

  @override
  State<SecurityCenterScreen> createState() => _SecurityCenterScreenState();
}

class _SecurityCenterScreenState extends State<SecurityCenterScreen> {
  final Map<String, bool> _toggles = {
    'Kill Switch': true,
    'DNS Leak Guard': true,
    'Auto WiFi Shield': false,
    'Ad & Tracker Blocker': true,
    'Malware Protection': true,
    'Dark Web Monitor': false,
    'Split Tunneling': false,
  };

  int get _score {
    final active = _toggles.values.where((v) => v).length;
    return (active / _toggles.length * 100).round();
  }

  Color get _scoreColor {
    if (_score >= 80) return AppColors.success;
    if (_score >= 50) return AppColors.warning;
    return Colors.red;
  }

  String get _scoreLabel {
    if (_score >= 80) return 'Highly Secure';
    if (_score >= 50) return 'Moderate';
    return 'Vulnerable';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Security Center', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Icon(Icons.verified_user_rounded, color: _scoreColor, size: 22),
          ),
        ],
      ),
      body: AppContainer(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            children: [
              _buildScoreCard().animate().fadeIn().scale(begin: const Offset(0.95, 0.95)),
              const SizedBox(height: 32),
              _buildProtectionToggles().animate().fadeIn(delay: 200.ms),
              const SizedBox(height: 32),
              _buildAiTools().animate().fadeIn(delay: 400.ms),
              const SizedBox(height: 32),
              _buildProtocolCard().animate().fadeIn(delay: 600.ms),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScoreCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _scoreColor.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: _scoreColor.withValues(alpha: 0.1),
            blurRadius: 30,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            height: 100,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: _score / 100,
                  strokeWidth: 10,
                  backgroundColor: Colors.white.withValues(alpha: 0.05),
                  valueColor: AlwaysStoppedAnimation<Color>(_scoreColor),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('$_score', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: _scoreColor)),
                    Text('%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _scoreColor)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_scoreLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20)),
                const SizedBox(height: 4),
                Text(
                  'Your privacy rating is based on active security features.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProtectionToggles() {
    final items = [
      ('Kill Switch', Icons.power_off_rounded, 'Blocks internet if VPN drops'),
      ('DNS Leak Guard', Icons.dns_rounded, 'Encrypts all DNS queries'),
      ('Auto WiFi Shield', Icons.wifi_rounded, 'Auto-connects on public WiFi'),
      ('Ad & Tracker Blocker', Icons.block_rounded, 'Blocks ads and trackers'),
      ('Malware Protection', Icons.security_rounded, 'Blocks malicious sites'),
      ('Split Tunneling', Icons.call_split_rounded, 'Choose apps to exclude'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 12),
          child: Text('PROTECTION SUITE', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.5)),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            children: items.asMap().entries.map((e) {
              final key = e.value.$1;
              final val = _toggles[key] ?? false;
              return Column(
                children: [
                  SwitchListTile(
                    value: val,
                    onChanged: (v) => setState(() => _toggles[key] = v),
                    activeThumbColor: AppColors.primaryBlue,
                    title: Text(key, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                    subtitle: Text(e.value.$3, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    secondary: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: val ? AppColors.primaryBlue.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(e.value.$2, color: val ? AppColors.primaryBlue : AppColors.textSecondary, size: 20),
                    ),
                  ),
                  if (e.key < items.length - 1)
                    const Divider(color: AppColors.divider, height: 1, indent: 64),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildAiTools() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 12),
          child: Text('DIAGNOSTIC TOOLS', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.5)),
        ),
        Row(
          children: [
            Expanded(child: _buildToolCard('IP CHECK', Icons.location_searching_rounded, AppColors.neonCyan)),
            const SizedBox(width: 16),
            Expanded(child: _buildToolCard('LEAK TEST', Icons.leak_remove_rounded, AppColors.accentPurple)),
          ],
        ),
      ],
    );
  }

  Widget _buildToolCard(String title, IconData icon, Color color) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildProtocolCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.settings_input_antenna_rounded, color: AppColors.primaryBlue, size: 20),
              const SizedBox(width: 12),
              Text('VPN PROTOCOL', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 20),
          _protocolItem('WireGuard (Recommended)', 'Best speed and modern encryption', true),
          _protocolItem('OpenVPN (TCP/UDP)', 'Most compatible and widely tested', false),
          _protocolItem('IKEv2', 'Fast connection on mobile networks', false),
        ],
      ),
    );
  }

  Widget _protocolItem(String title, String desc, bool active) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: InkWell(
          onTap: () {}, // Handled by state in real implementation
          borderRadius: BorderRadius.circular(12),
          child: Row(
            children: [
              // Custom Premium Radio
              Container(
                width: 20,
                height: 20,
                margin: const EdgeInsets.only(right: 16, left: 4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: active ? AppColors.primaryBlue : Colors.white24,
                    width: 2,
                  ),
                ),
                child: active ? Center(
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: AppColors.primaryBlue,
                      shape: BoxShape.circle,
                    ),
                  ),
                ) : null,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                    Text(desc, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
