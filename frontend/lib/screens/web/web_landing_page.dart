import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../utils/design_system.dart';
import '../../utils/responsive.dart';
import 'landing_footer.dart';

class WebLandingPage extends StatefulWidget {
  const WebLandingPage({super.key});

  @override
  State<WebLandingPage> createState() => _WebLandingPageState();
}

class _WebLandingPageState extends State<WebLandingPage>
    with TickerProviderStateMixin {
  late AnimationController _bgController;
  late AnimationController _heroController;
  late Animation<double> _heroFade;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);

    _heroController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _heroFade = CurvedAnimation(parent: _heroController, curve: Curves.easeOut);
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _heroController.forward();
    });
  }

  @override
  void dispose() {
    _bgController.dispose();
    _heroController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          _AnimatedBackground(controller: _bgController),
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              const SliverToBoxAdapter(child: _LandingTopBar()),
              SliverToBoxAdapter(child: _HeroSection(animation: _heroFade)),
              const SliverToBoxAdapter(child: _TrustBar()),
              const SliverToBoxAdapter(child: _FeaturesSection()),
              const SliverToBoxAdapter(child: _HowItWorksSection()),
              const SliverToBoxAdapter(child: _ModesSection()),
              const SliverToBoxAdapter(child: _NetworkSection()),
              const SliverToBoxAdapter(child: _PricingSection()),
              const SliverToBoxAdapter(child: _TestimonialsSection()),
              const SliverToBoxAdapter(child: _CtaSection()),
              const SliverToBoxAdapter(child: LandingFooter()),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Animated cosmic background
// ─────────────────────────────────────────────────────────────────
class _AnimatedBackground extends StatelessWidget {
  final AnimationController controller;
  const _AnimatedBackground({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return CustomPaint(
          size: Size.infinite,
          painter: _BgPainter(controller.value),
        );
      },
    );
  }
}

class _BgPainter extends CustomPainter {
  final double t;
  _BgPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = AppColors.background,
    );

    final circles = [
      (0.2, 0.3, 350.0, const Color(0xFF1E3A5F)),
      (0.8, 0.5, 400.0, const Color(0xFF2D1B4E)),
      (0.5, 0.85, 300.0, const Color(0xFF0D2137)),
    ];

    for (final (cx, cy, r, color) in circles) {
      final x = cx * size.width + math.sin(t * math.pi * 2) * 40;
      final y = cy * size.height + math.cos(t * math.pi * 2) * 30;
      final gradient = RadialGradient(colors: [
        color.withValues(alpha: 0.35),
        color.withValues(alpha: 0),
      ]);
      final paint = Paint()
        ..shader = gradient.createShader(
            Rect.fromCircle(center: Offset(x, y), radius: r));
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(_BgPainter old) => old.t != t;
}

// ─────────────────────────────────────────────────────────────────
// Navigation Bar
// ─────────────────────────────────────────────────────────────────
class _LandingTopBar extends StatelessWidget {
  const _LandingTopBar();

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 60, vertical: isMobile ? 14 : 20),
      decoration: const BoxDecoration(),
      child: isMobile
          ? Row(children: [
              _LogoHomeLink(),
              const Spacer(),
              Text('/ Home', style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12)),
              const SizedBox(width: 10),
              const _NavMenu(title: 'Home'),
            ])
          : Row(children: [
              _LogoHomeLink(),
              const SizedBox(width: 32),
              Text('/ Home', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 14)),
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

Widget _NavChip(String label, String route, BuildContext context) => TextButton(
  onPressed: () => Navigator.pushNamed(context, route),
  child: Text(label, style: const TextStyle(color: Colors.white60, fontSize: 14)),
);

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

// ─────────────────────────────────────────────────────────────────
// Hero Section
// ─────────────────────────────────────────────────────────────────
class _HeroSection extends StatelessWidget {
  final Animation<double> animation;
  const _HeroSection({required this.animation});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isDesktop = w > 900;

    return FadeTransition(
      opacity: animation,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 60 : 24,
          vertical: 60,
        ),
        child: isDesktop
            ? SizedBox(
                height: 600,
                child: Row(
                  children: [
                    Expanded(flex: 11, child: _HeroText()),
                    const SizedBox(width: 60),
                    Expanded(flex: 9, child: const _HeroVisual()),
                  ],
                ),
              )
            : Column(
                children: [
                  _HeroText(),
                  const SizedBox(height: 48),
                  const SizedBox(height: 360, child: _HeroVisual()),
                ],
              ),
      ),
    );
  }
}

class _HeroText extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.primaryBlue.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              const Text(
                'TRUSTED BY 14 MILLION+ USERS WORLDWIDE',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.primaryBlue, letterSpacing: 1.2),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const Text(
          'The VPN That\nNever Compromises.',
          style: TextStyle(
            fontSize: 64,
            fontWeight: FontWeight.w900,
            height: 1.05,
            letterSpacing: -2,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Military-grade encryption. Zero logs. Blazing speeds.\nProtect every device with one click.',
          style: TextStyle(
            fontSize: 18,
            color: Colors.white.withValues(alpha: 0.55),
            height: 1.7,
          ),
        ),
        const SizedBox(height: 44),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            Builder(
              builder: (ctx) => _PillButton(
                label: '→  Get Atmos VPN — Free 7 Days',
                onTap: () => Navigator.pushNamed(ctx, '/signup'),
                color: AppColors.primaryBlue,
                large: true,
              ),
            ),
            Builder(
              builder: (ctx) => _GhostButton(
                label: 'View All Plans',
                onTap: () => Navigator.pushNamed(ctx, '/pricing'),
                large: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 40),
        _HeroTrustRow(),
      ],
    );
  }
}

class _HeroTrustRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final items = ['No Logs', 'Kill Switch', 'AES-256', '24/7 Support']
        .map((t) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_rounded, color: AppColors.success, size: 14),
                const SizedBox(width: 6),
                Text(t, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ))
        .toList();

    if (isMobile) {
      return Wrap(
        spacing: 20,
        runSpacing: 10,
        children: items,
      );
    }

    return Row(
      children: [
        ...items.map((w) => Padding(
              padding: const EdgeInsets.only(right: 28),
              child: w,
            )),
      ],
    );
  }
}

class _HeroVisual extends StatefulWidget {
  const _HeroVisual();

  @override
  State<_HeroVisual> createState() => _HeroVisualState();
}

class _HeroVisualState extends State<_HeroVisual> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 3))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _c, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Outer glow rings
        AnimatedBuilder(
          animation: _c,
          builder: (_, __) => CustomPaint(
            size: const Size(500, 500),
            painter: _RingsPainter(_c.value),
          ),
        ),
        // Shield core
        AnimatedBuilder(
          animation: _pulse,
          builder: (_, child) => Transform.scale(
            scale: _pulse.value,
            child: child,
          ),
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.primaryBlue.withValues(alpha: 0.2),
                  Colors.transparent,
                ],
              ),
              border: Border.all(
                color: AppColors.primaryBlue.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: Center(
              child: ShaderMask(
                shaderCallback: (b) => AppColors.primaryGradient.createShader(b),
                child: const Icon(Icons.security, size: 120, color: Colors.white),
              ),
            ),
          ),
        ),
        // Floating stat cards
        Positioned(top: 30, right: 20, child: _FloatingCard('10 Gbps', 'Server Speed', Icons.bolt_rounded, AppColors.primaryBlue)),
        Positioned(bottom: 50, left: 10, child: _FloatingCard('99.99%', 'Uptime SLA', Icons.signal_wifi_4_bar_rounded, AppColors.success)),
        Positioned(top: 120, left: 0, child: _FloatingCard('AES-256', 'Encryption', Icons.lock_rounded, AppColors.accentPurple)),
      ],
    );
  }
}

class _RingsPainter extends CustomPainter {
  final double t;
  _RingsPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    for (int i = 0; i < 3; i++) {
      final progress = (t + i / 3) % 1.0;
      final radius = 130.0 + progress * 120;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.primaryBlue.withValues(alpha: (1 - progress) * 0.15);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => true;
}

class _FloatingCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;
  const _FloatingCard(this.value, this.label, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.1), blurRadius: 20)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.white)),
              Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Trust Bar
// ─────────────────────────────────────────────────────────────────
class _TrustBar extends StatelessWidget {
  const _TrustBar();

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 60),
      padding: EdgeInsets.symmetric(vertical: isMobile ? 24 : 32, horizontal: isMobile ? 20 : 48),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: isMobile
          ? Wrap(
              alignment: WrapAlignment.center,
              spacing: 24,
              runSpacing: 16,
              children: const [
                _StatBox('14M+', 'Active Users'),
                _StatBox('95+', 'Countries'),
                _StatBox('6,500+', 'Servers'),
                _StatBox('10 Gbps', 'Max Speed'),
                _StatBox('Zero', 'Logs Kept'),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatBox('14M+', 'Active Users'),
                _Divider(),
                _StatBox('95+', 'Countries'),
                _Divider(),
                _StatBox('6,500+', 'Servers'),
                _Divider(),
                _StatBox('10 Gbps', 'Max Speed'),
                _Divider(),
                _StatBox('Zero', 'Logs Kept'),
              ],
            ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String value;
  final String label;
  const _StatBox(this.value, this.label);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(width: 1, height: 40, color: Colors.white.withValues(alpha: 0.07));
}

// ─────────────────────────────────────────────────────────────────
// Features Section
// ─────────────────────────────────────────────────────────────────
class _FeaturesSection extends StatelessWidget {
  const _FeaturesSection();

  @override
  Widget build(BuildContext context) {
    return _Section(
      tag: 'ENTERPRISE SECURITY',
      title: 'Every feature you need.\nNothing you don\'t.',
      child: Wrap(
        spacing: 24,
        runSpacing: 24,
        alignment: WrapAlignment.center,
        children: [
          _FeatureCard(Icons.shield_rounded, 'AES-256 Encryption', 'Military-grade encryption used by governments and banks worldwide.', AppColors.primaryBlue),
          _FeatureCard(Icons.block_rounded, 'Advanced Kill Switch', 'Instantly blocks internet if VPN drops — your data never leaks.', AppColors.accentPurple),
          _FeatureCard(Icons.visibility_off_rounded, 'Strict No-Logs', 'Independently audited. We never track, store or share your data.', AppColors.success),
          _FeatureCard(Icons.speed_rounded, 'Lightway Protocol', 'Our proprietary protocol delivers 3× faster connections.', AppColors.warning),
          _FeatureCard(Icons.dns_rounded, 'DNS Leak Guard', 'All DNS queries are encrypted through our private resolver.', AppColors.primaryBlue),
          _FeatureCard(Icons.router_rounded, 'Split Tunneling', 'Choose which apps use VPN and which use your local network.', AppColors.accentPurple),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String desc;
  final Color color;
  const _FeatureCard(this.icon, this.title, this.desc, this.color);

  @override
  State<_FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<_FeatureCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 320,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: _hovered
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _hovered
                ? widget.color.withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.06),
          ),
          boxShadow: _hovered
              ? [BoxShadow(color: widget.color.withValues(alpha: 0.08), blurRadius: 30)]
              : [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(widget.icon, color: widget.color, size: 24),
            ),
            const SizedBox(height: 20),
            Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
            const SizedBox(height: 12),
            Text(widget.desc, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), height: 1.6, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// How it Works
// ─────────────────────────────────────────────────────────────────
class _HowItWorksSection extends StatelessWidget {
  const _HowItWorksSection();

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return _Section(
      tag: 'HOW IT WORKS',
      title: 'Protecting you in\nthree simple steps.',
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 80),
        child: isMobile
            ? Column(
                children: const [
                  _Step('1', 'Choose a Server', 'Pick from 6,500+ servers in 95 countries optimized for your use case.', Icons.public_rounded, expand: false),
                  SizedBox(height: 28),
                  _Step('2', 'One-Click Connect', 'Tap connect and our Lightway protocol establishes a secure tunnel instantly.', Icons.touch_app_rounded, expand: false),
                  SizedBox(height: 28),
                  _Step('3', 'Browse Freely', 'Your traffic is encrypted and your IP is hidden. Browse, stream, game with freedom.', Icons.lock_open_rounded, expand: false),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Step('1', 'Choose a Server', 'Pick from 6,500+ servers in 95 countries optimized for your use case.', Icons.public_rounded),
                  _StepConnector(),
                  _Step('2', 'One-Click Connect', 'Tap connect and our Lightway protocol establishes a secure tunnel instantly.', Icons.touch_app_rounded),
                  _StepConnector(),
                  _Step('3', 'Browse Freely', 'Your traffic is encrypted and your IP is hidden. Browse, stream, game with freedom.', Icons.lock_open_rounded),
                ],
              ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String number;
  final String title;
  final String desc;
  final IconData icon;
  final bool expand;
  const _Step(this.number, this.title, this.desc, this.icon, {this.expand = true});

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(
            child: Text(number, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
          ),
        ),
        const SizedBox(height: 28),
        Icon(icon, color: AppColors.primaryBlue, size: 32),
        const SizedBox(height: 20),
        Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
        const SizedBox(height: 12),
        Text(desc, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary, height: 1.6, fontSize: 14)),
      ],
    );

    if (expand) {
      return Expanded(child: content);
    }
    return content;
  }
}

class _StepConnector extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Container(
        width: 80,
        height: 1,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            AppColors.primaryBlue.withValues(alpha: 0.4),
            AppColors.accentPurple.withValues(alpha: 0.4),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Modes Section
// ─────────────────────────────────────────────────────────────────
class _ModesSection extends StatelessWidget {
  const _ModesSection();

  @override
  Widget build(BuildContext context) {
    return _Section(
      tag: 'SPECIALIZED MODES',
      title: 'Built for what you do.',
      isDark: true,
      child: Wrap(
        spacing: 24,
        runSpacing: 24,
        alignment: WrapAlignment.center,
        children: [
          _ModeCard(
            Icons.movie_rounded,
            'Streaming',
            'Netflix, Disney+, Hulu, BBC iPlayer — unblocked globally.',
            AppColors.accentPurple,
            ['Netflix', 'Disney+', 'Hulu', 'BBC iPlayer'],
          ),
          _ModeCard(
            Icons.sports_esports_rounded,
            'Gaming',
            'Sub-20ms latency paths with DDoS protection built-in.',
            AppColors.success,
            ['Low Latency', 'DDoS Shield', 'Geo Unlock', 'Stable Path'],
          ),
          _ModeCard(
            Icons.currency_bitcoin_rounded,
            'Crypto',
            'Isolated secure tunnel for trading and cold wallet access.',
            AppColors.warning,
            ['Anti-Phishing', 'Secure DNS', 'IP Isolation', 'Exchange Unlock'],
          ),
          _ModeCard(
            Icons.folder_zip_rounded,
            'Torrenting',
            'P2P optimized servers with SOCKS5 proxy support.',
            AppColors.primaryBlue,
            ['P2P Servers', 'SOCKS5', 'No Throttle', 'Port Forward'],
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatefulWidget {
  final IconData icon;
  final String name;
  final String desc;
  final Color color;
  final List<String> tags;
  const _ModeCard(this.icon, this.name, this.desc, this.color, this.tags);

  @override
  State<_ModeCard> createState() => _ModeCardState();
}

class _ModeCardState extends State<_ModeCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 280,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          gradient: _hovered
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    widget.color.withValues(alpha: 0.12),
                    widget.color.withValues(alpha: 0.04),
                  ])
              : null,
          color: _hovered ? null : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _hovered ? widget.color.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.07),
          ),
          boxShadow: _hovered ? [BoxShadow(color: widget.color.withValues(alpha: 0.12), blurRadius: 40)] : [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(widget.icon, color: widget.color, size: 28),
            ),
            const SizedBox(height: 20),
            Text(widget.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
            const SizedBox(height: 10),
            Text(widget.desc, style: const TextStyle(color: AppColors.textSecondary, height: 1.5, fontSize: 13)),
            const SizedBox(height: 20),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: widget.tags.map((t) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(t, style: TextStyle(color: widget.color, fontSize: 10, fontWeight: FontWeight.w700)),
              )).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Network Section
// ─────────────────────────────────────────────────────────────────
class _NetworkSection extends StatelessWidget {
  const _NetworkSection();

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return Container(
      margin: EdgeInsets.symmetric(vertical: isMobile ? 40 : 80, horizontal: isMobile ? 16 : 60),
      padding: EdgeInsets.all(isMobile ? 24 : 60),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryBlue.withValues(alpha: 0.08),
            AppColors.accentPurple.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.15)),
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('GLOBAL NETWORK', style: TextStyle(color: AppColors.primaryBlue, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
                const SizedBox(height: 12),
                const Text('6,500+ servers.\n95 countries.\nOne account.', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, height: 1.2, color: Colors.white)),
                const SizedBox(height: 16),
                Text(
                  'Our bare-metal server infrastructure is built for performance. Every node runs RAM-only â€” no data ever written to disk.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.55), height: 1.6, fontSize: 14),
                ),
                const SizedBox(height: 20),
                Builder(builder: (ctx) => _PillButton(label: 'Browse Server Locations', onTap: () => Navigator.pushNamed(ctx, '/servers'), color: AppColors.primaryBlue)),
                const SizedBox(height: 24),
                LayoutBuilder(builder: (context, constraints) {
                  final cardWidth = (constraints.maxWidth - 12) / 2;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      ('🇬🇧', 'United Kingdom', '120 servers'),
                      ('🇺🇸', 'United States', '1,970 servers'),
                      ('🇩🇪', 'Germany', '310 servers'),
                      ('🇯🇵', 'Japan', '115 servers'),
                      ('🇸🇬', 'Singapore', '88 servers'),
                      ('🇳🇱', 'Netherlands', '210 servers'),
                    ].map((s) => SizedBox(
                      width: cardWidth,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.$1, style: const TextStyle(fontSize: 20)),
                            const SizedBox(height: 6),
                            Text(s.$2, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Colors.white)),
                            Text(s.$3, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                          ],
                        ),
                      ),
                    )).toList(),
                  );
                }),
              ],
            )
          : Row(
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('GLOBAL NETWORK', style: TextStyle(color: AppColors.primaryBlue, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2)),
                const SizedBox(height: 16),
                const Text('6,500+ servers.\n95 countries.\nOne account.', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, height: 1.2, color: Colors.white)),
                const SizedBox(height: 24),
                Text(
                  'Our bare-metal server infrastructure is built for performance. Every node runs RAM-only — no data ever written to disk.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), height: 1.7, fontSize: 16),
                ),
                const SizedBox(height: 36),
                Builder(builder: (ctx) => _PillButton(label: 'Browse Server Locations', onTap: () => Navigator.pushNamed(ctx, '/servers'), color: AppColors.primaryBlue)),
              ],
            ),
          ),
          const SizedBox(width: 60),
          Expanded(
            flex: 5,
            child: Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                ('🇬🇧', 'United Kingdom', '120 servers'),
                ('🇺🇸', 'United States', '1,970 servers'),
                ('🇩🇪', 'Germany', '310 servers'),
                ('🇯🇵', 'Japan', '115 servers'),
                ('🇸🇬', 'Singapore', '88 servers'),
                ('🇳🇱', 'Netherlands', '210 servers'),
              ].map((s) => Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.$1, style: const TextStyle(fontSize: 24)),
                    const SizedBox(height: 6),
                    Text(s.$2, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white)),
                    Text(s.$3, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                  ],
                ),
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Pricing Section
// ─────────────────────────────────────────────────────────────────
class _PricingSection extends StatelessWidget {
  const _PricingSection();

  @override
  Widget build(BuildContext context) {
    return _Section(
      tag: 'PRICING',
      title: 'Choose your plan.',
      subtitle: 'All plans include our full feature set.',
      child: Wrap(
        spacing: 24,
        runSpacing: 24,
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 320,
            child: _PricingCard(
              name: 'Essential',
              price: '£3.99',
              period: '/mo',
              badge: null,
              features: ['5 Simultaneous Devices', 'Standard Speeds', '95+ Countries', '24/7 Support', 'Kill Switch'],
              isPopular: false,
            ),
          ),
          SizedBox(
            width: 340,
            child: _PricingCard(
              name: 'Elite',
              price: '£6.99',
              period: '/mo',
              badge: 'MOST POPULAR',
              features: ['Unlimited Devices', '10 Gbps Speeds', 'Streaming + Gaming', 'Crypto Mode', 'Priority Support', 'Kill Switch + Split Tunnel'],
              isPopular: true,
            ),
          ),
          SizedBox(
            width: 320,
            child: _PricingCard(
              name: 'Ultimate',
              price: '£11.99',
              period: '/mo',
              badge: 'BEST VALUE',
              features: ['Everything in Elite', 'Dedicated IP Address', 'AI Threat Detection', 'Dark Web Monitor', 'Business VPN', 'SLA Guarantee'],
              isPopular: false,
            ),
          ),
        ],
      ),
    );
  }
}

class _PricingCard extends StatefulWidget {
  final String name;
  final String price;
  final String period;
  final String? badge;
  final List<String> features;
  final bool isPopular;
  const _PricingCard({
    required this.name,
    required this.price,
    required this.period,
    required this.badge,
    required this.features,
    required this.isPopular,
  });

  @override
  State<_PricingCard> createState() => _PricingCardState();
}

class _PricingCardState extends State<_PricingCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(36),
        decoration: BoxDecoration(
          gradient: widget.isPopular
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.primaryBlue.withValues(alpha: 0.2),
                    AppColors.accentPurple.withValues(alpha: 0.1),
                  ])
              : null,
          color: widget.isPopular ? null : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: widget.isPopular
                ? AppColors.primaryBlue.withValues(alpha: 0.6)
                : _hovered ? Colors.white.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.07),
            width: widget.isPopular ? 1.5 : 1,
          ),
          boxShadow: widget.isPopular
              ? [BoxShadow(color: AppColors.primaryBlue.withValues(alpha: 0.2), blurRadius: 40)]
              : [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.badge != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: widget.isPopular ? AppColors.primaryBlue : AppColors.success.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(widget.badge!, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: widget.isPopular ? Colors.white : AppColors.success, letterSpacing: 1)),
              ),
              const SizedBox(height: 16),
            ],
            Text(widget.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(widget.price, style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w900, color: Colors.white)),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8, left: 4),
                  child: Text(widget.period, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                ),
              ],
            ),
            const SizedBox(height: 28),
            const Divider(color: Colors.white10, height: 1),
            const SizedBox(height: 24),
            ...widget.features.map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  Icon(Icons.check_circle_rounded, size: 16, color: widget.isPopular ? AppColors.primaryBlue : AppColors.success),
                  const SizedBox(width: 12),
                  Text(f, style: const TextStyle(color: Colors.white, fontSize: 14)),
                ],
              ),
            )),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pushNamed(context, '/signup'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.isPopular ? AppColors.primaryBlue : Colors.white.withValues(alpha: 0.1),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: Text(
                  widget.isPopular ? 'Start Free Trial' : 'Get Started',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Testimonials
// ─────────────────────────────────────────────────────────────────
class _TestimonialsSection extends StatelessWidget {
  const _TestimonialsSection();

  @override
  Widget build(BuildContext context) {
    return _Section(
      tag: 'WHAT USERS SAY',
      title: 'Loved by millions.',
      isDark: true,
      child: Wrap(
        spacing: 24,
        runSpacing: 24,
        alignment: WrapAlignment.center,
        children: [
          _Testimonial('Absolutely the fastest VPN I\'ve tested. Gaming latency went from 80ms to 18ms on EU servers.', 'Marcus T.', 'Pro Gamer', '★★★★★'),
          _Testimonial('The kill switch actually works — I tested it 20 times. No other VPN I tried has been this reliable.', 'Sarah K.', 'Security Researcher', '★★★★★'),
          _Testimonial('Streaming in 4K on Netflix UK from the US with zero buffering. That alone is worth every penny.', 'James L.', 'Content Creator', '★★★★★'),
        ],
      ),
    );
  }
}

class _Testimonial extends StatelessWidget {
  final String quote;
  final String name;
  final String role;
  final String stars;
  const _Testimonial(this.quote, this.name, this.role, this.stars);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 340,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(stars, style: const TextStyle(color: AppColors.warning, fontSize: 18)),
          const SizedBox(height: 16),
          Text('"$quote"', style: const TextStyle(color: Colors.white, height: 1.6, fontStyle: FontStyle.italic, fontSize: 14)),
          const SizedBox(height: 20),
          Text(name, style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
          Text(role, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// CTA Section
// ─────────────────────────────────────────────────────────────────
class _CtaSection extends StatelessWidget {
  const _CtaSection();

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return Container(
      margin: EdgeInsets.symmetric(vertical: isMobile ? 40 : 60, horizontal: isMobile ? 16 : 60),
      padding: EdgeInsets.symmetric(vertical: isMobile ? 48 : 80, horizontal: isMobile ? 24 : 60),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryBlue.withValues(alpha: 0.25), AppColors.accentPurple.withValues(alpha: 0.15)],
        ),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Text(
            'Ready to take back your privacy?',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: isMobile ? 30 : 40, fontWeight: FontWeight.w900, color: Colors.white),
          ),
          const SizedBox(height: 16),
          Text(
            'Join 14 million users. 7-day free trial, no credit card required.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: isMobile ? 14 : 18, color: Colors.white.withValues(alpha: 0.6)),
          ),
          SizedBox(height: isMobile ? 28 : 40),
          _PillButton(label: 'Start Protecting Yourself — It\'s Free', onTap: () => Navigator.pushNamed(context, '/signup'), color: AppColors.primaryBlue, large: !isMobile),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Footer
// ─────────────────────────────────────────────────────────────────
class _WebFooter extends StatelessWidget {
  const _WebFooter();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(60, 60, 60, 40),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.shield_rounded, color: Colors.white, size: 18)),
                      const SizedBox(width: 10),
                      const Text('Atmos VPN', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: Colors.white)),
                    ]),
                    const SizedBox(height: 16),
                    Text('Protecting digital freedom\nsince 2024.', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), height: 1.6)),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 12,
                      children: const [
                        _FooterSocialIcon(Icons.facebook),
                        _FooterSocialIcon(Icons.close),
                        _FooterSocialIcon(Icons.business),
                        _FooterSocialIcon(Icons.play_circle_filled),
                        _FooterSocialIcon(Icons.camera_alt_rounded),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(children: const [
                      _StoreBadge(
                        label: 'App Store',
                        topText: 'Download on the',
                        imagePath: 'assets/images/apple-logo.png',
                      ),
                      SizedBox(width: 12),
                      _StoreBadge(
                        label: 'Google Play',
                        topText: 'GET IT ON',
                        imagePath: 'assets/images/google-play.png',
                      ),
                    ]),
                  ],
                ),
              ),
              _FooterCol('PRODUCT', ['Features', 'Pricing', 'Servers', 'Download', 'Business VPN']),
          _FooterCol('USE CASES', ['Streaming', 'Gaming', 'Crypto', 'Torrenting', 'Privacy']),
          _FooterCol('LEARN', ['How VPN Works', 'Why VPN?', 'VPN Guide 2024', 'Blog']),
          _FooterCol('COMPANY', ['About Us', 'Careers', 'Press', 'Affiliates', 'Contact']),
          _FooterCol('LEGAL', ['Privacy Policy', 'Terms', 'No-Logs Audit', 'Cookie Policy', 'GDPR']),
        ],
      ),
      const _FooterAppsRow(),
      const SizedBox(height: 40),
      Divider(color: Colors.white.withValues(alpha: 0.06)),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('© 2026 Atmos VPN Ltd. All rights reserved.', style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 12)),
              Text('🇬🇧 English  |  Privacy Choice', style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

class _FooterCol extends StatelessWidget {
  final String title;
  final List<String> links;
  const _FooterCol(this.title, this.links);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.primaryBlue, letterSpacing: 1.2)),
          const SizedBox(height: 20),
          ...links.map((l) => _FooterLink(l)),
        ],
      ),
    );
  }
}

class _StoreBadge extends StatelessWidget {
  final String label;
  final String topText;
  final String imagePath;
  const _StoreBadge({required this.label, required this.topText, required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Image.asset(imagePath, width: 26, height: 26, fit: BoxFit.contain),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(topText, style: const TextStyle(color: Colors.white70, fontSize: 7, fontWeight: FontWeight.w600)),
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
          ],
        ),
      ]),
    );
  }
}

class _FooterSocialIcon extends StatelessWidget {
  final IconData icon;
  const _FooterSocialIcon(this.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Icon(icon, color: Colors.white),
    );
  }
}

class _FooterAppsRow extends StatelessWidget {
  const _FooterAppsRow();

  @override
  Widget build(BuildContext context) {
    final items = const [
      (Icons.window_rounded, 'Windows'),
      (Icons.laptop_mac_rounded, 'macOS'),
      (Icons.language_rounded, 'Linux'),
      (Icons.android_rounded, 'Android'),
      (Icons.apple, 'iOS'),
      (Icons.language_rounded, 'Chrome'),
      (Icons.public_rounded, 'Firefox'),
      (Icons.travel_explore_rounded, 'Edge'),
    ];

    return Align(
      alignment: Alignment.centerRight,
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 60,
        runSpacing: 16,
        children: items.map((item) => Column(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Icon(item.$1, color: Colors.white),
            ),
            Text(item.$2, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        )).toList(),
      ),
    );
  }
}

class _FooterLink extends StatefulWidget {
  final String label;
  const _FooterLink(this.label);

  @override
  State<_FooterLink> createState() => _FooterLinkState();
}

class _FooterLinkState extends State<_FooterLink> {
  bool _hovered = false;

  void _onTap() {
    // Basic mapping for demo/completeness
    final route = switch (widget.label.toLowerCase()) {
      'features' => '/features',
      'pricing' => '/pricing',
      'servers' => '/servers',
      'streaming' => '/use-cases/streaming',
      'gaming' => '/use-cases/gaming',
      'crypto' => '/use-cases/crypto',
      'torrenting' => '/use-cases/torrenting',
      'privacy' => '/use-cases/privacy',
      'how vpn works' => '/learn/how-vpn-works',
      'why vpn?' => '/learn/why-vpn',
      'vpn guide 2024' => '/learn/vpn-guide-2024',
      'blog' => '/blog',
      'press' => '/company/press',
      'affiliates' => '/company/affiliates',
      'privacy policy' => '/privacy-policy',
      'terms' => '/terms',
      'no-logs audit' => '/no-logs-audit',
      'gdpr' => '/gdpr',
      'contact' => '/contact',
      'about us' => '/about',
      _ => '/',
    };
    Navigator.pushNamed(context, route);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: _onTap,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            widget.label,
            style: TextStyle(
              color: _hovered ? Colors.white : Colors.white.withValues(alpha: 0.45),
              fontSize: 13,
              fontWeight: _hovered ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Shared Components
// ─────────────────────────────────────────────────────────────────
class _Section extends StatelessWidget {
  final String tag;
  final String title;
  final String? subtitle;
  final Widget child;
  final bool isDark;

  const _Section({
    required this.tag,
    required this.title,
    this.subtitle,
    required this.child,
    this.isDark = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isDark ? Colors.black.withValues(alpha: 0.15) : null,
      padding: const EdgeInsets.symmetric(vertical: 100, horizontal: 60),
      child: Column(
        children: [
          Text(tag, style: const TextStyle(color: AppColors.primaryBlue, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2)),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w900, height: 1.15, color: Colors.white)),
          if (subtitle != null) ...[
            const SizedBox(height: 16),
            Text(subtitle!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary, fontSize: 17, height: 1.6)),
          ],
          const SizedBox(height: 72),
          child,
        ],
      ),
    );
  }
}

class _NavLink extends StatefulWidget {
  final String label;
  final String route;
  const _NavLink({required this.label, required this.route});

  @override
  State<_NavLink> createState() => _NavLinkState();
}

class _NavLinkState extends State<_NavLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => Navigator.pushNamed(context, widget.route),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 150),
            style: TextStyle(
              color: _hovered ? Colors.white : Colors.white.withValues(alpha: 0.55),
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
            child: Text(widget.label),
          ),
        ),
      ),
    );
  }
}

class _PillButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final Color color;
  final bool large;
  const _PillButton({required this.label, required this.onTap, required this.color, this.large = false});

  @override
  State<_PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<_PillButton> {
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
          padding: EdgeInsets.symmetric(
            horizontal: widget.large ? 32 : 24,
            vertical: widget.large ? 18 : 14,
          ),
          decoration: BoxDecoration(
            color: _hovered ? widget.color.withValues(alpha: 0.85) : widget.color,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: widget.color.withValues(alpha: _hovered ? 0.4 : 0.25), blurRadius: _hovered ? 20 : 10)],
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: widget.large ? 16 : 14,
            ),
          ),
        ),
      ),
    );
  }
}

class _GhostButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool large;
  const _GhostButton({required this.label, required this.onTap, this.large = false});

  @override
  State<_GhostButton> createState() => _GhostButtonState();
}

class _GhostButtonState extends State<_GhostButton> {
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
          padding: EdgeInsets.symmetric(
            horizontal: widget.large ? 32 : 20,
            vertical: widget.large ? 18 : 14,
          ),
          decoration: BoxDecoration(
            color: _hovered ? Colors.white.withValues(alpha: 0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: _hovered ? 0.2 : 0.12)),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: _hovered ? 1.0 : 0.7),
              fontWeight: FontWeight.w700,
              fontSize: widget.large ? 16 : 14,
            ),
          ),
        ),
      ),
    );
  }
}
