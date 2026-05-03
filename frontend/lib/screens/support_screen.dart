import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../utils/design_system.dart';
import '../widgets/app_container.dart';

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        title: const Text('Help & Support', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
      ),
      body: AppContainer(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSupportHeader().animate().fadeIn().moveY(begin: 10, end: 0),
              const SizedBox(height: 32),
              _buildContactOptions().animate().fadeIn(delay: 200.ms),
              const SizedBox(height: 32),
              const Text('FREQUENTLY ASKED QUESTIONS', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.5)),
              const SizedBox(height: 16),
              _buildFAQList().animate().fadeIn(delay: 400.ms),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSupportHeader() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primaryBlue.withValues(alpha: 0.2), Colors.transparent],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          const Icon(Icons.headset_mic_rounded, color: AppColors.primaryBlue, size: 48),
          const SizedBox(height: 16),
          const Text('How can we help?', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          const Text(
            'Our team is available 24/7 to assist you with any issues or questions.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildContactOptions() {
    return Row(
      children: [
        Expanded(child: _contactCard('Live Chat', Icons.chat_bubble_rounded, AppColors.primaryBlue)),
        const SizedBox(width: 16),
        Expanded(child: _contactCard('Email Us', Icons.mail_rounded, AppColors.neonCyan)),
      ],
    );
  }

  Widget _contactCard(String title, IconData icon, Color color) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {}, // Simulated contact action
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(height: 12),
              Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFAQList() {
    final faqs = [
      ('How do I change my server location?', 'Go to the Server List from the dashboard and tap on any country to connect instantly.'),
      ('Is my data really private?', 'Yes, we use AES-256 encryption and follow a strict zero-logs policy audited by third parties.'),
      ('Why is my connection slow?', 'Speeds can vary based on distance. Try connecting to a server closer to your physical location.'),
      ('How many devices can I connect?', 'Pro users can connect up to 10 devices simultaneously with a single account.'),
    ];

    return Column(
      children: faqs.map((faq) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: ExpansionTile(
          shape: const RoundedRectangleBorder(side: BorderSide.none),
          iconColor: AppColors.primaryBlue,
          collapsedIconColor: Colors.white54,
          title: Text(faq.$1, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(faq.$2, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5)),
            ),
          ],
        ),
      )).toList(),
    );
  }
}
