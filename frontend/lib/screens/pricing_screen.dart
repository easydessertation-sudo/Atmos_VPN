import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/design_system.dart';
import '../widgets/app_container.dart';
import '../utils/responsive.dart';
import '../utils/api_service.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import 'web/landing_footer.dart';

class PricingScreen extends StatefulWidget {
  const PricingScreen({super.key});

  @override
  State<PricingScreen> createState() => _PricingScreenState();
}

class _PricingScreenState extends State<PricingScreen> {
  List<dynamic> _plans = [];
  bool _isLoading = true;

  @override 
  void initState() {
    super.initState();
    _fetchPlans();
  }

  Future<void> _fetchPlans() async {
    try {
      final response = await ApiService.getPlans();
      
      if (response['success'] == true) {
        if (mounted) {
          setState(() {
            final data = response['data'];
            List<dynamic> parsedPlans = [];
            
            if (data is List) {
              parsedPlans = data;
            } else if (data is Map) {
              // The API returns a map like: { "free": {...}, "starter": {...}, "pro": {...} }
              parsedPlans = data.entries.map((e) {
                var plan = Map<String, dynamic>.from(e.value);
                plan['id'] = e.key; // Inject the key as the plan ID
                plan['price_monthly'] = plan['monthly_usd'] ?? 0; // Map API field to UI field
                return plan;
              }).toList();
            }

            _plans = parsedPlans.where((p) => p['id'] != 'free').toList();
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _checkout(String planId) async {
    try {
      final response = await ApiService.createCheckout(planId, 'monthly');
      if (response['success'] == true) {
        final url = response['data']['checkout_url'];
        if (await canLaunchUrl(Uri.parse(url))) {
          await launchUrl(
            Uri.parse(url), 
            mode: LaunchMode.externalApplication,
          );
          
          // Workaround for Android in-app webview not supporting deep links:
          // When the user closes the payment window, we manually check if they upgraded!
          if (mounted) {
            final vpn = context.read<VPNProvider>();
            final wasFree = vpn.isFreeUser;
            await vpn.fetchProfile(); // Refresh from backend
            
            if (wasFree && !vpn.isFreeUser) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Payment Successful! Premium Unlocked.', style: TextStyle(fontWeight: FontWeight.bold)),
                  backgroundColor: AppColors.success,
                  behavior: SnackBarBehavior.floating,
                ),
              );
              Navigator.pushNamedAndRemoveUntil(context, '/dashboard', (route) => false);
            }
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(response['message'] ?? 'Checkout failed')));
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error initiating checkout. Are you logged in?')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          const _PricingTopBar(),
          Expanded(
            child: AppContainer(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Unlock All Premium Features',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -1,
                      ),
                    ).animate().fadeIn().moveY(begin: 10, end: 0),
                    
                    const SizedBox(height: 8),
                    
                    const Text(
                      'Choose the plan that fits your security needs',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
                    ).animate().fadeIn(delay: 200.ms),
                    
                    const SizedBox(height: 48),

                    if (_isLoading)
                      const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: AppColors.primaryBlue)))
                    else if (_plans.isEmpty)
                      const Center(child: Padding(padding: EdgeInsets.all(40), child: Text('No premium plans available right now.', style: TextStyle(color: AppColors.textSecondary))))
                    else
                      Builder(builder: (context) {
                        final cards = _plans.asMap().entries.map((entry) {
                          final i = entry.key;
                          final plan = entry.value;
                          final isPopular = plan['id'] == 'pro'; // Highlight Pro as popular
                          return _buildPricingCard(
                            context,
                            name: plan['name'].toString().toUpperCase(),
                            price: '£${plan['price_monthly']}',
                            period: 'month',
                            description: plan['id'] == 'premium' ? 'For ultimate privacy & power' : 'Perfect for regular users',
                            color: isPopular ? AppColors.neonCyan : (i == 0 ? AppColors.primaryBlue : AppColors.accentPurple),
                            features: [
                              plan['bandwidth_gb'] == null ? 'Unlimited Data' : '${plan['bandwidth_gb']} GB Data',
                              plan['speed_mbps'] == null ? 'Ultra-Fast Speeds' : 'Up to ${plan['speed_mbps']} Mbps',
                              '${plan['devices']} Devices',
                              if (plan['dedicated_ip'] == true) 'Dedicated IP Included',
                            ],
                            delay: (300 + i * 150).ms,
                            isPopular: isPopular,
                            badge: isPopular ? 'MOST POPULAR' : null,
                            onSelect: () => _checkout(plan['id']),
                          );
                        }).toList();

                        if (Responsive.isMobile(context)) {
                          return Column(
                            children: cards.map((c) => Padding(padding: const EdgeInsets.only(bottom: 24), child: c)).toList(),
                          );
                        }

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: cards.map((c) => Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(right: c != cards.last ? 24 : 0),
                              child: c,
                            )
                          )).toList(),
                        );
                      }),

                    const SizedBox(height: 32),
                    
                    // const Text(
                    //   '7-Day Money Back Guarantee • Cancel Anytime',
                    //   textAlign: TextAlign.center,
                    //   style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                    // ),
                    
                    const SizedBox(height: 40),
                    const LandingFooter(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPricingCard(
    BuildContext context, {
    required String name,
    required String price,
    required String period,
    required String description,
    required Color color,
    required List<String> features,
    required Duration delay,
    bool isPopular = false,
    String? badge,
    required VoidCallback onSelect,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isPopular ? color.withValues(alpha: 0.5) : AppColors.divider, width: isPopular ? 2 : 1),
        boxShadow: [
          if (isPopular)
            BoxShadow(
              color: color.withValues(alpha: 0.15),
              blurRadius: 30,
              spreadRadius: 2,
            ),
        ],
      ),
      child: Stack(
        children: [
          if (isPopular)
            Positioned(
              right: -20,
              top: -20,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          
          Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(name, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1.5)),
                    if (badge != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
                        child: Text(badge, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10)),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(price, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 36, letterSpacing: -1)),
                    const SizedBox(width: 4),
                    Text('/$period', style: const TextStyle(color: AppColors.textSecondary, fontSize: 16)),
                  ],
                ),
                Text(description, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
                
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Divider(color: AppColors.divider, height: 1),
                ),
                
                ...features.map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_rounded, color: color, size: 20),
                      const SizedBox(width: 12),
                      Expanded(child: Text(f, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600))),
                    ],
                  ),
                )),
                
                const SizedBox(height: 24),
                
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: ElevatedButton(
                      onPressed: onSelect,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isPopular ? color : AppColors.divider,
                      foregroundColor: isPopular ? Colors.white : Colors.white70,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: const Text('SELECT PLAN', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: delay).slideY(begin: 0.1, end: 0);
  }
}

class _PricingTopBar extends StatelessWidget {
  const _PricingTopBar();

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
              Text('/ Pricing', style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12)),
              const SizedBox(width: 10),
              const _NavMenu(title: 'Pricing'),
            ])
          : Row(children: [
              _LogoHomeLink(),
              const SizedBox(width: 32),
              Text('/ Pricing', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 14)),
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
          const Text('AtmosVPN', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white)),
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

class _PricingFooter extends StatelessWidget {
  const _PricingFooter();

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: EdgeInsets.symmetric(vertical: 28, horizontal: isMobile ? 16 : 60),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05)))),
      child: isMobile
          ? Column(children: [
              Text('© 2026 AtmosVPN Ltd.', style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 12)),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: ['/privacy-policy', '/terms', '/cookie-policy'].map((r) => TextButton(
                  onPressed: () => Navigator.pushNamed(context, r),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    r.replaceAll('-', ' ').replaceAll('/', '').replaceFirst(r[1], r[1].toUpperCase()),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11),
                  ),
                )).toList(),
              ),
            ])
          : Row(
              children: [
                Text('© 2026 AtmosVPN Ltd.', style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 12)),
                const Spacer(),
                ...['/privacy-policy', '/terms', '/cookie-policy'].map((r) => TextButton(
                  onPressed: () => Navigator.pushNamed(context, r),
                  child: Text(r.replaceAll('-', ' ').replaceAll('/', '').replaceFirst(r[1], r[1].toUpperCase()), style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 12)),
                )),
              ],
            ),
    );
  }
}

