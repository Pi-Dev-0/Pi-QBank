import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:ui'; // Import for ImageFilter
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

class _AIPageState extends State<AIPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  late FlutterTts flutterTts;
  XFile? _selectedImage; // New state variable for selected image
  int? _speakingMessageIndex; // To track which message is speaking

  // Personal Tone Settings
  String _toneName = '';
  String _toneGender = '';
  String _toneRelationship = '';
  String _toneLanguage = '';
  String _tonePurpose = '';
  List<Map<String, String>> _customTraits = [];
  String _selectedModel = 'gemini-2.5-flash-preview-05-20'; // Default model
  // Removed _customApiKey as it will be fetched directly

  // Image generation state
  bool _isGeneratingImage = false;

  @override
  void initState() {
    super.initState();
    _loadPersonalToneSettings(); // Load settings on init
    flutterTts = FlutterTts();
    _initTts();
  }

  void _initTts() async {
    // Set default language based on _toneLanguage, or fallback to English
    String languageCode = _toneLanguage.isNotEmpty ? _getLanguageCode(_toneLanguage) : "en-US";
    bool isLanguageAvailable = await flutterTts.isLanguageAvailable(languageCode);

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
      setState(() {
        _speakingMessageIndex = null;
      });
    });
  }

  Future _stop() async {
    await flutterTts.stop();
    setState(() {
      _speakingMessageIndex = null;
    });
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
      _selectedModel = prefs.getString('selected_model') ??
          'gemini-2.5-flash-preview-05-20'; // Default to gemini-2.5-flash-preview-05-20 if not found
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _controller.dispose();
    _stop(); // Stop TTS when disposing
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
            _messages.add(ChatMessage(
                text: 'Image attached',
                isUser: true,
                imagePath: _selectedImage!.path,
                onSpeak: (text) => _speak(text), // Pass text only
                onStop: _stop,
                isSpeaking: false));
      }
      if (messageText.isNotEmpty) {
        _messages.add(ChatMessage(text: messageText, isUser: true, onSpeak: (text) => _speak(text), onStop: _stop, isSpeaking: false));
      }
      _isLoading = true;
    });

    _scrollToBottom();

    try {
      final String model = _selectedImage != null
          ? 'gemini-2.0-flash' // Model for image chat
          : _selectedModel; // Use selected model for text chat

      // Use custom API key if provided, otherwise fall back to default
      final String? savedApiKey =
          await getApiKey(); // Get API key from dialog's shared preferences
      final String apiKey = savedApiKey != null && savedApiKey.isNotEmpty
          ? savedApiKey
          : AppConfig.geminiApiKey;

      final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey');

      List<Map<String, dynamic>> contents = [];

      // Construct the persona prompt from settings
      String personaPrompt = "You are a real human being.";

      if (_toneName.isNotEmpty) {
        personaPrompt += " Your name is $_toneName.";
      }
      if (_toneGender.isNotEmpty) {
        personaPrompt += " You identify as $_toneGender.";
      }

      // Directly assign the AI's role based on the 'relationship' setting
      if (_toneRelationship.isNotEmpty) {
        personaPrompt += " Your role is $_toneRelationship.";
      }

      if (_toneLanguage.isNotEmpty) {
        personaPrompt +=
            " Always respond strictly in $_toneLanguage."; // Emphasize strict language
      }
      if (_tonePurpose.isNotEmpty) {
        personaPrompt += " Your main purpose is $_tonePurpose.";
      }
      if (_customTraits.isNotEmpty) {
        personaPrompt +=
            " Additionally, consider these specific traits and integrate them into your responses:";
        for (var trait in _customTraits) {
          if (trait['trait'] != null &&
              trait['value'] != null &&
              trait['trait']!.isNotEmpty &&
              trait['value']!.isNotEmpty) {
            personaPrompt += " ${trait['trait']}: ${trait['value']}.";
          }
        }
      }

      // Add the persona prompt as an initial user message to set the context
      // The model's immediate response acknowledges this setup.
      contents.add({
        "role": "user",
        "parts": [
          {"text": personaPrompt}
        ]
      });
      contents.add({
        "role": "model",
        "parts": [
          {
            "text":
                "Understood. I will adhere to these guidelines. How can I assist you today?"
          }
        ]
      });

      // Add previous messages to the conversation history
      for (var msg in _messages) {
        List<Map<String, dynamic>> msgParts = [];
        msgParts.add({"text": msg.text});

        if (msg.imagePath != null) {
          final bytes = await File(msg.imagePath!).readAsBytes();
          final base64Image = base64Encode(bytes);
          msgParts.add({
            "inline_data": {"mime_type": "image/jpeg", "data": base64Image}
          });
        }
        contents
            .add({"role": msg.isUser ? "user" : "model", "parts": msgParts});
      }

      // Add the current message
      List<Map<String, dynamic>> currentParts = [];
      if (messageText.isNotEmpty) {
        currentParts.add({"text": messageText});
      }
      if (_selectedImage != null) {
        final bytes = await _selectedImage!.readAsBytes();
        final base64Image = base64Encode(bytes);
        currentParts.add({
          "inline_data": {"mime_type": "image/jpeg", "data": base64Image}
        });
      }
      contents.add({"role": "user", "parts": currentParts});

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({"contents": contents}),
      );

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        if (jsonResponse['candidates'] != null &&
            jsonResponse['candidates'].isNotEmpty) {
          final reply =
              jsonResponse['candidates'][0]['content']['parts'][0]['text'];
          setState(() {
            _messages.add(ChatMessage(text: reply, isUser: false, onSpeak: (text) => _speak(text), onStop: _stop, isSpeaking: false));
          });
        } else {
          throw Exception('Invalid response format or empty candidates');
        }
      } else {
        throw Exception(
            'Something went wrong! Consider using your own API key.');
      }
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage(
            text: 'Something went wrong! Consider using your own API Key.',
            isUser: false));
      });
    } finally {
      setState(() {
        _isLoading = false;
        _selectedImage = null;
      });
      _scrollToBottom();
    }
  }

  Future<void> _generateImage() async {
    if (_controller.text.isEmpty) return;

    setState(() {
      _isGeneratingImage = true;
      _messages.add(ChatMessage(
          text: "Generating image...", isUser: false, showLoader: true));
    });
    _scrollToBottom(); // Add scroll after showing loader

    try {
      final String? savedApiKey =
          await getApiKey(); // Get API key from dialog's shared preferences
      final String apiKey = savedApiKey != null && savedApiKey.isNotEmpty
          ? savedApiKey
          : AppConfig.geminiApiKey;
      final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-preview-image-generation:generateContent?key=$apiKey');

      final requestBody = {
        "contents": [
          {
            "parts": [
              {"text": _controller.text}
            ]
          }
        ],
        "generationConfig": {
          "temperature": 0.4,
          "topP": 1,
          "topK": 32,
          "maxOutputTokens": 2048,
          "responseModalities": ["TEXT", "IMAGE"]
        }
      };

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        final contentParts = jsonResponse['candidates'][0]['content']['parts'];

        String generatedText = '';
        String? base64Image;

        for (var part in contentParts) {
          if (part.containsKey('text')) {
            generatedText = part['text'];
          } else if (part.containsKey('inlineData') &&
              part['inlineData'].containsKey('data')) {
            base64Image = part['inlineData']['data'];
          }
        }

        setState(() {
          // Remove the loading message
          _messages.removeLast();
          // Add the final message with image
          _messages.add(ChatMessage(
            text: generatedText.isNotEmpty ? generatedText : "Generated image:",
            isUser: false,
            base64Image: base64Image,
            onSpeak: (text) => _speak(text),
            onStop: _stop,
            isSpeaking: false,
          ));
          _scrollToBottom(); // Add scroll after adding generated image
        });
      } else {
        throw Exception('Failed to generate image!');
      }
    } catch (e) {
      setState(() {
        // Remove the loading message first
        _messages.removeLast();
        // Then add the error message
        _messages.add(ChatMessage(
            text: 'Failed to generate image. Consider using your own API Key.',
            isUser: false,
            onSpeak: (text) => _speak(text),
            onStop: _stop,
            isSpeaking: false));
        _scrollToBottom();
      });
    } finally {
      setState(() {
        _isGeneratingImage = false;
        _controller.clear();
      });
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
            icon: const Icon(Icons.account_circle), // Changed to avatar icon
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const PersonalToneSettingPage()),
              ).then((_) {
                _loadPersonalToneSettings(); // Reload settings when returning from the settings page
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
                child: ListView.builder(
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
            LinearProgressIndicator(
              color: colorScheme.primary,
              backgroundColor: colorScheme.surfaceContainerHighest,
            ),
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
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(25),
                      color: colorScheme.surfaceContainerHighest,
                    ),
                    child: TextField(
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
                                padding: const EdgeInsets.only(left: 8.0),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircleAvatar(
                                      backgroundImage:
                                          FileImage(File(_selectedImage!.path)),
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
                                onPressed: _isLoading ? null : _pickImage,
                              ),
                            if (_selectedImage ==
                                null) // Only show auto_awesome when no image is selected
                              IconButton(
                                icon: const Icon(Icons.auto_awesome),
                                onPressed: _isLoading || _isGeneratingImage
                                    ? null
                                    : _generateImage,
                                tooltip: 'Generate Image',
                              ),
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
          ),
        ],
      ),
          if (_selectedImage != null)
            Positioned(
              bottom: 80.0, // Adjust this value to position above the input field
              left: 12.0,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 0.0, vertical: 8.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end, // Align buttons to the bottom
                  crossAxisAlignment: CrossAxisAlignment.start, // Align buttons to the left
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(25.0), // Rounded corners for the glass effect
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0), // Blurry effect
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(25),
                            border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.green,
                                blurRadius: 15,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: TextButton.icon(
                            onPressed: () {
                              _controller.text = 'Extract text from image';
                              _sendMessage();
                            },
                            icon: const Icon(Icons.text_fields, color: Colors.white), // White icon for contrast
                            label: const Text('Extract text', style: TextStyle(color: Colors.white)), // White text for contrast
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8), // Use height for vertical spacing
                    ClipRRect(
                      borderRadius: BorderRadius.circular(25),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(25),
                            border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.deepPurpleAccent,
                                blurRadius: 15,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: TextButton.icon(
                            onPressed: () {
                              _controller.text = 'Summarize this image';
                              _sendMessage();
                            },
                            icon: const Icon(Icons.summarize, color: Colors.white),
                            label: const Text('Summarize', style: TextStyle(color: Colors.white)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8), // Use height for vertical spacing
                    ClipRRect(
                      borderRadius: BorderRadius.circular(25),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(25),
                            border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.blue,
                                blurRadius: 15,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: TextButton.icon(
                            onPressed: () {
                              _controller.text = 'Describe this image';
                              _sendMessage();
                            },
                            icon: const Icon(Icons.description, color: Colors.white),
                            label: const Text('Describe', style: TextStyle(color: Colors.white)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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
          color: isUser ? Colors.blue : Colors.grey[300],
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
                        TextSpan(children: _formatText(text, context)),
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
