import 'dart:convert';
import 'package:http/http.dart' as http;

/// Service that fetches the list of available AI models and provider
/// base URLs from a Google Apps Script endpoint.
///
/// The script reads data from a Google Sheet with two tabs:
///
/// Tab "Models" (row 1 = header):
///   A: id | B: provider | C: type | D: displayName | E: description
///
/// Tab "Providers" (row 1 = header):
///   A: provider | B: baseUrl
///
/// The script returns a JSON object:
/// ```json
/// {
///   "models": [
///     {
///       "id": "gemma-3-27b-it",
///       "provider": "google",
///       "type": "text",
///       "displayName": "Gemma 3 27B",
///       "description": "Google's open-weight model"
///     }
///   ],
///   "providers": [
///     { "provider": "google", "baseUrl": "https://generativelanguage.googleapis.com/v1beta" },
///     { "provider": "openrouter", "baseUrl": "https://openrouter.ai/api/v1/chat/completions" }
///   ]
/// }
/// ```
class AIModelsService {
  static const String _appScriptUrl =
      'https://script.google.com/macros/s/AKfycbzB0Su0HklAXiePU7SRXA_h866eyGmhy-3UE1DKy689gOvRiJanJl_BbpBhemvng46sXQ/exec';

  static List<AIModel> _cachedModels = [];
  static Map<String, String> _cachedBaseUrls = {};
  static Map<String, String> _cachedApiKeys = {};
  static DateTime? _lastFetch;
  static const Duration _cacheExpiry = Duration(minutes: 30);

  /// All models, fetched from the Apps Script (or cache).
  /// Returns empty list if the Apps Script is unreachable and no cache exists.
  static Future<List<AIModel>> fetchModels({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedModels.isNotEmpty && _lastFetch != null) {
      if (DateTime.now().difference(_lastFetch!) < _cacheExpiry) {
        return _cachedModels;
      }
    }

    try {
      final response = await http.get(Uri.parse(_appScriptUrl)).timeout(
        const Duration(seconds: 15),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);

        // Parse models
        final List<dynamic> modelsJson = data['models'] as List<dynamic>? ?? [];
        _cachedModels = modelsJson
            .map((item) => AIModel.fromJson(item as Map<String, dynamic>))
            .toList();

        // Parse provider base URLs
        final List<dynamic> providersJson =
            data['providers'] as List<dynamic>? ?? [];
        _cachedBaseUrls = {};
        for (final p in providersJson) {
          final provider = p['provider'] as String?;
          final baseUrl = p['baseUrl'] as String?;
          if (provider != null && baseUrl != null) {
            _cachedBaseUrls[provider] = baseUrl;
          }
        }

        // Parse shared API keys from Sheet
        final List<dynamic> apiKeysJson = data['apiKeys'] as List<dynamic>? ?? [];
        _cachedApiKeys = {};
        for (final k in apiKeysJson) {
          final provider = k['provider'] as String?;
          final apiKey = k['apiKey'] as String?;
          if (provider != null && apiKey != null) {
            _cachedApiKeys[provider] = apiKey;
          }
        }

        _lastFetch = DateTime.now();
        return _cachedModels;
      }
    } catch (_) {
      // Network error — return cached models if available
    }

    // Return cached models if available, otherwise empty
    return _cachedModels;
  }

  /// Synchronous getter for cached base URL (may be empty if not fetched yet).
  static String getBaseUrlSync(String provider) {
    return _cachedBaseUrls[provider] ?? '';
  }

  /// Get the base URL for a given provider.
  static Future<String> getBaseUrl(String provider) async {
    if (_cachedBaseUrls.isEmpty) {
      await fetchModels();
    }
    return _cachedBaseUrls[provider] ?? '';
  }

  /// Get the shared API key for a given provider (from the Google Sheet).
  /// Returns empty string if no shared key is available.
  static Future<String> getApiKey(String provider) async {
    if (_cachedApiKeys.isEmpty) {
      await fetchModels();
    }
    return _cachedApiKeys[provider] ?? '';
  }

  /// Whether a shared API key is available for the provider.
  static Future<bool> hasSharedApiKey(String provider) async {
    final key = await getApiKey(provider);
    return key.isNotEmpty;
  }

  static List<AIModel> get models => _cachedModels;
}

/// Represents a single AI model entry.
class AIModel {
  final String id;
  final String provider;
  final String type;
  final String displayName;
  final String description;

  const AIModel({
    required this.id,
    required this.provider,
    required this.type,
    required this.displayName,
    required this.description,
  });

  factory AIModel.fromJson(Map<String, dynamic> json) => AIModel(
        id: json['id'] as String? ?? '',
        provider: json['provider'] as String? ?? 'google',
        type: json['type'] as String? ?? 'text',
        displayName:
            json['displayName'] as String? ?? json['id'] as String? ?? '',
        description: json['description'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'provider': provider,
        'type': type,
        'displayName': displayName,
        'description': description,
      };
}
