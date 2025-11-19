import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/test_result.dart';

class TestResultService {
  static const String _keyTestResults = 'testResults';

  static Future<void> saveTestResult(TestResult result) async {
    final prefs = await SharedPreferences.getInstance();
    final String newResultJson = json.encode(result.toJson());

    // Load existing results
    final List<String> existingResults = prefs.getStringList(_keyTestResults) ?? [];

    // Add new result to the list
    existingResults.add(newResultJson);

    // Save the updated list
    await prefs.setStringList(_keyTestResults, existingResults);
  }

  static Future<List<TestResult>> loadTestResults() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> resultsJson = prefs.getStringList(_keyTestResults) ?? [];
    return resultsJson.map((jsonString) => TestResult.fromJson(json.decode(jsonString))).toList();
  }

  static Future<void> clearAllTestResults() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyTestResults);
  }
}
