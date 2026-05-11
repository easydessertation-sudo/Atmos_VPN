import 'package:flutter/material.dart';
import 'dart:ui';
import '../utils/design_system.dart';

class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned(
            top: -100, right: -100,
            child: _AmbientGlow(color: AppColors.primaryBlue.withValues(alpha: 0.15), size: 500),
          ),
          Positioned(
            bottom: -200, left: -100,
            child: _AmbientGlow(color: AppColors.accentPurple.withValues(alpha: 0.1), size: 600),
          ),
          CustomScrollView(
            slivers: [
              _ResponsiveNavbar(),
              SliverToBoxAdapter(child: _HeroSection()),
              SliverToBoxAdapter(child: _InfrastructureShowcase()),
              SliverToBoxAdapter(child: _EnterpriseFeatures()),
              SliverToBoxAdapter(child: _ComparisonMatrix()),
              SliverToBoxAdapter(child: _EnterpriseFooter()),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Responsive Helpers ──────────────────────────────────────────────
double _hPad(BuildContext context) {
  final w = MediaQuery.of(context).size.width;
  if (w < 600) return 20;
  if (w < 1000) return 40;
  return 80;
}

bool _isMobile(BuildContext context) => MediaQuery.of(context).size.width < 700;

// ── Navbar ──────────────────────────────────────────────────────────
class _ResponsiveNavbar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final mobile = _isMobile(context);
    return SliverAppBar(
      floating: true,
      pinned: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      expandedHeight: 70,
      flexibleSpace: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            color: Colors.black.withValues(alpha: 0.2),
            padding: EdgeInsets.symmetric(horizontal: _hPad(context)),
            child: Row(
              children: [
                ShaderMask(
                  shaderCallback: (b) => AppColors.primaryGradient.createShader(b),
                  child: const Text('ATMOS VPN',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: -1)),
                ),
                const Spacer(),
                if (!mobile) ...[
                  const _NavLink('Security'),
                  const _NavLink('Network'),
                  const _NavLink('Pricing'),
                  const SizedBox(width: 24),
                ],
                ElevatedButton(
                  onPressed: () => Navigator.pushNamed(context, '/home'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: mobile ? 16 : 24, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(mobile ? 'GET APP' : 'LAUNCH APP',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Hero Section ────────────────────────────────────────────────────
class _HeroSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final mobile = _isMobile(context);
    final pad = _hPad(context);
    return Container(
      constraints: BoxConstraints(minHeight: mobile ? 0 : MediaQuery.of(context).size.height * 0.85),
      padding: EdgeInsets.symmetric(horizontal: pad, vertical: mobile ? 48 : 0),
      child: mobile
          ? _HeroColumn(context)
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 5, child: _HeroColumn(context)),
                const SizedBox(width: 40),
                Expanded(flex: 5, child: _HeroImage()),
              ],
            ),
    );
  }
}

Widget _HeroColumn(BuildContext context) {
  final mobile = _isMobile(context);
  return Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.primaryBlue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.3)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_rounded, color: AppColors.primaryBlue, size: 12),
            SizedBox(width: 8),
            Flexible(
              child: Text('QUANTUM-RESISTANT PROTECTION ACTIVE',
                  style: TextStyle(color: AppColors.primaryBlue, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      Text(
        'Privacy Without\nCompromise.',
        style: TextStyle(
          fontSize: mobile ? 44 : 68,
          fontWeight: FontWeight.w900,
          height: 1.1,
          letterSpacing: -1.5,
          color: Colors.white,
        ),
      ),
      const SizedBox(height: 20),
      Text(
        'Enterprise-grade encryption meets world-class speed. Secure your digital frontier.',
        style: TextStyle(
          fontSize: mobile ? 15 : 18,
          color: AppColors.textSecondary.withValues(alpha: 0.8),
          height: 1.6,
        ),
      ),
      const SizedBox(height: 36),
      Wrap(
        spacing: 16,
        runSpacing: 12,
        children: [
          ElevatedButton.icon(
            onPressed: () => Navigator.pushNamed(context, '/home'),
            icon: const Icon(Icons.arrow_forward_rounded, size: 16),
            label: const Text('Get Atmos VPN'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
              textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          OutlinedButton(
            onPressed: () {},
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
              textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Explore Technology'),
          ),
        ],
      ),
      const SizedBox(height: 48),
      const _TrustBadges(),
      if (mobile) const SizedBox(height: 48),
      if (mobile) const _HeroImage(),
    ],
  );
}

class _HeroImage extends StatelessWidget {
  const _HeroImage();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          _AmbientGlow(color: AppColors.primaryBlue.withValues(alpha: 0.1), size: 400),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.asset(
              'assets/images/enterprise_vpn_hero_mockup_1773460887367.png',
              fit: BoxFit.contain,
              errorBuilder: (c, e, s) => Container(
                width: 360,
                height: 280,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.shield_rounded, size: 80, color: AppColors.primaryBlue.withValues(alpha: 0.3)),
                    const SizedBox(height: 16),
                    const Text('Atmos VPN App', style: TextStyle(color: Colors.white54, fontSize: 16, fontWeight: FontWeight.bold)),
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

// ── Infrastructure ──────────────────────────────────────────────────
class _InfrastructureShowcase extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final pad = _hPad(context);
    return Container(
      padding: EdgeInsets.symmetric(vertical: 80, horizontal: pad),
      child: Column(
        children: [
          const _SectionHeader(
            tag: 'GLOBAL NETWORK',
            title: '12,000+ Edge Nodes.\nZero Latency.',
            subtitle: 'Our backbone spans 90+ countries with dedicated fiber for every user.',
          ),
          const SizedBox(height: 60),
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              children: [
                Image.asset(
                  'assets/images/global_secure_infrastructure_1773460901098.png',
                  width: double.infinity,
                  height: 300,
                  fit: BoxFit.cover,
                  errorBuilder: (c, e, s) => Container(
                    height: 300,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.primaryBlue.withValues(alpha: 0.1), AppColors.accentPurple.withValues(alpha: 0.1)],
                      ),
                    ),
                    child: const Center(child: Icon(Icons.public, size: 80, color: Colors.white24)),
                  ),
                ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [AppColors.background, Colors.transparent],
                      ),
                    ),
                  ),
                ),
                const _DataOverlay(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Features Grid ───────────────────────────────────────────────────
class _EnterpriseFeatures extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final pad = _hPad(context);
    final mobile = _isMobile(context);
    final features = [
      (Icons.security_rounded, 'Military Encryption', 'AES-256-GCM + ChaCha20-Poly1305 for unshakeable data integrity.'),
      (Icons.memory_rounded, 'RAM-Only Servers', 'Runs exclusively in volatile memory. No data ever written to disk.'),
      (Icons.speed_rounded, '10Gbps Standard', 'Symmetric speeds optimized for 4K streaming and ultra-low latency.'),
    ];
    return Container(
      padding: EdgeInsets.symmetric(vertical: 80, horizontal: pad),
      child: Column(
        children: [
          const _SectionHeader(tag: 'FEATURES', title: 'Built Different.', subtitle: 'Every component engineered for performance and privacy.'),
          const SizedBox(height: 48),
          mobile
              ? Column(
                  children: features.map((f) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _FeatureCard(icon: f.$1, title: f.$2, desc: f.$3),
                  )).toList(),
                )
              : Row(
                  children: features.map((f) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: _FeatureCard(icon: f.$1, title: f.$2, desc: f.$3),
                    ),
                  )).toList(),
                ),
        ],
      ),
    );
  }
}

// ── Comparison Matrix ───────────────────────────────────────────────
class _ComparisonMatrix extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final pad = _hPad(context);
    return Container(
      padding: EdgeInsets.symmetric(vertical: 80, horizontal: pad),
      child: Column(
        children: [
          const Text('WHY ATMOS VPN?',
              style: TextStyle(color: AppColors.primaryBlue, fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 12)),
          const SizedBox(height: 12),
          const Text('The Enterprise Advantage',
              style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Colors.white)),
          const SizedBox(height: 48),
          Container(
            decoration: AppDecorations.glass,
            padding: const EdgeInsets.all(28),
            child: Table(
              columnWidths: const {0: FlexColumnWidth(3), 1: FlexColumnWidth(2), 2: FlexColumnWidth(2)},
              children: [
                _tableHeader(),
                _tableRow('Quantum-Resistant Keys', true, false),
                _tableRow('Diskless Infrastructure', true, false),
                _tableRow('24/7 Concierge Support', true, true),
                _tableRow('Dynamic Private IP', true, false),
                _tableRow('Zero Logs (Audited)', true, false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  TableRow _tableHeader() {
    return const TableRow(children: [
      Padding(padding: EdgeInsets.symmetric(vertical: 18),
          child: Text('SPEC', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w900, fontSize: 11))),
      Padding(padding: EdgeInsets.symmetric(vertical: 18),
          child: Text('ATMOS VPN', style: TextStyle(color: AppColors.primaryBlue, fontWeight: FontWeight.w900, fontSize: 11))),
      Padding(padding: EdgeInsets.symmetric(vertical: 18),
          child: Text('STANDARD VPN', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w900, fontSize: 11))),
    ]);
  }

  TableRow _tableRow(String spec, bool us, bool them) {
    return TableRow(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)))),
      children: [
        Padding(padding: const EdgeInsets.symmetric(vertical: 18), child: Text(spec, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
        Padding(padding: const EdgeInsets.symmetric(vertical: 18),
            child: Icon(us ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                color: us ? AppColors.success : Colors.white10, size: 20)),
        Padding(padding: const EdgeInsets.symmetric(vertical: 18),
            child: Icon(them ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                color: them ? AppColors.textSecondary : Colors.white10, size: 20)),
      ],
    );
  }
}

// ── Footer ──────────────────────────────────────────────────────────
class _EnterpriseFooter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final mobile = _isMobile(context);
    final pad = _hPad(context);
    return Container(
      padding: EdgeInsets.all(pad),
      color: Colors.black.withValues(alpha: 0.2),
      child: Column(
        children: [
          const Divider(color: Colors.white10),
          const SizedBox(height: 40),
          mobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ATMOS VPN', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
                    const SizedBox(height: 12),
                    const Text('Redefining digital sovereignty.', style: TextStyle(color: AppColors.textSecondary)),
                    const SizedBox(height: 40),
                    Wrap(
                      spacing: 40,
                      runSpacing: 32,
                      children: [
                        _FooterLinkColumn('PRODUCT', ['Connectivity', 'Security', 'Enterprise']),
                        _FooterLinkColumn('LEGAL', ['Privacy Policy', 'Audit Reports']),
                      ],
                    ),
                  ],
                )
              : const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ATMOS VPN', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
                          SizedBox(height: 12),
                          Text('Redefining digital sovereignty.', style: TextStyle(color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    Spacer(),
                    _FooterLinkColumn('PRODUCT', ['Connectivity', 'Security', 'Enterprise', 'Hardware']),
                    SizedBox(width: 60),
                    _FooterLinkColumn('LEGAL', ['Privacy Policy', 'Cookie Policy', 'Audit Reports']),
                  ],
                ),
          const SizedBox(height: 48),
          const Text('© 2026 ATMOS VPN. ALL RIGHTS RESERVED.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 10, letterSpacing: 1)),
        ],
      ),
    );
  }
}

// ── Sub-components ──────────────────────────────────────────────────
class _NavLink extends StatelessWidget {
  final String label;
  const _NavLink(this.label);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 28),
    child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textSecondary)),
  );
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title, desc;
  const _FeatureCard({required this.icon, required this.title, required this.desc});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(28),
    decoration: AppDecorations.glass.copyWith(border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: AppColors.primaryBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: AppColors.primaryBlue, size: 22),
        ),
        const SizedBox(height: 24),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
        const SizedBox(height: 12),
        Text(desc, style: const TextStyle(color: AppColors.textSecondary, height: 1.6, fontSize: 14)),
      ],
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  final String tag, title, subtitle;
  const _SectionHeader({required this.tag, required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) {
    final mobile = _isMobile(context);
    return Column(
      children: [
        Text(tag, style: const TextStyle(color: AppColors.primaryBlue, fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 11)),
        const SizedBox(height: 14),
        Text(title, textAlign: TextAlign.center,
            style: TextStyle(fontSize: mobile ? 32 : 44, fontWeight: FontWeight.w900, height: 1.15, color: Colors.white)),
        const SizedBox(height: 20),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(subtitle, textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, height: 1.6, fontSize: 16)),
        ),
      ],
    );
  }
}

class _TrustBadges extends StatelessWidget {
  const _TrustBadges();
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 20,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      const Text('TRUSTED BY', style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
      ...['NETSEC', 'CYBERDEF', 'GLOBEGUARD'].map((b) =>
          Text(b, style: TextStyle(color: Colors.white.withValues(alpha: 0.12), fontWeight: FontWeight.w900, fontSize: 16)),
      ),
    ],
  );
}

class _AmbientGlow extends StatelessWidget {
  final Color color;
  final double size;
  const _AmbientGlow({required this.color, required this.size});
  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size,
    decoration: BoxDecoration(shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)])),
  );
}

class _DataOverlay extends StatelessWidget {
  const _DataOverlay();
  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 24, left: 24, right: 24,
      child: Wrap(
        alignment: WrapAlignment.spaceAround,
        spacing: 24, runSpacing: 16,
        children: const [
          _DataStat('99.99%', 'UPTIME'),
          _DataStat('12ms', 'AVG PING'),
          _DataStat('AES-256', 'ENCRYPTION'),
          _DataStat('ZERO', 'LOGS'),
        ],
      ),
    );
  }
}

class _DataStat extends StatelessWidget {
  final String val, label;
  const _DataStat(this.val, this.label);
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(val, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.primaryBlue, letterSpacing: 1)),
    ],
  );
}

class _FooterLinkColumn extends StatelessWidget {
  final String title;
  final List<String> links;
  const _FooterLinkColumn(this.title, this.links);
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: AppColors.primaryBlue, letterSpacing: 1)),
      const SizedBox(height: 20),
      ...links.map((l) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(l, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
      )),
    ],
  );
}
