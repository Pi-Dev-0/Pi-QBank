import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:pi_qbank/config/app_config.dart';
import '../models/video_models.dart'; // Import Video model from new location

class YoutubeApiService {
  // Replace with your actual App Script Web App URL
  // This URL should be deployed as a web app with "Anyone, even anonymous" access.
  static const String _baseUrl = AppConfig.youtubeApiKey;

  Future<List<Video>> fetchVideos() async { // Removed optional parameters
    if (_baseUrl == 'YOUR_APPSCRIPT_WEB_APP_URL_HERE' || _baseUrl.isEmpty) {
      throw Exception('YouTube API URL is not configured.');
    }

    final uri = Uri.parse(_baseUrl); // Removed query parameters

    try {
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final List<dynamic> jsonResponse = json.decode(response.body);
        return jsonResponse.map((data) => Video.fromJson(data)).toList();
      } else {
        throw Exception('Failed to load videos: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching videos: $e');
    }
  }
}
