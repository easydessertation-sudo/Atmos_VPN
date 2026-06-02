package com.atmosvpn.app.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.wireguard.android.backend.GoBackend
import com.wireguard.android.backend.Statistics
import com.wireguard.android.backend.Tunnel
import com.wireguard.config.Config
import java.io.StringReader

class WireGuardVpnService : VpnService() {

    companion object {
        const val TAG = "AtmosVPN"
        const val ACTION_START = "ACTION_START"
        const val ACTION_STOP = "ACTION_STOP"
        const val EXTRA_CONFIG = "EXTRA_CONFIG"
        const val EXTRA_SERVER_NAME = "EXTRA_SERVER_NAME"
        const val NOTIFICATION_ID = 1
        const val CHANNEL_ID = "atmos_vpn_service"

        @Volatile
        var isRunning = false

        @Volatile
        var lastError: String? = null

        // GoBackend should be a singleton to prevent TUN device conflicts across service restarts
        @Volatile
        private var backend: GoBackend? = null
    }

    private var activeTunnel: Tunnel? = null
    private var currentServerName: String = "AtmosVPN Server"

    // Statistics tracking
    private val handler = Handler(Looper.getMainLooper())
    private var lastRx = 0L
    private var lastTx = 0L
    private var lastTime = 0L

    private val updateRunnable = object : Runnable {
        override fun run() {
            if (isRunning && activeTunnel != null) {
                try {
                    val stats = backend?.getStatistics(activeTunnel!!)
                    if (stats != null) {
                        updateNotificationWithStats(stats)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to get stats: ${e.message}")
                }
                handler.postDelayed(this, 1000)
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        try {
            // Must use 'this' because GoBackend requires a VpnService context to cast to VpnService
            backend = GoBackend(this)
            Log.i(TAG, "GoBackend initialized successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize GoBackend: ${e.message}", e)
            lastError = "Failed to initialize VPN engine: ${e.message}"
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                Log.i(TAG, "ACTION_START received")
                val configString = intent.getStringExtra(EXTRA_CONFIG)
                currentServerName = intent.getStringExtra(EXTRA_SERVER_NAME) ?: "AtmosVPN Server"
                
                if (configString.isNullOrBlank()) {
                    Log.e(TAG, "No config provided")
                    lastError = "No WireGuard configuration provided"
                    stopSelf()
                    return START_NOT_STICKY
                }
                startVpn(configString)
            }
            ACTION_STOP -> {
                Log.i(TAG, "ACTION_STOP received")
                stopVpn()
            }
            else -> {
                Log.w(TAG, "Unknown action: ${intent?.action}")
            }
        }
        return START_STICKY
    }

    private fun startVpn(configString: String) {
        // Run in a background thread to allow sleeping for retries without blocking the main thread
        Thread {
            try {
                startForeground(NOTIFICATION_ID, buildNotification(currentServerName, "Connecting..."))

                val config = Config.parse(StringReader(configString).buffered())
                Log.i(TAG, "Config parsed successfully")

                activeTunnel = object : Tunnel {
                    override fun getName(): String = "wg0"
                    override fun onStateChange(newState: Tunnel.State) {
                        Log.i(TAG, "Tunnel state changed: $newState")
                        isRunning = newState == Tunnel.State.UP
                        if (isRunning) {
                            lastError = null
                            lastRx = 0L
                            lastTx = 0L
                            lastTime = System.currentTimeMillis()
                            handler.post(updateRunnable)
                        } else {
                            handler.removeCallbacks(updateRunnable)
                        }
                    }
                }

                var success = false
                var retryCount = 0
                val maxRetries = 3
                var lastBackendException: com.wireguard.android.backend.BackendException? = null

                while (!success && retryCount < maxRetries) {
                    try {
                        backend?.setState(activeTunnel!!, Tunnel.State.UP, config)
                        success = true
                        isRunning = true
                        lastError = null
                        Log.i(TAG, "VPN tunnel is UP on attempt ${retryCount + 1}")
                    } catch (e: com.wireguard.android.backend.BackendException) {
                        lastBackendException = e
                        val reasonString = e.reason.toString()
                        Log.w(TAG, "BackendException on attempt ${retryCount + 1}: $reasonString")
                        
                        // If it's a race condition with the kernel TUN teardown, wait and retry
                        if (reasonString == "UNABLE_TO_START_VPN" || reasonString == "UNKNOWN_TUN") {
                            retryCount++
                            Thread.sleep(800) // Sleep 800ms before retrying
                        } else {
                            // Don't retry for other errors like VPN_NOT_AUTHORIZED
                            break
                        }
                    }
                }

                if (!success) {
                    throw lastBackendException ?: Exception("Failed to start VPN after $maxRetries attempts")
                }

            } catch (e: com.wireguard.android.backend.BackendException) {
                Log.e(TAG, "BackendException: ${e.reason}", e)
                val reasonString = e.reason.toString()
                lastError = "VPN Engine Error: $reasonString"
                isRunning = false
                stopForeground(true)
                stopSelf()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start VPN: ${e.message}", e)
                lastError = e.message ?: e.javaClass.simpleName ?: "Unknown error starting tunnel"
                isRunning = false
                stopForeground(true)
                stopSelf()
            }
        }.start()
    }

    private fun stopVpn() {
        try {
            handler.removeCallbacks(updateRunnable)
            activeTunnel?.let { tunnel ->
                backend?.setState(tunnel, Tunnel.State.DOWN, null)
                Log.i(TAG, "VPN tunnel is DOWN")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping VPN: ${e.message}", e)
        } finally {
            isRunning = false
            activeTunnel = null
            stopForeground(true)
            stopSelf()
        }
    }

    private fun updateNotificationWithStats(stats: Statistics) {
        val currentTime = System.currentTimeMillis()
        val timeDiff = (currentTime - lastTime) / 1000.0 // in seconds

        val rx = stats.totalRx()
        val tx = stats.totalTx()

        val rxSpeed = if (timeDiff > 0) ((rx - lastRx) / timeDiff).toLong() else 0L
        val txSpeed = if (timeDiff > 0) ((tx - lastTx) / timeDiff).toLong() else 0L

        lastRx = rx
        lastTx = tx
        lastTime = currentTime

        val text = "↓ ${formatSpeed(rxSpeed)} ${formatBytes(rx)} - ↑ ${formatSpeed(txSpeed)} ${formatBytes(tx)}"
        
        val nm = getSystemService(NotificationManager::class.java)
        nm?.notify(NOTIFICATION_ID, buildNotification(currentServerName, text))
    }

    private fun formatSpeed(bytesPerSec: Long): String {
        val bitsPerSec = bytesPerSec * 8
        if (bitsPerSec < 1000) return "$bitsPerSec bit/s"
        if (bitsPerSec < 1000000) return String.format("%.1f kbit/s", bitsPerSec / 1000.0)
        return String.format("%.1f Mbit/s", bitsPerSec / 1000000.0)
    }

    private fun formatBytes(bytes: Long): String {
        if (bytes < 1024) return "$bytes B"
        if (bytes < 1048576) return String.format("%.1f kB", bytes / 1024.0)
        if (bytes < 1073741824) return String.format("%.1f MB", bytes / 1048576.0)
        return String.format("%.2f GB", bytes / 1073741824.0)
    }

    private fun buildNotification(title: String, contentText: String): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "AtmosVPN Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows when AtmosVPN is protecting your connection"
                setShowBadge(false)
            }
            getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
        }

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val stopIntent = Intent(this, WireGuardVpnService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this, 1, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val stopAction = Notification.Action.Builder(
            null, "Disconnect", stopPendingIntent
        ).build()

        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .addAction(stopAction)
            .build()
    }

    override fun onRevoke() {
        Log.i(TAG, "VPN permission revoked by user")
        stopVpn()
        super.onRevoke()
    }

    override fun onDestroy() {
        Log.i(TAG, "Service destroyed")
        stopVpn()
        super.onDestroy()
    }
}
