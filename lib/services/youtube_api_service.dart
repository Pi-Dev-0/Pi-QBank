import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:pi_qbank/config/app_config.dart';
import '../models/video_models.dart'; // Import Video model from new location

class YoutubeApiService {
  // Replace with your actual App Script Web App URL
  // This URL should be deployed as a web app with "Anyone, even anonymous" access.
  static const String _baseUrl = AppConfig.youtubeApiKey;

  // Hardcoded encryption key as per user's request
  static const String _encryptionKey = "YOUR_HARDCODED_ENCRYPTION_KEY"; // User requested hardcoded key

  // XOR encryption/decryption logic with Base64 encoding
  String _xorEncryptDecrypt(String inputBase64, String key) {
    try {
      // Decode Base64 string to bytes
      final encryptedBytes = base64.decode(inputBase64);
      final keyBytes = utf8.encode(key);
      final decryptedBytes = <int>[];

      for (int i = 0; i < encryptedBytes.length; i++) {
        decryptedBytes.add(encryptedBytes[i] ^ keyBytes[i % keyBytes.length]);
      }
      // Decode bytes to UTF-8 string
      return utf8.decode(decryptedBytes);
    } catch (e) {
      rethrow; // Re-throw to be caught by the main catch block
    }
  }

  Future<List<Video>> fetchVideos() async {
    if (_baseUrl == 'YOUR_APPSCRIPT_WEB_APP_URL_HERE' || _baseUrl.isEmpty) {
      throw Exception('YouTube API URL is not configured.');
    }

    final uri = Uri.parse(_baseUrl);

    try {
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        // Decrypt the response body (which is Base64 encoded)
        final decryptedBody = _xorEncryptDecrypt(response.body, _encryptionKey);
        final List<dynamic> jsonResponse = json.decode(decryptedBody);
        return jsonResponse.map((data) => Video.fromJson(data)).toList();
      } else {
        throw Exception('Failed to load videos: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching videos: $e');
    }
  }
}
