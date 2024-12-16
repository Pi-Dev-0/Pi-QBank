import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Formula {
  final String id;
  final String subject;
  final String title;
  final String? subtitle;
  final String formula;
  final String? description;

  Formula({
    required this.id,
    required this.subject,
    required this.title,
    this.subtitle,
    required this.formula,
    this.description,
  });

  factory Formula.fromJson(Map<String, dynamic> json) {
    return Formula(
      id: json['id']?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      subject: json['subject'] ?? '',
      title: json['title'] ?? '',
      subtitle: json['subtitle'],
      formula: json['formula'] ?? '',
      description: json['description'],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'subject': subject,
        'title': title,
        'subtitle': subtitle,
        'formula': formula,
        'description': description,
      };
}

class FormulaService {
  final String baseUrl;
  static const String _cacheKey = 'formula_cache';
  static const Duration _cacheDuration = Duration(days: 7);
  final SharedPreferences _prefs;

  FormulaService._({required this.baseUrl, required SharedPreferences prefs}) 
    : _prefs = prefs;

  static Future<FormulaService> create() async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = AppConfig.formulaApi;
    return FormulaService._(baseUrl: baseUrl, prefs: prefs);
  }

  Future<void> _saveToCache(List<Formula> formulas) async {
    final data = {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'formulas': formulas.map((f) => f.toJson()).toList(),
    };
    await _prefs.setString(_cacheKey, json.encode(data));
  }

  Future<List<Formula>?> _getFromCache() async {
    final cachedData = _prefs.getString(_cacheKey);
    if (cachedData != null) {
      final data = json.decode(cachedData);
      final timestamp = DateTime.fromMillisecondsSinceEpoch(data['timestamp']);
      if (DateTime.now().difference(timestamp) < _cacheDuration) {
        return (data['formulas'] as List)
            .map((item) => Formula.fromJson(item))
            .toList();
      }
    }
    return null;
  }

  Future<List<Formula>> getFormulas({String? subject}) async {
    try {
      // Try to get from cache first
      final cachedFormulas = await _getFromCache();
      if (cachedFormulas != null) {
        if (subject != null) {
          return cachedFormulas
              .where((formula) =>
                  formula.subject.toLowerCase() == subject.toLowerCase())
              .toList();
        }
        return cachedFormulas;
      }

      // If not in cache or cache expired, fetch from network
      final response = await http.get(Uri.parse(baseUrl));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success' && data['data'] != null) {
          List<Formula> allFormulas = (data['data'] as List)
              .map((item) => Formula.fromJson(item))
              .toList();

          // Save to cache
          await _saveToCache(allFormulas);

          if (subject != null) {
            return allFormulas
                .where((formula) =>
                    formula.subject.toLowerCase() == subject.toLowerCase())
                .toList();
          }
          return allFormulas;
        }
      }
      throw Exception('Failed to load formulas: ${response.statusCode}');
    } catch (e) {
      throw Exception('Failed to load formulas: $e');
    }
  }

  Future<void> clearCache() async {
    await _prefs.remove(_cacheKey);
  }
}
