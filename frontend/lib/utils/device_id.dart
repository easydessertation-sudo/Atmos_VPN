import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceId {
  static const _key = 'atmos_device_id';

  /// Gets the unique persistent device ID for this installation.
  static Future<String> get() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString(_key);
    
    if (deviceId == null) {
      deviceId = _generateUuidV4();
      await prefs.setString(_key, deviceId);
    }
    
    return deviceId;
  }

  /// Generates a standard UUID v4 string
  static String _generateUuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    
    bytes[6] = (bytes[6] & 0x0F) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3F) | 0x80; // variant
    
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).toList();
    
    return '${hex.sublist(0, 4).join()}-${hex.sublist(4, 6).join()}-${hex.sublist(6, 8).join()}-${hex.sublist(8, 10).join()}-${hex.sublist(10, 16).join()}';
  }
}
