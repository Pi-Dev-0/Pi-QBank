import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pi_qbank/models/saved_test.dart';

class SavedTestService {
  static const String _keySavedTests = 'savedTests';

  static Future<List<SavedTest>> loadSavedTests() async {
    final prefs = await SharedPreferences.getInstance();
    final String? savedTestsJson = prefs.getString(_keySavedTests);

    if (savedTestsJson == null) {
      return [];
    }

    final List<dynamic> jsonList = json.decode(savedTestsJson);
    return jsonList.map((json) => SavedTest.fromJson(json)).toList();
  }

  static Future<void> saveTest(SavedTest test) async {
    final prefs = await SharedPreferences.getInstance();
    final List<SavedTest> savedTests = await loadSavedTests();
    savedTests.add(test);
    final String jsonString =
        json.encode(savedTests.map((test) => test.toJson()).toList());
    await prefs.setString(_keySavedTests, jsonString);
  }

  static Future<void> deleteTest(String id) async {
    final prefs = await SharedPreferences.getInstance();
    List<SavedTest> savedTests = await loadSavedTests();
    savedTests.removeWhere((test) => test.id == id);
    final String jsonString =
        json.encode(savedTests.map((test) => test.toJson()).toList());
    await prefs.setString(_keySavedTests, jsonString);
  }
}