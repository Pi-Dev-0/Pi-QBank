import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:async';
import 'package:logger/logger.dart';

class ShortQuestionPage extends StatefulWidget {
  final int numberOfQuestions;
  final int testTimeInMinutes;
  final XFile? selectedImage;
  final String aiResponse;
  final String language;

  const ShortQuestionPage({
    super.key,
    required this.numberOfQuestions,
    required this.testTimeInMinutes,
    this.selectedImage,
    required this.aiResponse,
    required this.language,
  });

  @override
  State<ShortQuestionPage> createState() => _ShortQuestionPageState();
}

class _ShortQuestionPageState extends State<ShortQuestionPage> {
  final logger = Logger();
  List<Map<String, dynamic>> questions = [];
  Map<int, TextEditingController> answerControllers = {};
  int remainingTimeInSeconds = 0;
  bool _timeIsLow = false;
  late Timer _timer;
  bool _isSubmitted = false;

  @override
  void initState() {
    super.initState();
    parseQuestions();
    remainingTimeInSeconds = widget.testTimeInMinutes * 60;
    _startTimer();
  }

  void parseQuestions() {
    logger.i('Parsing AI response: ${widget.aiResponse}');
    try {
      List<String> lines = widget.aiResponse.split('\n');
      String currentQuestion = '';
      String currentAnswer = '';
      bool insideQuestion = false;

      for (String line in lines) {
        line = line.trim();
        if (line.isEmpty) continue;

        // Match Bengali numbers (১, ২, ৩) or English numbers followed by dot
        if (RegExp(r'^[\u09E6-\u09EF]\.|\d+\.').hasMatch(line)) {
          if (currentQuestion.isNotEmpty) {
            questions.add({
              'question': currentQuestion.trim(),
              'answer': currentAnswer.trim(),
            });
            if (questions.length >= widget.numberOfQuestions) break;
          }
          currentQuestion = line;
          currentAnswer = '';
          insideQuestion = true;
        } else if (line.toLowerCase().contains('উত্তর:') ||
            line.toLowerCase().contains('answer:') ||
            line.startsWith('উঃ')) {
          insideQuestion = false;
          currentAnswer = line
              .replaceFirst(
                  RegExp(r'^(উত্তর:|answer:|উঃ)', caseSensitive: false), '')
              .trim();
        } else if (insideQuestion) {
          currentQuestion = '$currentQuestion $line';
        }
      }

      // Add the last question if exists and we haven't reached the limit
      if (currentQuestion.isNotEmpty &&
          questions.length < widget.numberOfQuestions) {
        questions.add({
          'question': currentQuestion.trim(),
          'answer': currentAnswer.trim(),
        });
      }

      // Initialize controllers for all questions
      for (int i = 0; i < questions.length; i++) {
        answerControllers[i] = TextEditingController();
      }

      logger.i('Parsed ${questions.length} questions: $questions');
    } catch (e) {
      logger.e('Error parsing questions: $e');
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (remainingTimeInSeconds > 0) {
          remainingTimeInSeconds--;
          _timeIsLow = remainingTimeInSeconds < 60;
        } else {
          _timer.cancel();
          if (!_isSubmitted) {
            _submitTest();
          }
        }
      });
    });
  }

  void _submitTest() {
    if (_isSubmitted) return;

    _isSubmitted = true;
    _timer.cancel();

    // Show results view after submission
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                    formatTime(remainingTimeInSeconds),
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
      ),
      body: _isSubmitted ? _buildResultsView() : _buildTestView(),
    );
  }

  Widget _buildTestView() {
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
                  '${questions.length}',
                  Icons.quiz_outlined,
                ),
                _buildInfoCard(
                  'Answered',
                  '${answerControllers.values.where((c) => c.text.isNotEmpty).length}',
                  Icons.check_circle_outline,
                ),
                _buildInfoCard(
                  'Remaining',
                  '${answerControllers.values.where((c) => c.text.isEmpty).length}',
                  Icons.pending_outlined,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ...questions.asMap().entries.map((entry) {
            final index = entry.key;
            final question = entry.value;
            final isAnswered =
                answerControllers[index]?.text.isNotEmpty ?? false;

            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                  side: BorderSide(
                    color: isAnswered
                        ? Theme.of(context).primaryColor.withOpacity(0.3)
                        : Colors.grey.withOpacity(0.2),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor.withOpacity(0.05),
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
                              widget.language == 'বাংলা'
                                  ? _convertToBengaliNumber(index + 1)
                                  : '${index + 1}',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              question['question'] ?? '',
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
                        controller: answerControllers[index],
                        decoration: InputDecoration(
                          hintText: widget.language == 'বাংলা'
                              ? 'আপনার উত্তর এখানে লিখুন'
                              : 'Enter your answer here',
                          border: const OutlineInputBorder(),
                        ),
                        maxLines: 3,
                        enabled: !_isSubmitted,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          if (!_isSubmitted) ...[
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: questions.isEmpty ? null : _submitTest,
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
                children: [
                  const Icon(Icons.check_circle_outline, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    widget.language == 'বাংলা'
                        ? 'পরীক্ষা জমা দিন'
                        : 'Submit Test',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  // Add this new method to check answer correctness
  bool _isAnswerCorrect(String userAnswer, String correctAnswer) {
    if (userAnswer.isEmpty) return false;
    // Remove punctuation and normalize whitespace
    String normalizeAnswer(String answer) {
      return answer
          .replaceAll(RegExp(r'[।,.]'), '') // Remove punctuation
          .trim()
          .toLowerCase();
    }

    return normalizeAnswer(userAnswer) == normalizeAnswer(correctAnswer);
  }

  Widget _buildResultsView() {
    final correctAnswers = questions
        .where((q) => _isAnswerCorrect(
            answerControllers[questions.indexOf(q)]?.text ?? '',
            q['answer'] ?? ''))
        .length;
    final answeredQuestions = questions
        .where((q) =>
            (answerControllers[questions.indexOf(q)]?.text ?? '').isNotEmpty)
        .length;
    final percentage =
        (correctAnswers / questions.length * 100).toStringAsFixed(1);

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
                  Text(
                    widget.language == 'বাংলা'
                        ? 'পরীক্ষার ফলাফল'
                        : 'Test Results',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 20),
                  CircleAvatar(
                    radius: 60,
                    backgroundColor: Theme.of(context).primaryColor,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$correctAnswers/${questions.length}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          '$percentage%',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildStatisticRow(
                    widget.language == 'বাংলা'
                        ? 'মোট প্রশ্ন'
                        : 'Total Questions',
                    '${questions.length}',
                    Icons.quiz,
                  ),
                  _buildStatisticRow(
                    widget.language == 'বাংলা' ? 'সঠিক উত্তর' : 'Correct',
                    '$correctAnswers',
                    Icons.check_circle,
                    color: Colors.green,
                  ),
                  _buildStatisticRow(
                    widget.language == 'বাংলা' ? 'ভুল উত্তর' : 'Incorrect',
                    '${answeredQuestions - correctAnswers}',
                    Icons.cancel,
                    color: Colors.red,
                  ),
                  _buildStatisticRow(
                    widget.language == 'বাংলা'
                        ? 'উত্তর দেওয়া হয়নি'
                        : 'Not Answered',
                    '${questions.length - answeredQuestions}',
                    Icons.help,
                    color: Colors.orange,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            widget.language == 'বাংলা'
                ? 'বিস্তারিত বিশ্লেষণ'
                : 'Detailed Analysis',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          ...questions.asMap().entries.map((entry) {
            final index = entry.key;
            final question = entry.value;
            final answer = answerControllers[index]?.text ?? '';
            final hasAnswer = answer.isNotEmpty;

            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: hasAnswer
                      ? _isAnswerCorrect(answer, question['answer'] ?? '')
                          ? Colors.green.shade200
                          : Colors.red.shade200
                      : Colors.orange.shade200,
                  width: 1,
                ),
              ),
              child: ExpansionTile(
                leading: CircleAvatar(
                  backgroundColor: hasAnswer
                      ? _isAnswerCorrect(answer, question['answer'] ?? '')
                          ? Colors.green
                          : Colors.red
                      : Colors.orange,
                  child: Icon(
                    hasAnswer
                        ? _isAnswerCorrect(answer, question['answer'] ?? '')
                            ? Icons.check
                            : Icons.close
                        : Icons.help,
                    color: Colors.white,
                  ),
                ),
                title: Text(
                  widget.language == 'বাংলা'
                      ? 'প্রশ্ন ${_convertToBengaliNumber(index + 1)}'
                      : 'Question ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  question['question'] ?? '',
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
                          question['question'] ?? '',
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          widget.language == 'বাংলা'
                              ? 'সঠিক উত্তর:'
                              : 'Correct Answer:',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          question['answer'] ?? '',
                          style: const TextStyle(
                            color: Colors.green,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          widget.language == 'বাংলা'
                              ? 'আপনার উত্তর:'
                              : 'Your Answer:',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          answer.isEmpty
                              ? (widget.language == 'বাংলা'
                                  ? 'উত্তর দেওয়া হয়নি'
                                  : 'Not Answered')
                              : answer,
                          style: TextStyle(
                            color: _isAnswerCorrect(
                                    answer, question['answer'] ?? '')
                                ? Colors.green
                                : Colors.orange,
                            fontSize: 16,
                          ),
                        ),
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
            label: Text(
              widget.language == 'বাংলা' ? 'পরীক্ষা শেষ করুন' : 'Finish Test',
            ),
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

  String formatTime(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _timer.cancel();
    for (var controller in answerControllers.values) {
      controller.dispose();
    }
    super.dispose();
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

  String _convertToBengaliNumber(int number) {
    const english = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    const bengali = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];
    String strNum = number.toString();
    for (int i = 0; i < english.length; i++) {
      strNum = strNum.replaceAll(english[i], bengali[i]);
    }
    return strNum;
  }
}
