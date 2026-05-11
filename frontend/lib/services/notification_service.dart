import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/api_service.dart';
import 'dart:io';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Handle background messages
  debugPrint("Handling a background message: ${message.messageId}");
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  static Future<void> init() async {
    // 1. Request permissions
    if (Platform.isAndroid) {
      await Permission.notification.request();
    }

    // 2. Initialize Local Notifications
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _notificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse details) {
        // Handle notification tap
      },
    );

    // 3. Initialize Firebase Messaging (FCM)
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      await _setupFCM();
    }
  }

  static Future<void> _setupFCM() async {
    // Request permission for iOS/Android
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      provisional: false,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      // Foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        RemoteNotification? notification = message.notification;
        if (notification != null) {
          showNotification(
            id: notification.hashCode.abs() % 100000,
            title: notification.title ?? '',
            body: notification.body ?? '',
          );
        }
      });

      // Background message handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // Handle token refresh
      _messaging.onTokenRefresh.listen((newToken) {
        registerToken();
      });
    }
  }

  static Future<void> registerToken() async {
    try {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) return;
      
      String? token = await _messaging.getToken();
      if (token != null) {
        debugPrint("FCM Token: $token");
        // Register token with backend
        await ApiService.registerPushToken(token);
      }
    } catch (e) {
      debugPrint("Error registering token: $e");
    }
  }

  static Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'atmos_vpn_notifications',
      'Atmos VPN Notifications',
      channelDescription: 'Main channel for Atmos VPN notifications',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      color: Color(0xFF3B82F6),
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      await _notificationsPlugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: notificationDetails,
        payload: payload,
      );
    } catch (e) {
      debugPrint('Failsafe: Prevented notification crash: $e');
    }
  }
}
