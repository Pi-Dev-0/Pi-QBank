import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/scheduler.dart';
import 'package:pi_qbank/config/app_config.dart';
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

  Future<void> _sendMessage() async {
    final messageText = _controller.text;
    if (messageText.isEmpty) return;

    _controller.clear();
    setState(() {
      _messages.add(ChatMessage(text: messageText, isUser: true));
      _isLoading = true;
    });

    _scrollToBottom();

    try {
      final response = await http.post(
        Uri.parse(AppConfig.geminiApiKey),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'role': 'user',
              'parts': [
                {'text': messageText}
              ]
            }
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['candidates']?[0]?['content']?['parts']?[0]?['text'] != null) {
          final reply = data['candidates'][0]['content']['parts'][0]['text'];
          setState(() {
            _messages.add(ChatMessage(text: reply, isUser: false));
          });
        } else {
          throw Exception('Invalid response format');
        }
      } else {
        throw Exception('Failed to get response');
      }
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage(
            text: 'Error: Failed to get response. Please try again.',
            isUser: false));
      });
    } finally {
      setState(() {
        _isLoading = false;
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
                      onTap: _isLoading ? null : _sendMessage,
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

  const ChatMessage({super.key, required this.text, required this.isUser});

  List<TextSpan> _formatText(String text, BuildContext context) {
    final List<TextSpan> spans = [];
    final TextStyle defaultStyle = TextStyle(
      color: isUser ? Colors.white : Colors.black,
      fontSize: 15,
    );

    final lines = text.split('\n');

    for (int i = 0; i < lines.length; i++) {
      String line = lines[i];

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
        child: isUser
            ? Text(text, style: const TextStyle(color: Colors.white))
            : SelectableText.rich(
                TextSpan(children: _formatText(text, context)),
                onTap: () {},
              ),
      ),
    );
  }
}
