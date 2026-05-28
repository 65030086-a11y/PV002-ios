package com.example.app_power_view

import android.content.Intent
import android.net.wifi.WifiManager
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val multicastChannelName    = "com.example.app_power_view/multicast_lock"
    private val wifiSettingsChannelName = "com.example.app_power_view/wifi_settings"
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── Multicast lock (used by UDP discovery scanner) ───────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, multicastChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquire" -> {
                        try {
                            val wm = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager
                            multicastLock = wm.createMulticastLock("powerViewDiscovery")
                            multicastLock?.setReferenceCounted(false)
                            multicastLock?.acquire()
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("LOCK_FAILED", e.message, null)
                        }
                    }
                    "release" -> {
                        try {
                            multicastLock?.release()
                            multicastLock = null
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("UNLOCK_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Wi-Fi settings + current SSID ────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, wifiSettingsChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openWifiPanel" -> {
                        try {
                            // Android 10+ has a slide-up Wi-Fi panel; older
                            // versions fall back to the full settings page.
                            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                Intent(Settings.Panel.ACTION_WIFI)
                            } else {
                                Intent(Settings.ACTION_WIFI_SETTINGS)
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("OPEN_WIFI_FAILED", e.message, null)
                        }
                    }
                    "getCurrentSsid" -> {
                        // Returns the SSID the device is currently joined to,
                        // or null if unknown (not on Wi-Fi, or on Android 10+
                        // without location permission).
                        try {
                            val wm = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager
                            var ssid: String? = wm.connectionInfo?.ssid
                            if (ssid.isNullOrBlank() || ssid == "<unknown ssid>") {
                                result.success(null)
                            } else {
                                if (ssid.length >= 2 &&
                                    ssid.startsWith("\"") && ssid.endsWith("\"")) {
                                    ssid = ssid.substring(1, ssid.length - 1)
                                }
                                result.success(ssid)
                            }
                        } catch (e: Exception) {
                            result.error("SSID_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
