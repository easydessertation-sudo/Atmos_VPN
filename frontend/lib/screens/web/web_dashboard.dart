import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:provider/provider.dart';
import '../../utils/design_system.dart';
import '../../main.dart';
import '../../widgets/upgrade_banner.dart';
import 'web_app_shell.dart';

class WebDashboard extends StatefulWidget {
  const WebDashboard({super.key});

  @override
  State<WebDashboard> createState() => _WebDashboardState();
}

class _WebDashboardState extends State<WebDashboard>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  String _selectedMode = 'standard';

  final _modes = [
    _ModeConfig('standard', 'Standard VPN', 'Private browsing',
        Icons.shield_rounded, const Color(0xFF3B82F6)),
    _ModeConfig('streaming', 'Streaming', 'Netflix, Disney+',
        Icons.movie_rounded, const Color(0xFF8B5CF6)),
    _ModeConfig('gaming', 'Gaming', 'Low latency + DDoS',
        Icons.sports_esports_rounded, const Color(0xFFF97316)),
    _ModeConfig('crypto', 'Crypto', 'Secure trading',
        Icons.currency_bitcoin_rounded, const Color(0xFFF59E0B)),
  ];

  @override
  void initState() {
    super.initState();
    _pulseController =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WebAppShell(
      selectedIndex: 0,
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    final vpn = Provider.of<VPNProvider>(context);
    return Container(
      color: AppColors.background,
      child: Stack(
        children: [
          Positioned(
              top: -100,
              left: -100,
              child: _Glow(AppColors.primaryBlue.withValues(alpha: 0.07), 500)),
          Positioned(
              bottom: -100,
              right: -50,
              child:
                  _Glow(AppColors.accentPurple.withValues(alpha: 0.06), 400)),
          SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Good ${_greeting()},',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.45),
                                  fontSize: 14)),
                          const SizedBox(height: 4),
                          const Text('VPN Dashboard',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900)),
                        ]),
                    const Spacer(),
                    if (vpn.isFreeUser) _UpgradeBadge(),
                  ],
                ),
                const SizedBox(height: 32),

                // Main grid: Connect card + Mode selector
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Connect card
                    Expanded(
                      flex: 4,
                      child: _ConnectCard(
                        vpn: vpn,
                        pulseController: _pulseController,
                        selectedMode: _selectedMode,
                      ),
                    ),
                    const SizedBox(width: 24),
                    // Mode selector
                    Expanded(
                      flex: 3,
                      child: _ModeSelectorCard(
                        modes: _modes,
                        selectedMode: _selectedMode,
                        onModeChanged: (m) => setState(() => _selectedMode = m),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Stats row
                Row(children: [
                  Expanded(
                      child: _StatCard('Download', '48.9 MB/s',
                          Icons.arrow_downward_rounded, AppColors.success)),
                  const SizedBox(width: 16),
                  Expanded(
                      child: _StatCard('Upload', '2.4 MB/s',
                          Icons.arrow_upward_rounded, AppColors.primaryBlue)),
                  const SizedBox(width: 16),
                  Expanded(
                      child: _StatCard('Ping', '12 ms', Icons.timer_rounded,
                          AppColors.accentPurple)),
                  const SizedBox(width: 16),
                  Expanded(
                      child: _StatCard('Protocol', 'WireGuard',
                          Icons.lock_rounded, AppColors.warning)),
                ]),
                const SizedBox(height: 24),

                // Recent servers + Quick actions
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                        flex: 5,
                        child: _RecentServersCard(
                            onViewMap: () =>
                                Navigator.pushNamed(context, '/map'))),
                    const SizedBox(width: 24),
                    Expanded(flex: 3, child: _QuickFeaturesCard()),
                  ],
                ),
                const SizedBox(height: 24),

                // Free user upgrade banner
                if (vpn.isFreeUser && !vpn.hasUpgraded) ...[
                  const SizedBox(height: 32),
                  UpgradeBanner(
                    onUpgrade: () =>
                        Navigator.pushNamed(context, '/account/pricing'),
                    onWatchAd: () {}, // Simulated
                    onClose: () => vpn.setUpgrade(true), title: '',
                    subtitle: '', buttonText: '', // Hide for this session
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Morning';
    if (h < 17) return 'Afternoon';
    return 'Evening';
  }
}

class _ConnectCard extends StatelessWidget {
  final VPNProvider vpn;
  final AnimationController pulseController;
  final String selectedMode;
  const _ConnectCard(
      {required this.vpn,
      required this.pulseController,
      required this.selectedMode});

  Color get _modeColor {
    return switch (selectedMode) {
      'streaming' => const Color(0xFF8B5CF6),
      'gaming' => const Color(0xFFF97316),
      'crypto' => const Color(0xFFF59E0B),
      _ => AppColors.primaryBlue,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _modeColor.withValues(alpha: 0.12),
            Colors.white.withValues(alpha: 0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _modeColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  vpn.isConnected ? 'PROTECTED' : 'UNPROTECTED',
                  style: TextStyle(
                    color: vpn.isConnected ? AppColors.success : Colors.white38,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  vpn.isConnected ? '172.16.254.1' : 'IP Hidden',
                  style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Colors.white),
                ),
                Text(
                  vpn.isConnected ? vpn.currentServer : 'Not Connected',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 14),
                ),
              ]),
              // Animated connect button
              AnimatedBuilder(
                animation: pulseController,
                builder: (_, child) {
                  return MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => vpn.toggleConnection(),
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: _modeColor.withValues(
                                  alpha: vpn.isConnected
                                      ? 0.35
                                      : 0.15 + 0.1 * pulseController.value),
                              blurRadius: 30 + 10 * pulseController.value,
                            )
                          ],
                        ),
                        child: CustomPaint(
                          painter: _ConnectRingPainter(pulseController.value,
                              vpn.isConnected, _modeColor),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  vpn.isConnected
                                      ? Icons.power_settings_new_rounded
                                      : Icons.shield_rounded,
                                  size: 36,
                                  color: vpn.isConnected
                                      ? AppColors.success
                                      : _modeColor,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  vpn.isConnected ? 'STOP' : 'CONNECT',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    color: vpn.isConnected
                                        ? AppColors.success
                                        : _modeColor,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 32),
          const Divider(color: Colors.white10),
          const SizedBox(height: 24),
          // Server selector
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => Navigator.pushNamed(context, '/server-list'),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  children: [
                    const Text('🇬🇧', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Current Server',
                                style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700)),
                            Text(
                              vpn.isConnected
                                  ? vpn.currentServer
                                  : 'Auto-Select Best',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15),
                            ),
                          ]),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        color: Colors.white38),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeSelectorCard extends StatelessWidget {
  final List<_ModeConfig> modes;
  final String selectedMode;
  final ValueChanged<String> onModeChanged;
  const _ModeSelectorCard(
      {required this.modes,
      required this.selectedMode,
      required this.onModeChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('VPN Mode',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 18)),
          const SizedBox(height: 8),
          const Text('Choose how Atmos VPN protects you',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 20),
          ...modes.map((m) => _ModeRow(
              config: m,
              isSelected: selectedMode == m.id,
              onTap: () => onModeChanged(m.id))),
        ],
      ),
    );
  }
}

class _ModeRow extends StatefulWidget {
  final _ModeConfig config;
  final bool isSelected;
  final VoidCallback onTap;
  const _ModeRow(
      {required this.config, required this.isSelected, required this.onTap});

  @override
  State<_ModeRow> createState() => _ModeRowState();
}

class _ModeRowState extends State<_ModeRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? widget.config.color.withValues(alpha: 0.12)
                : _hovered
                    ? Colors.white.withValues(alpha: 0.04)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: widget.isSelected
                  ? widget.config.color.withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: widget.config.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(widget.config.icon,
                    color: widget.config.color, size: 18),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.config.name,
                          style: TextStyle(
                              color: widget.isSelected
                                  ? Colors.white
                                  : Colors.white70,
                              fontWeight: FontWeight.w700,
                              fontSize: 14)),
                      Text(widget.config.desc,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 11)),
                    ]),
              ),
              if (widget.isSelected)
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                      color: widget.config.color, shape: BoxShape.circle),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatCard(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16)),
          ]),
        ],
      ),
    );
  }
}

class _RecentServersCard extends StatelessWidget {
  final VoidCallback onViewMap;
  const _RecentServersCard({required this.onViewMap});

  final _servers = const [
    ('🇬🇧', 'London, UK', '18ms', 'Ultra Fast', 'Streaming'),
    ('🇺🇸', 'New York, USA', '85ms', 'Fast', 'Gaming'),
    ('🇩🇪', 'Frankfurt, Germany', '25ms', 'Ultra Fast', 'Standard'),
    ('🇯🇵', 'Tokyo, Japan', '150ms', 'Good', 'Streaming'),
    ('🇸🇬', 'Singapore', '120ms', 'Fast', 'Crypto'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('Recent Servers',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18)),
            const Spacer(),
            TextButton.icon(
              onPressed: onViewMap,
              icon: const Icon(Icons.map_rounded, size: 16),
              label: const Text('VIEW MAP',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
              style:
                  TextButton.styleFrom(foregroundColor: AppColors.accentPurple),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => Navigator.pushNamed(context, '/server-list'),
              child: const Text('VIEW ALL',
                  style: TextStyle(
                      color: AppColors.primaryBlue,
                      fontSize: 11,
                      fontWeight: FontWeight.w900)),
            ),
          ]),
          const SizedBox(height: 20),
          ..._servers.map((s) => _ServerRow(
              flag: s.$1, name: s.$2, ping: s.$3, speed: s.$4, type: s.$5)),
        ],
      ),
    );
  }
}

class _ServerRow extends StatefulWidget {
  final String flag, name, ping, speed, type;
  const _ServerRow(
      {required this.flag,
      required this.name,
      required this.ping,
      required this.speed,
      required this.type});

  @override
  State<_ServerRow> createState() => _ServerRowState();
}

class _ServerRowState extends State<_ServerRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _hovered
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Text(widget.flag, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
                    Text('${widget.speed} • ${widget.type}',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 11)),
                  ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(widget.ping,
                  style: const TextStyle(
                      color: AppColors.success,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 12),
            if (_hovered)
              ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Connect',
                    style:
                        TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
              )
            else
              const SizedBox(width: 72),
          ],
        ),
      ),
    );
  }
}

class _QuickFeaturesCard extends StatefulWidget {
  @override
  State<_QuickFeaturesCard> createState() => _QuickFeaturesCardState();
}

class _QuickFeaturesCardState extends State<_QuickFeaturesCard> {
  final Map<String, bool> _toggles = {
    'Kill Switch': true,
    'DNS Leak Guard': true,
    'Auto Connect': false,
    'Ad Blocker': true,
    'Split Tunneling': false,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Security Features',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 18)),
              TextButton(
                onPressed: () => Navigator.pushNamed(context, '/security'),
                child: const Text('MANAGE ALL',
                    style: TextStyle(
                        color: AppColors.primaryBlue,
                        fontWeight: FontWeight.w900,
                        fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ..._toggles.entries.map((e) => _ToggleRow(
                label: e.key,
                value: e.value,
                onChanged: (v) => setState(() => _toggles[e.key] = v),
              )),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ToggleRow(
      {required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: value
                  ? AppColors.success
                  : Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Text(label,
                  style: const TextStyle(color: Colors.white70, fontSize: 14))),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.primaryBlue,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}

class _UpgradeBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => Navigator.pushNamed(context, '/account/pricing'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primaryBlue, AppColors.accentPurple],
            ),
            borderRadius: BorderRadius.circular(30),
          ),
          child: const Text('⚡ Upgrade to Pro',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: Colors.white)),
        ),
      ),
    );
  }
}

// _AdBanner removed in favor of common UpgradeBanner

class _Glow extends StatelessWidget {
  final Color color;
  final double size;
  const _Glow(this.color, this.size);

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

class _ConnectRingPainter extends CustomPainter {
  final double t;
  final bool connected;
  final Color color;
  _ConnectRingPainter(this.t, this.connected, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color.withValues(alpha: 0.15);
    canvas.drawCircle(center, r - 1, bg);

    if (connected) {
      final fill = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = AppColors.success.withValues(alpha: 0.8);
      canvas.drawCircle(center, r - 1, fill);
    } else {
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.7);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r - 1),
        -math.pi / 2,
        2 * math.pi * (0.7 + 0.1 * t),
        false,
        arc,
      );
    }
  }

  @override
  bool shouldRepaint(_ConnectRingPainter old) => true;
}

class _ModeConfig {
  final String id, name, desc;
  final IconData icon;
  final Color color;
  const _ModeConfig(this.id, this.name, this.desc, this.icon, this.color);
}
