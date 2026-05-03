import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // On Android emulator use 10.0.2.2, on physical Android use your Mac's IP (via adb reverse), on web/iOS use localhost
  // Physical Android device needs Mac's Wi-Fi IP, not localhost
  static const String _macIp = '192.168.0.3'; // Your Mac's current Wi-Fi IP

  static String get baseUrl {
    // Use 127.0.0.1 instead of localhost for web to avoid IPv6 (::1) resolution errors
    if (kIsWeb) return 'http://127.0.0.1:8080/api';
    try {
      if (Platform.isAndroid) {
        // Physical Android uses Mac's network IP (both on same Wi-Fi)
        // Emulator would use 10.0.2.2
        return 'http://$_macIp:8080/api';
      }
      if (Platform.isIOS) {
        return 'http://$_macIp:8080/api';
      }
    } catch (_) {}
    return 'http://localhost:8080/api';
  }

  static Future<String?> get _token async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  static Future<String?> get _refreshToken async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('refresh_token');
  }

  static Future<Map<String, String>> get _headers async {
    final token = await _token;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Auto-refresh access token using refresh token when a 401 is received
  static Future<http.Response> _requestWithRefresh(
    Future<http.Response> Function() request,
  ) async {
    var response = await request();
    if (response.statusCode == 401) {
      // Try refresh
      final refreshed = await _tryRefreshToken();
      if (refreshed) {
        response = await request(); // Retry with new token
      }
    }
    return response;
  }

  static Future<bool> _tryRefreshToken() async {
    try {
      final rToken = await _refreshToken;
      if (rToken == null) return false;
      final resp = await http.post(
        Uri.parse('$baseUrl/auth/refresh'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $rToken'},
      );
      final data = jsonDecode(resp.body);
      if (data['success'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('access_token', data['data']['access_token']);
        return true;
      }
    } catch (_) {}
    return false;
  }

  // --- Auth ---
  static Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    final data = jsonDecode(response.body);
    if (data['success'] == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('access_token', data['data']['access_token']);
      await prefs.setString('refresh_token', data['data']['refresh_token']);
    }
    return data;
  }

  static Future<Map<String, dynamic>> register(String email, String password, String fullName) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'full_name': fullName,
      }),
    );
    final data = jsonDecode(response.body);
    if (data['success'] == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('access_token', data['data']['access_token']);
      await prefs.setString('refresh_token', data['data']['refresh_token']);
    }
    return data;
  }

  static Future<Map<String, dynamic>> getMe() async {
    final response = await _requestWithRefresh(
      () async => http.get(Uri.parse('$baseUrl/auth/me'), headers: await _headers),
    );
    return jsonDecode(response.body);
  }

  // --- Servers ---
  static Future<List<dynamic>> getServers({String? mode, String? search}) async {
    final queryParams = <String, String>{};
    if (mode != null) queryParams['mode'] = mode;
    if (search != null) queryParams['search'] = search;
    
    final uri = Uri.parse('$baseUrl/servers').replace(queryParameters: queryParams);
    final response = await http.get(uri, headers: await _headers);
    final data = jsonDecode(response.body);
    return data['success'] == true ? data['data'] : [];
  }

  // --- VPN ---
  static Future<Map<String, dynamic>> connect(String serverId, {String mode = 'standard'}) async {
    final response = await _requestWithRefresh(
      () async => http.post(
        Uri.parse('$baseUrl/vpn/connect'),
        headers: await _headers,
        body: jsonEncode({
          'server_id': serverId,
          'mode': mode,
          'device_name': kIsWeb ? 'Web Browser' : 'Mobile Device',
        }),
      ),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> disconnect() async {
    final response = await _requestWithRefresh(
      () async => http.post(
        Uri.parse('$baseUrl/vpn/disconnect'),
        headers: await _headers,
      ),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> getStatus() async {
    final response = await _requestWithRefresh(
      () async => http.get(Uri.parse('$baseUrl/vpn/status'), headers: await _headers),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> getDevices() async {
    final response = await _requestWithRefresh(
      () async => http.get(Uri.parse('$baseUrl/devices'), headers: await _headers),
    );
    return jsonDecode(response.body);
  }

  static Future<void> removeDevice(int deviceId) async {
    await _requestWithRefresh(
      () async => http.delete(Uri.parse('$baseUrl/devices/$deviceId'), headers: await _headers),
    );
  }

  static Future<Map<String, dynamic>> getBillingHistory() async {
    final response = await _requestWithRefresh(
      () async => http.get(Uri.parse('$baseUrl/subscriptions/history'), headers: await _headers),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> cancelSubscription() async {
    final response = await _requestWithRefresh(
      () async => http.post(Uri.parse('$baseUrl/subscriptions/cancel'), headers: await _headers),
    );
    return jsonDecode(response.body);
  }

  static Future<List<dynamic>> getSessionHistory({int limit = 20}) async {
    final uri = Uri.parse('$baseUrl/vpn/history').replace(queryParameters: {'limit': '$limit'});
    final response = await _requestWithRefresh(
      () async => http.get(uri, headers: await _headers),
    );
    final data = jsonDecode(response.body);
    return data['success'] == true ? data['data'] : [];
  }
}
