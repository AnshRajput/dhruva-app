package tech.appuinside.dhruva

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Forwards system entry points (share sheet, text-selection "Ask Dhruva AI",
 * launcher shortcuts) to Dart over `dhruva/intents` as
 * `{text?, route?, replaceable?}`. Routing lives in Dart (`IntentInbox`); this
 * class only extracts.
 *
 * PROCESS_TEXT round trip: when the selection menu was opened on an EDITABLE
 * field (EXTRA_PROCESS_TEXT_READONLY present and false) and this activity was
 * started for a result, the payload carries `replaceable: true` and Dart can
 * call `setProcessTextResult(text)` to hand the result back
 * (`setResult(RESULT_OK, Intent().putExtra(EXTRA_PROCESS_TEXT, text))`, then
 * finish). `open` so [ProcessTextActivity] (standard launch mode, required for
 * a result to reach the calling app) shares all of this.
 */
open class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var initial: Map<String, Any>? = null

    // True only for the launching intent of a PROCESS_TEXT started for a result
    // on an editable field. Later onNewIntent deliveries never reset it to true.
    private var replaceable = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        replaceable = isReplaceableProcessText(intent)
        initial = extract(intent)
        // Battery & heat guard (Dart: core/device_health). Always answers; any
        // unavailable value is -1 / "unknown".
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.dhruva/device_health")
            .setMethodCallHandler { call, result ->
                if (call.method == "read") result.success(readDeviceHealth())
                else result.notImplemented()
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

    // FlutterActivity treats an intent extra named `route` as the engine's
    // initial route, so a shortcut `route=new_chat` would hit go_router as
    // "/new_chat" before IntentInbox runs. Always boot at "/"; IntentInbox
    // owns shortcut routing.
    override fun getInitialRoute(): String = "/"

    // singleTop: a share/shortcut while the app is open lands here, not onCreate.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // A redelivered intent can't answer the original caller's request.
        replaceable = false
        extract(intent)?.let { channel?.invokeMethod("onIntent", it) }
    }

    /**
     * Sends [arg] back to the app that opened the selection menu and closes
     * this screen. Rejected unless this launch really is a replaceable
     * PROCESS_TEXT, and for empty or oversized text (the Binder transaction
     * limit is ~1 MB; the cap leaves ample headroom).
     */
    private fun returnProcessText(arg: Any?, result: MethodChannel.Result) {
        val text = arg as? String
        if (!replaceable) {
            result.error("not_replaceable", "No editable selection to replace", null)
        } else if (text.isNullOrBlank()) {
            result.error("empty", "Nothing to send back", null)
        } else if (text.length > MAX_RESULT_CHARS) {
            result.error("too_long", "Result is too long to send back", null)
        } else {
            setResult(RESULT_OK, Intent().putExtra(Intent.EXTRA_PROCESS_TEXT, text))
            replaceable = false
            result.success(true)
            finish()
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

    private fun isReplaceableProcessText(intent: Intent?): Boolean =
        intent?.action == Intent.ACTION_PROCESS_TEXT &&
            callingActivity != null &&
            intent.hasExtra(Intent.EXTRA_PROCESS_TEXT_READONLY) &&
            !intent.getBooleanExtra(Intent.EXTRA_PROCESS_TEXT_READONLY, true)

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
            return mapOf("text" to text, "replaceable" to (replaceable && intent?.action == Intent.ACTION_PROCESS_TEXT))
        }
        return intent?.getStringExtra("route")?.let { mapOf("route" to it) }
    }

    companion object {
        const val MAX_RESULT_CHARS = 100_000
    }
}

/**
 * Target of the text-selection "Ask Dhruva AI" menu item. A separate,
 * standard-launch-mode activity: [MainActivity] is singleTask, and a result
 * is never delivered to the caller of a singleTask activity, so "Replace
 * selected text" needs its own instance inside the calling app's task.
 */
class ProcessTextActivity : MainActivity()
