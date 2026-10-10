package com.pi.mathematics

import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.StringReader
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/**
 * Fetches and parses recent headlines from Bangladeshi news RSS feeds.
 * Caches the result in SharedPreferences so the home-screen widget can
 * display headlines without needing a network connection.
 *
 * Strategy:
 * 1. Try direct BD news RSS feeds (Prothom Alo, The Daily Star, etc.)
 * 2. Fall back to Google News RSS for Bangladesh if direct feeds fail
 * 3. Use lenient parsing to handle malformed XML common in BD feeds
 */
object NewsHighlightsFetcher {

    private const val TAG = "NewsHighlightsFetcher"
    private const val PREFS_KEY = "news_highlights_cache_v1"
    private const val MAX_HEADLINES = 25

    // Prioritized Bengali BD news feeds. Each entry: Pair<displayName, feedUrl>
    private val PRIORITIZED_FEEDS = listOf(
        "Daily Amar Desh" to "https://www.dailyamardesh.com/feed",
        "Prothom Alo" to "https://www.prothomalo.com/stories.rss",
        "Google News বাংলা" to "https://news.google.com/rss?hl=bn&gl=BD&ceid=BD:bn",
        "Dhaka Post" to "https://news.google.com/rss/search?q=site:dhakapost.com&hl=bn&gl=BD&ceid=BD:bn",
        "The Daily Campus" to "https://news.google.com/rss/search?q=site:thedailycampus.com&hl=bn&gl=BD&ceid=BD:bn",
    )

    data class Headline(
        val title: String,
        val link: String,
        val source: String,
    )

    /** Returns cached headlines from SharedPreferences, or empty list if none. */
    fun getCachedHeadlines(context: Context): List<Headline> {
        val prefs = context.getSharedPreferences(READING_PROGRESS_PREFERENCES, Context.MODE_PRIVATE)
        val raw = prefs.getString(PREFS_KEY, null) ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).mapNotNull { index ->
                val obj = array.optJSONObject(index) ?: return@mapNotNull null
                val title = obj.optString("title")
                val link = obj.optString("link")
                val source = obj.optString("source")
                if (title.isNotBlank() && link.isNotBlank()) {
                    Headline(title, link, source)
                } else {
                    null
                }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    /** Fetches headlines from all feeds in the background and updates the cache. */
    fun refresh(context: Context) {
        val appContext = context.applicationContext
        Executors.newSingleThreadExecutor().execute {
            val headlines = fetchAllFeeds()
            // Always save the cache (even if empty) so the widget knows
            // the fetch completed and doesn't show stale "loading" state.
            saveCache(appContext, headlines)
            // Notify the widget to refresh
            HighlightsWidgetProvider.refreshAll(appContext)
        }
    }

    /**
     * Loads more headlines by fetching from all feeds and appending
     * new items (excluding those already cached) to the existing cache.
     */
    fun loadMore(context: Context) {
        val appContext = context.applicationContext
        Executors.newSingleThreadExecutor().execute {
            val existing = getCachedHeadlines(appContext)
            val existingLinks = existing.map { it.link }.toSet()

            val all = fetchAllFeeds()
            // Keep only headlines not already shown
            val newItems = all.filterNot { it.link in existingLinks }

            if (newItems.isEmpty()) {
                Log.d(TAG, "No new headlines to load")
            }

            val combined = (existing + newItems).take(MAX_HEADLINES * 2)
            saveCache(appContext, combined)
            HighlightsWidgetProvider.refreshAll(appContext)
        }
    }

    private fun fetchAllFeeds(): List<Headline> {
        val all = mutableListOf<Headline>()

        // Fetch from all prioritized feeds
        for ((source, url) in PRIORITIZED_FEEDS) {
            try {
                val items = fetchFeed(source, url)
                Log.d(TAG, "Fetched ${items.size} headlines from $source")
                all.addAll(items)
            } catch (e: Exception) {
                Log.w(TAG, "Failed to fetch feed $source: ${e.message}")
            }
        }

        // Deduplicate by link and limit
        val distinct = all.distinctBy { it.link }.take(MAX_HEADLINES)
        Log.d(TAG, "Total headlines after dedup: ${distinct.size}")
        return distinct
    }

    private fun fetchFeed(source: String, feedUrl: String): List<Headline> {
        val url = URL(feedUrl)
        val connection = url.openConnection() as HttpURLConnection
        connection.connectTimeout = 8000
        connection.readTimeout = 8000
        connection.requestMethod = "GET"
        connection.setRequestProperty("User-Agent", "Pi-QBank/1.0")
        connection.setRequestProperty("Accept", "application/rss+xml, application/xml, text/xml, */*")

        val responseCode = connection.responseCode
        if (responseCode != HttpURLConnection.HTTP_OK) {
            connection.disconnect()
            return emptyList()
        }

        val raw = connection.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
        connection.disconnect()

        // Try strict XML parsing first, then fall back to lenient regex parsing.
        return try {
            parseRssStrict(raw, source)
        } catch (e: Exception) {
            Log.w(TAG, "Strict parse failed for $source, trying lenient: ${e.message}")
            parseRssLenient(raw, source)
        }
    }

    /**
     * Lenient RSS parser that handles unescaped ampersands and other
     * common XML violations found in BD news feeds.
     */
    private fun parseRssLenient(raw: String, source: String): List<Headline> {
        val headlines = mutableListOf<Headline>()

        // Fix unescaped ampersands: & not followed by a valid entity reference
        val sanitized = raw.replace(Regex("&(?!(amp|lt|gt|quot|apos|#\\d+|#x[0-9a-fA-F]+);)"), "&amp;")

        // Extract items/entries using regex
        val itemPattern = Regex("<(item|entry)[^>]*>(.*?)</\\1>", RegexOption.DOT_MATCHES_ALL)
        val titlePattern = Regex("<title[^>]*>(?:<!\\[CDATA\\[)?(.*?)(?:\\]\\]>)?</title>", RegexOption.DOT_MATCHES_ALL)
        val linkPattern = Regex("<link[^>]*>(?:<!\\[CDATA\\[)?(.*?)(?:\\]\\]>)?</link>", RegexOption.DOT_MATCHES_ALL)
        val linkHrefPattern = Regex("<link[^>]*href=[\"']([^\"']*)[\"']", RegexOption.DOT_MATCHES_ALL)
        val sourcePattern = Regex("<source[^>]*>(?:<!\\[CDATA\\[)?(.*?)(?:\\]\\]>)?</source>", RegexOption.DOT_MATCHES_ALL)

        for (itemMatch in itemPattern.findAll(sanitized)) {
            val itemBody = itemMatch.groupValues[2]

            val titleMatch = titlePattern.find(itemBody)
            val title = titleMatch?.groupValues?.get(1)?.trim() ?: continue

            // Try <link>text</link> first, then <link href="..."/>
            val linkMatch = linkPattern.find(itemBody)
            val link = if (linkMatch != null && linkMatch.groupValues[1].isNotBlank()) {
                linkMatch.groupValues[1].trim()
            } else {
                val hrefMatch = linkHrefPattern.find(itemBody)
                hrefMatch?.groupValues?.get(1)?.trim() ?: continue
            }

            // Extract the actual source (publisher) name; fall back to feed name.
            val sourceMatch = sourcePattern.find(itemBody)
            val actualSource = sourceMatch?.groupValues?.get(1)?.trim()?.takeIf { it.isNotBlank() } ?: source

            if (title.isNotBlank() && link.isNotBlank()) {
                headlines.add(Headline(title, link, actualSource))
            }
        }
        return headlines
    }

    /**
     * Strict XML parser using Android's XmlPullParser.
     * Used as the first attempt; falls back to lenient parsing on failure.
     */
    private fun parseRssStrict(raw: String, source: String): List<Headline> {
        val headlines = mutableListOf<Headline>()
        val parser = android.util.Xml.newPullParser()
        parser.setInput(StringReader(raw))
        var eventType = parser.eventType
        var inItem = false
        var title = ""
        var link = ""
        var itemSource = ""

        while (eventType != org.xmlpull.v1.XmlPullParser.END_DOCUMENT) {
            when (eventType) {
                org.xmlpull.v1.XmlPullParser.START_TAG -> {
                    when (parser.name.lowercase()) {
                        "item", "entry" -> {
                            inItem = true
                            title = ""
                            link = ""
                            itemSource = ""
                        }
                        "title" -> if (inItem) title = parser.nextText().trim()
                        "link" -> if (inItem) {
                            val href = parser.getAttributeValue(null, "href")
                            link = if (!href.isNullOrBlank()) href else parser.nextText().trim()
                        }
                        "source" -> if (inItem) itemSource = parser.nextText().trim()
                    }
                }
                org.xmlpull.v1.XmlPullParser.END_TAG -> {
                    if (parser.name.lowercase() == "item" || parser.name.lowercase() == "entry") {
                        if (title.isNotBlank() && link.isNotBlank()) {
                            val actualSource = itemSource.ifBlank { source }
                            headlines.add(Headline(title, link, actualSource))
                        }
                        inItem = false
                    }
                }
            }
            eventType = parser.next()
        }
        return headlines
    }

    private fun saveCache(context: Context, headlines: List<Headline>) {
        val array = JSONArray()
        headlines.forEach { headline ->
            val obj = JSONObject()
            obj.put("title", headline.title)
            obj.put("link", headline.link)
            obj.put("source", headline.source)
            array.put(obj)
        }
        context.getSharedPreferences(READING_PROGRESS_PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putString(PREFS_KEY, array.toString())
            .apply()
    }
}
