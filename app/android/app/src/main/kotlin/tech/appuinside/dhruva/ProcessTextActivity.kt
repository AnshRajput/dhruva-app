package tech.appuinside.dhruva

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import java.lang.ref.WeakReference
import java.security.SecureRandom

/**
 * Target of the text-selection "Ask Dhruva AI" menu item.
 *
 * It is a UI-less trampoline on purpose. It used to be a second FlutterActivity,
 * and each selection then booted a second full Flutter engine and app in the same
 * process (a second database connection, connector hub, brief scheduling, model
 * isolate and lease). Now there is one engine, owned by [MainActivity]; this
 * activity only forwards the selected text to it.
 *
 * It stays a standard-launch-mode activity in the CALLING app's task, because a
 * result can only reach the caller from there ([MainActivity] is singleTask).
 * When the selection was on an editable field and we were started for a result,
 * we stay alive, invisible, until Dhruva hands a replacement back through
 * [ProcessTextBridge], or until the user comes back without one.
 */
class ProcessTextActivity : Activity() {
    private var leftOnce = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val text = intent?.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString()
        if (intent?.action != Intent.ACTION_PROCESS_TEXT || text.isNullOrBlank()) {
            finish()
            return
        }
        val replaceable = callingActivity != null &&
            intent.hasExtra(Intent.EXTRA_PROCESS_TEXT_READONLY) &&
            !intent.getBooleanExtra(Intent.EXTRA_PROCESS_TEXT_READONLY, true)
        val token = if (replaceable) ProcessTextBridge.register(this) else null
        startActivity(
            Intent(this, MainActivity::class.java)
                .setAction(Intent.ACTION_PROCESS_TEXT)
                .putExtra(Intent.EXTRA_PROCESS_TEXT, text)
                .apply { token?.let { putExtra(ProcessTextBridge.EXTRA_TOKEN, it) } }
        )
        // Nothing to wait for: a read-only selection cannot take a result.
        if (token == null) finish()
    }

    override fun onPause() {
        super.onPause()
        leftOnce = true
    }

    // The user came back to the app they selected in without replacing
    // anything: step aside (a transparent activity would swallow their taps).
    override fun onResume() {
        super.onResume()
        if (leftOnce) finish()
    }

    override fun onDestroy() {
        ProcessTextBridge.clear(this)
        super.onDestroy()
    }
}

/**
 * Process-wide hand-off between [MainActivity] and the waiting
 * [ProcessTextActivity]. One pending request at a time; a newer selection
 * replaces an older one (the older trampoline steps aside on resume).
 */
object ProcessTextBridge {
    const val EXTRA_TOKEN = "tech.appuinside.dhruva.PROCESS_TEXT_TOKEN"

    private var pending: WeakReference<ProcessTextActivity>? = null
    private var token: String? = null

    @Synchronized
    fun register(activity: ProcessTextActivity): String {
        val bytes = ByteArray(16).also { SecureRandom().nextBytes(it) }
        val t = bytes.joinToString("") { "%02x".format(it) }
        pending = WeakReference(activity)
        token = t
        return t
    }

    /** True when [candidate] is the token of the request that is waiting. */
    @Synchronized
    fun accepts(candidate: String?): Boolean =
        candidate != null && candidate == token && pending?.get() != null

    @Synchronized
    fun hasPending(): Boolean = pending?.get() != null

    /**
     * Sets the result for the calling app and finishes the trampoline, only if
     * [requestToken] is the token of the request still waiting (a stale or
     * foreign result is refused).
     */
    @Synchronized
    fun deliver(text: String, requestToken: String?): Boolean {
        if (requestToken == null || requestToken != token) return false
        val activity = pending?.get() ?: return false
        pending = null
        token = null
        activity.setResult(
            Activity.RESULT_OK,
            Intent().putExtra(Intent.EXTRA_PROCESS_TEXT, text),
        )
        activity.finish()
        return true
    }

    @Synchronized
    fun clear(activity: ProcessTextActivity) {
        if (pending?.get() === activity) {
            pending = null
            token = null
        }
    }
}
