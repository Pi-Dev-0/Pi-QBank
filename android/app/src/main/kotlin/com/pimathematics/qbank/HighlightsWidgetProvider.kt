package com.pi.mathematics

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject

internal const val HIGHLIGHTS_WIDGET_ACTION_OPEN =
    "com.pi.mathematics.OPEN_HIGHLIGHT_FROM_WIDGET"
internal const val HIGHLIGHTS_WIDGET_ACTION_REFRESH =
    "com.pi.mathematics.REFRESH_HIGHLIGHTS_WIDGET"
internal const val HIGHLIGHTS_WIDGET_ACTION_LOAD_MORE =
    "com.pi.mathematics.LOAD_MORE_HIGHLIGHTS_WIDGET"
internal const val HIGHLIGHTS_WIDGET_EXTRA_URL = "highlights_widget_url"
internal const val HIGHLIGHTS_WIDGET_EXTRA_TITLE = "highlights_widget_title"
internal const val HIGHLIGHTS_WIDGET_EXTRA_SOURCE = "highlights_widget_source"

/**
 * Home-screen "Highlights" widget.
 *
 * Shows recent headlines fetched from Bangladeshi news RSS feeds
 * (see [NewsHighlightsFetcher]). Tapping a headline opens the article
 * inside the app.
 */
class HighlightsWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        manager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { updateWidget(context, manager, it) }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            HIGHLIGHTS_WIDGET_ACTION_OPEN -> {
                val url = intent.getStringExtra(HIGHLIGHTS_WIDGET_EXTRA_URL) ?: return
                val title = intent.getStringExtra(HIGHLIGHTS_WIDGET_EXTRA_TITLE) ?: ""
                val source = intent.getStringExtra(HIGHLIGHTS_WIDGET_EXTRA_SOURCE) ?: ""

                val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                    ?: return
                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                launchIntent.putExtra(HIGHLIGHTS_WIDGET_EXTRA_URL, url)
                launchIntent.putExtra(HIGHLIGHTS_WIDGET_EXTRA_TITLE, title)
                launchIntent.putExtra(HIGHLIGHTS_WIDGET_EXTRA_SOURCE, source)
                context.startActivity(launchIntent)
            }
            HIGHLIGHTS_WIDGET_ACTION_REFRESH -> {
                // Trigger a background refresh of the headlines
                NewsHighlightsFetcher.refresh(context)
            }
            HIGHLIGHTS_WIDGET_ACTION_LOAD_MORE -> {
                // Load more headlines
                NewsHighlightsFetcher.loadMore(context)
            }
        }
    }

    companion object {
        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, HighlightsWidgetProvider::class.java)
            val ids = manager.getAppWidgetIds(component)
            ids.forEach { updateWidget(context, manager, it) }
            if (ids.isNotEmpty()) {
                manager.notifyAppWidgetViewDataChanged(ids, R.id.highlights_widget_list)
            }
        }

        private fun updateWidget(context: Context, manager: AppWidgetManager, id: Int) {
            val views = RemoteViews(context.packageName, R.layout.highlights_widget)
            val adapterIntent = Intent(context, HighlightsWidgetRemoteViewsService::class.java)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
            views.setRemoteAdapter(R.id.highlights_widget_list, adapterIntent)
            views.setEmptyView(R.id.highlights_widget_list, R.id.highlights_widget_empty)

            // Refresh button (top-right)
            val refreshIntent = Intent(context, HighlightsWidgetProvider::class.java).apply {
                action = HIGHLIGHTS_WIDGET_ACTION_REFRESH
            }
            val refreshPendingIntent = PendingIntent.getBroadcast(
                context,
                id + 30000,
                refreshIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.highlights_widget_refresh, refreshPendingIntent)

            // Load More button (bottom)
            val loadMoreIntent = Intent(context, HighlightsWidgetProvider::class.java).apply {
                action = HIGHLIGHTS_WIDGET_ACTION_LOAD_MORE
            }
            val loadMorePendingIntent = PendingIntent.getBroadcast(
                context,
                id + 40000,
                loadMoreIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.highlights_widget_load_more, loadMorePendingIntent)

            // Headline tap → open article in app
            val openIntent = Intent(context, HighlightsWidgetProvider::class.java).apply {
                action = HIGHLIGHTS_WIDGET_ACTION_OPEN
            }
            val template = PendingIntent.getBroadcast(
                context,
                id + 10000,
                openIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
            )
            views.setPendingIntentTemplate(R.id.highlights_widget_list, template)
            manager.updateAppWidget(id, views)
        }
    }
}

class HighlightsWidgetRemoteViewsService : android.widget.RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        HighlightsWidgetFactory(applicationContext)
}

private class HighlightsWidgetFactory(
    private val context: Context,
) : android.widget.RemoteViewsService.RemoteViewsFactory {

    private var headlines: List<NewsHighlightsFetcher.Headline> = emptyList()

    override fun onCreate() = Unit

    override fun onDataSetChanged() {
        // This runs on a background thread, so reading the cache is safe.
        headlines = NewsHighlightsFetcher.getCachedHeadlines(context)
    }

    override fun onDestroy() {
        headlines = emptyList()
    }

    override fun getCount(): Int = headlines.size

    override fun getViewAt(position: Int): RemoteViews? {
        val headline = headlines.getOrNull(position) ?: return null
        val views = RemoteViews(context.packageName, R.layout.highlights_widget_item)
        views.setTextViewText(R.id.highlights_widget_item_title, headline.title)
        val sourceLabel = if (headline.source.isNotBlank()) headline.source else {
            try {
                Uri.parse(headline.link).host ?: ""
            } catch (_: Exception) {
                ""
            }
        }
        views.setTextViewText(R.id.highlights_widget_item_source, sourceLabel)

        val fillInIntent = Intent()
            .putExtra(HIGHLIGHTS_WIDGET_EXTRA_URL, headline.link)
            .putExtra(HIGHLIGHTS_WIDGET_EXTRA_TITLE, headline.title)
            .putExtra(HIGHLIGHTS_WIDGET_EXTRA_SOURCE, headline.source)
        views.setOnClickFillInIntent(R.id.highlights_widget_item_root, fillInIntent)
        return views
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long =
        headlines.getOrNull(position)?.link?.hashCode()?.toLong()
            ?: position.toLong()

    override fun hasStableIds(): Boolean = true
}
