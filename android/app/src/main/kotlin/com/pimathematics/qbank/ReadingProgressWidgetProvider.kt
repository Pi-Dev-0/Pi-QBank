package com.pi.mathematics

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

internal const val READING_PROGRESS_PREFERENCES = "FlutterSharedPreferences"
internal const val READING_PROGRESS_KEY = "flutter.physical_book_reading_progress_v1"
internal const val READING_PROGRESS_ACTION = "com.pi.mathematics.READING_WIDGET_ADJUST_PAGE"
internal const val READING_PROGRESS_BOOK_ID = "reading_progress_book_id"
internal const val READING_PROGRESS_PAGE_STEP = "reading_progress_page_step"

class ReadingProgressWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { appWidgetId ->
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action != READING_PROGRESS_ACTION) return

        val bookId = intent.getStringExtra(READING_PROGRESS_BOOK_ID) ?: return
        val pageStep = intent.getIntExtra(READING_PROGRESS_PAGE_STEP, 1)
        val prefs = context.getSharedPreferences(READING_PROGRESS_PREFERENCES, Context.MODE_PRIVATE)
        val records = readRecords(prefs)
        val book = records.firstOrNull { it.optString("id") == bookId } ?: return
        val startPage = book.optInt("startPage", 1).coerceAtLeast(1)
        val currentPage = book.optInt("currentPage", startPage).coerceAtLeast(startPage)
        val totalPages = book.optInt("totalPages", 0)
        val nextPage = (currentPage + pageStep).coerceAtLeast(startPage).let { page ->
            if (totalPages > 0) page.coerceAtMost(totalPages) else page
        }
        book.put("currentPage", nextPage)
        val timestamp = SimpleDateFormat(
            "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
            Locale.US,
        ).apply { timeZone = TimeZone.getTimeZone("UTC") }.format(Date())
        book.put("lastReadAt", timestamp)
        prefs.edit().putString(READING_PROGRESS_KEY, records.toString()).apply()
        refreshAll(context)
    }

    companion object {
        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, ReadingProgressWidgetProvider::class.java)
            val widgetIds = manager.getAppWidgetIds(component)
            widgetIds.forEach { updateWidget(context, manager, it) }
            if (widgetIds.isNotEmpty()) {
                manager.notifyAppWidgetViewDataChanged(widgetIds, R.id.reading_widget_list)
            }
        }

        private fun updateWidget(
            context: Context,
            manager: AppWidgetManager,
            appWidgetId: Int,
        ) {
            val views = RemoteViews(context.packageName, R.layout.reading_progress_widget)
            val adapterIntent = Intent(context, ReadingProgressWidgetRemoteViewsService::class.java)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
            views.setRemoteAdapter(R.id.reading_widget_list, adapterIntent)
            views.setEmptyView(R.id.reading_widget_list, R.id.reading_widget_empty)

            val clickIntent = Intent(context, ReadingProgressWidgetProvider::class.java).apply {
                action = READING_PROGRESS_ACTION
            }
            val clickTemplate = PendingIntent.getBroadcast(
                context,
                appWidgetId,
                clickIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
            )
            views.setPendingIntentTemplate(R.id.reading_widget_list, clickTemplate)
            manager.updateAppWidget(appWidgetId, views)
        }
    }
}

class ReadingProgressWidgetRemoteViewsService : android.widget.RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        ReadingProgressWidgetFactory(applicationContext)
}

private class ReadingProgressWidgetFactory(
    private val context: Context,
) : android.widget.RemoteViewsService.RemoteViewsFactory {
    private var books: List<JSONObject> = emptyList()

    override fun onCreate() = Unit

    override fun onDataSetChanged() {
        val prefs = context.getSharedPreferences(READING_PROGRESS_PREFERENCES, Context.MODE_PRIVATE)
        books = readRecords(prefs).sortedWith(
            compareBy<JSONObject> { it.optString("title").trim().lowercase(Locale.ROOT) }
                .thenBy { it.optString("id") },
        )
    }

    override fun onDestroy() {
        books = emptyList()
    }

    override fun getCount(): Int = books.size

    override fun getViewAt(position: Int): RemoteViews? {
        val book = books.getOrNull(position) ?: return null
        val bookId = book.optString("id")
        val title = book.optString("title", "Untitled book")
        val startPage = book.optInt("startPage", 1).coerceAtLeast(1)
        val currentPage = book.optInt("currentPage", startPage).coerceAtLeast(startPage)
        val totalPages = book.optInt("totalPages", 0)
        val views = RemoteViews(context.packageName, R.layout.reading_progress_widget_item)

        views.setImageViewResource(
            R.id.reading_widget_item_cover,
            R.drawable.reading_widget_book_cover,
        )
        decodeBookCover(book.optString("thumbnailPath").takeIf { it.isNotBlank() })?.let { cover ->
            views.setImageViewBitmap(R.id.reading_widget_item_cover, cover)
        }
        views.setTextViewText(R.id.reading_widget_item_title, title)
        val positionText = when {
            startPage > 1 && totalPages > 0 -> "Page $currentPage ($startPage–$totalPages)"
            startPage > 1 -> "Page $currentPage (Starts $startPage)"
            totalPages > 0 -> "Page $currentPage / $totalPages"
            else -> "Page $currentPage"
        }
        views.setTextViewText(R.id.reading_widget_item_position, positionText)
        val progressViewIds = intArrayOf(
            R.id.reading_widget_item_progress_early,
            R.id.reading_widget_item_progress_mid,
            R.id.reading_widget_item_progress_late,
            R.id.reading_widget_item_progress_done,
        )
        if (totalPages > 0) {
            val percent = if (startPage <= 1) {
                ((currentPage.toDouble() / totalPages) * 100).toInt().coerceIn(0, 100)
            } else if (totalPages <= startPage) {
                100
            } else {
                (((currentPage - startPage).toDouble() / (totalPages - startPage)) * 100).toInt().coerceIn(0, 100)
            }
            val colorAndBar = when {
                percent < 25 -> Pair(Color.rgb(239, 108, 87), progressViewIds[0])
                percent < 50 -> Pair(Color.rgb(242, 164, 58), progressViewIds[1])
                percent < 75 -> Pair(Color.rgb(83, 136, 232), progressViewIds[2])
                else -> Pair(Color.rgb(39, 162, 123), progressViewIds[3])
            }
            views.setProgressBar(colorAndBar.second, 100, percent, false)
            progressViewIds.forEach { viewId ->
                views.setViewVisibility(
                    viewId,
                    if (viewId == colorAndBar.second) View.VISIBLE else View.GONE,
                )
            }
            views.setTextViewText(R.id.reading_widget_item_percent, "$percent%")
            views.setTextColor(R.id.reading_widget_item_percent, colorAndBar.first)
            views.setInt(
                R.id.reading_widget_item_percent,
                "setBackgroundResource",
                when {
                    percent < 25 -> R.drawable.reading_widget_percent_early
                    percent < 50 -> R.drawable.reading_widget_percent_mid
                    percent < 75 -> R.drawable.reading_widget_percent_late
                    else -> R.drawable.reading_widget_percent_done
                },
            )
            views.setViewVisibility(R.id.reading_widget_item_percent, View.VISIBLE)
        } else {
            progressViewIds.forEach { views.setViewVisibility(it, View.GONE) }
            views.setViewVisibility(R.id.reading_widget_item_percent, View.GONE)
        }

        setFillInIntent(views, R.id.reading_widget_item_minus, bookId, -1)
        setFillInIntent(views, R.id.reading_widget_item_plus, bookId, 1)
        setFillInIntent(views, R.id.reading_widget_item_plus_five, bookId, 5)
        return views
    }

    private fun setFillInIntent(views: RemoteViews, viewId: Int, bookId: String, step: Int) {
        val fillInIntent = Intent()
            .putExtra(READING_PROGRESS_BOOK_ID, bookId)
            .putExtra(READING_PROGRESS_PAGE_STEP, step)
        views.setOnClickFillInIntent(viewId, fillInIntent)
    }

    private fun decodeBookCover(path: String?): Bitmap? {
        if (path == null) return null
        return try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, bounds)
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

            var sampleSize = 1
            while (bounds.outWidth / sampleSize > 144 || bounds.outHeight / sampleSize > 192) {
                sampleSize *= 2
            }
            BitmapFactory.decodeFile(
                path,
                BitmapFactory.Options().apply { inSampleSize = sampleSize },
            )
        } catch (_: Exception) {
            null
        }
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long =
        books.getOrNull(position)?.optString("id")?.hashCode()?.toLong() ?: position.toLong()

    override fun hasStableIds(): Boolean = true
}

private fun readRecords(prefs: android.content.SharedPreferences): MutableList<JSONObject> {
    val raw = prefs.getString(READING_PROGRESS_KEY, null) ?: return mutableListOf()
    return try {
        val array = JSONArray(raw)
        MutableList(array.length()) { index -> array.getJSONObject(index) }
    } catch (_: Exception) {
        mutableListOf()
    }
}
