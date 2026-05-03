import 'package:flutter/material.dart';
import '../../utils/design_system.dart';
import '../../utils/responsive.dart';
import 'landing_footer.dart';

// ─────────────────────────────────────────────────────────────────
// SERVERS PAGE
// ─────────────────────────────────────────────────────────────────
class ServersPage extends StatefulWidget {
  const ServersPage({super.key});

  @override
  State<ServersPage> createState() => _ServersPageState();
}

final _allServers = [
  ('🇬🇧', 'United Kingdom', 'London',       '18ms', '1 Gbps',   ['Streaming', 'P2P']),
  ('🇺🇸', 'United States',  'New York',      '85ms', '1 Gbps',   ['Gaming', 'Crypto']),
  ('🇺🇸', 'United States',  'Los Angeles',   '110ms','950 Mbps', ['Streaming', 'Gaming']),
  ('🇩🇪', 'Germany',        'Frankfurt',     '25ms', '1 Gbps',   ['Gaming', 'Streaming']),
  ('🇳🇱', 'Netherlands',    'Amsterdam',     '22ms', '1 Gbps',   ['Streaming', 'P2P']),
  ('🇯🇵', 'Japan',          'Tokyo',         '150ms','950 Mbps', ['Gaming', 'Streaming']),
  ('🇸🇬', 'Singapore',      'Singapore',     '120ms','800 Mbps', ['Crypto', 'Streaming']),
  ('🇦🇺', 'Australia',      'Sydney',        '180ms','700 Mbps', ['Streaming']),
  ('🇨🇦', 'Canada',         'Toronto',       '95ms', '900 Mbps', ['Streaming', 'Gaming']),
  ('🇫🇷', 'France',         'Paris',         '28ms', '1 Gbps',   ['Streaming']),
  ('🇨🇭', 'Switzerland',    'Zurich',        '30ms', '1 Gbps',   ['Crypto']),
  ('🇸🇪', 'Sweden',         'Stockholm',     '35ms', '1 Gbps',   ['Streaming', 'P2P']),
  ('🇮🇳', 'India',          'Mumbai',        '75ms', '500 Mbps', ['Streaming']),
  ('🇦🇪', 'UAE',            'Dubai',         '95ms', '400 Mbps', ['Crypto']),
  ('🇧🇷', 'Brazil',         'São Paulo',     '145ms','600 Mbps', ['Gaming']),
  ('🇿🇦', 'South Africa',   'Cape Town',     '200ms','300 Mbps', ['Streaming']),
];

class _ServersPageState extends State<ServersPage> {
  String _search = '';
  String _filter = 'All';

  List<(String, String, String, String, String, List<String>)> get _filtered {
    return _allServers.where((s) {
      final matchSearch = _search.isEmpty ||
          s.$2.toLowerCase().contains(_search.toLowerCase()) ||
          s.$3.toLowerCase().contains(_search.toLowerCase());
      final matchFilter = _filter == 'All' || s.$6.contains(_filter);
      return matchSearch && matchFilter;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildNav(context)),
          SliverToBoxAdapter(child: _buildHero()),
          SliverToBoxAdapter(child: _buildFilters()),
          SliverToBoxAdapter(child: _buildTable()),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
          const SliverToBoxAdapter(child: LandingFooter()),
        ],
      ),
    );
  }

  Widget _buildNav(BuildContext context) {
    return const _MiniNav(title: 'Server Network');
  }

  Widget _buildHero() {
    final isMobile = Responsive.isMobile(context);
    return Container(
      padding: EdgeInsets.symmetric(vertical: isMobile ? 60 : 80, horizontal: isMobile ? 20 : 60),
      child: Column(children: [
        const Text('SERVER NETWORK', style: TextStyle(color: AppColors.primaryBlue, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2)),
        const SizedBox(height: 12),
        const Text('6,500+ servers.\n100 countries. 1 app.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 42, height: 1.15)),
        const SizedBox(height: 20),
        const Text('Our global network is engineered for speed, reliability and privacy — with dedicated servers for streaming, gaming, and crypto.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontSize: 16, height: 1.6)),
        const SizedBox(height: 40),
        if (isMobile)
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 24,
            runSpacing: 16,
            children: [
              _StatPill('6,500+', 'Servers'),
              _StatPill('100', 'Countries'),
              _StatPill('1 Gbps', 'Per Server'),
              _StatPill('99.99%', 'Uptime'),
            ],
          )
        else
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _StatPill('6,500+', 'Servers'),
            const SizedBox(width: 32),
            _StatPill('100', 'Countries'),
            const SizedBox(width: 32),
            _StatPill('1 Gbps', 'Per Server'),
            const SizedBox(width: 32),
            _StatPill('99.99%', 'Uptime'),
          ]),
      ]),
    );
  }

  Widget _buildFilters() {
    final isMobile = Responsive.isMobile(context);
    final isTablet = Responsive.isTablet(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 20 : 60),
      child: Column(children: [
        if (isMobile) ...[
          Row(children: [
            Expanded(child: TextField(
              onChanged: (v) => setState(() => _search = v),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search country or city...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primaryBlue)),
              ),
            )),
          ]),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(children: ['All', 'Streaming', 'Gaming', 'Crypto', 'P2P'].map((f) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _filter = f),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: _filter == f ? AppColors.primaryBlue.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: _filter == f ? AppColors.primaryBlue.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.07)),
                    ),
                    child: Text(f, style: TextStyle(color: _filter == f ? AppColors.primaryBlue : Colors.white60, fontWeight: _filter == f ? FontWeight.w800 : FontWeight.w500, fontSize: 12)),
                  ),
                ),
              )).toList()),
            ),
          ),
        ] else ...[
          Row(
            children: [
              Expanded(child: TextField(
                onChanged: (v) => setState(() => _search = v),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search country or city...',
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                  prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primaryBlue)),
                ),
              )),
              SizedBox(width: isTablet ? 16 : 24),
              Row(children: ['All', 'Streaming', 'Gaming', 'Crypto', 'P2P'].map((f) => Padding(
                padding: EdgeInsets.only(right: isTablet ? 8 : 10),
                child: GestureDetector(
                  onTap: () => setState(() => _filter = f),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: EdgeInsets.symmetric(horizontal: isTablet ? 14 : 18, vertical: isTablet ? 8 : 10),
                    decoration: BoxDecoration(
                      color: _filter == f ? AppColors.primaryBlue.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(color: _filter == f ? AppColors.primaryBlue.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.07)),
                    ),
                    child: Text(f, style: TextStyle(color: _filter == f ? AppColors.primaryBlue : Colors.white60, fontWeight: _filter == f ? FontWeight.w800 : FontWeight.w500, fontSize: isTablet ? 12 : 13)),
                  ),
                ),
              )).toList()),
            ],
          ),
        ],
        const SizedBox(height: 24),
      ]),
    );
  }

  Widget _buildTable() {
    final filtered = _filtered;
    final isMobile = Responsive.isMobile(context);
    if (isMobile) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: filtered.map((s) {
            final pingMs = int.tryParse(s.$4.replaceAll('ms', '')) ?? 999;
            final pingColor = pingMs < 50 ? AppColors.success : pingMs < 120 ? AppColors.warning : Colors.red;
            return Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(s.$1, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  Expanded(child: Text('${s.$3}, ${s.$2}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14))),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  _ServerMeta('Ping', s.$4, pingColor),
                  const SizedBox(width: 14),
                  _ServerMeta('Speed', s.$5, Colors.white60),
                ]),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: s.$6.map((tag) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: AppColors.primaryBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                    child: Text(tag, style: const TextStyle(color: AppColors.primaryBlue, fontSize: 10, fontWeight: FontWeight.w700)),
                  )).toList(),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pushNamed(context, '/signup'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    child: const Text('Connect', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                  ),
                ),
              ]),
            );
          }).toList(),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 60),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.04), borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
          child: const Row(children: [
            SizedBox(width: 50),
            Expanded(flex: 3, child: Text('Country', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700))),
            Expanded(flex: 2, child: Text('City', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700))),
            Expanded(flex: 1, child: Text('Ping', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700))),
            Expanded(flex: 1, child: Text('Speed', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700))),
            Expanded(flex: 3, child: Text('Features', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700))),
            SizedBox(width: 100),
          ]),
        ),
        ...filtered.asMap().entries.map((e) {
          final s = e.value;
          final isLast = e.key == filtered.length - 1;
          final pingMs = int.tryParse(s.$4.replaceAll('ms', '')) ?? 999;
          final pingColor = pingMs < 50 ? AppColors.success : pingMs < 120 ? AppColors.warning : Colors.red;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              border: Border(
                bottom: isLast ? BorderSide.none : BorderSide(color: Colors.white.withValues(alpha: 0.04)),
              ),
            ),
            child: Row(children: [
              SizedBox(width: 50, child: Text(s.$1, style: const TextStyle(fontSize: 22))),
              Expanded(flex: 3, child: Text(s.$2, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14))),
              Expanded(flex: 2, child: Text(s.$3, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13))),
              Expanded(flex: 1, child: Text(s.$4, style: TextStyle(color: pingColor, fontWeight: FontWeight.w800, fontSize: 13))),
              Expanded(flex: 1, child: Text(s.$5, style: const TextStyle(color: Colors.white60, fontSize: 12))),
              Expanded(flex: 3, child: Wrap(spacing: 6, children: s.$6.map((tag) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppColors.primaryBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                child: Text(tag, style: const TextStyle(color: AppColors.primaryBlue, fontSize: 10, fontWeight: FontWeight.w700)),
              )).toList())),
              SizedBox(width: 100, child: ElevatedButton(
                onPressed: () => Navigator.pushNamed(context, '/signup'),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                child: const Text('Connect', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
              )),
            ]),
          );
        }),
      ]),
    );
  }
}

Widget _ServerMeta(String label, String value, Color valueColor) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
    const SizedBox(height: 4),
    Text(value, style: TextStyle(color: valueColor, fontWeight: FontWeight.w800, fontSize: 12)),
  ],
);

Widget _StatPill(String value, String label) => Column(children: [
  Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 28)),
  Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
]);

// ─────────────────────────────────────────────────────────────────
// BLOG PAGE
// ─────────────────────────────────────────────────────────────────
class BlogPage extends StatelessWidget {
  const BlogPage({super.key});

  final _posts = const [
    _BlogPost('Why WireGuard is the Future of VPN Protocols', 'Security', '8 min read', 'March 2026', 'WireGuard has revolutionised how VPNs work — here\'s everything you need to know about the protocol that\'s replacing OpenVPN.'),
    _BlogPost('The Complete Guide to Streaming with a VPN', 'Streaming', '12 min read', 'March 2026', 'Netflix, Disney+, BBC iPlayer — a complete walkthrough of unblocking every major streaming service from anywhere in the world.'),
    _BlogPost('Exposed: How ISPs Sell Your Browsing Data', 'Privacy', '6 min read', 'February 2026', 'Your internet service provider legally sells your browsing history to advertisers in many countries. Here\'s how to stop them.'),
    _BlogPost('VPN Gaming in 2026: Reduce Ping and Bypass Geo-Blocks', 'Gaming', '10 min read', 'February 2026', 'How to use a VPN to access game servers in other regions, reduce ping with route optimisation, and protect yourself from DDoS.'),
    _BlogPost('Bitcoin Privacy: Why Crypto Traders Need a VPN', 'Crypto', '7 min read', 'January 2026', 'Cryptocurrency offers financial privacy — but your IP address can still track every trade. Here\'s how a VPN closes that gap.'),
    _BlogPost('Understanding DNS Leaks and How to Fix Them', 'Security', '5 min read', 'January 2026', 'A DNS leak can expose your browsing history even when connected to a VPN. Learn how to detect and prevent this common vulnerability.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildNav(context)),
          SliverToBoxAdapter(child: Container(
            padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 60),
            child: Column(children: [
              const Text('LEARN', style: TextStyle(color: AppColors.primaryBlue, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2)),
              const SizedBox(height: 12),
              const Text('VPN Blog', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 42)),
              const SizedBox(height: 12),
              const Text('Expert guides, privacy tips, and VPN news.', style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
              const SizedBox(height: 60),
              Wrap(
                spacing: 24, runSpacing: 24,
                children: _posts.map((p) => _BlogCard(post: p)).toList(),
              ),
            ]),
          )),
          const SliverToBoxAdapter(child: LandingFooter()),
        ],
      ),
    );
  }

  Widget _buildNav(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 20),
    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.4), border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.07)))),
    child: Row(children: [
      GestureDetector(onTap: () => Navigator.pushNamed(context, '/'), child: Row(children: [
        Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.shield_rounded, size: 18, color: Colors.white)),
        const SizedBox(width: 10),
        const Text('SecureVPN', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white)),
        const SizedBox(width: 8),
        Text('/ Blog', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 14)),
      ])),
      const Spacer(),
      ElevatedButton(onPressed: () => Navigator.pushNamed(context, '/signup'), style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: const Text('Get SecureVPN', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white))),
    ]),
  );
}

class _BlogPost {
  final String title, category, readTime, date, excerpt;
  const _BlogPost(this.title, this.category, this.readTime, this.date, this.excerpt);
}

class _BlogCard extends StatefulWidget {
  final _BlogPost post;
  const _BlogCard({required this.post});

  @override
  State<_BlogCard> createState() => _BlogCardState();
}

class _BlogCardState extends State<_BlogCard> {
  bool _hov = false;

  Color get _catColor => switch (widget.post.category) {
    'Security' => AppColors.primaryBlue,
    'Streaming' => const Color(0xFF8B5CF6),
    'Gaming' => const Color(0xFFF97316),
    'Crypto' => const Color(0xFFF59E0B),
    _ => AppColors.success,
  };

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hov = true),
      onExit: (_) => setState(() => _hov = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 360,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: _hov ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _hov ? _catColor.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.06)),
          boxShadow: _hov ? [BoxShadow(color: _catColor.withValues(alpha: 0.06), blurRadius: 20)] : [],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: _catColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)), child: Text(widget.post.category, style: TextStyle(color: _catColor, fontSize: 11, fontWeight: FontWeight.w800))),
            const Spacer(),
            Text(widget.post.readTime, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          ]),
          const SizedBox(height: 16),
          Text(widget.post.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17, height: 1.35)),
          const SizedBox(height: 10),
          Text(widget.post.excerpt, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.55)),
          const SizedBox(height: 20),
          Row(children: [
            Text(widget.post.date, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            const Spacer(),
            Text('Read more →', style: TextStyle(color: _catColor, fontSize: 13, fontWeight: FontWeight.w700)),
          ]),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// CAREERS PAGE
// ─────────────────────────────────────────────────────────────────
class CareersPage extends StatelessWidget {
  const CareersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final jobs = [
      _Job('Senior Backend Engineer', 'Engineering', 'London / Remote', '75k – 110k GBP'),
      _Job('iOS Developer', 'Engineering', 'Remote', '65k – 95k GBP'),
      _Job('Android Developer', 'Engineering', 'Remote', '65k – 95k GBP'),
      _Job('Node.js / Go Backend Developer', 'Engineering', 'Remote', '60k – 90k GBP'),
      _Job('UX/UI Designer', 'Design', 'London / Remote', '55k – 80k GBP'),
      _Job('Head of Marketing', 'Marketing', 'London', '70k – 100k GBP'),
      _Job('Content Writer — Privacy & Security', 'Marketing', 'Remote', '40k – 55k GBP'),
      _Job('Customer Support Specialist', 'Support', 'Remote', '28k – 38k GBP'),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 20),
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.4), border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.07)))),
            child: Row(children: [
              GestureDetector(onTap: () => Navigator.pushNamed(context, '/'), child: const Text('← SecureVPN', style: TextStyle(color: Colors.white60, fontSize: 14))),
              const Spacer(),
            ]),
          )),
          SliverToBoxAdapter(child: Container(
            padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 60),
            child: Column(children: [
              const Text('CAREERS', style: TextStyle(color: AppColors.primaryBlue, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2)),
              const SizedBox(height: 12),
              const Text('Help us protect\n14 million people.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 42, height: 1.2)),
              const SizedBox(height: 16),
              const Text('We\'re a remote-first team of 60+ spread across 18 countries. We offer generous equity, full benefits, and unlimited holiday.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontSize: 16, height: 1.6)),
              const SizedBox(height: 60),
              Row(children: [
                Expanded(child: _PerkCard(Icons.home_rounded, 'Remote First', 'Work from anywhere. We\'ve been remote since day one.')),
                const SizedBox(width: 20),
                Expanded(child: _PerkCard(Icons.beach_access_rounded, 'Unlimited Holiday', 'We trust you to manage your own time. No arbitrary limits.')),
                const SizedBox(width: 20),
                Expanded(child: _PerkCard(Icons.trending_up_rounded, 'Equity', 'Every employee gets meaningful equity in SecureVPN Ltd.')),
                const SizedBox(width: 20),
                Expanded(child: _PerkCard(Icons.school_rounded, 'Learning Budget', '£2,000/year for courses, books, and conferences.')),
              ]),
              const SizedBox(height: 60),
              const Align(alignment: Alignment.centerLeft, child: Text('Open Positions', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 28))),
              const SizedBox(height: 24),
              ...jobs.map((j) => _JobRow(job: j)),
            ]),
          )),
        ],
      ),
    );
  }
}

class _Job {
  final String title, team, location, salary;
  const _Job(this.title, this.team, this.location, this.salary);
}

class _JobRow extends StatefulWidget {
  final _Job job;
  const _JobRow({required this.job});

  @override
  State<_JobRow> createState() => _JobRowState();
}

class _JobRowState extends State<_JobRow> {
  bool _hov = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hov = true),
      onExit: (_) => setState(() => _hov = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _hov ? Colors.white.withValues(alpha: 0.07) : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _hov ? AppColors.primaryBlue.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(children: [
          Expanded(flex: 4, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.job.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 4),
            Text(widget.job.team, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ])),
          Expanded(flex: 2, child: Row(children: [const Icon(Icons.location_on_rounded, color: Colors.white24, size: 14), const SizedBox(width: 4), Text(widget.job.location, style: const TextStyle(color: Colors.white60, fontSize: 13))])),
          Expanded(flex: 2, child: Text(widget.job.salary, style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w700, fontSize: 13))),
          ElevatedButton(onPressed: () {}, style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap), child: const Text('Apply', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
        ]),
      ),
    );
  }
}

class _PerkCard extends StatelessWidget {
  final IconData icon;
  final String title, desc;
  const _PerkCard(this.icon, this.title, this.desc);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: 0.06))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: AppColors.primaryBlue, size: 24),
      const SizedBox(height: 14),
      Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
      const SizedBox(height: 6),
      Text(desc, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.5)),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────
// COOKIE POLICY
// ─────────────────────────────────────────────────────────────────
class CookiePolicyPage extends StatelessWidget {
  const CookiePolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _MiniNav(title: 'Cookie Policy')),
          SliverToBoxAdapter(
            child: Responsive(
              mobile: _CookiePolicyMobile(),
              tablet: _CookiePolicyBody(),
              desktop: _CookiePolicyBody(),
            ),
          ),
          const SliverToBoxAdapter(child: LandingFooter()),
        ],
      ),
    );
  }
}

class _CookiePolicyBody extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 120),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Cookie Policy', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 40)),
        const SizedBox(height: 8),
        const Text('Last updated: March 2026', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        const SizedBox(height: 40),
        ..._cookieSections.map((s) => Padding(
          padding: const EdgeInsets.only(bottom: 32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.$1, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20)),
            const SizedBox(height: 12),
            Text(s.$2, style: const TextStyle(color: AppColors.textSecondary, height: 1.7, fontSize: 15)),
          ]),
        )),
      ]),
    );
  }
}

class _CookiePolicyMobile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 48, 20, 60),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Cookie Policy', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 28, height: 1.2)),
        const SizedBox(height: 6),
        const Text('Last updated: March 2026', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 28),
        ..._cookieSections.map((s) => Padding(
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

const _cookieSections = <(String, String)>[
  ('What are cookies?', 'Cookies are small text files placed on your device when you visit a website. They help websites remember your preferences and improve your experience.'),
  ('What cookies do we use?', 'Essential: Session tokens required for authentication and account security. These cannot be disabled.\n\nAnalytics (optional): We use privacy-preserving analytics to understand how our marketing site is used. These never include VPN usage data.\n\nPreferences: Remember your language and UI theme preferences.'),
  ('What we do NOT do', 'We do not use advertising cookies or sell cookie data to third parties. We do not track your VPN usage through cookies.'),
  ('Managing cookies', 'You can disable non-essential cookies at any time via your browser settings or by using our cookie preference centre (linked in the site footer).'),
  ('Contact', 'Questions about cookies? Email us at privacy@securevpn.com'),
];

// Shared web top bar + footer (matches Privacy Policy styling)
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
          const Text('SecureVPN', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white)),
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
// GDPR PAGE
// ─────────────────────────────────────────────────────────────────
class GdprPage extends StatelessWidget {
  const GdprPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 120),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(onTap: () => Navigator.pop(context), child: const Text('← Back', style: TextStyle(color: AppColors.primaryBlue))),
          const SizedBox(height: 32),
          const Text('GDPR & Data Rights', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 40)),
          const SizedBox(height: 8),
          const Text('Last updated: March 2026', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 40),
          Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.success.withValues(alpha: 0.2))), child: const Row(children: [
            Icon(Icons.verified_user_rounded, color: AppColors.success, size: 24),
            SizedBox(width: 14),
            Expanded(child: Text('SecureVPN Ltd is registered with the Information Commissioner\'s Office (ICO) in the UK. We are fully compliant with UK GDPR and the Data Protection Act 2018.', style: TextStyle(color: Colors.white70, height: 1.6))),
          ])),
          const SizedBox(height: 40),
          ...[
            ('Your Rights Under UK GDPR', 'As a UK/EU resident, you have the following rights:\n\n• Right to Access: Request a copy of all personal data we hold about you.\n• Right to Rectification: Correct inaccurate or incomplete data.\n• Right to Erasure: Request deletion of your personal data ("right to be forgotten").\n• Right to Restriction: Ask us to pause processing your data.\n• Right to Data Portability: Receive your data in a machine-readable format.\n• Right to Object: Object to processing based on legitimate interests.\n• Rights related to automated decision-making: We do not use automated decision-making.'),
            ('How to Exercise Your Rights', 'Email privacy@securevpn.com with the subject line "GDPR Rights Request". We will respond within 30 days. We may need to verify your identity before processing requests. There is no charge for exercising your rights.'),
            ('Legal Bases for Processing', 'Contract performance: Processing your account data to provide the VPN service.\nLegal obligation: Retaining billing records as required by UK law.\nLegitimate interests: Preventing fraud and maintaining service security.'),
            ('Data Transfers', 'Our VPN servers are located worldwide. When your VPN traffic routes through servers in other countries, this is part of the service you have contracted. This is not a transfer of your personal data — no personal data is stored on VPN servers.'),
            ('Supervisory Authority', 'If you believe we have violated your data rights, you have the right to lodge a complaint with the Information Commissioner\'s Office (ICO) at ico.org.uk'),
          ].map((s) => Padding(
            padding: const EdgeInsets.only(bottom: 32),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.$1, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20)),
              const SizedBox(height: 12),
              Text(s.$2, style: const TextStyle(color: AppColors.textSecondary, height: 1.7, fontSize: 15)),
            ]),
          )),
          const SizedBox(height: 60),
          const LandingFooter(),
        ]),
      ),
    );
  }
}
