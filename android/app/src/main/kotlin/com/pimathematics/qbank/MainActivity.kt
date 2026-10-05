package com.pi.mathematics

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.Manifest
import android.content.pm.PackageManager
import android.os.Build

class MainActivity : FlutterActivity() {
    private var newspaperWidgetChannel: MethodChannel? = null
    private var studyTimerWidgetChannel: MethodChannel? = null
    private var studyRoutineWidgetChannel: MethodChannel? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.pi.mathematics/reading_progress_widget"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "refresh" -> {
                    ReadingProgressWidgetProvider.refreshAll(applicationContext)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        newspaperWidgetChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.pi.mathematics/newspaper_widget"
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "refresh" -> {
                        NewspaperWidgetProvider.refreshAll(applicationContext)
                        result.success(null)
                    }
                    "consumeNewspaperRequest" -> result.success(consumeNewspaperRequest(intent))
                    else -> result.notImplemented()
                }
            }
        }

        studyRoutineWidgetChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.pi.mathematics/study_routine"
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "syncRoutine" -> {
                        val routine = call.arguments as? String
                        if (routine == null) {
                            result.error("invalid_routine", "Routine data is missing", null)
                        } else {
                            getSharedPreferences(STUDY_ROUTINE_PREFS, MODE_PRIVATE)
                                .edit()
                                .putString(STUDY_ROUTINE_KEY, routine)
                                .putBoolean(STUDY_ROUTINE_ENABLED_KEY, true)
                                .apply()
                            StudyRoutineData.reschedule(applicationContext)
                            StudyRoutineWidgetProvider.refreshAll(applicationContext)
                            result.success(null)
                        }
                    }
                    "requestNotificationPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                            PackageManager.PERMISSION_GRANTED) {
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 74302)
                        }
                        result.success(null)
                    }
                    "consumeStudyRoutineRequest" -> result.success(consumeStudyRoutineRequest(intent))
                    else -> result.notImplemented()
                }
            }
        }

        studyTimerWidgetChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.pi.mathematics/study_timer_widget"
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "consumeStudyTimerReport" -> result.success(consumeStudyTimerReport(intent))
                    else -> result.notImplemented()
                }
            }
        }

    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val request = readNewspaperRequest(intent)
        if (request != null) {
            newspaperWidgetChannel?.invokeMethod("openNewspaper", request, object : MethodChannel.Result {
                override fun success(result: Any?) {
                    clearNewspaperRequest(intent)
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = Unit

                override fun notImplemented() = Unit
            })
        }
        if (intent.getBooleanExtra("open_study_timer_report", false)) {
            studyTimerWidgetChannel?.invokeMethod("openStudyTimerReport", null, object : MethodChannel.Result {
                override fun success(result: Any?) {
                    intent.removeExtra("open_study_timer_report")
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = Unit

                override fun notImplemented() = Unit
            })
        }
        if (intent.getBooleanExtra("open_study_routine", false)) {
            studyRoutineWidgetChannel?.invokeMethod("openStudyRoutine", null, object : MethodChannel.Result {
                override fun success(result: Any?) {
                    intent.removeExtra("open_study_routine")
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = Unit

                override fun notImplemented() = Unit
            })
        }
    }

    private fun consumeNewspaperRequest(sourceIntent: Intent?): Map<String, String>? {
        val request = readNewspaperRequest(sourceIntent) ?: return null
        clearNewspaperRequest(sourceIntent)
        return request
    }

    private fun readNewspaperRequest(sourceIntent: Intent?): Map<String, String>? {
        sourceIntent ?: return null
        val name = sourceIntent.getStringExtra(NEWSPAPER_WIDGET_EXTRA_NAME) ?: return null
        val url = sourceIntent.getStringExtra(NEWSPAPER_WIDGET_EXTRA_URL) ?: return null
        return mapOf("name" to name, "url" to url)
    }

    private fun clearNewspaperRequest(sourceIntent: Intent?) {
        sourceIntent?.removeExtra(NEWSPAPER_WIDGET_EXTRA_NAME)
        sourceIntent?.removeExtra(NEWSPAPER_WIDGET_EXTRA_URL)
    }

    private fun consumeStudyTimerReport(sourceIntent: Intent?): Boolean {
        if (sourceIntent?.getBooleanExtra("open_study_timer_report", false) != true) return false
        sourceIntent.removeExtra("open_study_timer_report")
        return true
    }

    private fun consumeStudyRoutineRequest(sourceIntent: Intent?): Boolean {
        if (sourceIntent?.getBooleanExtra("open_study_routine", false) != true) return false
        sourceIntent.removeExtra("open_study_routine")
        return true
    }

}
