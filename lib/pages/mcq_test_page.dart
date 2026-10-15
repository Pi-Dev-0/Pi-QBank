import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:async';
import 'package:pi_qbank/pages/tools_page.dart';
import 'package:pi_qbank/models/test_result.dart'; // Import TestResult
import 'package:pi_qbank/services/test_result_service.dart'; // Import TestResultService
import 'package:pi_qbank/services/saved_test_service.dart'; // Import SavedTestService
import 'package:pi_qbank/widgets/upload_test_button.dart';

class MCQTestPage extends StatefulWidget {
  final int numberOfQuestions;
  final int testTimeInMinutes;
  final List<XFile>? selectedImages;
  final String aiResponse;
  final String language;
  final String? savedTestId;
  final String? aiTopic;

  const MCQTestPage({
    super.key,
    required this.numberOfQuestions,
    required this.testTimeInMinutes,
    this.selectedImages,
    required this.aiResponse,
    required this.language,
    this.savedTestId,
    this.aiTopic,
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

  // ── navigation ───────────────────────────────────────────────────────────
  //
  // One question on screen, as every well-known runner does. A single scroll of
  // forty questions tells the student nothing about how far they are, and it
  // leaves nowhere for "come back to this one" to live.
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  /// Questions marked to revisit. Deliberately separate from unanswered: a
  /// student can be confident of an answer and still want a second look, and
  /// collapsing the two loses that intent.
  final Set<int> _flagged = <int>{};

  /// Which slice of the review list the results page is showing:
  /// 0 all, 1 correct, 2 wrong, 3 skipped.
  int _resultFilter = 0;

  static const List<LogicalKeyboardKey> _digitKeys = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];

  static const List<LogicalKeyboardKey> _letterKeys = [
    LogicalKeyboardKey.keyA,
    LogicalKeyboardKey.keyB,
    LogicalKeyboardKey.keyC,
    LogicalKeyboardKey.keyD,
  ];
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
    // Nothing else stops the clock. Without this, a manual submit leaves the
    // periodic timer running, and it fires again at zero to file a second
    // result for the same sitting.
    _timer.cancel();
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

  Future<void> _showSubmitConfirmationDialog() async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Confirm Submission',
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Please review your progress before submitting.'),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _buildInfoCardDialog(
                      'Answered',
                      '$_answeredCount',
                      Icons.check_circle_outline,
                      const Color(0xFF10B981),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildInfoCardDialog(
                      'Unanswered',
                      '$_unansweredCount',
                      Icons.pending_outlined,
                      const Color(0xFFF59E0B),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildInfoCardDialog(
                      'Flagged',
                      '${_flagged.length}',
                      Icons.bookmark_outline,
                      const Color(0xFF8B5CF6),
                    ),
                  ),
                ],
              ),
              if (_unansweredCount > 0) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFED7AA)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          size: 18, color: Color(0xFFEA580C)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$_unansweredCount question'
                          '${_unansweredCount == 1 ? '' : 's'} '
                          'still unanswered. They will count as wrong.',
                          style: const TextStyle(
                              fontSize: 12.5, color: Color(0xFF9A3412)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 120, 145, 255),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Submit Now',
                  style: TextStyle(color: Colors.white)),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _submitTest();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    _pageController.dispose();
    _timerAnimationController.dispose();
    _resultAnimationController.dispose();
    super.dispose();
  }

  Future<bool?> _showExitConfirmationDialog() async {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text('Exit Exam?',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
            'Are you sure you want to exit? Your current progress will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Exit Exam'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
        canPop: _testSubmitted,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          final shouldPop = await _showExitConfirmationDialog();
          if (shouldPop == true) {
            if (context.mounted) Navigator.of(context).pop();
          }
        },
        child: Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            flexibleSpace: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.fromARGB(255, 115, 140, 230),
                    Color.fromARGB(255, 155, 100, 210),
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF667EEA).withOpacity(0.2),
                    blurRadius: 5,
                    offset: const Offset(0, 5),
                  ),
                ],
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
                      final progress =
                          _remainingSeconds / (widget.testTimeInMinutes * 60);
                      return Transform.scale(
                        scale: _timeIsLow
                            ? 1.0 + (_timerAnimationController.value * 0.1)
                            : 1.0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(25),
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              stops: [progress, progress],
                              colors: [
                                _timeIsLow
                                    ? Colors.red.shade400
                                    : Colors.white
                                        .withOpacity(0.8), // Progress color
                                Colors.white.withOpacity(
                                    0.3), // Changed from Colors.black.withOpacity(0.1) // Background color
                              ],
                            ),
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
                                    : const Color.fromARGB(255, 90, 0, 150),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _formatTime(_remainingSeconds),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: _timeIsLow
                                      ? Colors.white
                                      : const Color.fromARGB(255, 90, 0, 150),
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
              onPressed: () async {
                if (_testSubmitted) {
                  Navigator.of(context).pop();
                } else {
                  final shouldPop = await _showExitConfirmationDialog();
                  if (shouldPop == true) {
                    if (context.mounted) Navigator.of(context).pop();
                  }
                }
              },
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
            child: _testSubmitted ? _buildResultsView() : _buildExamView(),
          ),
        ));
  }

  // ── exam view ────────────────────────────────────────────────────────────

  /// One question at a time, with a palette, flagging and a progress read-out.
  Widget _buildExamView() {
    if (_mcqQuestions.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'This test has no questions.',
            style: TextStyle(fontSize: 15, color: Colors.black54),
          ),
        ),
      );
    }

    return CallbackShortcuts(
      bindings: _shortcuts,
      child: Focus(
        autofocus: true,
        child: Column(
          children: [
            _examStatusBar(),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _currentIndex = i),
                itemCount: _mcqQuestions.length,
                itemBuilder: (_, i) => _questionView(i),
              ),
            ),
            _examNavBar(),
          ],
        ),
      ),
    );
  }

  int get _answeredCount => _userAnswers.values.where((v) => v != null).length;

  int get _unansweredCount => _mcqQuestions.length - _answeredCount;

  /// Desktop shortcuts: digits or A-D to answer, arrows to move, F to flag.
  Map<ShortcutActivator, VoidCallback> get _shortcuts {
    final map = <ShortcutActivator, VoidCallback>{};
    final options = _optionCount(_currentIndex);
    for (var i = 0; i < options && i < _digitKeys.length; i++) {
      final n = i;
      map[SingleActivator(_digitKeys[i])] = () => _chooseByIndex(n);
    }
    for (var i = 0; i < options && i < _letterKeys.length; i++) {
      final n = i;
      map[SingleActivator(_letterKeys[i])] = () => _chooseByIndex(n);
    }
    map[const SingleActivator(LogicalKeyboardKey.arrowRight)] =
        () => _goTo(_currentIndex + 1);
    map[const SingleActivator(LogicalKeyboardKey.arrowLeft)] =
        () => _goTo(_currentIndex - 1);
    map[const SingleActivator(LogicalKeyboardKey.keyF)] = _toggleFlagCurrent;
    return map;
  }

  int _optionCount(int index) {
    if (index < 0 || index >= _mcqQuestions.length) return 0;
    final options = _mcqQuestions[index]['options'];
    return options is Map ? options.length : 0;
  }

  /// Options as a string-keyed map.
  ///
  /// Comes back as `Map<String, dynamic>` from the cloud page but as a plain
  /// decoded `Map` when replayed from a saved test, so neither shape can be
  /// assumed.
  Map<String, dynamic> _optionsOf(int index) {
    final options = _mcqQuestions[index]['options'];
    return options is Map
        ? options.cast<String, dynamic>()
        : <String, dynamic>{};
  }

  void _goTo(int index) {
    if (_mcqQuestions.isEmpty) return;
    final target = index.clamp(0, _mcqQuestions.length - 1);
    if (target == _currentIndex) return;
    setState(() => _currentIndex = target);
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _selectOption(int index, String key) => setState(() {
        // Tapping the chosen option again clears it, so a mis-tap is one tap to
        // undo rather than a wrong answer filed silently.
        _userAnswers[index] = _userAnswers[index] == key ? null : key;
      });

  void _chooseByIndex(int n) {
    final keys = _optionsOf(_currentIndex).keys.toList();
    if (n < 0 || n >= keys.length) return;
    setState(() => _userAnswers[_currentIndex] = keys[n]);
  }

  void _toggleFlagCurrent() => _toggleFlag(_currentIndex);

  void _toggleFlag(int index) => setState(() {
        if (!_flagged.remove(index)) _flagged.add(index);
      });

  // ── exam chrome ──────────────────────────────────────────────────────────

  Widget _examStatusBar() {
    final total = _mcqQuestions.length;
    final progress = total == 0 ? 0.0 : _answeredCount / total;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Column(
        children: [
          Row(
            children: [
              Text('Question ${_currentIndex + 1} of $total',
                  style: const TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w800)),
              const Spacer(),
              Text('$_answeredCount answered',
                  style:
                      const TextStyle(fontSize: 12.5, color: Colors.black45)),
            ],
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: const Color(0xFFEDE9FE),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Color(0xFF667EEA)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _questionView(int index) {
    final question = _mcqQuestions[index];
    final options = _optionsOf(index);
    final selected = _userAnswers[index];
    final flagged = _flagged.contains(index);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
          border: Border.all(color: const Color(0xFFEDE9FE)),
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _numberBadge(index, answered: selected != null),
                const SizedBox(width: 12),
                const Text('Question',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.black45)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _toggleFlag(index),
                  icon: Icon(
                    flagged ? Icons.bookmark : Icons.bookmark_border,
                    size: 18,
                    color: flagged ? const Color(0xFFF59E0B) : Colors.black38,
                  ),
                  label: Text(flagged ? 'Flagged' : 'Flag',
                      style: const TextStyle(fontSize: 12.5)),
                  style: TextButton.styleFrom(
                    foregroundColor:
                        flagged ? const Color(0xFFF59E0B) : Colors.black45,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              (question['question'] ?? '').toString(),
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1F2937),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            if (options.isEmpty)
              const Text('This question has no options.',
                  style: TextStyle(fontSize: 13, color: Colors.black38))
            else
              for (final entry in options.entries)
                _optionTile(
                  index: index,
                  optionKey: entry.key,
                  text: (entry.value ?? '').toString(),
                  selected: selected == entry.key,
                ),
          ],
        ),
      ),
    );
  }

  Widget _numberBadge(int index, {required bool answered}) => Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: answered
                ? [const Color(0xFF667EEA), const Color(0xFF764BA2)]
                : [Colors.grey.shade300, Colors.grey.shade400],
          ),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            '${index + 1}',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
      );

  Widget _optionTile({
    required int index,
    required String optionKey,
    required String text,
    required bool selected,
  }) {
    // Options arrive keyed "1".."4"; the familiar letter is shown instead so the
    // paper reads the way a printed one does.
    final number = int.tryParse(optionKey) ?? 1;
    final letter = String.fromCharCode(65 + (number - 1).clamp(0, 25));

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => _selectOption(index, optionKey),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF667EEA).withOpacity(0.08)
                : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color:
                  selected ? const Color(0xFF667EEA) : const Color(0xFFE5E7EB),
              width: selected ? 2 : 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFF667EEA)
                      : const Color(0xFFF1F2F9),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    letter,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: selected ? Colors.white : Colors.black54,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.35,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    color: selected
                        ? const Color(0xFF4F46E5)
                        : const Color(0xFF374151),
                  ),
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                const Icon(Icons.check_circle,
                    color: Color(0xFF667EEA), size: 20),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _examNavBar() {
    final total = _mcqQuestions.length;
    final last = _currentIndex >= total - 1;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 14,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _paletteButton(),
            const SizedBox(width: 4),
            Expanded(
              child: OutlinedButton.icon(
                onPressed:
                    _currentIndex == 0 ? null : () => _goTo(_currentIndex - 1),
                icon: const Icon(Icons.chevron_left, size: 20),
                label: const Text('Previous'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: last
                    ? _showSubmitConfirmationDialog
                    : () => _goTo(_currentIndex + 1),
                icon: Icon(last ? Icons.send_rounded : Icons.chevron_right,
                    size: 20),
                label: Text(last ? 'Submit' : 'Next'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF667EEA),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _paletteButton() => IconButton(
        onPressed: _openPalette,
        tooltip: 'Question palette',
        icon: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.grid_view_rounded, color: Color(0xFF4F46E5)),
            if (_unansweredCount > 0)
              Positioned(
                right: -6,
                top: -4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$_unansweredCount',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        ),
      );

  // ── question palette ─────────────────────────────────────────────────────

  void _openPalette() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        // The sheet stays open while jumping, so it has to repaint itself; the
        // page behind repaints from the page's own setState.
        builder: (sheetContext, setSheetState) =>
            _paletteSheet(() => setSheetState(() {})),
      ),
    );
  }

  Widget _paletteSheet(VoidCallback refresh) {
    final total = _mcqQuestions.length;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Question palette',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              '$_answeredCount answered · $_unansweredCount left'
              '${_flagged.isEmpty ? '' : ' · ${_flagged.length} flagged'}',
              style: const TextStyle(fontSize: 12.5, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (var i = 0; i < total; i++) _paletteCell(i, refresh),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            _paletteLegend(),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13)),
                    ),
                    child: const Text('Keep going'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _showSubmitConfirmationDialog();
                    },
                    icon: const Icon(Icons.send_rounded, size: 18),
                    label: const Text('Submit'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF667EEA),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _paletteCell(int index, VoidCallback refresh) {
    final answered = _userAnswers[index] != null;
    final flagged = _flagged.contains(index);
    final current = index == _currentIndex;

    final Color background;
    final Color foreground;
    if (flagged) {
      background = const Color(0xFFFEF3C7);
      foreground = const Color(0xFFB45309);
    } else if (answered) {
      background = const Color(0xFFD1FAE5);
      foreground = const Color(0xFF047857);
    } else {
      background = const Color(0xFFF1F2F9);
      foreground = Colors.black54;
    }

    return GestureDetector(
      onTap: () {
        _goTo(index);
        refresh();
      },
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: current ? const Color(0xFF4F46E5) : Colors.transparent,
            width: 2,
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Text(
                '${index + 1}',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: foreground),
              ),
            ),
            if (flagged)
              const Positioned(
                top: 4,
                right: 4,
                child: Icon(Icons.bookmark, size: 10, color: Color(0xFFB45309)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _paletteLegend() => const Wrap(
        spacing: 16,
        runSpacing: 8,
        children: [
          _PaletteKey(color: Color(0xFFD1FAE5), label: 'Answered'),
          _PaletteKey(color: Color(0xFFFEF3C7), label: 'Flagged'),
          _PaletteKey(color: Color(0xFFF1F2F9), label: 'Unanswered'),
        ],
      );

  Widget _buildInfoCardDialog(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
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
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsView() {
    final score = _mcqResults.where((result) => result['is_correct']).length;
    final total = _mcqResults.length;
    // A test submitted before it was parsed would otherwise divide by zero and
    // print "NaN%".
    final percentage = total == 0 ? 0.0 : score / total * 100;
    final percentageText = percentage.toStringAsFixed(1);
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
                            _getScoreColor(percentage),
                            _getScoreColor(percentage).withOpacity(0.7),
                          ],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _getScoreColor(percentage).withOpacity(0.4),
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
                              '$percentageText%',
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              _getGradeText(percentage),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '📊 Detailed Analysis',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Filtering beats scrolling: the point of a review is to
                    // find the ones you got wrong, and they are scattered
                    // through the list.
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _resultFilterChip(
                            0, 'All', total, const Color(0xFF667EEA)),
                        _resultFilterChip(
                            1, 'Correct', score, const Color(0xFF10B981)),
                        _resultFilterChip(
                            2, 'Wrong', incorrect, const Color(0xFFEF4444)),
                        _resultFilterChip(
                            3, 'Skipped', notAnswered, const Color(0xFFF59E0B)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (_mcqResults.isEmpty || !_mcqResults.any(_matchesFilter))
                Container(
                  padding: const EdgeInsets.all(24),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text('Nothing in this filter.',
                      style: TextStyle(fontSize: 13, color: Colors.black45)),
                ),
              ..._mcqResults
                  .asMap()
                  .entries
                  .where((e) => _matchesFilter(e.value))
                  .map((entry) {
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
              if (_testSubmitted)
                UploadTestButton(
                  questions: _mcqQuestions,
                  testType: 'MCQ',
                  language: widget.language,
                  initialTopic: widget.aiTopic,
                ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _retake,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retake this paper'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  foregroundColor: const Color(0xFF4F46E5),
                  side: const BorderSide(color: Color(0xFFC7D2FE), width: 1.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15)),
                ),
              ),
              const SizedBox(height: 12),
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

  /// Which review cards the results page is showing.
  bool _matchesFilter(Map<String, dynamic> result) {
    final correct = result['is_correct'] == true;
    final skipped = result['selected_option'] == null;
    switch (_resultFilter) {
      case 1:
        return correct;
      case 2:
        return !correct && !skipped;
      case 3:
        return skipped;
      default:
        return true;
    }
  }

  Widget _resultFilterChip(int value, String label, int count, Color color) {
    final selected = _resultFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _resultFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.12) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : const Color(0xFFE5E7EB),
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Text(
          '$label · $count',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: selected ? color : Colors.black54,
          ),
        ),
      ),
    );
  }

  /// Clear the answers and run the same paper again.
  void _retake() {
    setState(() {
      _testSubmitted = false;
      _mcqResults.clear();
      for (var i = 0; i < _mcqQuestions.length; i++) {
        _userAnswers[i] = null;
      }
      _flagged.clear();
      _resultFilter = 0;
      _currentIndex = 0;
      _timeIsLow = false;
    });
    _timerAnimationController.stop();
    _timerAnimationController.reset();
    if (_pageController.hasClients) _pageController.jumpToPage(0);
    _initializeTimer();
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

/// One swatch in the palette legend.
class _PaletteKey extends StatelessWidget {
  const _PaletteKey({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 13,
            height: 13,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.black12),
            ),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
        ],
      );
}
