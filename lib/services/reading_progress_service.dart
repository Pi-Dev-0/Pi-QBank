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
  final int currentPage;
  final int? totalPages;
  final DateTime lastReadAt;
  final String? thumbnailPath;

  const ReadingProgress({
    required this.id,
    required this.title,
    required this.currentPage,
    required this.totalPages,
    required this.lastReadAt,
    this.thumbnailPath,
  });

  double? get progress {
    final total = totalPages;
    if (total == null || total <= 0) return null;
    return (currentPage / total).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'currentPage': currentPage,
        'totalPages': totalPages,
        'lastReadAt': lastReadAt.toIso8601String(),
        'thumbnailPath': thumbnailPath,
      };

  factory ReadingProgress.fromJson(Map<String, dynamic> json) {
    return ReadingProgress(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Untitled book',
      currentPage: (json['currentPage'] as num?)?.toInt() ?? 1,
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
    required int? totalPages,
  }) async {
    final records = await getAll();
    final newBook = ReadingProgress(
      id: _uuid.v4(),
      title: title.trim(),
      currentPage: 1,
      totalPages: totalPages,
      lastReadAt: DateTime.now(),
      thumbnailPath: null,
    );
    records.add(newBook);
    await _save(records);
  }

  static Future<void> updatePage(String id, int page) async {
    final records = await getAll();
    final index = records.indexWhere((record) => record.id == id);
    if (index == -1) return;
    final previous = records[index];
    records[index] = ReadingProgress(
      id: previous.id,
      title: previous.title,
      currentPage: page,
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
    final destination = File('${coverDirectory.path}/$id.$extension');
    await File(sourcePath).copy(destination.path);

    final previous = records[index];
    _deleteManagedThumbnail(previous.thumbnailPath, coverDirectory.path);
    records[index] = ReadingProgress(
      id: previous.id,
      title: previous.title,
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
