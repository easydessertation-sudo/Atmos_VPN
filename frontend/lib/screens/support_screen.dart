import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../utils/design_system.dart';
import '../widgets/app_container.dart';

import '../utils/api_service.dart';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  List<dynamic> _faqs = [];
  bool _isLoadingFaqs = true;

  @override
  void initState() {
    super.initState();
    _fetchFaqs();
  }

  Future<void> _fetchFaqs() async {
    try {
      final response = await ApiService.getFaqs();
      if (response['success'] == true) {
        if (mounted) {
          setState(() {
            _faqs = response['data']['categories'] ?? [];
            _isLoadingFaqs = false;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingFaqs = false);
    }
  }

  void _showTicketDialog(BuildContext context) {
    final emailCtrl = TextEditingController();
    final subjectCtrl = TextEditingController();
    final messageCtrl = TextEditingController();
    String category = 'general';
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: AppColors.cardBackground,
            title: const Text('Submit a Ticket', style: TextStyle(color: Colors.white)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: emailCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Email', labelStyle: TextStyle(color: AppColors.textSecondary))),
                  TextField(controller: subjectCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Subject', labelStyle: TextStyle(color: AppColors.textSecondary))),
                  DropdownButton<String>(
                    value: category,
                    dropdownColor: AppColors.cardBackground,
                    items: const [
                      DropdownMenuItem(value: 'general', child: Text('General', style: TextStyle(color: Colors.white))),
                      DropdownMenuItem(value: 'technical', child: Text('Technical', style: TextStyle(color: Colors.white))),
                      DropdownMenuItem(value: 'billing', child: Text('Billing', style: TextStyle(color: Colors.white))),
                    ],
                    onChanged: (v) => setState(() => category = v!),
                  ),
                  TextField(controller: messageCtrl, style: const TextStyle(color: Colors.white), maxLines: 3, decoration: const InputDecoration(labelText: 'Message', labelStyle: TextStyle(color: AppColors.textSecondary))),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: isSubmitting ? null : () async {
                  setState(() => isSubmitting = true);
                  final resp = await ApiService.submitSupportTicket(emailCtrl.text, subjectCtrl.text, messageCtrl.text, category);
                  if (resp['success'] == true) {
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ticket submitted successfully!')));
                    }
                  } else {
                    setState(() => isSubmitting = false);
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(resp['message'] ?? 'Failed to submit')));
                    }
                  }
                },
                child: isSubmitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Submit'),
              ),
            ],
          );
        }
      ),
    );
  }

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
        Expanded(child: _contactCard('Live Chat', Icons.chat_bubble_rounded, AppColors.primaryBlue, () {})),
        const SizedBox(width: 16),
        Expanded(child: _contactCard('Email Us', Icons.mail_rounded, AppColors.neonCyan, () => _showTicketDialog(context))),
      ],
    );
  }

  Widget _contactCard(String title, IconData icon, Color color, VoidCallback onTap) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
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
    if (_isLoadingFaqs) {
      return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: AppColors.primaryBlue)));
    }
    if (_faqs.isEmpty) {
      return const Text('No FAQs available right now.', style: TextStyle(color: AppColors.textSecondary));
    }

    return Column(
      children: _faqs.map((category) {
        final categoryName = category['category'] ?? 'General';
        final questions = (category['questions'] as List<dynamic>? ?? []);
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text(categoryName, style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.bold)),
            ),
            ...questions.map((faq) => Container(
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
                title: Text(faq['q'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Text(faq['a'] ?? '', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5)),
                  ),
                ],
              ),
            )),
          ],
        );
      }).toList(),
    );
  }
}
