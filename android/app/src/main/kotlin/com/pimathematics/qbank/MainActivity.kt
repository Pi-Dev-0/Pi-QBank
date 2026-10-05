package com.pi.mathematics

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent

class MainActivity : FlutterActivity() {
    private var newspaperWidgetChannel: MethodChannel? = null

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
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val request = readNewspaperRequest(intent) ?: return
        val channel = newspaperWidgetChannel ?: return
        channel.invokeMethod("openNewspaper", request, object : MethodChannel.Result {
            override fun success(result: Any?) {
                clearNewspaperRequest(intent)
            }

            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = Unit

            override fun notImplemented() = Unit
        })
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
}
