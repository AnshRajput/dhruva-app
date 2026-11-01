package tech.appuinside.dhruva.connectors

import android.content.Context
import java.io.File
import java.io.FileOutputStream

/**
 * Switches shared between Dart (through the plugin) and the listener service,
 * in app-private SharedPreferences. Capture is OFF until Dart turns it on
 * (connect) and is turned off again on revoke.
 */
internal object ConnectorPrefs {
    private const val FILE = "dhruva_connectors"
    private const val KEY_CAPTURE = "notif_capture"
    private const val KEY_EXCLUDED = "notif_excluded"
    private const val KEY_CALENDAR_ASKED = "calendar_asked"

    private fun prefs(c: Context) =
        c.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    fun captureEnabled(c: Context) = prefs(c).getBoolean(KEY_CAPTURE, false)
    fun setCapture(c: Context, on: Boolean) =
        prefs(c).edit().putBoolean(KEY_CAPTURE, on).apply()

    fun excluded(c: Context): Set<String> =
        prefs(c).getStringSet(KEY_EXCLUDED, emptySet()) ?: emptySet()

    fun setExcluded(c: Context, packages: Collection<String>) =
        prefs(c).edit().putStringSet(KEY_EXCLUDED, packages.toSet()).apply()

    fun calendarAsked(c: Context) = prefs(c).getBoolean(KEY_CALENDAR_ASKED, false)
    fun setCalendarAsked(c: Context) =
        prefs(c).edit().putBoolean(KEY_CALENDAR_ASKED, true).apply()
}

/**
 * The listener's append-only queue: `<filesDir>/connectors/notifications/
 * notifications.jsonl`, one JSON object per line (schema in Dart:
 * data/connectors/notification_queue.dart). Size-capped by rotation: when the
 * live file would pass [MAX_BYTES] it becomes `.old` (replacing the previous
 * `.old`), so at most about 2 x [MAX_BYTES] ever sit on disk. Dart renames the
 * files away to drain them, which is why every append re-opens the path.
 */
internal object NotificationQueueWriter {
    const val MAX_BYTES = 512 * 1024
    private const val LIVE = "notifications.jsonl"
    private const val OLD = "notifications.jsonl.old"

    fun directory(c: Context): File =
        File(c.applicationContext.filesDir, "connectors/notifications").apply { mkdirs() }

    @Synchronized
    fun append(c: Context, line: String) {
        val bytes = (line + "\n").toByteArray(Charsets.UTF_8)
        val dir = directory(c)
        val live = File(dir, LIVE)
        if (live.exists() && live.length() + bytes.size > MAX_BYTES) {
            val old = File(dir, OLD)
            old.delete()
            live.renameTo(old)
        }
        FileOutputStream(File(dir, LIVE), true).use { it.write(bytes) }
    }
}
