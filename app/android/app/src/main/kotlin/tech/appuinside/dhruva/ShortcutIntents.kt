package tech.appuinside.dhruva

import android.app.PendingIntent
import android.content.Context
import android.content.Intent

/**
 * Builds the same `{route}` intent the static launcher shortcuts fire
 * (res/xml/shortcuts.xml), so the tile and widget reuse `IntentInbox` routing
 * instead of a second system. Routes: today, ask, new_chat, workflows (opens Actions), talk.
 */
object ShortcutIntents {
    private const val ACTION = "tech.appuinside.dhruva.SHORTCUT"

    fun intent(context: Context, route: String): Intent =
        Intent(ACTION).setClass(context, MainActivity::class.java)
            .putExtra("route", route)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    /** One request code per route: PendingIntents ignore extras when matching. */
    fun pending(context: Context, route: String, requestCode: Int): PendingIntent =
        PendingIntent.getActivity(
            context,
            requestCode,
            intent(context, route),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
}
