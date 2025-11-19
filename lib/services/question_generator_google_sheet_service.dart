import 'package:http/http.dart' as http;
import 'package:pi_qbank/config/app_config.dart';
import 'dart:convert';

class QuestionGeneratorGoogleSheetService {
  static const String _appScriptUrl = AppConfig.aiQuestionGenerator; // Replace with your App Script URL

  static Future<String> uploadQuestions({
    required String className,
    required String subject,
    required String chapter,
    required String questionType,
    required String language,
    required String generatedTopic,
    required List<Map<String, String>> generatedQuestions,
    required List<Map<String, dynamic>> generatedMcqs,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(_appScriptUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'action': 'addQuestions',
          'className': className,
          'subject': subject,
          'chapter': chapter,
          'questionType': questionType,
          'language': language,
          'generatedTopic': generatedTopic,
          'generatedQuestions': generatedQuestions,
          'generatedMcqs': generatedMcqs,
        }),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);
        if (responseData['status'] == 'SUCCESS') {
          return 'SUCCESS';
        } else {
          return 'ERROR: ${responseData['message'] ?? 'Unknown error'}';
        }
      } else {
        return 'ERROR: Server responded with status ${response.statusCode}';
      }
    } catch (e) {
      return 'ERROR: ${e.toString()}';
    }
  }
}