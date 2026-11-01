package tech.appuinside.dhruva.connectors

import android.content.ContentUris
import android.content.Context
import android.provider.CalendarContract
import java.util.Calendar
import java.util.TimeZone

/**
 * Read-only calendar access through the Calendar Provider with READ_CALENDAR
 * alone (no WRITE_CALENDAR is declared or requested anywhere). Only calendars
 * the user keeps visible in their calendar app are read.
 */
internal object CalendarReader {
    private const val MAX_EVENTS = 1000
    private const val MAX_ATTENDEES_PER_EVENT = 50
    private const val MAX_TEXT = 16 * 1024

    fun events(ctx: Context, fromMs: Long, toMs: Long): List<Map<String, Any?>> {
        val uri = CalendarContract.Instances.CONTENT_URI.buildUpon().also {
            ContentUris.appendId(it, fromMs)
            ContentUris.appendId(it, toMs)
        }.build()
        val projection = arrayOf(
            CalendarContract.Instances.EVENT_ID,
            CalendarContract.Instances.BEGIN,
            CalendarContract.Instances.END,
            CalendarContract.Instances.TITLE,
            CalendarContract.Instances.DESCRIPTION,
            CalendarContract.Instances.EVENT_LOCATION,
            CalendarContract.Instances.ALL_DAY,
            CalendarContract.Instances.CALENDAR_ID,
            CalendarContract.Instances.CALENDAR_DISPLAY_NAME,
            CalendarContract.Instances.RRULE,
        )
        val out = ArrayList<MutableMap<String, Any?>>()
        val byEventId = HashMap<Long, MutableList<MutableMap<String, Any?>>>()
        ctx.contentResolver.query(
            uri, projection,
            "${CalendarContract.Instances.VISIBLE} = 1", null,
            "${CalendarContract.Instances.BEGIN} ASC",
        )?.use { c ->
            while (c.moveToNext() && out.size < MAX_EVENTS) {
                val eventId = c.getLong(0)
                val allDay = c.getInt(6) == 1
                val begin = c.getLong(1)
                val end = c.getLong(2)
                val m = mutableMapOf<String, Any?>(
                    "id" to "$eventId@$begin",
                    "calendarId" to c.getLong(7).toString(),
                    "calendarName" to c.getString(8),
                    "title" to c.getString(3).orEmpty().take(500),
                    "description" to c.getString(4)?.take(MAX_TEXT),
                    "location" to c.getString(5)?.take(500),
                    "start" to if (allDay) utcMidnightToLocal(begin) else begin,
                    "end" to if (allDay) utcMidnightToLocal(end) else end,
                    "allDay" to allDay,
                    "recurring" to !c.getString(9).isNullOrEmpty(),
                    "attendees" to ArrayList<Map<String, String>>(),
                )
                out.add(m)
                byEventId.getOrPut(eventId) { mutableListOf() }.add(m)
            }
        }
        attach(ctx, byEventId)
        return out
    }

    private fun attach(ctx: Context, byEventId: Map<Long, List<MutableMap<String, Any?>>>) {
        val ids = byEventId.keys.toList()
        for (chunk in ids.chunked(100)) {
            val sel = "${CalendarContract.Attendees.EVENT_ID} IN (${chunk.joinToString(",")})"
            ctx.contentResolver.query(
                CalendarContract.Attendees.CONTENT_URI,
                arrayOf(
                    CalendarContract.Attendees.EVENT_ID,
                    CalendarContract.Attendees.ATTENDEE_NAME,
                    CalendarContract.Attendees.ATTENDEE_EMAIL,
                ),
                sel, null, null,
            )?.use { c ->
                while (c.moveToNext()) {
                    val name = c.getString(1)?.take(200)
                    val email = c.getString(2)?.take(320)
                    if (name.isNullOrBlank() && email.isNullOrBlank()) continue
                    val person = HashMap<String, String>()
                    if (!name.isNullOrBlank()) person["name"] = name
                    if (!email.isNullOrBlank()) person["email"] = email
                    for (ev in byEventId[c.getLong(0)].orEmpty()) {
                        @Suppress("UNCHECKED_CAST")
                        val list = ev["attendees"] as ArrayList<Map<String, String>>
                        if (list.size < MAX_ATTENDEES_PER_EVENT) list.add(person)
                    }
                }
            }
        }
    }

    // All-day events are stored as midnight UTC; show them on the same local
    // calendar day.
    private fun utcMidnightToLocal(utcMs: Long): Long {
        val utc = Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply { timeInMillis = utcMs }
        return Calendar.getInstance().apply {
            clear()
            set(utc.get(Calendar.YEAR), utc.get(Calendar.MONTH), utc.get(Calendar.DAY_OF_MONTH))
        }.timeInMillis
    }
}
