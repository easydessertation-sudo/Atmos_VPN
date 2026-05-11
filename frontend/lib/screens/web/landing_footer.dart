import 'package:flutter/material.dart';
import '../../utils/design_system.dart';
import '../../utils/responsive.dart';

class LandingFooter extends StatelessWidget {
  const LandingFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return Container(
      padding: EdgeInsets.fromLTRB(isMobile ? 20 : 60, isMobile ? 40 : 60,
          isMobile ? 20 : 60, isMobile ? 32 : 40),
      decoration: BoxDecoration(
        border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: Column(
        children: [
          if (isMobile)
            LayoutBuilder(
              builder: (context, constraints) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _FooterBrand(isMobile: true),
                    const SizedBox(height: 20),
                    Row(
                      children: const [
                        Expanded(
                          child: _StoreBadge(
                            label: 'App Store',
                            topText: 'Download on the',
                            imagePath: 'assets/images/apple-logo.png',
                            isMobile: true,
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: _StoreBadge(
                            label: 'Google Play',
                            topText: 'GET IT ON',
                            imagePath: 'assets/images/google-play.png',
                            isMobile: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Expanded(
                              child: _FooterCol(
                                  'PRODUCT',
                                  [
                                    'Features',
                                    'Pricing',
                                    'Servers',
                                    'Download',
                                    'Business VPN'
                                  ],
                                  isMobile: true),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: _FooterCol(
                                  'USE CASES',
                                  [
                                    'Streaming',
                                    'Gaming',
                                    'Crypto',
                                    'Torrenting',
                                    'Privacy'
                                  ],
                                  isMobile: true),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: _FooterCol(
                                  'LEARN',
                                  [
                                    'How VPN Works',
                                    'Why VPN?',
                                    'VPN Guide 2024',
                                    'Blog'
                                  ],
                                  isMobile: true),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Expanded(
                              child: _FooterCol(
                                  'COMPANY',
                                  [
                                    'About Us',
                                    'Careers',
                                    'Press',
                                    'Affiliates',
                                    'Contact'
                                  ],
                                  isMobile: true),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: _FooterCol(
                                  'LEGAL',
                                  [
                                    'Privacy Policy',
                                    'Terms',
                                    'No-Logs Audit',
                                    'Cookie Policy',
                                    'GDPR'
                                  ],
                                  isMobile: true),
                            ),
                            SizedBox(width: 12),
                            Expanded(child: SizedBox()),
                          ],
                        ),
                      ],
                    ),
                  ],
                );
              },
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Expanded(flex: 3, child: _FooterBrand()),
                Expanded(
                    child: _FooterCol('PRODUCT', [
                  'Features',
                  'Pricing',
                  'Servers',
                  'Download',
                  'Business VPN'
                ])),
                Expanded(
                    child: _FooterCol('USE CASES', [
                  'Streaming',
                  'Gaming',
                  'Crypto',
                  'Torrenting',
                  'Privacy'
                ])),
                Expanded(
                    child: _FooterCol('LEARN', [
                  'How VPN Works',
                  'Why VPN?',
                  'VPN Guide 2024',
                  'Blog'
                ])),
                Expanded(
                    child: _FooterCol('COMPANY', [
                  'About Us',
                  'Careers',
                  'Press',
                  'Affiliates',
                  'Contact'
                ])),
                Expanded(
                    child: _FooterCol('LEGAL', [
                  'Privacy Policy',
                  'Terms',
                  'No-Logs Audit',
                  'Cookie Policy',
                  'GDPR'
                ])),
              ],
            ),
          SizedBox(height: isMobile ? 28 : 36),
          _FooterAppsRow(isMobile: isMobile),
          SizedBox(height: isMobile ? 28 : 40),
          Divider(color: Colors.white.withValues(alpha: 0.06)),
          SizedBox(height: isMobile ? 16 : 24),
          if (isMobile)
            Column(children: [
              Text('(c) 2026 Atmos VPN Ltd. All rights reserved.',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.25),
                      fontSize: 12)),
              const SizedBox(height: 8),
              Text('EN  |  Privacy Choice',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.25),
                      fontSize: 12)),
            ])
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('(c) 2026 Atmos VPN Ltd. All rights reserved.',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.25),
                        fontSize: 12)),
                Text('EN  |  Privacy Choice',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.25),
                        fontSize: 12)),
              ],
            ),
        ],
      ),
    );
  }
}

class _FooterBrand extends StatelessWidget {
  final bool isMobile;
  const _FooterBrand({this.isMobile = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.shield_rounded,
                  color: Colors.white, size: 18)),
          const SizedBox(width: 10),
          const Text('Atmos VPN',
              style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  color: Colors.white)),
        ]),
        const SizedBox(height: 16),
        Text('Protecting digital freedom\nsince 2024.',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4), height: 1.6)),
        const SizedBox(height: 18),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: const [
            _FooterSocialIcon(Icons.facebook),
            _FooterSocialIcon(Icons.close),
            _FooterSocialIcon(Icons.business),
            _FooterSocialIcon(Icons.play_circle_filled),
            _FooterSocialIcon(Icons.camera_alt_rounded),
          ],
        ),
        if (!isMobile) ...[
          const SizedBox(height: 18),
          Row(
            children: [
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: _StoreBadge(
                    label: 'App Store',
                    topText: 'Download on the',
                    imagePath: 'assets/images/apple-logo.png',
                    isMobile: isMobile,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: _StoreBadge(
                    label: 'Google Play',
                    topText: 'GET IT ON',
                    imagePath: 'assets/images/google-play.png',
                    isMobile: isMobile,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _FooterCol extends StatelessWidget {
  final String title;
  final List<String> links;
  final bool isMobile;
  const _FooterCol(this.title, this.links, {this.isMobile = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(
                fontSize: isMobile ? 10 : 11,
                fontWeight: FontWeight.w900,
                color: AppColors.primaryBlue,
                letterSpacing: 1.2)),
        const SizedBox(height: 16),
        ...links.map((l) => _FooterLink(l, isMobile: isMobile)),
      ],
    );
  }
}

class _StoreBadge extends StatelessWidget {
  final String label;
  final String topText;
  final String imagePath;
  final bool isMobile;
  const _StoreBadge(
      {required this.label,
      required this.topText,
      required this.imagePath,
      this.isMobile = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          EdgeInsets.symmetric(horizontal: isMobile ? 12 : 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Image.asset(imagePath,
            width: isMobile ? 22 : 24,
            height: isMobile ? 22 : 24,
            fit: BoxFit.contain),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(topText,
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: isMobile ? 6 : 7,
                        fontWeight: FontWeight.w600,
                        height: 1.2)),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(label,
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: isMobile ? 11 : 12,
                        height: 1.2)),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

class _FooterSocialIcon extends StatefulWidget {
  final IconData icon;
  const _FooterSocialIcon(this.icon);

  @override
  State<_FooterSocialIcon> createState() => _FooterSocialIconState();
}

class _FooterSocialIconState extends State<_FooterSocialIcon> {
  bool isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => isHovered = true),
      onExit: (_) => setState(() => isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: isHovered
              ? Colors.grey.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Icon(widget.icon, color: Colors.white),
      ),
    );
  }
}

class _FooterAppsRow extends StatefulWidget {
  final bool isMobile;
  const _FooterAppsRow({this.isMobile = false});

  @override
  State<_FooterAppsRow> createState() => _FooterAppsRowState();
}

class _FooterAppsRowState extends State<_FooterAppsRow> {
  int? hoveredIndex;

  @override
  Widget build(BuildContext context) {
    final items = const [
      (Icons.window_rounded, 'Windows'),
      (Icons.laptop_mac_rounded, 'macOS'),
      (Icons.android_rounded, 'Android'),
      (Icons.computer_rounded, 'Linux'),
      (Icons.apple, 'iOS'),
      (Icons.chrome_reader_mode_outlined, 'Chrome'),
      (Icons.public_rounded, 'Firefox'),
      (Icons.travel_explore_rounded, 'Edge'),
    ];

    return Align(
      alignment: Alignment.center,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: widget.isMobile ? 38 : 60,
        runSpacing: widget.isMobile ? 18 : 26,
        children: List.generate(items.length, (index) {
          final item = items[index];
          final isHovered = hoveredIndex == index;

          return MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => hoveredIndex = index),
            onExit: (_) => setState(() => hoveredIndex = null),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isHovered
                    ? Colors.grey.withValues(alpha: 0.18)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: widget.isMobile ? 40 : 52,
                    height: widget.isMobile ? 40 : 52,
                    alignment: Alignment.center,
                    child: Icon(
                      item.$1,
                      color: Colors.white,
                      size: widget.isMobile ? 24 : 30,
                    ),
                  ),
                  SizedBox(height: widget.isMobile ? 1 : 1),
                  Text(
                    item.$2,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: widget.isMobile ? 11 : 12,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _FooterLink extends StatefulWidget {
  final String label;
  final bool isMobile;
  const _FooterLink(this.label, {this.isMobile = false});

  @override
  State<_FooterLink> createState() => _FooterLinkState();
}

class _FooterLinkState extends State<_FooterLink> {
  bool _hovered = false;

  void _onTap() {
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
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: _onTap,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            widget.label,
            style: TextStyle(
                color: _hovered ? Colors.white : Colors.white54,
                fontSize: widget.isMobile ? 12 : 13),
          ),
        ),
      ),
    );
  }
}
