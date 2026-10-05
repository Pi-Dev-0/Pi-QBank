package com.pi.mathematics

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject

internal const val NEWSPAPER_WIDGET_DATA_KEY = "flutter.newspaper_widget_channels_v1"
internal const val NEWSPAPER_WIDGET_ACTION_OPEN = "com.pi.mathematics.OPEN_NEWSPAPER_FROM_WIDGET"
internal const val NEWSPAPER_WIDGET_EXTRA_NAME = "newspaper_widget_name"
internal const val NEWSPAPER_WIDGET_EXTRA_URL = "newspaper_widget_url"

class NewspaperWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        manager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { updateWidget(context, manager, it) }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action != NEWSPAPER_WIDGET_ACTION_OPEN) return

        val name = intent.getStringExtra(NEWSPAPER_WIDGET_EXTRA_NAME) ?: return
        val url = intent.getStringExtra(NEWSPAPER_WIDGET_EXTRA_URL) ?: return
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
            val component = ComponentName(context, NewspaperWidgetProvider::class.java)
            val ids = manager.getAppWidgetIds(component)
            ids.forEach { updateWidget(context, manager, it) }
            if (ids.isNotEmpty()) {
                manager.notifyAppWidgetViewDataChanged(ids, R.id.newspaper_widget_list)
            }
            SingleNewspaperWidgetProvider.refreshAll(context)
        }

        private fun updateWidget(context: Context, manager: AppWidgetManager, id: Int) {
            val views = RemoteViews(context.packageName, R.layout.newspaper_widget)
            val adapterIntent = Intent(context, NewspaperWidgetRemoteViewsService::class.java)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
            views.setRemoteAdapter(R.id.newspaper_widget_list, adapterIntent)
            views.setEmptyView(R.id.newspaper_widget_list, R.id.newspaper_widget_empty)

            val openIntent = Intent(context, NewspaperWidgetProvider::class.java).apply {
                action = NEWSPAPER_WIDGET_ACTION_OPEN
            }
            val template = PendingIntent.getBroadcast(
                context,
                id + 10000,
                openIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
            )
            views.setPendingIntentTemplate(R.id.newspaper_widget_list, template)
            manager.updateAppWidget(id, views)
        }
    }
}

class NewspaperWidgetRemoteViewsService : android.widget.RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        NewspaperWidgetFactory(applicationContext)
}

private class NewspaperWidgetFactory(
    private val context: Context,
) : android.widget.RemoteViewsService.RemoteViewsFactory {
    private var channels: List<JSONObject> = emptyList()

    override fun onCreate() = Unit

    override fun onDataSetChanged() {
        val prefs = context.getSharedPreferences(READING_PROGRESS_PREFERENCES, Context.MODE_PRIVATE)
        val raw = prefs.getString(NEWSPAPER_WIDGET_DATA_KEY, null)
        channels = try {
            if (raw.isNullOrBlank()) {
                emptyList()
            } else {
                val array = JSONArray(raw)
                MutableList(array.length()) { index -> array.getJSONObject(index) }
                    .sortedWith(
                        compareByDescending<JSONObject> { it.optBoolean("favorite", false) }
                            .thenBy { it.optString("name").lowercase() },
                    )
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    override fun onDestroy() {
        channels = emptyList()
    }

    override fun getCount(): Int = channels.size

    override fun getViewAt(position: Int): RemoteViews? {
        val channel = channels.getOrNull(position) ?: return null
        val name = channel.optString("name", "Newspaper")
        val url = channel.optString("url")
        val host = try {
            android.net.Uri.parse(url).host ?: url
        } catch (_: Exception) {
            url
        }
        val views = RemoteViews(context.packageName, R.layout.newspaper_widget_item)
        views.setTextViewText(R.id.newspaper_widget_item_name, name)
        views.setTextViewText(R.id.newspaper_widget_item_host, host)
        views.setTextViewText(
            R.id.newspaper_widget_item_badge,
            if (channel.optBoolean("favorite", false)) "★ Favorite" else "Read",
        )
        val fillInIntent = Intent()
            .putExtra(NEWSPAPER_WIDGET_EXTRA_NAME, name)
            .putExtra(NEWSPAPER_WIDGET_EXTRA_URL, url)
        views.setOnClickFillInIntent(R.id.newspaper_widget_item_root, fillInIntent)
        return views
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long =
        channels.getOrNull(position)?.optString("url")?.hashCode()?.toLong()
            ?: position.toLong()

    override fun hasStableIds(): Boolean = true
}
