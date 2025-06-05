import 'package:flutter/material.dart';
import 'dart:async';
import 'package:pi_qbank/pages/tools_page.dart';

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

class _FillInTheBlanksTestPageState extends State<FillInTheBlanksTestPage>
    with TickerProviderStateMixin {
  final List<Map<String, String>> _fillInTheBlanksQuestions = [];
  final Map<int, TextEditingController> _answerControllers = {};
  bool _testSubmitted = false;
  final List<Map<String, dynamic>> _fillInTheBlanksResults = [];
  late Timer _timer;
  late int _remainingSeconds;
  bool _timeIsLow = false;
  late AnimationController _timerAnimationController;
  late AnimationController _submitButtonController;
  late Animation<double> _timerPulseAnimation;
  late Animation<double> _submitButtonAnimation;

  // Beautiful color scheme
  static const Color primaryBlue = Color(0xFF2196F3);
  static const Color primaryPurple = Color(0xFF9C27B0);
  static const Color accentTeal = Color(0xFF00BCD4);
  static const Color successGreen = Color(0xFF4CAF50);
  static const Color warningOrange = Color(0xFFFF9800);
  static const Color errorRed = Color(0xFFF44336);
  static const Color backgroundLight = Color(0xFFF8F9FA);
  static const Color cardWhite = Color(0xFFFFFFFF);

  @override
  void initState() {
    super.initState();
    _parseFillInTheBlanksQuestions();
    _initializeTimer();
    _initializeAnimations();
  }

  @override
  void dispose() {
    _timer.cancel();
    _timerAnimationController.dispose();
    _submitButtonController.dispose();
    _answerControllers.forEach((key, controller) => controller.dispose());
    super.dispose();
  }

  void _initializeAnimations() {
    _timerAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _submitButtonController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _timerPulseAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(
      parent: _timerAnimationController,
      curve: Curves.easeInOut,
    ));

    _submitButtonAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _submitButtonController,
      curve: Curves.easeInOut,
    ));

    _timerAnimationController.repeat(reverse: true);
  }

  void _initializeTimer() {
    _remainingSeconds = widget.testTimeInMinutes * 60;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
          _timeIsLow = _remainingSeconds < 60;
          if (_timeIsLow && !_timerAnimationController.isAnimating) {
            _timerAnimationController.repeat(reverse: true);
          }
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
    _answerControllers.forEach((key, controller) => controller.dispose());
    _answerControllers.clear();

    final lines = widget.aiResponse.split('\n');
    String currentQuestion = '';
    String currentAnswer = '';

    // Regex to match both English and Bengali numbers followed by a dot and space
    final questionNumberPattern = RegExp(r'^\s*(\d+|[১২৩৪৫৬৭৮৯০]+)\.\s*(.*)');

    for (var i = 0; i < lines.length; i++) {
      String line = lines[i].trim();
      if (line.isEmpty) continue;

      // Skip specific instruction lines if they appear in the response
      if (line.contains('শূন্যস্থান পূরণ করার প্রশ্ন') || line.contains('fill-in-the-blank questions')) {
        continue;
      }

      Match? questionMatch = questionNumberPattern.firstMatch(line);
      if (questionMatch != null) {
        // If we have a complete question and answer from previous iteration, add it
        if (currentQuestion.isNotEmpty && currentAnswer.isNotEmpty) {
          _fillInTheBlanksQuestions.add({
            'question': currentQuestion,
            'answer': currentAnswer,
          });
          _answerControllers[_fillInTheBlanksQuestions.length - 1] = TextEditingController();
        }

        String content = questionMatch.group(2)!.trim();
        int blankIndex = content.indexOf('_____');

        if (blankIndex != -1) {
          // Question and potentially answer are on the same line
          // The entire content of the line is the question, including text after the blank
          currentQuestion = content;

          // Now, try to find the answer on the next line
          if (i + 1 < lines.length) {
            String nextLine = lines[i + 1].trim();
            // Check if the next line is not another question number
            if (!questionNumberPattern.hasMatch(nextLine)) {
              currentAnswer = nextLine;
              i++; // Consume the next line as the answer
            } else {
              // Next line is a new question, so no answer found for current question
              currentAnswer = '';
            }
          } else {
            // Last line, no answer found
            currentAnswer = '';
          }
        } else {
          // This line is numbered but doesn't contain a blank.
          // This is a malformed question for fill-in-the-blanks based on the prompt.
          // We will still capture it as a question, but it won't have an answer.
          currentQuestion = content;
          currentAnswer = '';
        }
      } else {
        // This line is not a new question number.
        // If we are currently building a question (currentQuestion is not empty)
        // and we haven't found an answer yet (currentAnswer is empty),
        // this line might be a continuation of the question or the answer.
        if (currentQuestion.isNotEmpty && currentAnswer.isEmpty) {
          // Check if this line contains the blank, if the previous line didn't
          int blankIndex = line.indexOf('_____');
          if (blankIndex != -1) {
            // If a blank is found in a continuation line, treat the entire line as part of the question
            currentQuestion = '$currentQuestion $line'.trim();
            // Then, try to find the answer on the next line
            if (i + 1 < lines.length) {
              String nextLine = lines[i + 1].trim();
              if (!questionNumberPattern.hasMatch(nextLine)) {
                currentAnswer = nextLine;
                i++; // Consume the next line as the answer
              }
            }
          } else {
            // If no blank, and not a new question, it's just a continuation of the question text
            currentQuestion = '$currentQuestion $line'.trim();
          }
        }
      }
    }

    // Add the last question if it exists
    if (currentQuestion.isNotEmpty && currentAnswer.isNotEmpty) {
      _fillInTheBlanksQuestions.add({
        'question': currentQuestion,
        'answer': currentAnswer,
      });
      _answerControllers[_fillInTheBlanksQuestions.length - 1] = TextEditingController();
    }

    setState(() {});
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
      backgroundColor: backgroundLight,
      appBar: _buildAppBar(),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              backgroundLight,
              cardWhite,
            ],
          ),
        ),
        child: _testSubmitted ? _buildResultsView() : _buildTestView(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.transparent,
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [primaryBlue, primaryPurple],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      title: _testSubmitted
          ? ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Colors.white, Colors.white70],
              ).createShader(bounds),
              child: Text(
                widget.language,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            )
          : AnimatedBuilder(
              animation: _timerAnimationController,
              builder: (context, child) {
                return Transform.scale(
                  scale: _timeIsLow
                      ? 1.0 + (_timerPulseAnimation.value * 0.1)
                      : 1.0,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _timeIsLow
                            ? [errorRed, errorRed.withOpacity(0.7)]
                            : [
                                Colors.white.withOpacity(0.9),
                                Colors.white.withOpacity(0.7)
                              ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [
                        BoxShadow(
                          color: _timeIsLow
                              ? errorRed.withOpacity(0.2)
                              : Colors.black.withOpacity(0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 20,
                          color: _timeIsLow ? Colors.white : primaryBlue,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatTime(_remainingSeconds),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _timeIsLow ? Colors.white : primaryBlue,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      centerTitle: true,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
        onPressed: () => Navigator.of(context).pop(),
      ),
    );
  }

  Widget _buildTestView() {
    if (_fillInTheBlanksQuestions.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.quiz_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No questions available',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  cardWhite,
                  backgroundLight,
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildInfoCard(
                  'Total',
                  '${_fillInTheBlanksQuestions.length}',
                  Icons.quiz_outlined,
                  primaryBlue,
                ),
                _buildInfoCard(
                  'Answered',
                  '${_answerControllers.values.where((c) => c.text.isNotEmpty).length}',
                  Icons.check_circle_outline,
                  successGreen,
                ),
                _buildInfoCard(
                  'Remaining',
                  '${_fillInTheBlanksQuestions.length - _answerControllers.values.where((c) => c.text.isNotEmpty).length}',
                  Icons.pending_outlined,
                  warningOrange,
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
              return _buildQuestionCard(index);
            },
          ),
          const SizedBox(height: 20),
          _buildSubmitButton(),
        ],
      ),
    );
  }

  Widget _buildInfoCard(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(int index) {
    final question = _fillInTheBlanksQuestions[index];
    final isAnswered = _answerControllers[index]?.text.isNotEmpty ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cardWhite,
            Colors.grey.shade50,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
        border: Border.all(
          color: isAnswered
              ? primaryBlue.withOpacity(0.3)
              : Colors.grey.withOpacity(0.1),
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isAnswered
                    ? [
                        primaryBlue.withOpacity(0.1),
                        primaryPurple.withOpacity(0.05)
                      ]
                    : [Colors.grey.shade100, Colors.grey.shade50],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isAnswered
                          ? [primaryBlue, primaryPurple]
                          : [Colors.grey.shade400, Colors.grey.shade500],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (isAnswered ? primaryBlue : Colors.grey)
                            .withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    question['question']!,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2937), // Dark grey text
                      height: 1.4,
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
                labelText: 'আপনার উত্তর লিখুন',
                labelStyle: TextStyle(color: Colors.grey.shade600),
                hintText: 'এখানে টাইপ করুন...',
                hintStyle: TextStyle(color: Colors.grey.shade400),
                prefixIcon: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [primaryBlue, accentTeal],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.edit_rounded, color: Colors.white),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey.shade100,
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide(color: primaryBlue, width: 2),
                ),
              ),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Color(0xFF374151), // Darker text for input
              ),
              onChanged: (value) {
                setState(() {});
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return AnimatedBuilder(
      animation: _submitButtonAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _submitButtonAnimation.value,
          child: GestureDetector(
            onTapDown: (_) => _submitButtonController.forward(),
            onTapUp: (_) => _submitButtonController.reverse(),
            onTapCancel: () => _submitButtonController.reverse(),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                gradient: const LinearGradient(
                  colors: [primaryBlue, primaryPurple],
                ),
                boxShadow: [
                  BoxShadow(
                    color: primaryBlue.withOpacity(0.4),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _submitTest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.send_rounded, size: 24, color: Colors.white),
                    SizedBox(width: 12),
                    Text(
                      'Submit Test',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
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
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [cardWhite, backgroundLight],
                ),
                borderRadius: BorderRadius.circular(25),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 25,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [primaryBlue, primaryPurple],
                    ).createShader(bounds),
                    child: const Text(
                      '🎉 Test Results',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          _getScoreColor(double.parse(percentage)),
                          _getScoreColor(double.parse(percentage))
                              .withOpacity(0.7),
                        ],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _getScoreColor(double.parse(percentage))
                              .withOpacity(0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$percentage%',
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            _getGradeText(double.parse(percentage)),
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.white70,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  Row(
                    children: [
                      Expanded(
                          child: _buildStatisticCard(total.toString(), 'Total',
                              Icons.quiz_outlined, primaryBlue)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _buildStatisticCard(
                              score.toString(),
                              'Correct',
                              Icons.check_circle_outline,
                              successGreen)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                          child: _buildStatisticCard(incorrect.toString(),
                              'Wrong', Icons.cancel, errorRed)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _buildStatisticCard(notAnswered.toString(),
                              'Skipped', Icons.help, warningOrange)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardWhite,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: const Text(
                '📊 Detailed Analysis',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ..._fillInTheBlanksResults.asMap().entries.map((entry) {
              final index = entry.key;
              final result = entry.value;
              final isEmpty = (result['user_answer'] as String).isEmpty;
              final isCorrect = result['is_correct'];

              if (isEmpty) {
              } else if (isCorrect) {
              } else {}

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [cardWhite, Colors.grey.shade50],
                  ),
                  border: Border.all(
                    color: isCorrect
                        ? successGreen.withOpacity(0.3)
                        : isEmpty
                            ? warningOrange.withOpacity(0.3)
                            : errorRed.withOpacity(0.3),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    leading: Container(
                      width: 45,
                      height: 45,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isCorrect
                              ? [successGreen, successGreen.withOpacity(0.8)]
                              : isEmpty
                                  ? [
                                      warningOrange,
                                      warningOrange.withOpacity(0.8)
                                    ]
                                  : [errorRed, errorRed.withOpacity(0.8)],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (isCorrect
                                    ? successGreen
                                    : isEmpty
                                        ? warningOrange
                                        : errorRed)
                                .withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        isCorrect
                            ? Icons.check_rounded
                            : isEmpty
                                ? Icons.help_outline_rounded
                                : Icons.close_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    title: Text(
                      'Question ${index + 1}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    subtitle: Text(
                      result['question'],
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey[600],
                        height: 1.3,
                      ),
                    ),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(14),
                            bottomRight: Radius.circular(14),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              result['question'],
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF1F2937),
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 16),
                              _buildAnswerCard(
                                'Your Answer',
                                result['user_answer'],
                                isEmpty ? 'Question was skipped' : '', // Explanation for skipped
                                isEmpty
                                    ? warningOrange
                                    : (isCorrect ? successGreen : errorRed),
                                isEmpty
                                    ? Icons.help_outline
                                    : (isCorrect
                                        ? Icons.check_circle
                                        : Icons.cancel),
                              ),
                              if (!isCorrect || isEmpty) ...[
                                const SizedBox(height: 12),
                                _buildAnswerCard(
                                  'Correct Answer',
                                  result['correct_answer'],
                                  '', // No explanation for correct answer
                                  successGreen,
                                  Icons.lightbulb_outline,
                                ),
                              ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 30),
            _buildFinishButton(),
          ],
        ));
  }

  Widget _buildStatisticCard(
      String value, String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: color.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnswerCard(String title, String value, String explanation,
      Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value.isEmpty ? 'Not answered' : value,
            style: TextStyle(
              fontSize: 16,
              color: value.isEmpty ? Colors.grey : color,
              fontStyle: value.isEmpty ? FontStyle.italic : FontStyle.normal,
            ),
          ),
          // Removed SizedBox(height: 4) here as explanation is often empty
        ],
      ),
    );
  }

  Widget _buildFinishButton() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        gradient: const LinearGradient(
          colors: [primaryBlue, primaryPurple],
        ),
        boxShadow: [
          BoxShadow(
            color: primaryBlue.withOpacity(0.4),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: () {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const ToolsPage()),
            (Route<dynamic> route) => false,
          );
        },
        icon: const Icon(Icons.home_rounded, color: Colors.white),
        label: const Text(
          'Back to Home',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          minimumSize: const Size(double.infinity, 55),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  Color _getScoreColor(double percentage) {
    if (percentage >= 80) return successGreen;
    if (percentage >= 60) return primaryBlue;
    if (percentage >= 40) return warningOrange;
    return errorRed;
  }

  String _getGradeText(double percentage) {
    if (percentage >= 90) return 'A+';
    if (percentage >= 80) return 'A';
    if (percentage >= 70) return 'B';
    if (percentage >= 60) return 'C';
    if (percentage >= 50) return 'D';
    return 'F';
  }
}
