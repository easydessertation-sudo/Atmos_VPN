import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../utils/design_system.dart';
import '../widgets/app_container.dart';
import '../main.dart';

class MapViewScreen extends StatefulWidget {
  const MapViewScreen({super.key});

  @override
  State<MapViewScreen> createState() => _MapViewScreenState();
}

class _MapViewScreenState extends State<MapViewScreen> {
  final Map<String, Offset> _markerPositions = {
    'USA': const Offset(0.2, 0.4),
    'UK': const Offset(0.48, 0.32),
    'Germany': const Offset(0.52, 0.35),
    'Japan': const Offset(0.85, 0.45),
    'Singapore': const Offset(0.78, 0.65),
    'Australia': const Offset(0.85, 0.8),
    'Brazil': const Offset(0.3, 0.75),
    'India': const Offset(0.7, 0.5),
  };

  String? _selectedCountry;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<VPNProvider>();
    
    return Scaffold(
      backgroundColor: AppColors.background,
      body: AppContainer(
        child: Stack(
          children: [
            // stylised background map (could be an image or custom paint)
            _buildStylizedMap(),

            // Overlays
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(),
                  const Spacer(),
                  if (_selectedCountry != null)
                    _buildSelectionCard(provider)
                        .animate()
                        .fadeIn()
                        .slideY(begin: 0.2, end: 0),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStylizedMap() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.background,
      ),
      child: Stack(
        children: [
          // Grid lines for "high-tech" look
          ...List.generate(10, (i) => Positioned(
            left: i * (MediaQuery.of(context).size.width / 10),
            top: 0,
            bottom: 0,
            child: Container(width: 1, color: Colors.white.withValues(alpha: 0.02)),
          )),
          ...List.generate(15, (i) => Positioned(
            top: i * (MediaQuery.of(context).size.height / 15),
            left: 0,
            right: 0,
            child: Container(height: 1, color: Colors.white.withValues(alpha: 0.02)),
          )),

          // Stylized map markers
          ..._markerPositions.entries.map((e) => _buildMapMarker(e.key, e.value)),
        ],
      ),
    );
  }

  Widget _buildMapMarker(String country, Offset pos) {
    final isSelected = _selectedCountry == country;
    
    return Positioned(
      left: MediaQuery.of(context).size.width * pos.dx,
      top: MediaQuery.of(context).size.height * pos.dy,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => setState(() => _selectedCountry = country),
          child: Column(
            children: [
              Container(
                width: isSelected ? 24 : 12,
                height: isSelected ? 24 : 12,
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primaryBlue : Colors.white38,
                  shape: BoxShape.circle,
                  boxShadow: [
                    if (isSelected)
                      BoxShadow(
                        color: AppColors.primaryBlue.withValues(alpha: 0.6),
                        blurRadius: 15,
                        spreadRadius: 5,
                      ),
                  ],
                  border: Border.all(color: Colors.white, width: isSelected ? 3 : 1),
                ),
              ).animate(onPlay: (controller) => controller.repeat())
               .shimmer(duration: 2.seconds, color: Colors.white24),
              
              if (isSelected)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    country,
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.cardBackground.withValues(alpha: 0.8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          const SizedBox(width: 16),
          const Text(
            'Global Network',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionCard(VPNProvider provider) {
    // Find server for selected country
    final servers = provider.servers.where((s) => s['country'] == _selectedCountry).toList();
    final server = servers.isNotEmpty ? servers.first : null;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.cardBackground.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 40,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                server?['flag'] ?? '🏳️',
                style: const TextStyle(fontSize: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedCountry ?? 'Select a location',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
                    ),
                    Text(
                      server?['city'] ?? 'Multiple Locations',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('LATENCY', style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w800)),
                  Text(
                    '${server?['ping_ms'] ?? "--"} ms',
                    style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: ElevatedButton(
              onPressed: server != null ? () {
                provider.connect(server['id'].toString());
                Navigator.pop(context);
              } : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: const Text('CONNECT TO THIS LOCATION', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.5)),
            ),
          ),
        ],
      ),
    );
  }
}
