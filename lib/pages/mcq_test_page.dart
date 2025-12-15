import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:async';
import 'package:pi_qbank/pages/tools_page.dart';
import 'package:pi_qbank/models/test_result.dart'; // Import TestResult
import 'package:pi_qbank/services/test_result_service.dart'; // Import TestResultService
import 'package:pi_qbank/services/saved_test_service.dart'; // Import SavedTestService

class MCQTestPage extends StatefulWidget {
  final int numberOfQuestions;
  final int testTimeInMinutes;
  final List<XFile>? selectedImages;
  final String aiResponse;
  final String language;
  final String? savedTestId; // New: Optional ID for saved tests

  const MCQTestPage({
    super.key,
    required this.numberOfQuestions,
    required this.testTimeInMinutes,
    this.selectedImages,
    required this.aiResponse,
    required this.language,
    this.savedTestId, // New: Initialize savedTestId
  });

  @override
  State<MCQTestPage> createState() => _MCQTestPageState();
}

class _MCQTestPageState extends State<MCQTestPage>
    with TickerProviderStateMixin {
  late List<dynamic> _mcqQuestions = [];
  final Map<int, String?> _userAnswers = {};
  bool _testSubmitted = false;
  final List<Map<String, dynamic>> _mcqResults = [];
  late Timer _timer;
  late int _remainingSeconds;
  bool _timeIsLow = false;
  late AnimationController _timerAnimationController;
  late AnimationController _resultAnimationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _parseMcqQuestions();
    _initializeTimer();
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

  void _parseMcqQuestions() {
    try {
      String cleanedResponse = widget.aiResponse
          .replaceAll('```json\n', '')
          .replaceAll('```', '')
          .trim();
      final Map<String, dynamic> decodedResponse = json.decode(cleanedResponse);
      _mcqQuestions = decodedResponse['questions'] ?? [];
      for (int i = 0; i < _mcqQuestions.length; i++) {
        _userAnswers[i] = null;
      }
    } catch (e) {
      // Silently handle the error
    }
  }

  Future<void> _submitTest() async {
    _mcqResults.clear();
    int correctCount = 0;
    List<Map<String, dynamic>> questionsAndAnswers = [];

    for (int i = 0; i < _mcqQuestions.length; i++) {
      final question = _mcqQuestions[i];
      final selectedOption = _userAnswers[i];
      final correctAnswer = question['correct_answer'];
      final isCorrect = selectedOption == correctAnswer;

      if (isCorrect) {
        correctCount++;
      }

      _mcqResults.add({
        'question': question['question'],
        'selected_option': selectedOption,
        'correct_answer': correctAnswer,
        'is_correct': isCorrect,
        'options': question['options'],
      });

      questionsAndAnswers.add({
        'question': question['question'],
        'correctAnswer': correctAnswer,
        'userAnswer': selectedOption,
        'isCorrect': isCorrect,
        'options': question['options'], // Add MCQ options here
      });
    }

    final testResult = TestResult(
      testId: DateTime.now().millisecondsSinceEpoch.toString(),
      testType: 'MCQ Test',
      timestamp: DateTime.now(),
      score: correctCount,
      totalQuestions: _mcqQuestions.length,
      timeTakenInSeconds: (widget.testTimeInMinutes * 60) - _remainingSeconds,
      language: widget.language,
      questionsAndAnswers: questionsAndAnswers,
      imagePaths: widget.selectedImages?.map((e) => e.path).toList() ?? [],
    );

    TestResultService.saveTestResult(testResult);

    // If this test was loaded from a saved test, delete it after completion
    if (widget.savedTestId != null) {
      await SavedTestService.deleteTest(widget.savedTestId!);
    }

    setState(() {
      _testSubmitted = true;
    });
    _resultAnimationController.forward();
  }

  @override
  void dispose() {
    _timer.cancel();
    _timerAnimationController.dispose();
    _resultAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF667EEA),
                const Color(0xFF764BA2),
              ],
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
                            _formatTime(_remainingSeconds),
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
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFFF8FAFC),
              Colors.white,
            ],
          ),
        ),
        child: _testSubmitted ? _buildResultsView() : Column(
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
                  _buildInfoCard(
                    'Questions',
                    '${_mcqQuestions.length}',
                    Icons.quiz_outlined,
                    const Color(0xFF667EEA),
                  ),
                  _buildInfoCard(
                    'Answered',
                    '${_userAnswers.values.where((v) => v != null).length}',
                    Icons.check_circle_outline,
                    const Color(0xFF10B981),
                  ),
                  _buildInfoCard(
                    'Remaining',
                    '${_userAnswers.values.where((v) => v == null).length}',
                    Icons.pending_outlined,
                    const Color(0xFFF59E0B),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _mcqQuestions.length,
                      itemBuilder: (context, index) {
                        final question = _mcqQuestions[index];
                        final isAnswered = _userAnswers[index] != null;
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
                                        question['question'],
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
                                child: Column(
                                  children: (question['options'] as Map<String, dynamic>)
                                      .entries
                                      .map(
                                        (option) => Container(
                                          margin: const EdgeInsets.symmetric(vertical: 6),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(
                                              color: _userAnswers[index] == option.key
                                                  ? const Color(0xFF667EEA)
                                                  : Colors.grey.withOpacity(0.2),
                                              width: 2,
                                            ),
                                            gradient: _userAnswers[index] == option.key
                                                ? LinearGradient(
                                                    colors: [
                                                      const Color(0xFF667EEA)
                                                          .withOpacity(0.1),
                                                      const Color(0xFF764BA2)
                                                          .withOpacity(0.05),
                                                    ],
                                                  )
                                                : null,
                                          ),
                                          child: RadioListTile<String>(
                                            title: Text(
                                              option.value,
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight:
                                                    _userAnswers[index] == option.key
                                                        ? FontWeight.w600
                                                        : FontWeight.normal,
                                                color: _userAnswers[index] == option.key
                                                    ? const Color(0xFF667EEA)
                                                    : const Color(0xFF374151),
                                              ),
                                            ),
                                            value: option.key,
                                            groupValue: _userAnswers[index],
                                            onChanged: (value) {
                                              setState(() {
                                                _userAnswers[index] = value;
                                              });
                                            },
                                            activeColor: const Color(0xFF667EEA),
                                            contentPadding:
                                                const EdgeInsets.symmetric(horizontal: 8),
                                          ),
                                        ),
                                      )
                                      .toList(),
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
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }



  Widget _buildInfoCard(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                title,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
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
                            child: _buildStatisticCard(total.toString(),
                                'Total', Icons.quiz, const Color(0xFF667EEA))),
                        const SizedBox(width: 12),
                        Expanded(
                            child: _buildStatisticCard(
                                score.toString(),
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
              ..._mcqResults.asMap().entries.map((entry) {
                final index = entry.key;
                final result = entry.value;
                final isCorrect = result['is_correct'];
                final wasAnswered = result['selected_option'] != null;

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
                          : wasAnswered
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
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
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
                              : wasAnswered
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
                                    : wasAnswered
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
                            : wasAnswered
                                ? Icons.close_rounded
                                : Icons.help_outline_rounded,
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
                              result['selected_option'] ?? 'Not Answered',
                              result['options'][result['selected_option']] ??
                                  'Question was skipped',
                              isCorrect
                                  ? const Color(0xFF10B981)
                                  : wasAnswered
                                      ? const Color(0xFFEF4444)
                                      : const Color(0xFFF59E0B),
                              isCorrect
                                  ? Icons.check_circle
                                  : wasAnswered
                                      ? Icons.cancel
                                      : Icons.help_outline,
                            ),
                            if (!isCorrect || !wasAnswered) ...[
                              const SizedBox(height: 12),
                              _buildAnswerCard(
                                'Correct Answer',
                                result['correct_answer'],
                                result['options'][result['correct_answer']],
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatisticCard(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
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
            value,
            style: TextStyle(
              fontSize: 16,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            explanation,
            style: TextStyle(
              fontSize: 14,
              color: color.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
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
