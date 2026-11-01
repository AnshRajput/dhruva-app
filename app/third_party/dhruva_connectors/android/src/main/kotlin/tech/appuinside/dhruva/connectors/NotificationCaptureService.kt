package tech.appuinside.dhruva.connectors

import android.app.Notification
import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.telecom.TelecomManager
import org.json.JSONObject

/**
 * Records title / text / app / time of notifications into the app-private
 * queue (see [NotificationQueueWriter]) so Dart can ingest them on app open.
 * It never touches the database and never makes a network call.
 *
 * Exported only because the system must bind it, and guarded by
 * BIND_NOTIFICATION_LISTENER_SERVICE so only the system can. It does nothing
 * until the user has granted notification access AND the app has switched
 * capture on ([ConnectorPrefs.captureEnabled], off by default).
 *
 * Skipped, never recorded: this app's own notifications, the dialer, apps the
 * user excluded, ongoing/foreground-service and group-summary entries,
 * call/progress/transport/service categories, and notifications marked
 * VISIBILITY_SECRET. Text is exactly what Android hands a listener (Android 15
 * already redacts one-time-password notifications); nothing is unredacted here.
 */
class NotificationCaptureService : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val s = sbn ?: return
        try {
            record(applicationContext, s)
        } catch (_: Exception) {
            // A malformed notification must never crash the listener.
        }
    }

    private fun record(ctx: Context, s: StatusBarNotification) {
        if (!ConnectorPrefs.captureEnabled(ctx)) return
        val pkg = s.packageName ?: return
        if (pkg == ctx.packageName || pkg in DIALERS || pkg == defaultDialer(ctx)) return
        if (pkg in ConnectorPrefs.excluded(ctx)) return
        val n = s.notification ?: return
        if (n.flags and (Notification.FLAG_GROUP_SUMMARY or Notification.FLAG_ONGOING_EVENT or
                Notification.FLAG_FOREGROUND_SERVICE) != 0) return
        if (n.visibility == Notification.VISIBILITY_SECRET) return
        if (n.category in SKIPPED_CATEGORIES) return

        val extras = n.extras ?: return
        val title = clean(extras.getCharSequence(Notification.EXTRA_TITLE), MAX_TITLE)
        val text = clean(
            extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
                ?: extras.getCharSequence(Notification.EXTRA_TEXT),
            MAX_TEXT,
        )
        if (title.isEmpty() && text.isEmpty()) return

        val line = JSONObject()
            .put("v", 1)
            .put("pkg", pkg)
            .put("app", appLabel(ctx, pkg))
            .put("title", title)
            .put("text", text)
            .put("t", s.postTime)
            .toString()
        NotificationQueueWriter.append(ctx, line)
    }

    private fun defaultDialer(ctx: Context): String? = try {
        (ctx.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager)?.defaultDialerPackage
    } catch (_: Exception) {
        null
    }

    // Package visibility (Android 11+) can hide another app's label; Dart falls
    // back to the package id. QUERY_ALL_PACKAGES is deliberately not requested.
    private fun appLabel(ctx: Context, pkg: String): String = try {
        val pm = ctx.packageManager
        clean(pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)), MAX_APP)
    } catch (_: Exception) {
        ""
    }

    private fun clean(cs: CharSequence?, max: Int): String {
        val raw = cs?.toString() ?: return ""
        val sb = StringBuilder(minOf(raw.length, max))
        for (ch in raw) {
            if (sb.length >= max) break
            sb.append(if (ch.code < 0x20 && ch != '\n' || ch.code == 0x7f) ' ' else ch)
        }
        // Do not end on half a surrogate pair.
        if (sb.isNotEmpty() && Character.isHighSurrogate(sb.last())) sb.setLength(sb.length - 1)
        return sb.toString().trim()
    }

    private companion object {
        const val MAX_TITLE = 300
        const val MAX_TEXT = 3000
        const val MAX_APP = 100

        val DIALERS = setOf(
            "com.android.dialer",
            "com.google.android.dialer",
            "com.samsung.android.dialer",
            "com.android.incallui",
            "com.android.server.telecom",
            "com.android.phone",
        )

        val SKIPPED_CATEGORIES = setOf(
            Notification.CATEGORY_CALL,
            Notification.CATEGORY_PROGRESS,
            Notification.CATEGORY_SERVICE,
            Notification.CATEGORY_TRANSPORT,
        )
    }
}
