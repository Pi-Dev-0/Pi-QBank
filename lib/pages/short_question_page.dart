import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:async';
import '../widgets/custom_app_bar.dart';

class ShortQuestionPage extends StatefulWidget {
  final int numberOfQuestions;
  final int testTimeInMinutes;
  final XFile? selectedImage;
  final String aiResponse;
  final String language;

  const ShortQuestionPage({
    Key? key,
    required this.numberOfQuestions,
    required this.testTimeInMinutes,
    this.selectedImage,
    required this.aiResponse,
    required this.language,
  }) : super(key: key);

  @override
  State<ShortQuestionPage> createState() => _ShortQuestionPageState();
}

class _ShortQuestionPageState extends State<ShortQuestionPage> {
  List<Map<String, String>> questions = [];
  Map<int, TextEditingController> answerControllers = {};
  int remainingTimeInSeconds = 0;
  bool _timeIsLow = false;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    parseQuestions();
    remainingTimeInSeconds = widget.testTimeInMinutes * 60;
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (remainingTimeInSeconds > 0) {
          remainingTimeInSeconds--;
          _timeIsLow = remainingTimeInSeconds < 60; // Last minute warning
        } else {
          _timer.cancel();
          // Handle time up - maybe auto submit
        }
      });
    });
  }

  void parseQuestions() {
    // Simple parsing of AI response - adjust based on your AI response format
    List<String> lines = widget.aiResponse.split('\n');
    for (int i = 0;
        i < lines.length && questions.length < widget.numberOfQuestions;
        i++) {
      if (lines[i].trim().isNotEmpty) {
        questions.add({'question': lines[i].trim(), 'answer': ''});
        answerControllers[questions.length - 1] = TextEditingController();
      }
    }
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
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: questions.length,
              itemBuilder: (context, index) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Question ${index + 1}:',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(questions[index]['question'] ?? ''),
                        const SizedBox(height: 16),
                        TextField(
                          controller: answerControllers[index],
                          decoration: const InputDecoration(
                            hintText: 'Enter your answer here',
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 3,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
