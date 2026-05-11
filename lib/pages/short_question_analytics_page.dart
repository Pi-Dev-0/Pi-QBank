import 'package:flutter/material.dart';
import 'package:pi_qbank/models/test_result.dart';
import 'dart:math';
import 'package:pi_qbank/widgets/custom_app_bar.dart'; // Import CustomAppBar
import 'package:pi_qbank/services/test_result_service.dart'; // Import TestResultService

class ShortQuestionAnalyticsPage extends StatefulWidget {
  final List<TestResult> testResults;

  const ShortQuestionAnalyticsPage({super.key, required this.testResults});

  @override
  State<ShortQuestionAnalyticsPage> createState() =>
      _ShortQuestionAnalyticsPageState();
}

class _ShortQuestionAnalyticsPageState
    extends State<ShortQuestionAnalyticsPage> {
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
    final double averageScore =
        _currentTestResults.map((e) => e.score / e.totalQuestions).average;
    final int totalQuestionsAttempted =
        _currentTestResults.map((e) => e.totalQuestions).sum.toInt();
    final int totalCorrectAnswers =
        _currentTestResults.map((e) => e.score).sum.toInt();
    final double overallPercentage = (totalQuestionsAttempted > 0)
        ? (totalCorrectAnswers / totalQuestionsAttempted) * 100
        : 0.0;

    final int highestScore =
        _currentTestResults.map((e) => e.score).reduce(max).toInt();
    final int lowestScore =
        _currentTestResults.map((e) => e.score).reduce(min).toInt();

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
          colors: [
            const Color(0xFF6A11CB), // Deep Purple
            const Color(0xFF2575FC), // Blue
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2575FC).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, size: 40, color: Colors.white),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
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
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 28, color: color),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTestResultCard(BuildContext context, TestResult testResult,
      int index, double scorePercentage) {
    final testGradient = _getTestTypeGradient(testResult.testType);

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _showTestDetailsDialog(context, testResult),
            child: Column(
              children: [
                // Header with gradient
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
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
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          _getTestTypeIcon(testResult.testType),
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${testResult.testType} Test ${index + 1}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${scorePercentage.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: testGradient.first,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Body
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildDetailItem(
                            Icons.check_circle_outline,
                            'Score',
                            '${testResult.score}/${testResult.totalQuestions}',
                            Colors.green,
                          ),
                          _buildDetailItem(
                            Icons.timer_outlined,
                            'Time',
                            '${testResult.timeTakenInSeconds ~/ 60}m ${testResult.timeTakenInSeconds % 60}s',
                            Colors.orange,
                          ),
                          _buildDetailItem(
                            Icons.calendar_today_outlined,
                            'Date',
                            testResult.timestamp.toString().split(' ')[0],
                            Colors.purple,
                          ),
                        ],
                      ),
                      const SizedBox(height: 15),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: scorePercentage / 100,
                                backgroundColor: Colors.grey.shade100,
                                color: _getScoreColor(scorePercentage),
                                minHeight: 6,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 16,
                            color: Colors.grey.shade400,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailItem(
      IconData icon, String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade800,
          ),
        ),
      ],
    );
  }

  List<Color> _getTestTypeGradient(String testType) {
    switch (testType) {
      case 'MCQ Test':
        return [const Color(0xFF0077B6), const Color(0xFF00B4D8)];
      case 'Short Question':
        return [const Color(0xFF6A057F), const Color(0xFF9B2226)];
      case 'Quiz Test':
        return [const Color(0xFF009688), const Color(0xFF4DB6AC)]; // Teal gradient for Quiz
      case 'Fill In the Blanks':
        return [const Color(0xFFF77F00), const Color(0xFFFCBF49)];
      default:
        return [Colors.grey.shade600, Colors.grey.shade500];
    }
  }

  void _showTestDetailsDialog(BuildContext context, TestResult testResult) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        // Calculate dialog stats
        int correct = 0;
        int wrong = 0;
        int skipped = 0;
        for (var qa in testResult.questionsAndAnswers) {
          if (qa['isCorrect'] == true) {
            correct++;
          } else if (qa['userAnswer'] == null ||
              qa['userAnswer'].toString().trim().isEmpty) {
            skipped++;
          } else {
            wrong++;
          }
        }

        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600, maxHeight: 800),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
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
                // 1. Gradient Header
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 30),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF6A11CB), // Deep Purple
                        const Color(0xFF2575FC), // Blue
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  _getTestTypeIcon(testResult.testType),
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '${testResult.testType} Details',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded,
                                color: Colors.white),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white.withOpacity(0.2),
                              hoverColor: Colors.white.withOpacity(0.3),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // 2. Summary Statistics Card (Inside Header)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 15, horizontal: 20),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: Colors.white.withOpacity(0.2), width: 1),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildHeaderStat(
                                'Total',
                                '${testResult.totalQuestions}',
                                Icons.format_list_numbered_rounded,
                                Colors.white),
                            _buildVerticalDivider(),
                            _buildHeaderStat('Correct', '$correct',
                                Icons.check_circle_rounded, Colors.greenAccent),
                            _buildVerticalDivider(),
                            _buildHeaderStat('Wrong', '$wrong',
                                Icons.cancel_rounded, Colors.redAccent),
                            _buildVerticalDivider(),
                            _buildHeaderStat(
                                'Skipped',
                                '$skipped',
                                Icons.help_outline_rounded,
                                Colors.orangeAccent),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // 3. Question List
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(24),
                      bottomRight: Radius.circular(24),
                    ),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: testResult.questionsAndAnswers.length,
                      itemBuilder: (context, index) {
                        final qa = testResult.questionsAndAnswers[index];
                        final isCorrect = qa['isCorrect'] as bool;
                        final userAnswer = qa['userAnswer'];
                        final isSkipped = userAnswer == null ||
                            userAnswer.toString().trim().isEmpty;

                        MaterialColor statusColor;
                        IconData statusIcon;
                        if (isCorrect) {
                          statusColor = Colors.green;
                          statusIcon = Icons.check_circle;
                        } else if (isSkipped) {
                          statusColor = Colors.orange;
                          statusIcon = Icons.help;
                        } else {
                          statusColor = Colors.red;
                          statusIcon = Icons.cancel;
                        }

                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                            border: Border.all(
                                color: statusColor.withOpacity(0.3), width: 1),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Question Header
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.05),
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(16),
                                    topRight: Radius.circular(16),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: statusColor.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'Q${index + 1}',
                                        style: TextStyle(
                                          color: statusColor.shade700,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    Icon(statusIcon,
                                        color: statusColor, size: 20),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      qa['question'],
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black87,
                                        height: 1.4,
                                      ),
                                    ),
                                    if (testResult.testType == 'MCQ Test' &&
                                        qa['options'] != null) ...[
                                      const SizedBox(height: 16),
                                      ..._buildMcqOptions(
                                          qa['options'] as Map<String, dynamic>,
                                          qa['correctAnswer'],
                                          qa['userAnswer']),
                                    ],
                                    const SizedBox(height: 16),
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade50,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                            color: Colors.grey.shade200),
                                      ),
                                      child: Column(
                                        children: [
                                          _buildAnswerRow(
                                              'Your Answer',
                                              userAnswer ?? 'Skipped',
                                              isSkipped
                                                  ? Colors.orange.shade700
                                                  : (isCorrect
                                                      ? Colors.green.shade700
                                                      : Colors.red.shade700)),
                                          const Padding(
                                            padding: EdgeInsets.symmetric(
                                                vertical: 8),
                                            child: Divider(height: 1),
                                          ),
                                          _buildAnswerRow(
                                              'Correct Answer',
                                              qa['correctAnswer'],
                                              Colors.green.shade700),
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
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeaderStat(
      String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withOpacity(0.8),
          ),
        ),
      ],
    );
  }

  Widget _buildVerticalDivider() {
    return Container(
      height: 30,
      width: 1,
      color: Colors.white.withOpacity(0.2),
    );
  }

  Widget _buildAnswerRow(String label, String text, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  IconData _getTestTypeIcon(String testType) {
    switch (testType) {
      case 'MCQ Test':
        return Icons.quiz;
      case 'Short Question':
        return Icons.short_text;
      case 'Quiz Test':
        return Icons.bolt; // Fast icon for Quiz
      case 'Fill In the Blanks':
        return Icons.edit_note;
      default:
        return Icons.assignment;
    }
  }

  List<Widget> _buildMcqOptions(
      Map<String, dynamic> options, String correctAnswer, String? userAnswer) {
    List<Widget> optionWidgets = [];
    options.forEach((key, value) {
      final isCorrect = key == correctAnswer;
      final isUserAnswer = key == userAnswer;

      optionWidgets.add(
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isCorrect
                ? Colors.green.shade50
                : isUserAnswer
                    ? Colors.red.shade50
                    : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isCorrect
                  ? Colors.green.shade300
                  : isUserAnswer
                      ? Colors.red.shade300
                      : Colors.grey.shade200,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              if (isCorrect)
                Icon(Icons.check_circle, color: Colors.green.shade600, size: 18)
              else if (isUserAnswer)
                Icon(Icons.cancel, color: Colors.red.shade600, size: 18)
              else
                Icon(Icons.radio_button_unchecked,
                    color: Colors.grey.shade400, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$key. $value',
                  style: TextStyle(
                    color: isCorrect
                        ? Colors.green.shade800
                        : isUserAnswer
                            ? Colors.red.shade800
                            : Colors.grey.shade800,
                    fontWeight: isCorrect || isUserAnswer
                        ? FontWeight.w600
                        : FontWeight.normal,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
    return optionWidgets;
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
