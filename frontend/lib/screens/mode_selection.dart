import 'package:flutter/material.dart';
import '../utils/design_system.dart';

class ModeSelectionScreen extends StatefulWidget {
  const ModeSelectionScreen({super.key});

  @override
  State<ModeSelectionScreen> createState() => _ModeSelectionScreenState();
}

enum VPNMode { standard, streaming, gaming, crypto }

class _ModeSelectionScreenState extends State<ModeSelectionScreen> {
  VPNMode _selected = VPNMode.standard;

  static const _configs = {
    VPNMode.standard: _ModeData(
      'Generic VPN',
      'Secure everyday browsing with military-grade encryption.',
      Icons.shield_rounded,
      Color(0xFF3B82F6),
      ['Kill Switch', 'AES-256 Encryption', 'DNS Leak Guard', 'Split Tunneling', 'Auto Connect'],
      null,
    ),
    VPNMode.streaming: _ModeData(
      'Streaming Mode',
      'Bypass geo-blocks. Stream 4K without buffering.',
      Icons.movie_filter_rounded,
      Color(0xFF8B5CF6),
      ['Smart DNS', 'Platform Auto-Select', 'Buffer Optimization', '4K Streaming Ready'],
      ['Netflix', 'Disney+', 'Hulu', 'Amazon Prime', 'BBC iPlayer', 'HBO Max'],
    ),
    VPNMode.gaming: _ModeData(
      'Gaming Mode',
      'Ultra-low latency routing with anti-DDoS protection.',
      Icons.sports_esports_rounded,
      Color(0xFFF97316),
      ['DDoS Protection', 'Route Optimization', 'Packet Boost', 'Region Unlock', 'Low Jitter'],
      ['Call of Duty', 'Fortnite', 'PUBG', 'Valorant', 'Apex Legends', 'FIFA 25'],
    ),
    VPNMode.crypto: _ModeData(
      'Crypto Mode',
      'Isolated secure tunnel for trading and cold wallet access.',
      Icons.currency_bitcoin_rounded,
      Color(0xFFF59E0B),
      ['Anti-Phishing DNS', 'Kill Switch (Forced)', 'Tracker Blocking', 'Dark Web Monitor', 'Secure DNS'],
      ['Binance', 'Coinbase', 'Kraken', 'Bybit', 'OKX', 'Gemini'],
    ),
  };

  @override
  Widget build(BuildContext context) {
    final config = _configs[_selected]!;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Mode-colored background glow
          Positioned(
            top: -80,
            right: -80,
            child: _Glow(config.color.withValues(alpha: 0.12), 350),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildAppBar(context),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        _buildModeGrid(),
                        const SizedBox(height: 24),
                        _buildModeDetail(config),
                        const SizedBox(height: 24),
                        if (config.platforms != null) _buildPlatforms(config),
                        if (config.platforms != null) const SizedBox(height: 24),
                        _buildFeatures(config),
                        const SizedBox(height: 24),
                        _buildConnectButton(context, config),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(child: Text('VPN Mode', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20))),
        ],
      ),
    );
  }

  Widget _buildModeGrid() {
    final modes = [
      (VPNMode.standard, Icons.shield_rounded, 'Standard', const Color(0xFF3B82F6)),
      (VPNMode.streaming, Icons.movie_filter_rounded, 'Streaming', const Color(0xFF8B5CF6)),
      (VPNMode.gaming, Icons.sports_esports_rounded, 'Gaming', const Color(0xFFF97316)),
      (VPNMode.crypto, Icons.currency_bitcoin_rounded, 'Crypto', const Color(0xFFF59E0B)),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: modes.map((m) {
        final isSelected = _selected == m.$1;
        return GestureDetector(
          onTap: () => setState(() => _selected = m.$1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isSelected ? m.$4.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isSelected ? m.$4.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.08),
                width: isSelected ? 1.5 : 1,
              ),
              boxShadow: isSelected ? [BoxShadow(color: m.$4.withValues(alpha: 0.15), blurRadius: 20)] : [],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: m.$4.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                  child: Icon(m.$2, color: m.$4, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m.$3, style: TextStyle(color: isSelected ? Colors.white : Colors.white60, fontWeight: FontWeight.w800, fontSize: 14)),
                    if (isSelected)
                      Text('Active', style: TextStyle(color: m.$4, fontSize: 10, fontWeight: FontWeight.w700)),
                  ]),
                ),
                if (isSelected)
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: m.$4, shape: BoxShape.circle)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildModeDetail(_ModeData config) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [config.color.withValues(alpha: 0.12), config.color.withValues(alpha: 0.04)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: config.color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: config.color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
            child: Icon(config.icon, color: config.color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(config.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
              const SizedBox(height: 4),
              Text(config.desc, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4)),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildPlatforms(_ModeData config) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _selected == VPNMode.streaming ? 'Streaming Platforms' : _selected == VPNMode.gaming ? 'Optimized Games' : 'Supported Exchanges',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: config.platforms!.map((p) => _PlatformChip(p, config.color)).toList(),
        ),
      ],
    );
  }

  Widget _buildFeatures(_ModeData config) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Mode Features', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 12),
        ...config.features.map((f) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: config.color.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: Icon(Icons.check_rounded, color: config.color, size: 12),
              ),
              const SizedBox(width: 12),
              Text(f, style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
        )),
      ],
    );
  }

  Widget _buildConnectButton(BuildContext context, _ModeData config) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () => Navigator.pushNamed(context, '/dashboard'),
        icon: const Icon(Icons.bolt_rounded, size: 20),
        label: Text('Quick Connect — ${config.name}'),
        style: ElevatedButton.styleFrom(
          backgroundColor: config.color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 18),
          textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
      ),
    );
  }
}

class _PlatformChip extends StatefulWidget {
  final String label;
  final Color color;
  const _PlatformChip(this.label, this.color);

  @override
  State<_PlatformChip> createState() => _PlatformChipState();
}

class _PlatformChipState extends State<_PlatformChip> {
  bool _selected = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _selected = !_selected),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: _selected ? widget.color.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: _selected ? widget.color.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_selected) ...[
              Icon(Icons.check_rounded, color: widget.color, size: 12),
              const SizedBox(width: 6),
            ],
            Text(widget.label, style: TextStyle(color: _selected ? widget.color : Colors.white60, fontSize: 13, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _ModeData {
  final String name, desc;
  final IconData icon;
  final Color color;
  final List<String> features;
  final List<String>? platforms;
  const _ModeData(this.name, this.desc, this.icon, this.color, this.features, this.platforms);
}

class _Glow extends StatelessWidget {
  final Color color;
  final double size;
  const _Glow(this.color, this.size);

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [color, Colors.transparent])),
  );
}
