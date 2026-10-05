package com.pi.mathematics

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

internal const val QR_ALARM_PREFS = "FlutterSharedPreferences"
internal const val QR_ALARMS_KEY = "flutter.qr_alarms_v1"
private const val QR_ALARM_CHANNEL = "qr_alarms"
private const val QR_ALARM_FIRE = "com.pi.mathematics.QR_ALARM_FIRE"
private const val QR_ALARM_EMERGENCY = "com.pi.mathematics.QR_ALARM_EMERGENCY_DISMISS"
private const val QR_ACTIVE_ALARMS = "qr_alarm_active_ids"

internal object QrAlarmData {
    fun alarms(context: Context): List<JSONObject> {
        val raw = context.getSharedPreferences(QR_ALARM_PREFS, Context.MODE_PRIVATE)
            .getString(QR_ALARMS_KEY, null) ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).map { array.getJSONObject(it) }
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun syncAndSchedule(context: Context, encoded: String) {
        val previousIds = alarms(context).map { it.optString("id") }.toSet()
        val parsed = JSONArray(encoded)
        context.getSharedPreferences(QR_ALARM_PREFS, Context.MODE_PRIVATE)
            .edit().putString(QR_ALARMS_KEY, parsed.toString()).apply()
        val current = (0 until parsed.length()).map { parsed.getJSONObject(it) }
        (previousIds + current.map { it.optString("id") }).forEach { cancel(context, it) }
        current.filter { it.optBoolean("enabled", true) }.forEach { schedule(context, it) }
    }

    fun reschedule(context: Context) {
        alarms(context).filter { it.optBoolean("enabled", true) }.forEach { schedule(context, it) }
    }

    fun alarm(context: Context, id: String): JSONObject? =
        alarms(context).firstOrNull { it.optString("id") == id }

    fun markOneShotConsumed(context: Context, id: String) {
        val updated = alarms(context).map { alarm ->
            if (alarm.optString("id") == id) alarm.put("enabled", false)
            alarm
        }
        context.getSharedPreferences(QR_ALARM_PREFS, Context.MODE_PRIVATE)
            .edit().putString(QR_ALARMS_KEY, JSONArray(updated).toString()).apply()
    }

    fun schedule(context: Context, alarm: JSONObject) {
        val id = alarm.optString("id")
        if (id.isEmpty()) return
        val next = nextOccurrence(alarm) ?: return
        val intent = Intent(context, QrAlarmReceiver::class.java)
            .setAction(QR_ALARM_FIRE)
            .putExtra("alarm_id", id)
        val pending = PendingIntent.getBroadcast(
            context, requestCode(id), intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val manager = context.getSystemService(AlarmManager::class.java) ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && manager.canScheduleExactAlarms()) {
            manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next, pending)
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next, pending)
        } else {
            manager.set(AlarmManager.RTC_WAKEUP, next, pending)
        }
    }

    fun cancel(context: Context, id: String) {
        val intent = Intent(context, QrAlarmReceiver::class.java).setAction(QR_ALARM_FIRE)
        val pending = PendingIntent.getBroadcast(
            context, requestCode(id), intent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        ) ?: return
        context.getSystemService(AlarmManager::class.java)?.cancel(pending)
        pending.cancel()
    }

    private fun nextOccurrence(alarm: JSONObject): Long? {
        val hour = alarm.optInt("hour", -1)
        val minute = alarm.optInt("minute", -1)
        if (hour !in 0..23 || minute !in 0..59) return null
        val days = alarm.optJSONArray("weekdays") ?: JSONArray()
        val now = Calendar.getInstance()
        for (offset in 0..7) {
            val candidate = (now.clone() as Calendar).apply {
                add(Calendar.DAY_OF_YEAR, offset)
                set(Calendar.HOUR_OF_DAY, hour)
                set(Calendar.MINUTE, minute)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            if (days.length() > 0) {
                val weekday = if (candidate.get(Calendar.DAY_OF_WEEK) == Calendar.SUNDAY) 7
                    else candidate.get(Calendar.DAY_OF_WEEK) - 1
                if ((0 until days.length()).none { days.optInt(it) == weekday }) continue
            } else if (offset > 0) {
                continue
            }
            if (candidate.timeInMillis > now.timeInMillis) return candidate.timeInMillis
        }
        return null
    }

    private fun requestCode(id: String) = 61000 + (id.hashCode() and 0x0fffffff)
}

class QrAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            QR_ALARM_FIRE -> ring(context, intent.getStringExtra("alarm_id") ?: return)
            QR_ALARM_EMERGENCY -> dismiss(context, intent.getStringExtra("alarm_id") ?: return)
        }
    }

    private fun ring(context: Context, alarmId: String) {
        val alarm = QrAlarmData.alarm(context, alarmId) ?: return
        if (!alarm.optBoolean("enabled", true)) return
        val prefs = context.getSharedPreferences(QR_ALARM_PREFS, Context.MODE_PRIVATE)
        val activeIds = activeAlarmIds(prefs).toMutableSet().apply { add(alarmId) }
        prefs.edit().putString(QR_ACTIVE_ALARMS, JSONArray(activeIds.toList()).toString()).apply()
        showAlarmNotification(context, alarm)
        if (alarm.optJSONArray("weekdays")?.length()?.let { it > 0 } == true) {
            QrAlarmData.schedule(context, alarm)
        } else {
            QrAlarmData.markOneShotConsumed(context, alarmId)
        }
    }

    private fun showAlarmNotification(context: Context, alarm: JSONObject) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(QR_ALARM_CHANNEL, "QR alarms", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "Rings scheduled QR dismissal alarms."
                    enableVibration(true)
                    setSound(android.provider.Settings.System.DEFAULT_ALARM_ALERT_URI,
                        AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build())
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                },
            )
        }
        val id = alarm.optString("id")
        val scanIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra("open_qr_alarm_scan", true)
        }
        val scanPending = scanIntent?.let {
            PendingIntent.getActivity(context, requestCode(id) + 1, it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
        val emergencyIntent = Intent(context, QrAlarmReceiver::class.java)
            .setAction(QR_ALARM_EMERGENCY).putExtra("alarm_id", id)
        val emergencyPending = PendingIntent.getBroadcast(context, requestCode(id) + 2, emergencyIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(context, QR_ALARM_CHANNEL)
            else @Suppress("DEPRECATION") Notification.Builder(context)
        val notification = builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(alarm.optString("label", "QR Alarm"))
            .setContentText("Scan your QR code to dismiss this alarm")
            .setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .apply { if (scanPending != null) setContentIntent(scanPending) }
            .addAction(0, "Scan QR to dismiss", scanPending)
            .addAction(0, "Emergency dismiss", emergencyPending)
            .build()
        manager.notify(requestCode(id), notification)
    }

    private fun dismiss(context: Context, alarmId: String) {
        val prefs = context.getSharedPreferences(QR_ALARM_PREFS, Context.MODE_PRIVATE)
        val activeIds = activeAlarmIds(prefs).toMutableSet()
        if (!activeIds.remove(alarmId)) return
        context.getSystemService(NotificationManager::class.java)?.cancel(requestCode(alarmId))
        saveActiveAlarmIds(prefs, activeIds)
    }

    companion object {
        fun dismissActive(context: Context, qrValue: String?): Boolean {
            val prefs = context.getSharedPreferences(QR_ALARM_PREFS, Context.MODE_PRIVATE)
            val activeIds = activeAlarmIds(prefs)
            val activeId = if (qrValue == null) {
                activeIds.lastOrNull()
            } else {
                activeIds.firstOrNull { id ->
                    val alarm = QrAlarmData.alarm(context, id) ?: return@firstOrNull false
                    val savedValue = alarm.optString("qrValue")
                    val expectedValue = if (savedValue.isNotEmpty()) savedValue else {
                        val token = alarm.optString("qrToken")
                        if (token.isEmpty()) "" else "piqbank://qr-alarm/$id/$token"
                    }
                    qrValue == expectedValue && expectedValue.isNotEmpty()
                }
            }
            if (activeId == null) return false
            context.getSystemService(NotificationManager::class.java)?.cancel(61000 + (activeId.hashCode() and 0x0fffffff))
            saveActiveAlarmIds(prefs, activeIds.filterNot { it == activeId }.toSet())
            return true
        }

        private fun requestCode(id: String) = 61000 + (id.hashCode() and 0x0fffffff)
    }
}

private fun requestCode(id: String) = 61000 + (id.hashCode() and 0x0fffffff)

private fun activeAlarmIds(prefs: android.content.SharedPreferences): List<String> = try {
    val values = JSONArray(prefs.getString(QR_ACTIVE_ALARMS, "[]"))
    (0 until values.length()).mapNotNull { values.optString(it).takeIf(String::isNotEmpty) }
} catch (_: Exception) {
    emptyList()
}

private fun saveActiveAlarmIds(prefs: android.content.SharedPreferences, ids: Set<String>) {
    val editor = prefs.edit()
    if (ids.isEmpty()) editor.remove(QR_ACTIVE_ALARMS)
    else editor.putString(QR_ACTIVE_ALARMS, JSONArray(ids.toList()).toString())
    editor.apply()
}
