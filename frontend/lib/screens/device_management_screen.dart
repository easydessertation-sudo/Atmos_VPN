import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../utils/design_system.dart';
import '../utils/api_service.dart';
import '../widgets/app_container.dart';

class DeviceManagementScreen extends StatefulWidget {
  const DeviceManagementScreen({super.key});

  @override
  State<DeviceManagementScreen> createState() => _DeviceManagementScreenState();
}

class _DeviceManagementScreenState extends State<DeviceManagementScreen> {
  List<dynamic> _devices = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() { _loading = true; _error = null; });
    try {
      final resp = await ApiService.getDevices();
      if (resp['success'] == true) {
        setState(() { _devices = resp['data'] ?? []; });
      } else {
        setState(() { _error = resp['message'] ?? 'Failed to load devices'; });
      }
    } catch (e) {
      setState(() { _error = 'Cannot connect to server. Check your connection.'; });
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _removeDevice(int id) async {
    try {
      await ApiService.removeDevice(id);
      await _loadDevices();
    } catch (_) {}
  }

  IconData _platformIcon(String? platform) {
    switch (platform) {
      case 'ios': return Icons.phone_iphone_rounded;
      case 'android': return Icons.phone_android_rounded;
      case 'windows': return Icons.desktop_windows_rounded;
      case 'mac': return Icons.laptop_mac_rounded;
      case 'linux': return Icons.computer_rounded;
      case 'router': return Icons.router_rounded;
      default: return Icons.devices_rounded;
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
        title: const Text('Device Management', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            onPressed: _loadDevices,
          ),
        ],
      ),
      body: AppContainer(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline_rounded, color: AppColors.warning, size: 48),
                        const SizedBox(height: 16),
                        Text(_error!, style: const TextStyle(color: AppColors.textSecondary), textAlign: TextAlign.center),
                        const SizedBox(height: 24),
                        ElevatedButton(onPressed: _loadDevices, child: const Text('Retry')),
                      ],
                    ),
                  )
                : _devices.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.devices_rounded, color: AppColors.textSecondary.withValues(alpha: 0.5), size: 64),
                            const SizedBox(height: 16),
                            const Text('No devices registered yet.', style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                        itemCount: _devices.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, i) {
                          final device = _devices[i];
                          return _DeviceCard(
                            device: device,
                            platformIcon: _platformIcon(device['platform']),
                            onRemove: () => _removeDevice(device['id']),
                          ).animate().fadeIn(delay: Duration(milliseconds: i * 80)).slideX(begin: 0.1, end: 0);
                        },
                      ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final Map<String, dynamic> device;
  final IconData platformIcon;
  final VoidCallback onRemove;
  const _DeviceCard({required this.device, required this.platformIcon, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final lastSeen = device['last_seen'] != null
        ? DateTime.tryParse(device['last_seen'])?.toLocal()
        : null;
    final lastSeenStr = lastSeen != null
        ? '${lastSeen.day}/${lastSeen.month}/${lastSeen.year} ${lastSeen.hour}:${lastSeen.minute.toString().padLeft(2, '0')}'
        : 'Unknown';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(platformIcon, color: AppColors.primaryBlue, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device['name'] ?? 'Unknown Device',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 4),
                Text('Last seen: $lastSeenStr',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.warning),
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: AppColors.cardBackground,
                  title: const Text('Remove Device', style: TextStyle(color: Colors.white)),
                  content: Text('Remove "${device['name']}" from your account?',
                      style: const TextStyle(color: AppColors.textSecondary)),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                    TextButton(
                      onPressed: () { Navigator.pop(ctx); onRemove(); },
                      child: const Text('REMOVE', style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
