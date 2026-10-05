package com.pi.mathematics

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.app.Activity
import android.app.AlertDialog
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.util.Base64
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject

private const val SINGLE_NEWSPAPER_WIDGET_ACTION =
    "com.pi.mathematics.OPEN_SINGLE_NEWSPAPER_WIDGET"

class SingleNewspaperWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        manager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { updateWidget(context, manager, it) }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action != SINGLE_NEWSPAPER_WIDGET_ACTION) return

        val widgetId = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, -1)
        val prefs = context.getSharedPreferences(READING_PROGRESS_PREFERENCES, Context.MODE_PRIVATE)
        val selectedUrl = prefs.getString(selectionKey(widgetId), null) ?: return
        val channel = readNewspapers(context).firstOrNull { it.optString("url") == selectedUrl }
            ?: return
        val name = channel.optString("name", "Newspaper")
        val url = channel.optString("url")
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: return
        launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        launchIntent.putExtra(NEWSPAPER_WIDGET_EXTRA_NAME, name)
        launchIntent.putExtra(NEWSPAPER_WIDGET_EXTRA_URL, url)
        context.startActivity(launchIntent)
    }

    companion object {
        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, SingleNewspaperWidgetProvider::class.java)
            manager.getAppWidgetIds(component).forEach { updateWidget(context, manager, it) }
        }

        private fun updateWidget(context: Context, manager: AppWidgetManager, id: Int) {
            val views = RemoteViews(context.packageName, R.layout.single_newspaper_widget)
            val channel = selectedNewspaper(context, id)
            if (channel == null) {
                val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
                if (launch != null) {
                    val pending = PendingIntent.getActivity(
                        context,
                        id + 20000,
                        launch,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                    )
                    views.setOnClickPendingIntent(R.id.single_newspaper_widget_root, pending)
                }
            } else {
                val encodedIcon = channel.optString("iconBase64")
                if (encodedIcon.isNotBlank()) {
                    try {
                        val iconBytes = Base64.decode(encodedIcon, Base64.DEFAULT)
                        val icon = BitmapFactory.decodeByteArray(iconBytes, 0, iconBytes.size)
                        if (icon != null) {
                            views.setImageViewBitmap(R.id.single_newspaper_widget_icon, icon)
                        }
                    } catch (_: IllegalArgumentException) {
                        // Keep the app icon if cached favicon bytes cannot be decoded.
                    }
                }
                val open = Intent(context, SingleNewspaperWidgetProvider::class.java).apply {
                    action = SINGLE_NEWSPAPER_WIDGET_ACTION
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
                }
                val pending = PendingIntent.getBroadcast(
                    context,
                    id + 20000,
                    open,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
                views.setOnClickPendingIntent(R.id.single_newspaper_widget_root, pending)
            }
            manager.updateAppWidget(id, views)
        }

        private fun selectedNewspaper(context: Context, widgetId: Int): JSONObject? {
            val prefs = context.getSharedPreferences(READING_PROGRESS_PREFERENCES, Context.MODE_PRIVATE)
            val selectedUrl = prefs.getString(selectionKey(widgetId), null) ?: return null
            return readNewspapers(context).firstOrNull { it.optString("url") == selectedUrl }
        }
    }
}

private fun selectionKey(widgetId: Int) = "flutter.single_newspaper_widget_url_$widgetId"

private fun readNewspapers(context: Context): List<JSONObject> {
    val prefs = context.getSharedPreferences(READING_PROGRESS_PREFERENCES, Context.MODE_PRIVATE)
    val raw = prefs.getString(NEWSPAPER_WIDGET_DATA_KEY, null) ?: return emptyList()
    return try {
        val newspapers = JSONArray(raw)
        (0 until newspapers.length())
            .map { newspapers.getJSONObject(it) }
            .filter { it.optString("url").isNotBlank() }
            .sortedWith(
                compareByDescending<JSONObject> { it.optBoolean("favorite", false) }
                    .thenBy { it.optString("name").lowercase() },
            )
    } catch (_: Exception) {
        emptyList()
    }
}

class SingleNewspaperWidgetConfigureActivity : Activity() {
    private var widgetId = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(RESULT_CANCELED)
        widgetId = intent.getIntExtra(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        )
        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        val newspapers = readNewspapers(this)
        if (newspapers.isEmpty()) {
            AlertDialog.Builder(this)
                .setTitle("Choose a newspaper")
                .setMessage("Open the Newspapers page in Pi-QBank while online, then add this widget again.")
                .setPositiveButton(android.R.string.ok) { _, _ -> finish() }
                .setOnCancelListener { finish() }
                .show()
            return
        }

        val names = newspapers.map { newspaper ->
            val name = newspaper.optString("name", "Newspaper")
            if (newspaper.optBoolean("favorite", false)) "★ $name" else name
        }.toTypedArray()
        AlertDialog.Builder(this)
            .setTitle("Choose a newspaper")
            .setItems(names) { _, index ->
                getSharedPreferences(READING_PROGRESS_PREFERENCES, Context.MODE_PRIVATE)
                    .edit()
                    .putString(selectionKey(widgetId), newspapers[index].optString("url"))
                    .apply()
                SingleNewspaperWidgetProvider.refreshAll(this)
                val result = Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
                setResult(RESULT_OK, result)
                finish()
            }
            .setOnCancelListener { finish() }
            .show()
    }
}
