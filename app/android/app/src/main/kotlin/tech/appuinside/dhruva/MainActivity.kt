package tech.appuinside.dhruva

import android.content.Intent
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        initial = extract(intent)
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

    // singleTop: a share/shortcut while the app is open lands here, not onCreate.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        extract(intent)?.let { channel?.invokeMethod("onIntent", it) }
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
