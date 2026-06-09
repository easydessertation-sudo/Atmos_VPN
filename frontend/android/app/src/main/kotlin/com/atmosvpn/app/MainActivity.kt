package com.atmosvpn.app

import android.content.Intent
import android.net.VpnService
import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter
import android.os.Build
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import com.atmosvpn.app.vpn.WireGuardVpnService

/**
 * MainActivity — bridges Flutter ↔ Native VPN via MethodChannel.
 *
 * Handles three commands from Flutter:
 *   - "connect"     → requests VPN permission, then starts WireGuardVpnService
 *   - "disconnect"  → stops WireGuardVpnService
 *   - "isConnected" → returns WireGuardVpnService.isRunning
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.atmosvpn/vpn"
        private const val FCM_EVENTS_CHANNEL = "com.atmosvpn/fcm_events"
        private const val VPN_PERMISSION_REQUEST = 100
    }

    private var pendingResult: MethodChannel.Result? = null
    private var pendingConfig: String? = null
    private var pendingServerName: String? = null
    private var fcmEventSink: EventChannel.EventSink? = null

    private val fcmReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == "com.atmosvpn.app.FCM_MESSAGE") {
                val data = mapOf(
                    "type" to intent.getStringExtra("type"),
                    "title" to intent.getStringExtra("title"),
                    "body" to intent.getStringExtra("body")
                )
                fcmEventSink?.success(data)
            }
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Register receiver for background FCM intents
        val filter = IntentFilter("com.atmosvpn.app.FCM_MESSAGE")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(fcmReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(fcmReceiver, filter)
        }

        // Setup EventChannel to forward FCM payloads to Dart
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, FCM_EVENTS_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    fcmEventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    fcmEventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "connect" -> {
                        val config = call.argument<String>("config")
                        val serverName = call.argument<String>("serverName") ?: "AtmosVPN"
                        if (config.isNullOrBlank()) {
                            result.error("INVALID_CONFIG", "WireGuard config is empty", null)
                            return@setMethodCallHandler
                        }
                        connectVpn(config, serverName, result)
                    }
                    "disconnect" -> {
                        disconnectVpn(result)
                    }
                    "isConnected" -> {
                        var isVpnUp = false
                        try {
                            val stateFile = java.io.File(filesDir, "vpn_state.txt")
                            if (stateFile.exists()) {
                                isVpnUp = stateFile.readText().trim() == "true"
                            }
                        } catch (e: Exception) {}
                        
                        // Fallback static variable check (only works if in same process, but harmless)
                        if (!isVpnUp) {
                            isVpnUp = WireGuardVpnService.isRunning
                        }
                        
                        result.success(isVpnUp)
                    }
                    "getError" -> {
                        result.success(WireGuardVpnService.lastError)
                    }
                    "openVpnSettings" -> {
                        try {
                            val intent = Intent("android.settings.VPN_SETTINGS")
                            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("UNAVAILABLE", "VPN Settings not available", null)
                        }
                    }
                    else -> {
                        result.notImplemented()
                    }
                }
            }
    }

    /**
     * Request VPN permission if needed, then start the VPN service.
     */
    private fun connectVpn(config: String, serverName: String, result: MethodChannel.Result) {
        // VpnService.prepare() returns null if permission is already granted,
        // or an Intent to show the system VPN permission dialog.
        val prepareIntent = VpnService.prepare(this)

        if (prepareIntent != null) {
            // Need to ask the user for VPN permission
            pendingResult = result
            pendingConfig = config
            pendingServerName = serverName
            startActivityForResult(prepareIntent, VPN_PERMISSION_REQUEST)
        } else {
            // Permission already granted — start immediately
            startVpnService(config, serverName, result)
        }
    }

    /**
     * Handle the result from the VPN permission dialog.
     */
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode == VPN_PERMISSION_REQUEST) {
            val result = pendingResult
            val config = pendingConfig
            val serverName = pendingServerName ?: "AtmosVPN"

            // Clear pending state immediately to prevent double-use
            pendingResult = null
            pendingConfig = null
            pendingServerName = null

            if (resultCode == RESULT_OK && result != null && config != null) {
                startVpnService(config, serverName, result)
            } else {
                result?.error(
                    "PERMISSION_DENIED",
                    "VPN permission was denied by the user",
                    null
                )
            }
        }
    }

    /**
     * Actually start the foreground VPN service with the given config.
     */
    private fun startVpnService(config: String, serverName: String, result: MethodChannel.Result) {
        try {
            val intent = Intent(this, WireGuardVpnService::class.java).apply {
                action = WireGuardVpnService.ACTION_START
                putExtra(WireGuardVpnService.EXTRA_CONFIG, config)
                putExtra(WireGuardVpnService.EXTRA_SERVER_NAME, serverName)
            }
            startForegroundService(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("START_FAILED", "Failed to start VPN service: ${e.message}", null)
        }
    }

    /**
     * Stop the VPN service.
     */
    private fun disconnectVpn(result: MethodChannel.Result) {
        try {
            val intent = Intent(this, WireGuardVpnService::class.java).apply {
                action = WireGuardVpnService.ACTION_STOP
            }
            startService(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("STOP_FAILED", "Failed to stop VPN service: ${e.message}", null)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            unregisterReceiver(fcmReceiver)
        } catch (e: Exception) {}
    }
}
