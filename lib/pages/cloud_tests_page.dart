import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:pi_qbank/models/highschool_question.dart';
import 'package:pi_qbank/pages/mcq_test_page.dart';
import 'package:pi_qbank/services/highschool_export_service.dart';
import 'package:pi_qbank/services/highschool_qbank_service.dart';
import 'package:pi_qbank/utils/math_rich_text.dart';
import 'package:pi_qbank/utils/mcq_stem_units.dart';
import 'package:pi_qbank/widgets/custom_app_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Online exams built from the High School question bank.
///
/// The bank is the same Google Sheet the paper generator draws from, read
/// through `HighSchoolQBankService`, so a question written once is available
/// both as a printed paper and as an online exam — no second copy to maintain.
///
/// The page is an exam builder, not just a form: the whole subject is read
/// once, chapters become an instant client-side filter with live counts, the
/// paper is drawn with a visible summary, and the runner only ever receives
/// questions that can actually be marked.
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
  /// Three things are not obvious and all three fail loudly or, worse,
  /// silently:
  ///
  ///  * `options` is a **Map**, not a list. The runner iterates it as
  ///    `question['options'].entries` and renders a `RadioListTile` whose
  ///    `value` is `option.key`. Handing it a list throws
  ///    `List<dynamic> is not a subtype of Map<String, dynamic>` the moment the
  ///    first question is built.
  ///  * The student's answer is that **key**, so `correct_answer` has to be a
  ///    key too. The sheet stores the correct option as its *text*, so it is
  ///    translated to the matching key here. Sending the text would mark
  ///    nothing correct and every score would come out zero.
  ///  * An MCQ's question line lives in the sub-question payload while its
  ///    shared stimulus lives in `stem_text`. The runner shows one block of
  ///    text, so the stimulus has to travel with the question or the student
  ///    answers something they were never shown.
  ///  * The stimulus or question figure lives in `stem_image_url`, outside the
  ///    MCQ payload. It has to be carried explicitly as `image_url` or the
  ///    online runner shows only the text and silently drops the diagram.
  ///
  /// Exposed for tests: this is the contract between the two pages and nothing
  /// else exercises it.
  ///
  /// [shuffleOptions] reorders the answer choices while keeping
  /// `correct_answer` pointing at the right one. Without it, question 3's
  /// answer is always option 2 and the paper can be passed by pattern rather
  /// than by knowing the subject.
  ///
  /// [stem] overrides the introduction the question carries. A shared-stimulus
  /// run passes the rewritten intro on its first question and an empty string
  /// on the rest, so the intro and its figure are shown once, not repeated
  /// under every question in the run.
  static Map<String, dynamic> mcqPayload(
    HighSchoolQuestion q, {
    bool shuffleOptions = false,
    Random? random,
    String? stem,
    bool includeImage = true,
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

    final stemText = (stem ?? q.mcqStemText).trim();
    final question = (data?.text ?? '').trim();
    final shown = stemText.isEmpty ? question : '$stemText\n\n$question';
    final imageUrl = includeImage
        ? HighSchoolExportService.resolveImageUrl(q.mcqStemImageUrl)
        : '';

    return {
      'question': shown,
      'options': options,
      'correct_answer': correctKey,
      if (imageUrl.isNotEmpty) 'image_url': imageUrl,
    };
  }

  /// Build the runner payloads for a whole paper, in paper order.
  ///
  /// A shared-stimulus run is printed once: its first question carries the
  /// intro, rewritten to the numbers the run actually occupies in this paper,
  /// and the following questions carry only their own text. Without this the
  /// source numbers ("answer 6 and 7") stay frozen while the runner numbers
  /// the card 15, and each question repeats an intro that belongs to the run.
  ///
  /// Exposed for tests: this is where the run contract is applied.
  static List<Map<String, dynamic>> mcqPaperPayloads(
    List<HighSchoolQuestion> questions, {
    bool shuffleOptions = false,
    Random? random,
  }) {
    final payloads = <Map<String, dynamic>>[];
    for (var i = 0; i < questions.length; i++) {
      final question = questions[i];
      final previous = i == 0 ? null : questions[i - 1];
      final opensStem = question.opensMcqStemGroup(previous);
      final sharesStem = question.sharesMcqStemWith(previous);
      final stem = opensStem
          ? HighSchoolExportService.stemWithNumbers(
              question.mcqStemText,
              HighSchoolExportService.mcqStemRunNumbers(questions, i),
            )
          : '';
      payloads.add(
        mcqPayload(
          question,
          shuffleOptions: shuffleOptions,
          random: random,
          stem: stem,
          includeImage: !sharesStem,
        ),
      );
    }
    return payloads;
  }

  @override
  State<CloudTestsPage> createState() => _CloudTestsPageState();
}

/// How the paper is put together.
enum _PickMode { random, manual }

/// One palette for the builder, the sheets and the picker.
///
/// Keeping the exam chrome in one palette makes the page, its sheets and the
/// runner feel like one product rather than three screens stitched together.
class _C {
  _C._();

  static const primary = Color(0xFF4338CA);
  static const primaryDeep = Color(0xFF312E81);
  static const violet = Color(0xFF7C3AED);
  static const primarySoft = Color(0xFFEEF2FF);
  static const primaryLine = Color(0xFFC7D2FE);
  static const canvas = Color(0xFFF6F7FB);
  static const line = Color(0xFFE6E8F1);
  static const ink = Color(0xFF0F172A);
  static const muted = Color(0xFF64748B);
  static const faint = Color(0xFF94A3B8);
  static const success = Color(0xFF047857);
  static const successSoft = Color(0xFFECFDF5);
  static const warning = Color(0xFFB45309);
  static const warningSoft = Color(0xFFFFFBEB);
  static const danger = Color(0xFFB91C1C);
  static const dangerSoft = Color(0xFFFEF2F2);
}

class _CloudTestsPageState extends State<CloudTestsPage> {
  static const List<String> _classes = [
    'Class 6',
    'Class 7',
    'Class 8',
    'Class (9-10) SSC',
    'Class (11-12) HSC',
  ];

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
  static const String _prefsBalance = 'cloudExam.balance';
  static const String _prefsMinutes = 'cloudExam.minutes';
  static const String _prefsPicked = 'cloudExam.picked';

  static const List<String> _prefsKeys = [
    _prefsClass,
    _prefsSubject,
    _prefsChapters,
    _prefsMode,
    _prefsCount,
    _prefsShuffle,
    _prefsShuffleOptions,
    _prefsBalance,
    _prefsMinutes,
    _prefsPicked,
  ];

  late final HighSchoolQBankService _service =
      const HighSchoolQBankService(scriptUrl: CloudTestsPage.scriptUrl);

  // ── selection ────────────────────────────────────────────────────────────
  String? _className;
  String? _subject;

  /// Chapters the paper is limited to. Empty means every chapter.
  final Set<String> _chapters = <String>{};

  // ── loaded bank ──────────────────────────────────────────────────────────
  List<ChapterInfo> _chapterList = const [];
  List<HighSchoolQuestion> _allQuestions = const [];
  bool _loadingChapters = false;
  bool _loadingPool = false;

  /// True once a subject read has succeeded. Kept separately from
  /// `_allQuestions.isNotEmpty` because an empty subject is still a valid read
  /// and should not look like "nothing happened".
  bool _poolFetched = false;

  String? _error;
  String? _chapterWarning;

  /// Invalidates in-flight reads when the subject, class or reset changes.
  int _loadToken = 0;

  // ── exam plan ────────────────────────────────────────────────────────────
  int _mcqCount = 10;
  bool _shuffle = true;

  /// Reorder the four choices under each question.
  ///
  /// Off by default so a question printed as "উত্তর: খ" reads the same on
  /// screen; on, it stops a student from answering by position.
  bool _shuffleOptions = false;

  /// Spread a random draw across chapters before repeating one.
  ///
  /// Off by default: a quick practice on all chapters is usually a free draw.
  /// On, it is the fair "one from every chapter" paper a teacher wants.
  bool _balanceChapters = false;

  /// [random] draws N at random. [manual] takes exactly the questions ticked,
  /// so a teacher can sit a class down on a specific set.
  _PickMode _pickMode = _PickMode.random;

  /// Ids ticked in manual mode.
  final Set<String> _pickedIds = <String>{};

  /// Minutes to allow, or null for the derived default.
  int? _customMinutes;

  /// The random paper last drawn.
  ///
  /// `_selected` is read several times per frame — the count, the summary, the
  /// preview, the start action. Shuffling inside the getter meant each read
  /// produced a *different* paper, so Preview could show one set while Start
  /// ran another. The draw is kept until one of its inputs changes.
  List<HighSchoolQuestion>? _draw;
  Object? _drawKey;

  /// Bumped by "Redraw", so the same inputs can still produce a fresh paper.
  int _drawVersion = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreSettings());
  }

  // ── persistence ──────────────────────────────────────────────────────────

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
    if (subject == null || !_subjectsFor(className).contains(subject)) return;
    if (!mounted) return;

    final savedMinutes = prefs.getInt(_prefsMinutes);
    setState(() {
      _className = className;
      _subject = subject;
      _mcqCount = prefs.getInt(_prefsCount) ?? _mcqCount;
      _shuffle = prefs.getBool(_prefsShuffle) ?? _shuffle;
      _shuffleOptions = prefs.getBool(_prefsShuffleOptions) ?? _shuffleOptions;
      _balanceChapters = prefs.getBool(_prefsBalance) ?? _balanceChapters;
      _customMinutes =
          savedMinutes != null && savedMinutes > 0 ? savedMinutes : null;
      _pickMode = prefs.getString(_prefsMode) == 'manual'
          ? _PickMode.manual
          : _PickMode.random;
    });

    // Chapters and questions only exist once the bank answers, so the
    // remembered paper can be reassembled no earlier than that.
    await _loadSubject();
    if (!mounted) return;

    final savedChapters = prefs.getStringList(_prefsChapters) ?? const [];
    final knownChapters =
        _allChapters.map((chapter) => chapter.chapterNumber).toSet();
    final restoredChapters =
        savedChapters.where(knownChapters.contains).toSet();
    setState(() {
      _chapters
        ..clear()
        ..addAll(restoredChapters.length == knownChapters.length
            ? const <String>{}
            : restoredChapters);
      _clampPlanToAvailable();
      _drawVersion++;
    });

    // The picked questions are part of the paper, so a manual paper reopens
    // with the same questions ticked instead of an empty sheet. Ids that are
    // no longer in the bank (or filtered out by chapters) are dropped.
    final savedPicked = prefs.getStringList(_prefsPicked) ?? const [];
    if (savedPicked.isEmpty) return;
    final available = _scopedMcqs.map((question) => question.id).toSet();
    final restored = savedPicked.where(available.contains).toSet();
    setState(() {
      _pickedIds
        ..clear()
        ..addAll(expandMcqStemPicks(restored, _scopedMcqs));
    });
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
      await prefs.setBool(_prefsBalance, _balanceChapters);
      await prefs.setStringList(_prefsPicked, _pickedIds.toList());
      if (_customMinutes == null) {
        await prefs.remove(_prefsMinutes);
      } else {
        await prefs.setInt(_prefsMinutes, _customMinutes!);
      }
    } catch (_) {
      // A paper that fails to be remembered is not worth an error on screen.
    }
  }

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Start over?',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text(
          'This clears the class, subject and chapters, and forgets the paper '
          'remembered for next time. Saved test results are left alone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: _C.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Start over'),
          ),
        ],
      ),
    );
    if (ok == true) await _reset();
  }

  Future<void> _reset() async {
    _loadToken++;
    setState(() {
      _className = null;
      _subject = null;
      _chapters.clear();
      _chapterList = const [];
      _allQuestions = const [];
      _poolFetched = false;
      _loadingChapters = false;
      _loadingPool = false;
      _error = null;
      _chapterWarning = null;
      _pickedIds.clear();
      _mcqCount = 10;
      _shuffle = true;
      _shuffleOptions = false;
      _balanceChapters = false;
      _customMinutes = null;
      _pickMode = _PickMode.random;
      _draw = null;
      _drawKey = null;
      _drawVersion++;
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

  // ── selection handlers ───────────────────────────────────────────────────

  void _selectClass(String? value) {
    if (value == _className) return;
    _loadToken++;
    setState(() {
      _className = value;
      _subject = null;
      _chapters.clear();
      _pickedIds.clear();
      _chapterList = const [];
      _allQuestions = const [];
      _poolFetched = false;
      _loadingChapters = false;
      _loadingPool = false;
      _error = null;
      _chapterWarning = null;
      _draw = null;
      _drawKey = null;
      _drawVersion++;
    });
  }

  void _selectSubject(String? value) {
    if (value == _subject) return;
    _loadToken++;
    setState(() {
      _subject = value;
      _chapters.clear();
      _pickedIds.clear();
      _chapterList = const [];
      _allQuestions = const [];
      _poolFetched = false;
      _loadingChapters = false;
      _loadingPool = false;
      _error = null;
      _chapterWarning = null;
      _draw = null;
      _drawKey = null;
      _drawVersion++;
    });
    if (value != null) unawaited(_loadSubject());
  }

  // ── reading the bank ─────────────────────────────────────────────────────

  /// Read the whole subject in one go.
  ///
  /// Fetching every MCQ and filtering chapters locally is what lets the chapter
  /// sheet show live counts and the paper redraw instantly. The old flow read
  /// only the ticked chapters, so the counts were unknowable until after the
  /// request and every chapter tap became a network round-trip.
  ///
  /// Chapters and questions are fetched independently: the chapter endpoint is
  /// a convenience, and a failure there must not throw away a perfectly good
  /// question pool.
  Future<void> _loadSubject() async {
    final className = _className;
    final subject = _subject;
    if (className == null || subject == null) return;

    final token = ++_loadToken;
    setState(() {
      _loadingChapters = true;
      _loadingPool = true;
      _error = null;
      _chapterWarning = null;
    });

    List<ChapterInfo> chapters = const [];
    List<HighSchoolQuestion> questions = const [];
    Object? chapterError;
    Object? questionError;

    await Future.wait<void>([
      () async {
        try {
          chapters = await _service.fetchChapters(
            className: className,
            subject: subject,
          );
        } catch (error) {
          chapterError = error;
        }
      }(),
      () async {
        try {
          questions = await _service.fetchQuestions(
            className: className,
            subject: subject,
          );
        } catch (error) {
          questionError = error;
        }
      }(),
    ]);

    if (!mounted || token != _loadToken) return;

    if (questionError != null) {
      setState(() {
        _loadingChapters = false;
        _loadingPool = false;
        _error = _friendlyError(questionError!);
        if (chapters.isNotEmpty) _chapterList = chapters;
        if (chapterError != null) {
          _chapterWarning =
              'Chapter names could not be loaded: ${_friendlyError(chapterError!)}';
        }
      });
      return;
    }

    setState(() {
      _chapterList = chapters;
      _allQuestions = questions;
      _loadingChapters = false;
      _loadingPool = false;
      _poolFetched = true;
      _error = null;
      _chapterWarning = chapterError == null
          ? null
          : 'Chapter names could not be loaded. Using the chapters found in '
              'the questions.';
      _clampPlanToAvailable();
      _drawVersion++;
    });
  }

  String _friendlyError(Object error) {
    final text = error.toString().trim();
    const prefix = 'Exception: ';
    return text.startsWith(prefix) ? text.substring(prefix.length) : text;
  }

  // ── derived pool ─────────────────────────────────────────────────────────

  /// Every MCQ row returned by the bank, used for the "skipped" tally.
  Iterable<HighSchoolQuestion> get _mcqs =>
      _allQuestions.where((question) => question.isMcq);

  /// MCQs that can actually be marked.
  ///
  /// A question without text, with fewer than two choices, or whose stored
  /// correct answer matches no choice would produce a paper with an unmarkable
  /// question. Excluding them is the difference between a fair score and a
  /// silently wrong one; the page says how many were skipped rather than
  /// hiding the loss.
  List<HighSchoolQuestion> get _usableMcqs {
    final out = <HighSchoolQuestion>[];
    for (final question in _mcqs) {
      final data = question.mcqData;
      if (data == null || data.text.trim().isEmpty) continue;

      final options = <String>[];
      for (final option in data.options) {
        final text = option.trim();
        if (text.isNotEmpty) options.add(text);
      }
      if (options.length < 2) continue;
      if (!options.contains(data.correctAns.trim())) continue;
      out.add(question);
    }
    return out;
  }

  List<HighSchoolQuestion> get _scopedMcqs {
    final usable = _usableMcqs;
    if (_chapters.isEmpty) return usable;
    return usable
        .where((question) => _chapters.contains(question.chapterNumber))
        .toList(growable: false);
  }

  /// Chapters from the metadata endpoint plus any chapter that only appears on
  /// a question row. A missing `getChapters` response should not hide a
  /// chapter the bank clearly holds.
  List<ChapterInfo> get _allChapters {
    final byNumber = <String, ChapterInfo>{};
    for (final chapter in _chapterList) {
      final number = chapter.chapterNumber.trim();
      if (number.isEmpty) continue;
      byNumber[number] = chapter;
    }
    for (final question in _allQuestions) {
      final number = question.chapterNumber.trim();
      if (number.isEmpty) continue;
      byNumber.putIfAbsent(number, () => question.chapterInfo);
    }
    final out = byNumber.values.toList()
      ..sort((a, b) => compareChapterNumbers(a.chapterNumber, b.chapterNumber));
    return out;
  }

  Map<String, int> get _chapterCounts {
    final counts = <String, int>{};
    for (final question in _usableMcqs) {
      counts[question.chapterNumber] =
          (counts[question.chapterNumber] ?? 0) + 1;
    }
    return counts;
  }

  List<String> get _selectedChapterNumbers =>
      _chapters.toList()..sort(compareChapterNumbers);

  int get _scopeChapterCount =>
      _chapters.isEmpty ? _allChapters.length : _chapters.length;

  String _chapterLabel(String number) {
    for (final chapter in _chapterList) {
      if (chapter.chapterNumber == number &&
          chapter.chapterName.trim().isNotEmpty) {
        return chapter.chapterName;
      }
    }
    for (final question in _allQuestions) {
      if (question.chapterNumber == number &&
          question.chapterName.trim().isNotEmpty) {
        return question.chapterName;
      }
    }
    return 'অধ্যায় $number';
  }

  String get _scopeLabel {
    final chapters = _allChapters;
    if (chapters.isEmpty) return 'All chapters';
    if (_chapters.isEmpty) {
      return chapters.length == 1
          ? _chapterLabel(chapters.first.chapterNumber)
          : 'All ${chapters.length} chapters';
    }
    if (_chapters.length == 1) return _chapterLabel(_chapters.first);
    return '${_chapters.length} chapters';
  }

  String get _examTopic {
    final subject = (_subject ?? '').trim();
    return subject.isEmpty ? _scopeLabel : '$subject · $_scopeLabel';
  }

  int get _allMcqCount => _mcqs.length;

  int get _writtenCount => _allQuestions.length - _allMcqCount;

  // ── planning ─────────────────────────────────────────────────────────────

  void _clampPlanToAvailable() {
    final scoped = _scopedMcqs;
    final available = scoped.length;
    if (available <= 0) {
      _mcqCount = 0;
    } else if (_mcqCount <= 0) {
      _mcqCount = min(10, available);
    } else {
      _mcqCount = min(_mcqCount, available);
    }
    final ids = scoped.map((question) => question.id).toSet();
    _pickedIds.removeWhere((id) => !ids.contains(id));
    // A shared-stimulus pair is one unit. Expanding here repairs a selection
    // restored from before run-aware picking and keeps the figure and its two
    // questions together after a chapter change.
    final expanded = expandMcqStemPicks(_pickedIds, scoped);
    _pickedIds
      ..clear()
      ..addAll(expanded);
    _draw = null;
    _drawKey = null;
  }

  String get _chapterSignature => _selectedChapterNumbers.join('\u0001');

  /// The questions the paper will actually contain, in the order it will run.
  List<HighSchoolQuestion> get _selected {
    if (_pickMode == _PickMode.manual) {
      if (_pickedIds.isEmpty) return const [];
      // Bank order, not the order they were ticked: a list reordered by tapping
      // reads as random, and two students picking the same questions should get
      // the same paper. Expanding the ids keeps a shared-stimulus run whole
      // even if a restored selection only named one half of it.
      final pool = _scopedMcqs;
      final picked = expandMcqStemPicks(_pickedIds, pool);
      return pool
          .where((question) => picked.contains(question.id))
          .toList(growable: false);
    }

    final pool = _scopedMcqs;
    if (_mcqCount <= 0 || pool.isEmpty) return const [];

    final key = Object.hash(
      identityHashCode(_allQuestions),
      _chapterSignature,
      _mcqCount,
      _shuffle,
      _balanceChapters,
      _drawVersion,
    );
    if (key == _drawKey && _draw != null) return _draw!;

    final drawn = _drawRandom(pool);
    _draw = drawn;
    _drawKey = key;
    return drawn;
  }

  List<HighSchoolQuestion> _drawRandom(List<HighSchoolQuestion> pool) {
    final random = Random();
    final target = min(_mcqCount, pool.length);
    if (target <= 0) return const [];

    // Select whole shared-stimulus runs. Splitting a pair leaves a question
    // whose intro says "answer 6 and 7" while only 6 is on the paper, and the
    // intro's numbers then disagree with the card number as well.
    final units = mcqStemUnits(pool);
    if (units.isEmpty) return const [];

    if (!_balanceChapters || _scopeChapterCount < 2) {
      final list = List<List<HighSchoolQuestion>>.from(units);
      if (_shuffle) list.shuffle(random);
      final out = <HighSchoolQuestion>[];
      for (final unit in list) {
        if (out.length >= target) break;
        out.addAll(unit);
      }
      return out;
    }

    // Round-robin one unit at a time, so the paper reaches every chapter
    // before it takes a second run from any of them.
    final groups = <String, List<List<HighSchoolQuestion>>>{};
    for (final unit in units) {
      groups
          .putIfAbsent(
              unit.first.chapterNumber, () => <List<HighSchoolQuestion>>[])
          .add(unit);
    }
    final buckets = groups.values.toList(growable: false);
    for (final bucket in buckets) {
      if (_shuffle) bucket.shuffle(random);
    }
    final order = List<int>.generate(buckets.length, (index) => index);
    if (_shuffle) order.shuffle(random);
    final cursor = List<int>.filled(buckets.length, 0);
    final out = <HighSchoolQuestion>[];
    var added = true;
    while (out.length < target && added) {
      added = false;
      for (final index in order) {
        if (out.length >= target) break;
        if (cursor[index] < buckets[index].length) {
          out.addAll(buckets[index][cursor[index]++]);
          added = true;
        }
      }
    }
    return out;
  }

  void _redraw() {
    if (!_shuffle || _plannedCount == 0) return;
    setState(() => _drawVersion++);
  }

  int get _plannedCount => _selected.length;

  /// One mark per question: an MCQ is a single right answer.
  int get _plannedMarks => _plannedCount;

  /// Roughly a minute a question, with a floor so a two-question paper still
  /// gives the student time to read it — unless the user set a time.
  int get _plannedMinutes => _customMinutes ?? max(3, _plannedCount);

  // ── sheets ───────────────────────────────────────────────────────────────

  Future<void> _openChapterSheet() async {
    final chapters = _allChapters;
    if (chapters.isEmpty) return;
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.86,
        child: _ChapterSheet(
          chapters: chapters,
          counts: _chapterCounts,
          selected: _chapters,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _chapters
        ..clear()
        ..addAll(result);
      // Empty is the storage form of "every chapter", so normalise a full
      // selection back to it.
      if (_chapters.length == chapters.length) _chapters.clear();
      _clampPlanToAvailable();
      _drawVersion++;
    });
  }

  Future<void> _openTimeSheet() async {
    final choice = await showModalBottomSheet<_TimeChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TimeLimitSheet(
        initialMinutes: _customMinutes,
        autoMinutes: max(3, _plannedCount),
      ),
    );
    if (choice == null || !mounted) return;
    setState(() => _customMinutes = choice.minutes);
  }

  Future<void> _openPicker() async {
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.93,
        child: QuestionPicker(
          questions: _scopedMcqs,
          initial: expandMcqStemPicks(_pickedIds, _scopedMcqs),
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _pickedIds
        ..clear()
        ..addAll(expandMcqStemPicks(result, _scopedMcqs));
      _draw = null;
      _drawKey = null;
    });
  }

  // ── run ──────────────────────────────────────────────────────────────────

  void _startExam() {
    final picked = _selected;
    if (picked.isEmpty) return;

    // Remember the setup of a paper that was actually given.
    unawaited(_saveSettings());

    _go(
      MCQTestPage(
        numberOfQuestions: picked.length,
        testTimeInMinutes: _plannedMinutes,
        aiResponse: jsonEncode({
          'questions': CloudTestsPage.mcqPaperPayloads(
            picked,
            shuffleOptions: _shuffleOptions,
          ),
        }),
        language: 'Bangla',
        showAllQuestions: true,
        aiTopic: _examTopic,
      ),
    );
  }

  void _go(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  /// Show the paper before it is sat.
  ///
  /// The point of building a paper is to check it: that the right chapters came
  /// back, that the questions read properly, that the key matches an option.
  /// Once the exam starts none of that can be fixed.
  void _previewPaper() {
    final picked = _selected;
    if (picked.isEmpty) return;
    final minutes = _plannedMinutes;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        maxChildSize: 0.96,
        minChildSize: 0.55,
        expand: false,
        builder: (sheetContext, controller) => _PreviewSheet(
          questions: picked,
          minutes: minutes,
          scrollController: controller,
          onStart: () {
            Navigator.of(sheetContext).pop();
            _startExam();
          },
        ),
      ),
    );
  }

  // ── build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final picked = _selected;
    return Scaffold(
      backgroundColor: _C.canvas,
      appBar: CustomAppBar(
        title: 'Online Exam',
        actions: [
          if (_hasSomethingToReset)
            IconButton(
              onPressed: _confirmReset,
              tooltip: 'Start over',
              icon: const Icon(Icons.restart_alt_rounded),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final main = <Widget>[
              _hero(),
              const SizedBox(height: 14),
              _sourceCard(),
              const SizedBox(height: 14),
              _buildCard(),
              const SizedBox(height: 8),
            ];

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: main,
                              ),
                            ),
                            const SizedBox(width: 18),
                            SizedBox(width: 330, child: _paperPanel(picked)),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: main,
                        ),
                ),
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: _bottomBar(picked),
    );
  }

  bool get _hasSomethingToReset =>
      _className != null ||
      _subject != null ||
      _chapters.isNotEmpty ||
      _allQuestions.isNotEmpty ||
      _pickedIds.isNotEmpty;

  // ── hero ─────────────────────────────────────────────────────────────────

  Widget _hero() {
    final loaded = _poolFetched;
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_C.primary, _C.violet],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            Positioned(right: -36, top: -48, child: _heroBubble(150)),
            Positioned(right: 70, bottom: -54, child: _heroBubble(100)),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.18),
                          ),
                        ),
                        child: const Icon(
                          Icons.fact_check_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Exam builder',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.1,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'MCQs from the High School bank, marked for you.',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Text(
                          'MCQ only',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (loaded) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _heroStat('${_usableMcqs.length}', 'MCQs'),
                        _heroDivider(),
                        _heroStat('${_allChapters.length}', 'chapters'),
                        _heroDivider(),
                        _heroStat('${_allQuestions.length}', 'rows loaded'),
                      ],
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    Text(
                      _loadingPool
                          ? 'Reading the question bank…'
                          : _error != null
                              ? 'The question bank could not be read.'
                              : 'Choose a class and subject to begin.',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (_loadingPool) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: const LinearProgressIndicator(
                        minHeight: 3,
                        color: Colors.white,
                        backgroundColor: Colors.white24,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroBubble(double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.06),
        ),
      );

  Widget _heroStat(String value, String label) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                height: 1.2,
              ),
            ),
          ],
        ),
      );

  Widget _heroDivider() => Container(
        width: 1,
        height: 26,
        margin: const EdgeInsets.symmetric(horizontal: 10),
        color: Colors.white.withOpacity(0.22),
      );

  // ── source ───────────────────────────────────────────────────────────────

  Widget _sourceCard() {
    final status = _loadingPool || _loadingChapters
        ? _statusPill('Loading', _C.warning, _C.warningSoft, busy: true)
        : _error != null
            ? _statusPill('Error', _C.danger, _C.dangerSoft)
            : _poolFetched
                ? _statusPill('Loaded', _C.success, _C.successSoft)
                : _statusPill('Not loaded', _C.muted, const Color(0xFFF1F5F9));

    final chapters = _allChapters;
    final selectedNames = _selectedChapterNumbers;
    final chapterSubtitle = _loadingChapters
        ? 'Loading chapters…'
        : _className == null || _subject == null
            ? 'Pick a class and subject first'
            : chapters.isEmpty
                ? 'No chapter list — all questions will be used'
                : _chapters.isEmpty
                    ? 'All ${chapters.length} '
                        'chapter${chapters.length == 1 ? '' : 's'} included'
                    : '${_chapters.length} of ${chapters.length} selected';

    return _sectionCard(
      icon: Icons.school_outlined,
      title: 'Source',
      subtitle: 'Class, subject and chapters',
      trailing: status,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _fieldLabel('Class'),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: _className,
                      isExpanded: true,
                      style: const TextStyle(fontSize: 13, color: _C.ink),
                      decoration: _fieldDecoration(),
                      hint: const Text('Choose'),
                      items: [
                        for (final className in _classes)
                          DropdownMenuItem(
                            value: className,
                            child: Text(
                              className,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _selectClass,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _fieldLabel('Subject'),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: _subject,
                      isExpanded: true,
                      style: const TextStyle(fontSize: 13, color: _C.ink),
                      decoration: _fieldDecoration(),
                      hint: const Text('Choose'),
                      items: _className == null
                          ? const <DropdownMenuItem<String>>[]
                          : [
                              for (final subject in _subjectsFor(_className!))
                                DropdownMenuItem(
                                  value: subject,
                                  child: Text(
                                    subject,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                      onChanged: _className == null ? null : _selectSubject,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: chapters.isEmpty ? null : _openChapterSheet,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _C.line),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _C.primarySoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.menu_book_rounded,
                      color: _C.primary,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Chapters',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _C.ink,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          chapterSubtitle,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: _C.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_loadingChapters)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else ...[
                    if (_chapters.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _C.primarySoft,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_chapters.length}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: _C.primary,
                          ),
                        ),
                      ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: _C.faint,
                      size: 20,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (selectedNames.isNotEmpty && selectedNames.length <= 3) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final number in selectedNames)
                  _tinyPill(_chapterLabel(number)),
              ],
            ),
          ],
          if (_chapterWarning != null) ...[
            const SizedBox(height: 8),
            _inlineNote(
              Icons.info_outline_rounded,
              _chapterWarning!,
              _C.warning,
              _C.warningSoft,
            ),
          ],
          const SizedBox(height: 12),
          if (_loadingPool)
            const _LoadingLine(label: 'Reading the question bank…')
          else ...[
            if (_error != null) ...[
              _errorBox(_error!),
              const SizedBox(height: 10),
            ],
            if (_poolFetched) _loadedSummary() else _idleHint(),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed:
                    _className == null || _subject == null || _loadingPool
                        ? null
                        : _loadSubject,
                icon: _poolFetched
                    ? const Icon(Icons.refresh_rounded, size: 18)
                    : const Icon(Icons.download_rounded, size: 18),
                label: Text(
                  _poolFetched ? 'Refresh questions' : 'Load questions',
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  foregroundColor: _C.primary,
                  side: const BorderSide(color: _C.primaryLine),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _idleHint() => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 15, color: _C.faint),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _className == null || _subject == null
                  ? 'Pick a class and subject — the bank reads automatically.'
                  : 'Press Load questions to read this subject from the bank.',
              style: const TextStyle(
                fontSize: 11.5,
                color: _C.muted,
                height: 1.35,
              ),
            ),
          ),
        ],
      );

  Widget _loadedSummary() {
    final usable = _usableMcqs.length;
    final broken = _allMcqCount - usable;
    final written = _writtenCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _miniStat('$usable', 'answerable MCQs'),
            _miniStat('${_allChapters.length}', 'chapters'),
            _miniStat('${_allQuestions.length}', 'rows'),
          ],
        ),
        if (broken > 0 || written > 0) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (broken > 0)
                _tinyPill('$broken skipped — cannot be marked', warning: true),
              if (written > 0) _tinyPill('$written CQ/SQ ignored', muted: true),
            ],
          ),
        ],
      ],
    );
  }

  // ── build ────────────────────────────────────────────────────────────────

  Widget _buildCard() {
    final count = _plannedCount;
    return _sectionCard(
      icon: Icons.tune_rounded,
      title: 'Build the paper',
      subtitle: 'How many, which, and how long',
      trailing: count > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _C.successSoft,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$count ${count == 1 ? 'question' : 'questions'}',
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: _C.success,
                ),
              ),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _modeSwitch(),
          const SizedBox(height: 14),
          _buildBody(),
          if (_poolFetched && _usableMcqs.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(height: 1, color: _C.line),
            const SizedBox(height: 14),
            _options(),
          ],
          if (_plannedCount > 0) ...[
            const SizedBox(height: 14),
            _summaryStrip(),
          ],
        ],
      ),
    );
  }

  Widget _modeSwitch() => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F3FA),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            _modeTab(_PickMode.random, Icons.shuffle_rounded, 'Random'),
            _modeTab(_PickMode.manual, Icons.checklist_rounded, 'Pick myself'),
          ],
        ),
      );

  Widget _modeTab(_PickMode mode, IconData icon, String label) {
    final selected = _pickMode == mode;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_pickMode == mode) return;
          setState(() {
            _pickMode = mode;
            _draw = null;
            _drawKey = null;
            _clampPlanToAvailable();
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: const Color(0xFF0F172A).withOpacity(0.07),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: selected ? _C.primary : _C.faint),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? _C.primary : _C.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loadingPool) {
      return const _LoadingLine(label: 'Reading the question bank…');
    }
    if (!_poolFetched) {
      if (_error != null) {
        return _emptyHint(
          icon: Icons.cloud_off_rounded,
          title: 'Questions are not loaded',
          body: 'Use Load questions above to try again.',
          tone: _HintTone.warning,
        );
      }
      return _emptyHint(
        icon: _pickMode == _PickMode.manual
            ? Icons.checklist_rounded
            : Icons.inbox_outlined,
        title: _pickMode == _PickMode.manual
            ? 'Pick questions after loading'
            : 'Draw questions after loading',
        body: _pickMode == _PickMode.manual
            ? 'Load some questions first, then tick the exact ones to ask.'
            : 'Load some questions first — the paper is drawn from the bank.',
      );
    }
    if (_allQuestions.isEmpty) {
      return _emptyHint(
        icon: Icons.search_off_rounded,
        title: 'Nothing in this subject',
        body: 'The bank returned no questions for this class and subject.',
      );
    }
    if (_allMcqCount == 0) {
      return _emptyHint(
        icon: Icons.notes_rounded,
        title: 'No MCQs here',
        body: 'This selection only holds CQ and SQ, which need written '
            'answers. This page can only sit MCQs.',
      );
    }
    if (_usableMcqs.isEmpty) {
      return _emptyHint(
        icon: Icons.key_off_rounded,
        title: 'No answer keys found',
        body: 'Every MCQ returned is missing a matching answer key, so none '
            'can be marked fairly.',
      );
    }
    if (_scopedMcqs.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _emptyHint(
            icon: Icons.filter_alt_off_rounded,
            title: 'No MCQs in these chapters',
            body: 'The selected chapters have no answerable MCQs. Include '
                'another chapter or choose all of them.',
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _openChapterSheet,
            icon: const Icon(Icons.menu_book_rounded, size: 18),
            label: const Text('Change chapters'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _C.primary,
              side: const BorderSide(color: _C.primaryLine),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      );
    }
    return _pickMode == _PickMode.random
        ? _randomControls()
        : _manualControls();
  }

  Widget _randomControls() {
    final available = _scopedMcqs.length;
    final count = _mcqCount.clamp(1, available);
    final presets = <MapEntry<String, int>>[];
    if (available > 1) {
      for (final n in const [5, 10, 20, 30]) {
        if (n < available) presets.add(MapEntry('$n', n));
      }
      presets.add(MapEntry('All', available));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            color: _C.primarySoft,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _C.primaryLine.withOpacity(0.7)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Questions in this paper',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: _C.muted,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '$count',
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                                color: _C.primary,
                                height: 1.0,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Text(
                                '/ $available',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: _C.muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _shuffle && _plannedCount > 0 ? _redraw : null,
                    icon: const Icon(Icons.casino_outlined, size: 18),
                    label: const Text('Redraw'),
                    style: TextButton.styleFrom(
                      foregroundColor: _C.primary,
                      disabledForegroundColor: _C.faint,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              if (available > 1)
                Row(
                  children: [
                    _stepButton(
                      Icons.remove_rounded,
                      count > 1
                          ? () => setState(() => _mcqCount = count - 1)
                          : null,
                      'One fewer',
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          activeTrackColor: _C.primary,
                          inactiveTrackColor: _C.primaryLine,
                          thumbColor: _C.primary,
                          overlayColor: _C.primary.withOpacity(0.12),
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 8,
                          ),
                        ),
                        child: Slider(
                          value: count.toDouble(),
                          min: 1,
                          max: available.toDouble(),
                          label: '$count',
                          onChanged: (value) => setState(
                            () => _mcqCount = value.round().clamp(1, available),
                          ),
                        ),
                      ),
                    ),
                    _stepButton(
                      Icons.add_rounded,
                      count < available
                          ? () => setState(() => _mcqCount = count + 1)
                          : null,
                      'One more',
                    ),
                  ],
                )
              else
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    'This is the only answerable MCQ in the current scope.',
                    style: TextStyle(fontSize: 11.5, color: _C.muted),
                  ),
                ),
              if (presets.isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final preset in presets)
                      _presetChip(
                        preset.key,
                        selected: count == preset.value,
                        onTap: () => setState(() => _mcqCount = preset.value),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 6),
        _switchRow(
          icon: Icons.shuffle_rounded,
          title: 'Shuffle question order',
          subtitle: _shuffle
              ? 'A fresh order each time the paper is drawn.'
              : 'Keep the order the bank returns.',
          value: _shuffle,
          onChanged: (value) => setState(() {
            _shuffle = value;
            _draw = null;
            _drawKey = null;
          }),
        ),
        if (_scopeChapterCount > 1)
          _switchRow(
            icon: Icons.balance_rounded,
            title: 'Spread across chapters',
            subtitle: _balanceChapters
                ? 'Draw from every chapter before repeating one.'
                : 'Draw freely from the whole pool.',
            value: _balanceChapters,
            onChanged: (value) => setState(() {
              _balanceChapters = value;
              _draw = null;
              _drawKey = null;
            }),
          ),
      ],
    );
  }

  Widget _manualControls() {
    final picked = _selected;
    final chapterCount =
        picked.map((question) => question.chapterNumber).toSet().length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _C.primarySoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.checklist_rounded,
                color: _C.primary,
                size: 19,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    picked.isEmpty
                        ? 'No questions picked'
                        : '${picked.length} '
                            'question${picked.length == 1 ? '' : 's'} picked',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: _C.ink,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    picked.isEmpty
                        ? 'Choose the exact questions this paper should ask.'
                        : '$chapterCount '
                            'chapter${chapterCount == 1 ? '' : 's'} · asked in '
                            'bank order',
                    style: const TextStyle(fontSize: 11, color: _C.muted),
                  ),
                ],
              ),
            ),
            if (picked.isNotEmpty)
              TextButton(
                onPressed: () => setState(() {
                  _pickedIds.clear();
                  _draw = null;
                  _drawKey = null;
                }),
                style: TextButton.styleFrom(
                  foregroundColor: _C.muted,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('Clear', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (picked.isEmpty)
          _emptyHint(
            icon: Icons.touch_app_outlined,
            title: 'Nothing picked yet',
            body: 'Open the list and tick the questions to ask. The order '
                'follows the bank, so two students picking the same set get '
                'the same paper.',
          )
        else
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _C.line),
            ),
            child: Column(
              children: [
                for (var i = 0; i < min(picked.length, 4); i++) ...[
                  if (i > 0) const Divider(height: 1, color: _C.line),
                  _pickedRow(picked[i], i + 1),
                ],
                if (picked.length > 4)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'and ${picked.length - 4} more…',
                        style: const TextStyle(
                          fontSize: 11,
                          color: _C.muted,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _scopedMcqs.isEmpty ? null : _openPicker,
            icon: const Icon(Icons.edit_note_rounded, size: 19),
            label: Text(
              picked.isEmpty
                  ? 'Choose questions'
                  : 'Manage questions (${picked.length})',
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              foregroundColor: _C.primary,
              side: const BorderSide(color: _C.primaryLine),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _pickedRow(HighSchoolQuestion question, int position) {
    final text = (question.mcqData?.text ?? '').trim();
    return InkWell(
      onTap: _openPicker,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 5, 2, 5),
        child: Row(
          children: [
            _QuestionIndexPill(position),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  mathText(
                    text.isEmpty ? '(no question text)' : text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: _C.ink,
                      height: 1.3,
                    ),
                  ),
                  if (question.chapterName.isNotEmpty)
                    Text(
                      question.chapterName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: _C.faint,
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => setState(() {
                _pickedIds.remove(question.id);
                _draw = null;
                _drawKey = null;
              }),
              tooltip: 'Remove question $position',
              icon: const Icon(Icons.close_rounded, size: 17),
              color: _C.faint,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            ),
          ],
        ),
      ),
    );
  }

  Widget _options() => Column(
        children: [
          _switchRow(
            icon: Icons.shuffle_on_outlined,
            title: 'Shuffle answer options',
            subtitle: _shuffleOptions
                ? 'A–D move around, so position gives nothing away.'
                : 'Choices stay in the order the bank lists them.',
            value: _shuffleOptions,
            onChanged: (value) => setState(() => _shuffleOptions = value),
          ),
          if (_plannedCount > 0) ...[
            const SizedBox(height: 6),
            _timeTile(),
          ],
        ],
      );

  Widget _timeTile() {
    final auto = _customMinutes == null;
    return InkWell(
      onTap: _openTimeSheet,
      borderRadius: BorderRadius.circular(13),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: _C.line),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: _C.primarySoft,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.timer_outlined,
                size: 17,
                color: _C.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Time limit',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _C.ink,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    auto ? 'Auto · one minute per question' : 'Set by hand',
                    style: const TextStyle(fontSize: 11, color: _C.muted),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: _C.primarySoft,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _C.primaryLine),
              ),
              child: Text(
                '$_plannedMinutes min',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: _C.primary,
                ),
              ),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: _C.faint,
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryStrip() {
    final count = _plannedCount;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF5F3FF), Color(0xFFEEF2FF)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0E7FF)),
      ),
      child: Row(
        children: [
          _summaryStat('$count', count == 1 ? 'question' : 'questions'),
          _summaryDivider(),
          _summaryStat('$_plannedMarks', _plannedMarks == 1 ? 'mark' : 'marks'),
          _summaryDivider(),
          _summaryStat('$_plannedMinutes', 'minutes'),
        ],
      ),
    );
  }

  Widget _summaryStat(String value, String label) => Expanded(
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: _C.primary,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 10.5, color: _C.muted),
            ),
          ],
        ),
      );

  Widget _summaryDivider() => Container(
        width: 1,
        height: 30,
        color: const Color(0xFFDDD6FE),
      );

  // ── wide-screen paper panel ──────────────────────────────────────────────

  Widget _paperPanel(List<HighSchoolQuestion> picked) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _C.line),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withOpacity(0.04),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _C.primarySoft,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.description_outlined,
                    color: _C.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your paper',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: _C.ink,
                        ),
                      ),
                      SizedBox(height: 1),
                      Text(
                        'Live summary',
                        style: TextStyle(fontSize: 11.5, color: _C.muted),
                      ),
                    ],
                  ),
                ),
                if (picked.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _C.successSoft,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${picked.length}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: _C.success,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _panelStat('${picked.length}', 'questions'),
                _panelStat('${picked.length}', 'marks'),
                _panelStat(
                  '${picked.isEmpty ? 0 : _plannedMinutes}',
                  'minutes',
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: _C.line),
            const SizedBox(height: 12),
            if (picked.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _C.line),
                ),
                child: Text(
                  _pickMode == _PickMode.manual
                      ? 'Pick questions and they will appear here, in paper '
                          'order.'
                      : 'Choose a source and a question count to see the '
                          'paper take shape.',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: _C.muted,
                    height: 1.4,
                  ),
                ),
              )
            else ...[
              for (var i = 0; i < min(picked.length, 5); i++) ...[
                if (i > 0) const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _QuestionIndexPill(i + 1),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          mathText(
                            (picked[i].mcqData?.text ?? '').trim(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: _C.ink,
                              height: 1.35,
                            ),
                          ),
                          if (picked[i].chapterName.isNotEmpty)
                            Text(
                              picked[i].chapterName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                color: _C.faint,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
              if (picked.length > 5)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'and ${picked.length - 5} more…',
                    style: const TextStyle(fontSize: 11, color: _C.muted),
                  ),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _previewPaper,
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('Review full paper'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    foregroundColor: _C.primary,
                    side: const BorderSide(color: _C.primaryLine),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      );

  Widget _panelStat(String value, String label) => Expanded(
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: _C.primary,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 10.5, color: _C.muted),
            ),
          ],
        ),
      );

  // ── bottom bar ───────────────────────────────────────────────────────────

  Widget _bottomBar(List<HighSchoolQuestion> picked) {
    final ready = picked.isNotEmpty && !_loadingPool;
    final hint = ready
        ? '${picked.length} mark${picked.length == 1 ? '' : 's'} · '
            '$_plannedMinutes min'
        : _bottomHint();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.08),
            blurRadius: 18,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      ready
                          ? '${picked.length} '
                              'question${picked.length == 1 ? '' : 's'} ready'
                          : 'Nothing to start yet',
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: _C.ink,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      hint,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: _C.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (ready) ...[
                IconButton(
                  onPressed: _previewPaper,
                  tooltip: 'Preview the paper',
                  icon: const Icon(Icons.visibility_outlined, size: 20),
                  style: IconButton.styleFrom(
                    backgroundColor: _C.primarySoft,
                    foregroundColor: _C.primary,
                    minimumSize: const Size(46, 46),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: ready ? _startExam : null,
                  icon: const Icon(Icons.play_arrow_rounded, size: 22),
                  label: const Text(
                    'Start',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _C.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFE8EAF1),
                    disabledForegroundColor: _C.faint,
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    elevation: 0,
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

  String _bottomHint() {
    if (_loadingPool) return 'Reading the question bank…';
    if (_error != null) {
      return _allQuestions.isEmpty
          ? 'Fix the error above'
          : 'Showing the last loaded questions';
    }
    if (_allQuestions.isEmpty) return 'Load a source above';
    if (_scopedMcqs.isEmpty) return 'Choose chapters with MCQs';
    if (_pickMode == _PickMode.manual) return 'Pick some questions';
    return 'Choose how many questions';
  }

  // ── shared pieces ────────────────────────────────────────────────────────

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    required Widget child,
  }) =>
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _C.line),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withOpacity(0.04),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _C.primarySoft,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: _C.primary, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: _C.ink,
                          letterSpacing: 0.1,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: _C.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      );

  Widget _statusPill(
    String label,
    Color color,
    Color background, {
    bool busy = false,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              SizedBox(
                width: 11,
                height: 11,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: color,
                ),
              )
            else
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                ),
              ),
            const SizedBox(width: 5),
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
      );

  Widget _miniStat(String value, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _C.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: _C.ink,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(fontSize: 10.5, color: _C.muted),
            ),
          ],
        ),
      );

  Widget _tinyPill(
    String text, {
    bool warning = false,
    bool muted = false,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: warning
              ? _C.warningSoft
              : (muted ? const Color(0xFFF1F5F9) : _C.primarySoft),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: warning
                ? const Color(0xFFFDE68A)
                : (muted ? _C.line : _C.primaryLine),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: warning ? _C.warning : (muted ? _C.muted : _C.primary),
          ),
        ),
      );

  Widget _inlineNote(
    IconData icon,
    String text,
    Color color,
    Color background,
  ) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                text,
                style: TextStyle(fontSize: 11, color: color, height: 1.35),
              ),
            ),
          ],
        ),
      );

  Widget _errorBox(String message) => Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: _C.dangerSoft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFECACA)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 18,
              color: _C.danger,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: _C.danger,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _emptyHint({
    required IconData icon,
    required String title,
    required String body,
    _HintTone tone = _HintTone.neutral,
  }) {
    final color = tone == _HintTone.warning ? _C.warning : _C.muted;
    final background =
        tone == _HintTone.warning ? _C.warningSoft : const Color(0xFFF8FAFC);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: tone == _HintTone.warning ? const Color(0xFFFDE68A) : _C.line,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _C.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: color,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldLabel(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: _C.muted,
          letterSpacing: 0.2,
        ),
      );

  InputDecoration _fieldDecoration() => InputDecoration(
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        hintStyle: const TextStyle(fontSize: 13, color: _C.faint),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _C.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _C.primary, width: 1.4),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFEDF0F7)),
        ),
      );

  Widget _stepButton(
    IconData icon,
    VoidCallback? onPressed,
    String tooltip,
  ) =>
      IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon, size: 18),
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: _C.primary,
          disabledBackgroundColor: Colors.white.withOpacity(0.5),
          disabledForegroundColor: _C.faint,
          side: const BorderSide(color: _C.primaryLine),
          minimumSize: const Size(38, 38),
          padding: EdgeInsets.zero,
        ),
      );

  Widget _presetChip(
    String label, {
    required bool selected,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? _C.primary : _C.primaryLine.withOpacity(0.6),
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: _C.primary.withOpacity(0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? _C.primary : _C.muted,
            ),
          ),
        ),
      );

  Widget _switchRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) =>
      InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 17, color: _C.muted),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _C.ink,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: _C.muted,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: value,
                onChanged: onChanged,
                activeColor: _C.primary,
              ),
            ],
          ),
        ),
      );

  // ── subjects per class ───────────────────────────────────────────────────

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
}

// ───────────────────────────────────────────────────────────────────────────
// Local widgets
// ───────────────────────────────────────────────────────────────────────────

enum _HintTone { neutral, warning }

class _LoadingLine extends StatelessWidget {
  const _LoadingLine({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          const SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: _C.muted),
          ),
        ],
      );
}

/// The time-limit value returned by the sheet. A wrapper is needed because
/// `null` means automatic and `null` is also what a dismissed sheet returns.
class _TimeChoice {
  const _TimeChoice(this.minutes);

  final int? minutes;
}

class _TimeLimitSheet extends StatefulWidget {
  const _TimeLimitSheet({
    required this.initialMinutes,
    required this.autoMinutes,
  });

  final int? initialMinutes;
  final int autoMinutes;

  @override
  State<_TimeLimitSheet> createState() => _TimeLimitSheetState();
}

class _TimeLimitSheetState extends State<_TimeLimitSheet> {
  static const int _maxMinutes = 180;

  int? _minutes;
  late int _custom;

  @override
  void initState() {
    super.initState();
    _minutes = widget.initialMinutes;
    _custom = (widget.initialMinutes ?? widget.autoMinutes)
        .clamp(1, _maxMinutes)
        .toInt();
  }

  void _choose(int value) => setState(() {
        _minutes = value.clamp(1, _maxMinutes).toInt();
        _custom = value.clamp(1, _maxMinutes).toInt();
      });

  @override
  Widget build(BuildContext context) {
    final auto = _minutes == null;
    final shown = auto ? widget.autoMinutes : _minutes!;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: _C.line,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: _C.primarySoft,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.timer_outlined,
                      color: _C.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 11),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Time limit',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: _C.ink,
                          ),
                        ),
                        SizedBox(height: 1),
                        Text(
                          'How long the student gets once the paper starts.',
                          style: TextStyle(fontSize: 11.5, color: _C.muted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Cancel',
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _choice(
                title: 'Automatic',
                subtitle:
                    '${widget.autoMinutes} min — one minute per question, at '
                    'least three.',
                selected: auto,
                onTap: () => setState(() => _minutes = null),
              ),
              const SizedBox(height: 8),
              _choice(
                title: 'Set a limit',
                subtitle: 'Choose an exact number of minutes.',
                selected: !auto,
                onTap: () => setState(() => _minutes = _custom),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: _C.line),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Minutes',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _C.muted,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '$shown',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: _C.primary,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: (_minutes ?? _custom)
                          .clamp(1, _maxMinutes)
                          .toDouble(),
                      min: 1,
                      max: _maxMinutes.toDouble(),
                      label: '$shown min',
                      onChanged: (value) => _choose(value.round()),
                    ),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        for (final minutes in const [
                          5,
                          10,
                          15,
                          20,
                          30,
                          45,
                          60,
                          90,
                        ])
                          ChoiceChip(
                            label: Text('$minutes'),
                            selected: !auto && _minutes == minutes,
                            onSelected: (_) => _choose(minutes),
                            selectedColor: _C.primarySoft,
                            backgroundColor: Colors.white,
                            side: BorderSide(
                              color: !auto && _minutes == minutes
                                  ? _C.primary
                                  : _C.line,
                            ),
                            labelStyle: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: !auto && _minutes == minutes
                                  ? _C.primary
                                  : _C.muted,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () =>
                      Navigator.of(context).pop(_TimeChoice(_minutes)),
                  icon: const Icon(Icons.check_rounded, size: 19),
                  label: Text(
                    auto
                        ? 'Use automatic (${widget.autoMinutes} min)'
                        : 'Use $_minutes minutes',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: _C.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
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

  Widget _choice({
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          decoration: BoxDecoration(
            color: selected ? _C.primarySoft : Colors.white,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected ? _C.primary : _C.line,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                size: 20,
                color: selected ? _C.primary : _C.faint,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: selected ? _C.primary : _C.ink,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: _C.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _ChapterSheet extends StatefulWidget {
  const _ChapterSheet({
    required this.chapters,
    required this.counts,
    required this.selected,
  });

  final List<ChapterInfo> chapters;
  final Map<String, int> counts;
  final Set<String> selected;

  @override
  State<_ChapterSheet> createState() => _ChapterSheetState();
}

class _ChapterSheetState extends State<_ChapterSheet> {
  late final Set<String> _selected = widget.selected.isEmpty
      ? widget.chapters.map((chapter) => chapter.chapterNumber).toSet()
      : {...widget.selected};

  bool get _allSelected => _selected.length == widget.chapters.length;

  void _toggle(String number) => setState(() {
        if (!_selected.remove(number)) _selected.add(number);
      });

  void _toggleAll(bool value) => setState(() {
        _selected.clear();
        if (value) {
          _selected.addAll(
            widget.chapters.map((chapter) => chapter.chapterNumber),
          );
        }
      });

  void _apply() {
    if (_selected.isEmpty) return;
    // Empty is the page's storage form of "every chapter".
    Navigator.of(context).pop(_allSelected ? <String>{} : {..._selected});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 8, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: _C.primarySoft,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.menu_book_rounded,
                    color: _C.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Chapters',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: _C.ink,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '${widget.chapters.length} listed · '
                        '${_selected.length} selected',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: _C.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Cancel',
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          CheckboxListTile(
            value: _allSelected,
            onChanged: (value) => _toggleAll(value ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: _C.primary,
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 18),
            title: const Text(
              'All chapters',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _C.ink,
              ),
            ),
            subtitle: const Text(
              'Include every chapter in this subject.',
              style: TextStyle(fontSize: 10.5, color: _C.muted),
            ),
          ),
          const Divider(height: 1, color: _C.line),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
              itemCount: widget.chapters.length,
              itemBuilder: (_, index) {
                final chapter = widget.chapters[index];
                final count = widget.counts[chapter.chapterNumber] ?? 0;
                final selected = _selected.contains(chapter.chapterNumber);
                return CheckboxListTile(
                  value: selected,
                  onChanged: (_) => _toggle(chapter.chapterNumber),
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: _C.primary,
                  dense: true,
                  title: Text(
                    chapter.chapterName.isEmpty
                        ? 'অধ্যায় ${chapter.chapterNumber}'
                        : chapter.chapterName,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: _C.ink,
                    ),
                  ),
                  subtitle: Text(
                    count == 0
                        ? 'No answerable MCQs'
                        : '$count answerable '
                            'MCQ${count == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: _C.muted,
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: _C.line)),
            ),
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _selected.isEmpty
                          ? 'Choose at least one chapter'
                          : _allSelected
                              ? 'All chapters included'
                              : '${_selected.length} of '
                                  '${widget.chapters.length} selected',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _C.muted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _selected.isEmpty ? null : _apply,
                    style: FilledButton.styleFrom(
                      backgroundColor: _C.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 13,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(_allSelected ? 'Use all' : 'Apply'),
                  ),
                ],
              ),
            ),
          ),
        ],
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
  late final Set<String> _picked =
      expandMcqStemPicks(widget.initial, widget.questions);

  /// Every question maps to the shared-stimulus run it belongs to.
  late final Map<String, List<HighSchoolQuestion>> _runs = {
    for (final unit in mcqStemUnits(widget.questions))
      for (final question in unit) question.id: unit,
  };

  final Set<String> _expanded = <String>{};

  String _search = '';

  /// Chapter number the list is limited to, or null for all of them.
  String? _chapter;
  bool _pickedOnly = false;

  List<_ChapterBucket> get _buckets {
    final byNumber = <String, _ChapterBucket>{};
    for (final question in widget.questions) {
      final bucket = byNumber.putIfAbsent(
        question.chapterNumber,
        () => _ChapterBucket(question.chapterNumber, question.chapterName),
      );
      bucket.total++;
      if (_picked.contains(question.id)) bucket.picked++;
    }
    final out = byNumber.values.toList()
      ..sort((a, b) => compareChapterNumbers(a.number, b.number));
    return out;
  }

  List<HighSchoolQuestion> get _visible {
    final needle = _search.trim().toLowerCase();
    return widget.questions.where((question) {
      if (_pickedOnly && !_picked.contains(question.id)) return false;
      if (_chapter != null && question.chapterNumber != _chapter) return false;
      if (needle.isEmpty) return true;
      return (question.mcqData?.text ?? '').toLowerCase().contains(needle) ||
          question.chapterName.toLowerCase().contains(needle);
    }).toList();
  }

  /// The position each chosen question will take in the paper.
  ///
  /// Bank order, the same order `_selected` produces, so the numbers here are
  /// the numbers the student will actually see.
  Map<String, int> get _paperPositions {
    final positions = <String, int>{};
    var n = 0;
    for (final question in widget.questions) {
      if (_picked.contains(question.id)) positions[question.id] = ++n;
    }
    return positions;
  }

  void _toggle(String id) => setState(() {
        final unit = _runs[id];
        if (unit == null) {
          if (!_picked.remove(id)) _picked.add(id);
          return;
        }
        final select = !_picked.contains(id);
        for (final question in unit) {
          if (select) {
            _picked.add(question.id);
          } else {
            _picked.remove(question.id);
          }
        }
      });

  void _setShown(bool select) => setState(() {
        final ids = <String>{};
        for (final question in _visible) {
          final unit = _runs[question.id];
          if (unit == null) {
            ids.add(question.id);
          } else {
            ids.addAll(unit.map((item) => item.id));
          }
        }
        for (final id in ids) {
          if (select) {
            _picked.add(id);
          } else {
            _picked.remove(id);
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
        color: _C.canvas,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
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
                    itemBuilder: (_, index) => _row(visible[index], positions),
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pick questions',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _C.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${widget.questions.length} MCQ'
                    '${buckets.length > 1 ? ' across ${buckets.length} chapters' : ''}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: _C.muted,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
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
              onChanged: (value) => setState(() => _search = value),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                hintText: 'Search the question text…',
                hintStyle: const TextStyle(fontSize: 12.5, color: _C.faint),
                prefixIcon: const Icon(
                  Icons.search,
                  size: 18,
                  color: _C.faint,
                ),
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
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _C.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: _C.primary,
                    width: 1.4,
                  ),
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
                    for (final bucket in buckets)
                      _chapterChip(
                        bucket.name.isEmpty
                            ? 'অধ্যায় ${bucket.number}'
                            : bucket.name,
                        bucket.number,
                        bucket.total,
                        picked: bucket.picked,
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
                  style: TextButton.styleFrom(
                    foregroundColor: _C.primary,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(allShownPicked ? 'Clear shown' : 'Select shown'),
                ),
                if (_picked.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(_picked.clear),
                    style: TextButton.styleFrom(
                      foregroundColor: _C.muted,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Clear all'),
                  ),
              ],
            ),
          ],
        ),
      );

  Widget _chapterChip(
    String label,
    String? number,
    int total, {
    int picked = 0,
  }) {
    final selected = _chapter == number;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _chapter = selected ? null : number),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? _C.primary : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? _C.primary : _C.line,
            ),
          ),
          child: Text(
            picked > 0 ? '$label · $picked/$total' : '$label · $total',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : _C.muted,
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
          color: on ? _C.primary.withOpacity(0.10) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: on ? _C.primary : _C.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              on ? Icons.check_circle : Icons.circle_outlined,
              size: 14,
              color: on ? _C.primary : _C.faint,
            ),
            const SizedBox(width: 6),
            Text(
              'Picked only (${_picked.length})',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: on ? _C.primary : _C.muted,
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
              Icon(
                _pickedOnly ? Icons.checklist_rounded : Icons.search_off,
                size: 40,
                color: _C.faint,
              ),
              const SizedBox(height: 12),
              Text(
                _pickedOnly
                    ? 'Nothing picked yet.'
                    : 'No question matches "$_search".',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: _C.muted),
              ),
            ],
          ),
        ),
      );

  Widget _row(HighSchoolQuestion question, Map<String, int> positions) {
    final on = _picked.contains(question.id);
    final open = _expanded.contains(question.id);
    final data = question.mcqData;
    final options = data?.options ?? const <String>[];
    final correct = (data?.correctAns ?? '').trim();
    final position = positions[question.id];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: on ? _C.primary.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: on ? _C.primary : _C.line,
          width: on ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => _toggle(question.id),
            borderRadius: BorderRadius.circular(13),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 0, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    on
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    size: 20,
                    color: on ? _C.primary : _C.faint,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        mathText(
                          (data?.text ?? '').trim(),
                          maxLines: open ? null : 2,
                          overflow: open ? null : TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: _C.ink,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (position != null) _QuestionIndexPill(position),
                            if (question.chapterName.isNotEmpty)
                              Text(
                                question.chapterName,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: _C.faint,
                                ),
                              ),
                            if (correct.isNotEmpty)
                              mathText(
                                'Answer: $correct',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: _C.success,
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
                      if (!_expanded.remove(question.id)) {
                        _expanded.add(question.id);
                      }
                    }),
                    icon: Icon(
                      open ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                    ),
                    tooltip: open ? 'Hide choices' : 'Show choices',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 34, minHeight: 34),
                    color: _C.faint,
                  ),
                ],
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(40, 0, 14, 12),
              child: options.isEmpty
                  ? const Text(
                      'This question has no options.',
                      style: TextStyle(fontSize: 12, color: _C.warning),
                    )
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
                                      ? _C.success
                                      : _C.faint,
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: mathText(
                                    option,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: option.trim() == correct
                                          ? _C.success
                                          : _C.muted,
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

  Widget _footer() => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withOpacity(0.08),
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
                    Text(
                      '${_picked.length} selected',
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: _C.ink,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      _picked.isEmpty
                          ? 'The paper would be empty'
                          : 'Asked in bank order',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: _C.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(_picked),
                  icon: const Icon(Icons.check_rounded, size: 20),
                  label: Text(
                    _picked.isEmpty ? 'Done' : 'Use ${_picked.length}',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: _C.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

/// The small `Q3` badge marking a question's place in the paper.
///
/// Shared by the inline paper on the page and the picker rows so both number
/// the same question the same way.
class _QuestionIndexPill extends StatelessWidget {
  const _QuestionIndexPill(this.number);

  final int number;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        decoration: BoxDecoration(
          color: _C.primary,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          'Q$number',
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: Colors.white,
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

/// The paper as it will be sat, with the teacher's answer key visible.
class _PreviewSheet extends StatelessWidget {
  const _PreviewSheet({
    required this.questions,
    required this.minutes,
    required this.scrollController,
    required this.onStart,
  });

  final List<HighSchoolQuestion> questions;
  final int minutes;
  final ScrollController scrollController;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _C.canvas,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 12, 8, 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: _C.primarySoft,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.visibility_outlined,
                    color: _C.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Paper preview',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: _C.ink,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '${questions.length} '
                        'question${questions.length == 1 ? '' : 's'} · '
                        '${questions.length} '
                        'mark${questions.length == 1 ? '' : 's'} · $minutes min',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: _C.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              itemCount: questions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, index) => _card(questions[index], index),
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: _C.line)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Answers are highlighted for the teacher.',
                      style: TextStyle(fontSize: 11, color: _C.muted),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: onStart,
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    label: const Text('Start this paper'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _C.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 13,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
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

  Widget _card(HighSchoolQuestion question, int index) {
    final data = question.mcqData;
    final options = data?.options ?? const <String>[];
    final correct = (data?.correctAns ?? '').trim();
    final text = (data?.text ?? '').trim();
    final previous = index == 0 ? null : questions[index - 1];
    final opensStem = question.opensMcqStemGroup(previous);
    final sharesStem = question.sharesMcqStemWith(previous);
    final stem = opensStem
        ? HighSchoolExportService.stemWithNumbers(
            question.mcqStemText,
            HighSchoolExportService.mcqStemRunNumbers(questions, index),
          ).trim()
        : '';
    final chapter = question.chapterName.trim();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _QuestionIndexPill(index + 1),
              const SizedBox(width: 8),
              if (chapter.isNotEmpty)
                Expanded(
                  child: Text(
                    chapter,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: _C.faint,
                    ),
                  ),
                ),
            ],
          ),
          if (stem.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: _C.primarySoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: mathText(
                stem,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: _C.primaryDeep,
                  height: 1.4,
                ),
              ),
            ),
          ],
          if (!sharesStem && question.mcqStemImageUrl.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            _previewImage(question.mcqStemImageUrl),
          ],
          const SizedBox(height: 8),
          mathText(
            text.isEmpty ? '(no question text)' : text,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: _C.ink,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 9),
          for (var i = 0; i < options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: options[i].trim() == correct
                          ? _C.success
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _letter(i),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: options[i].trim() == correct
                            ? Colors.white
                            : _C.muted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: mathText(
                      options[i],
                      style: TextStyle(
                        fontSize: 12.5,
                        color: options[i].trim() == correct
                            ? _C.success
                            : _C.ink.withOpacity(0.82),
                        fontWeight: options[i].trim() == correct
                            ? FontWeight.w700
                            : FontWeight.normal,
                        height: 1.35,
                      ),
                    ),
                  ),
                  if (options[i].trim() == correct)
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 17,
                      color: _C.success,
                    ),
                ],
              ),
            ),
          if (correct.isEmpty)
            const Text(
              'No correct option recorded for this question.',
              style: TextStyle(fontSize: 11, color: _C.warning),
            ),
        ],
      ),
    );
  }

  Widget _previewImage(String rawUrl) {
    final url = HighSchoolExportService.resolveImageUrl(rawUrl);
    if (url.isEmpty) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        url,
        width: double.infinity,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const SizedBox(
            height: 120,
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        },
        errorBuilder: (_, __, ___) => Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _C.dangerSoft,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFFECACA)),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.broken_image_outlined,
                size: 17,
                color: _C.danger,
              ),
              SizedBox(width: 7),
              Expanded(
                child: Text(
                  'The question image could not be loaded.',
                  style: TextStyle(fontSize: 11, color: _C.danger),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _letter(int index) => String.fromCharCode(65 + index);
}
