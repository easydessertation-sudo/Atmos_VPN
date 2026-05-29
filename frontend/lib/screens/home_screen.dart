import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'package:provider/provider.dart';
import '../utils/design_system.dart';
import '../main.dart';
import '../widgets/upgrade_banner.dart';
import '../widgets/banner_ad_widget.dart';
import '../utils/ad_manager.dart';
import 'server_list.dart';
import 'security_center.dart';
import 'speed_test.dart';
import 'account_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MOBILE HOME SCREEN — mode-based VPN dashboard
// ─────────────────────────────────────────────────────────────────────────────
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _ModeOption {
  final String id, name, desc;
  final IconData icon;
  final Color color;
  const _ModeOption(this.id, this.name, this.desc, this.icon, this.color);
}

const _modes = [
  _ModeOption('standard', 'Generic VPN', 'Secure everyday browsing',
      Icons.shield_rounded, Color(0xFF3B82F6)),
  _ModeOption('streaming', 'Streaming', 'Netflix, Disney+, Hulu',
      Icons.movie_rounded, Color(0xFF8B5CF6)),
  _ModeOption('gaming', 'Gaming', 'Low latency + DDoS shield',
      Icons.sports_esports_rounded, Color(0xFFF97316)),
  _ModeOption('crypto', 'Crypto', 'Secure trading + phishing guard',
      Icons.currency_bitcoin_rounded, Color(0xFFF59E0B)),
];

// ─── Tab index constants ────────────────────────────────────────────────────
const int _kTabHome = 0;
const int _kTabServers = 1;
const int _kTabSecurity = 2;
const int _kTabActivity = 3;
const int _kTabProfile = 4;

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _selectedMode = 0;
  int _navIndex = 0;
  late AnimationController _pulseCtrl;

  Map<String, dynamic> _securityFeatures = {};
  bool _isFetchingSecurity = true;

  bool _isSessionDialogShowing = false;

  VPNProvider? _vpnProvider;

  void _onVpnChanged() {
    if (!mounted) return;
    final vpn = _vpnProvider;
    if (vpn != null && vpn.triggerSessionExpired) {
      if (!_isSessionDialogShowing) {
        _showSessionExpiredDialog();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchSecuritySettings();
    _pulseCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _vpnProvider = context.read<VPNProvider>();
        _vpnProvider?.addListener(_onVpnChanged);
      }
    });
  }

  Future<void> _fetchSecuritySettings() async {
    // Moved to VPNProvider. fetchSecuritySettings() is called on init there.
  }

  Future<void> _toggleSecurity(String key, bool value) async {
    context.read<VPNProvider>().toggleSecurityFeature(key, value);
  }

  Future<void> _showSessionExpiredDialog() async {
    if (!mounted || _isSessionDialogShowing) return;
    _isSessionDialogShowing = true;

    final vpn = context.read<VPNProvider>();
    final reqPlan = vpn.selectedServer?['required_plan']?.toString().toLowerCase() ?? 'free';
    final isStarterServer = reqPlan == 'starter';
    final tier = isStarterServer ? 'starter' : 'free';
    
    final int adsNeeded = isStarterServer ? 2 : 1;
    final int adsWatched = isStarterServer ? vpn.starterAdsWatched : 0;
    final int adsRemaining = adsNeeded - adsWatched;
    
    final dialogContent = isStarterServer 
        ? 'Your Starter 45-minute session has ended. Watch $adsRemaining more ad(s) to get 45 more minutes, or upgrade for unlimited access.'
        : 'Your Free 30-minute session has ended. Watch an ad to get 30 more minutes, or upgrade for unlimited access.';
    final buttonText = isStarterServer ? 'WATCH AD ($adsRemaining)' : 'WATCH AD (1)';

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('⏰ Session Expired',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        content: Text(dialogContent,
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              AdManager.showInterstitialAd(onAdDismissed: () async {
                bool claimed = await vpn.watchAd(tier: tier);
                if (claimed && vpn.selectedServer != null) {
                  // Connect automatically once all ads are watched!
                  vpn.connect(vpn.selectedServer!['id']!.toString(), mode: 'standard');
                } else if (isStarterServer && vpn.starterAdsWatched > 0) {
                  // If they watched 1 but need 2, re-trigger the dialog so they can click the 2nd one
                  vpn.triggerSessionExpiredDialog();
                }
              });
            },
            child: Text(buttonText,
                style: const TextStyle(
                    color: AppColors.primaryBlue, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushNamed(context, '/account/pricing');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('UPGRADE',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (mounted) {
      _isSessionDialogShowing = false;
    }
  }

  @override
  void dispose() {
    _vpnProvider?.removeListener(_onVpnChanged);
    _pulseCtrl.dispose();
    super.dispose();
  }

  Color get _activeColor => _modes[_selectedMode].color;

  @override
  Widget build(BuildContext context) {
    final vpn = Provider.of<VPNProvider>(context);
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (_navIndex != 0) {
          setState(() => _navIndex = 0);
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        // IndexedStack keeps all pages alive and preserves their scroll state.
        // The bottom nav bar lives on THIS Scaffold so it's always visible.
        body: IndexedStack(
          index: _navIndex,
          children: [
            // ── Tab 0: Home ───────────────────────────────────────────────────
            _HomeTab(
                vpn: vpn,
                modes: _modes,
                selectedMode: _selectedMode,
                onModeChanged: (i) => setState(() => _selectedMode = i),
                pulseCtrl: _pulseCtrl,
                activeColor: _activeColor,
                onToggleSecurity: _toggleSecurity,
                onNavigateTab: (i) => setState(() => _navIndex = i)),
            ServerListScreen(
              onSelectServer: () => setState(() => _navIndex = 0),
            ),
            // ── Tab 2: Security ──────────────────────────────────────────────
            const SecurityCenterScreen(),
            // ── Tab 3: Speed / Activity ──────────────────────────────────────
            const SpeedTestScreen(),
            // ── Tab 4: Account / Profile ─────────────────────────────────────
            const AccountScreen(),
          ],
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (vpn.isFreeUser)
              const Padding(
                padding: EdgeInsets.only(bottom: 0.0),
                child: BannerAdWidget(),
              ),
            _buildBottomNav(context),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    const items = [
      (Icons.home_rounded, 'Home'),
      (Icons.public_rounded, 'Servers'),
      (Icons.security_rounded, 'Security'),
      (Icons.bar_chart_rounded, 'Activity'),
      (Icons.person_rounded, 'Profile'),
    ];
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF080C17),
        border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.07))),
      ),
      child: SafeArea(
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(items.length, (i) {
              final active = _navIndex == i;
              return GestureDetector(
                // Simply switch the IndexedStack index — no Navigator.push!
                onTap: () => setState(() => _navIndex = i),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: SizedBox(
                    width: 60,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(items[i].$1,
                            color: active ? _activeColor : Colors.white24,
                            size: 22),
                        const SizedBox(height: 3),
                        Text(
                          items[i].$2,
                          style: TextStyle(
                            color: active ? _activeColor : Colors.white24,
                            fontSize: 9,
                            fontWeight:
                                active ? FontWeight.w800 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _HomeTab — the content for the Home tab inside the IndexedStack shell
// ─────────────────────────────────────────────────────────────────────────────
class _HomeTab extends StatelessWidget {
  final VPNProvider vpn;
  final List<_ModeOption> modes;
  final int selectedMode;
  final ValueChanged<int> onModeChanged;
  final AnimationController pulseCtrl;
  final Color activeColor;
  final Future<void> Function(String, bool) onToggleSecurity;
  final ValueChanged<int> onNavigateTab;

  const _HomeTab({
    required this.vpn,
    required this.modes,
    required this.selectedMode,
    required this.onModeChanged,
    required this.pulseCtrl,
    required this.activeColor,
    required this.onToggleSecurity,
    required this.onNavigateTab,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Background glows
        Positioned(
          top: -60,
          left: -60,
          child: _BgGlow(activeColor.withValues(alpha: 0.15), 300),
        ),
        Positioned(
          bottom: 80,
          right: -60,
          child: _BgGlow(activeColor.withValues(alpha: 0.08), 250),
        ),
        SafeArea(
          child: Column(
            children: [
              _buildTopBar(context),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      _buildModeSelector(),
                      const SizedBox(height: 28),
                      _buildConnectArea(context),
                      const SizedBox(height: 28),
                      _buildServerCard(context),
                      const SizedBox(height: 16),
                      _buildStatsRow(),
                      const SizedBox(height: 16),
                      _buildQuickFeatures(context),
                      if (vpn.isFreeUser && !vpn.hasUpgraded) ...[
                        const SizedBox(height: 32),
                        Builder(
                          builder: (context) {
                            final reqPlan = vpn.selectedServer?['required_plan']?.toString().toLowerCase() ?? 'free';
                            final isStarterServer = reqPlan == 'starter';
                            final tier = isStarterServer ? 'starter' : 'free';
                            
                            final int adsNeeded = isStarterServer ? 2 : 1;
                            final int adsWatched = isStarterServer ? vpn.starterAdsWatched : 0;
                            final int adsRemaining = adsNeeded - adsWatched;
                            
                            final title = isStarterServer ? 'GET STARTER SPEED!' : 'FREE SERVER ACCESS';
                            final subtitle = isStarterServer 
                                ? 'Watch $adsRemaining ad(s) to unlock this server for 45 minutes.' 
                                : 'Watch 1 ad to unlock this server for 30 minutes.';
                            final buttonText = isStarterServer ? 'WATCH AD ($adsRemaining)' : 'WATCH AD (1)';

                            return UpgradeBanner(
                              title: title,
                              subtitle: subtitle,
                              buttonText: buttonText,
                              onUpgrade: () =>
                                  Navigator.pushNamed(context, '/account/pricing'),
                              onWatchAd: () {
                                AdManager.showInterstitialAd(onAdDismissed: () async {
                                  bool claimed = await vpn.watchAd(tier: tier);
                                  if (claimed && vpn.selectedServer != null) {
                                    vpn.connect(vpn.selectedServer!['id']!.toString(), mode: 'standard');
                                  }
                                });
                              },
                              onClose: () => vpn.setUpgrade(true),
                            );
                          }
                        ),
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.asset(
              'assets/images/app_logo.png',
              width: 24,
              height: 24,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 8),
          const Text('AtmosVPN',
              style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: Colors.white)),
          const Expanded(child: SizedBox()),
          if (vpn.isFreeUser) ...[
            (() {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: vpn.remainingSeconds <= 0
                      ? AppColors.warning.withValues(alpha: 0.25)
                      : AppColors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: AppColors.warning.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                        Icons.timer_outlined,
                        color: AppColors.warning,
                        size: 11),
                    const SizedBox(width: 3),
                    Text(
                      !vpn.isSessionTimeLoaded
                          ? '···'
                          : (vpn.remainingSeconds <= 0
                              ? 'No time'
                              : '${(vpn.remainingSeconds ~/ 60).toString().padLeft(2, '0')}:${(vpn.remainingSeconds % 60).toString().padLeft(2, '0')}'),
                      style: const TextStyle(
                          color: AppColors.warning,
                          fontSize: 10,
                          fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              );
            })(),
            const SizedBox(width: 8),
          ],
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/notifications'),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  shape: BoxShape.circle),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.notifications_none_rounded,
                      color: Colors.white60, size: 20),
                  if (vpn.unreadCount > 0)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: const BoxDecoration(
                            color: AppColors.warning, shape: BoxShape.circle),
                        child: Center(
                          child: Text(
                            vpn.unreadCount > 9 ? '9+' : '${vpn.unreadCount}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 7,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => onNavigateTab(_kTabProfile),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  shape: BoxShape.circle),
              child: const Icon(Icons.person_rounded,
                  color: Colors.white60, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    return SizedBox(
      height: 50,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: modes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final mode = modes[i];
          final selected = selectedMode == i;
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => onModeChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: selected
                      ? mode.color.withValues(alpha: 0.2)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(
                    color: selected
                        ? mode.color.withValues(alpha: 0.6)
                        : Colors.white.withValues(alpha: 0.08),
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(mode.icon,
                        color: selected ? mode.color : Colors.white38,
                        size: 16),
                    const SizedBox(width: 6),
                    Text(mode.name,
                        style: TextStyle(
                            color: selected ? mode.color : Colors.white38,
                            fontWeight:
                                selected ? FontWeight.w800 : FontWeight.w500,
                            fontSize: 13)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildConnectArea(BuildContext context) {
    final isConnecting = !vpn.isConnected &&
        (vpn.status == 'Provisioning...' ||
            vpn.status == 'Configuring...' ||
            vpn.status == 'Connecting...');
    final hasFailed = vpn.lastError != null && !vpn.isConnected;

    return Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(
            vpn.isConnected
                ? 'PROTECTED'
                : isConnecting
                    ? vpn.status.toUpperCase()
                    : hasFailed
                        ? 'FAILED'
                        : 'UNPROTECTED',
            key: ValueKey(vpn.status),
            style: TextStyle(
              color: vpn.isConnected
                  ? AppColors.success
                  : isConnecting
                      ? activeColor
                      : hasFailed
                          ? AppColors.warning
                          : Colors.white38,
              fontWeight: FontWeight.w900,
              fontSize: 11,
              letterSpacing: 2,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          vpn.isConnected ? vpn.currentServer : 'IP Hidden',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22),
        ),
        if (hasFailed) ...[
          const SizedBox(height: 8),
          Text(vpn.lastError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.warning, fontSize: 12)),
        ],
        const SizedBox(height: 32),
        AnimatedBuilder(
          animation: pulseCtrl,
          builder: (_, child) {
            final scale = (vpn.isConnected || isConnecting)
                ? 1.0
                : (0.97 + 0.03 * pulseCtrl.value);
            return Transform.scale(scale: scale, child: child);
          },
          child: MouseRegion(
            cursor: isConnecting
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click,
            child: GestureDetector(
              onTap: isConnecting ? null : () => vpn.toggleConnection(),
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: activeColor.withValues(
                          alpha: vpn.isConnected ? 0.4 : 0.2),
                      blurRadius: vpn.isConnected ? 50 : 30,
                      spreadRadius: vpn.isConnected ? 5 : 0,
                    ),
                  ],
                ),
                child: CustomPaint(
                  painter: _RingPainter(
                      activeColor, vpn.isConnected, pulseCtrl.value),
                  child: Center(
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: vpn.isConnected
                              ? [
                                  AppColors.success.withValues(alpha: 0.3),
                                  Colors.transparent
                                ]
                              : [
                                  activeColor.withValues(alpha: 0.1),
                                  Colors.transparent
                                ],
                        ),
                        border: Border.all(
                          color: vpn.isConnected
                              ? AppColors.success.withValues(alpha: 0.5)
                              : activeColor.withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (isConnecting)
                            SizedBox(
                              width: 40,
                              height: 40,
                              child: CircularProgressIndicator(
                                  strokeWidth: 3, color: activeColor),
                            )
                          else
                            Icon(
                              vpn.isConnected
                                  ? Icons.power_settings_new_rounded
                                  : Icons.shield_rounded,
                              size: 48,
                              color: vpn.isConnected
                                  ? AppColors.success
                                  : activeColor,
                            ),
                          const SizedBox(height: 8),
                          Text(
                            vpn.isConnected
                                ? 'STOP'
                                : isConnecting
                                    ? '...'
                                    : 'CONNECT',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                              color: vpn.isConnected
                                  ? AppColors.success
                                  : activeColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          modes[selectedMode].desc,
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4), fontSize: 13),
        ),
        if (vpn.isConnected && vpn.isFreeUser) ...[
          Builder(builder: (context) {
            final reqPlan = vpn.selectedServer?['required_plan']?.toString().toLowerCase() ?? 'free';
            final isStarter = reqPlan == 'starter';
            final int h = vpn.remainingSeconds ~/ 3600;
            final int m = (vpn.remainingSeconds % 3600) ~/ 60;
            final int s = vpn.remainingSeconds % 60;
            final timeStr = '${h > 0 ? '$h : ' : ''}${m.toString().padLeft(2, '0')} : ${s.toString().padLeft(2, '0')}';
            return Padding(
              padding: const EdgeInsets.only(top: 24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    timeStr,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildServerCard(BuildContext context) {
    final server = vpn.selectedServer;
    final flag = server?['flag'] ?? '🌍';
    final ping = (server?['ping_ms'] ?? 0) as int;
    final pingColor = ping == 0
        ? AppColors.textSecondary
        : (ping < 50
            ? AppColors.success
            : (ping < 100 ? Colors.amber : AppColors.warning));
    final serverName = server != null
        ? '${server['city'] ?? server['name']}, ${server['country'] ?? ''}'
        : (vpn.isConnected ? vpn.currentServer : 'Select a server');

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onNavigateTab(_kTabServers),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: activeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12)),
                child: Text(flag, style: const TextStyle(fontSize: 20)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Server',
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                    Text(serverName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15),
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (server != null) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: pingColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20)),
                  child: Text('${ping}ms',
                      style: TextStyle(
                          color: pingColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 8),
              ],
              const Icon(Icons.chevron_right_rounded,
                  color: Colors.white24, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    final server = vpn.selectedServer;
    final ping = server != null ? '${server['ping_ms'] ?? '--'}ms' : '--';
    final load = server != null ? '${server['load_pct'] ?? '--'}%' : '--';
    final connected = vpn.isConnected;
    return Row(
      children: [
        Expanded(
            child: _StatPill(
                Icons.timer_rounded, ping, 'Ping', AppColors.success)),
        const SizedBox(width: 10),
        Expanded(
            child: _StatPill(Icons.speed_rounded, connected ? load : '--',
                'Server Load', activeColor)),
        const SizedBox(width: 10),
        Expanded(
            child: _StatPill(
                Icons.shield_rounded,
                connected ? 'ON' : 'OFF',
                'Protected',
                connected ? AppColors.success : AppColors.textSecondary)),
      ],
    );
  }

  Widget _buildQuickFeatures(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('QUICK SECURITY',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    letterSpacing: 1.2)),
            TextButton(
              onPressed: () => onNavigateTab(_kTabSecurity),
              child: const Text('MANAGE ALL',
                  style: TextStyle(
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.w900,
                      fontSize: 11)),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: vpn.isFetchingSecurity
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(
                      child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2))))
              : Column(
                  children: [
                    _QuickToggle(
                        'Kill Switch',
                        Icons.power_off_rounded,
                        vpn.securityFeatures['kill_switch_enabled'] == true,
                        activeColor,
                        (v) => onToggleSecurity('kill_switch_enabled', v)),
                    const SizedBox(height: 4),
                    _QuickToggle(
                        'DNS Leak Guard',
                        Icons.dns_rounded,
                        vpn.securityFeatures['dns_leak_protection'] == true,
                        activeColor,
                        (v) => onToggleSecurity('dns_leak_protection', v)),
                    const SizedBox(height: 4),
                    _QuickToggle(
                        'Ad Blocker',
                        Icons.block_rounded,
                        vpn.securityFeatures['ad_blocker_enabled'] == true,
                        activeColor,
                        (v) => onToggleSecurity('ad_blocker_enabled', v)),
                  ],
                ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-components
// ─────────────────────────────────────────────────────────────────────────────

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String value, label;
  final Color color;
  const _StatPill(this.icon, this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 10)),
        ],
      ),
    );
  }
}

class _QuickToggle extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool value;
  final Color color;
  final ValueChanged<bool> onChanged;

  const _QuickToggle(
      this.label, this.icon, this.value, this.color, this.onChanged);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 14),
        ),
        const SizedBox(width: 12),
        Expanded(
            child: Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 14))),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: color,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ],
    );
  }
}

class _BgGlow extends StatelessWidget {
  final Color color;
  final double size;
  const _BgGlow(this.color, this.size);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, Colors.transparent]),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final Color color;
  final bool connected;
  final double t;
  _RingPainter(this.color, this.connected, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    // Outer faint ring
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = color.withValues(alpha: 0.1));

    // Active arc
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = connected
          ? AppColors.success.withValues(alpha: 0.8)
          : color.withValues(alpha: 0.6);

    if (connected) {
      canvas.drawCircle(c, r - 1, paint);
    } else {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r - 1),
        -math.pi / 2,
        math.pi * (1.4 + 0.2 * t),
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => true;
}
