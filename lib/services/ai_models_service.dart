import 'dart:convert';
import 'package:http/http.dart' as http;

/// Service that fetches the list of available AI models from a Google Apps
/// Script endpoint. The script reads model data from a Google Sheet and
/// returns it as a JSON array.
///
/// Expected Sheet columns (row 1 = header):
///   A: id | B: provider | C: type | D: displayName | E: description
///
/// The script returns a JSON array of model objects:
/// ```json
/// [
///   {
///     "id": "gemma-3-27b-it",
///     "provider": "google",
///     "type": "text",
///     "displayName": "Gemma 3 27B",
///     "description": "Google's open-weight model"
///   }
/// ]
/// ```
class AIModelsService {
  static const String _appScriptUrl =
      'https://script.google.com/macros/s/AKfycbxAI_ModelsEndpoint/exec';

  static List<AIModel> _cachedModels = [];
  static DateTime? _lastFetch;
  static const Duration _cacheExpiry = Duration(minutes: 30);

  /// All models, fetched from the Apps Script (or cache).
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
        final List<dynamic> data = json.decode(response.body);
        _cachedModels = data
            .map((item) => AIModel.fromJson(item as Map<String, dynamic>))
            .toList();
        _lastFetch = DateTime.now();
        return _cachedModels;
      }
    } catch (_) {
      // Fall through to fallback
    }

    // Fallback: return cached models or built-in defaults
    if (_cachedModels.isNotEmpty) return _cachedModels;
    return _defaultModels;
  }

  /// Built-in fallback models (used when the Apps Script is unreachable).
  static final List<AIModel> _defaultModels = [
    AIModel(
      id: 'gemma-3-27b-it',
      provider: 'google',
      type: 'text',
      displayName: 'Gemma 3 27B',
      description: "Google's open-weight model",
    ),
    AIModel(
      id: 'gemma-3n-e4b-it',
      provider: 'google',
      type: 'text',
      displayName: 'Gemma 3N E4B',
      description: 'Efficient open-weight model',
    ),
    AIModel(
      id: 'gemini-2.5-flash-preview-09-2025',
      provider: 'google',
      type: 'image',
      displayName: 'Gemini 2.5 Flash',
      description: 'Fast multimodal model',
    ),
    AIModel(
      id: 'gemini-2.0-flash-001',
      provider: 'google',
      type: 'text',
      displayName: 'Gemini 2.0 Flash',
      description: 'Lightning-fast responses',
    ),
    AIModel(
      id: 'gemini-2.0-flash',
      provider: 'google',
      type: 'text',
      displayName: 'Gemini 2.0 Flash (stable)',
      description: 'Stable flash model',
    ),
    AIModel(
      id: 'gemini-1.5-flash',
      provider: 'google',
      type: 'text',
      displayName: 'Gemini 1.5 Flash',
      description: 'Previous generation flash',
    ),
    AIModel(
      id: 'gemini-1.5-pro',
      provider: 'google',
      type: 'text',
      displayName: 'Gemini 1.5 Pro',
      description: 'Previous generation pro',
    ),
    AIModel(
      id: 'google/gemini-2.0-flash-001',
      provider: 'openrouter',
      type: 'text',
      displayName: 'Gemini 2.0 Flash (OpenRouter)',
      description: 'Via OpenRouter',
    ),
    AIModel(
      id: 'anthropic/claude-3.5-sonnet',
      provider: 'openrouter',
      type: 'text',
      displayName: 'Claude 3.5 Sonnet',
      description: 'Anthropic via OpenRouter',
    ),
    AIModel(
      id: 'openai/gpt-4o',
      provider: 'openrouter',
      type: 'text',
      displayName: 'GPT-4o',
      description: 'OpenAI via OpenRouter',
    ),
    AIModel(
      id: 'openai/gpt-4o-mini',
      provider: 'openrouter',
      type: 'text',
      displayName: 'GPT-4o Mini',
      description: 'Smaller GPT-4o',
    ),
    AIModel(
      id: 'deepseek/deepseek-chat',
      provider: 'openrouter',
      type: 'text',
      displayName: 'DeepSeek Chat',
      description: 'DeepSeek via OpenRouter',
    ),
  ];

  static List<AIModel> get models => _cachedModels.isNotEmpty ? _cachedModels : _defaultModels;
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
        displayName: json['displayName'] as String? ?? json['id'] as String? ?? '',
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
