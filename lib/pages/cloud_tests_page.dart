import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:pi_qbank/widgets/custom_app_bar.dart';
import 'package:pi_qbank/pages/mcq_test_page.dart';

class CloudTestsPage extends StatefulWidget {
  const CloudTestsPage({super.key});

  @override
  State<CloudTestsPage> createState() => _CloudTestsPageState();
}

class _CloudTestsPageState extends State<CloudTestsPage> {
  bool _isLoading = true;
  String? _errorMessage;
  
  // Grouped tests: Key is a unique identifier (timestamp)
  final Map<String, _CloudTestGroup> _testGroups = {};

  final String _googleWebAppUrl = 'https://script.google.com/macros/s/AKfycbwAMFYO2yPtEmxK1Jbhu727bSvFei8I7ZQzUqXm079Gzj4w_tw9xreN3j3bl9mrwtkbTg/exec?action=getTests';

  @override
  void initState() {
    super.initState();
    _fetchCloudTests();
  }

  Future<void> _fetchCloudTests() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.get(Uri.parse(_googleWebAppUrl));
      if (response.statusCode == 200 || response.statusCode == 302) {
        String body = response.body;
        // In case of 302, Apps Script redirects, but http package follows redirects automatically.
        // So response.body should be the final output.
        final Map<String, dynamic> jsonResponse = json.decode(body);
        if (jsonResponse['status'] == 'success') {
          _parseTests(jsonResponse['data']);
        } else {
          setState(() {
            _errorMessage = 'Failed to load tests: ${jsonResponse['message'] ?? 'Unknown error'}';
          });
        }
      } else {
        setState(() {
          _errorMessage = 'Server error: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Network error: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _parseTests(Map<String, dynamic> data) {
    _testGroups.clear();
    
    // Parse MCQ
    if (data['MCQ'] != null) {
      for (var q in data['MCQ']) {
        String ts = q['timestamp']?.toString() ?? 'unknown_time';
        String key = 'MCQ_$ts';
        if (!_testGroups.containsKey(key)) {
          _testGroups[key] = _CloudTestGroup(
            timestamp: ts,
            testType: 'MCQ',
            className: q['className']?.toString() ?? 'N/A',
            subject: q['subject']?.toString() ?? 'N/A',
            topic: q['topic']?.toString() ?? 'N/A',
            language: q['language']?.toString() ?? 'English',
          );
        }
        _testGroups[key]!.questions.add(q);
      }
    }

    // Short Question
    if (data['Short Question'] != null) {
      for (var q in data['Short Question']) {
        String ts = q['timestamp']?.toString() ?? 'unknown_time';
        String key = 'Short_$ts';
        if (!_testGroups.containsKey(key)) {
          _testGroups[key] = _CloudTestGroup(
            timestamp: ts,
            testType: 'Short Question',
            className: q['className']?.toString() ?? 'N/A',
            subject: q['subject']?.toString() ?? 'N/A',
            topic: q['topic']?.toString() ?? 'N/A',
            language: q['language']?.toString() ?? 'English',
          );
        }
        _testGroups[key]!.questions.add(q);
      }
    }
  }

  void _launchTest(_CloudTestGroup group) {
    if (group.testType == 'MCQ') {
      // Re-format questions to match what MCQTestPage expects
      List<Map<String, dynamic>> formattedQuestions = group.questions.map((q) {
        return {
          "question": q['question'],
          "options": q['options'],
          "correct_answer": q['correct_answer'],
        };
      }).toList();

      final aiResponseJson = json.encode({
        "questions": formattedQuestions
      });
      
      // Default time: 1 minute per question
      int testTime = formattedQuestions.length;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MCQTestPage(
            numberOfQuestions: formattedQuestions.length,
            testTimeInMinutes: testTime,
            aiResponse: aiResponseJson,
            language: group.language,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Taking this type of exam is not supported yet.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: CustomAppBar(
        title: 'Cloud Tests',
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchCloudTests,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_testGroups.isEmpty) {
      return const Center(
        child: Text('No cloud tests available.'),
      );
    }

    final groups = _testGroups.values.toList();
    // Sort so newest is first. This assumes timestamps are ISO or sortable strings.
    groups.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 2,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _launchTest(group),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: group.testType == 'MCQ' ? Colors.blue.shade100 : Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          group.testType,
                          style: TextStyle(
                            color: group.testType == 'MCQ' ? Colors.blue.shade800 : Colors.orange.shade800,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Text(
                        '${group.questions.length} Questions',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${group.className} - ${group.subject}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Topic: ${group.topic}',
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        'Language: ${group.language}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CloudTestGroup {
  final String timestamp;
  final String testType;
  final String className;
  final String subject;
  final String topic;
  final String language;
  final List<dynamic> questions = [];

  _CloudTestGroup({
    required this.timestamp,
    required this.testType,
    required this.className,
    required this.subject,
    required this.topic,
    required this.language,
  });
}
