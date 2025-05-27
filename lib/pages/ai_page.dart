import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_gemini/flutter_gemini.dart'; // Main import for flutter_gemini
import 'package:image_picker/image_picker.dart'; // Import image_picker
import 'dart:io'; // Import dart:io for File
import '../widgets/custom_app_bar.dart';
import '../widgets/app_drawer.dart';

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
  XFile? _selectedImage; // New state variable for selected image

  @override
  void initState() {
    super.initState();
    Gemini.init(apiKey: 'AIzaSyDcCUa6A0K7ybStUl70iOr0MQQ47zgbA-0');
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _controller.dispose();
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
            imagePath: _selectedImage!.path));
      }
      if (messageText.isNotEmpty) {
        _messages.add(ChatMessage(text: messageText, isUser: true));
      }
      _isLoading = true;
    });

    _scrollToBottom();

    try {
      // Build the conversation history string
      String conversationHistory = '';
      for (var msg in _messages) {
        conversationHistory += '${msg.isUser ? 'User' : 'AI'}: ${msg.text}\n';
        if (msg.imagePath != null) {
          conversationHistory +=
              'User: [Image attached]\n'; // Indicate image in history
        }
      }
      conversationHistory += 'User: $messageText\n'; // Add current message

      final response = await Gemini.instance.textAndImage(
        text: conversationHistory, // Send entire history as text
        images:
            _selectedImage != null ? [await _selectedImage!.readAsBytes()] : [],
      );

      if (response != null && response.content?.parts?.isNotEmpty == true) {
        final reply = response.content!.parts!.map((e) => e.text).join();
        setState(() {
          _messages.add(ChatMessage(text: reply, isUser: false));
        });
      } else {
        throw Exception('Invalid response format or empty response');
      }
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage(
            text: 'Error: Failed to get response. Please try again. ($e)',
            isUser: false));
      });
    } finally {
      setState(() {
        _isLoading = false;
        _selectedImage = null; // Clear selected image after sending
      });
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: const CustomAppBar(title: 'AI Assistant'),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _messages.length,
              padding: const EdgeInsets.all(12.0),
              itemBuilder: (context, index) => _messages[index],
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
                        prefixIcon: _selectedImage != null
                            ? Padding(
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
                            : IconButton(
                                icon: const Icon(Icons.image),
                                onPressed: _isLoading ? null : _pickImage,
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
    );
  }
}

class ChatMessage extends StatelessWidget {
  final String text;
  final bool isUser;
  final String? imagePath; // Added for displaying images

  const ChatMessage(
      {super.key, required this.text, required this.isUser, this.imagePath});

  List<TextSpan> _formatText(String text, BuildContext context) {
    final List<TextSpan> spans = [];
    final TextStyle defaultStyle = TextStyle(
      color: isUser ? Colors.white : Colors.black,
      fontSize: 15,
    );

    final lines = text.split('\n');

    for (int i = 0; i < lines.length; i++) {
      String line = lines[i];

      // Handle colons first
      if (line.contains(':')) {
        final parts = line.split(':');
        spans.add(TextSpan(
          text: '${parts.first}:', // Include the colon in bold
          style: defaultStyle.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ));
        if (parts.length > 1) {
          spans.add(TextSpan(
            text: parts.sublist(1).join(':'),
            style: defaultStyle,
          ));
        }
        if (i < lines.length - 1) spans.add(const TextSpan(text: '\n'));
        continue;
      }

      // Handle headers
      if (line.startsWith('### ')) {
        spans.add(TextSpan(
          text: line.substring(4),
          style: defaultStyle.copyWith(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: Colors.black87,
          ),
        ));
        if (i < lines.length - 1) spans.add(const TextSpan(text: '\n'));
        continue;
      }

      if (line.startsWith('## ')) {
        spans.add(TextSpan(
          text: line.substring(3),
          style: defaultStyle.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Colors.black87,
          ),
        ));
        if (i < lines.length - 1) spans.add(const TextSpan(text: '\n'));
        continue;
      }

      // Handle bullet points for single asterisk
      if (line.trimLeft().startsWith('* ')) {
        spans.add(TextSpan(
          text: '•',
          style: defaultStyle.copyWith(
            fontSize: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
        ));
        line = line.replaceFirst('* ', '');
      }

      // Handle numbers (1. 2. etc)
      final numberPattern = RegExp(r'^\d+\.\s');
      if (numberPattern.hasMatch(line)) {
        final match = numberPattern.firstMatch(line);
        spans.add(TextSpan(
          text: match!.group(0),
          style: defaultStyle.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
              fontSize: 18),
        ));
        line = line.substring(match.end);
      }

      // Handle double asterisk for strong emphasis
      final strongPattern = RegExp(r'\*\*(.*?)\*\*');
      final hashtags = RegExp(r'#\w+');

      int lastIndex = 0;

      // First handle strong emphasis
      final strongMatches = strongPattern.allMatches(line);
      for (final match in strongMatches) {
        if (match.start > lastIndex) {
          spans.add(TextSpan(
            text: line.substring(lastIndex, match.start),
            style: defaultStyle,
          ));
        }

        spans.add(TextSpan(
          text: match.group(1),
          style: defaultStyle.copyWith(
            fontWeight: FontWeight.w900, // Stronger weight for **text**
            fontSize: defaultStyle.fontSize! * 1.1, // Slightly larger
          ),
        ));

        lastIndex = match.end;
      }

      // Handle remaining text and hashtags
      String remainingText = line.substring(lastIndex);
      final hashtagMatches = hashtags.allMatches(remainingText);
      lastIndex = 0;

      for (final match in hashtagMatches) {
        if (match.start > lastIndex) {
          spans.add(TextSpan(
            text: remainingText.substring(lastIndex, match.start),
            style: defaultStyle,
          ));
        }

        spans.add(TextSpan(
          text: match.group(0),
          style: defaultStyle.copyWith(
            color: Colors.blue,
            fontWeight: FontWeight.bold,
          ),
        ));

        lastIndex = match.end;
      }

      // Add any remaining text after hashtags
      if (lastIndex < remainingText.length) {
        spans.add(TextSpan(
          text: remainingText.substring(lastIndex),
          style: defaultStyle,
        ));
      }

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
      margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(12.0),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        decoration: BoxDecoration(
          color: isUser ? Colors.blue : Colors.grey[300],
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Column(
          // Changed to Column to stack text and image
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imagePath != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Image.file(
                  File(imagePath!),
                  height: 150,
                  fit: BoxFit.cover,
                ),
              ),
            isUser
                ? Text(text, style: const TextStyle(color: Colors.white))
                : SelectableText.rich(
                    TextSpan(children: _formatText(text, context)),
                    onTap: () {},
                  ),
          ],
        ),
      ),
    );
  }
}
