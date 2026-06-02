import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';

/// VpnService — the Dart side of the MethodChannel "speaking tube"
/// that talks to the native Android/iOS VPN engine.
///
/// This replaces the wireguard_flutter plugin with a custom implementation
/// that supports Kill Switch.
class VpnService {
  static const _channel = MethodChannel('com.atmosvpn/vpn');

  /// Start the VPN tunnel with the given WireGuard config string.
  ///
  /// On Android, this will trigger the system VPN permission dialog
  /// if the user has not already granted it.
  ///
  /// Returns `true` if the service was started successfully.
  /// Throws on failure.
  static Future<bool> connect(String wireguardConfig, {String serverName = "AtmosVPN", bool killSwitch = false}) async {
    if (kIsWeb) return false; // VPN not supported on web

    try {
      final result = await _channel.invokeMethod<bool>(
        'connect',
        {
          'config': wireguardConfig,
          'serverName': serverName,
          'killSwitch': killSwitch,
        },
      );
      return result ?? false;
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_DENIED') {
        throw Exception('VPN permission denied by user.');
      }
      throw Exception('Failed to connect VPN: ${e.message}');
    }
  }

  /// Stop the VPN tunnel.
  ///
  /// Returns `true` if the stop command was sent successfully.
  static Future<void> disconnect() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        await _channel.invokeMethod('disconnect');
      } else {
        // Fallback for Windows/macOS/Linux
      }
    } on PlatformException catch (e) {
      debugPrint("Failed to disconnect VPN: '${e.message}'.");
    }
  }

  static Future<void> openVpnSettings() async {
    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod('openVpnSettings');
      }
    } on PlatformException catch (e) {
      debugPrint("Failed to open VPN settings: '${e.message}'.");
    }
  }

  /// Check if the VPN tunnel is currently active.
  ///
  /// This queries the native service's static `isRunning` flag.
  static Future<bool> isConnected() async {
    if (kIsWeb) return false;

    try {
      final result = await _channel.invokeMethod<bool>('isConnected');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Get the last error message from the native VPN service, if any.
  static Future<String?> getError() async {
    if (kIsWeb) return null;

    try {
      final result = await _channel.invokeMethod<String?>('getError');
      return result;
    } on PlatformException {
      return null;
    }
  }
}
