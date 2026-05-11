import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:pi_qbank/services/chat_history_service.dart';
import 'package:pi_qbank/models/chat_message_model.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/app_drawer.dart';
import '../config/app_config.dart';
import '../widgets/api_key_dialog.dart';
import 'personal_tone_setting_page.dart';
import '../widgets/image_generation_loader.dart';
import 'full_screen_image_page.dart';

class AIPage extends StatefulWidget {
  const AIPage({super.key});

  @override
  State<AIPage> createState() => _AIPageState();
}

class _AIPageState extends State<AIPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode(); // Add FocusNode
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  late FlutterTts flutterTts;
  XFile? _selectedImage; // New state variable for selected image
  int? _speakingMessageIndex; // To track which message is speaking
  late AnimationController _animationController;
  late Animation<Color?> _colorAnimation;
  final ChatHistoryService _chatHistoryService = ChatHistoryService();
  List<List<ChatMessageModel>> _chatHistory = []; // List of past chats
  bool _isShowingHistory = false; // To toggle between current chat and history
  int? _currentChatIndex; // Null for a new chat, index for an existing chat
  bool _isHistoryLoaded = false; // New flag to track if history is loaded

  // Personal Tone Settings
  String _toneName = '';
  String _toneGender = '';
  String _toneRelationship = '';
  String _toneLanguage = '';
  String _tonePurpose = '';
  List<Map<String, String>> _customTraits = [];
  String _textModel = 'gemma-3-27b-it';
  String _imageModel = 'gemini-2.5-flash-preview-09-2025';
  String _baseUrl = 'https://generativelanguage.googleapis.com/v1beta';
  String _provider = 'google';

  // Image generation state

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // Add observer
    _startNewChatOnLaunch(); // Start a new blank chat and load history in background
    flutterTts = FlutterTts();
    _loadPersonalToneSettings().then((_) {
      _initTts(); // Initialize TTS after tone settings are loaded
    });

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3), // Duration for one full cycle
    )..repeat(reverse: true); // Repeat the animation

    _colorAnimation = TweenSequence<Color?>(
      [
        TweenSequenceItem(
            tween: ColorTween(begin: Colors.blue, end: Colors.red), weight: 1),
        TweenSequenceItem(
            tween: ColorTween(begin: Colors.red, end: Colors.green), weight: 1),
        TweenSequenceItem(
            tween: ColorTween(begin: Colors.green, end: Colors.purple),
            weight: 1),
        TweenSequenceItem(
            tween: ColorTween(begin: Colors.purple, end: Colors.blue),
            weight: 1),
      ],
    ).animate(_animationController);
  }

  void _initTts() async {
    // Set default language based on _toneLanguage, or fallback to English
    String languageCode =
        _toneLanguage.isNotEmpty ? _getLanguageCode(_toneLanguage) : "en-US";
    bool isLanguageAvailable =
        await flutterTts.isLanguageAvailable(languageCode);

    if (isLanguageAvailable) {
      await flutterTts.setLanguage(languageCode);
    } else {
      await flutterTts.setLanguage("en-US"); // Fallback to English
    }

    await flutterTts.setSpeechRate(0.5); // Set speech rate
    await flutterTts.setVolume(1.0); // Set volume
    await flutterTts.setPitch(1.0); // Set pitch
  }

  String _getLanguageCode(String languageName) {
    switch (languageName.toLowerCase()) {
      case 'bengali':
        return 'bn-BD'; // Or 'bn-IN' for Indian Bengali
      case 'english':
        return 'en-US';
      // Add more cases as needed
      default:
        return 'en-US'; // Default to English if not recognized
    }
  }

  Future _speak(String text) async {
    // No need to call _stop() here, it's handled by the button logic
    if (text.isNotEmpty) {
      await flutterTts.speak(text);
    }
    flutterTts.setCompletionHandler(() {
      if (mounted) {
        // Add mounted check
        setState(() {
          _speakingMessageIndex = null;
        });
      }
    });
  }

  Future _stop() async {
    await flutterTts.stop();
    if (mounted) {
      // Add mounted check
      setState(() {
        _speakingMessageIndex = null;
      });
    }
  }

  Future<void> _loadChatHistory() async {
    _chatHistory = await _chatHistoryService.loadChatHistory();
    setState(() {
      _isHistoryLoaded = true; // Set flag to true once history is loaded
    });
  }

  void _startNewChatOnLaunch() {
    setState(() {
      _messages.clear();
      _selectedImage = null;
      _isLoading = false;
      _speakingMessageIndex = null;
      _isShowingHistory = false;
      _currentChatIndex = null; // Ensure a new blank chat
      _isHistoryLoaded = false; // Reset flag
    });
    _loadChatHistory(); // Load history in the background
  }

  Future<void> _saveCurrentChat() async {
    if (_messages.isNotEmpty) {
      final chatMessageModels = _messages
          .map((msg) => ChatMessageModel(
                text: msg.text,
                isUser: msg.isUser,
                imagePath: msg.imagePath,
                base64Image: msg.base64Image,
                userImageBase64: msg.userImageBase64,
              ))
          .toList();

      if (_currentChatIndex != null) {
        // Update existing chat
        await _chatHistoryService.updateChat(
            _currentChatIndex!, chatMessageModels);
      } else {
        // Save as a new chat
        final newChatIndex =
            await _chatHistoryService.saveChat(chatMessageModels);
        setState(() {
          _currentChatIndex =
              newChatIndex; // Set the current chat index to the newly saved chat
        });
      }
      await _loadChatHistory(); // Reload history after saving/updating
    }
  }

  void _startNewChat() async {
    await _saveCurrentChat(); // Save the current chat before starting a new one
    setState(() {
      _messages.clear();
      _selectedImage = null;
      _isLoading = false;
      _speakingMessageIndex = null;
      _isShowingHistory = false; // Ensure we are on the current chat view
      _currentChatIndex = null; // Reset to null for a new chat
    });
    _scrollToBottom(); // Scroll to bottom for the new chat
  }

  void _viewChatHistory(int index) async {
    await _saveCurrentChat(); // Save current chat before viewing history
    setState(() {
      _currentChatIndex = index; // Set the current chat index
      _messages.clear();
      _messages.addAll(_chatHistory[index].map((model) => ChatMessage(
            text: model.text,
            isUser: model.isUser,
            imagePath: model.imagePath,
            base64Image: model.base64Image,
            userImageBase64: model.userImageBase64,
            onSpeak: (text) => _speak(text),
            onStop: _stop,
            isSpeaking: false,
          )));
      _isShowingHistory = false; // Switch back to current chat view
    });
    _scrollToBottom();
  }

  Future<void> _loadPersonalToneSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _toneName = prefs.getString('tone_name') ?? '';
      _toneGender = prefs.getString('tone_gender') ?? '';
      _toneRelationship = prefs.getString('tone_relationship') ?? '';
      _toneLanguage = prefs.getString('tone_language') ?? '';
      _tonePurpose = prefs.getString('tone_purpose') ?? '';

      final customTraitsJson = prefs.getStringList('tone_customTraits');
      if (customTraitsJson != null) {
        _customTraits = customTraitsJson
            .map((jsonString) =>
                Map<String, String>.from(jsonDecode(jsonString)))
            .toList();
      } else {
        _customTraits = [];
      }
      _textModel = prefs.getString('global_text_model') ?? 
          prefs.getString('global_selected_model') ??
          prefs.getString('selected_model') ??
          'gemma-3-27b-it';
          
      _imageModel = prefs.getString('global_image_model') ?? 
          prefs.getString('global_selected_model') ??
          prefs.getString('selected_model') ??
          'gemini-2.5-flash-preview-09-2025';
          
      _baseUrl = prefs.getString('global_ai_base_url') ??
          'https://generativelanguage.googleapis.com/v1beta';
      _provider = prefs.getString('global_ai_provider') ?? 'google';
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // Remove observer
    _focusNode.unfocus(); // Unfocus first
    _focusNode.dispose(); // Then dispose
    _scrollController.dispose();
    _controller.dispose();
    _stop(); // Stop TTS when disposing
    _animationController.dispose(); // Dispose the animation controller
    super.dispose();
  }

  void _scrollToBottom() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _selectedImage = image;
      });
    }
  }

  Future<void> _sendMessage() async {
    final messageText = _controller.text;
    if (messageText.isEmpty && _selectedImage == null) return;

    _controller.clear();
    setState(() {
      if (_selectedImage != null) {
        // Encode image once here
        final bytes = File(_selectedImage!.path)
            .readAsBytesSync(); // Synchronous read for immediate use
        final base64EncodedImage = base64Encode(bytes);

        _messages.add(ChatMessage(
            text: 'Image attached',
            isUser: true,
            imagePath: _selectedImage!.path, // Keep for display
            userImageBase64: base64EncodedImage, // Store base64 here
            onSpeak: (text) => _speak(text),
            onStop: _stop,
            isSpeaking: false));
      }
      if (messageText.isNotEmpty) {
        _messages.add(ChatMessage(
            text: messageText,
            isUser: true,
            onSpeak: (text) => _speak(text),
            onStop: _stop,
            isSpeaking: false));
      }
      _isLoading = true;
    });

    _scrollToBottom();

    try {
      String primaryModel = _selectedImage != null ? _imageModel : _textModel;

      // Define fallback models
      List<String> modelsToTry = [primaryModel];
      if (_selectedImage != null) {
        modelsToTry.addAll([
          'gemini-2.5-flash-preview-09-2025',
          'gemini-2.0-flash',
          'gemini-1.5-flash',
          'gemini-1.5-pro'
        ]);
      } else {
        modelsToTry.addAll([
          'gemini-2.0-flash',
          'gemini-1.5-flash',
          'gemma-3-27b-it',
          'gemini-2.0-flash-lite'
        ]);
      }
      // Remove duplicates
      modelsToTry = modelsToTry.toSet().toList();

      final String? savedApiKey = await getApiKey();
      final String apiKey = savedApiKey != null && savedApiKey.isNotEmpty
          ? savedApiKey
          : AppConfig.geminiApiKey;

      http.Response? finalResponse;
      String? usedModel;

      for (var model in modelsToTry) {
        try {
          debugPrint('Trying model: $model');
          String cleanUrl = _baseUrl.trim();
          if (cleanUrl.isEmpty) {
            cleanUrl = 'https://generativelanguage.googleapis.com/v1beta';
          }
          if (cleanUrl.endsWith('/')) {
            cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
          }
          
          final bool isGoogle = _provider == 'google';
          final url = isGoogle 
              ? Uri.parse('$cleanUrl/models/$model:generateContent?key=$apiKey')
              : (cleanUrl.endsWith('/chat/completions') 
                  ? Uri.parse(cleanUrl) 
                  : Uri.parse('$cleanUrl/chat/completions'));

          Map<String, String> headers = {'Content-Type': 'application/json'};
          if (!isGoogle) {
            headers['Authorization'] = 'Bearer $apiKey';
            if (_provider == 'openrouter') {
              headers['HTTP-Referer'] = 'https://github.com/rashidsahriar/Pi-QBank';
              headers['X-Title'] = 'Pi-QBank';
            }
          }

          dynamic body;
          
          if (isGoogle) {
            List<Map<String, dynamic>> contents = [];
            String personaPrompt = "You are a real human being.";
            if (_toneName.isNotEmpty) personaPrompt += " Your name is $_toneName.";
            if (_toneGender.isNotEmpty) personaPrompt += " You identify as $_toneGender.";
            if (_toneRelationship.isNotEmpty) personaPrompt += " Your role is $_toneRelationship.";
            if (_toneLanguage.isNotEmpty) personaPrompt += " Always respond strictly in $_toneLanguage.";
            if (_tonePurpose.isNotEmpty) personaPrompt += " Your main purpose is $_tonePurpose.";
            if (_customTraits.isNotEmpty) {
              personaPrompt += " Additionally, consider these traits:";
              for (var trait in _customTraits) {
                if (trait['trait']?.isNotEmpty == true && trait['value']?.isNotEmpty == true) {
                  personaPrompt += " ${trait['trait']}: ${trait['value']}.";
                }
              }
            }

            contents.add({
              "role": "user",
              "parts": [{"text": personaPrompt}]
            });
            contents.add({
              "role": "model",
              "parts": [{"text": "Understood. I will help you."}]
            });

            for (var msg in _messages) {
              List<Map<String, dynamic>> msgParts = [];
              msgParts.add({"text": msg.text});
              if (msg.userImageBase64 != null) {
                msgParts.add({
                  "inline_data": {
                    "mime_type": "image/jpeg",
                    "data": msg.userImageBase64
                  }
                });
              } else if (msg.imagePath != null) {
                final bytes = await File(msg.imagePath!).readAsBytes();
                final base64Image = base64Encode(bytes);
                msgParts.add({
                  "inline_data": {"mime_type": "image/jpeg", "data": base64Image}
                });
              }
              contents.add({"role": msg.isUser ? "user" : "model", "parts": msgParts});
            }
            body = {"contents": contents};
          } else {
            // OpenAI / OpenRouter format
            List<Map<String, dynamic>> messages = [];
            String systemPrompt = "You are a real human being.";
            if (_toneName.isNotEmpty) systemPrompt += " Your name is $_toneName.";
            if (_toneGender.isNotEmpty) systemPrompt += " You identify as $_toneGender.";
            if (_toneRelationship.isNotEmpty) systemPrompt += " Your role is $_toneRelationship.";
            if (_toneLanguage.isNotEmpty) systemPrompt += " Always respond strictly in $_toneLanguage.";
            if (_tonePurpose.isNotEmpty) systemPrompt += " Your main purpose is $_tonePurpose.";
            if (_customTraits.isNotEmpty) {
              systemPrompt += " Additionally, consider these traits:";
              for (var trait in _customTraits) {
                if (trait['trait']?.isNotEmpty == true && trait['value']?.isNotEmpty == true) {
                  systemPrompt += " ${trait['trait']}: ${trait['value']}.";
                }
              }
            }
            
            messages.add({"role": "system", "content": systemPrompt});

            for (var msg in _messages) {
              if (msg.userImageBase64 != null || msg.imagePath != null) {
                String? b64;
                if (msg.userImageBase64 != null) {
                  b64 = msg.userImageBase64;
                } else {
                  final bytes = await File(msg.imagePath!).readAsBytes();
                  b64 = base64Encode(bytes);
                }
                messages.add({
                  "role": msg.isUser ? "user" : "assistant",
                  "content": [
                    {"type": "text", "text": msg.text},
                    {
                      "type": "image_url",
                      "image_url": {"url": "data:image/jpeg;base64,$b64"}
                    }
                  ]
                });
              } else {
                messages.add({
                  "role": msg.isUser ? "user" : "assistant",
                  "content": msg.text
                });
              }
            }
            body = {"model": model, "messages": messages};
          }

          final response = await http.post(
            url,
            headers: headers,
            body: json.encode(body),
          );

          if (response.statusCode == 200) {
            finalResponse = response;
            usedModel = model;
            break; // Success! Stop trying.
          } else {
            debugPrint('Model $model failed with ${response.statusCode}');
          }
        } catch (e) {
          debugPrint('Model $model threw exception: $e');
        }
      }

      if (finalResponse != null && finalResponse.statusCode == 200) {
        final String decodedBody = utf8.decode(finalResponse.bodyBytes);
        final jsonResponse = json.decode(decodedBody);
        if (jsonResponse['candidates'] != null &&
            jsonResponse['candidates'].isNotEmpty) {
          final reply =
              jsonResponse['candidates'][0]['content']['parts'][0]['text'];
          if (!mounted) return;
          setState(() {
            _messages.add(ChatMessage(
                text: reply,
                isUser: false,
                onSpeak: (text) => _speak(text),
                onStop: _stop,
                isSpeaking: false));
            if (usedModel != null) {
              if (_selectedImage != null) {
                _imageModel = usedModel;
              } else {
                _textModel = usedModel;
              }
            }
          });
          await _saveCurrentChat();
        } else if (jsonResponse['choices'] != null && 
                  jsonResponse['choices'].isNotEmpty) {
          // Response from OpenAI / OpenRouter
          final reply = jsonResponse['choices'][0]['message']['content'];
          if (!mounted) return;
          setState(() {
            _messages.add(ChatMessage(
                text: reply,
                isUser: false,
                onSpeak: (text) => _speak(text),
                onStop: _stop,
                isSpeaking: false));
            if (usedModel != null) {
              if (_selectedImage != null) {
                _imageModel = usedModel;
              } else {
                _textModel = usedModel;
              }
            }
          });
          await _saveCurrentChat();
        } else {
          throw Exception('Invalid response format');
        }
      } else {
        // If we get here, all models failed.
        // Try to provide a helpful error from the last attempt if possible
        if (finalResponse != null && finalResponse.statusCode == 429) {
          throw Exception(
              'All models are busy (Quota Exceeded). Please try again later.');
        }
        throw Exception(
            'Failed to get a response from any model. Please check your connection or API key.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(ChatMessage(
            text: e.toString().contains('Exception:')
                ? e.toString().replaceAll('Exception: ', '')
                : 'Something went wrong! $e',
            isUser: false,
            isError: true));
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _selectedImage = null;
        });
        _scrollToBottom();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: CustomAppBar(
        title: '${_toneName.isNotEmpty ? _toneName : 'AI Chat'} ',
        actions: [
          IconButton(
            icon: Icon(_isShowingHistory
                ? Icons.chat
                : Icons.history), // Toggle icon based on view
            onPressed: () async {
              if (!_isShowingHistory) {
                // If switching to show history, save current chat
                await _saveCurrentChat();
              }
              setState(() {
                _isShowingHistory = !_isShowingHistory;
                if (!_isShowingHistory) {
                  // If switching back to current chat view, ensure a blank chat
                  _messages.clear();
                  _currentChatIndex = null;
                  _selectedImage = null;
                  _isLoading = false;
                  _speakingMessageIndex = null;
                }
              });
              _scrollToBottom();
            },
            tooltip: _isShowingHistory ? 'Current Chat' : 'Chat History',
          ),
          IconButton(
            icon: const Icon(Icons.account_circle), // Changed to avatar icon
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const PersonalToneSettingPage()),
              ).then((_) async {
                await _loadPersonalToneSettings(); // Reload settings when returning from the settings page
                _initTts(); // Re-initialize TTS with new settings
              });
            },
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: _isShowingHistory
                    ? (_isHistoryLoaded
                        ? ListView.builder(
                            itemCount: _chatHistory.length +
                                1, // +1 for New Chat option
                            padding: const EdgeInsets.all(12.0),
                            itemBuilder: (context, index) {
                              if (index == 0) {
                                return Card(
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 8.0),
                                  child: ListTile(
                                    leading: const Icon(Icons.add_comment),
                                    title: const Text('New Chat'),
                                    onTap: _startNewChat,
                                  ),
                                );
                              }
                              final chat = _chatHistory[
                                  index - 1]; // Adjust index for history list
                              // Display a summary of the chat
                              return Card(
                                margin:
                                    const EdgeInsets.symmetric(vertical: 8.0),
                                child: ListTile(
                                  title: Text(
                                      'Chat ${(_chatHistory.length - (index - 1))}: ${chat.first.text.substring(0, chat.first.text.length > 50 ? 50 : chat.first.text.length)}...'),
                                  subtitle: Text('${chat.length} messages'),
                                  onTap: () => _viewChatHistory(
                                      index - 1), // Pass the actual index
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete),
                                    onPressed: () async {
                                      await _chatHistoryService
                                          .deleteChatAtIndex(index -
                                              1); // Adjust index for actual history list
                                      _loadChatHistory(); // Reload history after deleting
                                    },
                                  ),
                                ),
                              );
                            },
                          )
                        : const Center(
                            child:
                                CircularProgressIndicator())) // Show loader while history loads
                    : ListView.builder(
                        controller: _scrollController,
                        itemCount: _messages.length,
                        padding: const EdgeInsets.all(12.0),
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          return ChatMessage(
                            key: ValueKey(message.hashCode), // Add a unique key
                            text: message.text,
                            isUser: message.isUser,
                            imagePath: message.imagePath,
                            generatedImageUrls: message.generatedImageUrls,
                            base64Image: message.base64Image,
                            showLoader: message.showLoader,
                            onSpeak: (text) async {
                              if (_speakingMessageIndex == index) {
                                // If this message is already speaking, stop it
                                await _stop();
                              } else {
                                // If another message is speaking or nothing is speaking, start this one
                                await _stop(); // Stop any other ongoing speech
                                setState(() {
                                  _speakingMessageIndex = index;
                                });
                                await _speak(text);
                              }
                            },
                            onStop: _stop,
                            isSpeaking: _speakingMessageIndex == index,
                          );
                        },
                      ),
              ),
              if (_isLoading)
                AnimatedBuilder(
                  animation: _colorAnimation,
                  builder: (context, child) {
                    return LinearProgressIndicator(
                      valueColor:
                          AlwaysStoppedAnimation<Color?>(_colorAnimation.value),
                      backgroundColor: colorScheme.surfaceContainerHighest,
                    );
                  },
                ),
              if (!_isShowingHistory) // Only show input field if not showing history
                Container(
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(
                            bottom: 8.0, left: 12.0, right: 12.0),
                        child: Row(
                          children: [
                            Icon(Icons.smart_toy,
                                size: 16,
                                color: colorScheme.primary.withOpacity(0.7)),
                            const SizedBox(width: 8),
                            Text(
                              'Using: ${_selectedImage != null ? "$_imageModel (Image)" : "$_textModel (Text)"}',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(25),
                                color: colorScheme.surfaceContainerHighest,
                              ),
                              child: TextField(
                                focusNode: _focusNode,
                                controller: _controller,
                                maxLines: 3, // Allow up to 3 lines
                                minLines: 1, // Start with at least 1 line
                                decoration: InputDecoration(
                                  hintText: 'Type your message...',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(25),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 10,
                                  ),
                                  prefixIcon: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (_selectedImage != null)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(left: 8.0),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              CircleAvatar(
                                                backgroundImage: FileImage(
                                                    File(_selectedImage!.path)),
                                                radius: 18,
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.close),
                                                onPressed: () {
                                                  setState(() {
                                                    _selectedImage = null;
                                                  });
                                                },
                                              ),
                                            ],
                                          ),
                                        )
                                      else
                                        IconButton(
                                          icon: const Icon(Icons.image),
                                          onPressed:
                                              _isLoading ? null : _pickImage,
                                        ),
                                      /* Image generation button removed */
                                    ],
                                  ),
                                ),
                                onSubmitted: (_) => _sendMessage(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: colorScheme.primary,
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: _isLoading
                                    ? null
                                    : _sendMessage, // Call _sendMessage without image parameter
                                customBorder: const CircleBorder(),
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Icon(
                                    Icons.send_rounded,
                                    color: colorScheme.onPrimary,
                                    size: 24,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class ChatMessage extends StatelessWidget {
  final String text;
  final bool isUser;
  final String? imagePath;
  final List<String>? generatedImageUrls;
  final String? base64Image;
  final bool showLoader;
  final Function(String text)? onSpeak;
  final Function()? onStop;
  final bool isSpeaking;
  final String? userImageBase64; // New field for user's base64 image
  final bool isError; // New field for error messages

  const ChatMessage({
    super.key,
    required this.text,
    required this.isUser,
    this.imagePath,
    this.generatedImageUrls,
    this.base64Image,
    this.showLoader = false,
    this.onSpeak,
    this.onStop,
    this.isSpeaking = false,
    this.userImageBase64, // Initialize new field
    this.isError = false, // Initialize new field
  });

  List<TextSpan> _formatText(String text, BuildContext context) {
    final List<TextSpan> spans = [];
    final TextStyle defaultStyle = TextStyle(
      color: isUser ? Colors.white : Colors.black,
      fontSize: 15,
    );

    final lines = text.split('\n');
    bool inCodeBlock = false;
    List<String> codeLines = [];

    for (int i = 0; i < lines.length; i++) {
      String line = lines[i];

      // Handle code blocks
      if (line.trim().startsWith('```')) {
        if (inCodeBlock) {
          spans.add(TextSpan(
            text: codeLines.join('\n'),
            style: defaultStyle.copyWith(
              fontFamily: 'monospace',
              backgroundColor: Colors.grey[200],
              color: Colors.black87,
            ),
          ));
          codeLines.clear();
          inCodeBlock = false;
        } else {
          inCodeBlock = true;
        }
        continue;
      }

      if (inCodeBlock) {
        codeLines.add(line);
        continue;
      }

      // Handle bullet points first - before any other formatting
      if (line.trim().startsWith('* ') && !line.trim().endsWith('*')) {
        // This is a bullet point, not italic text
        spans.add(TextSpan(
          text: '• ',
          style: defaultStyle.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: Theme.of(context).colorScheme.primary,
          ),
        ));
        line = line.replaceFirst('* ', ''); // Remove the bullet marker
      }

      // Process text formatting
      String currentText = line;
      List<TextSpan> lineSpans = [];

      // Process boldest (***text***)
      while (currentText.contains('***')) {
        int startIndex = currentText.indexOf('***');
        int endIndex = currentText.indexOf('***', startIndex + 3);

        if (endIndex != -1) {
          // Add text before the marker
          if (startIndex > 0) {
            lineSpans.add(TextSpan(
                text: currentText.substring(0, startIndex),
                style: defaultStyle));
          }

          // Add the bold+italic text
          lineSpans.add(TextSpan(
            text: currentText.substring(startIndex + 3, endIndex),
            style: defaultStyle.copyWith(
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
              color: Theme.of(context).colorScheme.primary,
              fontSize: 18, // Increased size for boldest text
            ),
          ));

          currentText = currentText.substring(endIndex + 3);
        } else {
          break;
        }
      }

      // Process bold (**text**)
      while (currentText.contains('**')) {
        int startIndex = currentText.indexOf('**');
        int endIndex = currentText.indexOf('**', startIndex + 2);

        if (endIndex != -1) {
          // Add text before the marker
          if (startIndex > 0) {
            lineSpans.add(TextSpan(
                text: currentText.substring(0, startIndex),
                style: defaultStyle));
          }

          // Add the bold text
          lineSpans.add(TextSpan(
            text: currentText.substring(startIndex + 2, endIndex),
            style: defaultStyle.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 16, // Increased size for bold text
            ),
          ));

          currentText = currentText.substring(endIndex + 2);
        } else {
          break;
        }
      }

      // Process italic (*text*)
      while (currentText.contains('*')) {
        int startIndex = currentText.indexOf('*');
        int endIndex = currentText.indexOf('*', startIndex + 1);

        if (endIndex != -1) {
          // Add text before the marker
          if (startIndex > 0) {
            lineSpans.add(TextSpan(
                text: currentText.substring(0, startIndex),
                style: defaultStyle));
          }

          // Add the italic text
          lineSpans.add(TextSpan(
            text: currentText.substring(startIndex + 1, endIndex),
            style: defaultStyle.copyWith(fontStyle: FontStyle.italic),
          ));

          currentText = currentText.substring(endIndex + 1);
        } else {
          break;
        }
      }

      // Add any remaining text
      if (currentText.isNotEmpty) {
        lineSpans.add(TextSpan(text: currentText, style: defaultStyle));
      }

      // Add the processed line spans
      spans.addAll(lineSpans);

      // Add newline if not the last line
      if (i < lines.length - 1) {
        spans.add(const TextSpan(text: '\n'));
      }
    }

    return spans;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 8.0),
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(12.0),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? Colors.blue
              : isError
                  ? Colors.red.shade100 // different color for error
                  : Colors.grey[300],
          borderRadius: BorderRadius.circular(12.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.20),
              spreadRadius: 1,
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          // Changed to Column to stack text and image
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imagePath != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => FullScreenImagePage(
                          imagePath: imagePath,
                        ),
                      ),
                    );
                  },
                  child: Image.file(
                    File(imagePath!),
                    height: 150,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            if (showLoader) // Changed condition to use showLoader flag
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: ImageGenerationLoader(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            if (base64Image != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => FullScreenImagePage(
                          base64Image: base64Image,
                        ),
                      ),
                    );
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8.0),
                    child: Image.memory(
                      base64Decode(base64Image!),
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            if (generatedImageUrls != null)
              Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                children: generatedImageUrls!
                    .map((url) => Image.network(
                          url,
                          height: 150,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return SizedBox(
                              height: 150,
                              width: 150,
                              child: Center(child: CircularProgressIndicator()),
                            );
                          },
                        ))
                    .toList(),
              ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                isUser
                    ? Text(text, style: const TextStyle(color: Colors.white))
                    : SelectableText.rich(
                        TextSpan(
                            children: _formatText(text, context),
                            style: TextStyle(
                              color: isError
                                  ? Colors.red.shade900
                                  : Colors.black, // Dark text for error
                            )),
                        onTap: () {},
                      ),
                if (!isUser && !showLoader && text.isNotEmpty)
                  Align(
                    alignment: Alignment.bottomRight,
                    child: IconButton(
                      icon: Icon(
                        isSpeaking ? Icons.volume_off : Icons.volume_up,
                        color: isUser ? Colors.white : Colors.black,
                      ),
                      onPressed: () {
                        if (isSpeaking) {
                          onStop?.call();
                        } else {
                          onSpeak?.call(text);
                        }
                      },
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
