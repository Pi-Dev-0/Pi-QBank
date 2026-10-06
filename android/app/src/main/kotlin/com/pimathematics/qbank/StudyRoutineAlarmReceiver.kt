package com.pi.mathematics

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import java.text.DateFormat
import java.util.Calendar
import org.json.JSONObject

private const val STUDY_NOTIFICATION_CHANNEL = "study_routine_fullscreen_v2"

class StudyRoutineAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != STUDY_ROUTINE_ALARM_ACTION) return
        val pendingResult = goAsync()
        try {
            val queryNow = Calendar.getInstance().apply { add(Calendar.SECOND, 2) }
            val active = StudyRoutineData.activeSession(context, queryNow)
            if (active != null) {
                showFullscreenStudyRoutine(context, active)
            }
            StudyRoutineWidgetProvider.refreshAll(context)
        } finally {
            pendingResult.finish()
        }
    }

    private fun showFullscreenStudyRoutine(context: Context, session: JSONObject) {
        val prefs = context.getSharedPreferences(STUDY_ROUTINE_PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(STUDY_ROUTINE_ENABLED_KEY, true)) return

        val subject = session.optString("subject", "Study Session")
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

        val durationMinutes = ((end - start + 24 * 60) % (24 * 60)).let { if (it == 0) 24 * 60 else it }
        val durationText = buildString {
            val h = durationMinutes / 60
            val m = durationMinutes % 60
            if (h > 0) append("${h}h ")
            if (m > 0 || h == 0) append("${m}m")
        }.trim()

        val overlayIntent = Intent(context, StudyRoutineOverlayActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra(StudyRoutineOverlayActivity.EXTRA_SUBJECT, subject)
            putExtra(StudyRoutineOverlayActivity.EXTRA_TIME_RANGE, range)
            putExtra(StudyRoutineOverlayActivity.EXTRA_DURATION, durationText)
            putExtra(StudyRoutineOverlayActivity.EXTRA_SESSION_ID, session.optString("id"))
        }

        // A user granted overlay access allows the reminder activity to open
        // above another app while the phone is awake and unlocked. Let Android's
        // full-screen notification handle the lock screen and screen-off cases.
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        val keyguardManager = context.getSystemService(Context.KEYGUARD_SERVICE) as? android.app.KeyguardManager
        val canDrawOverApps = Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            Settings.canDrawOverlays(context)
        if (canDrawOverApps && powerManager?.isInteractive == true &&
            keyguardManager?.isKeyguardLocked != true) {
            try {
                context.startActivity(overlayIntent)
            } catch (_: Exception) {
                // The high-priority notification remains available as fallback.
            }
        }

        val fullScreenPending = PendingIntent.getActivity(
            context,
            session.optString("id").hashCode(),
            overlayIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    STUDY_NOTIFICATION_CHANNEL,
                    "Study routine overlay",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "Full-screen study routine alerts"
                    setBypassDnd(true)
                    enableVibration(true)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                },
            )
        }

        val notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, STUDY_NOTIFICATION_CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }.setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Study time: $subject")
            .setContentText("$subject · $range")
            .setCategory(Notification.CATEGORY_ALARM)
            .setPriority(Notification.PRIORITY_MAX)
            .setFullScreenIntent(fullScreenPending, true)
            .setContentIntent(fullScreenPending)
            .setAutoCancel(true)
            .build()

        manager.notify(StudyRoutineOverlayActivity.STUDY_ROUTINE_NOTIFICATION_ID, notification)
    }
}

class StudyRoutineBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                StudyRoutineData.reschedule(context)
                StudyRoutineWidgetProvider.refreshAll(context)
                StudyTimerWidgetProvider.refreshAll(context)
            }
        }
    }
}
