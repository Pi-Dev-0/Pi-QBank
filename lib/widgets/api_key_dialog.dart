import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/ai_models_service.dart';

// Key for storing the API key in SharedPreferences
const String _apiKeyPrefKey = 'gemini_api_key';

// Function to save the API key
Future<void> saveApiKey(String apiKey) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_apiKeyPrefKey, apiKey);
}

// Function to retrieve the user's personal API key
Future<String?> getApiKey() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_apiKeyPrefKey);
}

/// Returns the effective API key for the given provider: user's own key
/// takes priority, otherwise falls back to the shared key from the Sheet.
Future<String> getEffectiveApiKey(String provider) async {
  final userKey = await getApiKey();
  if (userKey != null && userKey.isNotEmpty) return userKey;
  return AIModelsService.getApiKey(provider);
}

void showApiKeyDialog(BuildContext context) {
  final apiKeyController = TextEditingController();
  final obscureText = ValueNotifier<bool>(true);
  final sharedKey = ValueNotifier<String>('');

  getApiKey().then((key) {
    if (key != null && key.isNotEmpty) {
      apiKeyController.text = key;
    }
  });

  AIModelsService.getApiKey('google').then((key) {
    sharedKey.value = key;
  });

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, Color(0xFFF8F9FF)],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.key, color: Colors.blue.shade600, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('API Configuration',
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade800)),
                        const SizedBox(height: 4),
                        Text('Add your own key, or use the shared app key',
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Shared key info banner
              ValueListenableBuilder<String>(
                valueListenable: sharedKey,
                builder: (context, key, _) {
                  if (key.isEmpty) return const SizedBox.shrink();
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.verified_user, size: 16, color: Colors.green.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Shared app key active — you can use AI without adding your own key',
                            style: TextStyle(
                                fontSize: 12, color: Colors.green.shade700),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),

              // Input field
              ValueListenableBuilder<bool>(
                valueListenable: obscureText,
                builder: (context, isObscure, child) {
                  return TextField(
                    controller: apiKeyController,
                    obscureText: isObscure,
                    decoration: InputDecoration(
                      labelText: 'Your Gemini API Key (optional)',
                      hintText: 'Leave empty to use shared app key',
                      prefixIcon: Icon(Icons.lock_outline,
                          color: Colors.grey.shade500),
                      suffixIcon: IconButton(
                        icon: Icon(
                          isObscure ? Icons.visibility_off : Icons.visibility,
                          color: Colors.grey.shade500,
                        ),
                        onPressed: () => obscureText.value = !isObscure,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),

              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Cancel',
                        style: TextStyle(color: Colors.grey.shade600)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () async {
                      final key = apiKeyController.text.trim();
                      await saveApiKey(key);
                      if (!context.mounted) return;
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(key.isNotEmpty
                              ? 'API Key saved! Your key will be used first.'
                              : 'Using shared app key.'),
                          backgroundColor:
                              key.isNotEmpty ? Colors.green : Colors.blue,
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Save',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
