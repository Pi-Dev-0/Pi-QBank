import 'package:flutter/material.dart';
import 'dart:async';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/app_config.dart';
import 'package:pi_qbank/widgets/custom_app_bar.dart'; // Ensure this is imported
import 'package:logger/logger.dart';

class ShortTestPage extends StatefulWidget {
  final String selectedTestType;
  final int numberOfQuestions;
  final int testTimeInMinutes;
  final XFile? selectedImage;
  final String aiResponse;
  final String language; // Add this line

  const ShortTestPage({
    super.key,
    required this.selectedTestType,
    required this.numberOfQuestions,
    required this.testTimeInMinutes,
    this.selectedImage,
    required this.aiResponse,
    required this.language, // Add this line
  });

  @override
  State<ShortTestPage> createState() => _ShortTestPageState();
}

class _ShortTestPageState extends State<ShortTestPage> {
  final logger = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 5,
      lineLength: 50,
      colors: true,
      printEmojis: true,
      printTime: true,
    ),
  );

  late String _selectedTestType;
  late int _numberOfQuestions;
  late int _testTimeInMinutes;
  late XFile? _selectedImage;
  late String _aiResponse;

  bool _testStarted = false;
  int _remainingTimeInSeconds = 0;
  Timer? _timer;
  final TextEditingController _answerController = TextEditingController();
  String _currentQuestion = '';
  String _currentAnswer = '';
  bool _showAnswerInput = false;
  bool _isEvaluatingAnswer = false;

  List<dynamic> _mcqQuestions = [];
  int _currentQuestionIndex = 0;
  String? _selectedOption; // For MCQ tests
  bool _questionAnswered =
      false; // To track if the current question has been answered
  bool _testFinished = false; // To track if the entire test is finished
  List<Map<String, dynamic>> _mcqResults =
      []; // To store results of MCQ questions

  @override
  void initState() {
    logger.i('ShortTestPage - initState called');
    super.initState();
    _selectedTestType = widget.selectedTestType;
    _numberOfQuestions = widget.numberOfQuestions;
    _testTimeInMinutes = widget.testTimeInMinutes;
    _selectedImage = widget.selectedImage;
    _aiResponse = widget.aiResponse;

    _startTest();
    logger.i(
        'ShortTestPage - Test initialized with type: $_selectedTestType, questions: $_numberOfQuestions');
  }

  @override
  void dispose() {
    _timer?.cancel();
    _answerController.dispose();
    super.dispose();
  }

  void _startTest() {
    logger.i('ShortTestPage - _startTest called');
    setState(() {
      _testStarted = true;
      _remainingTimeInSeconds = _testTimeInMinutes * 60;

      if (_selectedTestType == 'MCQ Test' && _aiResponse.isNotEmpty) {
        try {
          logger.i('ShortTestPage - Parsing MCQ questions from AI response');
          // Clean the AI response by removing markdown code block delimiters
          String cleanedResponse = _aiResponse
              .replaceAll('```json\n', '')
              .replaceAll('```', '')
              .trim();
          final Map<String, dynamic> decodedResponse =
              json.decode(cleanedResponse);
          _mcqQuestions = decodedResponse['questions'] ?? [];
          if (_mcqQuestions.isNotEmpty) {
            _currentQuestionIndex = 0;
            _currentQuestion = _mcqQuestions[_currentQuestionIndex]['question'];
            _showAnswerInput = false; // MCQ uses options, not text input
          } else {
            _currentQuestion = 'Error: No MCQ questions generated.';
            _showAnswerInput = false;
          }
          logger.i(
              'ShortTestPage - MCQ questions parsed successfully: ${_mcqQuestions.length} questions');
        } catch (e) {
          logger.e('ShortTestPage - Error parsing MCQ questions: $e');
          _currentQuestion = 'Error parsing MCQ questions: ${e.toString()}';
          _showAnswerInput = false;
        }
      } else if (_selectedImage != null && _aiResponse.isNotEmpty) {
        _currentQuestion = _aiResponse;
        _showAnswerInput = true;
      } else {
        _currentQuestion =
            'Test in progress: Type - $_selectedTestType, Questions - $_numberOfQuestions';
        _showAnswerInput = false;
      }
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingTimeInSeconds > 0) {
        setState(() {
          _remainingTimeInSeconds--;
        });
      } else {
        timer.cancel();
        _autoSubmitTest();
      }
    });
  }

  Future<void> _submitAnswer() async {
    logger.i('ShortTestPage - _submitAnswer called');
    if (_selectedTestType == 'MCQ Test') {
      logger.i('ShortTestPage - Submitting MCQ answer: $_selectedOption');
      if (_selectedOption == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select an option.')),
        );
        return;
      }

      final currentMcq = _mcqQuestions[_currentQuestionIndex];
      final correctAnswer = currentMcq['correct_answer'];
      final isCorrect = _selectedOption == correctAnswer;

      setState(() {
        _questionAnswered = true;
        _mcqResults.add({
          'question': currentMcq['question'],
          'options': currentMcq['options'],
          'selected_option': _selectedOption,
          'correct_answer': correctAnswer,
          'is_correct': isCorrect,
        });
      });

      // If it's the last question, end the test
      if (_currentQuestionIndex == _mcqQuestions.length - 1) {
        _timer?.cancel();
        setState(() {
          _testFinished = true;
        });
      }
    } else {
      logger.i(
          'ShortTestPage - Submitting text answer: ${_answerController.text}');
      // Existing logic for Short Question, Broad Question, Fill In the Blanks
      if (_answerController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter your answer.')),
        );
        return;
      }

      setState(() {
        _isEvaluatingAnswer = true;
        _currentAnswer = _answerController.text;
      });

      try {
        logger.i('ShortTestPage - Sending answer for evaluation');
        final String apiKey = AppConfig.geminiApiKey;
        final url = Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$apiKey');

        List<Map<String, dynamic>> contents = [];

        if (_selectedImage != null) {
          final bytes = await _selectedImage!.readAsBytes();
          final base64Image = base64Encode(bytes);
          contents.add({
            "parts": [
              {
                "inline_data": {"mime_type": "image/jpeg", "data": base64Image}
              }
            ]
          });
        }

        contents.add({
          "parts": [
            {"text": "Question: $_currentQuestion"}
          ]
        });

        contents.add({
          "parts": [
            {
              "text":
                  "User's Answer: $_currentAnswer\n\nEvaluate the user's answer based on the provided image, the generated question, and the user's answer. Provide feedback and a score out of 100."
            }
          ]
        });

        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: json.encode({"contents": contents}),
        );

        if (response.statusCode == 200) {
          logger.i('ShortTestPage - Answer evaluation successful');
          final jsonResponse = json.decode(response.body);
          if (jsonResponse['candidates'] != null &&
              jsonResponse['candidates'].isNotEmpty) {
            final evaluation =
                jsonResponse['candidates'][0]['content']['parts'][0]['text'];
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: const Text('Answer Evaluation'),
                  content: SingleChildScrollView(child: Text(evaluation)),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _autoSubmitTest();
                      },
                      child: const Text('OK'),
                    ),
                  ],
                );
              },
            );
          } else {
            throw Exception('Invalid response format or empty candidates');
          }
        } else {
          throw Exception(
              'Failed to evaluate answer. Status: ${response.statusCode}, Body: ${response.body}');
        }
      } catch (e) {
        logger.e('ShortTestPage - Error evaluating answer: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error evaluating answer: ${e.toString()}')),
        );
      } finally {
        setState(() {
          _isEvaluatingAnswer = false;
        });
      }
    }
  }

  void _nextQuestion() {
    logger.i('ShortTestPage - Moving to next question');
    setState(() {
      _selectedOption = null; // Clear selected option for next question
      _questionAnswered = false; // Reset for the next question
      _currentQuestionIndex++;
      if (_currentQuestionIndex < _mcqQuestions.length) {
        _currentQuestion = _mcqQuestions[_currentQuestionIndex]['question'];
      } else {
        _timer?.cancel(); // Stop the timer if all questions are answered
        _testFinished = true; // Mark test as finished
      }
      logger
          .i('ShortTestPage - Current question index: $_currentQuestionIndex');
    });
  }

  void _autoSubmitTest() {
    logger.i('ShortTestPage - Auto submitting test');
    _timer?.cancel();
    setState(() {
      _testFinished = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Time is up! Test auto-submitted.')),
    );
  }

  String _formatTime(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final remainingSeconds = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$remainingSeconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'Short Test'),
      body: Column(
        children: [
          if (_testStarted && !_testFinished)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                'Time Remaining: ${_formatTime(_remainingTimeInSeconds)}',
                style: TextStyle(
                  fontSize: 24.0,
                  fontWeight: FontWeight.bold,
                  color:
                      _remainingTimeInSeconds < 60 ? Colors.red : Colors.green,
                ),
              ),
            ),
          Expanded(
            child: _testFinished
                ? SingleChildScrollView(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Test Completed!',
                          style: TextStyle(
                              fontSize: 24.0,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).primaryColor),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'You answered ${_mcqResults.where((result) => result['is_correct']).length} out of ${_mcqResults.length} questions correctly.',
                          style: const TextStyle(fontSize: 18.0),
                        ),
                        const SizedBox(height: 20),
                        ..._mcqResults.asMap().entries.map((entry) {
                          int index = entry.key;
                          Map<String, dynamic> result = entry.value;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 16.0),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Question ${index + 1}: ${result['question']}',
                                    style: const TextStyle(
                                        fontSize: 18.0,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Your Answer: ${result['selected_option']}',
                                    style: TextStyle(
                                      fontSize: 16.0,
                                      color: result['is_correct']
                                          ? Colors.green
                                          : Colors.red,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (!result['is_correct'])
                                    Text(
                                      'Correct Answer: ${result['correct_answer']}',
                                      style: const TextStyle(
                                        fontSize: 16.0,
                                        color: Colors.green,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  const SizedBox(height: 10),
                                  Text('Options:'),
                                  ...(result['options'] as Map<String, dynamic>)
                                      .entries
                                      .map((optionEntry) {
                                    return Text(
                                      '${optionEntry.key}) ${optionEntry.value}',
                                      style: TextStyle(
                                        color: optionEntry.key ==
                                                result['correct_answer']
                                            ? Colors.green
                                            : (optionEntry.key ==
                                                        result[
                                                            'selected_option'] &&
                                                    !result['is_correct'])
                                                ? Colors.red
                                                : null,
                                      ),
                                    );
                                  }).toList(),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                        const SizedBox(height: 20),
                        Center(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.of(context)
                                  .pop(); // Go back to previous page
                            },
                            child: const Text('Finish Test'),
                          ),
                        ),
                      ],
                    ),
                  )
                : Center(
                    child: _testStarted
                        ? SingleChildScrollView(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(height: 20),
                                Text(
                                  _currentQuestion,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontSize: 20.0,
                                      fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 20),
                                ...[
                                  // Wrap conditional widgets in a list and spread them
                                  if (_selectedTestType == 'MCQ Test' &&
                                      _mcqQuestions.isNotEmpty)
                                    Column(
                                      // Wrap the list of RadioListTiles in a Column
                                      children: [
                                        ...(_mcqQuestions[_currentQuestionIndex]
                                                    ['options']
                                                as Map<String, dynamic>)
                                            .entries
                                            .map((entry) {
                                          Color? textColor;
                                          if (_questionAnswered) {
                                            if (entry.key ==
                                                _mcqQuestions[
                                                        _currentQuestionIndex]
                                                    ['correct_answer']) {
                                              textColor = Colors.green;
                                            } else if (entry.key ==
                                                    _selectedOption &&
                                                entry.key !=
                                                    _mcqQuestions[
                                                            _currentQuestionIndex]
                                                        ['correct_answer']) {
                                              textColor = Colors.red;
                                            }
                                          }
                                          return RadioListTile<String>(
                                            title: Text(
                                              '${entry.key}) ${entry.value}',
                                              style:
                                                  TextStyle(color: textColor),
                                            ),
                                            value: entry.key,
                                            groupValue: _selectedOption,
                                            onChanged: _questionAnswered
                                                ? null
                                                : (String? value) {
                                                    setState(() {
                                                      _selectedOption = value;
                                                    });
                                                  },
                                          );
                                        }).toList(),
                                      ],
                                    )
                                  else if (_showAnswerInput)
                                    TextField(
                                      controller: _answerController,
                                      decoration: InputDecoration(
                                        labelText: 'Your Answer',
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12.0),
                                        ),
                                        prefixIcon: const Icon(Icons.edit),
                                      ),
                                      maxLines: 5,
                                      minLines: 1,
                                    ),
                                ], // End of spread list
                                const SizedBox(height: 20),
                                ElevatedButton(
                                  onPressed: _isEvaluatingAnswer
                                      ? null
                                      : (_questionAnswered
                                          ? _nextQuestion
                                          : _submitAnswer),
                                  child: Text(
                                    _isEvaluatingAnswer
                                        ? 'Evaluating...'
                                        : (_questionAnswered
                                            ? 'Next Question'
                                            : 'Submit Answer'),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(50),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12.0),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : const Text(
                            'Short Test Page - Configure test to begin.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 18.0),
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  // Removed _buildImagePickerCard as it's no longer needed here
}
