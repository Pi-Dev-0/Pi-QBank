package com.pi.mathematics

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import android.app.AlarmManager
import android.app.NotificationManager
import android.print.PrintAttributes
import android.print.PrintManager
import android.util.Log
import android.webkit.WebView
import android.webkit.WebViewClient
import android.os.Handler
import android.os.Looper

class MainActivity : FlutterActivity() {
    private var newspaperWidgetChannel: MethodChannel? = null
    private var studyTimerWidgetChannel: MethodChannel? = null
    private var studyRoutineWidgetChannel: MethodChannel? = null
    private var overlayPermissionResult: MethodChannel.Result? = null
    private var awaitingOverlayPermission = false
    private var specialAccessResult: MethodChannel.Result? = null
    private var specialAccessKind: String? = null
    private var notificationPermissionResult: MethodChannel.Result? = null
    private var pendingNewspaperRequest: Map<String, String>? = null
    private val printWebViews = mutableListOf<WebView>()

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        // Capture newspaper request from the launch intent so onResume can
        // forward it to Flutter once the engine is ready.
        pendingNewspaperRequest = readNewspaperRequest(intent)
    }

    override fun onDestroy() {
        printWebViews.forEach { webView ->
            webView.stopLoading()
            webView.destroy()
        }
        printWebViews.clear()
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.pi.mathematics/print_preview"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "printHtml" -> {
                    val arguments = call.arguments
                    val html = when (arguments) {
                        is String -> arguments
                        is Map<*, *> -> arguments["html"] as? String
                        else -> null
                    }
                    val paperSize = (arguments as? Map<*, *>)?.get("paperSize") as? String
                        ?: "A4"
                    if (html.isNullOrBlank()) {
                        result.error("invalid_html", "Print HTML is empty", null)
                    } else {
                        printHtml(html, paperSize, result)
                    }
                }
                else -> result.notImplemented()
            }
        }
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
                        NewsHighlightsFetcher.refresh(applicationContext)
                        result.success(null)
                    }
                    "consumeNewsArticleRequest" -> result.success(consumeNewsArticleRequest(intent))
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
                                .apply()
                            StudyRoutineData.reschedule(applicationContext)
                            StudyRoutineWidgetProvider.refreshAll(applicationContext)
                            result.success(null)
                        }
                    }
                    "setRemindersEnabled" -> {
                        val enabled = call.arguments as? Boolean
                        if (enabled == null) {
                            result.error("invalid_reminder_state", "Reminder state is missing", null)
                        } else {
                            getSharedPreferences(STUDY_ROUTINE_PREFS, MODE_PRIVATE)
                                .edit()
                                .putBoolean(STUDY_ROUTINE_ENABLED_KEY, enabled)
                                .apply()
                            StudyRoutineData.reschedule(applicationContext)
                            result.success(null)
                        }
                    }
                    "requestNotificationPermission" -> {
                        requestNotificationPermission(result)
                    }
                    "requestOverlayPermission" -> requestOverlayPermission(result)
                    "requestExactAlarmPermission" -> requestSpecialAccess("exact_alarm", result)
                    "requestFullScreenIntentPermission" -> requestSpecialAccess("full_screen_intent", result)
                    "refreshWidget" -> {
                        StudyRoutineWidgetProvider.refreshAll(applicationContext)
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
                    "refresh" -> {
                        StudyTimerWidgetProvider.refreshAll(applicationContext)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }

    }

    /** Loads the preview in a print-capable WebView and opens Android's printer UI. */
    private fun printHtml(html: String, paperSize: String, result: MethodChannel.Result) {
        val printWebView = WebView(this)
        printWebViews.add(printWebView)
        printWebView.settings.javaScriptEnabled = true
        printWebView.settings.loadsImagesAutomatically = true
        printWebView.settings.domStorageEnabled = true
        var printed = false
        printWebView.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView, url: String) {
                if (printed) return
                printed = true
                // Give web fonts and remote images a moment to finish before
                // Android snapshots the document for the print adapter.
                Handler(Looper.getMainLooper()).postDelayed({
                    try {
                        val printManager = getSystemService(PRINT_SERVICE) as PrintManager
                        val adapter = view.createPrintDocumentAdapter("Pi-QBank Question Paper")
                        val attributes = PrintAttributes.Builder()
                            .setMediaSize(mediaSizeFor(paperSize))
                            .setResolution(PrintAttributes.Resolution("qbank", "Pi-QBank", 300, 300))
                            .setMinMargins(PrintAttributes.Margins.NO_MARGINS)
                            .build()
                        printManager.print("Pi-QBank Question Paper", adapter, attributes)
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("print_failed", error.message, null)
                    }
                }, 700)
            }
        }
        printWebView.loadDataWithBaseURL(
            "https://pi-qbank.local/",
            html,
            "text/html",
            "UTF-8",
            null,
        )
    }

    private fun mediaSizeFor(paperSize: String): PrintAttributes.MediaSize {
        return when (paperSize.uppercase()) {
            "A3" -> PrintAttributes.MediaSize.ISO_A3
            "A5" -> PrintAttributes.MediaSize.ISO_A5
            "LETTER" -> PrintAttributes.MediaSize.NA_LETTER
            "LEGAL" -> PrintAttributes.MediaSize.NA_LEGAL
            else -> PrintAttributes.MediaSize.ISO_A4
        }
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }
        notificationPermissionResult = result
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 74302)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 74302) {
            notificationPermissionResult?.success(
                grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED,
            )
            notificationPermissionResult = null
        }
    }

    override fun onResume() {
        super.onResume()
        if (awaitingOverlayPermission) {
            awaitingOverlayPermission = false
            val granted = Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
                Settings.canDrawOverlays(this)
            overlayPermissionResult?.success(granted)
            overlayPermissionResult = null
        }
        specialAccessKind?.let { kind ->
            val granted = when (kind) {
                "exact_alarm" -> Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
                    getSystemService(AlarmManager::class.java)?.canScheduleExactAlarms() == true
                "full_screen_intent" -> Build.VERSION.SDK_INT < 34 ||
                    getSystemService(NotificationManager::class.java)?.canUseFullScreenIntent() == true
                else -> false
            }
            specialAccessKind = null
            specialAccessResult?.success(granted)
            specialAccessResult = null
        }
        StudyRoutineWidgetProvider.refreshAll(applicationContext)
        refreshHighlightsIfNeeded()
        // Handle newspaper request from widget when app is launched fresh
        pendingNewspaperRequest?.let { request ->
            pendingNewspaperRequest = null
            newspaperWidgetChannel?.invokeMethod("openNewspaper", request, object : MethodChannel.Result {
                override fun success(result: Any?) {
                    clearNewspaperRequest(intent)
                }
                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = Unit
                override fun notImplemented() = Unit
            })
        }
    }

    /**
     * Fetches fresh headlines from BD news RSS feeds when the cache is stale.
     * Runs in the background; the widget updates when caching completes.
     */
    private fun refreshHighlightsIfNeeded() {
        try {
            val prefs = getSharedPreferences(READING_PROGRESS_PREFERENCES, MODE_PRIVATE)
            val lastFetch = prefs.getLong("news_highlights_last_fetch", 0L)
            val now = System.currentTimeMillis()
            // Refresh at most every 30 minutes while the app is in use.
            if (now - lastFetch > 30 * 60 * 1000L) {
                prefs.edit().putLong("news_highlights_last_fetch", now).apply()
                NewsHighlightsFetcher.refresh(applicationContext)
            }
        } catch (error: Exception) {
            Log.w("MainActivity", "Highlights refresh failed: ${error.message}")
        }
    }

    private fun requestSpecialAccess(kind: String, result: MethodChannel.Result) {
        val alreadyAllowed = when (kind) {
            "exact_alarm" -> Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
                getSystemService(AlarmManager::class.java)?.canScheduleExactAlarms() == true
            "full_screen_intent" -> Build.VERSION.SDK_INT < 34 ||
                getSystemService(NotificationManager::class.java)?.canUseFullScreenIntent() == true
            else -> false
        }
        if (alreadyAllowed) {
            result.success(true)
            return
        }
        val settingsIntent = when (kind) {
            "exact_alarm" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                    .setData(android.net.Uri.parse("package:$packageName"))
            } else null
            "full_screen_intent" -> if (Build.VERSION.SDK_INT >= 34) {
                Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT)
                    .setData(android.net.Uri.parse("package:$packageName"))
            } else null
            else -> null
        }
        if (settingsIntent == null) {
            result.success(false)
            return
        }
        specialAccessResult = result
        specialAccessKind = kind
        try {
            startActivity(settingsIntent)
        } catch (error: Exception) {
            specialAccessKind = null
            specialAccessResult = null
            result.success(false)
        }
    }

    private fun requestOverlayPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(this)) {
            result.success(true)
            return
        }
        overlayPermissionResult = result
        awaitingOverlayPermission = true
        try {
            startActivity(
                Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION)
                    .setData(android.net.Uri.parse("package:$packageName")),
            )
        } catch (error: Exception) {
            awaitingOverlayPermission = false
            overlayPermissionResult = null
            result.error("overlay_settings_unavailable", error.message, null)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val request = readNewspaperRequest(intent)
        if (request != null) {
            pendingNewspaperRequest = request
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
        val highlightUrl = intent.getStringExtra(HIGHLIGHTS_WIDGET_EXTRA_URL)
        if (highlightUrl != null) {
            val highlightRequest = mapOf(
                "url" to highlightUrl,
                "title" to (intent.getStringExtra(HIGHLIGHTS_WIDGET_EXTRA_TITLE) ?: ""),
                "source" to (intent.getStringExtra(HIGHLIGHTS_WIDGET_EXTRA_SOURCE) ?: ""),
            )
            newspaperWidgetChannel?.invokeMethod("openNewsArticle", highlightRequest, object : MethodChannel.Result {
                override fun success(result: Any?) {
                    intent.removeExtra(HIGHLIGHTS_WIDGET_EXTRA_URL)
                    intent.removeExtra(HIGHLIGHTS_WIDGET_EXTRA_TITLE)
                    intent.removeExtra(HIGHLIGHTS_WIDGET_EXTRA_SOURCE)
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

    private fun consumeNewsArticleRequest(sourceIntent: Intent?): Map<String, String>? {
        val request = readNewsArticleRequest(sourceIntent) ?: return null
        clearNewsArticleRequest(sourceIntent)
        return request
    }

    private fun readNewsArticleRequest(sourceIntent: Intent?): Map<String, String>? {
        sourceIntent ?: return null
        val url = sourceIntent.getStringExtra(HIGHLIGHTS_WIDGET_EXTRA_URL) ?: return null
        val title = sourceIntent.getStringExtra(HIGHLIGHTS_WIDGET_EXTRA_TITLE) ?: ""
        val source = sourceIntent.getStringExtra(HIGHLIGHTS_WIDGET_EXTRA_SOURCE) ?: ""
        return mapOf("url" to url, "title" to title, "source" to source)
    }

    private fun clearNewsArticleRequest(sourceIntent: Intent?) {
        sourceIntent?.removeExtra(HIGHLIGHTS_WIDGET_EXTRA_URL)
        sourceIntent?.removeExtra(HIGHLIGHTS_WIDGET_EXTRA_TITLE)
        sourceIntent?.removeExtra(HIGHLIGHTS_WIDGET_EXTRA_SOURCE)
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
