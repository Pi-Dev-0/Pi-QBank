package com.pi.mathematics

import android.Manifest
import android.app.Notification
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import java.text.DateFormat
import java.util.Calendar

private const val STUDY_NOTIFICATION_CHANNEL = "study_routine_reminders"

class StudyRoutineAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != STUDY_ROUTINE_ALARM_ACTION) return
        val pendingResult = goAsync()
        try {
            if (intent.getBooleanExtra("notify_study_start", false)) {
                notifyCurrentStudySession(context)
            }
            StudyRoutineWidgetProvider.refreshAll(context)
            StudyRoutineData.reschedule(context)
        } finally {
            pendingResult.finish()
        }
    }

    private fun notifyCurrentStudySession(context: Context) {
        val prefs = context.getSharedPreferences(STUDY_ROUTINE_PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(STUDY_ROUTINE_ENABLED_KEY, true)) return
        val session = StudyRoutineData.activeSession(context) ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED) return

        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    STUDY_NOTIFICATION_CHANNEL,
                    "Study routine reminders",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ).apply { description = "Reminds you which subject to study now." },
            )
        }
        val start = session.optInt("startMinute")
        val end = session.optInt("endMinute")
        val now = Calendar.getInstance()
        val startTime = (now.clone() as Calendar).apply {
            set(Calendar.HOUR_OF_DAY, start / 60)
            set(Calendar.MINUTE, start % 60)
        }
        val endTime = (now.clone() as Calendar).apply {
            set(Calendar.HOUR_OF_DAY, end / 60)
            set(Calendar.MINUTE, end % 60)
        }
        val range = "${DateFormat.getTimeInstance(DateFormat.SHORT).format(startTime.time)} – " +
            DateFormat.getTimeInstance(DateFormat.SHORT).format(endTime.time)
        val openApp = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val contentIntent = openApp?.let {
            PendingIntent.getActivity(
                context,
                74300,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        val notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, STUDY_NOTIFICATION_CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }.setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Study time: ${session.optString("subject")}")
            .setContentText("${session.optString("subject")} · $range")
            .setStyle(Notification.BigTextStyle().bigText("It’s time to study ${session.optString("subject")} ($range)."))
            .setAutoCancel(true)
            .apply { if (contentIntent != null) setContentIntent(contentIntent) }
            .build()
        manager.notify(74301, notification)
    }
}

class StudyRoutineBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED -> {
                StudyRoutineData.reschedule(context)
                QrAlarmData.reschedule(context)
                StudyRoutineWidgetProvider.refreshAll(context)
                StudyTimerWidgetProvider.refreshAll(context)
            }
        }
    }
}
