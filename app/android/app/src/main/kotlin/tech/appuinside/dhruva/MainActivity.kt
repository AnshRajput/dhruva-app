package tech.appuinside.dhruva

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Forwards system entry points (share sheet, text-selection "Ask Dhruva AI",
 * launcher shortcuts) to Dart over `dhruva/intents` as `{text?, route?}`.
 * Routing lives in Dart (`IntentInbox`); this class only extracts.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var initial: Map<String, String>? = null

    companion object {
        // "Hide content in app switcher" (Settings > Privacy). Process-wide so a
        // recreated activity (rotation, theme change) keeps the flag; Dart
        // re-sends it on every launch.
        private var hideInSwitcher = false
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applySecureFlag()
    }

    private fun applySecureFlag() {
        if (hideInSwitcher) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        initial = extract(intent)
        // Battery & heat guard (Dart: core/device_health). Always answers; any
        // unavailable value is -1 / "unknown".
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.dhruva/device_health")
            .setMethodCallHandler { call, result ->
                if (call.method == "read") result.success(readDeviceHealth())
                else result.notImplemented()
            }
        // FLAG_SECURE on/off. Also hides the window from screenshots and screen
        // recording; the Settings row says so.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.dhruva/privacy")
            .setMethodCallHandler { call, result ->
                if (call.method == "setHideInSwitcher") {
                    hideInSwitcher = call.arguments as? Boolean ?: false
                    runOnUiThread { applySecureFlag() }
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dhruva/intents")
            .also { ch ->
                ch.setMethodCallHandler { call, result ->
                    if (call.method == "getInitialIntent") {
                        // Hand over once, so a config-change restart doesn't replay it.
                        result.success(initial)
                        initial = null
                    } else {
                        result.notImplemented()
                    }
                }
            }
    }

    // FlutterActivity treats an intent extra named `route` as the engine's
    // initial route, so a shortcut `route=new_chat` would hit go_router as
    // "/new_chat" before IntentInbox runs. Always boot at "/"; IntentInbox
    // owns shortcut routing.
    override fun getInitialRoute(): String = "/"

    // singleTop: a share/shortcut while the app is open lands here, not onCreate.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        extract(intent)?.let { channel?.invokeMethod("onIntent", it) }
    }

    private fun readDeviceHealth(): Map<String, Any> {
        var battery = -1
        var charging = false
        try {
            // Sticky broadcast: no receiver needed, returns the last value.
            val i = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            val level = i?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
            val scale = i?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
            if (level >= 0 && scale > 0) battery = level * 100 / scale
            val status = i?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
            charging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                status == BatteryManager.BATTERY_STATUS_FULL
        } catch (_: Exception) {
        }
        var thermal = "unknown"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                thermal = when (pm.currentThermalStatus) {
                    PowerManager.THERMAL_STATUS_NONE,
                    PowerManager.THERMAL_STATUS_LIGHT -> "nominal"
                    PowerManager.THERMAL_STATUS_MODERATE -> "fair"
                    PowerManager.THERMAL_STATUS_SEVERE -> "serious"
                    PowerManager.THERMAL_STATUS_CRITICAL,
                    PowerManager.THERMAL_STATUS_EMERGENCY,
                    PowerManager.THERMAL_STATUS_SHUTDOWN -> "critical"
                    else -> "unknown"
                }
            } catch (_: Exception) {
            }
        }
        return mapOf("battery" to battery, "charging" to charging, "thermal" to thermal)
    }

    private fun extract(intent: Intent?): Map<String, String>? {
        val text = when (intent?.action) {
            Intent.ACTION_SEND -> intent.getCharSequenceExtra(Intent.EXTRA_TEXT)
            Intent.ACTION_PROCESS_TEXT -> intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)
            else -> null
        }?.toString()
        if (!text.isNullOrBlank()) return mapOf("text" to text)
        return intent?.getStringExtra("route")?.let { mapOf("route" to it) }
    }
}
