import 'package:flutter/material.dart';
import 'package:pi_qbank/models/saved_test.dart';
import 'package:pi_qbank/services/saved_test_service.dart';
import 'package:pi_qbank/widgets/custom_app_bar.dart';
import 'package:pi_qbank/pages/mcq_test_page.dart';
import 'package:pi_qbank/pages/short_question_page.dart';
import 'package:pi_qbank/pages/fill_in_the_blanks_test_page.dart';
import 'package:pi_qbank/widgets/delete_confirmation_dialog.dart'; // Import the delete confirmation dialog

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
    await SavedTestService.deleteTest(id);
    _loadTests(); // Reload tests after deletion
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Test deleted successfully!'),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
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
          savedTestId: test.id, // Pass the saved test ID
        );
        break;
      case 'Short Question':
        testPage = ShortQuestionPage(
          numberOfQuestions: test.numberOfQuestions,
          testTimeInMinutes: test.testTimeInMinutes,
          selectedImages: test.selectedImages,
          aiResponse: test.aiResponse,
          language: test.language,
          savedTestId: test.id, // Pass the saved test ID
        );
        break;
      case 'Fill In the Blanks':
        testPage = FillInTheBlanksTestPage(
          numberOfQuestions: test.numberOfQuestions,
          testTimeInMinutes: test.testTimeInMinutes,
          aiResponse: test.aiResponse,
          language: test.language,
          selectedImages: test.selectedImages,
          savedTestId: test.id, // Pass the saved test ID
        );
        break;
      default:
        testPage = FillInTheBlanksTestPage(
          numberOfQuestions: test.numberOfQuestions,
          testTimeInMinutes: test.testTimeInMinutes,
          aiResponse: test.aiResponse,
          language: test.language,
          selectedImages: test.selectedImages,
          savedTestId: test.id, // Pass the saved test ID
        );
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => testPage),
    ).then((_) => _loadTests()); // Reload tests when returning from test page
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: CustomAppBar(
        title: 'Saved Tests',
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _savedTests.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.save_alt_outlined,
                        size: 80,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'No saved tests yet!',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Generate and save tests from the "Prepare Short Test" page.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16.0),
                  itemCount: _savedTests.length,
                  itemBuilder: (context, index) {
                    final test = _savedTests[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16.0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              test.testType,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Questions: ${test.numberOfQuestions}',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            Text(
                              'Time: ${test.testTimeInMinutes} minutes',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            Text(
                              'Language: ${test.language}',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            Text(
                              'Saved: ${test.savedDate.toLocal().toString().split(' ')[0]}',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () => _startTest(test),
                                  icon: const Icon(Icons.play_arrow),
                                  label: const Text('Start Test'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green.shade600,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                IconButton(
                                  icon: Icon(Icons.delete_outline,
                                      color: Colors.red.shade600),
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
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}