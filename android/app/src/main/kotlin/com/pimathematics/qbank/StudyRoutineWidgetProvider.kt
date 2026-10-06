package com.pi.mathematics

import android.app.AlarmManager
import android.appwidget.AppWidgetManager
import android.app.PendingIntent
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject
import java.text.DateFormat
import java.util.Calendar

internal const val STUDY_ROUTINE_PREFS = "FlutterSharedPreferences"
internal const val STUDY_ROUTINE_KEY = "flutter.study_routine_v1"
internal const val STUDY_ROUTINE_ALARM_ACTION = "com.pi.mathematics.STUDY_ROUTINE_BOUNDARY"
internal const val STUDY_ROUTINE_ENABLED_KEY = "flutter.study_routine_notifications_enabled"

internal object StudyRoutineData {
    fun sessions(context: Context): List<JSONObject> {
        val raw = context.getSharedPreferences(STUDY_ROUTINE_PREFS, Context.MODE_PRIVATE)
            .getString(STUDY_ROUTINE_KEY, null) ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).map { array.getJSONObject(it) }
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun activeSession(context: Context, now: Calendar = Calendar.getInstance()): JSONObject? {
        val weekday = isoWeekday(now.get(Calendar.DAY_OF_WEEK))
        val previousWeekday = if (weekday == 1) 7 else weekday - 1
        val minute = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
        return sessions(context).firstOrNull { session ->
            val days = session.optJSONArray("weekdays") ?: JSONArray()
            val start = session.optInt("startMinute", -1)
            val end = session.optInt("endMinute", -1)
            when {
                start !in 0..1439 || end !in 0..1439 || start == end -> false
                end > start -> containsDay(days, weekday) && minute >= start && minute < end
                minute >= start -> containsDay(days, weekday)
                minute < end -> containsDay(days, previousWeekday)
                else -> false
            }
        }
    }

    fun compareByCurrentTime(
        first: JSONObject,
        second: JSONObject,
        now: Calendar,
        activeId: String?,
    ): Int {
        val firstActive = first.optString("id") == activeId
        val secondActive = second.optString("id") == activeId
        if (firstActive != secondActive) return if (firstActive) -1 else 1
        if (firstActive) {
            val byStart = first.optInt("startMinute", 0)
                .compareTo(second.optInt("startMinute", 0))
            if (byStart != 0) return byStart
        }

        val firstNext = nextStartTime(first, now) ?: Long.MAX_VALUE
        val secondNext = nextStartTime(second, now) ?: Long.MAX_VALUE
        val byNextStart = firstNext.compareTo(secondNext)
        if (byNextStart != 0) return byNextStart
        val byStart = first.optInt("startMinute", 0)
            .compareTo(second.optInt("startMinute", 0))
        return if (byStart != 0) byStart
        else first.optString("id").compareTo(second.optString("id"))
    }

    private fun nextStartTime(session: JSONObject, now: Calendar): Long? {
        val startMinute = session.optInt("startMinute", -1)
        if (startMinute !in 0..1439) return null
        val weekdays = session.optJSONArray("weekdays") ?: JSONArray()
        for (offset in 0..7) {
            val day = (now.clone() as Calendar).apply {
                add(Calendar.DAY_OF_YEAR, offset)
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            val occursOnDay = if (weekdays.length() == 0) {
                offset == 0
            } else {
                containsDay(weekdays, isoWeekday(day.get(Calendar.DAY_OF_WEEK)))
            }
            if (!occursOnDay) continue
            day.set(Calendar.HOUR_OF_DAY, startMinute / 60)
            day.set(Calendar.MINUTE, startMinute % 60)
            if (day.timeInMillis > now.timeInMillis) return day.timeInMillis
        }
        return null
    }

    fun nextSession(context: Context, now: Calendar = Calendar.getInstance()): Pair<JSONObject, Calendar>? {
        val sessions = sessions(context)
        var best: Pair<JSONObject, Calendar>? = null
        for (offset in 0..7) {
            val day = (now.clone() as Calendar).apply {
                add(Calendar.DAY_OF_YEAR, offset)
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            val weekday = isoWeekday(day.get(Calendar.DAY_OF_WEEK))
            for (session in sessions) {
                val weekdays = session.optJSONArray("weekdays") ?: JSONArray()
                if (!containsDay(weekdays, weekday)) continue
                val startMinute = session.optInt("startMinute", -1)
                if (startMinute !in 0..1439) continue
                val start = (day.clone() as Calendar).apply {
                    set(Calendar.HOUR_OF_DAY, startMinute / 60)
                    set(Calendar.MINUTE, startMinute % 60)
                }
                if (start.timeInMillis <= now.timeInMillis) continue
                if (best == null || start.timeInMillis < best!!.second.timeInMillis) {
                    best = session to start
                }
            }
        }
        return best
    }

    fun reschedule(context: Context) {
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
        val intent = Intent(context, StudyRoutineAlarmReceiver::class.java)
            .setAction(STUDY_ROUTINE_ALARM_ACTION)
        val pending = PendingIntent.getBroadcast(
            context,
            74120,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        alarmManager.cancel(pending)

        val now = Calendar.getInstance()
        var nextBoundary: Calendar? = null
        var boundaryIsStart = false
        for (offset in -1..7) {
            val day = (now.clone() as Calendar).apply {
                add(Calendar.DAY_OF_YEAR, offset)
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            val weekday = isoWeekday(day.get(Calendar.DAY_OF_WEEK))
            for (session in sessions(context)) {
                val weekdays = session.optJSONArray("weekdays") ?: JSONArray()
                if (!containsDay(weekdays, weekday)) continue
                val startMinute = session.optInt("startMinute", -1)
                val endMinute = session.optInt("endMinute", -1)
                if (startMinute !in 0..1439 || endMinute !in 0..1439 || startMinute == endMinute) continue
                val boundaries = listOf(
                    Triple(startMinute, 0, true),
                    Triple(endMinute, if (endMinute < startMinute) 1 else 0, false),
                )
                for ((minute, dayOffset, isStart) in boundaries) {
                    val boundary = (day.clone() as Calendar).apply {
                        add(Calendar.DAY_OF_YEAR, dayOffset)
                        set(Calendar.HOUR_OF_DAY, minute / 60)
                        set(Calendar.MINUTE, minute % 60)
                    }
                    if (boundary.timeInMillis > now.timeInMillis &&
                        (nextBoundary == null || boundary.timeInMillis < nextBoundary!!.timeInMillis)) {
                        nextBoundary = boundary
                        boundaryIsStart = isStart
                    }
                }
            }
        }
        val next = nextBoundary ?: return
        intent.putExtra("notify_study_start", boundaryIsStart)
        val scheduledPending = PendingIntent.getBroadcast(
            context,
            74120,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next.timeInMillis, scheduledPending)
        } else {
            alarmManager.set(AlarmManager.RTC_WAKEUP, next.timeInMillis, scheduledPending)
        }
    }

    private fun containsDay(days: JSONArray, day: Int): Boolean =
        (0 until days.length()).any { days.optInt(it) == day }

    private fun isoWeekday(androidDay: Int): Int =
        if (androidDay == Calendar.SUNDAY) 7 else androidDay - 1
}

class StudyRoutineWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, appWidgetIds: IntArray) {
        appWidgetIds.forEach { updateWidget(context, manager, it) }
    }

    companion object {
        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val provider = ComponentName(context, StudyRoutineWidgetProvider::class.java)
            val ids = manager.getAppWidgetIds(provider)
            ids.forEach { updateWidget(context, manager, it) }
            if (ids.isNotEmpty()) {
                manager.notifyAppWidgetViewDataChanged(ids, R.id.study_widget_list)
            }
        }

        private fun updateWidget(context: Context, manager: AppWidgetManager, id: Int) {
            val views = RemoteViews(context.packageName, R.layout.study_routine_widget)
            views.setTextViewText(R.id.study_widget_status, "YOUR SUBJECTS · SCROLL")
            views.setInt(R.id.study_widget_status, "setBackgroundResource", R.drawable.study_widget_status_next)
            views.setTextColor(R.id.study_widget_status, 0xFF5345A5.toInt())
            val adapterIntent = Intent(context, StudyRoutineWidgetRemoteViewsService::class.java)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
                .setData(android.net.Uri.parse("routine-widget://$id"))
            views.setRemoteAdapter(R.id.study_widget_list, adapterIntent)
            views.setEmptyView(R.id.study_widget_list, R.id.study_widget_empty)
            val open = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (open != null) {
                open.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                open.putExtra("open_study_routine", true)
                val click = PendingIntent.getActivity(
                    context,
                    id + 93000,
                    open,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
                views.setOnClickPendingIntent(R.id.study_widget_root, click)
            }
            manager.updateAppWidget(id, views)
        }

        private fun periodLabel(context: Context, start: Int, end: Int): String {
            val date = Calendar.getInstance()
            val begin = (date.clone() as Calendar).apply {
                set(Calendar.HOUR_OF_DAY, start / 60)
                set(Calendar.MINUTE, start % 60)
            }
            val finish = (date.clone() as Calendar).apply {
                set(Calendar.HOUR_OF_DAY, end / 60)
                set(Calendar.MINUTE, end % 60)
            }
            val nextDay = if (end < start) " (+1 day)" else ""
            return "${DateFormat.getTimeInstance(DateFormat.SHORT).format(begin.time)} – " +
                DateFormat.getTimeInstance(DateFormat.SHORT).format(finish.time) + nextDay
        }

        private fun dayLabel(date: Calendar): String {
            val today = Calendar.getInstance()
            return when {
                date.get(Calendar.YEAR) == today.get(Calendar.YEAR) &&
                    date.get(Calendar.DAY_OF_YEAR) == today.get(Calendar.DAY_OF_YEAR) -> "Today"
                date.get(Calendar.YEAR) == today.get(Calendar.YEAR) &&
                    date.get(Calendar.DAY_OF_YEAR) - today.get(Calendar.DAY_OF_YEAR) == 1 -> "Tomorrow"
                else -> DateFormat.getDateInstance(DateFormat.MEDIUM).format(date.time)
            }
        }
    }
}

class StudyRoutineWidgetRemoteViewsService : android.widget.RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        StudyRoutineWidgetFactory(applicationContext)
}

private class StudyRoutineWidgetFactory(
    private val context: Context,
) : android.widget.RemoteViewsService.RemoteViewsFactory {
    private var routine: List<JSONObject> = emptyList()

    override fun onCreate() = Unit

    override fun onDataSetChanged() {
        val now = Calendar.getInstance()
        val activeId = StudyRoutineData.activeSession(context, now)?.optString("id")
        routine = StudyRoutineData.sessions(context).sortedWith { first, second ->
            StudyRoutineData.compareByCurrentTime(first, second, now, activeId)
        }
    }

    override fun onDestroy() {
        routine = emptyList()
    }

    override fun getCount(): Int = routine.size

    override fun getViewAt(position: Int): RemoteViews? {
        val session = routine.getOrNull(position) ?: return null
        val subject = session.optString("subject", "Subject")
        val period = periodLabel(
            context,
            session.optInt("startMinute"),
            session.optInt("endMinute"),
        )
        val views = RemoteViews(context.packageName, R.layout.study_routine_widget_item)
        views.setTextViewText(R.id.study_widget_item_subject, subject)
        views.setTextViewText(
            R.id.study_widget_item_period,
            period,
        )
        val active = StudyRoutineData.activeSession(context)
        if (active?.optString("id") == session.optString("id")) {
            views.setTextViewText(R.id.study_widget_item_status, "NOW")
            views.setViewVisibility(R.id.study_widget_item_status, android.view.View.VISIBLE)
        } else {
            views.setViewVisibility(R.id.study_widget_item_status, android.view.View.GONE)
        }
        return views
    }

    override fun getLoadingView(): RemoteViews? = null
    override fun getViewTypeCount(): Int = 1
    override fun getItemId(position: Int): Long =
        routine.getOrNull(position)?.optString("id")?.hashCode()?.toLong() ?: position.toLong()
    override fun hasStableIds(): Boolean = true

    private fun periodLabel(context: Context, start: Int, end: Int): String {
        val date = Calendar.getInstance()
        val begin = (date.clone() as Calendar).apply {
            set(Calendar.HOUR_OF_DAY, start / 60)
            set(Calendar.MINUTE, start % 60)
        }
        val finish = (date.clone() as Calendar).apply {
            set(Calendar.HOUR_OF_DAY, end / 60)
            set(Calendar.MINUTE, end % 60)
        }
        val suffix = if (end < start) " (+1 day)" else ""
        val durationMinutes = (end - start + 24 * 60) % (24 * 60)
        val hours = durationMinutes / 60
        val minutes = durationMinutes % 60
        val duration = buildList {
            if (hours > 0) add("${hours}h")
            if (minutes > 0) add("${minutes}m")
            if (hours == 0 && minutes == 0) add("0m")
        }.joinToString(" ")
        return "${DateFormat.getTimeInstance(DateFormat.SHORT).format(begin.time)} – " +
            DateFormat.getTimeInstance(DateFormat.SHORT).format(finish.time) +
            "$suffix · $duration"
    }
}
