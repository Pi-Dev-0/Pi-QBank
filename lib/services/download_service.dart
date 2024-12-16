import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

class DownloadService {
  static Future<String> getLocalPath() async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  static Future<bool> isContentDownloaded(String contentId) async {
    final path = await getLocalPath();
    final file = File('$path/$contentId.json');
    return file.exists();
  }

  static Future<String?> downloadPDF({
    required String url,
    required String fileName,
    required Function(double) onProgress,
  }) async {
    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('Failed to download file: ${response.statusCode}');
      }

      final contentLength = response.contentLength ?? 0;
      int received = 0;

      final directory = await getTemporaryDirectory();
      final filePath = '${directory.path}/$fileName';
      final file = File(filePath);

      final sink = file.openWrite();
      
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (contentLength > 0) {
          final progress = received / contentLength;
          onProgress(progress);
        }
      }

      await sink.close();
      Logger().d('File downloaded successfully to: $filePath');
      return filePath;
    } catch (e) {
      Logger().e('Error downloading file: $e');
      return null;
    }
  }

  static Future<void> downloadContent(String contentId, String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final path = await getLocalPath();
        final file = File('$path/$contentId.json');
        await file.writeAsBytes(response.bodyBytes);
      }
    } catch (e) {
      throw Exception('Failed to download content: $e');
    }
  }

  static Future<String?> getContent(String contentId) async {
    try {
      final path = await getLocalPath();
      final file = File('$path/$contentId.json');
      if (await file.exists()) {
        return file.readAsString();
      }
      return null;
    } catch (e) {
      return null;
    }
  }
} 