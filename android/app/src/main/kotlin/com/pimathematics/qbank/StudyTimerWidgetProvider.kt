package com.pi.mathematics

import android.appwidget.AppWidgetManager
import android.app.PendingIntent
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

internal const val STUDY_TIMER_PREFS = "FlutterSharedPreferences"
internal const val STUDY_TIMER_RUNNING_KEY = "flutter.study_timer_running"
internal const val STUDY_TIMER_ELAPSED_KEY = "flutter.study_timer_elapsed_ms"
internal const val STUDY_TIMER_SEGMENT_START_KEY = "flutter.study_timer_segment_start_epoch"
internal const val STUDY_TIMER_RUN_START_KEY = "flutter.study_timer_run_start_epoch"
internal const val STUDY_TIMER_HISTORY_KEY = "flutter.study_timer_history_v1"
internal const val STUDY_TIMER_ACTION = "com.pi.mathematics.STUDY_TIMER_ACTION"
internal const val STUDY_TIMER_MIDNIGHT_ACTION = "com.pi.mathematics.STUDY_TIMER_MIDNIGHT"
private const val STUDY_TIMER_DAY_KEY = "flutter.study_timer_day_key"

private const val ACTION_TOGGLE = "toggle"
private const val ACTION_REPORT = "report"
private const val REPORT_EXTRA = "open_study_timer_report"

class StudyTimerWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, appWidgetIds: IntArray) =
        refreshAll(context)

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        val prefs = context.getSharedPreferences(STUDY_TIMER_PREFS, Context.MODE_PRIVATE)
        if (intent.action == STUDY_TIMER_MIDNIGHT_ACTION) {
            ensureCurrentDay(prefs)
            refreshAll(context)
            return
        }
        if (intent.action != STUDY_TIMER_ACTION) return
        ensureCurrentDay(prefs)
        when (intent.getStringExtra("timer_action")) {
            ACTION_TOGGLE -> toggle(prefs)
            ACTION_REPORT -> {
                val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
                    ?: return
                launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                launch.putExtra(REPORT_EXTRA, true)
                context.startActivity(launch)
            }
        }
        refreshAll(context)
    }

    companion object {
        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val provider = ComponentName(context, StudyTimerWidgetProvider::class.java)
            val prefs = context.getSharedPreferences(STUDY_TIMER_PREFS, Context.MODE_PRIVATE)
            ensureCurrentDay(prefs)
            scheduleMidnightReset(context, prefs)
            manager.getAppWidgetIds(provider).forEach { updateWidget(context, manager, it) }
        }

        private fun updateWidget(context: Context, manager: AppWidgetManager, widgetId: Int) {
            val views = RemoteViews(context.packageName, R.layout.study_timer_widget)
            val prefs = context.getSharedPreferences(STUDY_TIMER_PREFS, Context.MODE_PRIVATE)
            val running = prefs.getBoolean(STUDY_TIMER_RUNNING_KEY, false)
            val elapsed = currentElapsed(prefs)
            if (running) {
                val base = SystemClock.elapsedRealtime() - elapsed
                views.setChronometer(R.id.study_timer_elapsed, base, "%s", true)
                views.setViewVisibility(R.id.study_timer_elapsed, android.view.View.VISIBLE)
                views.setViewVisibility(R.id.study_timer_elapsed_static, android.view.View.GONE)
            } else {
                views.setViewVisibility(R.id.study_timer_elapsed, android.view.View.GONE)
                views.setViewVisibility(R.id.study_timer_elapsed_static, android.view.View.VISIBLE)
                views.setTextViewText(R.id.study_timer_elapsed_static, formatDuration(elapsed))
            }
            views.setTextViewText(
                R.id.study_timer_toggle,
                if (running) "Pause" else "Start",
            )
            setAction(context, views, R.id.study_timer_toggle, widgetId, ACTION_TOGGLE)
            setAction(context, views, R.id.study_timer_report, widgetId, ACTION_REPORT)
            manager.updateAppWidget(widgetId, views)
        }

        private fun setAction(context: Context, views: RemoteViews, viewId: Int, widgetId: Int, action: String) {
            if (action == ACTION_REPORT) {
                val reportIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                    ?: return
                reportIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                reportIntent.putExtra(REPORT_EXTRA, true)
                val reportPending = PendingIntent.getActivity(
                    context,
                    widgetId * 10 + action.hashCode(),
                    reportIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
                views.setOnClickPendingIntent(viewId, reportPending)
                return
            }
            val intent = Intent(context, StudyTimerWidgetProvider::class.java).apply {
                this.action = STUDY_TIMER_ACTION
                putExtra("timer_action", action)
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
            }
            val pending = PendingIntent.getBroadcast(
                context,
                widgetId * 10 + action.hashCode(),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(viewId, pending)
        }

        private fun toggle(prefs: android.content.SharedPreferences) {
            val now = System.currentTimeMillis()
            val wasRunning = prefs.getBoolean(STUDY_TIMER_RUNNING_KEY, false)
            val elapsed = prefs.getLong(STUDY_TIMER_ELAPSED_KEY, 0L)
            if (wasRunning) {
                val segmentStart = prefs.getLong(STUDY_TIMER_SEGMENT_START_KEY, now)
                val segmentEnd = now.coerceAtLeast(segmentStart)
                appendHistory(prefs, segmentStart, segmentEnd)
                prefs.edit()
                    .putBoolean(STUDY_TIMER_RUNNING_KEY, false)
                    .putLong(STUDY_TIMER_ELAPSED_KEY, elapsed + segmentEnd - segmentStart)
                    .remove(STUDY_TIMER_SEGMENT_START_KEY)
                    .apply()
            } else {
                val editor = prefs.edit()
                    .putBoolean(STUDY_TIMER_RUNNING_KEY, true)
                    .putLong(STUDY_TIMER_SEGMENT_START_KEY, now)
                    .putString(STUDY_TIMER_DAY_KEY, currentDayKey(now))
                if (elapsed == 0L) editor.putLong(STUDY_TIMER_RUN_START_KEY, now)
                editor.apply()
            }
        }

        private fun appendHistory(prefs: android.content.SharedPreferences, start: Long, end: Long) {
            if (end <= start) return
            val history = try {
                JSONArray(prefs.getString(STUDY_TIMER_HISTORY_KEY, "[]"))
            } catch (_: Exception) {
                JSONArray()
            }
            history.put(
                JSONObject()
                    .put("startedAt", start)
                    .put("endedAt", end)
                    .put("durationMs", end - start),
            )
            val capped = JSONArray()
            for (i in (history.length() - 500).coerceAtLeast(0) until history.length()) {
                capped.put(history.getJSONObject(i))
            }
            prefs.edit().putString(STUDY_TIMER_HISTORY_KEY, capped.toString()).apply()
        }

        private fun currentElapsed(prefs: android.content.SharedPreferences): Long {
            val saved = prefs.getLong(STUDY_TIMER_ELAPSED_KEY, 0L)
            if (!prefs.getBoolean(STUDY_TIMER_RUNNING_KEY, false)) return saved.coerceAtLeast(0L)
            val start = prefs.getLong(STUDY_TIMER_SEGMENT_START_KEY, System.currentTimeMillis())
            return (saved + System.currentTimeMillis() - start).coerceAtLeast(0L)
        }

        private fun ensureCurrentDay(prefs: android.content.SharedPreferences) {
            val now = System.currentTimeMillis()
            val today = currentDayKey(now)
            val storedDay = prefs.getString(STUDY_TIMER_DAY_KEY, null)
            if (storedDay == null) {
                prefs.edit().putString(STUDY_TIMER_DAY_KEY, today).apply()
                return
            }
            if (storedDay == today) return

            if (prefs.getBoolean(STUDY_TIMER_RUNNING_KEY, false)) {
                val start = prefs.getLong(STUDY_TIMER_SEGMENT_START_KEY, now)
                val midnight = java.util.Calendar.getInstance().apply {
                    timeInMillis = start
                    set(java.util.Calendar.HOUR_OF_DAY, 0)
                    set(java.util.Calendar.MINUTE, 0)
                    set(java.util.Calendar.SECOND, 0)
                    set(java.util.Calendar.MILLISECOND, 0)
                    add(java.util.Calendar.DAY_OF_YEAR, 1)
                }.timeInMillis
                appendHistory(prefs, start, midnight.coerceAtLeast(start))
            }
            prefs.edit()
                .putBoolean(STUDY_TIMER_RUNNING_KEY, false)
                .putLong(STUDY_TIMER_ELAPSED_KEY, 0L)
                .putString(STUDY_TIMER_DAY_KEY, today)
                .remove(STUDY_TIMER_SEGMENT_START_KEY)
                .remove(STUDY_TIMER_RUN_START_KEY)
                .apply()
        }

        private fun currentDayKey(time: Long): String =
            SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(time))

        private fun scheduleMidnightReset(context: Context, prefs: android.content.SharedPreferences) {
            val alarmManager = context.getSystemService(android.app.AlarmManager::class.java) ?: return
            val intent = Intent(context, StudyTimerWidgetProvider::class.java)
                .setAction(STUDY_TIMER_MIDNIGHT_ACTION)
            val pending = PendingIntent.getBroadcast(
                context,
                74219,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            alarmManager.cancel(pending)
            val running = prefs.getBoolean(STUDY_TIMER_RUNNING_KEY, false)
            val elapsed = prefs.getLong(STUDY_TIMER_ELAPSED_KEY, 0L)
            if (!running && elapsed <= 0L) return
            val midnight = java.util.Calendar.getInstance().apply {
                add(java.util.Calendar.DAY_OF_YEAR, 1)
                set(java.util.Calendar.HOUR_OF_DAY, 0)
                set(java.util.Calendar.MINUTE, 0)
                set(java.util.Calendar.SECOND, 0)
                set(java.util.Calendar.MILLISECOND, 0)
            }.timeInMillis
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                alarmManager.setAndAllowWhileIdle(android.app.AlarmManager.RTC_WAKEUP, midnight, pending)
            } else {
                alarmManager.set(android.app.AlarmManager.RTC_WAKEUP, midnight, pending)
            }
        }

        private fun formatDuration(duration: Long): String {
            val seconds = duration / 1000
            val hours = seconds / 3600
            val minutes = (seconds % 3600) / 60
            val remainingSeconds = seconds % 60
            return String.format(Locale.getDefault(), "%02d:%02d:%02d", hours, minutes, remainingSeconds)
        }
    }
}
