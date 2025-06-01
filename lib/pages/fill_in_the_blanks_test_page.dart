import 'package:flutter/material.dart';
import 'dart:async';

class FillInTheBlanksTestPage extends StatefulWidget {
  final int numberOfQuestions;
  final int testTimeInMinutes;
  final String aiResponse;
  final String language;

  const FillInTheBlanksTestPage({
    super.key,
    required this.numberOfQuestions,
    required this.testTimeInMinutes,
    required this.aiResponse,
    required this.language,
  });

  @override
  State<FillInTheBlanksTestPage> createState() =>
      _FillInTheBlanksTestPageState();
}

class _FillInTheBlanksTestPageState extends State<FillInTheBlanksTestPage> {
  final List<Map<String, String>> _fillInTheBlanksQuestions = [];
  final Map<int, TextEditingController> _answerControllers = {};
  bool _testSubmitted = false;
  final List<Map<String, dynamic>> _fillInTheBlanksResults = [];
  late Timer _timer;
  late int _remainingSeconds;
  bool _timeIsLow = false;

  @override
  void initState() {
    super.initState();
    _parseFillInTheBlanksQuestions();
    _initializeTimer();
  }

  @override
  void dispose() {
    _timer.cancel();
    _answerControllers.forEach((key, controller) => controller.dispose());
    super.dispose();
  }

  void _initializeTimer() {
    _remainingSeconds = widget.testTimeInMinutes * 60;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
          _timeIsLow = _remainingSeconds < 60;
        } else {
          _submitTest();
          _timer.cancel();
        }
      });
    });
  }

  String _formatTime(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  void _parseFillInTheBlanksQuestions() {
    _fillInTheBlanksQuestions.clear();

    final lines = widget.aiResponse.split('\n');
    String currentQuestion = '';
    String currentAnswer = '';
    bool isReadingQuestion = false;

    // Regex pattern to match Bengali numbers followed by dot
    final bengaliNumberPattern = RegExp(r'[১২৩৪৫৬৭৮৯০]+\.');

    for (var i = 0; i < lines.length; i++) {
      String line = lines[i].trim();
      if (line.isEmpty) continue;

      // Skip the introduction line
      if (line.contains('শূন্যস্থান পূরণ করার প্রশ্ন')) continue;

      // Check for question start using regex
      if (bengaliNumberPattern.hasMatch(line)) {
        // Save previous question if exists
        if (currentQuestion.isNotEmpty && currentAnswer.isNotEmpty) {
          _fillInTheBlanksQuestions.add({
            'question': currentQuestion,
            'answer': currentAnswer,
          });
          _answerControllers[_fillInTheBlanksQuestions.length - 1] =
              TextEditingController();
        }

        currentQuestion = line;
        currentAnswer = '';
        isReadingQuestion = true;
      }
      // Check for answer line
      else if (line.startsWith('উত্তর:')) {
        currentAnswer = line.replaceFirst('উত্তর:', '').trim();
        isReadingQuestion = false;
      }
      // Handle multi-line questions
      else if (isReadingQuestion) {
        currentQuestion = '$currentQuestion $line';
      }
    }

    // Add the last question-answer pair
    if (currentQuestion.isNotEmpty && currentAnswer.isNotEmpty) {
      _fillInTheBlanksQuestions.add({
        'question': currentQuestion,
        'answer': currentAnswer,
      });
      _answerControllers[_fillInTheBlanksQuestions.length - 1] =
          TextEditingController();
    }

    setState(() {}); // Trigger rebuild
  }

  void _submitTest() {
    _fillInTheBlanksResults.clear();
    for (int i = 0; i < _fillInTheBlanksQuestions.length; i++) {
      final questionData = _fillInTheBlanksQuestions[i];
      final userAnswer = _answerControllers[i]?.text.trim() ?? '';
      final correctAnswer = questionData['answer']?.trim() ?? '';
      final isCorrect = userAnswer.toLowerCase() == correctAnswer.toLowerCase();

      _fillInTheBlanksResults.add({
        'question': questionData['question'],
        'user_answer': userAnswer,
        'correct_answer': correctAnswer,
        'is_correct': isCorrect,
      });
    }

    setState(() {
      _testSubmitted = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: _testSubmitted
            ? Text(widget.language)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _timeIsLow
                          ? Colors.red.shade100.withOpacity(0.9)
                          : Colors.white.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _timeIsLow ? Colors.red.shade300 : Colors.white,
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _timeIsLow
                              ? Colors.red.withOpacity(0.3)
                              : Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 20,
                          color: _timeIsLow
                              ? Colors.red
                              : Theme.of(context).primaryColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatTime(_remainingSeconds),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: _timeIsLow
                                ? Colors.red
                                : Theme.of(context).primaryColor,
                            letterSpacing: 1.2,
                          ),
                        ),
                        if (_timeIsLow) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.red.withOpacity(0.5),
                                  blurRadius: 4,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _testSubmitted ? _buildResultsView() : _buildTestView(),
    );
  }

  Widget _buildTestView() {
    if (_fillInTheBlanksQuestions.isEmpty) {
      return const Center(child: Text('No questions available'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).primaryColor.withOpacity(0.1),
                  Theme.of(context).primaryColor.withOpacity(0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildInfoCard(
                  'Questions',
                  '${_fillInTheBlanksQuestions.length}',
                  Icons.quiz_outlined,
                ),
                _buildInfoCard(
                  'Answered',
                  '${_answerControllers.values.where((c) => c.text.isNotEmpty).length}',
                  Icons.check_circle_outline,
                ),
                _buildInfoCard(
                  'Remaining',
                  '${_fillInTheBlanksQuestions.length - _answerControllers.values.where((c) => c.text.isNotEmpty).length}',
                  Icons.pending_outlined,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _fillInTheBlanksQuestions.length,
            itemBuilder: (context, index) {
              final question = _fillInTheBlanksQuestions[index];
              final isAnswered =
                  _answerControllers[index]?.text.isNotEmpty ?? false;
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      spreadRadius: 1,
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                    side: BorderSide(
                      color: isAnswered
                          ? Theme.of(context).primaryColor.withOpacity(0.3)
                          : Colors.grey.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color:
                              Theme.of(context).primaryColor.withOpacity(0.05),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(15),
                            topRight: Radius.circular(15),
                          ),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: isAnswered
                                  ? Theme.of(context).primaryColor
                                  : Colors.grey,
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                question['question']!,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: TextField(
                          controller: _answerControllers[index],
                          decoration: InputDecoration(
                            labelText: 'Your Answer',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.0),
                            ),
                            prefixIcon: const Icon(Icons.edit),
                          ),
                          onChanged: (value) {
                            setState(() {
                              // Trigger rebuild to update answered count
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).primaryColor.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: _submitTest,
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Theme.of(context).primaryColor,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                minimumSize: const Size(double.infinity, 50),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.check_circle_outline, size: 24),
                  SizedBox(width: 8),
                  Text(
                    'Submit Test',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
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

  Widget _buildInfoCard(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: Theme.of(context).primaryColor),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).primaryColor,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsView() {
    final score =
        _fillInTheBlanksResults.where((result) => result['is_correct']).length;
    final total = _fillInTheBlanksResults.length;
    final percentage =
        total > 0 ? (score / total * 100).toStringAsFixed(1) : '0.0';
    final notAnswered = _fillInTheBlanksResults
        .where((result) => (result['user_answer'] as String).isEmpty)
        .length;
    final incorrect = total - score - notAnswered;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text(
                    'Test Results',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 20),
                  CircleAvatar(
                    radius: 60,
                    backgroundColor: _getScoreColor(double.parse(percentage)),
                    child: Text(
                      '$percentage%',
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildStatisticRow(
                      'Total Questions', total.toString(), Icons.quiz),
                  _buildStatisticRow(
                      'Correct Answers', score.toString(), Icons.check_circle,
                      color: Colors.green),
                  _buildStatisticRow(
                      'Incorrect Answers', incorrect.toString(), Icons.cancel,
                      color: Colors.red),
                  _buildStatisticRow(
                      'Not Answered', notAnswered.toString(), Icons.help,
                      color: Colors.orange),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Detailed Analysis',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          ..._fillInTheBlanksResults.asMap().entries.map((entry) {
            final index = entry.key;
            final result = entry.value;
            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: result['is_correct']
                      ? Colors.green.shade200
                      : Colors.red.shade200,
                  width: 1,
                ),
              ),
              child: ExpansionTile(
                leading: CircleAvatar(
                  backgroundColor: (result['user_answer'] as String).isEmpty
                      ? Colors.orange
                      : result['is_correct']
                          ? Colors.green
                          : Colors.red,
                  child: Icon(
                    (result['user_answer'] as String).isEmpty
                        ? Icons.help_outline
                        : result['is_correct']
                            ? Icons.check
                            : Icons.close,
                    color: Colors.white,
                  ),
                ),
                title: Text(
                  'Question ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  result['question'],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          result['question'],
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 12),
                        _buildAnswerRow(
                          'Your Answer:',
                          result['user_answer'],
                          (result['user_answer'] as String).isEmpty
                              ? Colors.orange
                              : result['is_correct']
                                  ? Colors.green
                                  : Colors.red,
                        ),
                        if (!result['is_correct'] ||
                            (result['user_answer'] as String).isEmpty) ...[
                          const SizedBox(height: 8),
                          _buildAnswerRow(
                            'Correct Answer:',
                            result['correct_answer'],
                            Colors.green,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.check_circle),
            label: const Text('Finish Test'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticRow(String label, String value, IconData icon,
      {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: color ?? Colors.black87),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color ?? Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnswerRow(String label, String answer, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            answer,
            style: TextStyle(color: color),
          ),
        ),
      ],
    );
  }

  Color _getScoreColor(double percentage) {
    if (percentage >= 80) return Colors.green;
    if (percentage >= 60) return Colors.blue;
    if (percentage >= 40) return Colors.orange;
    return Colors.red;
  }
}
