import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:async';

class MCQTestPage extends StatefulWidget {
  final int numberOfQuestions;
  final int testTimeInMinutes;
  final XFile? selectedImage;
  final String aiResponse;
  final String language;

  const MCQTestPage({
    super.key,
    required this.numberOfQuestions,
    required this.testTimeInMinutes,
    this.selectedImage,
    required this.aiResponse,
    required this.language,
  });

  @override
  State<MCQTestPage> createState() => _MCQTestPageState();
}

class _MCQTestPageState extends State<MCQTestPage> {
  late List<dynamic> _mcqQuestions = [];
  final Map<int, String?> _userAnswers =
      {}; // Stores selected option for each question
  bool _testSubmitted = false; // New state to track if test is submitted
  final List<Map<String, dynamic>> _mcqResults =
      []; // Stores results after submission
  late Timer _timer;
  late int _remainingSeconds;
  bool _timeIsLow = false;

  @override
  void initState() {
    super.initState();
    _parseMcqQuestions();
    _initializeTimer();
  }

  void _initializeTimer() {
    _remainingSeconds = widget.testTimeInMinutes * 60;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
          _timeIsLow = _remainingSeconds < 60; // Last minute warning
        } else {
          _submitTest(); // Auto submit when time is up
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

  void _parseMcqQuestions() {
    try {
      String cleanedResponse = widget.aiResponse
          .replaceAll('```json\n', '')
          .replaceAll('```', '')
          .trim();
      final Map<String, dynamic> decodedResponse = json.decode(cleanedResponse);
      _mcqQuestions = decodedResponse['questions'] ?? [];
      // Initialize _userAnswers with null for all questions
      for (int i = 0; i < _mcqQuestions.length; i++) {
        _userAnswers[i] = null;
      }
    } catch (e) {
      // Silently handle the error
    }
  }

  void _submitTest() {
    _mcqResults.clear(); // Clear previous results if any
    for (int i = 0; i < _mcqQuestions.length; i++) {
      final question = _mcqQuestions[i];
      final selectedOption = _userAnswers[i];
      final correctAnswer = question['correct_answer'];
      final isCorrect = selectedOption == correctAnswer;

      _mcqResults.add({
        'question': question['question'],
        'selected_option': selectedOption,
        'correct_answer': correctAnswer,
        'is_correct': isCorrect,
        'options': question['options'],
      });
    }

    setState(() {
      _testSubmitted = true;
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
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
    if (_mcqQuestions.isEmpty) {
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
                  '${_mcqQuestions.length}',
                  Icons.quiz_outlined,
                ),
                _buildInfoCard(
                  'Answered',
                  '${_userAnswers.values.where((v) => v != null).length}',
                  Icons.check_circle_outline,
                ),
                _buildInfoCard(
                  'Remaining',
                  '${_userAnswers.values.where((v) => v == null).length}',
                  Icons.pending_outlined,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _mcqQuestions.length,
            itemBuilder: (context, index) {
              final question = _mcqQuestions[index];
              final isAnswered = _userAnswers[index] != null;
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
                                question['question'],
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
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          children: (question['options']
                                  as Map<String, dynamic>)
                              .entries
                              .map(
                                (option) => Container(
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  child: RadioListTile<String>(
                                    title: Text(option.value),
                                    value: option.key,
                                    groupValue: _userAnswers[index],
                                    onChanged: (value) {
                                      setState(() {
                                        _userAnswers[index] = value;
                                      });
                                    },
                                    activeColor: Theme.of(context).primaryColor,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      side: BorderSide(
                                        color: _userAnswers[index] == option.key
                                            ? Theme.of(context).primaryColor
                                            : Colors.grey.withOpacity(0.3),
                                      ),
                                    ),
                                    tileColor: _userAnswers[index] == option.key
                                        ? Theme.of(context)
                                            .primaryColor
                                            .withOpacity(0.1)
                                        : null,
                                  ),
                                ),
                              )
                              .toList(),
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
    final score = _mcqResults.where((result) => result['is_correct']).length;
    final total = _mcqResults.length;
    final percentage = (score / total * 100).toStringAsFixed(1);
    final notAnswered =
        _mcqResults.where((result) => result['selected_option'] == null).length;
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
          ..._mcqResults.asMap().entries.map((entry) {
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
                  backgroundColor:
                      result['is_correct'] ? Colors.green : Colors.red,
                  child: Icon(
                    result['is_correct'] ? Icons.check : Icons.close,
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
                          result['selected_option'] ?? 'Not Answered',
                          result['options'][result['selected_option']] ?? 'N/A',
                          result['is_correct'] ? Colors.green : Colors.red,
                        ),
                        if (!result['is_correct']) ...[
                          const SizedBox(height: 8),
                          _buildAnswerRow(
                            'Correct Answer:',
                            result['correct_answer'],
                            result['options'][result['correct_answer']],
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

  Widget _buildAnswerRow(
      String label, String optionKey, String optionValue, Color color) {
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
            '$optionKey: $optionValue',
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
