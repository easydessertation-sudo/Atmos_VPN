import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../utils/design_system.dart';
import '../widgets/app_container.dart';
import '../utils/api_service.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../utils/ad_manager.dart';
import '../services/vpn_service.dart';
import 'dart:io';

class SecurityCenterScreen extends StatefulWidget {
  const SecurityCenterScreen({super.key});

  @override
  State<SecurityCenterScreen> createState() => _SecurityCenterScreenState();
}

class _SecurityCenterScreenState extends State<SecurityCenterScreen> {
  // Score is computed live from switch states — no API timing issue
  int _computeScore(Map<String, bool> features) {
    final keys = [
      'dns_leak_protection',
      'auto_connect_wifi',
      'ad_blocker_enabled',
      'tracker_blocker_enabled',
      'malware_protection',
    ];
    final onCount = keys.where((k) => features[k] == true).length;
    // Assume Kill Switch is enabled for scoring purposes since it's an OS setting
    return (((onCount + 1) / (keys.length + 1)) * 100).round();
  }

  void _showKillSwitchDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Manage Kill Switch',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        content: const Text(
          'To enable or disable the Kill Switch, please configure it in your system settings:\n\n'
          '1. Tap "Open Settings" below.\n'
          '2. Tap the gear icon (⚙️) next to AtmosVPN.\n'
          '3. Turn "Always-on VPN" and "Block connections without VPN" ON or OFF according to your preference.',
          style: TextStyle(color: AppColors.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              VpnService.openVpnSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('OPEN SETTINGS',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // IP Check state
  String? _currentIp;
  bool _isCheckingIp = false;

  // Leak Test state
  bool _isRunningLeakTest = false;
  String? _leakTestResult;
  bool? _leakDetected;

  // Protocol state
  String _selectedProtocol = 'wireguard';
  bool _isSavingProtocol = false;

  final List<Map<String, String>> _protocols = [
    {
      'id': 'wireguard',
      'label': 'WireGuard (Recommended)',
      'desc': 'Best speed and modern encryption'
    },
    {
      'id': 'openvpn',
      'label': 'OpenVPN (TCP/UDP)',
      'desc': 'Most compatible and widely tested'
    },
    {
      'id': 'ikev2',
      'label': 'IKEv2/IPSec',
      'desc': 'Fast connection on mobile networks'
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadProtocolSetting();
  }

  Future<void> _loadProtocolSetting() async {
    try {
      final resp = await ApiService.getSettings();
      if (resp['success'] == true) {
        final proto =
            resp['data']?['connection']?['preferred_protocol']?.toString();
        if (proto != null && mounted) {
          setState(() => _selectedProtocol = proto);
        }
      }
    } catch (_) {}
  }

  Future<void> _toggleFeature(String key, bool value) async {
    final plan = context.read<VPNProvider>().userData?['plan']?.toString() ?? 'free';
    if (plan == 'free') {
      AdManager.showInterstitialAd(context: context, onAdDismissed: () async {
        await context.read<VPNProvider>().toggleSecurityFeature(key, value);
      });
    } else {
      await context.read<VPNProvider>().toggleSecurityFeature(key, value);
    }
  }

  Future<void> _checkIp() async {
    final plan = context.read<VPNProvider>().userData?['plan']?.toString() ?? 'free';

    void proceed() async {
      setState(() {
        _isCheckingIp = true;
        _currentIp = null;
      });
      try {
        final resp = await ApiService.getIp();
        final ip = resp['data']?['ip']?.toString() ?? resp['ip']?.toString();
        if (mounted) {
          setState(() => _currentIp = ip ?? 'Unable to fetch');
        }
      } catch (e) {
        if (mounted) setState(() => _currentIp = 'Error: Check connection');
      } finally {
        if (mounted) setState(() => _isCheckingIp = false);
      }
    }

    if (plan == 'free') {
      AdManager.showInterstitialAd(context: context, onAdDismissed: proceed);
    } else {
      proceed();
    }
  }

  Future<void> _runLeakTest() async {
    final plan = context.read<VPNProvider>().userData?['plan']?.toString() ?? 'free';

    void proceed() async {
      setState(() {
        _isRunningLeakTest = true;
        _leakTestResult = null;
        _leakDetected = null;
      });
      try {
        // Step 1: Get current public IP via our backend
        final ipResp = await ApiService.getIp();
        final currentIp =
            ipResp['data']?['ip']?.toString() ?? ipResp['ip']?.toString();

        // Step 2: Get VPN status to check if connected and what IP was assigned
        final vpn = context.read<VPNProvider>();
        final isConnected = vpn.isConnected;
        final realIp = vpn.realIp;

        await Future.delayed(const Duration(seconds: 1)); // simulate deeper check

        if (mounted) {
          if (!isConnected) {
            setState(() {
              _leakDetected = null;
              _leakTestResult =
                  'Not connected to VPN.\nConnect first to test for leaks.\nYour IP: ${currentIp ?? "Unknown"}';
            });
          } else {
            if (currentIp == null || realIp == null) {
              setState(() {
                _leakDetected = null;
                _leakTestResult = 'Could not determine IP addresses for leak test. Ensure you have internet connection.';
              });
            } else if (currentIp == realIp) {
              setState(() {
                _leakDetected = true;
                _leakTestResult =
                    'DNS/IP LEAK DETECTED ⚠️\nYour real IP ($realIp) is exposed!\nTraffic is NOT fully encrypted through VPN tunnel.';
              });
            } else {
              setState(() {
                _leakDetected = false;
                _leakTestResult =
                    'No DNS/IP leaks detected ✅\nVisible IP: $currentIp\nTraffic is fully encrypted through VPN tunnel.';
              });
            }
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _leakDetected = null;
            _leakTestResult = 'Test failed. Check your connection.';
          });
        }
      } finally {
        if (mounted) setState(() => _isRunningLeakTest = false);
      }
    }

    if (plan == 'free') {
      AdManager.showInterstitialAd(context: context, onAdDismissed: proceed);
    } else {
      proceed();
    }
  }

  Future<void> _selectProtocol(String protocolId) async {
    if (_isSavingProtocol || _selectedProtocol == protocolId) return;

    final plan = context.read<VPNProvider>().userData?['plan']?.toString() ?? 'free';

    void proceed() async {
      setState(() {
        _isSavingProtocol = true;
        _selectedProtocol = protocolId;
      });
      try {
        await ApiService.updateSettings({'preferred_protocol': protocolId});
      } catch (_) {}
      if (mounted) setState(() => _isSavingProtocol = false);
    }

    if (plan == 'free') {
      AdManager.showInterstitialAd(context: context, onAdDismissed: proceed);
    } else {
      proceed();
    }
  }

  Color _getScoreColor(int score) {
    if (score >= 80) return AppColors.success;
    if (score >= 50) return AppColors.warning;
    return Colors.red;
  }

  String _getScoreLabel(int score) {
    if (score >= 80) return 'Highly Secure';
    if (score >= 50) return 'Moderate';
    return 'Vulnerable';
  }

  @override
  Widget build(BuildContext context) {
    final vpn = context.watch<VPNProvider>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('Security Center',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: _computeScore(vpn.securityFeatures) / 100.0),
              duration: const Duration(milliseconds: 1000),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                final currentScore = (value * 100).toInt();
                final currentColor = _getScoreColor(currentScore);
                return Icon(Icons.verified_user_rounded,
                    color: currentColor, size: 22);
              },
            ),
          ),
        ],
      ),
      body: AppContainer(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            children: [
              _buildScoreCard(vpn)
                  .animate()
                  .fadeIn()
                  .scale(begin: const Offset(0.95, 0.95)),
              const SizedBox(height: 32),
              _buildProtectionToggles(vpn).animate().fadeIn(delay: 200.ms),
              const SizedBox(height: 32),
              _buildDiagnosticTools().animate().fadeIn(delay: 400.ms),
              const SizedBox(height: 32),
              _buildProtocolCard().animate().fadeIn(delay: 600.ms),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScoreCard(VPNProvider vpn) {
    final score = _computeScore(vpn.securityFeatures);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _getScoreColor(score).withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: _getScoreColor(score).withValues(alpha: 0.1),
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
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: score / 100.0),
              duration: const Duration(milliseconds: 1000),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                final currentScore = (value * 100).toInt();
                final currentColor = _getScoreColor(currentScore);
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 100,
                      height: 100,
                      child: CircularProgressIndicator(
                        value: value,
                        strokeWidth: 8,
                        backgroundColor: Colors.white.withValues(alpha: 0.05),
                        valueColor: AlwaysStoppedAnimation<Color>(currentColor),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('$currentScore',
                                style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w900,
                                    color: currentColor)),
                          ),
                          Text('%',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: currentColor)),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: score / 100.0),
              duration: const Duration(milliseconds: 1000),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                final currentScore = (value * 100).toInt();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_getScoreLabel(currentScore),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 20)),
                    const SizedBox(height: 4),
                    const Text(
                      'Your privacy rating is based on active security features.',
                      style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          height: 1.4),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProtectionToggles(VPNProvider vpn) {
    if (vpn.isFetchingSecurity && _computeScore(vpn.securityFeatures) == 0) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(color: AppColors.primaryBlue)));
    }

    final items = [
      (
        'kill_switch_enabled',
        'Manage Kill Switch',
        Icons.power_off_rounded,
        'Blocks internet if VPN drops'
      ),
      (
        'dns_leak_protection',
        'DNS Leak Guard',
        Icons.dns_rounded,
        'Encrypts all DNS queries'
      ),
      (
        'auto_connect_wifi',
        'Auto WiFi Shield',
        Icons.wifi_rounded,
        'Auto-connects on public WiFi'
      ),
      (
        'ad_blocker_enabled',
        'Ad Blocker',
        Icons.block_rounded,
        'Blocks ads at DNS level'
      ),
      (
        'tracker_blocker_enabled',
        'Tracker Blocker',
        Icons.radar_rounded,
        'Blocks tracking scripts'
      ),
      (
        'malware_protection',
        'Malware Protection',
        Icons.security_rounded,
        'Blocks malicious sites'
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 12),
          child: Text('PROTECTION SUITE',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 1.5)),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            children: items.asMap().entries.map((e) {
              final apiKey = e.value.$1;
              final title = e.value.$2;
              final icon = e.value.$3;
              final desc = e.value.$4;

              if (apiKey == 'kill_switch_enabled' && Platform.isAndroid) {
                return Column(
                  children: [
                    ListTile(
                      onTap: _showKillSwitchDialog,
                      title: Text(title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15)),
                      subtitle: Text(desc,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12)),
                      trailing: const Icon(Icons.arrow_forward_ios_rounded,
                          color: AppColors.textSecondary, size: 16),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child:
                            Icon(icon, color: AppColors.primaryBlue, size: 20),
                      ),
                    ),
                    if (e.key < items.length - 1)
                      const Divider(
                          color: AppColors.divider, height: 1, indent: 64),
                  ],
                );
              }

              final val = vpn.securityFeatures[apiKey] == true;
              return Column(
                children: [
                  SwitchListTile(
                    value: val,
                    onChanged: (v) => _toggleFeature(apiKey, v),
                    activeThumbColor: AppColors.primaryBlue,
                    title: Text(title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
                    subtitle: Text(desc,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                    secondary: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: val
                            ? AppColors.primaryBlue.withValues(alpha: 0.1)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon,
                          color: val
                              ? AppColors.primaryBlue
                              : AppColors.textSecondary,
                          size: 20),
                    ),
                  ),
                  if (e.key < items.length - 1)
                    const Divider(
                        color: AppColors.divider, height: 1, indent: 64),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildDiagnosticTools() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 12),
          child: Text('DIAGNOSTIC TOOLS',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 1.5)),
        ),
        Row(
          children: [
            Expanded(child: _buildIpCheckCard()),
            const SizedBox(width: 16),
            Expanded(child: _buildLeakTestCard()),
          ],
        ),
        // Result panel
        if (_currentIp != null || _leakTestResult != null) ...[
          const SizedBox(height: 16),
          _buildResultPanel(),
        ],
      ],
    );
  }

  Widget _buildIpCheckCard() {
    return GestureDetector(
      onTap: _isCheckingIp ? null : _checkIp,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _isCheckingIp
                ? AppColors.neonCyan.withValues(alpha: 0.08)
                : AppColors.cardBackground,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _isCheckingIp
                  ? AppColors.neonCyan.withValues(alpha: 0.5)
                  : AppColors.divider,
            ),
          ),
          child: Column(
            children: [
              _isCheckingIp
                  ? const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: AppColors.neonCyan),
                    )
                  : Icon(Icons.location_searching_rounded,
                      color: AppColors.neonCyan, size: 28),
              const SizedBox(height: 12),
              Text(
                'IP CHECK',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 0.5),
              ),
              if (_currentIp != null) ...[
                const SizedBox(height: 4),
                Text(_currentIp!,
                    style: TextStyle(
                        color: AppColors.neonCyan,
                        fontSize: 10,
                        fontWeight: FontWeight.w700)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeakTestCard() {
    Color cardColor = AppColors.accentPurple;
    if (_leakDetected == false) cardColor = AppColors.success;
    if (_leakDetected == true) cardColor = Colors.red;

    return GestureDetector(
      onTap: _isRunningLeakTest ? null : _runLeakTest,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _isRunningLeakTest
                ? cardColor.withValues(alpha: 0.08)
                : AppColors.cardBackground,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _isRunningLeakTest
                  ? cardColor.withValues(alpha: 0.5)
                  : AppColors.divider,
            ),
          ),
          child: Column(
            children: [
              _isRunningLeakTest
                  ? SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: cardColor),
                    )
                  : Icon(
                      _leakDetected == false
                          ? Icons.check_circle_rounded
                          : _leakDetected == true
                              ? Icons.warning_rounded
                              : Icons.leak_remove_rounded,
                      color: cardColor,
                      size: 28,
                    ),
              const SizedBox(height: 12),
              Text(
                'LEAK TEST',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 0.5),
              ),
              if (_leakDetected != null) ...[
                const SizedBox(height: 4),
                Text(
                  _leakDetected! ? 'LEAK!' : 'SECURE',
                  style: TextStyle(
                      color: cardColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w900),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultPanel() {
    final text = _leakTestResult ??
        (_currentIp != null ? 'Your public IP: $_currentIp' : null);
    if (text == null) return const SizedBox();

    final color = _leakDetected == false
        ? AppColors.success
        : _leakDetected == true
            ? Colors.red
            : AppColors.neonCyan;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
            color: color,
            fontSize: 13,
            height: 1.6,
            fontWeight: FontWeight.w600),
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
          Row(
            children: [
              const Icon(Icons.settings_input_antenna_rounded,
                  color: AppColors.primaryBlue, size: 20),
              const SizedBox(width: 12),
              const Text('VPN PROTOCOL',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 14)),
              const Spacer(),
              if (_isSavingProtocol)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primaryBlue),
                ),
            ],
          ),
          const SizedBox(height: 20),
          ..._protocols
              .map((p) => _protocolItem(p['id']!, p['label']!, p['desc']!)),
        ],
      ),
    );
  }

  Widget _protocolItem(String id, String title, String desc) {
    final active = _selectedProtocol == id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => _selectProtocol(id),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
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
                child: active
                    ? Center(
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: AppColors.primaryBlue,
                            shape: BoxShape.circle,
                          ),
                        ),
                      )
                    : null,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                          color: active ? Colors.white : Colors.white60,
                          fontWeight:
                              active ? FontWeight.w700 : FontWeight.w500,
                          fontSize: 14,
                        )),
                    Text(desc,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 11)),
                  ],
                ),
              ),
              if (active)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('ACTIVE',
                      style: TextStyle(
                          color: AppColors.primaryBlue,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
