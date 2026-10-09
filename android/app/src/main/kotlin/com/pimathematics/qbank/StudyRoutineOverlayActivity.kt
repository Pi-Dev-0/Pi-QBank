package com.pi.mathematics

import android.app.Activity
import android.app.KeyguardManager
import android.app.NotificationManager
import android.content.Context
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.window.OnBackInvokedCallback
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView

class StudyRoutineOverlayActivity : Activity() {

    private var ringtone: Ringtone? = null
    private var vibrator: Vibrator? = null
    private val handler = Handler(Looper.getMainLooper())
    private val stopAlertsRunnable = Runnable { stopAlerts() }
    private val autoDismissRunnable = Runnable { dismissOverlay() }
    private var backCallback: OnBackInvokedCallback? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        configureWindow()
        clearNotification()

        setContentView(R.layout.activity_study_routine_overlay)

        val subject = intent.getStringExtra(EXTRA_SUBJECT) ?: "Study Session"
        val timeRange = intent.getStringExtra(EXTRA_TIME_RANGE) ?: ""
        val duration = intent.getStringExtra(EXTRA_DURATION) ?: ""

        findViewById<TextView>(R.id.overlay_subject).text = subject
        val timeDisplay = if (duration.isNotEmpty()) "$timeRange ($duration)" else timeRange
        findViewById<TextView>(R.id.overlay_time_range).text = timeDisplay

        findViewById<Button>(R.id.overlay_btn_dismiss).setOnClickListener {
            dismissOverlay()
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            backCallback = OnBackInvokedCallback { /* Keep the reminder open until Dismiss. */ }
            onBackInvokedDispatcher.registerOnBackInvokedCallback(
                android.window.OnBackInvokedDispatcher.PRIORITY_DEFAULT,
                backCallback!!,
            )
        }

        startAlerts()
        handler.postDelayed(stopAlertsRunnable, ALERT_DURATION_MS)
        handler.postDelayed(autoDismissRunnable, AUTO_DISMISS_DURATION_MS)
    }

    private fun configureWindow() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
            keyguardManager?.requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    private fun clearNotification() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        manager?.cancel(STUDY_ROUTINE_NOTIFICATION_ID)
    }

    private fun startAlerts() {
        try {
            val alertUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            ringtone = RingtoneManager.getRingtone(applicationContext, alertUri)?.apply {
                play()
            }
        } catch (_: Exception) {}

        try {
            vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                vibratorManager?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            }
            val pattern = longArrayOf(0, 500, 400, 500, 400, 500)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createWaveform(pattern, -1))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(pattern, -1)
            }
        } catch (_: Exception) {}
    }

    private fun stopAlerts() {
        try {
            ringtone?.stop()
            ringtone = null
        } catch (_: Exception) {}
        try {
            vibrator?.cancel()
            vibrator = null
        } catch (_: Exception) {}
    }

    private fun dismissOverlay() {
        stopAlerts()
        clearNotification()
        finish()
    }

    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        // The reminder is dismissed only with its Dismiss button.
    }

    override fun onDestroy() {
        handler.removeCallbacks(stopAlertsRunnable)
        handler.removeCallbacks(autoDismissRunnable)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            backCallback?.let { onBackInvokedDispatcher.unregisterOnBackInvokedCallback(it) }
            backCallback = null
        }
        stopAlerts()
        clearNotification()
        super.onDestroy()
    }

    companion object {
        private const val ALERT_DURATION_MS = 5_000L
        private const val AUTO_DISMISS_DURATION_MS = 5 * 60 * 1000L
        const val EXTRA_SUBJECT = "extra_study_subject"
        const val EXTRA_TIME_RANGE = "extra_study_time_range"
        const val EXTRA_DURATION = "extra_study_duration"
        const val EXTRA_SESSION_ID = "extra_study_session_id"
        const val STUDY_ROUTINE_NOTIFICATION_ID = 74301
    }
}
