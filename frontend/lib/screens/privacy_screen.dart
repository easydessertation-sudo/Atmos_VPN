import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/design_system.dart';
import '../widgets/app_container.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  Future<void> _launchEmail() async {
    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: 'privacy@atmosvpn.com',
      queryParameters: {
        'subject': 'AtmosVPN Privacy Request',
      },
    );
    try {
      await launchUrl(emailLaunchUri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _launchAuditReport() async {
    final Uri url = Uri.parse('https://atmosvpn.com/audit');
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Privacy Policy',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
        centerTitle: false,
      ),
      body: AppContainer(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- Last Updated ---
              const Text(
                'Last Updated: May 18, 2026',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 24),
              const Divider(color: AppColors.divider, height: 1),
              const SizedBox(height: 24),

              // --- 1. OUR COMMITMENT TO YOUR PRIVACY ---
              _buildSectionHeader('1. Our Commitment to Your Privacy'),
              const SizedBox(height: 12),
              _buildCommitmentSection(),
              const SizedBox(height: 32),
              const Divider(color: AppColors.divider, height: 1),
              const SizedBox(height: 32),

              // --- 2. WHAT WE DO NOT COLLECT ---
              _buildSectionHeader('2. What We Do NOT Collect'),
              const SizedBox(height: 12),
              _buildNotCollectSection(),
              const SizedBox(height: 32),
              const Divider(color: AppColors.divider, height: 1),
              const SizedBox(height: 32),

              // --- 3. DATA WE COLLECT ---
              _buildSectionHeader('3. Data We Collect'),
              const SizedBox(height: 16),
              _buildDataCollectedList(),
              const SizedBox(height: 32),
              const Divider(color: AppColors.divider, height: 1),
              const SizedBox(height: 32),

              // --- 4. LEGAL BASIS (GDPR) ---
              _buildSectionHeader('4. Legal Basis (GDPR)'),
              const SizedBox(height: 16),
              _buildLegalBasisSection(),
              const SizedBox(height: 32),
              const Divider(color: AppColors.divider, height: 1),
              const SizedBox(height: 32),

              // --- 5. YOUR RIGHTS ---
              _buildSectionHeader('5. Your Rights'),
              const SizedBox(height: 16),
              _buildYourRightsSection(),
              const SizedBox(height: 32),
              const Divider(color: AppColors.divider, height: 1),
              const SizedBox(height: 32),

              // --- 6. THIRD-PARTY SERVICES ---
              _buildSectionHeader('6. Third-Party Services'),
              const SizedBox(height: 16),
              _buildThirdPartySection(),
              const SizedBox(height: 32),
              const Divider(color: AppColors.divider, height: 1),
              const SizedBox(height: 32),

              // --- 7. SECURITY ---
              _buildSectionHeader('7. Security'),
              const SizedBox(height: 16),
              _buildSecuritySection(),
              const SizedBox(height: 32),
              const Divider(color: AppColors.divider, height: 1),
              const SizedBox(height: 32),

              // --- 8. CHILDREN & POLICY UPDATES ---
              _buildChildrenAndUpdatesSection(),
              const SizedBox(height: 32),
              const Divider(color: AppColors.divider, height: 1),
              const SizedBox(height: 32),

              // --- 9. ZERO-LOGS POLICY (Moved here) ---
              _buildSectionHeader('9. Zero-Logs Policy'),
              const SizedBox(height: 12),
              _buildZeroLogsSection(),
              const SizedBox(height: 32),
              const Divider(color: AppColors.divider, height: 1),
              const SizedBox(height: 32),

              // --- CONTACT CARD ---
              _buildContactSection(),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w800,
        fontSize: 18,
      ),
    );
  }

  Widget _buildCommitmentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'AtmosVPN operates under a strict zero-logs policy. We do not collect, store, or process any data that could identify you or link your online activities to your account.',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'AtmosVPN has been independently audited by Cure53 Security Research.',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _launchAuditReport,
          child: const Text(
            'View Audit Report →',
            style: TextStyle(
              color: AppColors.primaryBlue,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNotCollectSection() {
    return const Text(
      'We never store your IP address, browsing history, traffic data, DNS queries, connection timestamps, session duration, bandwidth usage, or the VPN server IP you connect to.',
      style: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 14,
        height: 1.5,
      ),
    );
  }

  Widget _buildZeroLogsSection() {
    final List<String> noLogsItems = [
      'Browsing history',
      'IP addresses',
      'DNS queries',
      'Connection timestamps',
      'VPN traffic data',
      'Session duration',
      'Bandwidth usage',
      'VPN server activity',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'AtmosVPN operates a strict no-logs policy. We do not collect, monitor, store, or log any of the following data:',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        Column(
          children: noLogsItems.map((item) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6.0),
                    child: Icon(Icons.circle, color: AppColors.textSecondary, size: 6),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        const Text(
          'Our network architecture and no-logs systems have been independently audited and verified by Cure53.',
          style: TextStyle(
            color: AppColors.success,
            fontWeight: FontWeight.w600,
            fontSize: 14,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildDataCollectedList() {
    final List<Map<String, String>> data = [
      {
        'title': 'Email Address',
        'purpose': 'Account login, subscription management & recovery',
        'retention': 'Until account deletion',
      },
      {
        'title': 'Payment Data',
        'purpose': 'Secure subscription billing processed entirely via Stripe',
        'retention': 'Per Stripe merchant policy',
      },
      {
        'title': 'Push Notification Token',
        'purpose': 'Delivery of real-time account, expiry & security alerts',
        'retention': 'Until revoked/refreshed',
      },
      {
        'title': 'Anonymous Crash Reports',
        'purpose': 'Fully anonymous technical reports to fix bugs & improve stability',
        'retention': '90 days maximum',
      },
      {
        'title': 'Google/Apple Display Name',
        'purpose': 'Optional display name linked during SSO login',
        'retention': 'Until account deletion',
      },
    ];

    return Column(
      children: data.map((item) {
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      item['title']!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    item['retention']!,
                    style: const TextStyle(
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Purpose: ${item['purpose']!}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildLegalBasisSection() {
    final points = [
      'Providing and maintaining the core VPN connection service.',
      'Subscription authentication and billing processing.',
      'Maintaining app security, stability, and detecting fraud.',
      'Push notifications for critical alerts (requires your consent).',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Under GDPR (EU/EEA laws), we process your minimal account data under the following legitimate legal bases:',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        ...points.map((p) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6.0),
                    child: Icon(Icons.circle, color: AppColors.textSecondary, size: 6),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      p,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            )),
        const SizedBox(height: 12),
        const Text(
          'We strictly never sell, trade, or rent user account data to advertisers or third parties.',
          style: TextStyle(
            color: AppColors.success,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildYourRightsSection() {
    final rights = [
      'Access and export your registered account data.',
      'Correct or update your email address or name.',
      'Instantly delete your account and all associated logs.',
      'Withdraw consent to push notifications at any time.',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'You hold full control over your private information. You have the right to:',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        ...rights.map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6.0),
                    child: Icon(Icons.circle, color: AppColors.textSecondary, size: 6),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      r,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            )),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'WANT TO SIGN OUT THE ACCOUNT?',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'You can sign out your account instantly inside the app by going to Settings → LOGOUT.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildThirdPartySection() {
    final services = [
      {
        'name': 'Stripe',
        'desc': 'Processes all core billing and subscription transactions securely without disclosing full card data to us.'
      },
      {
        'name': 'Google Play & Apple Pay',
        'desc': 'Handles in-app purchases and subscription registration on Android and iOS.'
      },
      {
        'name': 'Hosting Services',
        'desc': 'Secure, encrypted cloud and bare-metal server infrastructure hosts our backend API and global VPN nodes.'
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: services.map((s) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s['name']!,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                s['desc']!,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSecuritySection() {
    final specs = [
      'Advanced WireGuard® and OpenVPN protocol support.',
      'ChaCha20-Poly1305 and AES-256 cipher encryption.',
      'Secure, localized key generation directly on your physical device.',
      'Full cryptographic shielding of user account logins using TLS 1.3.',
    ];

    return Column(
      children: specs.map((spec) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 6.0),
                child: Icon(Icons.circle, color: AppColors.textSecondary, size: 6),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  spec,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildChildrenAndUpdatesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('8. Children\'s Privacy & Policy Updates'),
        const SizedBox(height: 16),
        const Text(
          'Children\'s Privacy',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'AtmosVPN is not intended for use by children under the age of 13 (or 16 in the European Union/EEA). We do not knowingly collect any data from children.',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Policy Updates',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'We update this policy occasionally to remain fully transparent. If we make any major security or operational changes, we will notify all users via push notification or email at least 14 days in advance.',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildContactSection() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Have Privacy Questions?',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Our privacy officer is ready to help. We respond to all formal requests within 30 days.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _launchEmail,
            child: const Text(
              'EMAIL PRIVACY OFFICER (privacy@atmosvpn.com)',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.primaryBlue,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
