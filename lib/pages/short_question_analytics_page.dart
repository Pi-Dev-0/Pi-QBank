import 'package:flutter/material.dart';
import 'package:pi_qbank/models/test_result.dart';
import 'dart:math';
import 'package:pi_qbank/widgets/custom_app_bar.dart'; // Import CustomAppBar
import 'package:pi_qbank/services/test_result_service.dart'; // Import TestResultService

class ShortQuestionAnalyticsPage extends StatefulWidget {
  final List<TestResult> testResults;

  const ShortQuestionAnalyticsPage({super.key, required this.testResults});

  @override
  State<ShortQuestionAnalyticsPage> createState() => _ShortQuestionAnalyticsPageState();
}

class _ShortQuestionAnalyticsPageState extends State<ShortQuestionAnalyticsPage> {
  List<TestResult> _currentTestResults = [];

  @override
  void initState() {
    super.initState();
    _currentTestResults = widget.testResults;
  }

  Future<void> _clearAnalytics() async {
    await TestResultService.clearAllTestResults();
    setState(() {
      _currentTestResults = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_currentTestResults.isEmpty) {
      return Scaffold(
        appBar: CustomAppBar(
          title: 'Test Analytics',
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.delete_forever, color: Colors.white),
              onPressed: _clearAnalytics,
              tooltip: 'Clear All Analytics',
            ),
          ],
        ),
        body: const Center(
          child: Text(
            'No test results found.',
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
        ),
      );
    }

    // Calculate summary statistics
    final int totalTests = _currentTestResults.length;
    final double averageScore = _currentTestResults.map((e) => e.score / e.totalQuestions).average;
    final int totalQuestionsAttempted = _currentTestResults.map((e) => e.totalQuestions).sum.toInt();
    final int totalCorrectAnswers = _currentTestResults.map((e) => e.score).sum.toInt();
    final double overallPercentage = (totalQuestionsAttempted > 0)
        ? (totalCorrectAnswers / totalQuestionsAttempted) * 100
        : 0.0;

    final int highestScore = _currentTestResults.map((e) => e.score).reduce(max).toInt();
    final int lowestScore = _currentTestResults.map((e) => e.score).reduce(min).toInt();

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Test Analytics',
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_forever, color: Colors.white),
            onPressed: _clearAnalytics,
            tooltip: 'Clear All Analytics',
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF8FAFC),
              Colors.white,
            ],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSummaryCard(
                title: 'Overall Performance',
                value: '${overallPercentage.toStringAsFixed(1)}%',
                icon: Icons.bar_chart_rounded,
                color: Colors.blueAccent,
              ),
              const SizedBox(height: 20),
              _buildStatisticGrid(
                totalTests: totalTests,
                averageScore: averageScore,
                highestScore: highestScore,
                lowestScore: lowestScore,
                totalQuestionsAttempted: totalQuestionsAttempted,
                totalCorrectAnswers: totalCorrectAnswers,
              ),
              const SizedBox(height: 30),
              Text(
                'Individual Test Results',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 20),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _currentTestResults.length,
                itemBuilder: (context, index) {
                  final testResult = _currentTestResults[index];
                  final double scorePercentage =
                      (testResult.score / testResult.totalQuestions) * 100;
                  return _buildTestResultCard(
                      context, testResult, index, scorePercentage);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.8), color],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 50, color: Colors.white),
          const SizedBox(height: 15),
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 38,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticGrid({
    required int totalTests,
    required double averageScore,
    required int highestScore,
    required int lowestScore,
    required int totalQuestionsAttempted,
    required int totalCorrectAnswers,
  }) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 15,
      mainAxisSpacing: 15,
      children: [
        _buildGridItem(
          'Total Tests',
          totalTests.toString(),
          Icons.assignment_turned_in_outlined,
          Colors.deepPurple,
        ),
        _buildGridItem(
          'Avg. Score',
          '${(averageScore * 100).toStringAsFixed(1)}%',
          Icons.trending_up_rounded,
          Colors.teal,
        ),
        _buildGridItem(
          'Highest Score',
          highestScore.toString(),
          Icons.emoji_events_outlined,
          Colors.amber.shade700,
        ),
        _buildGridItem(
          'Lowest Score',
          lowestScore.toString(),
          Icons.trending_down_rounded,
          Colors.redAccent,
        ),
        _buildGridItem(
          'Total Questions',
          totalQuestionsAttempted.toString(),
          Icons.quiz_outlined,
          Colors.indigo,
        ),
        _buildGridItem(
          'Total Correct',
          totalCorrectAnswers.toString(),
          Icons.check_circle_outline,
          Colors.green,
        ),
      ],
    );
  }

  Widget _buildGridItem(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: color.withOpacity(0.2), width: 1.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 35, color: color),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTestResultCard(
      BuildContext context, TestResult testResult, int index, double scorePercentage) {
    return Card(
      margin: const EdgeInsets.only(bottom: 15),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: InkWell(
        onTap: () => _showTestDetailsDialog(context, testResult),
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.all(18.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${testResult.testType} Test ${index + 1}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  Text(
                    '${scorePercentage.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _getScoreColor(scorePercentage),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: scorePercentage / 100,
                backgroundColor: Colors.grey.shade300,
                color: _getScoreColor(scorePercentage),
                minHeight: 8,
                borderRadius: BorderRadius.circular(5),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildDetailChip(
                    Icons.check_circle_outline,
                    'Score: ${testResult.score}/${testResult.totalQuestions}',
                    Colors.green.shade700,
                  ),
                  _buildDetailChip(
                    Icons.timer_outlined,
                    'Time: ${testResult.timeTakenInSeconds ~/ 60}m ${testResult.timeTakenInSeconds % 60}s',
                    Colors.orange.shade700,
                  ),
                ],
              ),
              const SizedBox(height: 5),
              _buildDetailChip(
                Icons.calendar_today_outlined,
                'Date: ${testResult.timestamp.toLocal().toString().split(' ')[0]}',
                Colors.purple.shade700,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTestDetailsDialog(BuildContext context, TestResult testResult) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('${testResult.testType} Details'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: testResult.questionsAndAnswers.length,
              itemBuilder: (context, qaIndex) {
                final qa = testResult.questionsAndAnswers[qaIndex];
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Q${qaIndex + 1}: ${qa['question']}',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        if (testResult.testType == 'MCQ Test' &&
                            qa['options'] != null) ...[
                          const Text('Options:',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: _buildMcqOptions(
                                qa['options'] as Map<String, dynamic>,
                                qa['correctAnswer']),
                          ),
                          const SizedBox(height: 4),
                        ],
                        Text('Your Answer: ${qa['userAnswer']}'),
                        const SizedBox(height: 4),
                        Text('Correct Answer: ${qa['correctAnswer']}'),
                        const SizedBox(height: 4),
                        Text('Result: ${qa['isCorrect'] ? 'Correct' : 'Incorrect'}',
                            style: TextStyle(
                                color: qa['isCorrect'] ? Colors.green : Colors.red)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Close'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  List<Widget> _buildMcqOptions(
      Map<String, dynamic> options, String correctAnswer) {
    List<Widget> optionWidgets = [];
    options.forEach((key, value) {
      optionWidgets.add(
        Text(
          '$key. $value',
          style: TextStyle(
            color: key == correctAnswer ? Colors.green : Colors.black,
            fontWeight: key == correctAnswer ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      );
    });
    optionWidgets.add(const SizedBox(height: 4));
    return optionWidgets;
  }

  Widget _buildDetailChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }


  Color _getScoreColor(double percentage) {
    if (percentage >= 80) return Colors.green.shade600;
    if (percentage >= 60) return Colors.blue.shade600;
    if (percentage >= 40) return Colors.orange.shade600;
    return Colors.red.shade600;
  }
}

extension IterableNumExtension on Iterable<num> {
  double get average {
    if (isEmpty) return 0.0;
    return toList().cast<double>().reduce((a, b) => a + b) / length;
  }

  num get sum {
    if (isEmpty) return 0;
    return toList().cast<int>().reduce((a, b) => a + b);
  }
}