package billion.group.wireguard_flutter


import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry

import android.app.Activity
import io.flutter.embedding.android.FlutterActivity
import android.content.Intent
import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.util.Log
import com.beust.klaxon.Klaxon
import com.wireguard.android.backend.*
import com.wireguard.crypto.Key
import com.wireguard.crypto.KeyPair
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.*
import java.util.*

import kotlinx.coroutines.launch
import java.io.ByteArrayInputStream

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.IntentFilter
import androidx.core.app.NotificationCompat
import java.util.concurrent.CompletableFuture

/** WireguardFlutterPlugin */

const val PERMISSIONS_REQUEST_CODE = 10014
const val METHOD_CHANNEL_NAME = "billion.group.wireguard_flutter/wgcontrol"
const val METHOD_EVENT_NAME = "billion.group.wireguard_flutter/wgstage"

class WireguardFlutterPlugin : FlutterPlugin, MethodCallHandler, ActivityAware,
    PluginRegistry.ActivityResultListener {
    private lateinit var channel: MethodChannel
    private lateinit var events: EventChannel
    private lateinit var tunnelName: String
    private var serverNameForNotification: String = "AtmosVPN"
    private val futureBackend = CompletableDeferred<Backend>()
    private var vpnStageSink: EventChannel.EventSink? = null
    private val scope = CoroutineScope(Job() + Dispatchers.Main.immediate)
    private var backend: Backend? = null
    private var havePermission = false
    private lateinit var context: Context
    private var activity: Activity? = null
    private var config: com.wireguard.config.Config? = null
    private var tunnel: WireGuardTunnel? = null
    private val TAG = "NVPN"
    var isVpnChecked = false

    private var disconnectReceiver: BroadcastReceiver? = null
    private var statsJob: Job? = null
    private val NOTIFICATION_ID = 1001

    private var lastRxBytes = 0L
    private var lastTxBytes = 0L
    private var lastStatsTime = 0L

    companion object {
        private var state: String = "no_connection"

        fun getStatus(): String {
            return state
        }
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        this.havePermission =
            (requestCode == PERMISSIONS_REQUEST_CODE) && (resultCode == Activity.RESULT_OK)
        return havePermission
    }

    override fun onAttachedToActivity(activityPluginBinding: ActivityPluginBinding) {
        this.activity = activityPluginBinding.activity as FlutterActivity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        this.activity = null
    }

    override fun onReattachedToActivityForConfigChanges(activityPluginBinding: ActivityPluginBinding) {
        this.activity = activityPluginBinding.activity as FlutterActivity
    }

    override fun onDetachedFromActivity() {
        this.activity = null
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, METHOD_CHANNEL_NAME)
        events = EventChannel(flutterPluginBinding.binaryMessenger, METHOD_EVENT_NAME)
        context = flutterPluginBinding.applicationContext

        createNotificationChannel()

        disconnectReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action == "DISCONNECT_VPN_ACTION") {
                    scope.launch(Dispatchers.IO) {
                        try {
                            updateStage("disconnecting")
                            stopStatsLoop() // Instantly stop the notification loop
                            futureBackend.await().setState(
                                tunnel(tunnelName) { state ->
                                    scope.launch(Dispatchers.Main) {
                                        updateStageFromState(state)
                                    }
                                }, Tunnel.State.DOWN, config
                            )
                            Log.i(TAG, "Disconnected via Notification!")
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to disconnect via Notification: \$e")
                        }
                    }
                }
            }
        }
        
        if (Build.VERSION.SDK_INT >= 33) {
            context.registerReceiver(disconnectReceiver, IntentFilter("DISCONNECT_VPN_ACTION"), 2) // RECEIVER_NOT_EXPORTED = 2
        } else {
            context.registerReceiver(disconnectReceiver, IntentFilter("DISCONNECT_VPN_ACTION"))
        }

        scope.launch(Dispatchers.IO) {
            try {
                backend = createBackend()
                futureBackend.complete(backend!!)
            } catch (e: Throwable) {
                Log.e(TAG, Log.getStackTraceString(e))
            }
        }

        channel.setMethodCallHandler(this)
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                isVpnChecked = false
                vpnStageSink = events
            }

            override fun onCancel(arguments: Any?) {
                isVpnChecked = false
                vpnStageSink = null
            }
        })

    }

    private fun createBackend(): Backend {
        if (backend == null) {
            backend = GoBackend(context)
        }
        return backend as Backend
    }

    private fun flutterSuccess(result: Result, o: Any) {
        scope.launch(Dispatchers.Main) {
            result.success(o)
        }
    }

    private fun flutterError(result: Result, error: String) {
        scope.launch(Dispatchers.Main) {
            result.error(error, null, null)
        }
    }

    private fun flutterNotImplemented(result: Result) {
        scope.launch(Dispatchers.Main) {
            result.notImplemented()
        }
    }

    override fun onMethodCall(call: MethodCall, result: Result) {

        when (call.method) {
            "initialize" -> setupTunnel(call.argument<String>("localizedDescription").toString(), result)
            "start" -> {
                val srvName = call.argument<String>("serverAddress")
                if (srvName != null && srvName.isNotEmpty()) {
                    serverNameForNotification = "AtmosVPN - $srvName"
                } else {
                    serverNameForNotification = "AtmosVPN"
                }
                connect(call.argument<String>("wgQuickConfig").toString(), result)

                if (!isVpnChecked) {
                    if (isVpnActive()) {
                        state = "connected"
                        isVpnChecked = true
                        println("VPN is active")
                    } else {
                        state = "disconnected"
                        isVpnChecked = true
                        println("VPN is not active")
                    }
                }
            }
            "stop" -> {
                disconnect(result)
            }
            "stage" -> {
                result.success(getStatus())
            }
            "checkPermission" -> {
                checkPermission()
                result.success(null)
            }
            else -> flutterNotImplemented(result)
        }
    }
    private fun isVpnActive(): Boolean {
        try {
            val connectivityManager =
                context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val activeNetwork = connectivityManager.activeNetwork
                val networkCapabilities = connectivityManager.getNetworkCapabilities(activeNetwork)
                return networkCapabilities?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true
            } else {
                return false
            }
        } catch (e: Exception) {
            Log.e(TAG, "isVpnActive - ERROR - \${e.message}")
            return false
        }
    }
    private fun updateStage(stage: String?) {
        scope.launch(Dispatchers.Main) {
            val updatedStage = stage ?: "no_connection"
            state = updatedStage
            vpnStageSink?.success(updatedStage.lowercase(Locale.ROOT))
        }
    }
    private fun updateStageFromState(state: Tunnel.State) {
        scope.launch(Dispatchers.Main) {
            when (state) {
                Tunnel.State.UP -> {
                    updateStage("connected")
                    startStatsLoop()
                }
                Tunnel.State.DOWN -> {
                    updateStage("disconnected")
                    stopStatsLoop()
                }
                else -> updateStage("wait_connection")
            }
        }
    }
    private fun disconnect(result: Result) {
        scope.launch(Dispatchers.IO) {
            try {
                if (futureBackend.await().runningTunnelNames.isEmpty()) {
                    updateStage("disconnected")
                    throw Exception("Tunnel is not running")
                }
                updateStage("disconnecting")
                futureBackend.await().setState(
                    tunnel(tunnelName) { state ->
                        scope.launch(Dispatchers.Main) {
                            Log.i(TAG, "onStateChange - \$state")
                            updateStageFromState(state)
                        }
                    }, Tunnel.State.DOWN, config
                )
                Log.i(TAG, "Disconnect - success!")
                flutterSuccess(result, "")
            } catch (e: BackendException) {
                Log.e(TAG, "Disconnect - BackendException - ERROR - \${e.reason}", e)
                flutterError(result, e.reason.toString())
            } catch (e: Throwable) {
                Log.e(TAG, "Disconnect - Can't disconnect from tunnel: \${e.message}")
                flutterError(result, e.message.toString())
            }
        }
    }

    private fun connect(wgQuickConfig: String, result: Result) {
        scope.launch(Dispatchers.IO) {
            try {
                if (!havePermission) {
                    checkPermission()
                    throw Exception("Permissions are not given")
                }
                updateStage("prepare")
                val inputStream = ByteArrayInputStream(wgQuickConfig.toByteArray())
                config = com.wireguard.config.Config.parse(inputStream)
                updateStage("connecting")
                futureBackend.await().setState(
                    tunnel(tunnelName) { state ->
                        scope.launch(Dispatchers.Main) {
                            Log.i(TAG, "onStateChange - \$state")
                            updateStageFromState(state)
                        }
                    }, Tunnel.State.UP, config
                )
                Log.i(TAG, "Connect - success!")
                flutterSuccess(result, "")
            } catch (e: BackendException) {
                Log.e(TAG, "Connect - BackendException - ERROR - \${e.reason}", e)
                flutterError(result, e.reason.toString())
            } catch (e: Throwable) {
                Log.e(TAG, "Connect - Can't connect to tunnel: \$e", e)
                flutterError(result, e.message.toString())
            }
        }
    }

    private fun setupTunnel(localizedDescription: String, result: Result) {
        scope.launch(Dispatchers.IO) {
            if (Tunnel.isNameInvalid(localizedDescription)) {
                flutterError(result, "Invalid Name")
                return@launch
            }
            tunnelName = localizedDescription
            checkPermission()
            result.success(null)
        }
    }

    private fun checkPermission() {
        val intent = GoBackend.VpnService.prepare(this.activity)
        if (intent != null) {
            havePermission = false
            this.activity?.startActivityForResult(intent, PERMISSIONS_REQUEST_CODE)
        } else {
            havePermission = true
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        events.setStreamHandler(null)
        isVpnChecked = false
        disconnectReceiver?.let {
            try {
                context.unregisterReceiver(it)
            } catch (e: Exception) {}
        }
    }

    private fun tunnel(name: String, callback: StateChangeCallback? = null): WireGuardTunnel {
        if (tunnel == null) {
            tunnel = WireGuardTunnel(name, callback)
        }
        return tunnel as WireGuardTunnel
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "vpn_stats_channel",
                "VPN Status",
                NotificationManager.IMPORTANCE_LOW
            )
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    private var isFirstNotification = true

    private fun startStatsLoop() {
        statsJob?.cancel()
        lastStatsTime = System.currentTimeMillis()
        lastRxBytes = 0L
        lastTxBytes = 0L
        isFirstNotification = true
        updateNotification("Connected") // Initial state

        statsJob = scope.launch(Dispatchers.IO) {
            while (isActive) {
                try {
                    val tunnelInstance = tunnel
                    if (tunnelInstance != null && backend != null) {
                        val stats = backend!!.getStatistics(tunnelInstance)
                        var rxBytes = stats.totalRx()
                        var txBytes = stats.totalTx()

                        val currentTime = System.currentTimeMillis()
                        val timeDiff = currentTime - lastStatsTime

                        var rxSpeed = 0L
                        var txSpeed = 0L

                        if (timeDiff > 0) {
                            rxSpeed = ((rxBytes - lastRxBytes) * 1000 / timeDiff)
                            txSpeed = ((txBytes - lastTxBytes) * 1000 / timeDiff)
                        }

                        lastRxBytes = rxBytes
                        lastTxBytes = txBytes
                        lastStatsTime = currentTime

                        val text = "↓ ${formatSpeed(rxSpeed)} ${formatBytes(rxBytes)} - ↑ ${formatSpeed(txSpeed)} ${formatBytes(txBytes)}"
                        updateNotification(text)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Stats error: \$e")
                }
                delay(1000)
            }
        }
    }

    private fun stopStatsLoop() {
        statsJob?.cancel()
        statsJob = null
        try {
            val goBackendClass = GoBackend::class.java
            val vpnServiceField = goBackendClass.getDeclaredField("vpnService")
            vpnServiceField.isAccessible = true
            val future = vpnServiceField.get(null) as? CompletableFuture<*>
            // Use getNow(null) instead of get() to avoid blocking the calling thread.
            // future.get() is a blocking call that freezes the UI thread and causes ANR.
            val vpnServiceInstance = future?.getNow(null) as? android.app.Service
            if (vpnServiceInstance != null) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    vpnServiceInstance.stopForeground(android.app.Service.STOP_FOREGROUND_REMOVE)
                } else {
                    @Suppress("DEPRECATION")
                    vpnServiceInstance.stopForeground(true)
                }
            }
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.cancel(NOTIFICATION_ID)
        } catch (e: Exception) {}
    }

    private fun formatBytes(bytes: Long): String {
        if (bytes < 1024) return "$bytes B"
        val kb = bytes / 1024.0
        if (kb < 1024) return String.format(Locale.US, "%.1f KB", kb)
        val mb = kb / 1024.0
        if (mb < 1024) return String.format(Locale.US, "%.1f MB", mb)
        val gb = mb / 1024.0
        return String.format(Locale.US, "%.2f GB", gb)
    }

    private fun formatSpeed(bytesPerSec: Long): String {
        val bitsPerSec = bytesPerSec * 8
        if (bitsPerSec < 1000) return "$bitsPerSec bit/s"
        val kbps = bitsPerSec / 1000.0
        if (kbps < 1000) return String.format(Locale.US, "%.1f kbit/s", kbps)
        val mbps = kbps / 1000.0
        return String.format(Locale.US, "%.1f Mbit/s", mbps)
    }

    private fun updateNotification(text: String) {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        
        val disconnectIntent = Intent("DISCONNECT_VPN_ACTION")
        disconnectIntent.setPackage(context.packageName)
        val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val disconnectPendingIntent = PendingIntent.getBroadcast(context, 0, disconnectIntent, pendingIntentFlags)
        
        val builder = NotificationCompat.Builder(context, "vpn_stats_channel")
            .setContentTitle(serverNameForNotification)
            .setContentText(text)
            .setSmallIcon(context.resources.getIdentifier("ic_launcher", "mipmap", context.packageName))
            .setOngoing(true)
            .addAction(0, "Disconnect", disconnectPendingIntent)
            
        val packageManager = context.packageManager
        val launchIntent = packageManager.getLaunchIntentForPackage(context.packageName)
        if (launchIntent != null) {
            val contentIntent = PendingIntent.getActivity(context, 0, launchIntent, pendingIntentFlags)
            builder.setContentIntent(contentIntent)
        }

        val notification = builder.build()

        try {
            val goBackendClass = GoBackend::class.java
            val vpnServiceField = goBackendClass.getDeclaredField("vpnService")
            vpnServiceField.isAccessible = true
            val future = vpnServiceField.get(null) as? CompletableFuture<*>
            // Use getNow(null) instead of get() to avoid blocking the calling thread.
            val vpnServiceInstance = future?.getNow(null) as? android.net.VpnService
            if (vpnServiceInstance != null && isFirstNotification) {
                vpnServiceInstance.startForeground(NOTIFICATION_ID, notification)
                isFirstNotification = false
            } else {
                notificationManager.notify(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            notificationManager.notify(NOTIFICATION_ID, notification)
        }
    }
}

typealias StateChangeCallback = (Tunnel.State) -> Unit

class WireGuardTunnel(
    private val name: String, private val onStateChanged: StateChangeCallback? = null
) : Tunnel {

    override fun getName() = name

    override fun onStateChange(newState: Tunnel.State) {
        onStateChanged?.invoke(newState)
    }

}
