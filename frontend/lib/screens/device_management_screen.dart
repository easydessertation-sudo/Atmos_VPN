import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/design_system.dart';
import '../utils/api_service.dart';
import '../utils/device_id.dart';
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
  String? _currentDeviceId;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _currentDeviceId = await DeviceId.get();
      final resp = await ApiService.getDevices();
      
      if (resp['success'] == true) {
        setState(() {
          _devices = resp['data'] ?? [];
        });
      } else {
        setState(() {
          _error = resp['message'] ?? 'Failed to load devices';
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

  Future<void> _removeDevice(String id, bool isCurrentDevice) async {
    try {
      final res = await ApiService.removeDevice(id);
      if (res['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Device removed successfully.'),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        
        if (isCurrentDevice) {
          try {
            await ApiService.logout();
          } catch (_) {}
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('access_token');
          await prefs.remove('refresh_token');
          await prefs.remove('auth_provider');
          if (mounted) {
            Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
          }
        } else {
          await _loadDevices();
        }
      } else {
        if (mounted) {
          String rawMsg = 'Failed to remove device.';
          final msgData = res['message'];
          if (msgData is List) {
            rawMsg = msgData.map((e) {
              if (e is Map) return e['msg'] ?? e.toString();
              return e.toString();
            }).join(', ');
          } else if (msgData != null) {
            rawMsg = msgData.toString();
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(rawMsg),
              backgroundColor: AppColors.warning,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.warning,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  IconData _platformIcon(String? platform) {
    switch (platform) {
      case 'ios':
        return Icons.phone_iphone_rounded;
      case 'android':
        return Icons.phone_android_rounded;
      case 'windows':
        return Icons.desktop_windows_rounded;
      case 'mac':
        return Icons.laptop_mac_rounded;
      case 'linux':
        return Icons.computer_rounded;
      case 'router':
        return Icons.router_rounded;
      default:
        return Icons.devices_rounded;
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
        title: const Text('Device Management',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
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
                        const Icon(Icons.error_outline_rounded,
                            color: AppColors.warning, size: 48),
                        const SizedBox(height: 16),
                        Text(_error!,
                            style:
                                const TextStyle(color: AppColors.textSecondary),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 24),
                        ElevatedButton(
                            onPressed: _loadDevices,
                            child: const Text('Retry')),
                      ],
                    ),
                  )
                : _devices.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.devices_rounded,
                                color: AppColors.textSecondary
                                    .withValues(alpha: 0.5),
                                size: 64),
                            const SizedBox(height: 16),
                            const Text('No devices registered yet.',
                                style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 16)),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 20),
                        itemCount: _devices.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, i) {
                          final device = _devices[i];
                          // The device's UUID is usually returned in device_id, sometimes id.
                          final bool isCurrent = device['device_id'] == _currentDeviceId || device['id'] == _currentDeviceId;
                          return _DeviceCard(
                            device: device,
                            platformIcon: _platformIcon(device['platform']),
                            isCurrentDevice: isCurrent,
                            onRemove: () => _removeDevice(device['id'], isCurrent),
                          )
                              .animate()
                              .fadeIn(delay: Duration(milliseconds: i * 80))
                              .slideX(begin: 0.1, end: 0);
                        },
                      ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final Map<String, dynamic> device;
  final IconData platformIcon;
  final bool isCurrentDevice;
  final VoidCallback onRemove;
  const _DeviceCard(
      {required this.device,
      required this.platformIcon,
      required this.isCurrentDevice,
      required this.onRemove});

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
                Row(
                  children: [
                    Flexible(
                      child: Text(device['name'] ?? 'Unknown Device',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15)),
                    ),
                    if (isCurrentDevice) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.5)),
                        ),
                        child: const Text('THIS DEVICE', style: TextStyle(color: AppColors.primaryBlue, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text('Last seen: $lastSeenStr',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded,
                color: AppColors.warning),
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: AppColors.cardBackground,
                  title: const Text('Remove Device',
                      style: TextStyle(color: Colors.white)),
                  content: Text('Remove "${device['name']}" from your account?',
                      style: const TextStyle(color: AppColors.textSecondary)),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel')),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        onRemove();
                      },
                      child: const Text('REMOVE',
                          style: TextStyle(
                              color: AppColors.warning,
                              fontWeight: FontWeight.bold)),
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
