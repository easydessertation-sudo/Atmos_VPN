package com.atmosvpn.app

import io.flutter.app.FlutterApplication
import android.content.Context
import android.os.Process
import android.app.ActivityManager

class MainApplication : FlutterApplication() {
    override fun onCreate() {
        if (isVpnProcess()) {
            // Do NOT initialize Flutter in the background VPN process!
            // This prevents the Native Engine from crashing when Android starts the VPN service.
            return
        }
        super.onCreate()
    }

    private fun isVpnProcess(): Boolean {
        try {
            val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val myPid = Process.myPid()
            for (processInfo in am.runningAppProcesses ?: emptyList()) {
                if (processInfo.pid == myPid && processInfo.processName.endsWith(":vpn")) {
                    return true
                }
            }
        } catch (e: Exception) {
            // Ignore
        }
        return false
    }
}
