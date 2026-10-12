import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/highschool_question.dart';

/// Service that communicates with the Google Apps Script web app
/// backing the HighSchool_Questions sheet.
///
/// Set [scriptUrl] to your deployed Apps Script web-app URL.
class HighSchoolQBankService {
  final String scriptUrl;

  const HighSchoolQBankService({required this.scriptUrl});

  // ───────────────────────────────────────────────────────────────────────────
  // Fetch questions
  // ───────────────────────────────────────────────────────────────────────────

  /// Fetches questions for the given [className] and [subject].
  /// Optionally filters by [chapters] (list of chapter numbers as strings).
  Future<List<HighSchoolQuestion>> fetchQuestions({
    required String className,
    required String subject,
    List<String>? chapters,
  }) async {
    final queryParams = {
      'action':  'getQuestions',
      'class':   className,
      'subject': subject,
      if (chapters != null && chapters.isNotEmpty)
        'chapters': chapters.join(','),
    };

    final uri = Uri.parse(scriptUrl).replace(queryParameters: queryParams);

    final response = await http.get(uri).timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw Exception('Request timed out. Check your connection.'),
    );

    if (response.statusCode != 200) {
      throw Exception('Server error: ${response.statusCode}');
    }

    final decoded = json.decode(response.body) as Map<String, dynamic>;
    if (decoded['status'] != 'SUCCESS') {
      throw Exception(decoded['message'] ?? 'Unknown server error');
    }

    final rawList = decoded['data'] as List<dynamic>? ?? [];
    return rawList
      .map((e) => HighSchoolQuestion.fromJson(e as Map<String, dynamic>))
      .toList();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Fetch chapters for a class + subject combo
  // ───────────────────────────────────────────────────────────────────────────

  Future<List<ChapterInfo>> fetchChapters({
    required String className,
    required String subject,
  }) async {
    final queryParams = {
      'action':  'getChapters',
      'class':   className,
      'subject': subject,
    };

    final uri = Uri.parse(scriptUrl).replace(queryParameters: queryParams);
    final response = await http.get(uri).timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception('Server error: ${response.statusCode}');
    }

    final decoded = json.decode(response.body) as Map<String, dynamic>;
    if (decoded['status'] != 'SUCCESS') {
      throw Exception(decoded['message'] ?? 'Unknown server error');
    }

    final rawList = decoded['data'] as List<dynamic>? ?? [];
    return rawList
      .map((e) => ChapterInfo.fromJson(e as Map<String, dynamic>))
      .toList();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Upload questions (single or bulk)
  // ───────────────────────────────────────────────────────────────────────────

  /// Posts [questions] to the Apps Script for storage in the Google Sheet.
  /// Returns a status message from the server.
  Future<String> uploadQuestions(List<HighSchoolQuestion> questions) async {
    final body = json.encode({
      'action': 'addQuestions',
      'questions': questions.map((q) => q.toJson()).toList(),
    });

    final response = await http
      .post(
        Uri.parse(scriptUrl),
        headers: {'Content-Type': 'application/json'},
        body: body,
      )
      .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('Server error: ${response.statusCode}');
    }

    final decoded = json.decode(response.body) as Map<String, dynamic>;
    if (decoded['status'] == 'SUCCESS') {
      return decoded['message'] as String? ?? 'Questions uploaded successfully.';
    } else {
      throw Exception(decoded['message'] ?? 'Upload failed');
    }
  }
}
