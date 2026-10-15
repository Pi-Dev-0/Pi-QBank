import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:pi_qbank/models/highschool_question.dart';
import 'package:pi_qbank/pages/mcq_test_page.dart';
import 'package:pi_qbank/services/highschool_qbank_service.dart';
import 'package:pi_qbank/widgets/custom_app_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Online exams built from the High School question bank.
///
/// The bank is the same Google Sheet the paper generator draws from, read
/// through `HighSchoolQBankService`, so a question written once is available
/// both as a printed paper and as an online exam — no second copy to maintain.
///
/// MCQ only. The bank also holds CQ and SQ, but those are written answers:
/// nothing can mark them from what a student types, so offering them here would
/// produce an exam whose score is fiction. Printing them as a paper is a
/// different job, and the paper generator already does it.
class CloudTestsPage extends StatefulWidget {
  const CloudTestsPage({super.key});

  /// Same deployment the web uploader posts to.
  static const String scriptUrl =
      'https://script.google.com/macros/s/AKfycbztYwdYoZyBXrKcvee-GLDQZJhSRlP8kHHjjDCkwTvtWVMdmXxDSJzgE9kIQI28EhDU/exec';

  /// Turn a bank row into the shape `MCQTestPage` reads.
  ///
  /// Two things are not obvious and both fail loudly:
  ///
  ///  * `options` is a **Map**, not a list. The runner iterates it as
  ///    `question['options'].entries` and renders a `RadioListTile` whose
  ///    `value` is `option.key`. Handing it a list throws
  ///    `List<dynamic> is not a subtype of Map<String, dynamic>` the moment the
  ///    first question is built.
  ///  * The student's answer is that **key**, so `correct_answer` has to be a
  ///    key too. The sheet stores the correct option as its *text*, so it is
  ///    translated to the matching key here. Sending the text would mark
  ///    nothing correct and every score would come out zero — no crash, just a
  ///    silently wrong result.
  ///
  /// Exposed for tests: this is the contract between the two pages and nothing
  /// else exercises it.
  ///
  /// [shuffleOptions] reorders the answer choices while keeping
  /// `correct_answer` pointing at the right one. Without it, question 3's
  /// answer is always option 2 and the paper can be passed by pattern rather
  /// than by knowing the subject.
  static Map<String, dynamic> mcqPayload(
    HighSchoolQuestion q, {
    bool shuffleOptions = false,
    Random? random,
  }) {
    final data = q.mcqData;
    final texts = data?.options ?? const <String>[];

    // The order the options are laid out in, as indices into `texts`.
    final order = List<int>.generate(texts.length, (i) => i);
    if (shuffleOptions && order.isNotEmpty) {
      order.shuffle(random ?? Random());
    }

    final options = <String, dynamic>{};
    for (var slot = 0; slot < order.length; slot++) {
      options['${slot + 1}'] = texts[order[slot]];
    }

    // The key is the slot, not the original index, so it is looked up through
    // the same order that laid the options out.
    var correctKey = '';
    final wanted = (data?.correctAns ?? '').trim();
    for (var slot = 0; slot < order.length; slot++) {
      if (texts[order[slot]].trim() == wanted) {
        correctKey = '${slot + 1}';
        break;
      }
    }

    return {
      'question': (data?.text ?? '').trim(),
      'options': options,
      'correct_answer': correctKey,
    };
  }

  @override
  State<CloudTestsPage> createState() => _CloudTestsPageState();
}

/// How the paper is put together.
enum _PickMode { random, manual }

class _CloudTestsPageState extends State<CloudTestsPage> {
  static const List<String> _classes = [
    'Class 6',
    'Class 7',
    'Class 8',
    'Class (9-10) SSC',
    'Class (11-12) HSC',
  ];

  late final HighSchoolQBankService _service =
      const HighSchoolQBankService(scriptUrl: CloudTestsPage.scriptUrl);

  // ── remembered setup ─────────────────────────────────────────────────────
  //
  // A teacher setting a weekly test picks the same class, subject and chapters
  // every time. Re-picking them from four dropdowns before each paper is pure
  // friction, so the last paper's setup is restored on open.
  static const String _prefsClass = 'cloudExam.class';
  static const String _prefsSubject = 'cloudExam.subject';
  static const String _prefsChapters = 'cloudExam.chapters';
  static const String _prefsMode = 'cloudExam.mode';
  static const String _prefsCount = 'cloudExam.count';
  static const String _prefsShuffle = 'cloudExam.shuffle';
  static const String _prefsShuffleOptions = 'cloudExam.shuffleOptions';
  static const String _prefsMinutes = 'cloudExam.minutes';

  static const List<String> _prefsKeys = [
    _prefsClass,
    _prefsSubject,
    _prefsChapters,
    _prefsMode,
    _prefsCount,
    _prefsShuffle,
    _prefsShuffleOptions,
    _prefsMinutes,
  ];

  @override
  void initState() {
    super.initState();
    _restoreSettings();
  }

  // ── selection ────────────────────────────────────────────────────────────
  String? _className;
  String? _subject;
  final Set<String> _chapters = {};

  // ── loading ──────────────────────────────────────────────────────────────
  bool _loadingChapters = false;
  bool _loadingQuestions = false;
  String? _error;
  List<ChapterInfo> _chapterList = const [];
  List<HighSchoolQuestion> _questions = const [];

  // ── exam plan ────────────────────────────────────────────────────────────
  //
  // MCQ only. The bank also holds CQ and SQ, but those are written answers:
  // they cannot be marked from what the student types, so an online exam built
  // from them could only collect text for a human to mark afterwards. That is
  // a different tool, and leaving it on this screen only produced two counters
  // a student could fill and then not be able to sit.
  int _mcqCount = 10;
  bool _shuffle = true;

  /// Reorder the four choices under each question.
  ///
  /// Off by default so a question printed as "উত্তর: খ" reads the same on
  /// screen; on, it stops a student from answering by position.
  bool _shuffleOptions = false;

  /// How the paper is put together.
  ///
  /// [random] draws N at random, which is the usual case for practice. [manual]
  /// takes exactly the questions that were ticked, so a teacher can sit a class
  /// down on a specific set — the ones from last year's paper, say, or a weak
  /// chapter on its own.
  _PickMode _pickMode = _PickMode.random;

  /// Ids ticked in manual mode.
  ///
  /// Kept here rather than inside the picker sheet so the count, the marks and
  /// the preview stay live while the sheet is open.
  final Set<String> _pickedIds = <String>{};

  /// Minutes to allow, or null for the derived default.
  ///
  /// Derived from the question count, which suits MCQ but not every paper: a
  /// student who needs longer, or a teacher who wants a hard limit, sets it
  /// here rather than having the app guess.
  int? _customMinutes;

  /// Bring back the last paper that was actually started.
  ///
  /// Silently does nothing when there is nothing remembered, or when the store
  /// is unavailable — on a fresh install there is simply no paper to restore,
  /// and that is not an error worth showing.
  Future<void> _restoreSettings() async {
    SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      return;
    }

    final className = prefs.getString(_prefsClass);
    final subject = prefs.getString(_prefsSubject);
    if (className == null || !_classes.contains(className)) return;
    if (subject == null || subject.isEmpty) return;
    if (!mounted) return;

    setState(() {
      _className = className;
      _subject = subject;
      _mcqCount = prefs.getInt(_prefsCount) ?? _mcqCount;
      _shuffle = prefs.getBool(_prefsShuffle) ?? _shuffle;
      _shuffleOptions = prefs.getBool(_prefsShuffleOptions) ?? _shuffleOptions;
      _customMinutes = prefs.getInt(_prefsMinutes);
      _pickMode = prefs.getString(_prefsMode) == 'manual'
          ? _PickMode.manual
          : _PickMode.random;
    });

    // Chapters and questions only exist once the bank answers, so the
    // remembered paper can be reassembled no earlier than that.
    await _loadChapters();
    final savedChapters = prefs.getStringList(_prefsChapters) ?? const [];
    if (!mounted) return;
    setState(() {
      _chapters
        ..clear()
        ..addAll(savedChapters
            .where((c) => _chapterList.any((info) => info.chapterNumber == c)));
    });
    await _loadQuestions();
  }

  /// Remember the setup of a paper the user actually started.
  ///
  /// Saving on start rather than on every tap means "last used" means the last
  /// paper given, not the last dropdown touched.
  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsClass, _className ?? '');
      await prefs.setString(_prefsSubject, _subject ?? '');
      await prefs.setStringList(_prefsChapters, _chapters.toList());
      await prefs.setString(
          _prefsMode, _pickMode == _PickMode.manual ? 'manual' : 'random');
      await prefs.setInt(_prefsCount, _mcqCount);
      await prefs.setBool(_prefsShuffle, _shuffle);
      await prefs.setBool(_prefsShuffleOptions, _shuffleOptions);
      if (_customMinutes == null) {
        await prefs.remove(_prefsMinutes);
      } else {
        await prefs.setInt(_prefsMinutes, _customMinutes!);
      }
    } catch (_) {
      // A paper that fails to be remembered is not worth an error on screen.
    }
  }

  /// Forget the remembered setup and clear the form.
  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Start over?',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
            'This clears the class, subject and chapters, and forgets the '
            'paper remembered for next time.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Start over'),
          ),
        ],
      ),
    );
    if (ok == true) await _reset();
  }

  Future<void> _reset() async {
    setState(() {
      _className = null;
      _subject = null;
      _chapters.clear();
      _chapterList = const [];
      _questions = const [];
      _pickedIds.clear();
      _mcqCount = 10;
      _shuffle = true;
      _shuffleOptions = false;
      _customMinutes = null;
      _pickMode = _PickMode.random;
      _error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      // Only this page's keys: `clear()` would take the saved test results with
      // it.
      for (final key in _prefsKeys) {
        await prefs.remove(key);
      }
    } catch (_) {
      // Nothing to forget.
    }
  }

  Future<void> _loadChapters() async {
    if (_className == null || _subject == null) return;
    setState(() {
      _loadingChapters = true;
      _error = null;
      _chapters.clear();
    });
    try {
      final chapters = await _service.fetchChapters(
          className: _className!, subject: _subject!);
      if (!mounted) return;
      setState(() {
        _chapterList = chapters;
        _loadingChapters = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingChapters = false;
        _error = 'Could not load chapters: $e';
      });
    }
  }

  Future<void> _loadQuestions() async {
    if (_className == null || _subject == null) return;
    setState(() {
      _loadingQuestions = true;
      _error = null;
    });
    try {
      final all = await _service.fetchQuestions(
        className: _className!,
        subject: _subject!,
        chapters: _chapters.isEmpty ? null : _chapters.toList(),
      );
      if (!mounted) return;
      setState(() {
        _questions = all;
        _loadingQuestions = false;
        _clampPlanToAvailable();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingQuestions = false;
        _error = 'Could not load questions: $e';
      });
    }
  }

  List<HighSchoolQuestion> get _mcqs =>
      _questions.where((q) => q.isMcq).toList();

  /// Never ask for more of a type than the bank actually holds.
  ///
  /// Without this the stepper can say "20 CQ" against a chapter with three,
  /// and the exam silently comes up short.
  void _clampPlanToAvailable() {
    _mcqCount = min(_mcqCount, _mcqs.length);
    // A new load can remove questions that were ticked.
    final ids = _mcqs.map((q) => q.id).toSet();
    _pickedIds.removeWhere((id) => !ids.contains(id));
  }

  /// The questions the paper will actually contain, in the order it will run.
  List<HighSchoolQuestion> get _selected {
    if (_pickMode == _PickMode.manual) {
      // Bank order, not the order they were ticked: a list reordered by tapping
      // reads as random, and two students picking the same questions should get
      // the same paper.
      return _mcqs.where((q) => _pickedIds.contains(q.id)).toList();
    }
    if (_mcqCount <= 0 || _mcqs.isEmpty) return const [];
    final list = List<HighSchoolQuestion>.from(_mcqs);
    if (_shuffle) list.shuffle(Random());
    return list.take(_mcqCount).toList();
  }

  int get _plannedCount => _selected.length;

  /// One mark per question: an MCQ is a single right answer.
  int get _plannedMarks => _plannedCount;

  /// Roughly a minute a question, with a floor so a two-question paper still
  /// gives the student time to read it — unless the user set a time.
  int get _plannedMinutes => _customMinutes ?? max(3, _plannedCount);

  /// How much of the subject the paper will draw on.
  String get _chapterScope {
    if (_chapterList.isEmpty) return '';
    if (_chapters.isEmpty) {
      return 'All ${_chapterList.length} '
          'chapter${_chapterList.length == 1 ? '' : 's'}';
    }
    return '${_chapters.length} of ${_chapterList.length} chapters';
  }

  void _startExam() {
    final picked = _selected;
    if (picked.isEmpty) return;

    // Remember the setup of a paper that was actually given.
    _saveSettings();

    _go(
      MCQTestPage(
        numberOfQuestions: picked.length,
        testTimeInMinutes: _plannedMinutes,
        aiResponse: jsonEncode({
          'questions': [
            for (final q in picked)
              CloudTestsPage.mcqPayload(q, shuffleOptions: _shuffleOptions),
          ],
        }),
        language: 'Bangla',
      ),
    );
  }

  /// Show the paper before it is sat.
  ///
  /// The point of building a paper is to check it: that the right chapters came
  /// back, that the questions read properly, that the key matches an option.
  /// Once the exam starts none of that can be fixed.
  void _previewPaper() {
    final picked = _selected;
    if (picked.isEmpty) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (context, controller) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF5F7FA),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4F46E5).withOpacity(0.10),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(Icons.visibility_outlined,
                          color: Color(0xFF4F46E5), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Paper preview',
                              style: TextStyle(
                                  fontSize: 16.5, fontWeight: FontWeight.w800)),
                          Text(
                            '${picked.length} question'
                            '${picked.length == 1 ? '' : 's'} · '
                            '$_plannedMarks marks · $_plannedMinutes min',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black45),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  itemCount: picked.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _previewCard(picked[i], i),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _previewCard(HighSchoolQuestion q, int index) {
    final data = q.mcqData;
    final options = data?.options ?? const <String>[];
    final correct = (data?.correctAns ?? '').trim();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EAF6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('${index + 1}.',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              if (q.chapterName.isNotEmpty)
                Expanded(
                  child: Text(q.chapterName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(fontSize: 11, color: Colors.black38)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text((data?.text ?? '').trim(),
              style: const TextStyle(fontSize: 14, height: 1.4)),
          const SizedBox(height: 10),
          for (var i = 0; i < options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    options[i].trim() == correct
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                    size: 15,
                    color: options[i].trim() == correct
                        ? const Color(0xFF10B981)
                        : Colors.black26,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      options[i],
                      style: TextStyle(
                        fontSize: 13,
                        color: options[i].trim() == correct
                            ? const Color(0xFF047857)
                            : Colors.black54,
                        fontWeight: options[i].trim() == correct
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (correct.isEmpty)
            const Text('No correct option recorded for this question.',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF9A3412))),
        ],
      ),
    );
  }

  void _go(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: CustomAppBar(
        title: 'Online Exam',
        actions: [
          if (_className != null || _subject != null)
            IconButton(
              onPressed: _confirmReset,
              tooltip: 'Start over',
              icon: const Icon(Icons.restart_alt_rounded),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _header(),
            const SizedBox(height: 16),
            _stepCard(
              number: 1,
              title: 'Choose the source',
              child: _sourceSelector(),
            ),
            const SizedBox(height: 12),
            _stepCard(
              number: 2,
              title: 'Build the paper',
              child: _planBuilder(),
            ),
          ],
        ),
      ),
      // A bar rather than a floating button: a FAB sits over the list and gets
      // clipped at the bottom of the viewport, and it vanishes whenever the
      // paper is empty — which hides the one action the page exists for.
      bottomNavigationBar: _bottomBar(),
    );
  }

  bool get _canStart =>
      _plannedCount > 0 && !_loadingQuestions && _error == null;

  // ── header ───────────────────────────────────────────────────────────────
  Widget _header() => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.fact_check_rounded,
                      color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Online Exam',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w800)),
                      SizedBox(height: 2),
                      Text('MCQ, marked automatically',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 12.5)),
                    ],
                  ),
                ),
              ],
            ),
            if (_questions.isNotEmpty) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  _headerStat('${_questions.length}', 'loaded',
                      Icons.inventory_2_outlined),
                  _headerDivider(),
                  _headerStat(
                      '${_mcqs.length}', 'MCQ', Icons.check_circle_outline),
                  _headerDivider(),
                  _headerStat(
                      '${_chapters.length}',
                      _chapters.length == 1 ? 'chapter' : 'chapters',
                      Icons.menu_book_outlined),
                ],
              ),
            ],
          ],
        ),
      );

  Widget _headerStat(String value, String label, IconData icon) => Expanded(
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.white70),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        height: 1.1)),
                Text(label,
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 10.5)),
              ],
            ),
          ],
        ),
      );

  Widget _headerDivider() => Container(
        width: 1,
        height: 26,
        margin: const EdgeInsets.symmetric(horizontal: 10),
        color: Colors.white.withOpacity(0.25),
      );

  /// The persistent action bar.
  ///
  /// Always present, disabled until a paper is buildable, with a one-line
  /// summary of what will start. A button that appears and disappears is harder
  /// to trust than one that says why it is off.
  Widget _bottomBar() {
    final ready = _canStart;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 18,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      ready
                          ? '$_plannedCount question${_plannedCount == 1 ? '' : 's'} ready'
                          : 'Nothing to start yet',
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      ready
                          ? '$_plannedMarks marks · $_plannedMinutes min'
                          : _questions.isEmpty
                              ? 'Load a source above'
                              : 'Select at least one question',
                      style: const TextStyle(
                          fontSize: 11.5, color: Colors.black45),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (ready) ...[
                IconButton.filledTonal(
                  onPressed: _previewPaper,
                  tooltip: 'Preview the paper',
                  icon: const Icon(Icons.visibility_outlined, size: 20),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFEEF2FF),
                    foregroundColor: const Color(0xFF4F46E5),
                    minimumSize: const Size(50, 50),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: ready ? _startExam : null,
                  icon: const Icon(Icons.play_arrow_rounded, size: 24),
                  label: const Text('Start',
                      style: TextStyle(
                          fontSize: 15.5, fontWeight: FontWeight.w800)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFE5E7EB),
                    disabledForegroundColor: Colors.black38,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── step 1 ───────────────────────────────────────────────────────────────
  Widget _stepCard({
    required int number,
    required String title,
    required Widget child,
  }) =>
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE8EAF6)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor: const Color(0xFF4F46E5),
                  child: Text('$number',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 10),
                Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      );

  Widget _sourceSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Class'),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: _className,
          isExpanded: true,
          decoration: _field(),
          items: [
            for (final c in _classes)
              DropdownMenuItem(value: c, child: Text(c)),
          ],
          onChanged: (v) => setState(() {
            _className = v;
            _subject = null;
            _chapterList = const [];
            _chapters.clear();
            _questions = const [];
            _error = null;
          }),
        ),
        const SizedBox(height: 14),
        _label('Subject'),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: _subject,
          isExpanded: true,
          decoration: _field(),
          items: _className == null
              ? const []
              : [
                  for (final s in _subjectsFor(_className!))
                    DropdownMenuItem(value: s, child: Text(s)),
                ],
          onChanged: _className == null
              ? null
              : (v) {
                  setState(() {
                    _subject = v;
                    _chapters.clear();
                    _questions = const [];
                    _error = null;
                  });
                  _loadChapters();
                },
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Chapters'),
                  if (_chapterScope.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    // Says how much of the subject the paper draws on, so an
                    // empty selection does not look like nothing was chosen.
                    Text(_chapterScope,
                        style: TextStyle(
                            fontSize: 11.5, color: Colors.grey.shade600)),
                  ],
                ],
              ),
            ),
            if (_chapterList.isNotEmpty)
              TextButton(
                onPressed: () => setState(() {
                  if (_chapters.length == _chapterList.length) {
                    _chapters.clear();
                  } else {
                    _chapters
                      ..clear()
                      ..addAll(_chapterList.map((c) => c.chapterNumber));
                  }
                }),
                child: Text(_chapters.length == _chapterList.length
                    ? 'Clear'
                    : 'Select all'),
              ),
          ],
        ),
        const SizedBox(height: 2),
        if (_loadingChapters)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: LinearProgressIndicator(),
          )
        else if (_chapterList.isEmpty)
          Text(
            _subject == null
                ? 'Pick a subject to see its chapters.'
                : 'This subject has no chapters yet — all questions will be used.',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in _chapterList)
                FilterChip(
                  selected: _chapters.contains(c.chapterNumber),
                  showCheckmark: false,
                  selectedColor: const Color(0xFF4F46E5).withOpacity(0.12),
                  side: BorderSide(
                    color: _chapters.contains(c.chapterNumber)
                        ? const Color(0xFF4F46E5)
                        : const Color(0xFFE0E0E0),
                  ),
                  label: Text(
                    c.chapterName.isEmpty
                        ? 'অধ্যায় ${c.chapterNumber}'
                        : c.chapterName,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  onSelected: (_) => setState(() =>
                      _chapters.contains(c.chapterNumber)
                          ? _chapters.remove(c.chapterNumber)
                          : _chapters.add(c.chapterNumber)),
                ),
            ],
          ),
        const SizedBox(height: 16),
        if (_error != null) _errorBox(_error!),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed:
                _className == null || _subject == null ? null : _loadQuestions,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text(_loadingQuestions
                ? 'Loading…'
                : _questions.isEmpty
                    ? 'Load questions'
                    : 'Reload questions'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        // The bank returns every question type; this page can only sit MCQs.
        // Saying so here stops "185 loaded" from reading as "185 questions will
        // be asked" — a paper of ten against a bank of 185 looks like a bug
        // otherwise.
        if (_questions.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 15, color: Colors.grey.shade500),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${_questions.length} loaded, of which ${_mcqs.length} '
                  '${_mcqs.length == 1 ? 'is an MCQ' : 'are MCQs'}'
                  '${_questions.length == _mcqs.length ? '.' : ' — the rest are CQ and SQ, which this page cannot mark.'}',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  InputDecoration _field() => InputDecoration(
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFF7F8FC),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      );

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF64748B)),
      );

  Widget _errorBox(String message) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFECACA)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message,
                  style: const TextStyle(
                      color: Color(0xFF991B1B), fontSize: 12.5)),
            ),
          ],
        ),
      );

  /// Subjects per class.
  ///
  /// The bank does not expose a subject list — `getChapters` needs a subject
  /// before it will answer — so this mirrors the paper generator. A subject
  /// with no rows simply comes back empty rather than failing.
  List<String> _subjectsFor(String className) => switch (className) {
        'Class 6' => const ['সাধারণ গণিত', 'বিজ্ঞান', 'বাংলা', 'English'],
        'Class 7' => const ['সাধারণ গণিত', 'বিজ্ঞান', 'বাংলা', 'English'],
        'Class 8' => const ['সাধারণ গণিত', 'বিজ্ঞান', 'বাংলা', 'English'],
        'Class (9-10) SSC' => const [
            'উচ্চতর গণিত',
            'সাধারণ গণিত',
            'পদার্থবিজ্ঞান',
            'রসায়ন',
            'জীববিজ্ঞান',
            'বাংলা',
            'English',
            'হিসাববিজ্ঞান',
            'তথ্য ও যোগাযোগ প্রযুক্তি',
          ],
        _ => const [
            'উচ্চতর গণিত',
            'পদার্থবিজ্ঞান',
            'রসায়ন',
            'জীববিজ্ঞান',
            'বাংলা',
            'English',
            'হিসাববিজ্ঞান',
            'অর্থনীতি',
            'তথ্য ও যোগাযোগ প্রযুক্তি',
          ],
      };

  // ── step 2 ───────────────────────────────────────────────────────────────
  Widget _planBuilder() {
    // The mode switch stays visible even with nothing loaded: it shows the
    // shape of the form straight away, and it is the one control that does not
    // depend on the bank having answered.
    if (_questions.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _modeSwitch(),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F8FC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Load some questions first — the paper is built from what the bank returns.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
            ),
          ),
        ],
      );
    }

    if (_mcqs.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFED7AA)),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_outline, color: Color(0xFFEA580C), size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'No MCQ in this selection. The bank also holds CQ and SQ, which '
                'need writing out, so they are not offered here.',
                style: TextStyle(color: Color(0xFF9A3412), fontSize: 12.5),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        _modeSwitch(),
        const SizedBox(height: 16),
        if (_pickMode == _PickMode.random)
          _randomControls()
        else
          _manualPicker(),
        // Applies to both modes: how the questions were chosen says nothing
        // about whether the choices under each one should be reordered.
        SwitchListTile(
          value: _shuffleOptions,
          onChanged: (v) => setState(() => _shuffleOptions = v),
          contentPadding: EdgeInsets.zero,
          title: const Text('Shuffle answer options',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: Text(
              _shuffleOptions
                  ? 'The four choices come out in a different order each time.'
                  : 'Choices stay in the order the bank lists them.',
              style: const TextStyle(fontSize: 12)),
        ),
        const Divider(height: 30),
        _durationRow(),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFF5F3FF), Color(0xFFEEF2FF)],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE0E7FF)),
          ),
          child: Row(
            children: [
              _stat('$_plannedCount', 'questions'),
              _statDivider(),
              _stat('$_plannedMarks', 'marks'),
              _statDivider(),
              _stat('$_plannedMinutes', 'minutes'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _plannedCount == 0 ? null : _previewPaper,
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: Text(_plannedCount == 0
                ? 'Preview the paper'
                : 'Preview ${_plannedCount == 1 ? 'the question' : 'all $_plannedCount questions'}'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _statDivider() => Container(
        width: 1,
        height: 30,
        color: const Color(0xFFDDD6FE),
      );

  Widget _modeSwitch() => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F2F9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            for (final mode in _PickMode.values)
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _pickMode = mode),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      color:
                          _pickMode == mode ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                      boxShadow: _pickMode == mode
                          ? [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.07),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          mode == _PickMode.random
                              ? Icons.shuffle_rounded
                              : Icons.checklist_rounded,
                          size: 16,
                          color: _pickMode == mode
                              ? const Color(0xFF4F46E5)
                              : Colors.black45,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          mode == _PickMode.random ? 'Random' : 'Pick myself',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: _pickMode == mode
                                ? const Color(0xFF4F46E5)
                                : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _randomControls() => Column(
        children: [
          _countRow('MCQ', 'one mark each', _mcqs.length, _mcqCount,
              (v) => setState(() => _mcqCount = v)),
          SwitchListTile(
            value: _shuffle,
            onChanged: (v) => setState(() => _shuffle = v),
            contentPadding: EdgeInsets.zero,
            title: const Text('Shuffle',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: Text(
                _shuffle
                    ? 'Questions come out in a different order each time.'
                    : 'Off keeps the order the bank returns.',
                style: const TextStyle(fontSize: 12)),
          ),
          // Quick presets beat making someone tap + to reach 30. Only sizes the
          // bank can actually fill are offered, so a preset never silently
          // clamps to something else.
          if (_mcqs.isNotEmpty)
            Row(
              children: [
                for (final n in [5, 10, 20, 0])
                  if (n == 0 || n <= _mcqs.length) ...[
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: GestureDetector(
                          onTap: () => setState(
                              () => _mcqCount = n == 0 ? _mcqs.length : n),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _mcqCount == (n == 0 ? _mcqs.length : n)
                                  ? const Color(0xFF4F46E5).withOpacity(0.10)
                                  : Colors.white,
                              border: Border.all(
                                color: _mcqCount == (n == 0 ? _mcqs.length : n)
                                    ? const Color(0xFF4F46E5)
                                    : const Color(0xFFE0E0E0),
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(n == 0 ? 'All' : '$n',
                                style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color:
                                        _mcqCount == (n == 0 ? _mcqs.length : n)
                                            ? const Color(0xFF4F46E5)
                                            : Colors.black87)),
                          ),
                        ),
                      ),
                    ),
                  ],
              ],
            ),
        ],
      );

  /// Manual mode, reduced to a summary and a way in.
  ///
  /// The list itself lives in a full-height sheet: four chapters of questions
  /// crammed into a 320px box inside the form could not be filtered, scanned or
  /// checked against the key.
  Widget _manualPicker() {
    final picked = _selected;
    final chapters = picked.map((q) => q.chapterNumber).toSet().length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F8FC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE8EAF6)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: const Color(0xFF4F46E5).withOpacity(0.10),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.checklist_rounded,
                    color: Color(0xFF4F46E5), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      picked.isEmpty
                          ? 'No questions picked'
                          : '${picked.length} question'
                              '${picked.length == 1 ? '' : 's'} picked',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      picked.isEmpty
                          ? 'Choose the exact questions this paper should ask.'
                          : 'From $chapters '
                              'chapter${chapters == 1 ? '' : 's'} · '
                              'asked in bank order',
                      style: const TextStyle(
                          fontSize: 11.5, color: Colors.black45),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _mcqs.isEmpty ? null : _openPicker,
            icon: const Icon(Icons.edit_note_rounded, size: 20),
            label: Text(picked.isEmpty ? 'Choose questions' : 'Edit selection'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openPicker() async {
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.93,
        child: QuestionPicker(questions: _mcqs, initial: _pickedIds),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _pickedIds
        ..clear()
        ..addAll(result);
    });
  }

  Widget _durationRow() {
    // Matches the derived default in `_plannedMinutes`, so tapping + starts
    // from the number the student already sees.
    final derived = max(3, _plannedCount);
    final auto = _customMinutes == null;
    return Row(
      children: [
        const Icon(Icons.timer_outlined, size: 18, color: Color(0xFF64748B)),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Time limit',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            Text(auto ? 'auto — one minute a question' : 'set by hand',
                style: const TextStyle(fontSize: 11, color: Colors.black45)),
          ],
        ),
        const Spacer(),
        Text(
            _plannedMinutes < 60
                ? '$_plannedMinutes min'
                : '${_plannedMinutes ~/ 60} h ${_plannedMinutes % 60} min',
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Color(0xFF4F46E5))),
        const SizedBox(width: 4),
        IconButton(
          onPressed: () => setState(
              () => _customMinutes = max(1, (_customMinutes ?? derived) - 5)),
          icon: const Icon(Icons.remove_circle_outline),
          iconSize: 21,
        ),
        IconButton(
          onPressed: () =>
              setState(() => _customMinutes = (_customMinutes ?? derived) + 5),
          icon: const Icon(Icons.add_circle_outline),
          iconSize: 21,
        ),
        if (!auto)
          TextButton(
            onPressed: () => setState(() => _customMinutes = null),
            child: const Text('Auto', style: TextStyle(fontSize: 12)),
          ),
      ],
    );
  }

  Widget _stat(String value, String label) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF4F46E5),
                    height: 1.1)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
          ],
        ),
      );

  Widget _countRow(
    String label,
    String hint,
    int available,
    int value,
    ValueChanged<int> onChanged,
  ) {
    final disabled = available == 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Opacity(
        opacity: disabled ? 0.4 : 1,
        child: Row(
          children: [
            Container(
              width: 42,
              padding: const EdgeInsets.symmetric(vertical: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF4F46E5).withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(label,
                  style: const TextStyle(
                      color: Color(0xFF4F46E5),
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label == 'SQ' ? 'Short answer' : label,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  Text(
                      disabled
                          ? 'none in this selection'
                          : '$hint · $available available',
                      style: const TextStyle(
                          fontSize: 11.5, color: Colors.black45)),
                ],
              ),
            ),
            IconButton(
              onPressed:
                  disabled || value <= 0 ? null : () => onChanged(value - 1),
              icon: const Icon(Icons.remove_circle_outline),
              iconSize: 22,
            ),
            SizedBox(
              width: 34,
              child: Text('$value',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            IconButton(
              onPressed: disabled || value >= available
                  ? null
                  : () => onChanged(value + 1),
              icon: const Icon(Icons.add_circle_outline),
              iconSize: 22,
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-height picker for choosing exactly which questions a paper asks.
///
/// Works on its own copy and hands the result back on close, so cancelling — or
/// swiping the sheet away — leaves the paper exactly as it was.
///
/// Public so a test can drive it with a synthetic bank; the page is the only
/// thing that opens it.
class QuestionPicker extends StatefulWidget {
  const QuestionPicker({
    super.key,
    required this.questions,
    required this.initial,
  });

  final List<HighSchoolQuestion> questions;
  final Set<String> initial;

  @override
  State<QuestionPicker> createState() => _QuestionPickerState();
}

class _QuestionPickerState extends State<QuestionPicker> {
  late final Set<String> _picked = {...widget.initial};
  final Set<String> _expanded = <String>{};

  String _search = '';

  /// Chapter number the list is limited to, or null for all of them.
  String? _chapter;
  bool _pickedOnly = false;

  List<_ChapterBucket> get _buckets {
    final byNumber = <String, _ChapterBucket>{};
    for (final q in widget.questions) {
      final bucket = byNumber.putIfAbsent(
        q.chapterNumber,
        () => _ChapterBucket(q.chapterNumber, q.chapterName),
      );
      bucket.total++;
      if (_picked.contains(q.id)) bucket.picked++;
    }
    return byNumber.values.toList();
  }

  List<HighSchoolQuestion> get _visible {
    final needle = _search.trim().toLowerCase();
    return widget.questions.where((q) {
      if (_pickedOnly && !_picked.contains(q.id)) return false;
      if (_chapter != null && q.chapterNumber != _chapter) return false;
      if (needle.isEmpty) return true;
      return (q.mcqData?.text ?? '').toLowerCase().contains(needle) ||
          q.chapterName.toLowerCase().contains(needle);
    }).toList();
  }

  /// The position each chosen question will take in the paper.
  ///
  /// Bank order, the same order `_selected` produces, so the numbers here are
  /// the numbers the student will actually see.
  Map<String, int> get _paperPositions {
    final positions = <String, int>{};
    var n = 0;
    for (final q in widget.questions) {
      if (_picked.contains(q.id)) positions[q.id] = ++n;
    }
    return positions;
  }

  void _toggle(String id) => setState(() {
        if (!_picked.remove(id)) _picked.add(id);
      });

  void _setShown(bool select) => setState(() {
        for (final q in _visible) {
          if (select) {
            _picked.add(q.id);
          } else {
            _picked.remove(q.id);
          }
        }
      });

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final buckets = _buckets;
    final positions = _paperPositions;
    final allShownPicked =
        visible.isNotEmpty && visible.every((q) => _picked.contains(q.id));

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF5F7FA),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          _header(buckets),
          _controls(buckets, allShownPicked),
          Expanded(
            child: visible.isEmpty
                ? _emptyState()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: visible.length,
                    itemBuilder: (_, i) => _row(visible[i], positions),
                  ),
          ),
          _footer(),
        ],
      ),
    );
  }

  Widget _header(List<_ChapterBucket> buckets) => Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 6, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Pick questions',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    '${widget.questions.length} MCQ'
                    '${buckets.length > 1 ? ' across ${buckets.length} chapters' : ''}',
                    style: const TextStyle(fontSize: 12, color: Colors.black45),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
              tooltip: 'Cancel',
            ),
          ],
        ),
      );

  Widget _controls(List<_ChapterBucket> buckets, bool allShownPicked) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(
          children: [
            TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                hintText: 'Search the question text…',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => _search = ''),
                      ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            if (buckets.length > 1) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 33,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _chapterChip('All', null, widget.questions.length),
                    for (final b in buckets)
                      _chapterChip(
                        b.name.isEmpty ? 'অধ্যায় ${b.number}' : b.name,
                        b.number,
                        b.total,
                        picked: b.picked,
                      ),
                  ],
                ),
              ),
            ],
            Row(
              children: [
                _pickedOnlyToggle(),
                const Spacer(),
                TextButton(
                  onPressed: _visible.isEmpty
                      ? null
                      : () => _setShown(!allShownPicked),
                  child: Text(allShownPicked ? 'Clear shown' : 'Select shown'),
                ),
                if (_picked.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(_picked.clear),
                    child: const Text('Clear all'),
                  ),
              ],
            ),
          ],
        ),
      );

  Widget _chapterChip(String label, String? number, int total,
      {int picked = 0}) {
    final selected = _chapter == number;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _chapter = selected ? null : number),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF4F46E5) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color:
                  selected ? const Color(0xFF4F46E5) : const Color(0xFFE5E7EB),
            ),
          ),
          child: Text(
            picked > 0 ? '$label · $picked/$total' : '$label · $total',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : Colors.black54,
            ),
          ),
        ),
      ),
    );
  }

  Widget _pickedOnlyToggle() {
    final on = _pickedOnly;
    return GestureDetector(
      onTap: () => setState(() => _pickedOnly = !on),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: on ? const Color(0xFF4F46E5).withOpacity(0.10) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: on ? const Color(0xFF4F46E5) : const Color(0xFFE5E7EB)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(on ? Icons.check_circle : Icons.circle_outlined,
                size: 14, color: on ? const Color(0xFF4F46E5) : Colors.black38),
            const SizedBox(width: 6),
            Text(
              'Picked only (${_picked.length})',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: on ? const Color(0xFF4F46E5) : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_pickedOnly ? Icons.checklist_rounded : Icons.search_off,
                  size: 40, color: Colors.black26),
              const SizedBox(height: 12),
              Text(
                _pickedOnly
                    ? 'Nothing picked yet.'
                    : 'No question matches "$_search".',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.black45),
              ),
            ],
          ),
        ),
      );

  Widget _row(HighSchoolQuestion q, Map<String, int> positions) {
    final on = _picked.contains(q.id);
    final open = _expanded.contains(q.id);
    final data = q.mcqData;
    final options = data?.options ?? const <String>[];
    final correct = (data?.correctAns ?? '').trim();
    final position = positions[q.id];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: on ? const Color(0xFF4F46E5).withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: on ? const Color(0xFF4F46E5) : const Color(0xFFE5E7EB),
          width: on ? 1.6 : 1,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => _toggle(q.id),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 2, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    on
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    size: 20,
                    color: on ? const Color(0xFF4F46E5) : Colors.black26,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (data?.text ?? '').trim(),
                          maxLines: open ? null : 2,
                          overflow: open ? null : TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, height: 1.35),
                        ),
                        const SizedBox(height: 5),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (position != null) _positionPill(position),
                            if (q.chapterName.isNotEmpty)
                              Text(q.chapterName,
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.black38)),
                            if (correct.isNotEmpty)
                              Text(
                                'Answer: $correct',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF047857),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() {
                      if (!_expanded.remove(q.id)) _expanded.add(q.id);
                    }),
                    icon: Icon(open ? Icons.expand_less : Icons.expand_more,
                        size: 20),
                    tooltip: open ? 'Hide choices' : 'Show choices',
                    visualDensity: VisualDensity.compact,
                    color: Colors.black38,
                  ),
                ],
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(40, 0, 14, 12),
              child: options.isEmpty
                  ? const Text('This question has no options.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF9A3412)))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final option in options)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  option.trim() == correct
                                      ? Icons.check_circle
                                      : Icons.circle_outlined,
                                  size: 14,
                                  color: option.trim() == correct
                                      ? const Color(0xFF10B981)
                                      : Colors.black26,
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    option,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: option.trim() == correct
                                          ? const Color(0xFF047857)
                                          : Colors.black54,
                                      fontWeight: option.trim() == correct
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }

  Widget _positionPill(int n) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        decoration: BoxDecoration(
          color: const Color(0xFF4F46E5),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text('Q$n',
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Colors.white)),
      );

  Widget _footer() => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${_picked.length} selected',
                        style: const TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 1),
                    Text(
                      _picked.isEmpty
                          ? 'The paper would be empty'
                          : 'Asked in bank order',
                      style: const TextStyle(
                          fontSize: 11.5, color: Colors.black45),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(_picked),
                  icon: const Icon(Icons.check_rounded, size: 20),
                  label:
                      Text(_picked.isEmpty ? 'Done' : 'Use ${_picked.length}'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
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

/// One chapter's tally in the picker's filter row.
class _ChapterBucket {
  _ChapterBucket(this.number, this.name);

  final String number;
  final String name;
  int total = 0;
  int picked = 0;
}
