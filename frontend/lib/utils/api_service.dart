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
    // Using live ngrok URL for all platforms
    return 'https://skinny-said-unmovable.ngrok-free.dev/api';
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
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $rToken'
        },
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

  static dynamic _decodeResponse(http.Response response) {
    try {
      if (response.statusCode >= 400) {
        print(
            'API Error [${response.statusCode}] on ${response.request?.url}: ${response.body}');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        if (decoded.containsKey('detail') && !decoded.containsKey('message')) {
          decoded['message'] = decoded['detail'];
        }
      }
      return decoded;
    } catch (e) {
      print('API Decode Exception on ${response.request?.url}: $e');
      print('Response Body: ${response.body}');
      // Return a default error object so the app doesn't crash from format exception
      return {
        'success': false,
        'message':
            'Server is unreachable or returned malformed data (Error ${response.statusCode}).'
      };
    }
  }

  // --- Auth ---
  static Future<Map<String, dynamic>> login(
      String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    final data = _decodeResponse(response);
    if (data['success'] == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('access_token', data['data']['access_token']);
      await prefs.setString('refresh_token', data['data']['refresh_token']);
    }
    return data;
  }

  static Future<Map<String, dynamic>> register(
      String email, String password, String fullName) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'full_name': fullName,
      }),
    );
    final data = _decodeResponse(response);
    if (data['success'] == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('access_token', data['data']['access_token']);
      await prefs.setString('refresh_token', data['data']['refresh_token']);
    }
    return data;
  }

  static Future<Map<String, dynamic>> getMe() async {
    final response = await _requestWithRefresh(
      () async =>
          http.get(Uri.parse('$baseUrl/auth/me'), headers: await _headers),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> changePassword(
      String oldPassword, String newPassword) async {
    final response = await _requestWithRefresh(
      () async => http.post(
        Uri.parse('$baseUrl/auth/change-password'),
        headers: await _headers,
        body: jsonEncode(
            {'old_password': oldPassword, 'new_password': newPassword}),
      ),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> logout() async {
    final response = await _requestWithRefresh(
      () async => http.post(
        Uri.parse('$baseUrl/auth/logout'),
        headers: await _headers,
      ),
    );
    final data = _decodeResponse(response);
    if (data['success'] == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('access_token');
      await prefs.remove('refresh_token');
    }
    return data;
  }

  static Future<Map<String, dynamic>> forgotPassword(String email) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/forgot-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> resetPassword(
      String token, String newPassword) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/reset-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'token': token, 'new_password': newPassword}),
    );
    return _decodeResponse(response);
  }

  // --- Servers ---
  static Future<Map<String, dynamic>> getModes() async {
    final response = await _requestWithRefresh(
      () async =>
          http.get(Uri.parse('$baseUrl/modes'), headers: await _headers),
    );
    return _decodeResponse(response);
  }

  static Future<List<dynamic>> getServers(
      {String? mode, bool top = false, String? country}) async {
    final queryParams = <String, String>{};
    if (mode != null) queryParams['mode'] = mode;
    if (top) queryParams['top'] = 'true';
    if (country != null) queryParams['country'] = country;

    final uri =
        Uri.parse('$baseUrl/servers').replace(queryParameters: queryParams);
    final response = await _requestWithRefresh(
      () async => http.get(uri, headers: await _headers),
    );
    print('SERVERS API STATUS: ${response.statusCode}');
    print(
        'SERVERS API BODY: ${response.body.substring(0, response.body.length.clamp(0, 300))}');
    final data = _decodeResponse(response);
    if (data['success'] == true && data['data'] != null) {
      // API returns data as a direct list of servers
      if (data['data'] is List) {
        return data['data'];
      }
      // Fallback: data might be wrapped in a servers key
      if (data['data'] is Map && data['data']['servers'] != null) {
        return data['data']['servers'];
      }
    }
    print('SERVERS API returned no data. Full response: ${data}');
    return [];
  }

  static Future<Map<String, dynamic>> getBestServer() async {
    final response = await _requestWithRefresh(
      () async =>
          http.get(Uri.parse('$baseUrl/servers/best'), headers: await _headers),
    );
    return _decodeResponse(response);
  }

  // --- VPN ---
  static Future<Map<String, dynamic>> provisionVpn({
    String? serverId,
    required String publicKey,
    String? deviceName,
    String? platform,
    String mode = 'standard',
  }) async {
    final body = <String, dynamic>{
      'public_key': publicKey,
      'mode': mode,
    };
    if (serverId != null) body['server_id'] = serverId;
    if (deviceName != null) body['device_name'] = deviceName;
    if (platform != null) body['platform'] = platform;

    final response = await _requestWithRefresh(
      () async => http.post(
        Uri.parse('$baseUrl/vpn/provision'),
        headers: await _headers,
        body: jsonEncode(body),
      ),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> getVpnConfig(String serverId) async {
    final response = await _requestWithRefresh(
      () async => http.get(Uri.parse('$baseUrl/vpn/config/$serverId'),
          headers: await _headers),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> getVpnConfigs() async {
    final response = await _requestWithRefresh(
      () async =>
          http.get(Uri.parse('$baseUrl/vpn/configs'), headers: await _headers),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> revokeVpnConfig(String configId) async {
    final response = await _requestWithRefresh(
      () async => http.delete(Uri.parse('$baseUrl/vpn/config/$configId'),
          headers: await _headers),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> getVpnJob(String jobId) async {
    final response = await http.get(Uri.parse('$baseUrl/vpn/job/$jobId'));
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> getBandwidthUsage() async {
    final response = await _requestWithRefresh(
      () async => http.get(Uri.parse('$baseUrl/usage/bandwidth'),
          headers: await _headers),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> connect(String serverId,
      {String mode = 'standard', String protocol = 'wireguard'}) async {
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
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> disconnect() async {
    final response = await _requestWithRefresh(
      () async => http.post(
        Uri.parse('$baseUrl/vpn/disconnect'),
        headers: await _headers,
      ),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> getStatus() async {
    final response = await _requestWithRefresh(
      () async =>
          http.get(Uri.parse('$baseUrl/vpn/status'), headers: await _headers),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> getDevices() async {
    final response = await _requestWithRefresh(
      () async =>
          http.get(Uri.parse('$baseUrl/devices'), headers: await _headers),
    );
    return _decodeResponse(response);
  }

  static Future<void> removeDevice(int deviceId) async {
    await _requestWithRefresh(
      () async => http.delete(Uri.parse('$baseUrl/devices/$deviceId'),
          headers: await _headers),
    );
  }

  static Future<Map<String, dynamic>> getBillingHistory() async {
    final response = await _requestWithRefresh(
      () async => http.get(Uri.parse('$baseUrl/subscriptions/history'),
          headers: await _headers),
    );
    return _decodeResponse(response);
  }

  static Future<List<dynamic>> getSessionHistory({int limit = 20}) async {
    final uri = Uri.parse('$baseUrl/vpn/history')
        .replace(queryParameters: {'limit': '$limit'});
    final response = await _requestWithRefresh(
      () async => http.get(uri, headers: await _headers),
    );
    final data = _decodeResponse(response);
    return data['success'] == true ? data['data'] : [];
  }

  // --- Billing ---
  static Future<Map<String, dynamic>> getPlans() async {
    final response = await http.get(Uri.parse('$baseUrl/plans'));
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> getBillingStatus() async {
    final response = await _requestWithRefresh(
      () async => http.get(Uri.parse('$baseUrl/billing/status'),
          headers: await _headers),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> createCheckout(
      String plan, String billingCycle) async {
    final response = await _requestWithRefresh(
      () async => http.post(
        Uri.parse('$baseUrl/billing/checkout'),
        headers: await _headers,
        body: jsonEncode({'plan': plan, 'billing_cycle': billingCycle}),
      ),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> getBillingPortal() async {
    final response = await _requestWithRefresh(
      () async => http.post(Uri.parse('$baseUrl/billing/portal'),
          headers: await _headers),
    );
    return _decodeResponse(response);
  }

  // --- Notifications ---
  static Future<Map<String, dynamic>> getNotifications(
      {bool unreadOnly = false}) async {
    final uri = Uri.parse('$baseUrl/notifications')
        .replace(queryParameters: unreadOnly ? {'unread_only': 'true'} : {});
    final response = await _requestWithRefresh(
      () async => http.get(uri, headers: await _headers),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> markNotificationRead(String id) async {
    final response = await _requestWithRefresh(
      () async => http.patch(Uri.parse('$baseUrl/notifications/$id/read'),
          headers: await _headers),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> markAllNotificationsRead() async {
    final response = await _requestWithRefresh(
      () async => http.patch(Uri.parse('$baseUrl/notifications/read-all'),
          headers: await _headers),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> deleteNotification(String id) async {
    final response = await _requestWithRefresh(
      () async => http.delete(Uri.parse('$baseUrl/notifications/$id'),
          headers: await _headers),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> registerPushToken(String token) async {
    final response = await _requestWithRefresh(
      () async => http.post(
        Uri.parse('$baseUrl/notifications/register-token'),
        headers: await _headers,
        body: jsonEncode({
          'token': token,
          'platform': Platform.isAndroid ? 'android' : 'ios'
        }),
      ),
    );
    return _decodeResponse(response);
  }

  // --- Settings ---
  static Future<Map<String, dynamic>> getSettings() async {
    final response = await _requestWithRefresh(
      () async =>
          http.get(Uri.parse('$baseUrl/settings'), headers: await _headers),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> updateSettings(
      Map<String, dynamic> settings) async {
    final response = await _requestWithRefresh(
      () async => http.patch(
        Uri.parse('$baseUrl/settings'),
        headers: await _headers,
        body: jsonEncode(settings),
      ),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> getReferrals() async {
    final response = await _requestWithRefresh(
      () async =>
          http.get(Uri.parse('$baseUrl/referrals'), headers: await _headers),
    );
    return _decodeResponse(response);
  }

  // --- Security ---
  static Future<Map<String, dynamic>> getSecuritySettings() async {
    final response = await _requestWithRefresh(
      () async => http.get(Uri.parse('$baseUrl/security/settings'),
          headers: await _headers),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> updateSecuritySettings(
      Map<String, dynamic> settings) async {
    final response = await _requestWithRefresh(
      () async => http.patch(
        Uri.parse('$baseUrl/security/settings'),
        headers: await _headers,
        body: jsonEncode(settings),
      ),
    );
    return _decodeResponse(response);
  }

  // --- Support ---
  static Future<Map<String, dynamic>> submitSupportTicket(
      String email, String subject, String message, String category) async {
    final response = await http.post(
      Uri.parse('$baseUrl/support/ticket'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'subject': subject,
        'message': message,
        'category': category
      }),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> getFaqs() async {
    final response = await http.get(Uri.parse('$baseUrl/support/faq'));
    return _decodeResponse(response);
  }

  // --- Health & Speed ---
  static Future<Map<String, dynamic>> getApiStatus() async {
    final response = await http.get(Uri.parse('$baseUrl/status'));
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> getIp() async {
    final response = await http.get(Uri.parse('$baseUrl/ip'));
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> runSpeedTest() async {
    final response = await _requestWithRefresh(
      () async => http.post(Uri.parse('$baseUrl/speedtest/run'),
          headers: await _headers),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> googleVerify(String idToken) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/google/verify'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'id_token': idToken}),
    );
    final data = _decodeResponse(response);
    if (data['success'] == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('access_token', data['data']['access_token']);
      await prefs.setString('refresh_token', data['data']['refresh_token']);
    }
    return data;
  }

  static Future<Map<String, dynamic>> appleVerify(
      String idToken, {String? email, String? fullName}) async {
    final Map<String, dynamic> body = {'id_token': idToken};
    if (email != null && email.isNotEmpty) body['email'] = email;
    if (fullName != null && fullName.isNotEmpty) body['full_name'] = fullName;

    final response = await http.post(
      Uri.parse('$baseUrl/auth/apple/verify'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    final data = _decodeResponse(response);
    if (data['success'] == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('access_token', data['data']['access_token']);
      await prefs.setString('refresh_token', data['data']['refresh_token']);
    }
    return data;
  }

  // --- Rewards & Sessions ---
  static Future<Map<String, dynamic>> getSessionTime() async {
    final response = await _requestWithRefresh(
      () async => http.get(Uri.parse('$baseUrl/vpn/session-time'),
          headers: await _headers),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> claimAdReward() async {
    final response = await _requestWithRefresh(
      () async => http.post(Uri.parse('$baseUrl/rewards/watch-ad'),
          headers: await _headers),
    );
    return _decodeResponse(response);
  }
}
