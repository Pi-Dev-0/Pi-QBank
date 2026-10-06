import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class ReadingProgress {
  final String id;
  final String title;
  final int startPage;
  final int currentPage;
  final int? totalPages;
  final DateTime lastReadAt;
  final String? thumbnailPath;

  const ReadingProgress({
    required this.id,
    required this.title,
    this.startPage = 1,
    required this.currentPage,
    required this.totalPages,
    required this.lastReadAt,
    this.thumbnailPath,
  });

  double? get progress {
    final total = totalPages;
    if (total == null || total <= 0) return null;
    if (startPage <= 1) {
      return (currentPage / total).clamp(0.0, 1.0);
    }
    if (total <= startPage) return 1.0;
    return ((currentPage - startPage) / (total - startPage)).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'startPage': startPage,
        'currentPage': currentPage,
        'totalPages': totalPages,
        'lastReadAt': lastReadAt.toIso8601String(),
        'thumbnailPath': thumbnailPath,
      };

  factory ReadingProgress.fromJson(Map<String, dynamic> json) {
    final start = (json['startPage'] as num?)?.toInt() ?? 1;
    final current = (json['currentPage'] as num?)?.toInt() ?? start;
    return ReadingProgress(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Untitled book',
      startPage: start,
      currentPage: current < start ? start : current,
      totalPages: (json['totalPages'] as num?)?.toInt(),
      lastReadAt: DateTime.tryParse(json['lastReadAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      thumbnailPath: json['thumbnailPath'] as String?,
    );
  }
}

class ReadingProgressService {
  static const _storageKey = 'physical_book_reading_progress_v1';
  static const _uuid = Uuid();
  static const _widgetChannel = MethodChannel(
    'com.pi.mathematics/reading_progress_widget',
  );

  static Future<List<ReadingProgress>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final stored = prefs.getString(_storageKey);
    if (stored == null) return [];
    try {
      final decoded = jsonDecode(stored) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(ReadingProgress.fromJson)
          .toList()
        ..sort((a, b) => b.lastReadAt.compareTo(a.lastReadAt));
    } catch (_) {
      return [];
    }
  }

  static Future<void> add({
    required String title,
    int startPage = 1,
    required int? totalPages,
  }) async {
    final records = await getAll();
    final initialStart = startPage < 1 ? 1 : startPage;
    final newBook = ReadingProgress(
      id: _uuid.v4(),
      title: title.trim(),
      startPage: initialStart,
      currentPage: initialStart,
      totalPages: totalPages,
      lastReadAt: DateTime.now(),
      thumbnailPath: null,
    );
    records.add(newBook);
    await _save(records);
  }

  static Future<void> edit({
    required String id,
    required String title,
    required int startPage,
    required int? totalPages,
  }) async {
    final records = await getAll();
    final index = records.indexWhere((record) => record.id == id);
    if (index == -1) return;
    final previous = records[index];
    final validStart = startPage < 1 ? 1 : startPage;
    var validCurrent = previous.currentPage;
    if (validCurrent < validStart) {
      validCurrent = validStart;
    } else if (totalPages != null && validCurrent > totalPages) {
      validCurrent = totalPages;
    }
    records[index] = ReadingProgress(
      id: previous.id,
      title: title.trim(),
      startPage: validStart,
      currentPage: validCurrent,
      totalPages: totalPages,
      lastReadAt: DateTime.now(),
      thumbnailPath: previous.thumbnailPath,
    );
    await _save(records);
  }

  static Future<void> updatePage(String id, int page) async {
    final records = await getAll();
    final index = records.indexWhere((record) => record.id == id);
    if (index == -1) return;
    final previous = records[index];
    final validPage = page < previous.startPage ? previous.startPage : page;
    records[index] = ReadingProgress(
      id: previous.id,
      title: previous.title,
      startPage: previous.startPage,
      currentPage: validPage,
      totalPages: previous.totalPages,
      lastReadAt: DateTime.now(),
      thumbnailPath: previous.thumbnailPath,
    );
    await _save(records);
  }

  static Future<void> updateThumbnail(String id, String sourcePath) async {
    final records = await getAll();
    final index = records.indexWhere((record) => record.id == id);
    if (index == -1) return;

    final documents = await getApplicationDocumentsDirectory();
    final coverDirectory =
        Directory('${documents.path}/reading_progress_covers');
    await coverDirectory.create(recursive: true);
    final sourceExtension = sourcePath.split('.').last.toLowerCase();
    final extension =
        const {'jpg', 'jpeg', 'png', 'webp'}.contains(sourceExtension)
            ? sourceExtension
            : 'jpg';
    // Use a fresh path each time. Reusing the same path can cause us to delete
    // the newly copied file when removing the previous cover, and can leave
    // Flutter's file image cache showing the old cover.
    final destination = File(
      '${coverDirectory.path}/$id-${_uuid.v4()}.$extension',
    );
    await File(sourcePath).copy(destination.path);

    final previous = records[index];
    _deleteManagedThumbnail(previous.thumbnailPath, coverDirectory.path);
    records[index] = ReadingProgress(
      id: previous.id,
      title: previous.title,
      startPage: previous.startPage,
      currentPage: previous.currentPage,
      totalPages: previous.totalPages,
      lastReadAt: previous.lastReadAt,
      thumbnailPath: destination.path,
    );
    await _save(records);
  }

  static Future<void> removeThumbnail(String id) async {
    final records = await getAll();
    final index = records.indexWhere((record) => record.id == id);
    if (index == -1) return;
    final previous = records[index];
    final documents = await getApplicationDocumentsDirectory();
    final coverDirectory =
        Directory('${documents.path}/reading_progress_covers');
    _deleteManagedThumbnail(previous.thumbnailPath, coverDirectory.path);
    records[index] = ReadingProgress(
      id: previous.id,
      title: previous.title,
      startPage: previous.startPage,
      currentPage: previous.currentPage,
      totalPages: previous.totalPages,
      lastReadAt: previous.lastReadAt,
      thumbnailPath: null,
    );
    await _save(records);
  }

  static Future<void> remove(String id) async {
    final records = await getAll();
    final index = records.indexWhere((record) => record.id == id);
    final removed = index == -1 ? null : records[index];
    records.removeWhere((record) => record.id == id);
    if (removed != null) {
      final documents = await getApplicationDocumentsDirectory();
      _deleteManagedThumbnail(
        removed.thumbnailPath,
        '${documents.path}/reading_progress_covers',
      );
    }
    await _save(records);
  }

  static void _deleteManagedThumbnail(String? path, String managedDirectory) {
    if (path == null || !path.startsWith('$managedDirectory/')) return;
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  }

  static Future<void> _save(List<ReadingProgress> records) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(records.map((record) => record.toJson()).toList()),
    );
    await _refreshWidget();
  }

  static Future<void> _refreshWidget() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _widgetChannel.invokeMethod<void>('refresh');
    } on MissingPluginException {
      // The Android widget bridge is unavailable on older app installations.
    } on PlatformException {
      // A widget refresh failure must not prevent progress from being saved.
    }
  }
}
