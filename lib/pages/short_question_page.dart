import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:async';
import 'package:pi_qbank/pages/tools_page.dart';
import 'package:pi_qbank/models/test_result.dart'; // Import TestResult
import 'package:pi_qbank/services/test_result_service.dart'; // Import TestResultService
import 'package:pi_qbank/pages/short_question_analytics_page.dart'; // Import ShortQuestionAnalyticsPage
import 'package:pi_qbank/widgets/upload_test_button.dart';
import 'package:pi_qbank/services/saved_test_service.dart'; // Import SavedTestService

class ShortQuestionPage extends StatefulWidget {
  final int numberOfQuestions;
  final int testTimeInMinutes;
  final List<XFile>? selectedImages;
  final String aiResponse;
  final String language;
  final String? savedTestId;
  final String testType; // Added: Field for test type

  const ShortQuestionPage({
    super.key,
    required this.numberOfQuestions,
    required this.testTimeInMinutes,
    this.selectedImages,
    required this.aiResponse,
    required this.language,
    this.savedTestId, 
    this.testType = 'Short Question', // Default value
  });

  @override
  State<ShortQuestionPage> createState() => _ShortQuestionPageState();
}

class _ShortQuestionPageState extends State<ShortQuestionPage>
    with TickerProviderStateMixin {
  List<Map<String, dynamic>> questions = [];
  Map<int, TextEditingController> answerControllers = {};
  int remainingTimeInSeconds = 0;
  bool _timeIsLow = false;
  late Timer _timer;
  bool _isSubmitted = false;
  late AnimationController _timerAnimationController;
  late AnimationController _resultAnimationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    parseQuestions();
    remainingTimeInSeconds = widget.testTimeInMinutes * 60;
    _startTimer();
    _initializeAnimations();
  }

  void _initializeAnimations() {
    _timerAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _resultAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
          parent: _resultAnimationController, curve: Curves.easeInOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _resultAnimationController,
      curve: Curves.elasticOut,
    ));
  }

  void parseQuestions() {
    try {
      List<String> lines = widget.aiResponse.split('\n');
      String currentQuestion = '';
      String currentAnswer = '';
      bool insideQuestion = false;

      for (String line in lines) {
        line = line.trim();
        if (line.isEmpty) continue;

        // Match any number (including multi-digit) followed by dot, or Bengali numbers
        if (RegExp(r'^\d+\.|^[\u09E6-\u09EF]+\.').hasMatch(line)) {
          if (currentQuestion.isNotEmpty) {
            questions.add({
              'question': _stripMarkdown(currentQuestion.trim()),
              'answer': _stripMarkdown(currentAnswer.trim()),
            });
            if (questions.length >= widget.numberOfQuestions) break;
          }
          currentQuestion = line;
          currentAnswer = '';
          insideQuestion = true; // We are now inside a question block
        } else if (line.toLowerCase().contains('উত্তর:') ||
            line.toLowerCase().contains('answer:') ||
            line.startsWith('উঃ')) {
          // If an answer is detected, stop adding to currentQuestion
          insideQuestion = false;
          currentAnswer = line
              .replaceFirst(
                  RegExp(r'^(উত্তর:|answer:|উঃ)', caseSensitive: false), '')
              .trim();
        } else {
          // If not a new question and not an answer line,
          // append to currentQuestion if still inside question block,
          // otherwise append to currentAnswer (for multi-line answers)
          if (insideQuestion) {
            currentQuestion = '$currentQuestion $line';
          } else {
            currentAnswer = '$currentAnswer $line';
          }
        }
      }

      // Add the last question if exists and we haven't reached the limit
      if (currentQuestion.isNotEmpty &&
          questions.length < widget.numberOfQuestions) {
        questions.add({
          'question': _stripMarkdown(currentQuestion.trim()),
          'answer': _stripMarkdown(currentAnswer.trim()),
        });
      }

      // Initialize controllers for all questions
      for (int i = 0; i < questions.length; i++) {
        answerControllers[i] = TextEditingController();
      }
    } catch (e) {
      // Silently handle error
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (remainingTimeInSeconds > 0) {
          remainingTimeInSeconds--;
          _timeIsLow = remainingTimeInSeconds < 60;
          if (_timeIsLow && !_timerAnimationController.isAnimating) {
            _timerAnimationController.repeat(reverse: true);
          }
        } else {
          _timer.cancel();
          if (!_isSubmitted) {
            _submitTest();
          }
        }
      });
    });
  }

  Future<void> _submitTest() async {
    if (_isSubmitted) return;

    _isSubmitted = true;
    _timer.cancel();
    _resultAnimationController.forward();
    setState(() {});

    int correctCount = 0;
    List<Map<String, dynamic>> questionsAndAnswers = [];

    for (int i = 0; i < questions.length; i++) {
      final questionData = questions[i];
      final userAnswer = answerControllers[i]?.text ?? '';
      final correctAnswer = questionData['answer'] ?? '';
      final isCorrect = _isAnswerCorrect(userAnswer, correctAnswer);

      if (isCorrect) {
        correctCount++;
      }

      questionsAndAnswers.add({
        'question': questionData['question'],
        'correctAnswer': correctAnswer,
        'userAnswer': userAnswer,
        'isCorrect': isCorrect,
      });
    }

    final testResult = TestResult(
      testId: DateTime.now().millisecondsSinceEpoch.toString(),
      testType: widget.testType,
      timestamp: DateTime.now(),
      score: correctCount,
      totalQuestions: questions.length,
      timeTakenInSeconds:
          (widget.testTimeInMinutes * 60) - remainingTimeInSeconds,
      language: widget.language,
      questionsAndAnswers: questionsAndAnswers,
      imagePaths: widget.selectedImages?.map((e) => e.path).toList() ?? [],
    );

    TestResultService.saveTestResult(testResult);

    // If this test was loaded from a saved test, delete it after completion
    if (widget.savedTestId != null) {
      await SavedTestService.deleteTest(widget.savedTestId!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF667EEA),
                Color(0xFF764BA2),
              ],
            ),
          ),
        ),
        title: _isSubmitted
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
                        ? 1.0 + (_timerAnimationController.value * 0.1)
                        : 1.0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _timeIsLow
                              ? [Colors.red.shade400, Colors.red.shade600]
                              : [
                                  Colors.white.withOpacity(0.9),
                                  Colors.white.withOpacity(0.7)
                                ],
                        ),
                        borderRadius: BorderRadius.circular(25),
                        boxShadow: [
                          BoxShadow(
                            color: (_timeIsLow ? Colors.red : Colors.black)
                                .withOpacity(0.2),
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
                            color: _timeIsLow
                                ? Colors.white
                                : const Color(0xFF667EEA),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            formatTime(remainingTimeInSeconds),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: _timeIsLow
                                  ? Colors.white
                                  : const Color(0xFF667EEA),
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
        child: _isSubmitted ? _buildResultsView() : _buildTestView(),
      ),
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
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white,
                  const Color(0xFFF8FAFC),
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
                Expanded(
                  child: _buildInfoCard(
                    'Questions',
                    '${questions.length}',
                    Icons.quiz_outlined,
                    const Color(0xFF667EEA),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildInfoCard(
                    'Answered',
                    '${answerControllers.values.where((c) => c.text.isNotEmpty).length}',
                    Icons.check_circle_outline,
                    const Color(0xFF10B981),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildInfoCard(
                    'Remaining',
                    '${answerControllers.values.where((c) => c.text.isEmpty).length}',
                    Icons.pending_outlined,
                    const Color(0xFFF59E0B),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(
              height: 20), // Added space between info card and questions
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: questions.length,
            itemBuilder: (context, index) {
              final question = questions[index];
              final isAnswered =
                  answerControllers[index]?.text.isNotEmpty ?? false;
              return Container(
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white,
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
                        ? const Color(0xFF667EEA).withOpacity(0.3)
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
                                  const Color(0xFF667EEA).withOpacity(0.1),
                                  const Color(0xFF764BA2).withOpacity(0.05)
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
                                    ? [
                                        const Color(0xFF667EEA),
                                        const Color(0xFF764BA2)
                                      ]
                                    : [
                                        Colors.grey.shade400,
                                        Colors.grey.shade500
                                      ],
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: (isAnswered
                                          ? const Color(0xFF667EEA)
                                          : Colors.grey)
                                      .withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                widget.language == 'বাংলা'
                                    ? _convertToBengaliNumber(index + 1)
                                    : '${index + 1}',
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
                              question['question'] ?? '',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1F2937),
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
              );
            },
          ),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              gradient: const LinearGradient(
                colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF667EEA).withOpacity(0.4),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: questions.isEmpty ? null : _submitTest,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                minimumSize: const Size(double.infinity, 50),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.send_rounded, size: 24, color: Colors.white),
                  const SizedBox(width: 12),
                  Text(
                    widget.language == 'বাংলা'
                        ? 'পরীক্ষা জমা দিন'
                        : 'Submit Test',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
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
    final total = questions.length;
    final percentage = (correctAnswers / total * 100).toStringAsFixed(1);
    final notAnswered = questions
        .where((q) =>
            (answerControllers[questions.indexOf(q)]?.text ?? '').isEmpty)
        .length;
    final incorrect = total - correctAnswers - notAnswered;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: SingleChildScrollView(
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
                    colors: [Colors.white, const Color(0xFFF8FAFC)],
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
                        colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                      ).createShader(bounds),
                      child: Text(
                        widget.language == 'বাংলা'
                            ? '🎉 পরীক্ষার ফলাফল'
                            : '🎉 Test Results',
                        style: const TextStyle(
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
                            child: _buildStatisticCard(total.toString(),
                                'Total', Icons.quiz, const Color(0xFF667EEA))),
                        const SizedBox(width: 12),
                        Expanded(
                            child: _buildStatisticCard(
                                correctAnswers.toString(),
                                'Correct',
                                Icons.check_circle,
                                const Color(0xFF10B981))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                            child: _buildStatisticCard(
                                incorrect.toString(),
                                'Wrong',
                                Icons.cancel,
                                const Color(0xFFEF4444))),
                        const SizedBox(width: 12),
                        Expanded(
                            child: _buildStatisticCard(
                                notAnswered.toString(),
                                'Skipped',
                                Icons.help,
                                const Color(0xFFF59E0B))),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Text(
                  widget.language == 'বাংলা'
                      ? '📊 বিস্তারিত বিশ্লেষণ'
                      : '📊 Detailed Analysis',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ...questions.asMap().entries.map((entry) {
                final index = entry.key;
                final question = entry.value;
                final answer = answerControllers[index]?.text ?? '';
                final hasAnswer = answer.isNotEmpty;
                final isCorrect =
                    _isAnswerCorrect(answer, question['answer'] ?? '');

                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Colors.white, Colors.grey.shade50],
                    ),
                    border: Border.all(
                      color: isCorrect
                          ? const Color(0xFF10B981).withOpacity(0.3)
                          : hasAnswer
                              ? const Color(0xFFEF4444).withOpacity(0.3)
                              : const Color(0xFFF59E0B).withOpacity(0.3),
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
                                ? [
                                    const Color(0xFF10B981),
                                    const Color(0xFF059669)
                                  ]
                                : hasAnswer
                                    ? [
                                        const Color(0xFFEF4444),
                                        const Color(0xFFDC2626)
                                      ]
                                    : [
                                        const Color(0xFFF59E0B),
                                        const Color(0xFFD97706)
                                      ],
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: (isCorrect
                                      ? const Color(0xFF10B981)
                                      : hasAnswer
                                          ? const Color(0xFFEF4444)
                                          : const Color(0xFFF59E0B))
                                  .withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(
                          isCorrect
                              ? Icons.check_rounded
                              : hasAnswer
                                  ? Icons.close_rounded
                                  : Icons.help_outline_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      title: Text(
                        widget.language == 'বাংলা'
                            ? 'প্রশ্ন ${_convertToBengaliNumber(index + 1)}'
                            : 'Question ${index + 1}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      subtitle: Text(
                        question['question'] ?? '',
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
                                question['question'] ?? '',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF1F2937),
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 16),
                              _buildAnswerCard(
                                widget.language == 'বাংলা'
                                    ? 'আপনার উত্তর'
                                    : 'Your Answer',
                                hasAnswer
                                    ? (answerControllers[index]?.text ?? '')
                                    : '', // Value is just the answer or empty
                                hasAnswer
                                    ? '' // No explanation if answered
                                    : (widget.language == 'বাংলা'
                                        ? 'প্রশ্নটি এড়িয়ে যাওয়া হয়েছে'
                                        : 'Question was skipped'),
                                isCorrect
                                    ? const Color(0xFF10B981)
                                    : hasAnswer
                                        ? const Color(0xFFEF4444)
                                        : const Color(0xFFF59E0B),
                                isCorrect
                                    ? Icons.check_circle
                                    : hasAnswer
                                        ? Icons.cancel
                                        : Icons.help_outline,
                              ),
                              if (!isCorrect || !hasAnswer) ...[
                                const SizedBox(height: 12),
                                _buildAnswerCard(
                                  widget.language == 'বাংলা'
                                      ? 'সঠিক উত্তর'
                                      : 'Correct Answer',
                                  question['answer'],
                                  '', // No explanation for correct answer
                                  const Color(0xFF10B981),
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
              if (_isSubmitted)
                UploadTestButton(
                  questions: questions,
                  testType: widget.testType,
                  language: widget.language,
                ),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF667EEA).withOpacity(0.4),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: () {
                    final testResult = TestResult(
                      testId: DateTime.now().millisecondsSinceEpoch.toString(),
                      testType: widget.testType,
                      timestamp: DateTime.now(),
                      score: questions
                          .where((q) => _isAnswerCorrect(
                              answerControllers[questions.indexOf(q)]?.text ??
                                  '',
                              q['answer'] ?? ''))
                          .length,
                      totalQuestions: questions.length,
                      timeTakenInSeconds: (widget.testTimeInMinutes * 60) -
                          remainingTimeInSeconds,
                      language: widget.language,
                      questionsAndAnswers:
                          questions.asMap().entries.map((entry) {
                        final index = entry.key;
                        final questionData = entry.value;
                        final userAnswer = answerControllers[index]?.text ?? '';
                        final correctAnswer = questionData['answer'] ?? '';
                        final isCorrect =
                            _isAnswerCorrect(userAnswer, correctAnswer);
                        return {
                          'question': questionData['question'],
                          'correctAnswer': correctAnswer,
                          'userAnswer': userAnswer,
                          'isCorrect': isCorrect,
                        };
                      }).toList(),
                      imagePaths:
                          widget.selectedImages?.map((e) => e.path).toList() ??
                              [],
                    );
                    _navigateToAnalyticsPage(testResult);
                  },
                  icon:
                      const Icon(Icons.analytics_rounded, color: Colors.white),
                  label: Text(
                    widget.language == 'বাংলা'
                        ? 'বিশ্লেষণ দেখুন'
                        : 'View Analytics',
                    style: const TextStyle(
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
              ),
              const SizedBox(height: 16), // Add some space
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF667EEA).withOpacity(0.4),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const ToolsPage()),
                      (Route<dynamic> route) => false,
                    );
                  },
                  icon: const Icon(Icons.home_rounded, color: Colors.white),
                  label: Text(
                    widget.language == 'বাংলা'
                        ? 'হোমপেজে ফিরে যান'
                        : 'Back to Home',
                    style: const TextStyle(
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToAnalyticsPage(TestResult testResult) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ShortQuestionAnalyticsPage(
          testResults: [
            testResult
          ], // Pass a list containing the single test result
        ),
      ),
    );
  }

  String formatTime(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  String _stripMarkdown(String text) {
    // Remove bold (**text**) and italics (*text*)
    String strippedText =
        text.replaceAll(RegExp(r'\*\*([^\*]+)\*\*'), r'\1'); // bold
    strippedText =
        strippedText.replaceAll(RegExp(r'\*([^\*]+)\*'), r'\1'); // italics
    // Remove any remaining single asterisks that might be part of the text but not markdown
    strippedText = strippedText.replaceAll(RegExp(r'\*'), '');
    // Remove leading/trailing spaces
    return strippedText.trim();
  }

  @override
  void dispose() {
    _timer.cancel();
    _timerAnimationController.dispose();
    _resultAnimationController.dispose();
    for (var controller in answerControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _buildInfoCard(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 14),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '$title: $value',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
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
      padding: const EdgeInsets.all(16),
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
          const SizedBox(height: 8),
          Text(
            value.isEmpty
                ? (widget.language == 'বাংলা'
                    ? 'উত্তর দেওয়া হয়নি'
                    : 'Not Answered')
                : value,
            style: TextStyle(
              fontSize: 16,
              color: value.isEmpty ? Colors.grey : color,
              fontStyle: value.isEmpty ? FontStyle.italic : FontStyle.normal,
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

  Color _getScoreColor(double percentage) {
    if (percentage >= 80) return Colors.green;
    if (percentage >= 60) return Colors.blue;
    if (percentage >= 40) return Colors.orange;
    return Colors.red;
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
