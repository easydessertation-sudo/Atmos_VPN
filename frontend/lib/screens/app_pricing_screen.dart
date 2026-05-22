import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import '../utils/design_system.dart';
import '../utils/api_service.dart';
import '../main.dart';

class AppPricingScreen extends StatefulWidget {
  const AppPricingScreen({super.key});

  @override
  State<AppPricingScreen> createState() => _AppPricingScreenState();
}

class _AppPricingScreenState extends State<AppPricingScreen> {
  List<dynamic> _plans = [];
  bool _isLoading = true;
  String _selectedPlanId = 'pro';

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
              parsedPlans = data.entries.map((e) {
                var plan = Map<String, dynamic>.from(e.value);
                plan['id'] = e.key;
                plan['price_monthly'] = plan['monthly_usd'] ?? 0;
                return plan;
              }).toList();
            }

            _plans = parsedPlans.toList();
            if (_plans.isNotEmpty && !_plans.any((p) => p['id'] == 'pro')) {
              _selectedPlanId = _plans.first['id'];
            }
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

  Future<void> _checkout() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService.createCheckout(_selectedPlanId, 'monthly');
      if (response['success'] == true) {
        final url = response['data']['checkout_url'];
        if (await canLaunchUrl(Uri.parse(url))) {
          await launchUrl(
            Uri.parse(url), 
            mode: LaunchMode.externalApplication,
          );
          
          if (mounted) {
            final vpn = context.read<VPNProvider>();
            final wasFree = vpn.isFreeUser;
            await vpn.fetchProfile();
            
            if (wasFree && !vpn.isFreeUser) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Payment Successful! Premium Unlocked.', style: TextStyle(fontWeight: FontWeight.bold)),
                  backgroundColor: AppColors.success,
                  behavior: SnackBarBehavior.floating,
                ),
              );
              Navigator.pushNamedAndRemoveUntil(context, '/dashboard', (route) => false);
              return;
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
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 10),
                  // Header
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.workspace_premium_rounded, color: AppColors.primaryBlue, size: 32),
                  ).animate().scale(delay: 100.ms, duration: 400.ms, curve: Curves.easeOutBack),
                  
                  const SizedBox(height: 24),
                  
                  const Text(
                    'Unlock Premium',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -1,
                    ),
                  ).animate().fadeIn(delay: 200.ms).moveY(begin: 10, end: 0),
                  
                  const SizedBox(height: 12),
                  
                  const Text(
                    'Get unlimited bandwidth, ultra-fast servers, and maximum security.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 16, height: 1.4),
                  ).animate().fadeIn(delay: 300.ms),
                  
                  const SizedBox(height: 40),

                  if (_isLoading && _plans.isEmpty)
                    const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: AppColors.primaryBlue)))
                  else if (_plans.isEmpty)
                    const Center(child: Padding(padding: EdgeInsets.all(40), child: Text('No premium plans available right now.', style: TextStyle(color: AppColors.textSecondary))))
                  else
                    ..._plans.asMap().entries.map((entry) {
                      final i = entry.key;
                      final plan = entry.value;
                      final currency = plan['currency']?.toString() ?? 'USD';
                      String currencySymbol = '\$';
                      if (currency.toUpperCase() == 'GBP') {
                        currencySymbol = '£';
                      } else if (currency.toUpperCase() == 'EUR') {
                        currencySymbol = '€';
                      } else if (currency.toUpperCase() == 'INR') {
                        currencySymbol = '₹';
                      }
                      return _buildAppPricingCard(
                        planId: plan['id'],
                        name: plan['name'].toString().toUpperCase(),
                        price: plan['price_monthly'].toString(),
                        currencySymbol: currencySymbol,
                        delay: (400 + i * 150).ms,
                      );
                    }),
                    
                  const SizedBox(height: 32),
                  
                  // Dynamic Features List based on Selected Plan Specifications
                  if (_plans.isNotEmpty) Builder(
                    builder: (context) {
                      Map<String, dynamic>? selectedPlan;
                      for (var plan in _plans) {
                        if (plan is Map && plan['id'] == _selectedPlanId) {
                          selectedPlan = Map<String, dynamic>.from(plan);
                          break;
                        }
                      }
                      if (selectedPlan == null) return const SizedBox.shrink();

                      final featuresMap = selectedPlan['features'] is Map ? selectedPlan['features'] : {};
                      
                      final speedVal = selectedPlan['speed_mbps'];
                      final speedText = speedVal == null ? 'Unlimited high-speed bandwidth' : 'High speed up to $speedVal Mbps';

                      final devicesVal = selectedPlan['simultaneous'] ?? selectedPlan['devices'];
                      final devicesText = devicesVal == null ? 'Connect unlimited devices' : 'Connect up to $devicesVal devices';

                      final bandwidthVal = selectedPlan['bandwidth_gb'];
                      final bandwidthText = bandwidthVal == null ? 'Unlimited data volume' : '$bandwidthVal GB data bandwidth';

                      final hasStreaming = featuresMap['streaming'] == true;
                      final hasP2P = featuresMap['p2p'] == true;
                      final hasDedicatedIp = selectedPlan['dedicated_ip'] == true || featuresMap['dedicated_ip'] == true;
                      final hasAdBlocker = featuresMap['ad_blocker'] == true;
                      final hasKillSwitch = featuresMap['kill_switch'] == true;
                      final hasPrioritySupport = featuresMap['priority_support'] == true;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'PLAN SPECIFICATIONS',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                              letterSpacing: 1.5,
                            ),
                          ).animate().fadeIn(duration: 300.ms),
                          const SizedBox(height: 16),
                          _buildFeatureRow(Icons.speed_rounded, speedText),
                          _buildFeatureRow(Icons.devices_rounded, devicesText),
                          _buildFeatureRow(Icons.data_usage_rounded, bandwidthText),
                          if (hasStreaming) _buildFeatureRow(Icons.play_circle_outline_rounded, 'Premium streaming unlocked'),
                          if (hasP2P) _buildFeatureRow(Icons.swap_horizontal_circle_outlined, 'P2P & torrent traffic allowed'),
                          if (hasDedicatedIp) _buildFeatureRow(Icons.vpn_lock_rounded, 'Dedicated IP address included'),
                          if (hasAdBlocker) _buildFeatureRow(Icons.block_flipped, 'Built-in Ad Blocker included'),
                          if (hasKillSwitch) _buildFeatureRow(Icons.toggle_on_rounded, 'Secure Kill Switch enabled'),
                          if (hasPrioritySupport) _buildFeatureRow(Icons.support_agent_rounded, '24/7 Priority VIP support'),
                        ],
                      );
                    }
                  ),
                  
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
          
          // Bottom Checkout Area
          if (_plans.isNotEmpty) Builder(
            builder: (context) {
              final currentPlanId = context.watch<VPNProvider>().userData?['plan'] ?? 'free';
              final isCurrentPlan = _selectedPlanId == currentPlanId;
              final isFreePlanSelected = _selectedPlanId == 'free';
              final isButtonDisabled = _isLoading || isCurrentPlan || isFreePlanSelected;
              
              String buttonText = 'CONTINUE';
              if (isCurrentPlan) buttonText = 'CURRENT PLAN';
              else if (isFreePlanSelected) buttonText = 'FREE PLAN';

              return Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.cardBackground,
                  border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ElevatedButton(
                        onPressed: isButtonDisabled ? null : _checkout,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: _isLoading 
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
                          : Text(buttonText, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1)),
                      ),
                    // const SizedBox(height: 16),
                    // const Text(
                    //   '7-Day Money-Back Guarantee. Cancel anytime.',
                    //   textAlign: TextAlign.center,
                    //   style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    // ),
                  ],
                ),
              ),
            ).animate().slideY(begin: 1.0, end: 0, delay: 500.ms, curve: Curves.easeOutCubic);
            }
          ),
        ],
      ),
    );
  }

  Widget _buildAppPricingCard({
    required String planId,
    required String name,
    required String price,
    required String currencySymbol,
    required Duration delay,
  }) {
    final isSelected = _selectedPlanId == planId;
    final isPopular = planId == 'pro';
    
    return GestureDetector(
      onTap: () => setState(() => _selectedPlanId = planId),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryBlue.withValues(alpha: 0.1) : AppColors.cardBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primaryBlue : AppColors.divider,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: AppColors.primaryBlue.withValues(alpha: 0.2),
                blurRadius: 20,
                spreadRadius: -5,
              )
          ],
        ),
        child: Row(
          children: [
            // Radio button style indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppColors.primaryBlue : AppColors.textSecondary.withValues(alpha: 0.5),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          color: AppColors.primaryBlue,
                          shape: BoxShape.circle,
                        ),
                      ),
                    )
                  : null,
            ),
            
            const SizedBox(width: 16),
            
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      if (isPopular) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.neonCyan.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'POPULAR',
                            style: TextStyle(color: AppColors.neonCyan, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                          ),
                        ),
                      ]
                    ],
                  ),
                ],
              ),
            ),
            
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$currencySymbol$price',
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
                Text(
                  '/ month',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: delay).slideY(begin: 0.2, end: 0);
  }
  
  Widget _buildFeatureRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.white70, size: 16),
          ),
          const SizedBox(width: 16),
          Text(text, style: const TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
