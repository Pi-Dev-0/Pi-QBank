package com.pi.mathematics

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.provider.Settings

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.pimathematics.qbank/settings"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
            call, result ->
            when (call.method) {
                "openWifiSettings" -> {
                    try {
                        val panelIntent = Intent(Settings.Panel.ACTION_INTERNET_CONNECTIVITY)
                        startActivity(panelIntent)
                        result.success(null)
                    } catch (e: Exception) {
                        try {
                            // Fallback for older Android versions
                            val settingsIntent = Intent(Settings.ACTION_WIFI_SETTINGS)
                            settingsIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            startActivity(settingsIntent)
                            result.success(null)
                        } catch (e2: Exception) {
                            result.error("ERROR", "Failed to open settings", null)
                        }
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
