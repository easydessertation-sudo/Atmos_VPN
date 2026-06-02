import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/api_service.dart';
import '../utils/device_id.dart';
import '../firebase_options.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BACKGROUND HANDLER (top-level, called when app is in background or killed)
// ─────────────────────────────────────────────────────────────────────────────
// RULES:
//  1. Must be a top-level function (not a class method) — annotated @pragma
//  2. Firebase.initializeApp() is NOT needed here; FlutterFire does it for you
//     before invoking this handler in the background isolate.
//  3. We ALWAYS show via flutter_local_notifications because:
//     - OPPO/Realme/Xiaomi phones (like CPH2613) block OS-level FCM display
//     - Data-only messages are never displayed by the OS automatically
//  4. We re-initialize FlutterLocalNotificationsPlugin every time because
//     this runs in a SEPARATE background isolate with no shared memory.
// ─────────────────────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
Future<void> notificationBackgroundHandler(RemoteMessage message) async {
  // Step 1: Initialize Firebase — required in background isolate on many devices
  // even though FlutterFire docs say it's automatic. Belt-and-suspenders.
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    print('[FCM-BG] ✅ Firebase initialized');
  } catch (e) {
    print('[FCM-BG] Firebase already initialized or error: $e');
  }

  print('[FCM-BG] Handler invoked!');
  print('[FCM-BG] notification block: ${message.notification?.title} / ${message.notification?.body}');
  print('[FCM-BG] data block: ${message.data}');

  try {
    final String title = message.notification?.title ??
        message.data['title']?.toString() ??
        'AtmosVPN';
    final String body = message.notification?.body ??
        message.data['body']?.toString() ??
        message.data['message']?.toString() ??
        '';

    print('[FCM-BG] Resolved → title="$title" body="$body"');

    if (body.isEmpty) {
      print('[FCM-BG] ⚠️ Body is empty — skipping show()');
      return;
    }

    final FlutterLocalNotificationsPlugin plugin =
        FlutterLocalNotificationsPlugin();

    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@drawable/ic_notification');
    const DarwinInitializationSettings iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await plugin.initialize(
      settings: const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (_) {},
    );
    print('[FCM-BG] Plugin initialized');

    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
          plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          'atmos_vpn_notifications',
          'AtmosVPN Notifications',
          description: 'Push notifications from AtmosVPN',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );
      print('[FCM-BG] Channel created/verified');
    }

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'atmos_vpn_notifications',
      'AtmosVPN Notifications',
      channelDescription: 'Push notifications from AtmosVPN',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@drawable/ic_notification',
      showWhen: true,
      color: Color(0xFF3B82F6),
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await plugin.show(
      id: message.hashCode.abs() % 100000,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: message.data['type']?.toString(),
    );
    print('[FCM-BG] ✅ Notification shown successfully!');
  } catch (e, stack) {
    print('[FCM-BG] ❌ ERROR: $e');
    print('[FCM-BG] Stack: $stack');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NOTIFICATION SERVICE
// ─────────────────────────────────────────────────────────────────────────────
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  // ── Static notification details ─────────────────────────────────────────
  static const AndroidNotificationDetails _androidDetails =
      AndroidNotificationDetails(
    'atmos_vpn_notifications',
    'AtmosVPN Notifications',
    channelDescription: 'Push notifications from AtmosVPN',
    importance: Importance.max,
    priority: Priority.high,
    icon: '@drawable/ic_notification',
    showWhen: true,
    color: Color(0xFF3B82F6),
  );

  static const DarwinNotificationDetails _iosDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
  );

  static const NotificationDetails _notifDetails =
      NotificationDetails(android: _androidDetails, iOS: _iosDetails);

  // ── init() — call once from main() before runApp() ──────────────────────
  static Future<void> init() async {
    // 1. Request OS permission (Android 13+)
    if (Platform.isAndroid) {
      await Permission.notification.request();
    }

    // 2. Initialize local notifications
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@drawable/ic_notification');
    const DarwinInitializationSettings iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      settings: const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (NotificationResponse details) {
        _handleNotificationTap(details.payload);
      },
      // Handle taps on notifications that launched the app from terminated state
      onDidReceiveBackgroundNotificationResponse: _onBackgroundNotificationTap,
    );

    // 3. Create Android notification channel (idempotent)
    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          'atmos_vpn_notifications',
          'AtmosVPN Notifications',
          description: 'Push notifications from AtmosVPN',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );
    }

    // 4. FCM setup (skip on desktop platforms)
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      // Show foreground notifications via local notifications (not FCM heads-up)
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: false, // We handle this manually via onMessage for full control
        badge: true,
        sound: false,
      );
      await _setupFCM();
    }
  }

  // ── FCM listeners (foreground + tap handling) ────────────────────────────
  static Future<void> _setupFCM() async {
    // Request FCM permission
    final NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      provisional: false,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      // ── Foreground messages ─────────────────────────────────────────────
      // FCM does NOT show a heads-up when the app is in the foreground.
      // We must show it manually via flutter_local_notifications.
      // Listen to the native Kotlin EventChannel for foreground messages
      const EventChannel('com.atmosvpn/fcm_events').receiveBroadcastStream().listen((dynamic event) {
        if (event is Map) {
          debugPrint("Received FCM from native broadcast: $event");
          // Here you can use a Provider/Riverpod/Bloc to update your in-app notification counter
        }
      });

      // ── Background tap (app was in background, user tapped notification) ─
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        _handleNotificationTap(message.data['type']?.toString());
      });

      // ── Killed-state tap (app was fully closed, user tapped notification) ─
      _messaging.getInitialMessage().then((RemoteMessage? message) {
        if (message != null) {
          // Delay slightly to let the navigator mount
          Future.delayed(const Duration(milliseconds: 800), () {
            _handleNotificationTap(message.data['type']?.toString());
          });
        }
      });

      // ── Token refresh ────────────────────────────────────────────────────
      _messaging.onTokenRefresh.listen((_) => registerToken());
    }
  }

  // ── Navigation on notification tap ──────────────────────────────────────
  static void _handleNotificationTap(String? type) {
    if (type == 'security') {
      navigatorKey.currentState?.pushNamed('/security');
    } else {
      navigatorKey.currentState?.pushNamed('/notifications');
    }
  }

  // Must be top-level or static for the background callback
  @pragma('vm:entry-point')
  static void _onBackgroundNotificationTap(NotificationResponse details) {
    // This fires when the user taps a flutter_local_notifications notification
    // while the app is terminated. Navigation will be handled once the app
    // fully initializes via the standard getInitialMessage() path.
  }

  // ── Token registration ───────────────────────────────────────────────────
  static Future<void> registerToken() async {
    try {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) return;

      // 1. Check for a pending token saved by Kotlin while the app was killed
      final prefs = await SharedPreferences.getInstance();
      final pendingToken = prefs.getString('fcm_token_pending');
      if (pendingToken != null && pendingToken.isNotEmpty) {
        debugPrint('Syncing pending rotated FCM token from SharedPreferences...');
        final String deviceId = await DeviceId.get();
        final String platform = Platform.isAndroid ? 'android' : 'ios';
        await ApiService.registerPushToken(pendingToken, deviceId, platform);
        await prefs.remove('fcm_token_pending');
      }

      // 2. Register current active token
      final String? token = await _messaging.getToken();
      if (token != null) {
        debugPrint('====================================');
        debugPrint('FCM PUSH TOKEN (For Firebase Console):');
        debugPrint(token);
        debugPrint('====================================');
        final String deviceId = await DeviceId.get();
        final String platform = Platform.isAndroid ? 'android' : 'ios';
        await ApiService.registerPushToken(token, deviceId, platform);
      }
    } catch (_) {}
  }

  // ── Show a local notification (callable from VPNProvider polling) ─────────
  static Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: _notifDetails,
        payload: payload,
      );
    } catch (e) {
      debugPrint('[Notifications] showNotification error: $e');
    }
  }
}
