package tech.appuinside.dhruva

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews

/**
 * Home-screen widget: pole-star mark, "Ask Dhruva..." pill (new chat), and
 * Workflows / Talk buttons. Resizable 4x1 down to 2x1: narrower widths drop
 * the Workflows button first, then Talk, and shorten the pill label.
 */
class DhruvaWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { update(context, manager, it) }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        newOptions: Bundle,
    ) = update(context, manager, id)

    private fun update(context: Context, manager: AppWidgetManager, id: Int) {
        val widthDp = manager.getAppWidgetOptions(id)
            .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
        // Unknown width (0) renders the full layout.
        val showWorkflows = widthDp == 0 || widthDp >= 250
        val showTalk = widthDp == 0 || widthDp >= 170
        val shortLabel = widthDp in 1..149

        val views = RemoteViews(context.packageName, R.layout.widget_dhruva).apply {
            setTextViewText(
                R.id.widget_ask,
                context.getString(if (shortLabel) R.string.widget_ask_short else R.string.widget_ask),
            )
            setViewVisibility(R.id.widget_workflows, if (showWorkflows) View.VISIBLE else View.GONE)
            setViewVisibility(R.id.widget_talk, if (showTalk) View.VISIBLE else View.GONE)
            val newChat = ShortcutIntents.pending(context, "new_chat", 0)
            setOnClickPendingIntent(R.id.widget_root, newChat)
            setOnClickPendingIntent(R.id.widget_ask, newChat)
            setOnClickPendingIntent(R.id.widget_workflows, ShortcutIntents.pending(context, "workflows", 1))
            setOnClickPendingIntent(R.id.widget_talk, ShortcutIntents.pending(context, "talk", 2))
        }
        manager.updateAppWidget(id, views)
    }
}
