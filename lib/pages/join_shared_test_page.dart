import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:pi_qbank/widgets/custom_app_bar.dart';
import 'package:pi_qbank/pages/mcq_test_page.dart';
import 'package:pi_qbank/pages/short_question_page.dart';

// IMPORTANT: Replace this with your actual Google Apps Script Web App URL
const String kAppsScriptUrl = "https://script.google.com/macros/s/AKfycbxgeWMYp5dku6jtpgG2CVF-5RJn15VBq3_zmdfoxtmWvMIuT6TK8nTLk48fXgBfvpIzdA/exec";

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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _joinTest() async {
    final String code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      _showError('Please enter a Share Code');
      return;
    }

    if (kAppsScriptUrl == "YOUR_APPS_SCRIPT_URL_HERE") {
      _showError('The Apps Script URL has not been configured yet.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.get(Uri.parse('$kAppsScriptUrl?testId=$code'));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          _navigateToTest(data);
        } else {
          _showError(data['error'] ?? 'Failed to fetch test. Check your code.');
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
    final String testType = data['testType'];
    final String language = data['language'];
    final int duration = int.tryParse(data['duration'].toString()) ?? 10;
    final String jsonData = data['jsonData'];

    try {
      final decodedJson = json.decode(jsonData);
      final questions = decodedJson['questions'] as List?;
      
      if (questions == null || questions.isEmpty) {
        _showError('Invalid test data format.');
        return;
      }

      if (testType == 'MCQ') {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MCQTestPage(
              numberOfQuestions: questions.length,
              testTimeInMinutes: duration,
              aiResponse: jsonData,
              language: language,
            ),
          ),
        );
      } else if (testType == 'Short Question') {
        String formattedResponse = '';
        for (int i = 0; i < questions.length; i++) {
          final q = questions[i];
          formattedResponse += '${i + 1}. ${q['question']}\nউত্তর: ${q['answer']}\n\n';
        }

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ShortQuestionPage(
              numberOfQuestions: questions.length,
              testTimeInMinutes: duration,
              aiResponse: formattedResponse,
              language: language,
            ),
          ),
        );
      } else {
        _showError('Unsupported test type shared.');
      }
    } catch (e) {
      _showError('Error parsing test data.');
    }
  }

  Future<void> _pasteFromClipboard() async {
    ClipboardData? data = await Clipboard.getData('text/plain');
    if (data != null && data.text != null) {
      if (!mounted) return;
      setState(() {
        _codeController.text = data.text!;
      });
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
                    const Icon(Icons.group_add_outlined, size: 64, color: Colors.white),
                    const SizedBox(height: 16),
                    const Text(
                      'Join a Test',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter the 6-character Share Code provided by your teacher or friend to start the test.',
                      style: TextStyle(fontSize: 14, color: Colors.indigo.shade100, height: 1.4),
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
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _codeController,
                      textCapitalization: TextCapitalization.characters,
                      textAlign: TextAlign.center,
                      maxLength: 6,
                      style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        hintText: 'XXXXXX',
                        counterText: '',
                        fillColor: Colors.grey.shade50,
                        filled: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.grey.shade300)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.grey.shade300)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.indigo.shade400, width: 2)),
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
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 4,
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                              )
                            : const Text(
                                'Join Test',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
