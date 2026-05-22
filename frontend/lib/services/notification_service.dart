import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/api_service.dart';
import '../utils/device_id.dart';
import 'dart:io';

@pragma('vm:entry-point')
Future<void> notificationBackgroundHandler(RemoteMessage message) async {
  try {
    String? title;
    String? body;

    if (message.notification != null) {
      title = message.notification!.title;
      body = message.notification!.body;
    } else if (message.data.containsKey('title') ||
        message.data.containsKey('body')) {
      title = message.data['title'];
      body = message.data['body'];
    }

    if (title != null && body != null) {
      final FlutterLocalNotificationsPlugin notificationsPlugin =
          FlutterLocalNotificationsPlugin();

      // Initialize settings for background isolate
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const DarwinInitializationSettings initializationSettingsIOS =
          DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const InitializationSettings initializationSettings =
          InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsIOS,
      );

      await notificationsPlugin.initialize(
        settings: initializationSettings,
        onDidReceiveNotificationResponse: (_) {},
      );

      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        'atmos_vpn_notifications',
        'AtmosVPN Notifications',
        channelDescription: 'Main channel for AtmosVPN notifications',
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

      await notificationsPlugin.show(
        id: message.hashCode.abs() % 100000,
        title: title,
        body: body,
        notificationDetails: notificationDetails,
      );
    }
  } catch (e) {}
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  static Future<void> init() async {
    // 1. Request permissions
    if (Platform.isAndroid) {
      await Permission.notification.request();
    }

    // 2. Initialize Local Notifications
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _notificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse details) {
        // Handle notification tap
      },
    );

    // Create the default Android notification channel explicitly
    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          _notificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        await androidImplementation.createNotificationChannel(
          const AndroidNotificationChannel(
            'atmos_vpn_notifications',
            'AtmosVPN Notifications',
            description: 'Main channel for AtmosVPN notifications',
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
          ),
        );
      }
    }

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
        final deviceId = await DeviceId.get();
        final platform = Platform.isAndroid ? 'android' : 'ios';
        
        // Register token with backend
        await ApiService.registerPushToken(token, deviceId, platform);
      }
    } catch (e) {}
  }

  static Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'atmos_vpn_notifications',
      'AtmosVPN Notifications',
      channelDescription: 'Main channel for AtmosVPN notifications',
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
