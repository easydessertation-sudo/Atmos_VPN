import 'package:flutter/material.dart';
import '../../utils/design_system.dart';
import 'landing_footer.dart';
import '../../utils/responsive.dart';

// ─────────────────────────────────────────────────────────────────
// Shared web page scaffold
// ─────────────────────────────────────────────────────────────────
class _WebPageShell extends StatelessWidget {
  final String title;
  final List<Widget> sections;
  final Widget? footer;
  const _WebPageShell({required this.title, required this.sections, this.footer});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _MiniNav(title: title)),
          ...sections.map((s) => SliverToBoxAdapter(child: s)),
          SliverToBoxAdapter(child: footer ?? const LandingFooter()),
        ],
      ),
    );
  }
}

class _MiniNav extends StatelessWidget {
  final String title;
  const _MiniNav({required this.title});

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 60, vertical: isMobile ? 14 : 20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.07))),
      ),
      child: isMobile
          ? Row(children: [
              _LogoHomeLink(),
              const Spacer(),
              Text('/ $title', style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12)),
              const SizedBox(width: 10),
              _NavMenu(title: title),
            ])
          : Row(children: [
              _LogoHomeLink(),
              const SizedBox(width: 32),
              Text('/ $title', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 14)),
              const Spacer(),
              _NavChip('Features', '/features', context),
              _NavChip('Pricing', '/pricing', context),
              _NavChip('Servers', '/servers', context),
              const SizedBox(width: 20),
              TextButton(onPressed: () => Navigator.pushNamed(context, '/login'), child: const Text('Log In', style: TextStyle(color: Colors.white70))),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => Navigator.pushNamed(context, '/signup'),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: const Text('Get Started', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ]),
    );
  }
}

class _LogoHomeLink extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => Navigator.pushNamedAndRemoveUntil(context, '/', (r) => false),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.shield_rounded, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          const Text('Atmos VPN', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white)),
        ]),
      ),
    );
  }
}

class _NavMenu extends StatelessWidget {
  final String title;
  const _NavMenu({required this.title});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Menu',
      color: AppColors.cardBackground,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      offset: const Offset(0, 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      constraints: const BoxConstraints(minWidth: 200),
      icon: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: const Icon(Icons.menu_rounded, color: Colors.white, size: 20),
      ),
      onSelected: (value) {
        if (value.startsWith('route:')) {
          Navigator.pushNamed(context, value.replaceFirst('route:', ''));
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          height: 44,
          value: 'title',
          child: Row(children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.navigation_rounded, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 10),
            const Text('Navigate', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ]),
        ),
        PopupMenuItem<String>(
          enabled: false,
          height: 28,
          value: 'subtitle',
          child: Text('/ $title', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11)),
        ),
        const PopupMenuDivider(height: 12),
        PopupMenuItem<String>(
          value: 'route:/features',
          height: 44,
          child: _MenuRow(icon: Icons.auto_awesome_rounded, label: 'Features'),
        ),
        PopupMenuItem<String>(
          value: 'route:/pricing',
          height: 44,
          child: _MenuRow(icon: Icons.payments_rounded, label: 'Pricing'),
        ),
        PopupMenuItem<String>(
          value: 'route:/servers',
          height: 44,
          child: _MenuRow(icon: Icons.public_rounded, label: 'Servers'),
        ),
        const PopupMenuDivider(height: 12),
        PopupMenuItem<String>(
          value: 'route:/login',
          height: 44,
          child: _MenuRow(icon: Icons.login_rounded, label: 'Log In'),
        ),
        PopupMenuItem<String>(
          value: 'route:/signup',
          height: 46,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(children: [
              Icon(Icons.bolt_rounded, color: Colors.white, size: 16),
              SizedBox(width: 8),
              Text('Get Started', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
            ]),
          ),
        ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MenuRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Icon(icon, color: Colors.white, size: 16),
      ),
      const SizedBox(width: 10),
      Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
    ]);
  }
}

Widget _NavChip(String label, String route, BuildContext context) => TextButton(
  onPressed: () => Navigator.pushNamed(context, route),
  child: Text(label, style: const TextStyle(color: Colors.white60, fontSize: 14)),
);



Widget _sectionHeader(String tag, String title, [String? subtitle]) {
  return Column(children: [
    Text(tag.toUpperCase(), style: const TextStyle(color: AppColors.primaryBlue, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2)),
    const SizedBox(height: 12),
    Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900, height: 1.2)),
    if (subtitle != null) ...[
      const SizedBox(height: 12),
      Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary, fontSize: 16, height: 1.6)),
    ],
  ]);
}

// ─────────────────────────────────────────────────────────────────
// FEATURES PAGE
// ─────────────────────────────────────────────────────────────────
class FeaturesPage extends StatelessWidget {
  const FeaturesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _WebPageShell(title: 'Features', footer: const LandingFooter(), sections: [
      _FeaturesHero(),
      _FeaturesGrid(),
      _ProtocolSection(),
      _KillSwitchSection(),
      _NoLogsSection(),
      _CtaBanner('Everything you need. One subscription.', context),
    ]);
  }
}

class _FeaturesHero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 100, horizontal: 60),
      child: Column(children: [
        _sectionHeader('ENTERPRISE SECURITY', 'Features built for the\nmodern internet.', 'We don\'t cut corners. Every feature is engineered for performance, privacy, and reliability.'),
        const SizedBox(height: 56),
        Wrap(
          spacing: 20, runSpacing: 20, alignment: WrapAlignment.center,
          children: [
            _BigFeatureCard(Icons.shield_rounded, 'AES-256 Encryption', 'The same encryption standard used by NATO, banks, and intelligence agencies worldwide.', AppColors.primaryBlue),
            _BigFeatureCard(Icons.block_rounded, 'Advanced Kill Switch', 'App-level and system-level kill switch instantly terminates traffic if the VPN tunnel drops. Your real IP is never exposed.', AppColors.accentPurple),
            _BigFeatureCard(Icons.visibility_off_rounded, 'Strict No-Logs Policy', 'Independently audited by Cure53. We operate RAM-only infrastructure — nothing is ever written to disk.', AppColors.success),
            _BigFeatureCard(Icons.bolt_rounded, 'Lightway Protocol', 'Our proprietary protocol is built on wolfSSL for speeds up to 3× faster than OpenVPN with lower CPU usage.', AppColors.warning),
            _BigFeatureCard(Icons.call_split_rounded, 'Split Tunneling', 'Route specific apps through the VPN while others use your regular connection. Full control at the app level.', AppColors.primaryBlue),
            _BigFeatureCard(Icons.dns_rounded, 'Secure DNS Resolver', 'All DNS queries route through our private encrypted resolver. No third-party DNS providers, no leaks.', AppColors.accentPurple),
            _BigFeatureCard(Icons.wifi_rounded, 'Auto WiFi Protect', 'Automatically connects to VPN on untrusted public WiFi networks — cafés, airports, hotels.', AppColors.success),
            _BigFeatureCard(Icons.router_rounded, 'Router Support', 'Install Atmos VPN directly on your router to protect every device in your home or office.', AppColors.warning),
          ],
        ),
      ]),
    );
  }
}

class _BigFeatureCard extends StatefulWidget {
  final IconData icon;
  final String title, desc;
  final Color color;
  const _BigFeatureCard(this.icon, this.title, this.desc, this.color);

  @override
  State<_BigFeatureCard> createState() => _BigFeatureCardState();
}

class _BigFeatureCardState extends State<_BigFeatureCard> {
  bool _hov = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hov = true),
      onExit: (_) => setState(() => _hov = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 340,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: _hov ? widget.color.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _hov ? widget.color.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.06)),
          boxShadow: _hov ? [BoxShadow(color: widget.color.withValues(alpha: 0.08), blurRadius: 30)] : [],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: widget.color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: Icon(widget.icon, color: widget.color, size: 24)),
          const SizedBox(height: 20),
          Text(widget.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 10),
          Text(widget.desc, style: const TextStyle(color: AppColors.textSecondary, height: 1.6, fontSize: 14)),
        ]),
      ),
    );
  }
}

class _FeaturesGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final items = [
      ('Multi-hop / Double VPN', 'Route through two servers for maximum anonymity'),
      ('Obfuscated Servers', 'Disguise VPN traffic as regular HTTPS — works in China & Russia'),
      ('Onion Over VPN', 'Combine Tor network with VPN for ultimate privacy'),
      ('Dedicated IP', 'Get a static IP address on the Elite & Ultimate plans'),
      ('P2P / Torrenting', 'Optimized high-speed servers for BitTorrent and P2P sharing'),
      ('Ad & Tracker Blocker', 'Block ads, malware, and tracking scripts at the DNS level'),
      ('Dark Web Monitor', 'Get alerts if your credentials appear in a data breach'),
      ('Password Generator', 'Create secure passwords directly within the app'),
      ('Streaming Unlock', 'Netflix, Disney+, BBC iPlayer, Hulu — all unblocked'),
      ('Gaming Mode', 'Sub-20ms optimized paths with DDoS protection'),
      ('IPv6 Leak Protection', 'Full IPv6 support with automatic leak prevention'),
      ('WebRTC Leak Guard', 'Blocks browser-based WebRTC IP leaks automatically'),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(60, 0, 60, 100),
      child: Column(children: [
        _sectionHeader('FULL FEATURE LIST', 'Everything included.'),
        const SizedBox(height: 48),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          children: items.map((item) => Container(
            width: 340,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withValues(alpha: 0.06))),
            child: Row(children: [
              const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.$1, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                Text(item.$2, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4)),
              ])),
            ]),
          )).toList(),
        ),
      ]),
    );
  }
}

class _ProtocolSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return Container(
      color: Colors.black.withValues(alpha: 0.2),
      padding: EdgeInsets.symmetric(vertical: 80, horizontal: isMobile ? 20 : 80),
      child: Column(children: [
        _sectionHeader('VPN PROTOCOLS', 'Choose your connection protocol.', 'All protocols are available on every plan. Our app automatically selects the best one for your network.'),
        const SizedBox(height: 48),
        if (isMobile)
          Column(children: [
            _ProtoCard('WireGuard', Icons.flash_on_rounded, AppColors.success, 'Latest generation protocol. Blazing-fast, lightweight, and extremely secure.', ['Fastest', 'Best for mobile', 'CPU efficient']),
            const SizedBox(height: 16),
            _ProtoCard('OpenVPN', Icons.lock_rounded, AppColors.primaryBlue, 'Battle-tested protocol used for over 20 years. Maximum compatibility and very strong security.', ['Most compatible', 'TCP & UDP', 'Audited']),
            const SizedBox(height: 16),
            _ProtoCard('IKEv2/IPSec', Icons.phone_android_rounded, AppColors.accentPurple, 'Designed for mobile devices. Reconnects instantly when switching between WiFi and mobile data.', ['Mobile optimised', 'Fast reconnect', 'Battery friendly']),
            const SizedBox(height: 16),
            _ProtoCard('Lightway', Icons.bolt_rounded, AppColors.warning, 'Our proprietary protocol built on wolfSSL. 3× faster than OpenVPN with 10× less code.', ['Proprietary', 'Ultra fast', 'Audited']),
          ])
        else
          Row(children: [
            Expanded(child: _ProtoCard('WireGuard', Icons.flash_on_rounded, AppColors.success, 'Latest generation protocol. Blazing-fast, lightweight, and extremely secure.', ['Fastest', 'Best for mobile', 'CPU efficient'])),
            const SizedBox(width: 20),
            Expanded(child: _ProtoCard('OpenVPN', Icons.lock_rounded, AppColors.primaryBlue, 'Battle-tested protocol used for over 20 years. Maximum compatibility and very strong security.', ['Most compatible', 'TCP & UDP', 'Audited'])),
            const SizedBox(width: 20),
            Expanded(child: _ProtoCard('IKEv2/IPSec', Icons.phone_android_rounded, AppColors.accentPurple, 'Designed for mobile devices. Reconnects instantly when switching between WiFi and mobile data.', ['Mobile optimised', 'Fast reconnect', 'Battery friendly'])),
            const SizedBox(width: 20),
            Expanded(child: _ProtoCard('Lightway', Icons.bolt_rounded, AppColors.warning, 'Our proprietary protocol built on wolfSSL. 3× faster than OpenVPN with 10× less code.', ['Proprietary', 'Ultra fast', 'Audited'])),
          ]),
      ]),
    );
  }
}

class _ProtoCard extends StatelessWidget {
  final String name, desc;
  final IconData icon;
  final Color color;
  final List<String> tags;
  const _ProtoCard(this.name, this.icon, this.color, this.desc, this.tags);

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return Container(
      constraints: isMobile ? const BoxConstraints(maxWidth: 360) : null,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withValues(alpha: 0.2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 14),
        Text(name, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 18)),
        const SizedBox(height: 8),
        Text(desc, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5)),
        const SizedBox(height: 16),
        Wrap(spacing: 6, runSpacing: 6, children: tags.map((t) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
          child: Text(t, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800)),
        )).toList()),
      ]),
    );
  }
}

class _KillSwitchSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return Container(
      margin: EdgeInsets.symmetric(vertical: isMobile ? 40 : 60, horizontal: isMobile ? 16 : 60),
      padding: EdgeInsets.all(isMobile ? 28 : 60),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [AppColors.primaryBlue.withValues(alpha: 0.1), AppColors.accentPurple.withValues(alpha: 0.06)]),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.15)),
      ),
      child: isMobile
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('KILL SWITCH', style: TextStyle(color: AppColors.primaryBlue, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2)),
              const SizedBox(height: 12),
              const Text('Your last line of defence.', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 28, height: 1.2)),
              const SizedBox(height: 12),
              Text('If the VPN connection drops for any reason, the kill switch immediately blocks all internet traffic — protecting your real IP from ever being exposed.', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), height: 1.6, fontSize: 14)),
              const SizedBox(height: 18),
              ...['App-level kill switch (block specific apps)', 'System-level kill switch (block all traffic)', 'Instant trigger — zero leak window', 'Available on all platforms'].map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  const Icon(Icons.check_rounded, color: AppColors.success, size: 16),
                  const SizedBox(width: 10),
                  Expanded(child: Text(f, style: const TextStyle(color: Colors.white70, fontSize: 13))),
                ]),
              )),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white.withValues(alpha: 0.06))),
                child: Column(children: [
                  const Icon(Icons.power_off_rounded, color: AppColors.success, size: 52),
                  const SizedBox(height: 12),
                  const Text('Kill Switch Active', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w900, fontSize: 18)),
                  const SizedBox(height: 6),
                  const Text('Your IP is always protected', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ]),
              ),
            ])
          : Row(children: [
              Expanded(flex: 5, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('KILL SWITCH', style: TextStyle(color: AppColors.primaryBlue, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2)),
                const SizedBox(height: 16),
                const Text('Your last line of defence.', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 36, height: 1.2)),
                const SizedBox(height: 16),
                Text('If the VPN connection drops for any reason, the kill switch immediately blocks all internet traffic — protecting your real IP from ever being exposed.', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), height: 1.7, fontSize: 16)),
                const SizedBox(height: 24),
                ...['App-level kill switch (block specific apps)', 'System-level kill switch (block all traffic)', 'Instant trigger — zero leak window', 'Available on all platforms'].map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(children: [
                    const Icon(Icons.check_rounded, color: AppColors.success, size: 16),
                    const SizedBox(width: 10),
                    Text(f, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                  ]),
                )),
              ])),
              const SizedBox(width: 60),
              Expanded(flex: 4, child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: 0.06))),
                child: Column(children: [
                  const Icon(Icons.power_off_rounded, color: AppColors.success, size: 64),
                  const SizedBox(height: 16),
                  const Text('Kill Switch Active', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w900, fontSize: 20)),
                  const SizedBox(height: 8),
                  const Text('Your IP is always protected', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                ]),
              )),
            ]),
    );
  }
}

class _NoLogsSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return Container(
      padding: EdgeInsets.symmetric(vertical: 80, horizontal: isMobile ? 20 : 60),
      child: Column(children: [
        _sectionHeader('ZERO LOGS', 'We see nothing. We know nothing.', 'Our no-logs policy has been independently verified by Cure53, the world\'s leading cybersecurity firm.'),
        const SizedBox(height: 60),
        if (isMobile)
          Column(children: [
            _LogCard('✗', 'IP Addresses', 'We never store your real IP or assign-on connect IP'),
            const SizedBox(height: 14),
            _LogCard('✗', 'Browsing History', 'What sites you visit is your business, not ours'),
            const SizedBox(height: 14),
            _LogCard('✗', 'Timestamps', 'When you connect or disconnects is never logged'),
            const SizedBox(height: 14),
            _LogCard('✗', 'Bandwidth', 'How much data you use is not tracked'),
            const SizedBox(height: 14),
            _LogCard('✗', 'DNS Queries', 'Every DNS lookup is encrypted and discarded'),
          ])
        else
          Row(children: [
            Expanded(child: _LogCard('✗', 'IP Addresses', 'We never store your real IP or assign-on connect IP')),
            const SizedBox(width: 16),
            Expanded(child: _LogCard('✗', 'Browsing History', 'What sites you visit is your business, not ours')),
            const SizedBox(width: 16),
            Expanded(child: _LogCard('✗', 'Timestamps', 'When you connect or disconnects is never logged')),
            const SizedBox(width: 16),
            Expanded(child: _LogCard('✗', 'Bandwidth', 'How much data you use is not tracked')),
            const SizedBox(width: 16),
            Expanded(child: _LogCard('✗', 'DNS Queries', 'Every DNS lookup is encrypted and discarded')),
          ]),
      ]),
    );
  }
}

class _LogCard extends StatelessWidget {
  final String icon, title, desc;
  const _LogCard(this.icon, this.title, this.desc);

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final card = Container(
      width: isMobile ? double.infinity : null,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withValues(alpha: 0.15)),
      ),
      child: Column(children: [
        Text(icon, style: const TextStyle(color: Colors.red, fontSize: 24, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
        const SizedBox(height: 6),
        Text(desc, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, height: 1.4)),
      ]),
    );

    if (!isMobile) return card;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: card,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// HOW VPN WORKS PAGE
// ─────────────────────────────────────────────────────────────────
class HowVpnWorksPage extends StatelessWidget {
  const HowVpnWorksPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _WebPageShell(title: 'How VPN Works', sections: [
      _HowHero(),
      _HowSteps(),
      _EncryptionExplainer(),
      _UseCases(),
      _CtaBanner('Start protecting yourself in 60 seconds.', context),
    ]);
  }
}

class _HowHero extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 100, horizontal: 60),
    child: Column(children: [
      _sectionHeader('HOW IT WORKS', 'Your data, encrypted\nfrom point A to point B.', 'A VPN creates a secure, encrypted tunnel between your device and the internet. Here\'s exactly what happens when you connect.'),
    ]),
  );
}

class _HowSteps extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final steps = [
      ('1', 'You connect', 'You open the app and hit Connect. Atmos VPN establishes an encrypted tunnel to one of our 6,500+ servers using your chosen protocol.', Icons.wifi_rounded),
      ('2', 'Your traffic is encrypted', 'Every packet of data leaving your device is encrypted with AES-256 before it leaves. Not even your ISP can see what you\'re doing.', Icons.lock_rounded),
      ('3', 'Your IP is masked', 'To the rest of the internet, your requests appear to come from the VPN server\'s IP address — not your real location.', Icons.public_rounded),
      ('4', 'You browse freely', 'Access any content, in any country, with full privacy. The VPN server fetches content on your behalf and sends it back encrypted.', Icons.explore_rounded),
    ];

    return Container(
      color: Colors.black.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 60),
      child: Column(children: [
        ...steps.asMap().entries.map((e) {
          final i = e.key;
          final s = e.value;
          final isRight = i % 2 == 1;
          return Padding(
            padding: const EdgeInsets.only(bottom: 60),
            child: Row(
              children: isRight
                  ? [_HowVisual(s.$4, AppColors.primaryBlue), const SizedBox(width: 60), Expanded(child: _HowText(s.$1, s.$2, s.$3))]
                  : [Expanded(child: _HowText(s.$1, s.$2, s.$3)), const SizedBox(width: 60), _HowVisual(s.$4, AppColors.accentPurple)],
            ),
          );
        }),
      ]),
    );
  }
}

class _HowText extends StatelessWidget {
  final String num, title, desc;
  const _HowText(this.num, this.title, this.desc);

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('Step $num', style: const TextStyle(color: AppColors.primaryBlue, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 2)),
    const SizedBox(height: 12),
    Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 32)),
    const SizedBox(height: 16),
    Text(desc, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 16, height: 1.7)),
  ]);
}

class _HowVisual extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _HowVisual(this.icon, this.color);

  @override
  Widget build(BuildContext context) => Container(
    width: 220,
    height: 220,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      shape: BoxShape.circle,
      border: Border.all(color: color.withValues(alpha: 0.2)),
    ),
    child: Center(child: Icon(icon, color: color, size: 80)),
  );
}

class _EncryptionExplainer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(children: [
        _sectionHeader('AES-256 ENCRYPTION', 'Unbreakable. Literally.'),
        const SizedBox(height: 32),
        Text(
          'AES-256 encryption has 2²⁵⁶ possible keys. If every atom in the observable universe were a computer running at maximum speed since the Big Bang, it still wouldn\'t have cracked a single key. That\'s how secure your data is with Atmos VPN.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 16, height: 1.8),
        ),
        const SizedBox(height: 32),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _EncBadge('AES-256-GCM'),
          const SizedBox(width: 12),
          _EncBadge('RSA-4096 Handshake'),
          const SizedBox(width: 12),
          _EncBadge('HMAC-SHA256'),
          const SizedBox(width: 12),
          _EncBadge('Perfect Forward Secrecy'),
        ]),
      ]),
    );
  }
}

class _EncBadge extends StatelessWidget {
  final String label;
  const _EncBadge(this.label);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    decoration: BoxDecoration(color: AppColors.primaryBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.25))),
    child: Text(label, style: const TextStyle(color: AppColors.primaryBlue, fontWeight: FontWeight.w700, fontSize: 12)),
  );
}

class _UseCases extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 60),
      child: Column(children: [
        _sectionHeader('USE CASES', 'Why people use Atmos VPN.'),
        const SizedBox(height: 48),
        Wrap(spacing: 24, runSpacing: 24, alignment: WrapAlignment.center, children: [
          _UseCase(Icons.movie_rounded, 'Streaming', 'Unlock Netflix US, BBC iPlayer, Disney+ and 50+ streaming services from anywhere in the world.', const Color(0xFF8B5CF6)),
          _UseCase(Icons.sports_esports_rounded, 'Gaming', 'Get lower ping by connecting to game servers in your target region. Stop DDoS attacks.', const Color(0xFFF97316)),
          _UseCase(Icons.currency_bitcoin_rounded, 'Crypto Trading', 'Protect your exchange sessions with an isolated secure tunnel and anti-phishing DNS.', const Color(0xFFF59E0B)),
          _UseCase(Icons.business_rounded, 'Remote Work', 'Securely access your company network from anywhere with enterprise-grade encryption.', const Color(0xFF3B82F6)),
          _UseCase(Icons.folder_zip_rounded, 'Torrenting', 'P2P-optimised servers with no speed caps and SOCKS5 proxy support.', const Color(0xFF10B981)),
          _UseCase(Icons.school_rounded, 'Research & Privacy', 'Browse sensitive topics without your ISP or government monitoring your activity.', const Color(0xFFEF4444)),
        ]),
      ]),
    );
  }
}

class _UseCase extends StatefulWidget {
  final IconData icon;
  final String title, desc;
  final Color color;
  const _UseCase(this.icon, this.title, this.desc, this.color);

  @override
  State<_UseCase> createState() => _UseCaseState();
}

class _UseCaseState extends State<_UseCase> {
  bool _hov = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hov = true),
      onExit: (_) => setState(() => _hov = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 300,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: _hov ? widget.color.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _hov ? widget.color.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: widget.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)), child: Icon(widget.icon, color: widget.color, size: 22)),
          const SizedBox(height: 16),
          Text(widget.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 8),
          Text(widget.desc, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// ABOUT US PAGE
// ─────────────────────────────────────────────────────────────────
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _WebPageShell(title: 'About Us', sections: [
      Responsive(
        mobile: _AboutMobile(),
        tablet: _AboutTablet(),
        desktop: _AboutDesktop(),
      ),
    ]);
  }
}

class _AboutMobile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 20),
      child: Column(children: [
        _sectionHeader('ABOUT ATMOS VPN', 'Built by privacy advocates.\nFor everyone.', 'Atmos VPN was founded in 2024 by a team of cybersecurity engineers, ex-intelligence analysts, and privacy advocates. We believe internet privacy is a fundamental right — not a luxury.'),
        const SizedBox(height: 48),
        Column(children: [
          _ValueCard(Icons.verified_user_rounded, 'Our Mission', 'Make enterprise-grade privacy accessible and affordable for everyone on Earth.', AppColors.primaryBlue, isMobile: true),
          const SizedBox(height: 16),
          _ValueCard(Icons.visibility_off_rounded, 'Our Values', 'Transparency, privacy, and security guide every decision we make — from code to policy.', AppColors.accentPurple, isMobile: true),
          const SizedBox(height: 16),
          _ValueCard(Icons.public_rounded, 'Our Reach', '14 million users across 180 countries trust Atmos VPN to protect their digital lives.', AppColors.success, isMobile: true),
        ]),
        const SizedBox(height: 48),
        _sectionHeader('OUR STORY', 'From a small team to\n14 million users.'),
        const SizedBox(height: 32),
        Text(
          'Atmos VPN was born from frustration. Our founders — a group of security engineers who spent years working in enterprise cybersecurity — watched as consumer VPN products consistently failed to meet the security standards of professional tools.\n\nWe decided to build the VPN we always wanted: one that combines the security rigour of enterprise tools with the simplicity of a consumer app. No compromises. No dark patterns. No data selling.\n\nToday, Atmos VPN protects journalists in authoritarian regimes, activists in conflict zones, gamers who want fair competition, and everyday people who simply want their privacy back.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 15, height: 1.8),
        ),
        const SizedBox(height: 48),
        _CtaBanner('Join 14 million people who chose privacy.', context),
      ]),
    );
  }
}

class _AboutTablet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 40),
      child: Column(children: [
        _sectionHeader('ABOUT ATMOS VPN', 'Built by privacy advocates.\nFor everyone.', 'Atmos VPN was founded in 2024 by a team of cybersecurity engineers, ex-intelligence analysts, and privacy advocates. We believe internet privacy is a fundamental right — not a luxury.'),
        const SizedBox(height: 56),
        Row(children: [
          Expanded(child: _ValueCard(Icons.verified_user_rounded, 'Our Mission', 'Make enterprise-grade privacy accessible and affordable for everyone on Earth.', AppColors.primaryBlue)),
          const SizedBox(width: 20),
          Expanded(child: _ValueCard(Icons.visibility_off_rounded, 'Our Values', 'Transparency, privacy, and security guide every decision we make — from code to policy.', AppColors.accentPurple)),
          const SizedBox(width: 20),
          Expanded(child: _ValueCard(Icons.public_rounded, 'Our Reach', '14 million users across 180 countries trust Atmos VPN to protect their digital lives.', AppColors.success)),
        ]),
        const SizedBox(height: 56),
        _sectionHeader('OUR STORY', 'From a small team to\n14 million users.'),
        const SizedBox(height: 32),
        Container(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Text(
            'Atmos VPN was born from frustration. Our founders — a group of security engineers who spent years working in enterprise cybersecurity — watched as consumer VPN products consistently failed to meet the security standards of professional tools.\n\nWe decided to build the VPN we always wanted: one that combines the security rigour of enterprise tools with the simplicity of a consumer app. No compromises. No dark patterns. No data selling.\n\nToday, Atmos VPN protects journalists in authoritarian regimes, activists in conflict zones, gamers who want fair competition, and everyday people who simply want their privacy back.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 16, height: 1.9),
          ),
        ),
        const SizedBox(height: 56),
        _CtaBanner('Join 14 million people who chose privacy.', context),
      ]),
    );
  }
}

class _AboutDesktop extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 100, horizontal: 60),
      child: Column(children: [
        _sectionHeader('ABOUT ATMOS VPN', 'Built by privacy advocates.\nFor everyone.', 'Atmos VPN was founded in 2024 by a team of cybersecurity engineers, ex-intelligence analysts, and privacy advocates. We believe internet privacy is a fundamental right — not a luxury.'),
        const SizedBox(height: 72),
        Row(children: [
          Expanded(child: _ValueCard(Icons.verified_user_rounded, 'Our Mission', 'Make enterprise-grade privacy accessible and affordable for everyone on Earth.', AppColors.primaryBlue)),
          const SizedBox(width: 24),
          Expanded(child: _ValueCard(Icons.visibility_off_rounded, 'Our Values', 'Transparency, privacy, and security guide every decision we make — from code to policy.', AppColors.accentPurple)),
          const SizedBox(width: 24),
          Expanded(child: _ValueCard(Icons.public_rounded, 'Our Reach', '14 million users across 180 countries trust Atmos VPN to protect their digital lives.', AppColors.success)),
        ]),
        const SizedBox(height: 72),
        _sectionHeader('OUR STORY', 'From a small team to\n14 million users.'),
        const SizedBox(height: 40),
        Container(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Text(
            'Atmos VPN was born from frustration. Our founders — a group of security engineers who spent years working in enterprise cybersecurity — watched as consumer VPN products consistently failed to meet the security standards of professional tools.\n\nWe decided to build the VPN we always wanted: one that combines the security rigour of enterprise tools with the simplicity of a consumer app. No compromises. No dark patterns. No data selling.\n\nToday, Atmos VPN protects journalists in authoritarian regimes, activists in conflict zones, gamers who want fair competition, and everyday people who simply want their privacy back.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 16, height: 1.9),
          ),
        ),
        const SizedBox(height: 72),
        _CtaBanner('Join 14 million people who chose privacy.', context),
      ]),
    );
  }
}

class _ValueCard extends StatelessWidget {
  final IconData icon;
  final String title, desc;
  final Color color;
  final bool isMobile;
  const _ValueCard(this.icon, this.title, this.desc, this.color, {this.isMobile = false});

  @override
  Widget build(BuildContext context) => Container(
    width: isMobile ? double.infinity : null,
    padding: EdgeInsets.all(isMobile ? 24 : 32),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withValues(alpha: 0.2))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: color, size: isMobile ? 24 : 28),
      SizedBox(height: isMobile ? 14 : 18),
      Text(title, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: isMobile ? 18 : 20)),
      SizedBox(height: isMobile ? 8 : 10),
      Text(desc, style: TextStyle(color: AppColors.textSecondary, height: 1.6, fontSize: isMobile ? 13 : 14)),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────
// PRIVACY POLICY PAGE
// ─────────────────────────────────────────────────────────────────
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _WebPageShell(title: 'Privacy Policy', sections: [
      Responsive(
        mobile: _LegalPageMobile(
          title: 'Privacy Policy',
          lastUpdated: 'March 2026',
          sections: [
            ('1. Introduction', 'Atmos VPN Ltd ("we", "our", "us") is committed to protecting your privacy. This policy explains how we handle data in connection with our VPN service. tl;dr: We collect the minimum data necessary to provide the service, and we never sell or share your data with third parties for marketing purposes.'),
            ('2. What We Collect', 'Account data: Email address, hashed password, subscription plan. Payment data: Processed securely through Stripe — we never see or store your card details. Diagnostic data (optional): Crash reports that you can disable in app settings. We do NOT collect: Your IP address, browsing history, DNS queries, connection timestamps, bandwidth, or any data that could identify your activity.'),
            ('3. Zero-Logs Policy', 'Our no-logs policy is audited by Cure53 biannually. Our VPN infrastructure operates exclusively on RAM-only servers. No data is written to persistent storage. When a server restarts, all data is permanently wiped.'),
            ('4. Data Retention', 'Account data is retained until you delete your account. Payment records are kept for 7 years as required by UK accounting law. Deleted account data is purged within 30 days.'),
            ('5. Your Rights', 'Under UK GDPR, you have the right to: access your data, correct inaccurate data, request deletion, data portability, and to restrict processing. Contact privacy@atmosvpn.com to exercise these rights.'),
            ('6. Security', 'All data in transit is encrypted with TLS 1.3. Passwords are hashed using bcrypt with cost factor 12. We undergo third-party security audits annually.'),
            ('7. Contact', 'Atmos VPN Ltd, 30 Churchill Place, London, E14 5EU. Email: privacy@atmosvpn.com'),
          ],
        ),
        tablet: _LegalPage(
          title: 'Privacy Policy',
          lastUpdated: 'March 2026',
          sections: [
            ('1. Introduction', 'Atmos VPN Ltd ("we", "our", "us") is committed to protecting your privacy. This policy explains how we handle data in connection with our VPN service. tl;dr: We collect the minimum data necessary to provide the service, and we never sell or share your data with third parties for marketing purposes.'),
            ('2. What We Collect', 'Account data: Email address, hashed password, subscription plan. Payment data: Processed securely through Stripe — we never see or store your card details. Diagnostic data (optional): Crash reports that you can disable in app settings. We do NOT collect: Your IP address, browsing history, DNS queries, connection timestamps, bandwidth, or any data that could identify your activity.'),
            ('3. Zero-Logs Policy', 'Our no-logs policy is audited by Cure53 biannually. Our VPN infrastructure operates exclusively on RAM-only servers. No data is written to persistent storage. When a server restarts, all data is permanently wiped.'),
            ('4. Data Retention', 'Account data is retained until you delete your account. Payment records are kept for 7 years as required by UK accounting law. Deleted account data is purged within 30 days.'),
            ('5. Your Rights', 'Under UK GDPR, you have the right to: access your data, correct inaccurate data, request deletion, data portability, and to restrict processing. Contact privacy@atmosvpn.com to exercise these rights.'),
            ('6. Security', 'All data in transit is encrypted with TLS 1.3. Passwords are hashed using bcrypt with cost factor 12. We undergo third-party security audits annually.'),
            ('7. Contact', 'Atmos VPN Ltd, 30 Churchill Place, London, E14 5EU. Email: privacy@atmosvpn.com'),
          ],
        ),
        desktop: _LegalPage(
          title: 'Privacy Policy',
          lastUpdated: 'March 2026',
          sections: [
            ('1. Introduction', 'Atmos VPN Ltd ("we", "our", "us") is committed to protecting your privacy. This policy explains how we handle data in connection with our VPN service. tl;dr: We collect the minimum data necessary to provide the service, and we never sell or share your data with third parties for marketing purposes.'),
            ('2. What We Collect', 'Account data: Email address, hashed password, subscription plan. Payment data: Processed securely through Stripe — we never see or store your card details. Diagnostic data (optional): Crash reports that you can disable in app settings. We do NOT collect: Your IP address, browsing history, DNS queries, connection timestamps, bandwidth, or any data that could identify your activity.'),
            ('3. Zero-Logs Policy', 'Our no-logs policy is audited by Cure53 biannually. Our VPN infrastructure operates exclusively on RAM-only servers. No data is written to persistent storage. When a server restarts, all data is permanently wiped.'),
            ('4. Data Retention', 'Account data is retained until you delete your account. Payment records are kept for 7 years as required by UK accounting law. Deleted account data is purged within 30 days.'),
            ('5. Your Rights', 'Under UK GDPR, you have the right to: access your data, correct inaccurate data, request deletion, data portability, and to restrict processing. Contact privacy@atmosvpn.com to exercise these rights.'),
            ('6. Security', 'All data in transit is encrypted with TLS 1.3. Passwords are hashed using bcrypt with cost factor 12. We undergo third-party security audits annually.'),
            ('7. Contact', 'Atmos VPN Ltd, 30 Churchill Place, London, E14 5EU. Email: privacy@atmosvpn.com'),
          ],
        ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────
// TERMS OF SERVICE
// ─────────────────────────────────────────────────────────────────
class TermsPage extends StatelessWidget {
  const TermsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _WebPageShell(title: 'Terms of Service', sections: [
      Responsive(
        mobile: _LegalPageMobile(
          title: 'Terms of Service',
          lastUpdated: 'March 2026',
          sections: [
            ('1. Acceptance', 'By using Atmos VPN, you agree to these Terms of Service. If you do not agree, please stop using the service immediately.'),
            ('2. Permitted Use', 'Atmos VPN may only be used for lawful purposes. You may not use Atmos VPN to: conduct illegal activities, send spam, conduct DDoS attacks, access material that exploits children, or circumvent export restrictions.'),
            ('3. Account Responsibility', 'You are responsible for maintaining the security of your account credentials. You must notify us immediately of any unauthorised access.'),
            ('4. Free Plan Limitations', 'Free accounts are limited to 45-minute VPN sessions with standard mode only. Ads may be displayed within the app on the free plan.'),
            ('5. Subscription', 'Paid subscriptions are billed in advance. All plans include a 30-day money-back guarantee. Cancellations take effect at the end of the current billing period.'),
            ('6. Service Availability', 'We aim for 99.99% uptime but cannot guarantee uninterrupted service. Planned maintenance will be announced 24 hours in advance.'),
            ('7. Termination', 'We reserve the right to terminate accounts that violate these terms without refund. We will provide notice where possible.'),
            ('8. Governing Law', 'These terms are governed by the laws of England and Wales. Disputes will be resolved in the courts of England and Wales.'),
          ],
        ),
        tablet: _LegalPage(
          title: 'Terms of Service',
          lastUpdated: 'March 2026',
          sections: [
            ('1. Acceptance', 'By using Atmos VPN, you agree to these Terms of Service. If you do not agree, please stop using the service immediately.'),
            ('2. Permitted Use', 'Atmos VPN may only be used for lawful purposes. You may not use Atmos VPN to: conduct illegal activities, send spam, conduct DDoS attacks, access material that exploits children, or circumvent export restrictions.'),
            ('3. Account Responsibility', 'You are responsible for maintaining the security of your account credentials. You must notify us immediately of any unauthorised access.'),
            ('4. Free Plan Limitations', 'Free accounts are limited to 45-minute VPN sessions with standard mode only. Ads may be displayed within the app on the free plan.'),
            ('5. Subscription', 'Paid subscriptions are billed in advance. All plans include a 30-day money-back guarantee. Cancellations take effect at the end of the current billing period.'),
            ('6. Service Availability', 'We aim for 99.99% uptime but cannot guarantee uninterrupted service. Planned maintenance will be announced 24 hours in advance.'),
            ('7. Termination', 'We reserve the right to terminate accounts that violate these terms without refund. We will provide notice where possible.'),
            ('8. Governing Law', 'These terms are governed by the laws of England and Wales. Disputes will be resolved in the courts of England and Wales.'),
          ],
        ),
        desktop: _LegalPage(
          title: 'Terms of Service',
          lastUpdated: 'March 2026',
          sections: [
            ('1. Acceptance', 'By using Atmos VPN, you agree to these Terms of Service. If you do not agree, please stop using the service immediately.'),
            ('2. Permitted Use', 'Atmos VPN may only be used for lawful purposes. You may not use Atmos VPN to: conduct illegal activities, send spam, conduct DDoS attacks, access material that exploits children, or circumvent export restrictions.'),
            ('3. Account Responsibility', 'You are responsible for maintaining the security of your account credentials. You must notify us immediately of any unauthorised access.'),
            ('4. Free Plan Limitations', 'Free accounts are limited to 45-minute VPN sessions with standard mode only. Ads may be displayed within the app on the free plan.'),
            ('5. Subscription', 'Paid subscriptions are billed in advance. All plans include a 30-day money-back guarantee. Cancellations take effect at the end of the current billing period.'),
            ('6. Service Availability', 'We aim for 99.99% uptime but cannot guarantee uninterrupted service. Planned maintenance will be announced 24 hours in advance.'),
            ('7. Termination', 'We reserve the right to terminate accounts that violate these terms without refund. We will provide notice where possible.'),
            ('8. Governing Law', 'These terms are governed by the laws of England and Wales. Disputes will be resolved in the courts of England and Wales.'),
          ],
        ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────
// NO-LOGS AUDIT PAGE
// ─────────────────────────────────────────────────────────────────
class NoLogsAuditPage extends StatelessWidget {
  const NoLogsAuditPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _WebPageShell(title: 'No-Logs Audit', sections: [
      Container(
        padding: const EdgeInsets.symmetric(vertical: 100, horizontal: 60),
        child: Column(children: [
          _sectionHeader('SECURITY AUDIT', 'Our no-logs policy.\nIndependently verified.', 'We don\'t ask you to trust us. We hire world-class security firms to verify our claims.'),
          const SizedBox(height: 60),
          Container(
            padding: const EdgeInsets.all(48),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [AppColors.success.withValues(alpha: 0.08), AppColors.primaryBlue.withValues(alpha: 0.06)]),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.success.withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.verified_rounded, color: AppColors.success, size: 28),
                  const SizedBox(width: 12),
                  const Text('Audited by Cure53', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w900, fontSize: 22)),
                ]),
                const SizedBox(height: 16),
                Text('Cure53 is Berlin\'s leading cybersecurity research firm, trusted by Mozilla, Google, and NATO. They conducted a comprehensive audit of our entire infrastructure, codebase, and policies.', style: TextStyle(color: Colors.white.withValues(alpha: 0.55), height: 1.7, fontSize: 15)),
                const SizedBox(height: 24),
                ...['No user activity logs found', 'No timestamp records', 'No IP address logs', 'RAM-only server infrastructure verified', 'Automatic data wipe on server restart confirmed'].map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(children: [const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 16), const SizedBox(width: 10), Text(f, style: const TextStyle(color: Colors.white, fontSize: 14))]),
                )),
              ])),
              const SizedBox(width: 60),
              Expanded(flex: 2, child: Column(children: [
                Container(padding: const EdgeInsets.all(32), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: 0.07))), child: Column(children: [
                  const Icon(Icons.description_rounded, color: AppColors.primaryBlue, size: 48),
                  const SizedBox(height: 16),
                  const Text('Audit Report', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 4),
                  const Text('March 2026', style: TextStyle(color: Color.fromARGB(255, 255, 255, 255), fontSize: 14)),
                  const SizedBox(height: 20),
                  ElevatedButton(onPressed: () {}, style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: const Text('Download PDF', style: TextStyle(fontWeight: FontWeight.w800))),
                ])),
              ])),
            ]),
          ),
        ]),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────
// CONTACT PAGE
// ─────────────────────────────────────────────────────────────────
class ContactPage extends StatelessWidget {
  const ContactPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _WebPageShell(title: 'Contact', sections: [
      Container(
        padding: const EdgeInsets.symmetric(vertical: 100, horizontal: 60),
        child: Column(children: [
          _sectionHeader('CONTACT US', 'We\'re here to help.'),
          const SizedBox(height: 60),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 4, child: _ContactForm()),
            const SizedBox(width: 60),
            Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _ContactInfo(Icons.email_rounded, 'General Enquiries', 'hello@atmosvpn.com'),
              const SizedBox(height: 20),
              _ContactInfo(Icons.security_rounded, 'Security Reports', 'security@atmosvpn.com'),
              const SizedBox(height: 20),
              _ContactInfo(Icons.business_rounded, 'Business & Enterprise', 'enterprise@atmosvpn.com'),
              const SizedBox(height: 20),
              _ContactInfo(Icons.privacy_tip_rounded, 'Privacy & Legal', 'privacy@atmosvpn.com'),
              const SizedBox(height: 32),
              Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: AppColors.primaryBlue.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.2))), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Icon(Icons.headset_mic_rounded, color: AppColors.primaryBlue, size: 18), SizedBox(width: 8), Text('24/7 Live Support', style: TextStyle(color: AppColors.primaryBlue, fontWeight: FontWeight.w900))]),
                SizedBox(height: 8),
                Text('Pro & Elite users get priority 24/7 live chat support with < 2 minute response times.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5)),
              ])),
            ])),
          ]),
        ]),
      ),
    ]);
  }
}

class _ContactForm extends StatefulWidget {
  @override
  State<_ContactForm> createState() => _ContactFormState();
}

class _ContactFormState extends State<_ContactForm> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  bool _sent = false;

  @override
  Widget build(BuildContext context) {
    if (_sent) return Container(padding: const EdgeInsets.all(40), decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.success.withValues(alpha: 0.2))), child: const Column(children: [
      Icon(Icons.check_circle_rounded, color: AppColors.success, size: 56),
      SizedBox(height: 16),
      Text('Message sent!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 24)),
      SizedBox(height: 8),
      Text('We\'ll reply within 24 hours.', style: TextStyle(color: AppColors.textSecondary)),
    ]));

    return Container(padding: const EdgeInsets.all(32), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: 0.07))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Send a message', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22)),
      const SizedBox(height: 24),
      _WebField('Your Name', _nameCtrl),
      const SizedBox(height: 16),
      _WebField('Email Address', _emailCtrl),
      const SizedBox(height: 16),
      _WebField('Message', _msgCtrl, lines: 5),
      const SizedBox(height: 24),
      SizedBox(width: double.infinity, child: ElevatedButton(
        onPressed: () => setState(() => _sent = true),
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        child: const Text('Send Message', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      )),
    ]));
  }
}

class _ContactInfo extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _ContactInfo(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: AppColors.primaryBlue.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: AppColors.primaryBlue, size: 18)),
    const SizedBox(width: 14),
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w700)),
      Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
    ]),
  ]);
}

// ─────────────────────────────────────────────────────────────────
// SHARED LEGAL PAGE TEMPLATE
// ─────────────────────────────────────────────────────────────────
class _LegalPage extends StatelessWidget {
  final String title, lastUpdated;
  final List<(String, String)> sections;
  const _LegalPage({required this.title, required this.lastUpdated, required this.sections});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 120),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 40)),
        const SizedBox(height: 8),
        Text('Last updated: $lastUpdated', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        const SizedBox(height: 48),
        ...sections.map((s) => Padding(
          padding: const EdgeInsets.only(bottom: 32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.$1, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20)),
            const SizedBox(height: 12),
            Text(s.$2, style: const TextStyle(color: AppColors.textSecondary, height: 1.72, fontSize: 15)),
          ]),
        )),
      ]),
    );
  }
}

class _LegalPageMobile extends StatelessWidget {
  final String title, lastUpdated;
  final List<(String, String)> sections;
  const _LegalPageMobile({required this.title, required this.lastUpdated, required this.sections});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 48, 20, 60),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 28, height: 1.2)),
        const SizedBox(height: 6),
        Text('Last updated: $lastUpdated', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 28),
        ...sections.map((s) => Padding(
          padding: const EdgeInsets.only(bottom: 22),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.$1, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17)),
            const SizedBox(height: 10),
            Text(s.$2, style: const TextStyle(color: AppColors.textSecondary, height: 1.6, fontSize: 14)),
          ]),
        )),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// SHARED COMPONENTS
// ─────────────────────────────────────────────────────────────────
class _CtaBanner extends StatelessWidget {
  final String title;
  final BuildContext ctx;
  const _CtaBanner(this.title, this.ctx);

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return Container(
    margin: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 60, vertical: isMobile ? 40 : 60),
    padding: EdgeInsets.symmetric(vertical: isMobile ? 40 : 60, horizontal: isMobile ? 24 : 60),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [AppColors.primaryBlue.withValues(alpha: 0.2), AppColors.accentPurple.withValues(alpha: 0.12)]),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.2)),
    ),
    child: Column(children: [
      Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 36, height: 1.2)),
      const SizedBox(height: 32),
      ElevatedButton(onPressed: () => Navigator.pushNamed(ctx, '/signup'), style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)), child: const Text('Start Free — No Card Required')),
    ]),
  );
  }
}

class _FeaturesFooterContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return Container(
      padding: EdgeInsets.symmetric(vertical: isMobile ? 40 : 60, horizontal: isMobile ? 20 : 60),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                   Wrap(
                    spacing: 16,
                    children: const [
                      _SocialIcon(Icons.facebook),
                      _SocialIcon(Icons.close),
                      _SocialIcon(Icons.business),
                      _SocialIcon(Icons.play_circle_filled),
                      _SocialIcon(Icons.camera_alt_rounded),
                    ],
                  ),
                ]),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Align(
                  alignment: Alignment.topRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(children: const [
                      _StoreBadge(
                        label: 'App Store',
                        topText: 'Download on the',
                        imagePath: 'assets/images/apple-logo.png',
                      ),
                      SizedBox(width: 16),
                      _StoreBadge(
                        label: 'Google Play',
                        topText: 'GET IT ON',
                        imagePath: 'assets/images/google-play.png',
                      ),
                    ]),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final cols = wide ? 4 : 2;
            final items = [
              _FooterColumn('Atmos VPN', const [
                'About us',
                'Careers',
                'Money-back guarantee',
                'VPN routers',
                'Reviews',
                'Where to buy',
               ]),
              _FooterColumn('Engage', const [
                'What is a VPN?',
                'Cybersecurity hub',
                'Social responsibility',
                'Trust center',
                'Press area',
                'Become a partner',
              ]),
              _FooterColumn('Help', const [
                'Support center',
                'Privacy policy',
                'Cookie preferences',
                'Terms of service',
                'Contact us',
                'Ask an expert',
              ]),
              _FooterColumn('Discover', const [
                'Atmos VPN Security',
                'Atmos VPN Layer',
                'Atmos VPN Pass',
                'Atmos VPN Stellar',
                'Atmos VPN Protect',
                'Saily',
               ]),
            ];
            return Wrap(
              spacing: 32,
              runSpacing: 24,
              children: List.generate(cols, (i) => SizedBox(
                width: (constraints.maxWidth - (cols - 1) * 32) / cols,
                child: items[i],
              )),
            );
          }),
        ],
      ),
    );
  }
}

class _FooterColumn extends StatelessWidget {
  final String title;
  final List<String> items;
  const _FooterColumn(this.title, this.items);

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
      const SizedBox(height: 12),
      ...items.map((t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(t, style: const TextStyle(color: Colors.white70, fontSize: 13)),
      )),
    ]);
  }
}

class _SocialIcon extends StatelessWidget {
  final IconData icon;
  const _SocialIcon(this.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Icon(icon, color: Colors.white),
    );
  }
}

class _StoreBadge extends StatelessWidget {
  final String label;
  final String imagePath;
  final String topText;
  const _StoreBadge({required this.label, required this.topText, required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
      ),
      child: Row(children: [
        Image.asset(imagePath, width: 30, height: 30, fit: BoxFit.contain),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(topText, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
          ],
        ),
      ]),
    );
  }
}



Widget _WebField(String hint, TextEditingController ctrl, {int lines = 1}) => TextField(
  controller: ctrl,
  maxLines: lines,
  style: const TextStyle(color: Colors.white),
  decoration: InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Colors.white30, fontSize: 14),
    filled: true,
    fillColor: Colors.white.withValues(alpha: 0.05),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primaryBlue)),
  ),
);
