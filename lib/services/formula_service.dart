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

  // Hardcoded encryption key for Formula API
  static const String _encryptionKey = "FORMULA_SECRET_KEY";

  FormulaService._({required this.baseUrl, required SharedPreferences prefs}) 
    : _prefs = prefs;

  static Future<FormulaService> create() async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = AppConfig.formulaApi;
    return FormulaService._(baseUrl: baseUrl, prefs: prefs);
  }

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
      rethrow;
    }
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
        // Decrypt the response body (which is Base64 encoded)
        final decryptedBody = _xorEncryptDecrypt(response.body, _encryptionKey);
        final data = json.decode(decryptedBody);
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
