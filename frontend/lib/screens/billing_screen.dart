import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/design_system.dart';
import '../utils/api_service.dart';
import '../widgets/app_container.dart';

class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  List<dynamic> _history = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await ApiService.getBillingHistory();
      if (resp['success'] == true) {
        setState(() {
          _history = resp['data'] ?? [];
        });
      } else {
        setState(() {
          _error = resp['message'] ?? 'Failed to load billing';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Cannot connect to server. Check your connection.';
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _cancelSubscription() async {
    try {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Opening billing portal...'),
              duration: Duration(seconds: 2)),
        );
      final resp = await ApiService.getBillingPortal();
      if (resp['success'] == true && resp['data']?['portal_url'] != null) {
        final url = Uri.parse(resp['data']['portal_url']);
        if (await canLaunchUrl(url)) {
          await launchUrl(
            url,
            mode: LaunchMode.inAppWebView,
            webViewConfiguration:
                const WebViewConfiguration(enableJavaScript: true),
          );
          // Refresh billing history after user closes the portal
          if (mounted) _loadHistory();
        }
      } else {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text(resp['message'] ?? 'Failed to open billing portal')),
          );
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Cannot connect to server. Please try again.')),
        );
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
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Billing & Subscriptions',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
      ),
      body: AppContainer(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            color: AppColors.warning, size: 48),
                        const SizedBox(height: 16),
                        Text(_error!,
                            style:
                                const TextStyle(color: AppColors.textSecondary),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 24),
                        ElevatedButton(
                            onPressed: _loadHistory,
                            child: const Text('Retry')),
                      ],
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 20),
                    children: [
                      // Upgrade button
                      ElevatedButton.icon(
                        onPressed: () =>
                            Navigator.pushNamed(context, '/account/pricing'),
                        icon: const Icon(Icons.rocket_launch_rounded),
                        label: const Text('UPGRADE PLAN',
                            style: TextStyle(
                                fontWeight: FontWeight.w900, letterSpacing: 1)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                      ).animate().fadeIn(),
                      const SizedBox(height: 32),

                      const Text('BILLING HISTORY',
                          style: TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                              letterSpacing: 1)),
                      const SizedBox(height: 16),

                      if (_history.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            color: AppColors.cardBackground,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.divider),
                          ),
                          child: const Column(
                            children: [
                              Icon(Icons.receipt_long_rounded,
                                  color: AppColors.textSecondary, size: 48),
                              SizedBox(height: 16),
                              Text('No billing history',
                                  style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 15)),
                              SizedBox(height: 8),
                              Text('You are on the Free plan.',
                                  style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 13)),
                            ],
                          ),
                        )
                      else
                        ...List.generate(_history.length, (i) {
                          final sub = _history[i];
                          final date =
                              DateTime.tryParse(sub['started_at'] ?? '')
                                  ?.toLocal();
                          final dateStr = date != null
                              ? '${date.day}/${date.month}/${date.year}'
                              : 'Unknown date';
                          final amount = (sub['amount_pence'] ?? 0) / 100.0;
                          final isActive = sub['status'] == 'active';
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: AppColors.cardBackground,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppColors.divider),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? AppColors.success
                                            .withValues(alpha: 0.1)
                                        : AppColors.textSecondary
                                            .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    isActive
                                        ? Icons.verified_rounded
                                        : Icons.history_rounded,
                                    color: isActive
                                        ? AppColors.success
                                        : AppColors.textSecondary,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${(sub['plan'] ?? 'Free').toString().toUpperCase()} — ${sub['billing_cycle'] ?? ''}',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14),
                                      ),
                                      Text(dateStr,
                                          style: const TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 12)),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '£${amount.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 15),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: (isActive
                                                ? AppColors.success
                                                : AppColors.textSecondary)
                                            .withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        sub['status']
                                                ?.toString()
                                                .toUpperCase() ??
                                            '',
                                        style: TextStyle(
                                          color: isActive
                                              ? AppColors.success
                                              : AppColors.textSecondary,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          )
                              .animate()
                              .fadeIn(delay: Duration(milliseconds: i * 80));
                        }),

                      if (_history.any((s) => s['status'] == 'active')) ...[
                        const SizedBox(height: 32),
                        TextButton.icon(
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: AppColors.cardBackground,
                                title: const Text('Cancel Subscription',
                                    style: TextStyle(color: Colors.white)),
                                content: const Text(
                                    'Are you sure? You will retain access until the end of your billing period.',
                                    style: TextStyle(
                                        color: AppColors.textSecondary)),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: const Text('Keep Plan')),
                                  TextButton(
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      _cancelSubscription();
                                    },
                                    child: const Text('CANCEL SUBSCRIPTION',
                                        style: TextStyle(
                                            color: AppColors.warning,
                                            fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            );
                          },
                          icon: const Icon(Icons.cancel_outlined,
                              color: AppColors.warning),
                          label: const Text('Cancel Subscription',
                              style: TextStyle(
                                  color: AppColors.warning,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                      const SizedBox(height: 40),
                    ],
                  ),
      ),
    );
  }
}
