import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class DownloadedPaper {
  final String title;
  final String subtitle;
  final String examYear;
  final String category;
  final String filePath;

  DownloadedPaper({
    required this.title,
    required this.subtitle,
    required this.examYear,
    required this.category,
    required this.filePath,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'subtitle': subtitle,
        'examYear': examYear,
        'category': category,
        'filePath': filePath,
      };

  factory DownloadedPaper.fromJson(Map<String, dynamic> json) => DownloadedPaper(
        title: json['title'] ?? '',
        subtitle: json['subtitle'] ?? '',
        examYear: json['examYear'] ?? '',
        category: json['category'] ?? '',
        filePath: json['filePath'] ?? '',
      );
}

class DownloadedPapersRegistry {
  static const _key = 'downloaded_papers';
  static final DownloadedPapersRegistry _instance = DownloadedPapersRegistry._internal();
  final _prefs = SharedPreferences.getInstance();

  factory DownloadedPapersRegistry() {
    return _instance;
  }

  DownloadedPapersRegistry._internal();

  Future<List<DownloadedPaper>> getDownloadedPapers() async {
    final prefs = await _prefs;
    final papersJson = prefs.getStringList(_key) ?? [];
    return papersJson
        .map((json) => DownloadedPaper.fromJson(jsonDecode(json)))
        .toList();
  }

  Future<void> addDownloadedPaper(DownloadedPaper paper) async {
    final prefs = await _prefs;
    final papers = await getDownloadedPapers();
    
    // Check if paper already exists
    if (!papers.any((p) => p.filePath == paper.filePath)) {
      papers.add(paper);
      final papersJson = papers
          .map((paper) => jsonEncode(paper.toJson()))
          .toList();
      await prefs.setStringList(_key, papersJson);
    }
  }

  Future<void> removeDownloadedPaper(String filePath) async {
    final prefs = await _prefs;
    final papers = await getDownloadedPapers();
    papers.removeWhere((paper) => paper.filePath == filePath);
    final papersJson = papers
        .map((paper) => jsonEncode(paper.toJson()))
        .toList();
    await prefs.setStringList(_key, papersJson);
  }
}
