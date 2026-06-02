package com.atmosvpn.app

import android.app.ActivityManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * Native FCM service for reliable killed-state notifications on OPPO/Realme/Xiaomi.
 *
 * Problem: OPPO's HansManager blocks cold-starting the Dart VM when the app is
 * fully killed, so Flutter's onBackgroundMessage never fires.
 *
 * Solution: This native Kotlin service handles FCM directly. Since it runs inside
 * Google Play Services (a system-privileged process), HansManager cannot block it.
 *
 * Strategy:
 *  - App KILLED      → show notification natively here. No Dart VM needed. ✅
 *  - App BACKGROUND  → Flutter's onBackgroundMessage already works (battery fix). ✅
 *  - App FOREGROUND  → Flutter's onMessage stream handles it. ✅
 *
 * This service replaces Flutter's FlutterFirebaseMessagingService entirely
 * (see tools:node="replace" in AndroidManifest.xml).
 * For foreground/background message delivery to Dart, we use a direct broadcast
 * to the Flutter engine via the existing FCM plugin infrastructure.
 */
class AtmosVpnFirebaseService : FirebaseMessagingService() {

    companion object {
        private const val TAG = "AtmosVpnFirebase"
        private const val CHANNEL_ID   = "atmos_vpn_notifications"
        private const val CHANNEL_NAME = "AtmosVPN Notifications"
        private val BRAND_COLOR = Color.parseColor("#3B82F6")
    }

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        Log.d(TAG, "Message received natively: ${remoteMessage.data}")
        // Always show a native notification — this reliably covers all states
        // This is pure Android, so OPPO's HansManager cannot crash it trying to start Dart.
        showNativeNotification(remoteMessage)

        // Forward to Flutter via standard Broadcast (received by MainActivity)
        val intent = Intent("com.atmosvpn.app.FCM_MESSAGE")
        intent.setPackage(packageName)
        intent.putExtra("type", remoteMessage.data["type"])
        intent.putExtra("title", remoteMessage.notification?.title ?: remoteMessage.data["title"])
        intent.putExtra("body", remoteMessage.notification?.body ?: remoteMessage.data["body"] ?: remoteMessage.data["message"])
        sendBroadcast(intent)
    }

    override fun onNewToken(token: String) {
        Log.d(TAG, "FCM token rotated: $token")
        // Save to Flutter's native SharedPreferences so Dart can read it on next launch
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        prefs.edit().putString("flutter.fcm_token_pending", token).apply()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Native notification display
    // ─────────────────────────────────────────────────────────────────────────

    private fun showNativeNotification(message: RemoteMessage) {
        // Pull title — prefer notification block, fall back to data fields
        val title = message.notification?.title
            ?: message.data["title"]
            ?: "AtmosVPN"

        // Pull body — backend sends 'message' key, not 'body'
        val body = message.notification?.body
            ?: message.data["body"]
            ?: message.data["message"]  // ← backend uses 'message' not 'body'
            ?: return                    // nothing to show, bail out

        val notificationManager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // Create channel (idempotent — safe to call on every message)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Push notifications from AtmosVPN"
                enableLights(true)
                lightColor = BRAND_COLOR
                enableVibration(true)
                setShowBadge(true)
            }
            notificationManager.createNotificationChannel(channel)
        }

        // Intent that opens the app when the user taps the notification
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra("notification_type", message.data["type"] ?: "general")
        }
        
        if (launchIntent == null) {
            Log.w(TAG, "Silent drop: No launch intent found for package $packageName")
            return
        }

        val pendingIntent = PendingIntent.getActivity(
            this,
            System.currentTimeMillis().toInt(),
            launchIntent,
            PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setColor(BRAND_COLOR)
            .setContentIntent(pendingIntent)
            .build()

        notificationManager.notify(
            System.currentTimeMillis().toInt(),
            notification
        )
    }
}
