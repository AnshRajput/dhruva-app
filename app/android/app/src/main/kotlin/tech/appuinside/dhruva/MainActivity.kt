package tech.appuinside.dhruva

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Forwards system entry points (share sheet, text-selection "Ask Dhruva AI",
 * launcher shortcuts) to Dart over `dhruva/intents` as
 * `{text?, route?, replaceable?}`. Routing lives in Dart (`IntentInbox`); this
 * class only extracts.
 *
 * PROCESS_TEXT round trip: the selection menu starts [ProcessTextActivity], a
 * UI-less trampoline (it does NOT boot a second Flutter engine; this activity
 * and its engine are the only ones in the process). The trampoline forwards
 * the text here. When the selection was on an EDITABLE field and the trampoline
 * was started for a result, it also forwards a one-time token ([ProcessTextBridge]);
 * a payload with a valid token carries `replaceable: true` and Dart can call
 * `setProcessTextResult(text)`, which hands the text to the waiting trampoline
 * (it sets the result for the calling app and finishes) and sends this task to
 * the back so the user lands in the app they selected in.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var initial: Map<String, Any>? = null

    companion object {
        // "Hide content in app switcher" (Settings > Privacy). Process-wide so a
        // recreated activity (rotation, theme change) keeps the flag; Dart
        // re-sends it on every launch.
        private var hideInSwitcher = false

        const val MAX_RESULT_CHARS = 100_000
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
                    when (call.method) {
                        "getInitialIntent" -> {
                            // Hand over once, so a config-change restart doesn't replay it.
                            result.success(initial)
                            initial = null
                        }
                        "setProcessTextResult" -> returnProcessText(call.arguments, result)
                        "openAppSettings" -> result.success(openAppSettings())
                        else -> result.notImplemented()
                    }
                }
            }
    }

    // FlutterActivity also honours `dart_entrypoint`, `initial_route` and shell
    // argument extras from the launching intent, and this activity is exported:
    // pin the Dart entrypoint so no other app can pick one (the background sync
    // dispatcher is a vm:entry-point too).
    override fun getDartEntrypointFunctionName(): String = "main"

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

    /**
     * Sends [arg] back to the app that opened the selection menu (through the
     * waiting [ProcessTextActivity]) and returns the user to it. Rejected unless
     * a replaceable PROCESS_TEXT is really waiting, and for empty or oversized
     * text (the Binder transaction limit is ~1 MB; the cap leaves ample
     * headroom).
     */
    private fun returnProcessText(arg: Any?, result: MethodChannel.Result) {
        val text = arg as? String
        if (!ProcessTextBridge.hasPending()) {
            result.error("not_replaceable", "No editable selection to replace", null)
        } else if (text.isNullOrBlank()) {
            result.error("empty", "Nothing to send back", null)
        } else if (text.length > MAX_RESULT_CHARS) {
            result.error("too_long", "Result is too long to send back", null)
        } else if (!ProcessTextBridge.deliver(text)) {
            result.error("not_replaceable", "The app you selected in is gone", null)
        } else {
            result.success(true)
            moveTaskToBack(true)
        }
    }

    /**
     * Opens this app's page in system Settings (the fix for a denied
     * permission, which an app cannot re-request). False if the OS refuses.
     */
    private fun openAppSettings(): Boolean =
        try {
            startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            true
        } catch (_: Exception) {
            false
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

    private fun extract(intent: Intent?): Map<String, Any>? {
        val text = when (intent?.action) {
            Intent.ACTION_SEND -> intent.getCharSequenceExtra(Intent.EXTRA_TEXT)
            Intent.ACTION_PROCESS_TEXT -> intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)
            else -> null
        }?.toString()
        if (!text.isNullOrBlank()) {
            // Replaceable only with the trampoline's one-time token: an exported
            // activity must not trust a bare `replaceable` extra from any app.
            val replaceable = intent?.action == Intent.ACTION_PROCESS_TEXT &&
                ProcessTextBridge.accepts(intent.getStringExtra(ProcessTextBridge.EXTRA_TOKEN))
            return mapOf("text" to text, "replaceable" to replaceable)
        }
        return intent?.getStringExtra("route")?.let { mapOf("route" to it) }
    }
}
