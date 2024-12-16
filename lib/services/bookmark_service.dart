import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class BookmarkedPaper {
  final String title;
  final String subtitle;
  final String year;
  final String examYear;
  final String downloadUrl;
  final String category;
  final DateTime bookmarkedAt;

  BookmarkedPaper({
    required this.title,
    required this.subtitle,
    required this.year,
    required this.examYear,
    required this.downloadUrl,
    String? category,
    DateTime? bookmarkedAt,
  })  : category = category ?? 'General',
        bookmarkedAt = bookmarkedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'title': title,
        'subtitle': subtitle,
        'year': year,
        'examYear': examYear,
        'downloadUrl': downloadUrl,
        'category': category,
        'bookmarkedAt': bookmarkedAt.toIso8601String(),
      };

  factory BookmarkedPaper.fromJson(Map<String, dynamic> json) =>
      BookmarkedPaper(
        title: json['title'],
        subtitle: json['subtitle'],
        year: json['year'],
        examYear: json['examYear'],
        downloadUrl: json['downloadUrl'],
        category: json['category'] ?? 'General',
        bookmarkedAt: DateTime.parse(json['bookmarkedAt']),
      );

  bool isSamePaper(BookmarkedPaper other) {
    return downloadUrl == other.downloadUrl && 
           subtitle == other.subtitle &&
           title == other.title;
  }
}

class BookmarkService {
  static const String _bookmarksKey = 'bookmarked_papers';
  static List<BookmarkedPaper> _bookmarks = [];
  static bool _initialized = false;

  static Future<void> _init() async {
    if (_initialized) return;

    final prefs = await SharedPreferences.getInstance();
    final bookmarksJson = prefs.getStringList(_bookmarksKey) ?? [];
    _bookmarks = bookmarksJson
        .map((json) => BookmarkedPaper.fromJson(jsonDecode(json)))
        .toList();
    _initialized = true;
  }

  static Future<void> _saveBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    final bookmarksJson =
        _bookmarks.map((bookmark) => jsonEncode(bookmark.toJson())).toList();
    await prefs.setStringList(_bookmarksKey, bookmarksJson);
  }

  static Future<List<BookmarkedPaper>> getBookmarks() async {
    await _init();
    return List.from(_bookmarks);
  }

  static Future<bool> isBookmarked(String downloadUrl, String subtitle, String title) async {
    await _init();
    return _bookmarks.any((bookmark) => 
      bookmark.downloadUrl == downloadUrl && 
      bookmark.subtitle == subtitle &&
      bookmark.title == title
    );
  }

  static Future<void> toggleBookmark(BookmarkedPaper paper) async {
    await _init();
    
    final existingIndex = _bookmarks.indexWhere((bookmark) => bookmark.isSamePaper(paper));

    if (existingIndex != -1) {
      _bookmarks.removeAt(existingIndex);
    } else {
      _bookmarks.insert(0, paper);
    }

    await _saveBookmarks();
  }
}
