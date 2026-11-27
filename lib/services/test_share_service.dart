import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// A user-facing problem while publishing a test.
class TestShareException implements Exception {
  TestShareException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Publishes a generated test to the Google Apps Script endpoint.
///
/// The service owns the HTTP details so the page can stay focused on the flow:
/// timeout, UTF-8 decoding, response shape, and the numeric/string share code.
class TestShareService {
  TestShareService({
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
    this.contentType = 'application/json',
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  /// Apps Script can reject the CORS preflight for `application/json` on Web.
  /// Web builds pass `text/plain;charset=utf-8`; mobile keeps JSON.
  final String contentType;

  Future<String> publish({
    required String url,
    required String testType,
    required String language,
    required int duration,
    required String jsonData,
  }) async {
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty) {
      throw TestShareException('The share service URL is not configured.');
    }

    http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(trimmedUrl),
            headers: {
              'Content-Type': contentType,
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'testType': testType,
              'language': language,
              'duration': duration,
              'jsonData': jsonData,
            }),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw TestShareException(
        'The server took too long to respond. Please try again.',
      );
    } catch (e) {
      throw TestShareException('Network error: $e');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TestShareException('Server error: ${response.statusCode}');
    }

    dynamic data;
    try {
      data = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw TestShareException('The server returned an invalid response.');
    }

    if (data is! Map) {
      throw TestShareException('The server returned an unexpected response.');
    }

    final successValue = data['success'];
    final success = successValue == true ||
        (successValue is String && successValue.toLowerCase() == 'true') ||
        '${data['status'] ?? ''}'.toUpperCase() == 'SUCCESS';

    if (!success) {
      final message = data['error'] ?? data['message'];
      throw TestShareException(
        '${message ?? 'Failed to share the test.'}',
      );
    }

    final code = data['testId']?.toString().trim();
    if (code == null || code.isEmpty) {
      throw TestShareException('The server did not return a share code.');
    }

    return code;
  }

  void dispose() => _client.close();
}
