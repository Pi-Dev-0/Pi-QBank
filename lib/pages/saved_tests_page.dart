import 'package:flutter/material.dart';
import 'package:pi_qbank/models/saved_test.dart';
import 'package:pi_qbank/services/saved_test_service.dart';
import 'package:pi_qbank/widgets/custom_app_bar.dart';
import 'package:pi_qbank/pages/mcq_test_page.dart';
import 'package:pi_qbank/pages/short_question_page.dart';
import 'package:pi_qbank/pages/fill_in_the_blanks_test_page.dart';
import 'package:pi_qbank/widgets/delete_confirmation_dialog.dart';
import 'package:pi_qbank/widgets/view_and_edit_questions_dialog.dart';
import 'dart:convert';

class SavedTestsPage extends StatefulWidget {
  const SavedTestsPage({super.key});

  @override
  State<SavedTestsPage> createState() => _SavedTestsPageState();
}

class _SavedTestsPageState extends State<SavedTestsPage> {
  List<SavedTest> _savedTests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTests();
  }

  Future<void> _loadTests() async {
    setState(() {
      _isLoading = true;
    });
    _savedTests = await SavedTestService.loadSavedTests();
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _deleteTest(String id) async {
    final messenger = ScaffoldMessenger.of(context);
    await SavedTestService.deleteTest(id);
    await _loadTests();
    if (mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Test deleted successfully!'),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  void _startTest(SavedTest test) {
    if (!mounted) return;
    final Widget testPage;
    switch (test.testType) {
      case 'MCQ Test':
        testPage = MCQTestPage(
          numberOfQuestions: test.numberOfQuestions,
          testTimeInMinutes: test.testTimeInMinutes,
          selectedImages: test.selectedImages,
          aiResponse: test.aiResponse,
          language: test.language,
          savedTestId: test.id,
        );
        break;
      case 'Short Question':
        testPage = ShortQuestionPage(
          numberOfQuestions: test.numberOfQuestions,
          testTimeInMinutes: test.testTimeInMinutes,
          selectedImages: test.selectedImages,
          aiResponse: test.aiResponse,
          language: test.language,
          savedTestId: test.id,
        );
        break;
      case 'Fill In the Blanks':
        testPage = FillInTheBlanksTestPage(
          numberOfQuestions: test.numberOfQuestions,
          testTimeInMinutes: test.testTimeInMinutes,
          aiResponse: test.aiResponse,
          language: test.language,
          selectedImages: test.selectedImages,
          savedTestId: test.id,
        );
        break;
      default:
        testPage = FillInTheBlanksTestPage(
          numberOfQuestions: test.numberOfQuestions,
          testTimeInMinutes: test.testTimeInMinutes,
          aiResponse: test.aiResponse,
          language: test.language,
          selectedImages: test.selectedImages,
          savedTestId: test.id,
        );
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => testPage),
    ).then((_) => _loadTests());
  }

  List<Map<String, String>> _parseQuestions(SavedTest test) {
    List<Map<String, String>> parsedQuestions = [];

    try {
      // Try to parse as JSON for MCQ tests
      String cleanedResponse = test.aiResponse
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();
      final jsonResponse = json.decode(cleanedResponse);

      if (jsonResponse['questions'] != null) {
        final List<dynamic> questions = jsonResponse['questions'];
        for (var q in questions) {
          String questionText = q['question'] ?? 'No question text';
          Map<String, dynamic> options = q['options'] ?? {};
          String correctAnswer = q['correct_answer'] ?? 'N/A';

          String fullQuestion = questionText;
          options.forEach((key, value) {
            fullQuestion += '\n$key: $value';
          });

          parsedQuestions.add({
            'question': fullQuestion,
            'answer': correctAnswer,
          });
        }
      } else {
        throw Exception("Not a valid MCQ JSON format.");
      }
    } catch (e) {
      // Fall back to plain text parsing for Short Questions
      try {
        final questionBlocks =
            test.aiResponse.trim().split(RegExp(r'\n\s*\n+'));

        for (var block in questionBlocks) {
          if (block.trim().isEmpty) continue;

          String question = '';
          String answer = '';
          final lines = block.trim().split('\n');
          List<String> questionLines = [];
          bool answerFound = false;

          for (var line in lines) {
            line = line.trim();
            if (RegExp(r'^(answer:|উত্তর:|উঃ)', caseSensitive: false)
                .hasMatch(line)) {
              answer = line
                  .replaceFirst(
                      RegExp(r'^(answer:|উত্তর:|উঃ)', caseSensitive: false), '')
                  .trim();
              answerFound = true;
            } else if (!answerFound) {
              questionLines.add(line);
            } else {
              answer += '\n$line';
            }
          }

          question = questionLines.join(' ').trim();
          question = question
              .replaceFirst(RegExp(r'^\d+\.\s*|^[০-৯]+\.\s*'), '')
              .trim();

          if (question.isNotEmpty) {
            parsedQuestions.add({
              'question': _stripMarkdown(question),
              'answer': _stripMarkdown(answer),
            });
          }
        }
      } catch (e2) {
        // Return empty list if parsing fails
      }
    }

    return parsedQuestions;
  }

  String _stripMarkdown(String text) {
    return text
        .replaceAll(RegExp(r'\*\*'), '')
        .replaceAll(RegExp(r'__'), '')
        .replaceAll(RegExp(r'\*'), '')
        .replaceAll(RegExp(r'_'), '')
        .trim();
  }

  void _viewQuestions(SavedTest test) {
    final parsedQuestions = _parseQuestions(test);
    final testGradient = _getTestTypeGradient(test.testType);

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: testGradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.visibility_outlined,
                          color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        test.language == 'বাংলা'
                            ? 'প্রশ্ন দেখুন'
                            : 'View Questions',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              // Content
              Expanded(
                child: parsedQuestions.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.assignment_outlined,
                                size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            Text(
                              test.language == 'বাংলা'
                                  ? 'কোন প্রশ্ন পাওয়া যায়নি'
                                  : 'No questions found',
                              style: TextStyle(
                                  color: Colors.grey.shade500, fontSize: 16),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(24),
                        itemCount: parsedQuestions.length,
                        itemBuilder: (context, index) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: Colors.grey.shade200, width: 1),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.grey.withOpacity(0.05),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    borderRadius: const BorderRadius.only(
                                      topLeft: Radius.circular(20),
                                      topRight: Radius.circular(20),
                                    ),
                                    border: Border(
                                      bottom: BorderSide(
                                          color: Colors.grey.shade200),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: testGradient.first
                                              .withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          test.language == 'বাংলা'
                                              ? 'প্রশ্ন ${index + 1}'
                                              : 'Question ${index + 1}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: testGradient.first,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        parsedQuestions[index]['question'] ??
                                            '',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.grey.shade800,
                                          height: 1.5,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: Colors.green.shade50
                                              .withOpacity(0.5),
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          border: Border.all(
                                              color: Colors.green.shade100),
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Icon(Icons.check_circle_outline,
                                                color: Colors.green.shade600,
                                                size: 20),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    test.language == 'বাংলা'
                                                        ? 'সঠিক উত্তর'
                                                        : 'Correct Answer',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color:
                                                          Colors.green.shade700,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    parsedQuestions[index]
                                                            ['answer'] ??
                                                        '',
                                                    style: TextStyle(
                                                      fontSize: 15,
                                                      color:
                                                          Colors.green.shade900,
                                                      height: 1.4,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editQuestions(SavedTest test) async {
    List<Map<String, String>> parsedQuestions = _parseQuestions(test);
    final messenger = ScaffoldMessenger.of(context);

    await showDialog(
      context: context,
      builder: (context) => ViewAndEditQuestionsDialog(
        initialQuestions: parsedQuestions,
        selectedLanguage: test.language,
        selectedTestType: test.testType,
        selectedImages: test.selectedImages,
        onSave: (updatedQuestions) async {
          // Reconstruct aiResponse
          String newAiResponse;
          if (test.testType == 'MCQ Test') {
            List<Map<String, dynamic>> questionsList = [];
            for (var q in updatedQuestions) {
              final lines = q['question']!.split('\n');
              final questionText = lines[0];
              final options = <String, String>{};
              for (int i = 1; i < lines.length; i++) {
                final optionParts = lines[i].split(': ');
                if (optionParts.length == 2) {
                  options[optionParts[0]] = optionParts[1];
                }
              }
              questionsList.add({
                "question": questionText,
                "options": options,
                "correct_answer": q['answer'],
              });
            }
            final newJsonResponse = {"questions": questionsList};
            newAiResponse = '```json\n${json.encode(newJsonResponse)}\n```';
          } else {
            StringBuffer newResponse = StringBuffer();
            for (int i = 0; i < updatedQuestions.length; i++) {
              newResponse
                  .writeln('${i + 1}. ${updatedQuestions[i]['question']}');
              newResponse.writeln('Answer: ${updatedQuestions[i]['answer']}');
              newResponse.writeln();
            }
            newAiResponse = newResponse.toString();
          }

          // Update the saved test
          final updatedTest = SavedTest(
            id: test.id,
            testType: test.testType,
            numberOfQuestions: updatedQuestions.length,
            testTimeInMinutes: test.testTimeInMinutes,
            imagePaths: test.imagePaths,
            aiResponse: newAiResponse,
            language: test.language,
            savedDate: test.savedDate,
          );

          await SavedTestService.updateTest(updatedTest);
          await _loadTests();

          if (mounted) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(test.language == 'বাংলা'
                    ? 'পরিবর্তনগুলো সংরক্ষণ করা হয়েছে'
                    : 'Changes saved successfully'),
                backgroundColor: Colors.green.shade600,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            );
          }
        },
      ),
    );
  }

  IconData _getTestTypeIcon(String testType) {
    switch (testType) {
      case 'MCQ Test':
        return Icons.quiz;
      case 'Short Question':
        return Icons.short_text;
      case 'Fill In the Blanks':
        return Icons.edit_note;
      default:
        return Icons.assignment;
    }
  }

  List<Color> _getTestTypeGradient(String testType) {
    switch (testType) {
      case 'MCQ Test':
        return [const Color(0xFF2193b0), const Color(0xFF6dd5ed)];
      case 'Short Question':
        return [const Color(0xFFcc2b5e), const Color(0xFF753a88)];
      case 'Fill In the Blanks':
        return [const Color(0xFFff9966), const Color(0xFFff5e62)];
      default:
        return [Colors.grey.shade600, Colors.grey.shade500];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: CustomAppBar(
        title: 'Saved Tests',
        centerTitle: true,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.blue.shade50,
              Colors.purple.shade50,
              Colors.white,
            ],
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _savedTests.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(32),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.blue.shade100,
                                  Colors.purple.shade100,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.blue.withOpacity(0.2),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.save_alt_outlined,
                              size: 80,
                              color: Colors.blue.shade700,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'No saved tests yet!',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 40),
                            child: Text(
                              'Generate and save tests from the "Prepare Short Test" page.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                      itemCount: _savedTests.length,
                      itemBuilder: (context, index) {
                        final test = _savedTests[index];
                        final testGradient =
                            _getTestTypeGradient(test.testType);
                        final testIcon = _getTestTypeIcon(test.testType);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 20.0),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.1),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Column(
                              children: [
                                // Header with gradient
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: testGradient,
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.25),
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          border: Border.all(
                                            color:
                                                Colors.white.withOpacity(0.3),
                                            width: 1,
                                          ),
                                        ),
                                        child: Icon(testIcon,
                                            color: Colors.white, size: 28),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              test.testType,
                                              style: const TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.calendar_today_outlined,
                                                  size: 14,
                                                  color: Colors.white
                                                      .withOpacity(0.9),
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  'Saved: ${test.savedDate.toLocal().toString().split(' ')[0]}',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: Colors.white
                                                        .withOpacity(0.9),
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline,
                                            color: Colors.white),
                                        style: IconButton.styleFrom(
                                          backgroundColor:
                                              Colors.white.withOpacity(0.2),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                        ),
                                        onPressed: () async {
                                          final bool? confirmDelete =
                                              await showDeleteConfirmationDialog(
                                            context: context,
                                            title: 'Delete Saved Test',
                                            message:
                                                'Are you sure you want to delete this saved test?',
                                            paperTitle: test.testType,
                                            paperSubtitle:
                                                '${test.numberOfQuestions} Questions, ${test.testTimeInMinutes} Mins',
                                          );
                                          if (confirmDelete == true) {
                                            _deleteTest(test.id);
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                // Content
                                Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _buildInfoChip(
                                              Icons.quiz_outlined,
                                              '${test.numberOfQuestions} Questions',
                                              Colors.blue.shade700,
                                              Colors.blue.shade50,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: _buildInfoChip(
                                              Icons.timer_outlined,
                                              '${test.testTimeInMinutes} mins',
                                              Colors.orange.shade800,
                                              Colors.orange.shade50,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      _buildInfoChip(
                                        Icons.language_outlined,
                                        test.language,
                                        Colors.purple.shade700,
                                        Colors.purple.shade50,
                                      ),
                                      const SizedBox(height: 20),
                                      // Action buttons
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _buildActionButton(
                                              icon: Icons.visibility_outlined,
                                              label: 'View',
                                              color: Colors.blue.shade600,
                                              onPressed: () =>
                                                  _viewQuestions(test),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: _buildActionButton(
                                              icon: Icons.edit_outlined,
                                              label: 'Edit',
                                              color: Colors.orange.shade600,
                                              onPressed: () =>
                                                  _editQuestions(test),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: _buildActionButton(
                                              icon: Icons.play_arrow_rounded,
                                              label: 'Start',
                                              color: Colors.green.shade600,
                                              isPrimary: true,
                                              onPressed: () => _startTest(test),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(
      IconData icon, String label, Color iconColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: iconColor.withOpacity(0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: iconColor.withOpacity(0.8),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
    bool isPrimary = false,
  }) {
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary ? color : Colors.white,
          foregroundColor: isPrimary ? Colors.white : color,
          elevation: isPrimary ? 4 : 0,
          shadowColor: isPrimary ? color.withOpacity(0.4) : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: isPrimary
                ? BorderSide.none
                : BorderSide(color: color.withOpacity(0.3), width: 1.5),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
