import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pi_qbank/config/app_config.dart';
import 'package:pi_qbank/pages/mcq_test_page.dart';
import 'package:pi_qbank/pages/short_question_page.dart';
import 'package:pi_qbank/utils/test_json.dart';
import 'package:pi_qbank/widgets/custom_app_bar.dart';

class JoinSharedTestPage extends StatefulWidget {
  const JoinSharedTestPage({super.key});

  @override
  State<JoinSharedTestPage> createState() => _JoinSharedTestPageState();
}

class _JoinSharedTestPageState extends State<JoinSharedTestPage> {
  final TextEditingController _codeController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
  }

  Future<void> _joinTest() async {
    final String code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      _showError('Please enter a Share Code');
      return;
    }

    if (AppConfig.testShareApi.trim().isEmpty) {
      _showError('The Apps Script URL has not been configured yet.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final uri = Uri.parse(AppConfig.testShareApi).replace(
        queryParameters: {'testId': code},
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (data is! Map) {
          _showError('The server returned an unexpected response.');
          return;
        }
        final successValue = data['success'];
        final success = successValue == true ||
            (successValue is String && successValue.toLowerCase() == 'true') ||
            '${data['status'] ?? ''}'.toUpperCase() == 'SUCCESS';
        if (success) {
          if (!mounted) return;
          _navigateToTest(Map<String, dynamic>.from(data));
        } else {
          _showError(
              '${data['error'] ?? 'Failed to fetch test. Check your code.'}');
        }
      } else {
        _showError('Server error: ${response.statusCode}');
      }
    } catch (e) {
      _showError('Network error: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _navigateToTest(Map<String, dynamic> data) {
    final testTypeLabel = '${data['testType'] ?? ''}';
    final language = '${data['language'] ?? 'বাংলা'}';
    final duration =
        (int.tryParse('${data['duration'] ?? ''}') ?? 10).clamp(1, 180);
    final jsonData = '${data['jsonData'] ?? ''}';

    final type = TestType.tryFromLabel(testTypeLabel);
    if (type == null) {
      _showError('Unsupported test type shared.');
      return;
    }
    if (type == TestType.creative) {
      _showError('Creative Question tests cannot be joined yet.');
      return;
    }

    try {
      final test = parseTest(jsonData, type);

      if (type == TestType.mcq) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MCQTestPage(
              numberOfQuestions: test.questions.length,
              testTimeInMinutes: duration,
              aiResponse: test.normalizedJson,
              language: language,
              aiTopic: test.topic,
            ),
          ),
        );
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ShortQuestionPage(
              numberOfQuestions: test.questions.length,
              testTimeInMinutes: duration,
              aiResponse: formatShortQuestions(test.questions, language),
              language: language,
              aiTopic: test.topic,
            ),
          ),
        );
      }
    } on TestFormatException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Error parsing test data.');
    }
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData('text/plain');
      if (!mounted) return;

      final text = data?.text?.trim() ?? '';
      if (text.isEmpty) {
        _showError('The clipboard is empty.');
        return;
      }

      _codeController.text = text;
      setState(() {});
    } catch (_) {
      _showError('Could not read the clipboard.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: CustomAppBar(
        title: 'Join Shared Test',
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Colors.indigo.shade500, Colors.indigo.shade800],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.indigo.withOpacity(0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const Icon(Icons.group_add_outlined,
                        size: 64, color: Colors.white),
                    const SizedBox(height: 16),
                    const Text(
                      'Join a Test',
                      style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter the 6-character Share Code provided by your teacher or friend to start the test.',
                      style: TextStyle(
                          fontSize: 14,
                          color: Colors.indigo.shade100,
                          height: 1.4),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 48),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Share Code',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _codeController,
                      textCapitalization: TextCapitalization.characters,
                      textAlign: TextAlign.center,
                      maxLength: 6,
                      style: const TextStyle(
                          fontSize: 24,
                          letterSpacing: 8,
                          fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        hintText: 'XXXXXX',
                        counterText: '',
                        fillColor: Colors.grey.shade50,
                        filled: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide:
                                BorderSide(color: Colors.grey.shade300)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide:
                                BorderSide(color: Colors.grey.shade300)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                                color: Colors.indigo.shade400, width: 2)),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.paste_outlined),
                          onPressed: _pasteFromClipboard,
                          tooltip: 'Paste from clipboard',
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _joinTest,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo.shade600,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          elevation: 4,
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 3),
                              )
                            : const Text(
                                'Join Test',
                                style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
