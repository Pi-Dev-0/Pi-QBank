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

/// Deliberately small, page-local palette. Keeping the exam chrome in one
/// palette makes the question runner and result review feel like one product.
class _McqPalette {
  static const navy = Color(0xFF111C3A);
  static const indigo = Color(0xFF4056D6);
  static const indigoDark = Color(0xFF2F3FA8);
  static const ink = Color(0xFF17213D);
  static const muted = Color(0xFF64708A);
  static const canvas = Color(0xFFF5F7FC);
  static const surface = Color(0xFFFFFFFF);
  static const line = Color(0xFFE3E8F3);
  static const selected = Color(0xFFF0F2FF);
  static const teal = Color(0xFF138A83);
  static const tealSoft = Color(0xFFE8F7F5);
  static const amber = Color(0xFFC27A13);
  static const amberSoft = Color(0xFFFFF5E3);
  static const red = Color(0xFFD14343);
}

class MCQTestPage extends StatefulWidget {
  final int numberOfQuestions;
  final int testTimeInMinutes;
  final List<XFile>? selectedImages;
  final String aiResponse;
  final String language;

  /// When true, the runner shows every question in one scrollable paper.
  /// Existing callers keep the paginated runner by default.
  final bool showAllQuestions;
  final String? savedTestId;
  final String? aiTopic;

  const MCQTestPage({
    super.key,
    required this.numberOfQuestions,
    required this.testTimeInMinutes,
    this.selectedImages,
    required this.aiResponse,
    required this.language,
    this.showAllQuestions = false,
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

  /// One key per paper-mode card, so the palette can scroll a question into
  /// view instead of only moving an index nothing is showing.
  final List<GlobalKey> _paperKeys = <GlobalKey>[];

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
      duration: const Duration(milliseconds: 450),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
          parent: _resultAnimationController, curve: Curves.easeOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _resultAnimationController,
      curve: Curves.easeOutCubic,
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
      _paperKeys
        ..clear()
        ..addAll(List.generate(_mcqQuestions.length, (_) => GlobalKey()));
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
                      const Color(0xFFD97706),
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
                backgroundColor: const Color(0xFF2563EB),
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
          backgroundColor: _McqPalette.canvas,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            systemOverlayStyle: SystemUiOverlayStyle.light,
            flexibleSpace: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _McqPalette.navy,
                    _McqPalette.indigoDark,
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
                boxShadow: [
                  BoxShadow(
                    color: _McqPalette.indigo.withOpacity(0.24),
                    blurRadius: 5,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
            ),
            title: _testSubmitted
                ? const Text(
                    'Result',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
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
                            color: _timeIsLow
                                ? const Color(0xFFDC2626)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(25),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.18),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
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
                                    ? Colors.white
                                    : _McqPalette.indigo,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _formatTime(_remainingSeconds),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: _timeIsLow
                                      ? Colors.white
                                      : _McqPalette.ink,
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
                  _McqPalette.canvas,
                  const Color(0xFFFBFCFF),
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

    if (widget.showAllQuestions) return _buildAllQuestionsView();

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

  /// A paper-style runner for cloud tests: every question stays visible, while
  /// the answer state and timer remain shared with the normal runner.
  Widget _buildAllQuestionsView() {
    return Column(
      children: [
        _paperStatusBar(),
        Expanded(
          // A Column rather than a lazy list: the palette needs every card
          // mounted so it can scroll a question that is far off-screen into
          // view. A paper is tens of questions, not thousands.
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
            child: Column(
              children: [
                for (var i = 0; i < _mcqQuestions.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: KeyedSubtree(
                      key: i < _paperKeys.length ? _paperKeys[i] : null,
                      child: _questionView(i, embedded: true),
                    ),
                  ),
              ],
            ),
          ),
        ),
        _allQuestionsNavBar(),
      ],
    );
  }

  /// The live exam read-out: answered, flagged and how far through the paper
  /// the student is. The countdown stays in the app bar above it.
  Widget _paperStatusBar() {
    final total = _mcqQuestions.length;
    final answered = _answeredCount;
    final flagged = _flagged.length;
    final progress = total == 0 ? 0.0 : answered / total;
    final percent = (progress * 100).round();

    return Container(
      decoration: BoxDecoration(
        color: _McqPalette.surface,
        border: const Border(bottom: BorderSide(color: _McqPalette.line)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _paperMetric(
                    icon: Icons.check_circle_rounded,
                    value: '$answered/$total',
                    label: 'answered',
                    color: _McqPalette.teal,
                    background: _McqPalette.tealSoft,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _paperMetric(
                    icon: Icons.bookmark_rounded,
                    value: '$flagged',
                    label: 'flagged',
                    color: flagged == 0 ? _McqPalette.muted : _McqPalette.amber,
                    background: flagged == 0
                        ? _McqPalette.canvas
                        : _McqPalette.amberSoft,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$percent%',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: _McqPalette.indigo,
                ),
              ),
              const SizedBox(width: 3),
              const Text('done',
                  style: TextStyle(fontSize: 10.5, color: Colors.black38)),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: const Color(0xFFDDE3FF),
              valueColor: AlwaysStoppedAnimation<Color>(
                answered == total && total > 0
                    ? _McqPalette.teal
                    : _McqPalette.indigo,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paperMetric({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
    required Color background,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w800, color: color),
            ),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: color.withOpacity(0.75)),
              ),
            ),
          ],
        ),
      );

  Widget _allQuestionsNavBar() {
    final total = _mcqQuestions.length;
    final answered = _answeredCount;
    final flagged = _flagged.length;
    return Container(
      decoration: BoxDecoration(
        color: _McqPalette.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 14,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _paletteButton(),
            const SizedBox(width: 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$answered of $total answered',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    _unansweredCount == 0
                        ? 'All questions answered'
                        : '$_unansweredCount left'
                            '${flagged == 0 ? '' : ' · $flagged flagged'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(fontSize: 10.5, color: Colors.black45),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 44,
              child: ElevatedButton.icon(
                onPressed: _showSubmitConfirmationDialog,
                icon: const Icon(Icons.send_rounded, size: 17),
                label: const Text('Submit',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1D4ED8),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
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
    final changed = target != _currentIndex;
    if (changed) setState(() => _currentIndex = target);

    // Paper mode has no PageView to animate; the card itself has to be scrolled
    // to. The palette is the only caller that can jump far, and all cards stay
    // mounted so the key always has a context.
    if (widget.showAllQuestions) {
      if (target < _paperKeys.length) {
        final targetContext = _paperKeys[target].currentContext;
        if (targetContext != null) {
          Scrollable.ensureVisible(
            targetContext,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            alignment: 0.02,
          );
        }
      }
      return;
    }

    if (!changed) return;
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
      color: _McqPalette.surface,
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
              backgroundColor: const Color(0xFFDDE3FF),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(_McqPalette.indigo),
            ),
          ),
        ],
      ),
    );
  }

  Widget _questionView(int index, {bool embedded = false}) {
    final question = _mcqQuestions[index];
    final options = _optionsOf(index);
    final selected = _userAnswers[index];
    final flagged = _flagged.contains(index);

    final card = Container(
      decoration: BoxDecoration(
        color: _McqPalette.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(color: _McqPalette.line),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _numberBadge(index, answered: selected != null),
              const SizedBox(width: 8),
              _answerStatusPill(index),
              const Spacer(),
              if (embedded)
                IconButton(
                  onPressed: () => _toggleFlag(index),
                  tooltip: flagged ? 'Remove flag' : 'Flag for review',
                  icon: Icon(
                    flagged ? Icons.bookmark : Icons.bookmark_border,
                    size: 19,
                    color: flagged ? const Color(0xFFF59E0B) : Colors.black38,
                  ),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 34, minHeight: 34),
                )
              else
                TextButton.icon(
                  onPressed: () => _toggleFlag(index),
                  icon: Icon(
                    flagged ? Icons.bookmark : Icons.bookmark_border,
                    size: 17,
                    color: flagged ? const Color(0xFFF59E0B) : Colors.black38,
                  ),
                  label: Text(flagged ? 'Flagged' : 'Flag',
                      style: const TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor:
                        flagged ? const Color(0xFFF59E0B) : Colors.black45,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: const Size(0, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            (question['question'] ?? '').toString(),
            style: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
              color: _McqPalette.ink,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          if (options.isEmpty)
            const Text('This question has no options.',
                style: TextStyle(fontSize: 13, color: Colors.black38))
          else
            _optionGrid(index, options),
        ],
      ),
    );

    if (embedded) return card;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: card,
    );
  }

  /// Per-card state, so a student can tell at a glance which questions still
  /// need an answer without opening the palette.
  Widget _answerStatusPill(int index) {
    final answered = _userAnswers[index] != null;
    final color = answered ? const Color(0xFF047857) : const Color(0xFF64748B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: answered ? const Color(0xFFECFDF5) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            answered ? Icons.check_rounded : Icons.radio_button_unchecked,
            size: 11,
            color: color,
          ),
          const SizedBox(width: 3),
          Text(
            answered ? 'Answered' : 'Not answered',
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }

  Widget _numberBadge(int index, {required bool answered}) => Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: answered
                ? [const Color(0xFF2563EB), const Color(0xFF1E40AF)]
                : [const Color(0xFF64748B), const Color(0xFF475569)],
          ),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            '${index + 1}',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ),
      );

  /// Short options read better as a 2 x 2 block: it halves the vertical run of
  /// the paper without shrinking the tap targets. Long options keep the full
  /// width so they do not wrap into a tall, narrow column.
  Widget _optionGrid(int index, Map<String, dynamic> options) {
    final entries = options.entries.toList();
    final selected = _userAnswers[index];
    return LayoutBuilder(
      builder: (context, constraints) {
        final texts = [
          for (final entry in entries) (entry.value ?? '').toString(),
        ];
        if (!_optionsFitTwoColumns(context, texts, constraints.maxWidth)) {
          return Column(
            children: [
              for (final entry in entries)
                _optionTile(
                  index: index,
                  optionKey: entry.key,
                  text: (entry.value ?? '').toString(),
                  selected: selected == entry.key,
                ),
            ],
          );
        }

        const gap = 8.0;
        final cellWidth = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          children: [
            for (final entry in entries)
              SizedBox(
                width: cellWidth,
                child: _optionTile(
                  index: index,
                  optionKey: entry.key,
                  text: (entry.value ?? '').toString(),
                  selected: selected == entry.key,
                  dense: true,
                ),
              ),
          ],
        );
      },
    );
  }

  /// Whether every option fits on one line in a half-width, dense tile.
  ///
  /// The chrome is mirrored from `_optionTile(dense: true)`: 2px border,
  /// 8px side padding, 22px letter, 7px gap and 20px reserved for the tick.
  bool _optionsFitTwoColumns(
      BuildContext context, List<String> texts, double maxWidth) {
    if (texts.length < 2) return false;
    const gap = 8.0;
    final textWidth = (maxWidth - gap) / 2 - 69;
    if (textWidth < 30) return false;

    final textScaler = MediaQuery.textScalerOf(context);
    final textDirection = Directionality.of(context);
    // `Text` inherits the app's typeface (HindSiliguri), so measure with the
    // same inherited style instead of the framework default.
    final measureStyle = DefaultTextStyle.of(context).style.merge(
          const TextStyle(
            fontSize: 14,
            height: 1.3,
            fontWeight: FontWeight.w600,
          ),
        );
    for (final text in texts) {
      if (text.contains('\n')) return false;
      final painter = TextPainter(
        text: TextSpan(text: text, style: measureStyle),
        maxLines: 1,
        textDirection: textDirection,
        textScaler: textScaler,
      )..layout(maxWidth: textWidth);
      if (painter.didExceedMaxLines) return false;
    }
    return true;
  }

  Widget _optionTile({
    required int index,
    required String optionKey,
    required String text,
    required bool selected,
    bool dense = false,
  }) {
    // Options arrive keyed "1".."4"; the familiar letter is shown instead so the
    // paper reads the way a printed one does.
    final number = int.tryParse(optionKey) ?? 1;
    final letter = String.fromCharCode(65 + (number - 1).clamp(0, 25));
    final radius = dense ? 9.0 : 11.0;
    final badgeSize = dense ? 22.0 : 26.0;
    final badgeGap = dense ? 7.0 : 10.0;
    final checkGap = dense ? 4.0 : 6.0;
    final checkSize = dense ? 16.0 : 18.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: InkWell(
        onTap: () => _selectOption(index, optionKey),
        borderRadius: BorderRadius.circular(radius),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(
            horizontal: dense ? 8 : 11,
            vertical: dense ? 9 : 10,
          ),
          decoration: BoxDecoration(
            color: selected ? _McqPalette.selected : _McqPalette.surface,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: selected ? _McqPalette.indigo : _McqPalette.line,
              width: selected ? 2 : 1.4,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: badgeSize,
                height: badgeSize,
                decoration: BoxDecoration(
                  color: selected ? _McqPalette.indigo : _McqPalette.canvas,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    letter,
                    style: TextStyle(
                      fontSize: dense ? 11 : 12,
                      fontWeight: FontWeight.bold,
                      color: selected ? Colors.white : Colors.black54,
                    ),
                  ),
                ),
              ),
              SizedBox(width: badgeGap),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.3,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    color: selected ? _McqPalette.indigoDark : _McqPalette.ink,
                  ),
                ),
              ),
              if (selected) ...[
                SizedBox(width: checkGap),
                Icon(Icons.check_circle,
                    color: _McqPalette.indigo, size: checkSize),
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
        color: _McqPalette.surface,
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
                  foregroundColor: _McqPalette.indigoDark,
                  side: const BorderSide(color: Color(0xFFBFC8F7), width: 1.4),
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
                  backgroundColor: _McqPalette.indigo,
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
            const Icon(Icons.grid_view_rounded, color: Color(0xFF1D4ED8)),
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
                      backgroundColor: const Color(0xFF2563EB),
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
      background = _McqPalette.amberSoft;
      foreground = _McqPalette.amber;
    } else if (answered) {
      background = _McqPalette.tealSoft;
      foreground = _McqPalette.teal;
    } else {
      background = _McqPalette.canvas;
      foreground = _McqPalette.muted;
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
            color: current ? _McqPalette.indigo : Colors.transparent,
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
                child: Icon(Icons.bookmark, size: 10, color: _McqPalette.amber),
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
          _PaletteKey(color: _McqPalette.tealSoft, label: 'Answered'),
          _PaletteKey(color: _McqPalette.amberSoft, label: 'Flagged'),
          _PaletteKey(color: _McqPalette.canvas, label: 'Unanswered'),
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
    final percentageText = '${percentage.toStringAsFixed(1)}%';
    final notAnswered =
        _mcqResults.where((result) => result['selected_option'] == null).length;
    final incorrect = total - score - notAnswered;
    final timeTaken = (widget.testTimeInMinutes * 60) - _remainingSeconds;

    final visibleResults = _mcqResults
        .asMap()
        .entries
        .where((entry) => _matchesFilter(entry.value))
        .toList();

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _resultHero(
                percentage: percentage,
                percentageText: percentageText,
                score: score,
                total: total,
                timeTaken: timeTaken,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _resultStat(total.toString(), 'Total', Icons.quiz_outlined,
                      _McqPalette.indigo),
                  const SizedBox(width: 6),
                  _resultStat(score.toString(), 'Correct',
                      Icons.check_circle_outline, _McqPalette.teal),
                  const SizedBox(width: 6),
                  _resultStat(incorrect.toString(), 'Wrong',
                      Icons.cancel_outlined, _McqPalette.red),
                  const SizedBox(width: 6),
                  _resultStat(notAnswered.toString(), 'Skipped',
                      Icons.remove_circle_outline, _McqPalette.amber),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Text(
                    'Review answers',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${visibleResults.length} shown',
                    style: const TextStyle(fontSize: 11, color: Colors.black45),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Filtering beats scrolling: the point of a review is to find the
              // ones you got wrong, and they are scattered through the list.
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _resultFilterChip(0, 'All', total, _McqPalette.indigo),
                  _resultFilterChip(1, 'Correct', score, _McqPalette.teal),
                  _resultFilterChip(2, 'Wrong', incorrect, _McqPalette.red),
                  _resultFilterChip(
                      3, 'Skipped', notAnswered, _McqPalette.amber),
                ],
              ),
              const SizedBox(height: 10),
              if (_mcqResults.isEmpty)
                _resultEmptyNote('Nothing to review.')
              else if (visibleResults.isEmpty)
                _resultEmptyNote('Nothing in this filter.')
              else
                for (final entry in visibleResults)
                  _resultCard(entry.key, entry.value),
              const SizedBox(height: 20),
              if (_testSubmitted)
                UploadTestButton(
                  questions: _mcqQuestions,
                  testType: 'MCQ',
                  language: widget.language,
                  initialTopic: widget.aiTopic,
                ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _retake,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retake this paper'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  foregroundColor: _McqPalette.indigoDark,
                  side: const BorderSide(color: Color(0xFFBFC8F7), width: 1.4),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13)),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  gradient: const LinearGradient(
                    colors: [_McqPalette.indigo, _McqPalette.indigoDark],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _McqPalette.indigo.withOpacity(0.28),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
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
                  icon: const Icon(Icons.home_rounded,
                      color: Colors.white, size: 19),
                  label: const Text(
                    'Back to Home',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Score first, then the one line of context that matters: grade, correct
  /// count and how long the sitting took.
  Widget _resultHero({
    required double percentage,
    required String percentageText,
    required int score,
    required int total,
    required int timeTaken,
  }) {
    final color = _getScoreColor(percentage);
    final grade = _getGradeText(percentage);
    final detail = '${_formatTime(timeTaken)} taken';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 86,
            height: 86,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 86,
                  height: 86,
                  child: CircularProgressIndicator(
                    value: total == 0 ? 0 : score / total,
                    strokeWidth: 7,
                    strokeCap: StrokeCap.round,
                    backgroundColor: color.withOpacity(0.12),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          percentageText,
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: color,
                          ),
                        ),
                      ),
                      const Text(
                        'score',
                        style: TextStyle(fontSize: 9.5, color: Colors.black45),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        grade,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        _resultMessage(percentage),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '$score of $total correct',
                  style:
                      const TextStyle(fontSize: 12.5, color: Color(0xFF374151)),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5, color: Colors.black45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _resultMessage(double percentage) {
    if (percentage >= 90) return 'Excellent work';
    if (percentage >= 70) return 'Well done';
    if (percentage >= 50) return 'Good effort';
    if (percentage >= 40) return 'Keep going';
    return 'Needs more practice';
  }

  Widget _resultStat(String value, String label, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: color.withOpacity(0.18)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 12, color: color),
                const SizedBox(width: 3),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 1),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: Colors.black45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultEmptyNote(String message) => Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Text(
          message,
          style: const TextStyle(fontSize: 12, color: Colors.black45),
        ),
      );

  /// A compact review row. The status lives beside the number so a student can
  /// scan the list without expanding every card.
  Widget _resultCard(int index, Map<String, dynamic> result) {
    final isCorrect = result['is_correct'] == true;
    final wasAnswered = result['selected_option'] != null;
    final color = isCorrect
        ? const Color(0xFF10B981)
        : wasAnswered
            ? const Color(0xFFEF4444)
            : const Color(0xFFF59E0B);
    final label = isCorrect
        ? 'Correct'
        : wasAnswered
            ? 'Wrong'
            : 'Skipped';
    final options = result['options'] as Map? ?? const {};
    final selected = result['selected_option']?.toString();
    final correct = result['correct_answer']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: ValueKey('result-$index'),
          tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(13)),
          ),
          collapsedShape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(13)),
          ),
          leading: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCorrect
                  ? Icons.check_rounded
                  : wasAnswered
                      ? Icons.close_rounded
                      : Icons.remove_rounded,
              color: color,
              size: 17,
            ),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Q${index + 1}',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              (result['question'] ?? '').toString(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                height: 1.3,
                color: Color(0xFF374151),
              ),
            ),
          ),
          children: [
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 8),
            // The collapsed row only has room for two lines; expanding keeps
            // the whole question readable.
            Text(
              (result['question'] ?? '').toString(),
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: Color(0xFF374151),
              ),
            ),
            const SizedBox(height: 8),
            _buildAnswerCard(
              'Your answer',
              selected,
              options[selected]?.toString(),
              isCorrect
                  ? const Color(0xFF059669)
                  : wasAnswered
                      ? const Color(0xFFDC2626)
                      : const Color(0xFFB45309),
              isCorrect
                  ? Icons.check_circle_outline
                  : wasAnswered
                      ? Icons.cancel_outlined
                      : Icons.remove_circle_outline,
            ),
            if (!isCorrect) ...[
              const SizedBox(height: 6),
              _buildAnswerCard(
                'Correct answer',
                correct,
                options[correct]?.toString(),
                const Color(0xFF059669),
                Icons.lightbulb_outline,
              ),
            ],
          ],
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.12) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? color : const Color(0xFFE2E8F0),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Text(
          '$label · $count',
          style: TextStyle(
            fontSize: 11.5,
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

  Widget _buildAnswerCard(
    String title,
    String? optionKey,
    String? optionText,
    Color color,
    IconData icon,
  ) {
    final answer = optionText == null || optionText.isEmpty
        ? (optionKey ?? 'Not answered')
        : '${optionKey == null ? '' : '$optionKey. '}$optionText';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: color,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  answer,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.3,
                    color: Color(0xFF374151),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getScoreColor(double percentage) {
    if (percentage >= 80) return _McqPalette.teal;
    if (percentage >= 60) return _McqPalette.indigo;
    if (percentage >= 40) return _McqPalette.amber;
    return _McqPalette.red;
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
