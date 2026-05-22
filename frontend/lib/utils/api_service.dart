import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'device_id.dart';

class ApiService {
  /// Production backend — all routes are under /api/
  static const String baseUrl = 'https://api.atmosvpn.com';
  static const String _api = '$baseUrl/api';

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
        Uri.parse('$_api/auth/refresh'),
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
      }
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        if (decoded.containsKey('detail') && !decoded.containsKey('message')) {
          decoded['message'] = decoded['detail'];
        }
        if (decoded.containsKey('status') && !decoded.containsKey('success')) {
          decoded['success'] = decoded['status'] == 'success';
        }
        if (decoded.containsKey('msg') && !decoded.containsKey('message')) {
          decoded['message'] = decoded['msg'];
        }
      }
      return decoded;
    } catch (e) {
      return {
        'success': false,
        'message':
            'Server is unreachable or returned malformed data (Error ${response.statusCode}).'
      };
    }
  }

  // ─── Auth ────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> login(
      String email, String password) async {
    final response = await http.post(
      Uri.parse('$_api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    final data = _decodeResponse(response);
    if (data['success'] == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('access_token', data['data']['access_token']);
      await prefs.setString('refresh_token', data['data']['refresh_token']);
      await prefs.setString('auth_provider', 'email');
    }
    return data;
  }

  static Future<Map<String, dynamic>> register(
      String email, String password, String fullName) async {
    final response = await http.post(
      Uri.parse('$_api/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'full_name': fullName,
      }),
    );
    // NOTE: register does NOT return tokens — only requires_verification: true.
    // Tokens are returned by verifyEmail() after the 6-digit code is confirmed.
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> verifyEmail(
      String email, String code) async {
    final response = await http.post(
      Uri.parse('$_api/auth/verify-email'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'code': code}),
    );
    final data = _decodeResponse(response);
    if (data['success'] == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('access_token', data['data']['access_token']);
      await prefs.setString('refresh_token', data['data']['refresh_token']);
      await prefs.setString('auth_provider', 'email');
    }
    return data;
  }

  static Future<Map<String, dynamic>> resendVerification(
      String email) async {
    final response = await http.post(
      Uri.parse('$_api/auth/resend-verification'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> getMe() async {
    final response = await _requestWithRefresh(
      () async =>
          http.get(Uri.parse('$_api/auth/me'), headers: await _headers),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> changePassword(
      String oldPassword, String newPassword) async {
    final response = await _requestWithRefresh(
      () async => http.post(
        Uri.parse('$_api/auth/change-password'),
        headers: await _headers,
        body: jsonEncode(
            {'old_password': oldPassword, 'new_password': newPassword}),
      ),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> logout() async {
    try {
      final deviceId = await DeviceId.get();
      await removePushToken(deviceId: deviceId);
    } catch (_) {}

    final response = await _requestWithRefresh(
      () async => http.post(
        Uri.parse('$_api/auth/logout'),
        headers: await _headers,
      ),
    );
    final data = _decodeResponse(response);
    // Always clear tokens locally regardless of server response
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    await prefs.remove('auth_provider');
    return data;
  }

  static Future<Map<String, dynamic>> forgotPassword(String email) async {
    final response = await http.post(
      Uri.parse('$_api/auth/forgot-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> resetPassword(
      String token, String newPassword) async {
    final response = await http.post(
      Uri.parse('$_api/auth/reset-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'token': token, 'new_password': newPassword}),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> googleVerify(String idToken) async {
    final response = await http.post(
      Uri.parse('$_api/auth/google/verify'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'id_token': idToken}),
    );
    final data = _decodeResponse(response);
    if (data['success'] == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('access_token', data['data']['access_token']);
      await prefs.setString('refresh_token', data['data']['refresh_token']);
      await prefs.setString('auth_provider', 'google');
    }
    return data;
  }

  static Future<Map<String, dynamic>> appleVerify(
      String idToken, {String? email, String? fullName}) async {
    final Map<String, dynamic> body = {'id_token': idToken};
    if (email != null && email.isNotEmpty) body['email'] = email;
    if (fullName != null && fullName.isNotEmpty) body['full_name'] = fullName;

    final response = await http.post(
      Uri.parse('$_api/auth/apple/verify'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    final data = _decodeResponse(response);
    if (data['success'] == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('access_token', data['data']['access_token']);
      await prefs.setString('refresh_token', data['data']['refresh_token']);
      await prefs.setString('auth_provider', 'apple');
    }
    return data;
  }

  static Future<Map<String, dynamic>> updateProfile({String? fullName, String? avatarPath}) async {
    final token = await _token;
    final request = http.MultipartRequest('PUT', Uri.parse('$_api/auth/profile'));
    if (token != null) request.headers['Authorization'] = 'Bearer $token';

    if (fullName != null && fullName.isNotEmpty) {
      request.fields['full_name'] = fullName;
    }

    if (avatarPath != null && avatarPath.isNotEmpty) {
      request.files.add(await http.MultipartFile.fromPath('avatar', avatarPath));
    }

    try {
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      return _decodeResponse(response);
    } catch (e) {
      return {'success': false, 'message': 'Network error occurred while updating profile.'};
    }
  }

  // ─── Servers ─────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getModes() async {
    final response = await _requestWithRefresh(
      () async =>
          http.get(Uri.parse('$_api/modes'), headers: await _headers),
    );
    return _decodeResponse(response);
  }

  static Future<List<dynamic>> getServers(
      {String? mode, bool top = false, String? country}) async {
    final queryParams = <String, String>{};
    if (mode != null) queryParams['mode'] = mode;
    if (top) queryParams['top'] = 'true';
    if (country != null) queryParams['search'] = country; // API uses 'search'

    final uri =
        Uri.parse('$_api/servers').replace(queryParameters: queryParams);
    final response = await _requestWithRefresh(
      () async => http.get(uri, headers: await _headers),
    );
    final data = _decodeResponse(response);
    if (data['success'] == true && data['data'] != null) {
      if (data['data'] is List) {
        return data['data'];
      }
      if (data['data'] is Map && data['data']['servers'] != null) {
        return data['data']['servers'];
      }
    }
    return [];
  }

  static Future<Map<String, dynamic>> getBestServer({String mode = 'standard'}) async {
    final uri = Uri.parse('$_api/servers/best')
        .replace(queryParameters: {'mode': mode});
    final response = await _requestWithRefresh(
      () async => http.get(uri, headers: await _headers),
    );
    return _decodeResponse(response);
  }

  // ─── VPN ─────────────────────────────────────────────────────────────────

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
        Uri.parse('$_api/vpn/provision'),
        headers: await _headers,
        body: jsonEncode(body),
      ),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> getVpnConfig(String serverId) async {
    final response = await _requestWithRefresh(
      () async => http.get(Uri.parse('$_api/vpn/config/$serverId'),
          headers: await _headers),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> getVpnConfigs() async {
    final response = await _requestWithRefresh(
      () async =>
          http.get(Uri.parse('$_api/vpn/configs'), headers: await _headers),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> revokeVpnConfig(String configId) async {
    final response = await _requestWithRefresh(
      () async => http.delete(Uri.parse('$_api/vpn/config/$configId'),
          headers: await _headers),
    );
    return _decodeResponse(response);
  }

  /// Poll this after provision to check if the WireGuard peer is ready.
  /// Status: pending | running | completed | retrying | failed
  static Future<Map<String, dynamic>> getVpnJob(String jobId) async {
    final response = await http.get(Uri.parse('$_api/vpn/job/$jobId'));
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> getBandwidthUsage() async {
    final response = await _requestWithRefresh(
      () async => http.get(Uri.parse('$_api/usage/bandwidth'),
          headers: await _headers),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> connect(String serverId,
      {String mode = 'standard', String protocol = 'wireguard'}) async {
    final response = await _requestWithRefresh(
      () async => http.post(
        Uri.parse('$_api/vpn/connect'),
        headers: await _headers,
        body: jsonEncode({
          'server_id': serverId,
          'mode': mode,
          'protocol': protocol,
          'device_name': kIsWeb ? 'Web Browser' : 'Mobile Device',
        }),
      ),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> disconnect() async {
    final response = await _requestWithRefresh(
      () async => http.post(
        Uri.parse('$_api/vpn/disconnect'),
        headers: await _headers,
      ),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> getStatus() async {
    final response = await _requestWithRefresh(
      () async =>
          http.get(Uri.parse('$_api/vpn/status'), headers: await _headers),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> getSessionTime() async {
    final response = await _requestWithRefresh(
      () async => http.get(Uri.parse('$_api/vpn/session-time'),
          headers: await _headers),
    );
    return _decodeResponse(response);
  }

  static Future<List<dynamic>> getSessionHistory({int limit = 20}) async {
    final uri = Uri.parse('$_api/vpn/history')
        .replace(queryParameters: {'limit': '$limit'});
    final response = await _requestWithRefresh(
      () async => http.get(uri, headers: await _headers),
    );
    final data = _decodeResponse(response);
    return data['success'] == true ? data['data'] : [];
  }

  // ─── Devices ─────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getDevices() async {
    final response = await _requestWithRefresh(
      () async =>
          http.get(Uri.parse('$_api/devices'), headers: await _headers),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> removeDevice(String deviceId) async {
    final response = await _requestWithRefresh(
      () async => http.delete(Uri.parse('$_api/devices/$deviceId'),
          headers: await _headers),
    );
    return _decodeResponse(response);
  }

  // ─── Billing ─────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getPlans() async {
    final response = await http.get(Uri.parse('$_api/plans'));
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> getBillingStatus() async {
    final response = await _requestWithRefresh(
      () async => http.get(Uri.parse('$_api/billing/status'),
          headers: await _headers),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> createCheckout(
      String plan, String billingCycle) async {
    final response = await _requestWithRefresh(
      () async => http.post(
        Uri.parse('$_api/billing/checkout'),
        headers: await _headers,
        body: jsonEncode({'plan': plan, 'billing_cycle': billingCycle}),
      ),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> getBillingPortal() async {
    final response = await _requestWithRefresh(
      () async => http.post(Uri.parse('$_api/billing/portal'),
          headers: await _headers),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> getBillingHistory() async {
    final response = await _requestWithRefresh(
      () async => http.get(Uri.parse('$_api/subscriptions/history'),
          headers: await _headers),
    );
    return _decodeResponse(response);
  }

  // ─── Notifications ────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getNotifications(
      {bool unreadOnly = false, int page = 1, int limit = 20}) async {
    final queryParams = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
    };
    if (unreadOnly) queryParams['unread_only'] = 'true';
        
    final uri = Uri.parse('$_api/notifications')
        .replace(queryParameters: queryParams);
    final response = await _requestWithRefresh(
      () async => http.get(uri, headers: await _headers),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> markNotificationRead(String id) async {
    final response = await _requestWithRefresh(
      () async => http.patch(Uri.parse('$_api/notifications/$id/read'),
          headers: await _headers),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> markAllNotificationsRead() async {
    final response = await _requestWithRefresh(
      () async => http.patch(Uri.parse('$_api/notifications/read-all'),
          headers: await _headers),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> deleteNotification(String id) async {
    final response = await _requestWithRefresh(
      () async => http.delete(Uri.parse('$_api/notifications/$id'),
          headers: await _headers),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> registerPushToken(String fcmToken, String deviceId, String platform) async {
    final response = await _requestWithRefresh(
      () async => http.post(
        Uri.parse('$_api/users/fcm-token'),
        headers: await _headers,
        body: jsonEncode({
          'fcm_token': fcmToken,
          'device_id': deviceId,
          'platform': platform
        }),
      ),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> removePushToken({String? deviceId, String? fcmToken}) async {
    final queryParams = <String, String>{};
    if (deviceId != null) queryParams['device_id'] = deviceId;
    if (fcmToken != null) queryParams['fcm_token'] = fcmToken;
    
    final uri = Uri.parse('$_api/users/fcm-token').replace(queryParameters: queryParams);
    final response = await _requestWithRefresh(
      () async => http.delete(uri, headers: await _headers),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> triggerTestNotification() async {
    final response = await _requestWithRefresh(
      () async => http.post(Uri.parse('$_api/test/notifications/trigger'),
          headers: await _headers),
    );
    return _decodeResponse(response);
  }

  // ─── Settings ────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getSettings() async {
    final response = await _requestWithRefresh(
      () async =>
          http.get(Uri.parse('$_api/settings'), headers: await _headers),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> updateSettings(
      Map<String, dynamic> settings) async {
    final response = await _requestWithRefresh(
      () async => http.patch(
        Uri.parse('$_api/settings'),
        headers: await _headers,
        body: jsonEncode(settings),
      ),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> getReferrals() async {
    final response = await _requestWithRefresh(
      () async =>
          http.get(Uri.parse('$_api/referrals'), headers: await _headers),
    );
    return _decodeResponse(response);
  }

  // ─── Security ────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getSecuritySettings() async {
    final response = await _requestWithRefresh(
      () async => http.get(Uri.parse('$_api/security/settings'),
          headers: await _headers),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> updateSecuritySettings(
      Map<String, dynamic> settings) async {
    final response = await _requestWithRefresh(
      () async => http.patch(
        Uri.parse('$_api/security/settings'),
        headers: await _headers,
        body: jsonEncode(settings),
      ),
    );
    return _decodeResponse(response);
  }

  // ─── Support ─────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> submitSupportTicket(
      String email, String subject, String message, String category) async {
    final response = await http.post(
      Uri.parse('$_api/support/ticket'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': email.split('@').first, // derive name from email
        'email': email,
        'subject': category,
        'message': message,
      }),
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> getFaqs() async {
    final response = await http.get(Uri.parse('$_api/support/faq'));
    return _decodeResponse(response);
  }

  // ─── Health & Speed ───────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getApiStatus() async {
    final response = await http.get(Uri.parse('$_api/status'));
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> getIp() async {
    final response = await http.get(Uri.parse('$_api/ip'));
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> runSpeedTest() async {
    final response = await _requestWithRefresh(
      () async => http.post(Uri.parse('$_api/speedtest/run'),
          headers: await _headers),
    );
    return _decodeResponse(response);
  }

  // ─── Rewards ─────────────────────────────────────────────────────────────

  /// Old reward endpoint — kept for backward compat
  static Future<Map<String, dynamic>> claimAdReward() async {
    final response = await _requestWithRefresh(
      () async => http.post(Uri.parse('$_api/rewards/watch-ad'),
          headers: await _headers),
    );
    return _decodeResponse(response);
  }

  // ─── Ads (New) ───────────────────────────────────────────────────────────

  /// Check if an ad is ready to show (for the home screen banner).
  static Future<Map<String, dynamic>> getAdStatus() async {
    final response = await _requestWithRefresh(
      () async =>
          http.get(Uri.parse('$_api/ads/status'), headers: await _headers),
    );
    return _decodeResponse(response);
  }

  /// Get the current ad creative (title, image_url, video_url, reward_minutes).
  static Future<Map<String, dynamic>> getCurrentAd() async {
    final response = await _requestWithRefresh(
      () async =>
          http.get(Uri.parse('$_api/ads/current'), headers: await _headers),
    );
    return _decodeResponse(response);
  }

  /// Record that the user watched an ad — credits reward minutes.
  static Future<Map<String, dynamic>> recordAdWatch(String adId) async {
    final response = await _requestWithRefresh(
      () async => http.post(Uri.parse('$_api/ads/$adId/watch'),
          headers: await _headers),
    );
    return _decodeResponse(response);
  }
}
