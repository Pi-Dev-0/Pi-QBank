import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/highschool_question.dart';
import '../services/highschool_qbank_service.dart';
import '../services/highschool_export_service.dart';
import '../pages/question_paper_preview_page.dart';
import '../widgets/custom_app_bar.dart';
import '../config/app_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Colour & design tokens
// ─────────────────────────────────────────────────────────────────────────────

const _kPrimary = Color(0xFF5C35E3); // vibrant indigo-violet
const _kAccent = Color(0xFF00C6AB); // teal-mint accent
const _kCqColor = Color(0xFF3A7BF7); // blue for CQ
const _kMcqColor = Color(0xFFE86339); // warm orange for MCQ
const _kRqColor = Color(0xFF0E9F6E); // green for short questions (SQ)
const _kBg = Color(0xFFF4F3FF);
const _kCardBg = Colors.white;
const _kDarkText = Color(0xFF1E1B3A);
const _kSubText = Color(0xFF6B6880);

// ─────────────────────────────────────────────────────────────────────────────
// Available options
// ─────────────────────────────────────────────────────────────────────────────

const _kClasses = [
  'Class 6',
  'Class 7',
  'Class 8',
  'Class (9-10) SSC',
  'Class (11-12) HSC',
];

const _kSubjectsByClass = {
  'Class 6': [
    'সাধারণ গণিত',
    'বিজ্ঞান',
    'বাংলা',
    'English',
  ],
  'Class 7': [
    'সাধারণ গণিত',
    'বিজ্ঞান',
    'বাংলা',
    'English',
  ],
  'Class 8': [
    'সাধারণ গণিত',
    'বিজ্ঞান',
    'বাংলা',
    'English',
  ],
  'Class (9-10) SSC': [
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
  'Class (11-12) HSC': [
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

/// The classes the way a paper writes them.
///
/// A display name only: the bank stores (and the endpoint filters on) the
/// canonical label in [_kClasses], and the picker keeps listing that label. This
/// map is only what the printed শ্রেণি line puts on the paper.
const _kClassLabels = {
  'Class 6': 'ষষ্ঠ',
  'Class 7': 'সপ্তম',
  'Class 8': 'অষ্টম',
  'Class (9-10) SSC': 'নবম-দশম',
  'Class (11-12) HSC': 'একাদশ-দ্বাদশ',
};

/// The name to print for [className] — its paper name when the picker set it,
/// and the value itself when it is a hand-typed section like `অষ্টম (ক)`.
///
/// Only the printed শ্রেণি field uses this. The picker itself keeps listing the
/// canonical labels ([_kClasses]), which are what the bank and the fetch calls
/// speak.
String _classLabel(String className) => _kClassLabels[className] ?? className;

// ─────────────────────────────────────────────────────────────────────────────
// Page entry point
// ─────────────────────────────────────────────────────────────────────────────

class HighSchoolQPaperGeneratorPage extends StatefulWidget {
  const HighSchoolQPaperGeneratorPage({super.key});

  @override
  State<HighSchoolQPaperGeneratorPage> createState() =>
      _HighSchoolQPaperGeneratorPageState();
}

class _HighSchoolQPaperGeneratorPageState
    extends State<HighSchoolQPaperGeneratorPage> with TickerProviderStateMixin {
  // ── Step tracking ──────────────────────────────────────────────────────────
  int _currentStep = 0; // 0 = filter, 1 = picker, 2 = export HTML

  // ── Step 1 state ──────────────────────────────────────────────────────────
  String? _selectedClass;
  String? _selectedSubject;
  List<ChapterInfo> _availableChapters = [];
  final Set<String> _selectedChapterNumbers = {};
  bool _loadingChapters = false;

  // ── Step 2 state ──────────────────────────────────────────────────────────
  List<HighSchoolQuestion> _fetchedQuestions = [];
  bool _loadingQuestions = false;
  final Map<String, bool> _expandedCards = {};

  /// Chapters whose question cards the picker has folded away, by chapter
  /// number.
  ///
  /// Only the cards are hidden: the header stays, with its counts, so the group
  /// can be opened again. Kept across filters and searches, because it describes
  /// how the reader has folded the list, not what the query is.
  final Set<String> _collapsedChapters = {};

  /// Chapters the picker is showing. Empty means all of them, so the default is
  /// never a surprising filter.
  final Set<String> _pickerChapterFilter = {};

  /// One-line summary of the paper so far, shown above the section editor.
  /// Search box for the chapter chips in step 1.
  final _chapterSearchCtrl = TextEditingController();
  String _chapterQuery = '';

  /// Which question type the picker is showing.
  _PickFilter _pickFilter = _PickFilter.all;
  final _pickSearchCtrl = TextEditingController();
  String _pickSearchQuery = '';

  /// How many questions the "এলোমেলো নির্বাচন" bar should draw.
  final _randomCqCtrl = TextEditingController();
  final _randomMcqCtrl = TextEditingController();
  final _randomRqCtrl = TextEditingController();

  // ── Step 3 state ──────────────────────────────────────────────────────────
  final _schoolCtrl = TextEditingController();
  final _examCtrl = TextEditingController(text: 'বার্ষিক পরীক্ষা ২০২৬');
  final _subjectCtrl = TextEditingController();
  final _classCtrl = TextEditingController();
  final _timeCtrl = TextEditingController(text: '২ ঘন্টা ৩০ মিনিট');
  final _marksCtrl = TextEditingController();

  /// "যেকোনো N টি প্রশ্নের উত্তর দাও" — leave blank (or 0) to omit the note.
  final _cqAnswerAnyCtrl = TextEditingController();

  /// The instruction the paper carries for the CQ block.
  ///
  /// The field holds a count, so the note is written out here: a bare "5" in
  /// the box means "যেকোনো ৫ টি প্রশ্নের উত্তর দাও" on the sheet. A blank
  /// box — or a zero — means the paper carries no such instruction at all.
  /// Anything that is not a number is taken as the reader's own wording and
  /// printed as it stands.
  String get _cqInstruction {
    final text = _cqAnswerAnyCtrl.text.trim();
    if (text.isEmpty) return '';
    final count = int.tryParse(text);
    if (count == null) return text;
    if (count <= 0) return '';
    return 'যেকোনো ${_bengaliNumber(count)} টি প্রশ্নের উত্তর দাও';
  }

  /// [number] written the way a paper writes it.
  static String _bengaliNumber(int number) {
    const digits = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];
    return '$number'
        .split('')
        .map((d) => digits[int.parse(d)])
        .join();
  }

  /// How stem images are sized in the HTML paper.
  StemImageSize _imageSize = StemImageSize.medium;

  /// How CQ questions are arranged (single or double column).
  QuestionLayout _cqLayout = QuestionLayout.single;

  /// How MCQ questions are arranged (single or double column).
  QuestionLayout _mcqLayout = QuestionLayout.doubleColumn;

  /// Short questions stay single-column by default: they are one line each, so
  /// two columns only helps when there are many of them.
  QuestionLayout _rqLayout = QuestionLayout.single;

  /// How far every text size in the paper is moved from the size it was tuned
  /// at — one point per step.
  ///
  /// The step moves every size together: masthead, section banners, question
  /// text and the marks; the sheet carries it as `calc(… + Npt)`.
  double _fontStep = 0;

  /// The range the control allows. Below −3 the text stops being comfortable on
  /// paper; +6 is already half again the height of a paper at 0.
  static const double _fontStepMin = -3;
  static const double _fontStepMax = 6;

  /// The face the HTML sheet is set in. See [PaperFont].
  PaperFont _paperFont = PaperFont.hindSiliguri;

  // ── Animation ─────────────────────────────────────────────────────────────
  late final AnimationController _stepAnim = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 400));
  late final Animation<double> _fadeAnim =
      CurvedAnimation(parent: _stepAnim, curve: Curves.easeInOut);

  // ── Service ───────────────────────────────────────────────────────────────
  // Replace with your deployed Apps Script URL
  late final HighSchoolQBankService _service = HighSchoolQBankService(
    scriptUrl: AppConfig.highSchoolQBankApi,
  );

  @override
  void initState() {
    super.initState();
    _stepAnim.forward();
  }

  @override
  void dispose() {
    _stepAnim.dispose();
    _schoolCtrl.dispose();
    _examCtrl.dispose();
    _subjectCtrl.dispose();
    _classCtrl.dispose();
    _timeCtrl.dispose();
    _marksCtrl.dispose();
    _cqAnswerAnyCtrl.dispose();
    _randomCqCtrl.dispose();
    _randomMcqCtrl.dispose();
    _randomRqCtrl.dispose();
    _chapterSearchCtrl.dispose();
    _pickSearchCtrl.dispose();
    super.dispose();
  }

  // ── Derived counters ──────────────────────────────────────────────────────

  List<HighSchoolQuestion> get _selectedQuestions =>
      _fetchedQuestions.where((q) => q.isSelected).toList();

  // ── Question sets ────────────────────────────────────────────────────────
  //
  // A paper can be arranged as two variants ("ক" / "খ") so nearby students
  // are not handed the same question order. Both sets go into one HTML file.

  /// When false the paper is a single set, exactly as before.
  bool _twoSets = false;

  /// Order the sections are printed in. Defaults to the paper's original
  /// arrangement: CQ, then the short questions, then MCQ.
  final List<_SectionKind> _sectionOrder = [
    _SectionKind.cq,
    _SectionKind.rq,
    _SectionKind.mcq,
  ];

  /// The same order in the export service's vocabulary.
  ///
  /// [_SectionKind] is the app's own enum; the service takes [PaperSection] so
  /// every format can be handed the order the reader dragged the blocks into.
  List<PaperSection> get _paperSectionOrder => [
        for (final kind in _sectionOrder)
          if (kind.isCq)
            PaperSection.cq
          else if (kind.isMcq)
            PaperSection.mcq
          else
            PaperSection.rq,
      ];

  /// Sections that actually hold questions, in the user's order.
  ///
  /// An empty section is left out of the list rather than shown greyed out, so
  /// a drag always moves something the reader can see.
  List<_SectionKind> get _activeSections =>
      _sectionOrder.where((k) => _questionsOf(k).isNotEmpty).toList();

  /// The বাংলা letter a section is headed with.
  ///
  /// Assigned by position, not by question type. The sections can be dragged
  /// into any order, so whichever one comes first is ক বিভাগ, the next খ, and
  /// so on. Tying the letter to the type would print two "ক বিভাগ"s the moment
  /// the reader moved a section.
  String _sectionLetter(_SectionKind kind) {
    final i = _activeSections.indexOf(kind);
    return const ['\u0995', '\u0996', '\u0997'][i < 0 ? 0 : i];
  }

  List<HighSchoolQuestion> _questionsOf(_SectionKind kind) {
    if (kind.isCq) return _selectedCqs;
    if (kind.isMcq) return _selectedMcqs;
    return _selectedShorts;
  }

  /// Marks in a section, summed the same way as the grand total.
  int _marksOf(_SectionKind kind) =>
      _questionsOf(kind).fold(0, (sum, q) => sum + q.totalMarks);

  /// True when CQ is immediately followed by the short questions.
  ///
  /// The merged two-column flow only exists while the two types are
  /// neighbours: they are emitted as one continuous run of blocks, so anything
  /// placed between them would have to be pulled back out of that flow.
  /// Separating them by dragging therefore turns the merge off, and the paper
  /// falls back to two ordinary sections in the order chosen here.
  bool get _mergesCqAndShorts {
    final order = _activeSections;
    for (var i = 0; i + 1 < order.length; i++) {
      // Either way round. Placing the short questions first should not end the
      // shared flow: the reader asked for one continuous run of questions, and
      // the order they chose only decides where the CQ part starts.
      if ((order[i].isCq && order[i + 1].isRq) ||
          (order[i].isRq && order[i + 1].isCq)) {
        return true;
      }
    }
    return false;
  }

  /// Names shown on each set's banner.
  final List<TextEditingController> _setLabelControllers = [
    TextEditingController(text: 'ক'),
    TextEditingController(text: 'খ'),
  ];

  /// The labels in play, in order. One entry when [twoSets] is off.
  List<String> get _setLabels => _twoSets
      ? [0, 1].map((i) => _setLabelControllers[i].text.trim()).toList()
      : [''];

  /// Selected questions belonging to the set at [index].
  ///
  /// Shared with the exports: an empty set mirrors the whole paper rather than
  /// printing a blank sheet, so the count shown here is the count that prints.
  List<HighSchoolQuestion> _questionsForSet(int index) =>
      HighSchoolExportService.questionsForSet(
        _selectedQuestions,
        _twoSets ? _setLabels : const [],
        index,
      );

  List<HighSchoolQuestion> get _selectedCqs =>
      _selectedQuestions.where((q) => q.isCq).toList();

  List<HighSchoolQuestion> get _selectedMcqs =>
      _selectedQuestions.where((q) => q.isMcq).toList();

  List<HighSchoolQuestion> get _selectedShorts =>
      _selectedQuestions.where((q) => q.isShort).toList();

  int get _totalCqs => _fetchedQuestions.where((q) => q.isCq).length;
  int get _totalMcqs => _fetchedQuestions.where((q) => q.isMcq).length;
  int get _totalShorts => _fetchedQuestions.where((q) => q.isShort).length;

  /// Move [question] into [setIndex], or out of every set when it is already
  /// there and only one set is active.
  void _toggleQuestionSet(HighSchoolQuestion question, int setIndex) {
    final label = _setLabels[setIndex];
    if (label.isEmpty) return;

    if (question.setLabel == label) {
      // Tapping the active set again returns the question to "no set", which
      // is where every question starts.
      question.setLabel = _twoSets ? '' : label;
    } else {
      question.setLabel = label;
    }
    setState(() {});
  }

  /// Deal the selected questions alternately between the sets.
  ///
  /// Alternating rather than dealing in blocks keeps each set's *shape* close
  /// to the other, so the two papers look alike and neither runs long. With
  /// two sets this also means both always receive a question of each type in
  /// roughly the same order.
  void _splitSelectedEvenly() {
    final selected = _selectedQuestions;
    if (!_twoSets || selected.length < 2) return;
    for (var i = 0; i < selected.length; i++) {
      selected[i].setLabel = _setLabels[i % 2];
    }
    setState(() {});
  }

  /// Put every selected question into the first set.
  void _assignAllToFirstSet() {
    if (!_twoSets) return;
    for (final q in _selectedQuestions) {
      q.setLabel = _setLabels.first;
    }
    setState(() {});
  }

  /// Ids that appear more than once in the loaded questions.
  ///
  /// Apps Script rejects duplicate ids on upload, but the sheet can still be
  /// edited by hand, and two rows sharing an id would otherwise share one
  /// expand/collapse state — tapping one question would toggle another.
  Set<String> get _duplicateIds {
    final counts = <String, int>{};
    for (final q in _fetchedQuestions) {
      if (q.id.isEmpty) continue;
      counts[q.id] = (counts[q.id] ?? 0) + 1;
    }
    return {
      for (final e in counts.entries)
        if (e.value > 1) e.key
    };
  }

  /// Stable per-question UI key: the id when it is unique, otherwise a
  /// composite that still identifies the row.
  String _cardKey(HighSchoolQuestion q, int index) {
    if (q.id.isNotEmpty && !_duplicateIds.contains(q.id)) return q.id;
    return '~${q.className}|${q.subject}|${q.chapterNumber}|'
        '${q.chapterName}|${q.questionType}|${q.stemText}|$index';
  }

  int get _totalSelectedMarks =>
      _selectedQuestions.fold(0, (sum, q) => sum + q.totalMarks);

  /// Marks split by question type, plus how many of them the current filter or
  /// search is keeping off screen.
  ///
  /// One total across three types cannot be checked by eye. Filter the picker
  /// to CQ and the total still counts every selected MCQ and RQ, so the marks
  /// on the visible cards stop adding up to it — which looks exactly like a
  /// broken sum even though the paper would carry all of them.
  ({int cq, int mcq, int rq, int hidden}) get _marksBreakdown {
    final visible = _visibleQuestions.toSet();
    var cq = 0, mcq = 0, rq = 0, hidden = 0;
    for (final q in _selectedQuestions) {
      final marks = q.totalMarks;
      if (q.isCq) {
        cq += marks;
      } else if (q.isMcq) {
        mcq += marks;
      } else if (q.isShort) {
        rq += marks;
      }
      if (!visible.contains(q)) hidden += marks;
    }
    return (cq: cq, mcq: mcq, rq: rq, hidden: hidden);
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  Future<void> _goToStep(int step) async {
    await _stepAnim.reverse();
    setState(() => _currentStep = step);
    _stepAnim.forward();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Step 1 logic
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _onClassChanged(String? value) async {
    setState(() {
      _selectedClass = value;
      _selectedSubject = null;
      _availableChapters = [];
      _selectedChapterNumbers.clear();
    });
  }

  Future<void> _onSubjectChanged(String? value) async {
    setState(() {
      _selectedSubject = value;
      _availableChapters = [];
      _selectedChapterNumbers.clear();
    });
    if (value != null && _selectedClass != null) {
      await _fetchChapters();
    }
  }

  Future<void> _fetchChapters() async {
    setState(() => _loadingChapters = true);
    try {
      final chapters = await _service.fetchChapters(
        className: _selectedClass!,
        subject: _selectedSubject!,
      );
      if (!mounted) return;
      setState(() => _availableChapters = chapters);
    } catch (e) {
      _showError('অধ্যায় লোড করতে ব্যর্থ: ${_friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _loadingChapters = false);
    }
  }

  Future<void> _fetchQuestions() async {
    if (_selectedClass == null || _selectedSubject == null) {
      _showError('দয়া করে ক্লাস ও বিষয় নির্বাচন করুন।');
      return;
    }
    setState(() => _loadingQuestions = true);
    try {
      final questions = await _service.fetchQuestions(
        className: _selectedClass!,
        subject: _selectedSubject!,
        chapters: _selectedChapterNumbers.isNotEmpty
            ? _selectedChapterNumbers.toList()
            : null,
      );
      if (questions.isEmpty) {
        _showError('কোনো প্রশ্ন পাওয়া যায়নি। অন্য ফিল্টার চেষ্টা করুন।');
        // Still on to the picker rather than stopping here: its empty list is
        // where a question can be written by hand, and that is exactly what a
        // subject with no rows needs.
        await _goToStep(1);
        return;
      }
      setState(() {
        // A hand-typed question is not in the sheet, so a re-fetch can never
        // return it. Carry the ones belonging to this class and subject across,
        // otherwise going back to widen the chapter filter would quietly throw
        // away the questions that were typed because the sheet had none.
        final typed = _fetchedQuestions
            .where((q) =>
                q.isManual &&
                q.className == _selectedClass &&
                q.subject == _selectedSubject)
            .toList();
        // A corrected row would otherwise come back exactly as the bank has it,
        // quietly throwing the correction away; matching by id keeps the paper
        // printing what was fixed.
        final corrected = {
          for (final q in _fetchedQuestions)
            if (q.isEdited) q.id: q,
        };
        _fetchedQuestions = [
          for (final q in questions) corrected[q.id] ?? q,
          ...typed,
        ];
        _expandedCards.clear();
      });
      await _goToStep(1);
    } catch (e) {
      _showError('প্রশ্ন লোড করতে ব্যর্থ: ${_friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _loadingQuestions = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Step 2 logic
  // ─────────────────────────────────────────────────────────────────────────

  /// The MCQs that print under one উদ্দীপক, each keyed by every id in its run.
  ///
  /// A shared intro is printed once, over the first question of the run, so half
  /// a run is not something the paper has a way to print — a shared question is
  /// never used on its own. The picker holds to that by selecting a run whole,
  /// which means it has to know which questions form one: the same walk the
  /// writers make, over the questions in the order the paper prints them
  /// (chapters in reading order, MCQs only, a new run wherever a question does
  /// not follow the one before it).
  ///
  /// Runs of one are left out: a question with an intro of its own, or with no
  /// intro at all, is shared with nobody.
  Map<String, List<HighSchoolQuestion>> _mcqStemRuns() {
    final byChapter = <String, List<HighSchoolQuestion>>{};
    for (final q in _fetchedQuestions) {
      if (!q.isMcq) continue;
      byChapter.putIfAbsent(q.chapterNumber, () => []).add(q);
    }

    final runs = <String, List<HighSchoolQuestion>>{};
    void record(List<HighSchoolQuestion> run) {
      if (run.length < 2) return;
      for (final q in run) {
        runs[q.id] = run;
      }
    }

    for (final number in byChapter.keys.toList()..sort(compareChapterNumbers)) {
      final mcqs = byChapter[number]!;
      var run = <HighSchoolQuestion>[mcqs.first];
      for (var i = 1; i < mcqs.length; i++) {
        if (mcqs[i].sharesMcqStemWith(mcqs[i - 1])) {
          run.add(mcqs[i]);
        } else {
          record(run);
          run = [mcqs[i]];
        }
      }
      record(run);
    }
    return runs;
  }

  /// Apply one selection to a question and to everything sharing its উদ্দীপক.
  ///
  /// Assumes the caller has already opened a [setState]: every selection change
  /// the picker makes goes through here, so no path — a ticked box, a set chip,
  /// select-all over a filtered list — can leave half a run selected.
  void _applySelection(
    HighSchoolQuestion q,
    bool selected,
    Map<String, List<HighSchoolQuestion>> runs,
  ) {
    q.isSelected = selected;
    for (final other in runs[q.id] ?? const <HighSchoolQuestion>[]) {
      other.isSelected = selected;
    }
  }

  void _toggleQuestion(HighSchoolQuestion q) {
    final runs = _mcqStemRuns();
    setState(() => _applySelection(q, !q.isSelected, runs));
  }

  /// The questions the picker is currently showing: filtered by type and
  /// narrowed by the search box.
  ///
  /// Selection itself lives on the question, so filtering never hides a
  /// selection — the counter bar still reports every selected question.
  List<HighSchoolQuestion> get _visibleQuestions {
    final query = _pickSearchQuery.trim().toLowerCase();
    return _fetchedQuestions.where((q) {
      if (!_pickFilter.matches(q)) return false;
      // An empty filter means every chapter, which keeps the default from
      // silently hiding anything.
      if (_pickerChapterFilter.isNotEmpty &&
          !_pickerChapterFilter.contains(q.chapterNumber)) {
        return false;
      }
      if (query.isEmpty) return true;
      return q.stemText.toLowerCase().contains(query) ||
          q.chapterName.toLowerCase().contains(query) ||
          q.questionType.toLowerCase().contains(query) ||
          (q.mcqData?.text.toLowerCase().contains(query) ?? false) ||
          (q.shortData?.text.toLowerCase().contains(query) ?? false) ||
          q.cqSubQuestions.any((s) => s.text.toLowerCase().contains(query));
    }).toList();
  }

  /// True when a filter or search is narrowing the list, so the select-all
  /// buttons can say they only affect what is on screen.
  bool get _pickIsNarrowed =>
      _pickFilter != _PickFilter.all || _pickSearchQuery.trim().isNotEmpty;

  void _selectAll() {
    final runs = _mcqStemRuns();
    setState(() {
      for (final q in _visibleQuestions) {
        _applySelection(q, true, runs);
      }
    });
  }

  /// Unticks what is on screen — and with it the run of any shared MCQ in it, so
  /// a partner hidden by the filter cannot be left behind on its own.
  void _deselectAll() {
    final runs = _mcqStemRuns();
    setState(() {
      for (final q in _visibleQuestions) {
        _applySelection(q, false, runs);
      }
    });
  }

  /// Draw [count] questions at random, spread as evenly as possible across the
  /// types that have anything to offer.
  ///
  /// The spread is what makes the draw useful: asking for a dozen questions and
  /// getting a dozen of one kind is a poor paper. The types present are dealt
  /// round-robin — one CQ, one MCQ, one RQ, then round again — so each type
  /// comes out within one of the others, and a type that is short simply runs
  /// out while the others carry on.
  ///
  /// An MCQ run prints under one উদ্দীপক, so the run is the unit drawn here: the
  /// whole run is taken rather than one question out of it, and the run's size
  /// counts against the type's share. A run larger than the share is taken only
  /// when it is the smallest the type has — the alternative is a run that would
  /// blow the count wide open.
  List<HighSchoolQuestion> _randomQuestions(
      int cqCount, int mcqCount, int rqCount) {
    final pools = <_PickFilter, List<HighSchoolQuestion>>{
      _PickFilter.cq: _fetchedQuestions.where((q) => q.isCq).toList(),
      _PickFilter.mcq: _fetchedQuestions.where((q) => q.isMcq).toList(),
      _PickFilter.rq: _fetchedQuestions.where((q) => q.isShort).toList(),
    };
    pools.removeWhere((_, pool) => pool.isEmpty);
    if (pools.isEmpty &&
        cqCount <= 0 &&
        mcqCount <= 0 &&
        rqCount <= 0) return const [];

    final order = pools.keys.toList();
    final share = <_PickFilter, int>{
      _PickFilter.cq: cqCount,
      _PickFilter.mcq: mcqCount,
      _PickFilter.rq: rqCount,
    };
    share.removeWhere((_, v) => v <= 0);

    final rng = Random();
    final drawn = <HighSchoolQuestion>[];
    for (final type in order) {
      final want = share[type] ?? 0;
      if (want == 0) continue;
      final pool = [...pools[type]!]..shuffle(rng);
      if (type == _PickFilter.mcq) {
        drawn.addAll(_drawMcqRuns(pool, want, rng));
      } else {
        drawn.addAll(pool.take(want));
      }
    }
    return drawn;
  }

  /// Draw MCQ runs until [want] questions have been covered.
  List<HighSchoolQuestion> _drawMcqRuns(
      List<HighSchoolQuestion> pool, int want, Random rng) {
    final runs = _mcqStemRuns();
    final seen = <String>{};
    final units = <List<HighSchoolQuestion>>[];
    for (final q in pool) {
      final run = runs[q.id];
      if (run != null && run.length > 1) {
        // The first id identifies the run; the rest are already in it.
        if (seen.add(run.first.id)) units.add(run);
      } else {
        units.add([q]);
      }
    }
    units.shuffle(rng);

    final remaining = [...units];
    final drawn = <HighSchoolQuestion>[];
    var taken = 0;
    while (taken < want && remaining.isNotEmpty) {
      // Prefer a run that fits the share still outstanding; otherwise take the
      // smallest, so a single large run cannot swallow the whole share.
      var index = remaining.indexWhere((u) => taken + u.length <= want);
      if (index < 0) {
        final shortest =
            remaining.map((u) => u.length).reduce((a, b) => a < b ? a : b);
        index = remaining.indexWhere((u) => u.length == shortest);
      }
      final run = remaining.removeAt(index);
      drawn.addAll(run);
      taken += run.length;
    }
    return drawn;
  }

  /// Replace the current selection with a random draw of the asked-for size.
  void _pickRandomQuestions() {
    final cqCount = int.tryParse(_randomCqCtrl.text.trim()) ?? 0;
    final mcqCount = int.tryParse(_randomMcqCtrl.text.trim()) ?? 0;
    final rqCount = int.tryParse(_randomRqCtrl.text.trim()) ?? 0;

    if (cqCount <= 0 && mcqCount <= 0 && rqCount <= 0) {
      _showError('দয়া করে কমপক্ষে একটি ধরনের সংখ্যা লিখুন।');
      return;
    }

    final drawn = _randomQuestions(cqCount, mcqCount, rqCount);
    if (drawn.isEmpty) {
      _showError('নির্বাচন করার মতো প্রশ্ন নেই।');
      return;
    }

    final runs = _mcqStemRuns();
    setState(() {
      // Start from nothing: the number is what the reader asked for, so the
      // previous selection has to go or the two would be added together.
      for (final q in _fetchedQuestions) {
        _applySelection(q, false, runs);
      }
      for (final q in drawn) {
        _applySelection(q, true, runs);
      }
    });

    final parts = [
      if (_selectedCqs.isNotEmpty) 'সৃজনশীল ${_selectedCqs.length}টি',
      if (_selectedMcqs.isNotEmpty) 'বহুনির্বাচনি ${_selectedMcqs.length}টি',
      if (_selectedShorts.isNotEmpty) 'সংক্ষিপ্ত ${_selectedShorts.length}টি',
    ].join(', ');
    _showNotice(
        'এলোমেলো ${_selectedQuestions.length} টি প্রশ্ন নির্বাচন হয়েছে — $parts');
  }

  // ── Hand-typed questions ──────────────────────────────────────────────────

  /// Open the hand-entry sheet and file whatever comes back into the picker.
  ///
  /// Reached from the picker, including its empty state — which is where a
  /// subject with no rows at all ends up, so a question can always be written
  /// even when the bank has nothing to show.
  Future<void> _openManualQuestion() async {
    if (_selectedClass == null || _selectedSubject == null) {
      _showError('দয়া করে ক্লাস ও বিষয় নির্বাচন করুন।');
      return;
    }

    final question = await showModalBottomSheet<HighSchoolQuestion>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ManualQuestionSheet(
        className: _selectedClass!,
        subject: _selectedSubject!,
        chapters: _manualChapterChoices,
        // One chapter picked in step 1 means the question belongs to it; with
        // nothing picked, the sheet defaults to the first chapter it knows.
        initialChapter: _selectedChapterNumbers.length == 1
            ? _selectedChapterNumbers.first
            : null,
      ),
    );
    if (question == null || !mounted) return;
    _addManualQuestion(question);
  }

  /// The chapters the hand-entry sheet can file a question under.
  ///
  /// Everything the reader could be looking at: the chapters the subject has,
  /// plus any chapter a loaded question came from — the second set covers the
  /// case where the chapter list itself failed to load.
  List<ChapterInfo> get _manualChapterChoices {
    final byNumber = <String, String>{};
    for (final c in _availableChapters) {
      if (c.chapterNumber.trim().isNotEmpty) {
        byNumber[c.chapterNumber] = c.chapterName;
      }
    }
    for (final q in _fetchedQuestions) {
      if (q.chapterNumber.trim().isNotEmpty) {
        byNumber.putIfAbsent(q.chapterNumber, () => q.chapterName);
      }
    }
    return [
      for (final e in byNumber.entries)
        ChapterInfo(chapterNumber: e.key, chapterName: e.value),
    ]..sort((a, b) => compareChapterNumbers(a.chapterNumber, b.chapterNumber));
  }

  /// File a hand-typed question into the picker.
  ///
  /// It arrives selected: the only reason to type one is to print it.
  void _addManualQuestion(HighSchoolQuestion question) {
    setState(() {
      _fetchedQuestions = [..._fetchedQuestions, question];
      // A folded chapter would swallow the question just typed, and the sheet
      // never says which chapter it landed in.
      _collapsedChapters.remove(question.chapterNumber);
    });
    if (_currentStep == 0) {
      _goToStep(1);
    } else {
      _showInfo('প্রশ্নটি তালিকায় যোগ হয়েছে।');
    }
  }

  /// Open the hand-entry sheet on an existing question, pre-filled, and put the
  /// answer back in the list.
  ///
  /// Paper-only, exactly like a hand-typed question: the row keeps its id and the
  /// sheet keeps the text it was fetched with. An edit is how a question gets
  /// printed the way it should read, not how the bank gets corrected.
  Future<void> _openEditQuestion(HighSchoolQuestion question) async {
    final edited = await showModalBottomSheet<HighSchoolQuestion>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ManualQuestionSheet(
        className: _selectedClass ?? question.className,
        subject: _selectedSubject ?? question.subject,
        chapters: _manualChapterChoices,
        original: question,
      ),
    );
    if (edited == null || !mounted) return;

    setState(() {
      // The sheet was opened from this very object, so identity is the precise
      // match; the id is only a fallback in case the list was rebuilt meanwhile.
      final at = _fetchedQuestions.indexOf(question);
      final index = at >= 0
          ? at
          : _fetchedQuestions.indexWhere((q) => q.id == question.id);
      if (index < 0) {
        _fetchedQuestions = [..._fetchedQuestions, edited];
        return;
      }
      final wasExpanded = _expandedCards[_cardKey(question, index)] == true;
      _fetchedQuestions = [..._fetchedQuestions]..[index] = edited;
      // The card was open when the edit started; its text has just changed, so
      // carry the open state onto whatever key the card has now.
      if (wasExpanded) {
        _expandedCards[_cardKey(edited, index)] = true;
      }
    });
    _showInfo('প্রশ্নটি সম্পাদনা করা হয়েছে।');
  }

  void _toggleChapter(String chapterNumber) => setState(() {
        if (!_collapsedChapters.remove(chapterNumber)) {
          _collapsedChapters.add(chapterNumber);
        }
      });

  void _showInfo(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: _kAccent,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _proceedToGenerate() {
    if (_selectedQuestions.isEmpty) {
      _showError('অন্তত একটি প্রশ্ন নির্বাচন করুন।');
      return;
    }
    _subjectCtrl.text = _selectedSubject ?? '';
    // Step 3's শ্রেণি field writes the class the way a paper does. The canonical
    // label the picker listed stays behind for the fetch calls and the sheet.
    _classCtrl.text =
        _selectedClass == null ? '' : _classLabel(_selectedClass!);
    _marksCtrl.text = '$_totalSelectedMarks';
    _goToStep(2);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Step 3 — HTML generation & export
  // ─────────────────────────────────────────────────────────────────────────

  String _getBaseFileName() {
    final sub = _subjectCtrl.text.trim().isNotEmpty
        ? _subjectCtrl.text.trim()
        : 'QuestionPaper';
    final exam =
        _examCtrl.text.trim().isNotEmpty ? '_${_examCtrl.text.trim()}' : '';
    return '$sub$exam'.replaceAll(RegExp(r'[^\w\u0980-\u09FF-]'), '_');
  }

  Future<void> _exportHtml({bool open = true}) async {
    try {
      // A face the app ships is written into the file, so load it before the
      // sheet is built; see [HighSchoolExportService.preloadPaperFonts].
      await HighSchoolExportService.preloadPaperFonts();
      final stemImages = _imageSize.isVisible
          ? await HighSchoolExportService.prefetchStemImages(_selectedQuestions)
          : <String, Uint8List>{};
      final html = HighSchoolExportService.generateHtml(
        schoolName: _schoolCtrl.text,
        examName: _examCtrl.text,
        subject: _subjectCtrl.text,
        className: _classCtrl.text,
        time: _timeCtrl.text,
        totalMarks: _marksCtrl.text,
        questions: _selectedQuestions,
        imageBytes: stemImages,
        setLabels: _twoSets ? _setLabels : const [],
        sectionOrder: _paperSectionOrder,
        imageSize: _imageSize,
        cqLayout: _cqLayout,
        mcqLayout: _mcqLayout,
        rqLayout: _rqLayout,
        fontStep: _fontStep,
        font: _paperFont,
        cqInstruction: _cqInstruction,
      );
      final file = await HighSchoolExportService.saveFile(
        content: html,
        fileName: '${_getBaseFileName()}.html',
      );
      if (!mounted) return;
      if (open) {
        await HighSchoolExportService.openExportedFile(context, file);
      } else {
        await HighSchoolExportService.shareExportedFile(
          file,
          text: '${_examCtrl.text} - HTML Web Page',
        );
      }
    } catch (e) {
      _showError('HTML ফাইল তৈরি করতে সমস্যা: $e');
    }
  }

  /// Open the full-page live preview of the generated HTML.
  Future<void> _openLivePreview() async {
    if (_selectedQuestions.isEmpty) {
      _showError('প্রিভিউ করার জন্য অন্তত একটি প্রশ্ন নির্বাচন করুন।');
      return;
    }

    // Linux desktop and web have no WebView host, so the in-app preview cannot
    // run there. Fall back to opening the very same HTML in the system browser.
    if (!QuestionPaperPreviewPage.supportsWebView) {
      await _previewInSystemBrowser();
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QuestionPaperPreviewPage(
          schoolName: _schoolCtrl.text,
          examName: _examCtrl.text,
          subject: _subjectCtrl.text,
          className: _classCtrl.text,
          time: _timeCtrl.text,
          totalMarks: _marksCtrl.text,
          questions: _selectedQuestions,
          setLabels: _twoSets ? _setLabels : const [],
          sectionOrder: _paperSectionOrder,
          imageSize: _imageSize,
          cqLayout: _cqLayout,
          mcqLayout: _mcqLayout,
          rqLayout: _rqLayout,
          fontStep: _fontStep,
          font: _paperFont,
        ),
      ),
    );
  }

  /// Preview fallback for platforms without a WebView: write the preview HTML
  /// to a temp file and hand it to the default browser.
  Future<void> _previewInSystemBrowser() async {
    await HighSchoolExportService.preloadPaperFonts();
    final stemImages = _imageSize.isVisible
        ? await HighSchoolExportService.prefetchStemImages(_selectedQuestions)
        : <String, Uint8List>{};
    final html = HighSchoolExportService.generateHtml(
      schoolName: _schoolCtrl.text,
      examName: _examCtrl.text,
      subject: _subjectCtrl.text,
      className: _classCtrl.text,
      time: _timeCtrl.text,
      totalMarks: _marksCtrl.text,
      questions: _selectedQuestions,
      imageBytes: stemImages,
      setLabels: _twoSets ? _setLabels : const [],
      sectionOrder: _paperSectionOrder,
      imageSize: _imageSize,
      cqLayout: _cqLayout,
      mcqLayout: _mcqLayout,
      rqLayout: _rqLayout,
      fontStep: _fontStep,
      font: _paperFont,
      cqInstruction: _cqInstruction,
      // Desktop-width layout, as in the in-app preview: the file opens in a
      // browser, and a phone-width one should still show the printed page.
      desktopMode: true,
    );
    final file = await HighSchoolExportService.saveFile(
      content: html,
      fileName: '${_getBaseFileName()}_preview.html',
    );
    if (!mounted) return;
    await HighSchoolExportService.openExportedFile(context, file);
  }

  /// Turn network and configuration failures into actionable messages.
  String _friendlyError(Object error) {
    if (error is QBankNotConfiguredException) {
      return 'সার্ভার ঠিকানা সেট করা নেই। '
          'HS_QBANK_API দিয়ে অ্যাপটি আবার বিল্ড করুন।';
    }
    final text = error.toString();
    if (text.contains('SocketException') ||
        text.contains('Failed host lookup') ||
        text.contains('Connection refused')) {
      return 'সার্ভারে পৌঁছানো যায়নি। ইন্টারনেট সংযোগ দেখুন।';
    }
    if (text.contains('HandshakeException') || text.contains('CERTIFICATE')) {
      return 'নিরাপদ সংযোগ (SSL) প্রতিষ্ঠা করা যায়নি।';
    }
    if (text.contains('timeout') || text.contains('TimeoutException')) {
      return 'সময়োত্তীর্ণ হয়েছে। সংযোগ দ্রুত নয়, আবার চেষ্টা করুন।';
    }
    return text;
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  /// A quiet confirmation, the same shape as [_showError] but green.
  void _showNotice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF0E9F6E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: CustomAppBar(
        title: 'প্রশ্নপত্র তৈরি করুন',
        actions: [
          if (_currentStep > 0)
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              tooltip: 'আগের ধাপ',
              onPressed: () => _goToStep(_currentStep - 1),
            ),
        ],
      ),
      body: Column(
        children: [
          _StepIndicator(currentStep: _currentStep),
          Expanded(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: _buildCurrentStep(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _buildStep1();
      case 1:
        return _buildStep2();
      case 2:
        return _buildStep3();
      default:
        return const SizedBox.shrink();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 1 — Filter & Selection
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStep1() {
    final subjects = _selectedClass != null
        ? (_kSubjectsByClass[_selectedClass] ?? <String>[])
        : <String>[];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
              icon: Icons.filter_list_rounded, label: 'ফিল্টার ও নির্বাচন'),
          const SizedBox(height: 16),

          // Section badge
          _InfoChip(icon: Icons.school_rounded, label: 'বিভাগ: উচ্চ মাধ্যমিক'),
          const SizedBox(height: 20),

          // Class dropdown
          _buildDropdown<String>(
            label: 'ক্লাস নির্বাচন করুন',
            icon: Icons.class_rounded,
            value: _selectedClass,
            items: _kClasses,
            displayText: (c) => c,
            onChanged: _onClassChanged,
          ),
          const SizedBox(height: 16),

          // Subject dropdown
          _buildDropdown<String>(
            label: 'বিষয় নির্বাচন করুন',
            icon: Icons.book_rounded,
            value: _selectedSubject,
            items: subjects,
            displayText: (s) => s,
            enabled: _selectedClass != null,
            onChanged: _onSubjectChanged,
          ),
          const SizedBox(height: 20),

          // Chapter chips
          _buildChapterSection(),
          const SizedBox(height: 28),

          // Fetch button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: _loadingQuestions
                ? const Center(
                    child: CircularProgressIndicator(color: _kPrimary))
                : ElevatedButton.icon(
                    icon: const Icon(Icons.cloud_download_rounded),
                    label: const Text('প্রশ্ন লোড করুন',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPrimary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 4,
                      shadowColor: _kPrimary.withOpacity(0.4),
                    ),
                    onPressed: _fetchQuestions,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    required IconData icon,
    required T? value,
    required List<T> items,
    required String Function(T) displayText,
    required ValueChanged<T?> onChanged,
    bool enabled = true,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 3))
        ],
      ),
      child: DropdownButtonFormField<T>(
        value: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: _kPrimary),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none),
          filled: true,
          fillColor: _kCardBg,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        items: items
            .map((item) => DropdownMenuItem<T>(
                  value: item,
                  child: Text(displayText(item)),
                ))
            .toList(),
        onChanged: enabled ? onChanged : null,
      ),
    );
  }

  /// Chapter chips for step 1.
  ///
  /// Several things were missing and all of them bit in practice: chapters came
  /// back in sheet order so `10` sorted before `2`, there was no way to select
  /// everything without tapping every chip, nothing said what an empty selection
  /// meant, and a subject with many chapters became an unreadable wall of chips.
  Widget _buildChapterSection() {
    if (_selectedClass == null || _selectedSubject == null) {
      return const SizedBox.shrink();
    }

    // Sorted numerically, so the list reads in the order a textbook does —
    // including a section like "2.2", which is a number too.
    final chapters = [..._availableChapters]
      ..sort((a, b) => compareChapterNumbers(a.chapterNumber, b.chapterNumber));

    final query = _chapterQuery.trim().toLowerCase();
    final shown = query.isEmpty
        ? chapters
        : chapters
            .where((c) =>
                c.chapterNumber.toLowerCase().contains(query) ||
                c.chapterName.toLowerCase().contains(query))
            .toList();

    final allSelected = chapters.isNotEmpty &&
        chapters
            .every((c) => _selectedChapterNumbers.contains(c.chapterNumber));
    final picked = _selectedChapterNumbers.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.menu_book_rounded, color: _kPrimary, size: 20),
            const SizedBox(width: 8),
            const Text('অধ্যায় নির্বাচন করুন',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: _kDarkText)),
            const Spacer(),
            if (chapters.isNotEmpty) ...[
              TextButton(
                onPressed: () => setState(() {
                  if (allSelected) {
                    _selectedChapterNumbers.clear();
                  } else {
                    _selectedChapterNumbers
                      ..clear()
                      ..addAll(chapters.map((c) => c.chapterNumber));
                  }
                }),
                child: Text(allSelected ? 'সব বাদ দিন' : 'সব নির্বাচন'),
              ),
              if (picked > 0)
                TextButton(
                  onPressed: () =>
                      setState(() => _selectedChapterNumbers.clear()),
                  child: const Text('বাদ দিন'),
                ),
            ],
          ],
        ),

        // Says plainly what an empty selection means, which used to be guesswork.
        if (chapters.isNotEmpty && picked == 0) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.check_circle_outline, size: 15, color: _kAccent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'কোনো অধ্যায় বাছাই না করলে সব ${chapters.length}টি অধ্যায় থেকেই প্রশ্ন আসবে।',
                  style: const TextStyle(fontSize: 11.5, color: _kSubText),
                ),
              ),
            ],
          ),
        ] else if (picked > 0) ...[
          const SizedBox(height: 6),
          Text('$picked টি অধ্যায় নির্বাচিত (${chapters.length}টির মধ্যে)',
              style: const TextStyle(fontSize: 11.5, color: _kPrimary)),
        ],

        const SizedBox(height: 10),
        if (_loadingChapters)
          const Center(
              child: Padding(
            padding: EdgeInsets.all(16.0),
            child: CircularProgressIndicator(color: _kAccent),
          ))
        else if (chapters.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange),
                SizedBox(width: 8),
                Expanded(
                    child: Text(
                        'কোনো অধ্যায় পাওয়া যায়নি — সব প্রশ্ন থেকেই লোড হবে।')),
              ],
            ),
          )
        else ...[
          // A wall of chips is unusable once a subject has more than a handful
          // of chapters, so search appears only when it is needed.
          if (chapters.length > 7) ...[
            SizedBox(
              height: 38,
              child: TextField(
                controller: _chapterSearchCtrl,
                onChanged: (v) => setState(() => _chapterQuery = v),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  hintText: 'অধ্যায় খুঁজুন…',
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: _chapterQuery.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _chapterSearchCtrl.clear();
                            setState(() => _chapterQuery = '');
                          },
                        ),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],

          if (shown.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('কোনো অধ্যায় মেলেনি।',
                  style: TextStyle(color: _kSubText, fontSize: 12)),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final ch in shown) _chapterChip(ch, chapters.length),
              ],
            ),
        ],
      ],
    );
  }

  /// One chapter chip: number as a badge, name as the label.
  ///
  /// The number is pulled out of the label and shown as a badge so a long
  /// chapter name cannot push the number out of sight.
  Widget _chapterChip(dynamic ch, int total) {
    final selected =
        _selectedChapterNumbers.contains(ch.chapterNumber as String);
    return FilterChip(
      selected: selected,
      showCheckmark: false,
      avatar: CircleAvatar(
        radius: 10,
        backgroundColor: selected ? _kPrimary : _kSubText.withOpacity(0.18),
        child: Text(
          '${ch.chapterNumber}',
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.bold,
            color: selected ? Colors.white : _kSubText,
          ),
        ),
      ),
      label: Text('${ch.chapterName}',
          maxLines: 1, overflow: TextOverflow.ellipsis),
      selectedColor: _kPrimary.withOpacity(0.13),
      side: BorderSide(color: selected ? _kPrimary : Colors.grey.shade300),
      onSelected: (v) => setState(() {
        if (v) {
          _selectedChapterNumbers.add(ch.chapterNumber as String);
        } else {
          _selectedChapterNumbers.remove(ch.chapterNumber as String);
        }
      }),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 2 — Interactive Question Picker
  // ═══════════════════════════════════════════════════════════════════════════

  /// A count box and a button that fill the selection with a random draw.
  ///
  /// Kept beside the select-all actions because it is the same kind of decision:
  /// it decides what the paper contains. Only the size is asked for; which
  /// questions come back is [_pickRandomQuestions]' business.
  Widget _buildRandomSelectorBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 8, 8, 8),
      decoration: BoxDecoration(
        color: _kPrimary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: _kPrimary.withOpacity(0.16)),
      ),
      child: Row(
        children: [
          Icon(Icons.casino_outlined, size: 18, color: _kPrimary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'এলোমেলো নির্বাচন',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: _kDarkText,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: _RandomCountField(
                        controller: _randomCqCtrl,
                        label: 'CQ',
                        max: _totalCqs,
                        color: _kCqColor,
                        fieldKey: const ValueKey('cq-count-field'),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: _RandomCountField(
                        controller: _randomMcqCtrl,
                        label: 'MCQ',
                        max: _totalMcqs,
                        color: _kMcqColor,
                        fieldKey: const ValueKey('mcq-count-field'),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: _RandomCountField(
                        controller: _randomRqCtrl,
                        label: 'RQ',
                        max: _totalShorts,
                        color: _kRqColor,
                        fieldKey: const ValueKey('rq-count-field'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 34,
            child: ElevatedButton(
              onPressed: _pickRandomQuestions,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
              child: const Text(
                'বাছাই',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2() {
    final visible = _visibleQuestions;
    final byChapter = <String, List<HighSchoolQuestion>>{};
    for (final q in visible) {
      byChapter.putIfAbsent(q.chapterNumber, () => []).add(q);
    }
    final chapterNumbers = byChapter.keys.toList()..sort(compareChapterNumbers);

    // The উদ্দীপক runs, so a card can say it is one of a shared pair and a click
    // on it can take the pair along.
    final stemRuns = _mcqStemRuns();

    return Column(
      children: [
        // Sticky counter bar
        _buildStickyBar(),
        // Chapter filter, when the paper draws on more than one
        _buildPickerChapterBar([
          for (final c in _fetchedQuestions.map((q) => q.chapterNumber).toSet())
            c
        ]..sort(compareChapterNumbers)),
        // Type filter + search
        _buildPickFilterBar(visible.length),
        // Question list
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            children: [
              // Select all / none, plus hand entry. A Wrap so the three actions
              // stack onto a second line on a phone rather than overflowing.
              Wrap(
                spacing: 4,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.done_all_rounded, size: 18),
                    label:
                        Text(_pickIsNarrowed ? 'এই তালিকার সব' : 'সব নির্বাচন'),
                    onPressed: _selectAll,
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.remove_done_rounded, size: 18),
                    label: Text(_pickIsNarrowed ? 'এই তালিকা বাদ' : 'বাদ দিন'),
                    style: TextButton.styleFrom(foregroundColor: Colors.grey),
                    onPressed: _deselectAll,
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.edit_note_rounded, size: 18),
                    label: const Text('নিজে প্রশ্ন লিখুন'),
                    style: TextButton.styleFrom(foregroundColor: _kPrimary),
                    onPressed: _openManualQuestion,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildRandomSelectorBar(),
              const SizedBox(height: 8),
              // Chapter groups
              for (final chNum in chapterNumbers) ...[
                _ChapterGroupHeader(
                  key: ValueKey('chapter-header-$chNum'),
                  chapterNumber: chNum,
                  chapterName: byChapter[chNum]!.first.chapterName,
                  total: byChapter[chNum]!.length,
                  selected: byChapter[chNum]!.where((q) => q.isSelected).length,
                  collapsed: _collapsedChapters.contains(chNum),
                  onToggle: () => _toggleChapter(chNum),
                ),
                const SizedBox(height: 8),
                // A folded chapter shows its header and nothing else.
                if (!_collapsedChapters.contains(chNum)) ...[
                  for (final q in _pickerOrder(byChapter[chNum]!))
                    _buildQuestionCard(
                        q, _cardKey(q, _fetchedQuestions.indexOf(q)),
                        run: stemRuns[q.id]),
                ],
                const SizedBox(height: 16),
              ],
              if (visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Column(
                    children: [
                      Text(
                        _pickIsNarrowed
                            ? 'কোনো প্রশ্ন মেলেনি। ফিল্টার বা সার্চ বদলে দেখুন।'
                            : 'কোনো প্রশ্ন পাওয়া যায়নি।',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: _kSubText),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.edit_note_rounded, size: 18),
                        label: const Text('নিজে প্রশ্ন লিখুন'),
                        onPressed: _openManualQuestion,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// The order a chapter's questions take in the picker: the selected ones on
  /// top, then the rest, and inside each half the CQ → MCQ → RQ order the list
  /// has always used.
  ///
  /// Without this a ticked question stays wherever it was, so the answer to
  /// "what have I chosen here?" is scattered down a long chapter.
  List<HighSchoolQuestion> _pickerOrder(List<HighSchoolQuestion> questions) {
    List<HighSchoolQuestion> byType(Iterable<HighSchoolQuestion> items) => [
          ...items.where((q) => q.isCq),
          ...items.where((q) => q.isMcq),
          ...items.where((q) => q.isShort),
        ];
    return [
      ...byType(questions.where((q) => q.isSelected)),
      ...byType(questions.where((q) => !q.isSelected)),
    ];
  }

  /// Chips to narrow the picker to one question type, plus a search box.
  ///
  /// Sits outside the list so it stays put while the questions scroll.
  /// Chapter chips for the picker, shown only when there is more than one.
  ///
  /// Selecting several chapters in step 1 used to dump every one of them into
  /// one long list, with no way to narrow it afterwards.
  Widget _buildPickerChapterBar(List<String> chapterNumbers) {
    if (chapterNumbers.length < 2) return const SizedBox.shrink();

    final withCounts = <String, int>{
      for (final c in chapterNumbers)
        c: _fetchedQuestions.where((q) => q.chapterNumber == c).length,
    };
    final all = _pickerChapterFilter.isEmpty ||
        _pickerChapterFilter.containsAll(chapterNumbers);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.filter_alt_outlined, size: 15, color: _kSubText),
              const SizedBox(width: 6),
              const Text('অধ্যায়',
                  style: TextStyle(fontSize: 11, color: _kSubText)),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() {
                  if (all) {
                    _pickerChapterFilter.clear();
                  } else {
                    _pickerChapterFilter
                      ..clear()
                      ..addAll(chapterNumbers);
                  }
                }),
                child: Text(
                  all ? 'সব দেখান' : 'শুধু এগুলো',
                  style: const TextStyle(
                      fontSize: 11,
                      color: _kPrimary,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 30,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final c in chapterNumbers) ...[
                  _PickerChapterChip(
                    chapterNumber: c,
                    count: withCounts[c] ?? 0,
                    selected: _pickerChapterFilter.isEmpty ||
                        _pickerChapterFilter.contains(c),
                    onTap: () => setState(() {
                      if (_pickerChapterFilter.isEmpty) {
                        // First tap after "all" narrows to just this one.
                        _pickerChapterFilter
                          ..clear()
                          ..add(c);
                      } else if (_pickerChapterFilter.contains(c)) {
                        _pickerChapterFilter.remove(c);
                      } else {
                        _pickerChapterFilter.add(c);
                      }
                    }),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPickFilterBar(int visibleCount) {
    int countOf(_PickFilter f) => _fetchedQuestions.where(f.matches).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 38,
            child: TextField(
              controller: _pickSearchCtrl,
              onChanged: (v) => setState(() => _pickSearchQuery = v),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                prefixIcon: const Icon(Icons.search, size: 19),
                hintText: 'অনুসন্ধান…',
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: _pickSearchQuery.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _pickSearchCtrl.clear();
                          setState(() => _pickSearchQuery = '');
                        },
                      ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final f in _PickFilter.values) ...[
                  _PickFilterChip(
                    label: f.badge,
                    title: f.title,
                    count: countOf(f),
                    color: f.color,
                    selected: _pickFilter == f,
                    onTap: () => setState(() => _pickFilter = f),
                  ),
                  const SizedBox(width: 8),
                ],
                if (_pickIsNarrowed)
                  Text('$visibleCount টি দেখানো হচ্ছে',
                      style: const TextStyle(fontSize: 11, color: _kSubText)),
              ],
            ),
          ),
          // Selected questions stay in the total even when the filter hides
          // them, so the cards on screen stop adding up to it. Say so, rather
          // than leaving the reader to think the sum is wrong.
          if (_marksBreakdown.hidden > 0) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 15, color: Colors.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ফিল্টারের বাইরে ${_marksBreakdown.hidden} নম্বরের নির্বাচিত '
                      'প্রশ্ন আছে — মোট নম্বরে ধরা হয়েছে, তাই দেখা কার্ডের নম্বরের '
                      'চেয়ে মোট বেশি দেখাবে।',
                      style: const TextStyle(fontSize: 11, color: Colors.amber),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStickyBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _kPrimary,
        boxShadow: [
          BoxShadow(
              color: _kPrimary.withOpacity(0.35),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _CountBadge(
                    label: 'CQ',
                    selected: _selectedCqs.length,
                    total: _totalCqs,
                    color: _kCqColor),
                _CountBadge(
                    label: 'MCQ',
                    selected: _selectedMcqs.length,
                    total: _totalMcqs,
                    color: _kMcqColor),
                if (_totalShorts > 0)
                  _CountBadge(
                      label: 'RQ',
                      selected: _selectedShorts.length,
                      total: _totalShorts,
                      color: _kRqColor),
                Text('মোট নম্বর: $_totalSelectedMarks',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _proceedToGenerate,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            child: const Text('প্রশ্নপত্র সাজান ➜',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  /// One-line summary shown in the collapsed question card.
  static String _previewText(HighSchoolQuestion q) {
    if (q.isShort) return q.shortData?.text ?? '';
    if (q.isCq) {
      return q.paperStemText.isEmpty ? '(কোনো উদ্দীপক নেই)' : q.paperStemText;
    }
    return q.mcqData?.text ?? '';
  }

  Widget _buildQuestionCard(HighSchoolQuestion q, String cardKey,
      {List<HighSchoolQuestion>? run}) {
    final isExpanded = _expandedCards[cardKey] == true;
    final typeColor = q.isCq ? _kCqColor : (q.isShort ? _kRqColor : _kMcqColor);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: q.isSelected ? _kPrimary.withOpacity(0.035) : _kCardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: q.isSelected ? _kPrimary.withOpacity(0.5) : Colors.transparent,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: q.isSelected
                ? _kPrimary.withOpacity(0.12)
                : Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header row
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _expandedCards[cardKey] = !isExpanded),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Checkbox(
                    value: q.isSelected,
                    activeColor: _kPrimary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5)),
                    onChanged: (_) => _toggleQuestion(q),
                  ),
                  const SizedBox(width: 4),
                  // Type badge
                  _TypeBadge(type: q.questionType, color: typeColor),
                  const SizedBox(width: 8),
                  // Preview text
                  Expanded(
                    child: Text(
                      _previewText(q),
                      maxLines: isExpanded ? 10 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: _kDarkText),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    children: [
                      Text('${q.totalMarks}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _kPrimary,
                              fontSize: 15)),
                      const Text('নম্বর',
                          style: TextStyle(fontSize: 10, color: _kSubText)),
                    ],
                  ),
                  const SizedBox(width: 4),
                  Icon(isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: _kSubText),
                ],
              ),
            ),
          ),
          // Tags row
          Padding(
            padding: const EdgeInsets.only(left: 56, right: 12, bottom: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (q.stemImageUrl.trim().isNotEmpty)
                  _TagChip(
                      label: 'ছবি আছে',
                      color: Colors.blue.shade50,
                      textColor: Colors.blue.shade700),
                if (q.boardYearTag.isNotEmpty)
                  _TagChip(
                      label: q.boardYearTag,
                      color: Colors.purple.shade100,
                      textColor: Colors.purple.shade800),
                // Where the row came from, so a hand-typed question is not
                // mistaken for one that is in the bank.
                if (q.isManual)
                  _TagChip(
                      label: 'নিজে লেখা',
                      color: Colors.amber.shade100,
                      textColor: Colors.amber.shade900),
                // Corrected here without touching the sheet, so it is worth
                // saying which rows differ from the bank.
                if (q.isEdited)
                  _TagChip(
                      label: 'সম্পাদিত',
                      color: Colors.deepOrange.shade50,
                      textColor: Colors.deepOrange.shade700),
                // One উদ্দীপক over several questions: the run is selected whole,
                // so say which run this card is part of rather than letting a
                // second question tick itself without explanation.
                if (run != null && run.length > 1)
                  _TagChip(
                      label: 'একই উদ্দীপক · ${run.length}টি',
                      color: Colors.indigo.shade50,
                      textColor: Colors.indigo.shade700),
                _TagChip(
                    label: 'অধ্যায় ${q.chapterNumber}: ${q.chapterName}',
                    color: Colors.teal.shade50,
                    textColor: Colors.teal.shade700),
                // Only meaningful once the paper is being printed as two sets.
                if (_twoSets)
                  for (var i = 0; i < 2; i++)
                    _SetChip(
                      label: _setLabels[i].isEmpty
                          ? (i == 0 ? 'ক' : 'খ')
                          : _setLabels[i],
                      active: q.setLabel == _setLabels[i],
                      selected: q.isSelected,
                      onTap: () {
                        _toggleQuestion(q);
                        _toggleQuestionSet(q, i);
                      },
                    ),
              ],
            ),
          ),
          // Expanded detail
          if (isExpanded) _buildExpandedDetail(q),
        ],
      ),
    );
  }

  /// What an expanded card shows: the question as the paper will print it, and
  /// the way to correct it.
  ///
  /// The edit button lives here rather than on the collapsed row because what is
  /// being corrected is the text in front of the reader — and because a card has
  /// to be opened to see what is wrong with it.
  Widget _buildExpandedDetail(HighSchoolQuestion q) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 10),
            child: TextButton.icon(
              onPressed: () => _openEditQuestion(q),
              icon: const Icon(Icons.edit_outlined, size: 15),
              label:
                  const Text('সম্পাদনা করুন', style: TextStyle(fontSize: 12.5)),
              style: TextButton.styleFrom(
                foregroundColor: _kPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ),
        _buildExpandedBody(q),
      ],
    );
  }

  Widget _buildExpandedBody(HighSchoolQuestion q) {
    if (q.isShort) {
      final data = q.shortData;
      return Container(
        margin: const EdgeInsets.fromLTRB(56, 0, 12, 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.teal.shade50,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                    child: Text(data?.text ?? '',
                        style: const TextStyle(fontSize: 13))),
                const SizedBox(width: 8),
                Text('[${data?.mark ?? q.totalMarks}]',
                    style: const TextStyle(color: _kSubText, fontSize: 12)),
              ],
            ),
            if (q.stemImageUrl.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              _buildQuestionImage(q.stemImageUrl),
            ],
          ],
        ),
      );
    }
    if (q.isCq) {
      return Container(
        margin: const EdgeInsets.fromLTRB(56, 0, 12, 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (q.stemImageUrl.trim().isNotEmpty) ...[
              _buildQuestionImage(q.stemImageUrl),
              const SizedBox(height: 8),
            ],
            ...q.cqSubQuestions.map((sq) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            color: _kCqColor,
                            borderRadius: BorderRadius.circular(4)),
                        child: Text(sq.label,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(sq.text,
                              style: const TextStyle(fontSize: 13))),
                      const SizedBox(width: 8),
                      Text('[${sq.mark}]',
                          style:
                              const TextStyle(color: _kSubText, fontSize: 12)),
                    ],
                  ),
                )),
          ],
        ),
      );
    } else {
      final mcq = q.mcqData;
      if (mcq == null) return const SizedBox.shrink();
      final letters = ['ক', 'খ', 'গ', 'ঘ'];
      final stem = q.mcqStemText;
      return Container(
        margin: const EdgeInsets.fromLTRB(56, 0, 12, 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The intro and its figure, when the question carries them. A
            // group of MCQs shares one উদ্দীপক, so what is shown here is what
            // prints over the first question of that group.
            if (stem.isNotEmpty) ...[
              Text(stem, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 6),
            ],
            if (q.stemImageUrl.trim().isNotEmpty) ...[
              _buildQuestionImage(q.stemImageUrl),
              const SizedBox(height: 8),
            ],
            ...List.generate(mcq.options.length, (i) {
              final letter = i < letters.length ? letters[i] : '${i + 1}';
              final isCorrect = mcq.options[i] == mcq.correctAns;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isCorrect
                            ? Colors.green.shade400
                            : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(letter,
                          style: TextStyle(
                              color: isCorrect ? Colors.white : Colors.black87,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(mcq.options[i],
                            style: TextStyle(
                                fontSize: 13,
                                color: isCorrect
                                    ? Colors.green.shade700
                                    : Colors.black87))),
                    if (isCorrect)
                      const Icon(Icons.check_circle,
                          size: 16, color: Colors.green),
                  ],
                ),
              );
            }),
          ],
        ),
      );
    }
  }

  Widget _buildQuestionImage(String rawUrl) {
    final imageUrl = HighSchoolExportService.resolveImageUrl(rawUrl);
    if (imageUrl.isEmpty) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxHeight: 190),
        color: Colors.white,
        alignment: Alignment.center,
        child: Image.network(
          imageUrl,
          height: 180,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            final expected = progress.expectedTotalBytes;
            final value = expected == null
                ? null
                : progress.cumulativeBytesLoaded / expected;
            return SizedBox(
              height: 120,
              child: Center(
                child: CircularProgressIndicator(
                  value: value,
                  strokeWidth: 2,
                  color: _kPrimary,
                ),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) => Container(
            height: 90,
            alignment: Alignment.center,
            color: Colors.grey.shade100,
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.broken_image_outlined, color: Colors.grey),
                SizedBox(height: 4),
                Text('ছবি দেখানো যায়নি',
                    style: TextStyle(fontSize: 11, color: _kSubText)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 3 — Exam Header Config & Export
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStep3() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
              icon: Icons.edit_document, label: 'পরীক্ষার তথ্য পূরণ করুন'),
          const SizedBox(height: 12),

          // The paper in one glance, before anything is written.
          _buildSummaryChips(),
          const SizedBox(height: 12),

          _buildSectionCard(),
          const SizedBox(height: 12),

          // Everything the paper's masthead prints, in one card.
          _buildPaperInfoCard(),
          const SizedBox(height: 12),

          // Paper appearance settings share one compact row.
          _buildPaperSettingsSelector(),
          const SizedBox(height: 14),

          // Export and share the generated paper as HTML.
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.open_in_browser_rounded, size: 19),
                    label: const Text('HTML ফাইল খুলুন',
                        style: TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kPrimary,
                      side: const BorderSide(color: _kPrimary, width: 1.4),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13)),
                    ),
                    onPressed: _exportHtml,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.share_rounded, size: 19),
                    label: const Text('HTML শেয়ার',
                        style: TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0284C7),
                      side: const BorderSide(
                          color: Color(0xFF0284C7), width: 1.4),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13)),
                    ),
                    onPressed: () => _exportHtml(open: false),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // The live preview renders the same HTML file in-app.
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.visibility_rounded, size: 20),
              label: const Text('লাইভ প্রিভিউ দেখুন',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13)),
                elevation: 3,
                shadowColor: _kAccent.withOpacity(0.4),
              ),
              onPressed: _openLivePreview,
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  /// The chosen questions and their marks, as one line of compact chips.
  ///
  /// Each type carries its count and its marks in a single chip, because the two
  /// are read together — how many questions of this kind, and what they are
  /// worth — and splitting them into separate chips made the reader pair them by
  /// eye. The total stands out from the rest.
  Widget _buildSummaryChips() {
    final marks = _marksBreakdown;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _SummaryChip(
          icon: Icons.quiz_rounded,
          label: 'CQ: ${_selectedCqs.length}টি  ·  ${marks.cq} নম্বর',
        ),
        _SummaryChip(
          icon: Icons.format_list_bulleted_rounded,
          label: 'MCQ: ${_selectedMcqs.length}টি  ·  ${marks.mcq} নম্বর',
        ),
        _SummaryChip(
          icon: Icons.short_text_rounded,
          label: 'RQ: ${_selectedShorts.length}টি  ·  ${marks.rq} নম্বর',
        ),
        _SummaryChip(
          icon: Icons.star_rounded,
          label: 'মোট নম্বর: $_totalSelectedMarks',
          emphasized: true,
        ),
      ],
    );
  }

  /// The masthead — school, exam and class lines — in a single card.
  ///
  /// They print as one block on the page, so they read best together. The two
  /// short fields share a row, which keeps the card from running on.
  Widget _buildPaperInfoCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.badge_outlined, size: 16, color: _kPrimary),
              const SizedBox(width: 6),
              const Text('প্রশ্নপত্রের মাথার তথ্য',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: _kDarkText)),
            ],
          ),
          const SizedBox(height: 10),
          _buildTextField(
            ctrl: _schoolCtrl,
            label: 'শিক্ষা প্রতিষ্ঠানের নাম',
            icon: Icons.account_balance_rounded,
          ),
          const SizedBox(height: 8),
          _buildTextField(
            ctrl: _examCtrl,
            label: 'পরীক্ষার নাম',
            icon: Icons.description_rounded,
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildTextField(ctrl: _subjectCtrl, label: 'বিষয়'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child:
                    _buildTextField(ctrl: _classCtrl, label: 'শ্রেণি ও শাখা'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildTextField(ctrl: _timeCtrl, label: 'সময়'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTextField(
                  ctrl: _marksCtrl,
                  label: 'পূর্ণমান',
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildTextField(
            ctrl: _cqAnswerAnyCtrl,
            label: 'যেকোনো কয়টি CQ-র উত্তর দিতে হবে',
            icon: Icons.rule_rounded,
            keyboardType: TextInputType.number,
            // The remark sits under the field, not in the label: the label
            // would otherwise be too long to float above the box.
            helperText: 'খালি রাখলে লেখা হবে না।'
                '${_selectedCqs.isEmpty ? '' : ' সর্বোচ্চ ${_selectedCqs.length}টি দেওয়া যাবে।'}',
          ),
        ],
      ),
    );
  }

  /// Image size, paper text size, and typeface in one row of dropdowns.
  Widget _buildPaperSettingsSelector() {
    final fontSteps = [
      for (var step = _fontStepMin; step <= _fontStepMax; step++) step,
    ];
    String fontSizeLabel(double step) => step == 0
        ? 'স্বাভাবিক'
        : '${step > 0 ? '+' : ''}${step.toStringAsFixed(0)} pt';

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _buildSettingDropdown<StemImageSize>(
              label: 'ছবির আকার',
              value: _imageSize,
              items: StemImageSize.values,
              itemLabel: (size) => size.label,
              selectedItemLabel: (size) =>
                  size == StemImageSize.hidden ? 'বন্ধ' : size.label,
              onChanged: (value) {
                if (value != null) setState(() => _imageSize = value);
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildSettingDropdown<double>(
              label: 'লেখার আকার',
              value: _fontStep,
              items: fontSteps,
              itemLabel: fontSizeLabel,
              onChanged: (value) {
                if (value != null) setState(() => _fontStep = value);
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildSettingDropdown<PaperFont>(
              label: 'ফন্ট',
              value: _paperFont,
              items: PaperFont.values,
              itemLabel: (font) => font.label,
              selectedItemLabel: (font) => switch (font) {
                PaperFont.hindSiliguri => 'হিন্দ',
                PaperFont.notoSansBengali => 'নোটো সান্স',
                PaperFont.notoSerifBengali => 'নোটো সেরিফ',
                PaperFont.balooDa => 'বালু দা',
                PaperFont.mina => 'মিনা',
                PaperFont.kalpurush => 'কলপুরুষ',
                PaperFont.solaimanLipi => 'সলাইমান',
                PaperFont.nirmalaUi => 'নির্মলা',
              },
              onChanged: (value) {
                if (value != null) setState(() => _paperFont = value);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingDropdown<T>({
    required String label,
    required T value,
    required List<T> items,
    required String Function(T) itemLabel,
    String Function(T)? selectedItemLabel,
    required ValueChanged<T?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _kSubText,
            ),
          ),
        ),
        DropdownButtonFormField<T>(
          value: value,
          isExpanded: true,
          iconSize: 18,
          style: const TextStyle(fontSize: 12, color: _kDarkText),
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: const BorderSide(color: _kPrimary, width: 1.4),
            ),
          ),
          selectedItemBuilder: (context) => [
            for (final item in items)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  (selectedItemLabel ?? itemLabel)(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          items: [
            for (final item in items)
              DropdownMenuItem<T>(
                value: item,
                child: Text(
                  itemLabel(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }

  /// The paper's structure in one card: the order its blocks print in, and how
  /// wide each of them runs.
  ///
  /// The two belong together — they answer the same question, what the paper is
  /// made of — and apart they meant two lists of the same three sections, one
  /// showing the order the reader chose and the other a fixed order that could
  /// contradict it. Here, top to bottom *is* the order on the page, so the letter
  /// a block is headed with reads straight off its row.
  Widget _buildSectionCard() {
    final merged = _mergesCqAndShorts;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.view_column_outlined,
                  size: 17, color: _kPrimary),
              const SizedBox(width: 7),
              const Text('বিভাগ ও কলাম',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                      color: _kDarkText)),
              const Spacer(),
              Text('ধরে টেনে ক্রম বদলাও',
                  style: TextStyle(fontSize: 11, color: _kSubText)),
            ],
          ),
          const SizedBox(height: 8),
          ReorderableListView.builder(
            shrinkWrap: true,
            buildDefaultDragHandles: false,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _sectionOrder.length,
            // Every block is listed, empty ones included, so the rows map onto
            // [_sectionOrder] one for one and a drop is a plain move. The old
            // list hid empty blocks, which is what forced every drop to translate
            // a visible index back onto the stored order.
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex -= 1;
                _sectionOrder.insert(
                    newIndex, _sectionOrder.removeAt(oldIndex));
              });
            },
            itemBuilder: (context, index) {
              final kind = _sectionOrder[index];
              final count = _questionsOf(kind).length;
              return _SectionCardRow(
                key: ValueKey(kind),
                kind: kind,
                index: index,
                questionCount: count,
                marks: _marksOf(kind),
                // Only a block that prints has a letter. An empty block is
                // skipped on the page, so numbering it would promise a division
                // the reader will not find there.
                letter: count == 0 ? '' : _sectionLetter(kind),
                layout: _layoutOf(kind),
                onLayout: (v) => setState(() => _setLayoutOf(kind, v)),
              );
            },
          ),
          const SizedBox(height: 8),
          const Text(
            'প্রতিটি বিভাগ আলাদাভাবে এক বা দুই কলামে বসানো যায়। ছবি থাকলে ছোট কলামে ছবি ছোট দেখাবে।',
            style: TextStyle(fontSize: 11, color: _kSubText),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: _kPrimary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _kPrimary.withOpacity(0.16)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.merge_type_rounded,
                    size: 14, color: _kPrimary.withOpacity(0.7)),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    merged
                        ? 'সৃজনশীল ও সংক্ষিপ্ত প্রশ্ন পরপর আছে, তাই দুটি একটিই '
                            'প্রবাহে একসাথে বসবে। মাঝে কোনো বিভাগ না সরালে এই যুক্ত '
                            'বিন্যাস থাকবে।'
                        : 'সৃজনশীল ও সংক্ষিপ্ত প্রশ্ন পরপর নেই, তাই এরা আলাদা বিভাগ হিসেবে '
                            'বসবে। দুটি পরপর করলে আবার একটিই প্রবাহে জুটে যাবে।',
                    style: const TextStyle(fontSize: 11, color: _kSubText),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),
          _buildSetControls(),
        ],
      ),
    );
  }

  /// The column setting that governs [kind]: the three are independent.
  QuestionLayout _layoutOf(_SectionKind kind) => kind.isCq
      ? _cqLayout
      : kind.isMcq
          ? _mcqLayout
          : _rqLayout;

  void _setLayoutOf(_SectionKind kind, QuestionLayout value) {
    if (kind.isCq) {
      _cqLayout = value;
    } else if (kind.isMcq) {
      _mcqLayout = value;
    } else {
      _rqLayout = value;
    }
  }

  /// Controls for printing the paper as two variants in one document.
  Widget _buildSetControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('দুইটি সেটে প্রশ্নপত্র',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: _kDarkText)),
                  const SizedBox(height: 3),
                  Text(
                    'ক ও খ একই পেজে তৈরি হবে — আলাদা করে তৈরি করলে '
                    'প্রতিটির একটা পেজ নষ্ট হয়।',
                    style: TextStyle(fontSize: 11, color: _kSubText),
                  ),
                ],
              ),
            ),
            Switch(
              value: _twoSets,
              activeColor: _kPrimary,
              onChanged: (v) => setState(() {
                _twoSets = v;
                if (!v) _assignAllToFirstSet();
              }),
            ),
          ],
        ),
        if (_twoSets) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              for (var i = 0; i < 2; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(
                  child: _buildTextField(
                    ctrl: _setLabelControllers[i],
                    label: i == 0 ? 'প্রথম সেটের নাম' : 'দ্বিতীয় সেটের নাম',
                    icon: i == 0 ? Icons.looks_one : Icons.looks_two,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _selectedQuestions.length < 2
                      ? null
                      : _splitSelectedEvenly,
                  icon: const Icon(Icons.balance, size: 17),
                  label: Text(
                      'অর্ধেক করে ভাগ করো (${_selectedQuestions.length} টি)'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _assignAllToFirstSet,
                  icon: const Icon(Icons.merge_type, size: 17),
                  label: const Text('সব প্রশ্ন প্রথম সেটে'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < 2; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: i == 0
                          ? _kPrimary.withOpacity(0.10)
                          : Colors.teal.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _setLabels[i].isEmpty
                          ? (i == 0 ? 'ক' : 'খ')
                          : _setLabels[i],
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: i == 0 ? _kPrimary : Colors.teal.shade700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_questionsForSet(i).length} টি প্রশ্ন'
                    '  ·  ${_questionsForSet(i).fold(0, (s, q) => s + q.totalMarks)} নম্বর',
                    style: const TextStyle(fontSize: 11, color: _kSubText),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          const Text(
            'প্রতিটি প্রশ্নের কার্ডে সেট বদলাতে পারেন।',
            style: TextStyle(fontSize: 11, color: _kSubText),
          ),
          const SizedBox(height: 3),
          const Text(
            'কোনো সেটে নিজের প্রশ্ন না থাকলে সেটিও প্রথম সেটের সব প্রশ্ন ছাপে — শুধু MCQ-এর ক্রম বদলে যায়।',
            style: TextStyle(fontSize: 11, color: _kSubText),
          ),
        ],
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController ctrl,
    required String label,
    IconData? icon,
    TextInputType? keyboardType,
    String? helperText,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      style: const TextStyle(color: _kDarkText, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13.5, color: _kSubText),
        floatingLabelStyle: const TextStyle(
            fontSize: 13, color: _kPrimary, fontWeight: FontWeight.w600),
        prefixIcon: icon == null ? null : Icon(icon, color: _kPrimary, size: 20),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 38, minHeight: 40),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(11)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: _kPrimary, width: 1.8),
        ),
        helperText: helperText,
        helperStyle: const TextStyle(fontSize: 11, color: _kSubText),
        helperMaxLines: 2,
        filled: true,
        fillColor: _kCardBg,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small reusable sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  final int currentStep;
  const _StepIndicator({required this.currentStep});

  @override
  Widget build(BuildContext context) {
    const steps = ['ফিল্টার', 'প্রশ্ন বেছে নিন', 'প্রশ্নপত্র তৈরি'];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
      child: Row(
        children: List.generate(steps.length * 2 - 1, (i) {
          if (i.isOdd) {
            final stepIndex = i ~/ 2;
            return Expanded(
              child: Container(
                height: 2,
                color:
                    stepIndex < currentStep ? _kPrimary : Colors.grey.shade200,
              ),
            );
          }
          final stepIndex = i ~/ 2;
          final active = stepIndex == currentStep;
          final done = stepIndex < currentStep;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done
                      ? _kAccent
                      : (active ? _kPrimary : Colors.grey.shade200),
                ),
                child: Center(
                  child: done
                      ? const Icon(Icons.check, size: 18, color: Colors.white)
                      : Text('${stepIndex + 1}',
                          style: TextStyle(
                              color:
                                  active ? Colors.white : Colors.grey.shade500,
                              fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 4),
              Text(steps[stepIndex],
                  style: TextStyle(
                      fontSize: 10,
                      color: active ? _kPrimary : Colors.grey.shade500,
                      fontWeight:
                          active ? FontWeight.bold : FontWeight.normal)),
            ],
          );
        }),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: _kPrimary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: _kPrimary, size: 22),
          ),
          const SizedBox(width: 12),
          Text(label,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _kDarkText)),
        ],
      );
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: [_kPrimary.withOpacity(0.1), _kAccent.withOpacity(0.1)]),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _kPrimary.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: _kPrimary),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    color: _kDarkText,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      );
}

/// A compact stat for the summary strip on the generate step.
///
/// Square-ish rather than pill-shaped: the strip holds several at once, and a
/// rounded tag per item made the row read as a list of buttons. The total is
/// [emphasized] so the one number worth finding stands out at a glance.
class _SummaryChip extends StatelessWidget {
  final IconData? icon;
  final String label;
  final bool emphasized;

  const _SummaryChip({
    required this.label,
    this.icon,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: emphasized
              ? _kPrimary.withOpacity(0.10)
              : _kPrimary.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: emphasized
                ? _kPrimary.withOpacity(0.35)
                : _kPrimary.withOpacity(0.14),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: _kPrimary),
              const SizedBox(width: 4),
            ],
            Text(label,
                style: TextStyle(
                    fontSize: 11.5,
                    color: emphasized ? _kPrimary : _kDarkText,
                    fontWeight:
                        emphasized ? FontWeight.bold : FontWeight.w600)),
          ],
        ),
      );
}

/// A compact count box for the random selector bar.
///
/// Shows a tiny label (CQ/MCQ/RQ) above a centered number field. The
/// [max] hint caps the field so the reader knows the bank's limit.
class _RandomCountField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final int max;
  final Color color;
  final Key? fieldKey;

  const _RandomCountField({
    required this.controller,
    required this.label,
    required this.max,
    required this.color,
    this.fieldKey,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: 28,
            child: TextField(
              key: fieldKey,
              controller: controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 3,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: _kDarkText,
              ),
              decoration: InputDecoration(
                isDense: true,
                counterText: '',
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                hintText: '0',
                hintStyle: TextStyle(fontSize: 10, color: _kSubText),
                filled: true,
                fillColor: Colors.white,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(7),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(7),
                  borderSide: BorderSide(color: color, width: 1.3),
                ),
              ),
            ),
          ),
          if (max > 0)
            Text(
              'মক্স $max',
              style: TextStyle(fontSize: 7.5, color: _kSubText),
            ),
        ],
      );
}

/// The bar over one chapter's questions in the picker.
///
/// Tapping it folds the chapter's cards away — the header keeps the chapter's
/// name and counts, so the group can be opened again. A subject easily runs to
/// twenty chapters, and folding the ones already dealt with is the difference
/// between scanning the list and scrolling through it.
class _ChapterGroupHeader extends StatelessWidget {
  final String chapterNumber;
  final String chapterName;

  /// How many questions the chapter shows under the current filter.
  final int total;

  /// How many of those are selected.
  final int selected;

  final bool collapsed;
  final VoidCallback onToggle;

  const _ChapterGroupHeader({
    super.key,
    required this.chapterNumber,
    required this.chapterName,
    required this.total,
    required this.selected,
    required this.collapsed,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                _kPrimary.withOpacity(0.08),
                _kAccent.withOpacity(0.05)
              ]),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kPrimary.withOpacity(0.15)),
            ),
            child: Row(
              children: [
                const Icon(Icons.folder_special_rounded,
                    color: _kPrimary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('অধ্যায় $chapterNumber: $chapterName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _kDarkText,
                          fontSize: 13)),
                ),
                const SizedBox(width: 8),
                Text('$total টি',
                    style: const TextStyle(fontSize: 11, color: _kSubText)),
                if (selected > 0) ...[
                  const SizedBox(width: 6),
                  Text('$selected নির্বাচিত',
                      style: const TextStyle(
                          fontSize: 11,
                          color: _kRqColor,
                          fontWeight: FontWeight.w600)),
                ],
                const SizedBox(width: 2),
                // The arrow is the affordance; the whole bar is the target.
                Tooltip(
                  message: collapsed ? 'প্রশ্নগুলো দেখান' : 'প্রশ্নগুলো লুকান',
                  child: AnimatedRotation(
                    turns: collapsed ? -0.25 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(Icons.keyboard_arrow_down_rounded,
                        size: 20, color: _kSubText),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _TypeBadge extends StatelessWidget {
  final String type;
  final Color color;
  const _TypeBadge({required this.type, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Text(type,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.bold)),
      );
}

/// A tappable chip that assigns a question to one of the two printed sets.
///
/// Deliberately not a plain [Checkbox]: tapping it both selects the question
/// and assigns it, because a set can only contain questions that are part of
/// the paper.
class _SetChip extends StatelessWidget {
  const _SetChip({
    required this.label,
    required this.active,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool active;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: active
              ? _kPrimary
              : (selected ? _kPrimary.withOpacity(0.08) : Colors.grey.shade100),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: active ? _kPrimary : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              active ? Icons.check_circle : Icons.circle_outlined,
              size: 13,
              color: active ? Colors.white : _kSubText,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                color: active ? Colors.white : _kSubText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Which question type the picker is showing.
///
/// CQ, MCQ and short questions arrive interleaved from the sheet, so without
/// this the list reads as one mixed pile and picking a coherent paper means
/// scrolling past everything you do not want.
enum _PickFilter {
  all('সব', 'সব প্রশ্ন', _kPrimary),
  cq('CQ', 'সৃজনশীল', _kCqColor),
  mcq('MCQ', 'বহুনির্বাচনি', _kMcqColor),
  rq('RQ', 'সংক্ষিপ্ত', _kRqColor);

  const _PickFilter(this.badge, this.title, this.color);

  /// The letter shown on the chip, matching the badge on a question card.
  final String badge;

  /// Spoken name, used as the chip tooltip.
  final String title;

  /// Matches the colour of this type's badge, so the two agree at a glance.
  final Color color;

  bool matches(HighSchoolQuestion q) {
    switch (this) {
      case _PickFilter.all:
        return true;
      case _PickFilter.cq:
        return q.isCq;
      case _PickFilter.mcq:
        return q.isMcq;
      case _PickFilter.rq:
        return q.isShort;
    }
  }
}

/// A tappable type chip for the picker: letter, name and how many exist.
///
/// Shows the full count even when narrowed to another type, so it stays a
/// truthful menu of what could be shown rather than only what is on screen.
class _PickFilterChip extends StatelessWidget {
  final String label;
  final String title;
  final int count;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _PickFilterChip({
    required this.label,
    required this.title,
    required this.count,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : color;
    return Tooltip(
      message: title,
      child: Material(
        color: selected ? color : color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? color : color.withOpacity(0.35),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: fg,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w400,
                    color: selected ? Colors.white : _kSubText,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A question section on the paper, in the order the reader arranges them.
///
/// The paper used to hard-code one order, and a different one when CQ and the
/// short questions were merged, so there was no way to print the sections in
/// the order a particular exam wanted.
enum _SectionKind {
  cq('সৃজনশীল প্রশ্ন (CQ)', 'সৃজনশীল প্রশ্ন', _kCqColor),
  rq('সংক্ষিপ্ত প্রশ্ন (SQ)', 'সংক্ষিপ্ত প্রশ্ন', _kRqColor),
  mcq('বহুনির্বাচনী প্রশ্ন (MCQ)', 'বহুনির্বাচনী প্রশ্ন', _kMcqColor);

  const _SectionKind(this.title, this.shortName, this.color);

  /// The block's name as the printed banner spells it, minus the `ক-বিভাগ:`
  /// prefix. The letter comes from the block's *place* in the printed order, so
  /// it can only be added once the row knows where it sits.
  final String title;

  /// Compact name, for a row that has no questions to count.
  final String shortName;

  final Color color;

  bool get isCq => this == _SectionKind.cq;
  bool get isMcq => this == _SectionKind.mcq;
  bool get isRq => this == _SectionKind.rq;
}

/// One block of the paper: where it prints, what it holds and how wide it runs.
///
/// The row itself is the drag handle; the column toggle inside it still takes a
/// tap, because a drag only begins once the pointer moves.
class _SectionCardRow extends StatelessWidget {
  const _SectionCardRow({
    super.key,
    required this.kind,
    required this.questionCount,
    required this.marks,
    required this.letter,
    required this.index,
    required this.layout,
    required this.onLayout,
  });

  final _SectionKind kind;
  final int questionCount;
  final int marks;

  /// The বাংলা letter this block prints under, or empty when it holds nothing
  /// and is skipped on the page.
  final String letter;
  final int index;
  final QuestionLayout layout;
  final ValueChanged<QuestionLayout> onLayout;

  @override
  Widget build(BuildContext context) {
    final empty = questionCount == 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        decoration: BoxDecoration(
          color: empty ? Colors.grey.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: empty ? Colors.grey.shade300 : kind.color.withOpacity(0.35),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
          child: Row(
            children: [
              // The drag area stops short of the column toggle: a pill inside
              // the drag listener would start a reorder the moment a click
              // moved a pixel, and the setting would not change.
              Expanded(
                child: ReorderableDragStartListener(
                  index: index,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: Row(
                      children: [
                        Icon(Icons.drag_indicator_rounded,
                            size: 18,
                            color: empty ? Colors.grey.shade400 : kind.color),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                letter.isEmpty
                                    ? kind.title
                                    : '$letter-বিভাগ: ${kind.title}',
                                style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.bold,
                                    color: empty ? _kSubText : _kDarkText),
                              ),
                              Text(
                                empty
                                    ? 'কোনো ${kind.shortName} নেই'
                                    : '$questionCount টি প্রশ্ন  ·  $marks নম্বর',
                                style: const TextStyle(
                                    fontSize: 11, color: _kSubText),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _ColumnToggle(value: layout, onChanged: onLayout),
            ],
          ),
        ),
      ),
    );
  }
}

/// The one-or-two column choice for a section, as two glyphs.
///
/// Glyphs rather than words: the row already carries the block's name, its
/// letter and its counts, and the choice has to fit beside them. These are the
/// same bars the paper itself is drawn with, so two bars read as "two columns"
/// without a label.
class _ColumnToggle extends StatelessWidget {
  const _ColumnToggle({required this.value, required this.onChanged});

  final QuestionLayout value;
  final ValueChanged<QuestionLayout> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < QuestionLayout.values.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          // Labelled for the pointer and the screen reader: the pill itself is
          // two bars and no words, which is all that fits beside a section name.
          Tooltip(
            message: QuestionLayout.values[i].label,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onChanged(QuestionLayout.values[i]),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                decoration: BoxDecoration(
                  color: value == QuestionLayout.values[i]
                      ? _kPrimary.withOpacity(0.10)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: value == QuestionLayout.values[i]
                        ? _kPrimary
                        : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: List.generate(
                    QuestionLayout.values[i].mcqColumns,
                    (_) => Container(
                      width: 7,
                      height: 14,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: value == QuestionLayout.values[i]
                            ? _kPrimary.withOpacity(0.55)
                            : Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// One chapter chip in the picker bar: number, name and how many questions it
/// holds, so narrowing to a chapter also says what narrowing costs.
class _PickerChapterChip extends StatelessWidget {
  const _PickerChapterChip({
    required this.chapterNumber,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String chapterNumber;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _kPrimary.withOpacity(0.12) : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? _kPrimary : Colors.grey.shade300,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('অধ্যায় $chapterNumber',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: selected ? _kPrimary : _kSubText,
                  )),
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: _kSubText.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('$count',
                    style: const TextStyle(fontSize: 10, color: _kSubText)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;
  const _TagChip(
      {required this.label, required this.color, required this.textColor});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: TextStyle(fontSize: 10, color: textColor)),
      );
}

class _CountBadge extends StatelessWidget {
  final String label;
  final int selected;
  final int total;
  final Color color;
  const _CountBadge(
      {required this.label,
      required this.selected,
      required this.total,
      required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20)),
        child: Text('$label: $selected/$total',
            style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold)),
      );
}

// Hand entry
// ─────────────────────────────────────────────────────────────────────────────

/// The kind of question being typed, in the picker's own words.
enum _ManualKind {
  cq('CQ', 'সৃজনশীল', _kCqColor, 'উদ্দীপক'),
  mcq('MCQ', 'বহুনির্বাচনি', _kMcqColor, 'প্রশ্ন'),
  sq('RQ', 'সংক্ষিপ্ত', _kRqColor, 'প্রশ্ন');

  const _ManualKind(this.type, this.title, this.color, this.textLabel);

  /// The `question_type` the model and the picker use.
  final String type;
  final String title;
  final Color color;

  /// What the big text box holds for this kind.
  final String textLabel;
}

/// One CQ sub-question being typed: its text and its mark.
///
/// The label is not stored — it follows the row's position, so removing the
/// second sub-question re-letters the rest ক, খ, গ exactly as the paper will.
class _ManualSubRow {
  _ManualSubRow(int mark)
      : textCtrl = TextEditingController(),
        markCtrl = TextEditingController(text: '$mark');

  final TextEditingController textCtrl;
  final TextEditingController markCtrl;

  void dispose() {
    textCtrl.dispose();
    markCtrl.dispose();
  }
}

/// Sheet for typing a question the question bank does not have — or for
/// correcting one it does.
///
/// Returns the finished [HighSchoolQuestion] through the navigator, or null when
/// the reader backs out. Nothing is uploaded either way: a typed question joins
/// this paper only, and a correction prints here while the bank keeps the row it
/// came from, so the bank cannot fill up with one-off rows and no write
/// permission is needed. See [HighSchoolQuestion.manual] and
/// [HighSchoolQuestion.edited].
class _ManualQuestionSheet extends StatefulWidget {
  const _ManualQuestionSheet({
    required this.className,
    required this.subject,
    required this.chapters,
    this.initialChapter,
    this.original,
  });

  final String className;
  final String subject;

  /// Chapters the question can be filed under, in reading order.
  final List<ChapterInfo> chapters;

  /// Pre-selected chapter number, when step 1 was narrowed to one chapter.
  final String? initialChapter;

  /// The question being corrected, when the sheet is opened for an edit.
  ///
  /// Non-null puts the sheet in edit mode: the fields arrive filled with the
  /// question as stored and the result keeps its identity. Null means a question
  /// being written from scratch.
  final HighSchoolQuestion? original;

  @override
  State<_ManualQuestionSheet> createState() => _ManualQuestionSheetState();
}

class _ManualQuestionSheetState extends State<_ManualQuestionSheet> {
  /// What the chapter dropdown offers when the chapter is not in the list.
  static const String _newChapter = '__new__';

  /// Sub-question labels, in order. Options use the first four.
  static const List<String> _letters = ['ক', 'খ', 'গ', 'ঘ', 'ঙ'];

  /// Four options is what every paper in the bank uses, so the sheet does not
  /// ask how many: it is always four.
  static const int _optionCount = 4;

  _ManualKind _kind = _ManualKind.cq;

  late String _chapter;
  final _newNumberCtrl = TextEditingController();
  final _newNameCtrl = TextEditingController();

  /// The উদ্দীপক for a CQ, the question itself for an MCQ or a short question.
  final _textCtrl = TextEditingController();

  /// An MCQ's own উদ্দীপক — the intro and figure shared with the questions
  /// printed under it. Kept apart from [_textCtrl], which holds the question.
  final _stemCtrl = TextEditingController();

  /// URL of the figure that goes with the stem. CQ and MCQ only.
  final _imageCtrl = TextEditingController();

  /// CQ sub-questions. Four to start with — the shape of an ordinary CQ.
  final List<_ManualSubRow> _subs = [
    for (var i = 0; i < 4; i++) _ManualSubRow(i + 1)
  ];

  final _optionCtrls = [
    for (var i = 0; i < _optionCount; i++) TextEditingController()
  ];

  /// Which option is ticked as the correct one, or -1 for none.
  ///
  /// -1 is what editing an MCQ the bank has no answer for opens with: a tick the
  /// reader never placed must not be saved back as an answer.
  int _correct = 0;

  final _shortMarkCtrl = TextEditingController(text: '1');

  String? _error;

  /// True when the sheet was opened on an existing question. The fields then
  /// arrive filled and saving replaces that question instead of adding one.
  bool get _editing => widget.original != null;

  @override
  void initState() {
    super.initState();
    final original = widget.original;
    if (original != null) {
      _fillFrom(original);
      return;
    }
    final preferred = widget.initialChapter;
    final known = preferred != null &&
        widget.chapters.any((c) => c.chapterNumber == preferred);
    _chapter = known
        ? preferred
        : (widget.chapters.isEmpty
            ? _newChapter
            : widget.chapters.first.chapterNumber);
  }

  /// Load a question into the fields so it can be corrected in place.
  ///
  /// The raw stored text goes in, not the printed form: a source tag stays in the
  /// উদ্দীপক exactly as the row holds it, and the paper trims it as it always
  /// does. An empty box is a box to be filled, so a CQ with three sub-questions
  /// still gets a fourth row to type into.
  void _fillFrom(HighSchoolQuestion q) {
    _kind = _ManualKind.values.firstWhere(
      (k) => k.type == q.questionType.toUpperCase(),
      // An unexpected type is a short question: text and a mark, nothing more.
      orElse: () => _ManualKind.sq,
    );

    if (widget.chapters.any((c) => c.chapterNumber == q.chapterNumber)) {
      _chapter = q.chapterNumber;
    } else {
      // A chapter the list does not know about is kept as a new one, so saving
      // cannot quietly move the question into a different chapter.
      _chapter = _newChapter;
      _newNumberCtrl.text = q.chapterNumber;
      _newNameCtrl.text = q.chapterName;
    }

    if (q.isCq) {
      _textCtrl.text = q.stemText;
    } else if (q.isMcq) {
      _textCtrl.text = q.mcqData?.text ?? '';
    } else {
      _textCtrl.text = q.shortData?.text ?? '';
    }
    _stemCtrl.text = q.isMcq ? q.stemText : '';
    _imageCtrl.text = q.stemImageUrl;
    _shortMarkCtrl.text = '${q.shortData?.mark ?? q.shortMark}';

    if (q.isCq) {
      for (final row in _subs) {
        row.dispose();
      }
      _subs
        ..clear()
        ..addAll([
          for (final s in q.cqSubQuestions.take(_letters.length))
            _ManualSubRow(s.mark < 1 ? 1 : s.mark)..textCtrl.text = s.text,
        ]);
      // Four rows is the shape of an ordinary CQ; a five-part question never
      // loses its fifth.
      while (_subs.length < 4) {
        _subs.add(_ManualSubRow(_subs.length + 1));
      }
    }

    if (q.isMcq) {
      final options = q.mcqData?.options ?? const <String>[];
      for (var i = 0; i < _optionCount; i++) {
        _optionCtrls[i].text = i < options.length ? options[i] : '';
      }
      final at = options.indexOf(q.mcqData?.correctAns ?? '');
      // No stored answer stays no answer rather than defaulting to the first
      // option, which would quietly invent one.
      _correct = at;
    }
  }

  @override
  void dispose() {
    _newNumberCtrl.dispose();
    _newNameCtrl.dispose();
    _textCtrl.dispose();
    _stemCtrl.dispose();
    _imageCtrl.dispose();
    for (final s in _subs) {
      s.dispose();
    }
    for (final c in _optionCtrls) {
      c.dispose();
    }
    _shortMarkCtrl.dispose();
    super.dispose();
  }

  // ── Building the question ─────────────────────────────────────────────────

  /// Validate what was typed and hand the question back to the picker.
  void _save() {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) {
      setState(() => _error = '${_kind.textLabel} লিখুন।');
      return;
    }

    final number =
        _chapter == _newChapter ? _newNumberCtrl.text.trim() : _chapter;
    final name =
        _chapter == _newChapter ? _newNameCtrl.text.trim() : _nameOf(_chapter);
    if (number.isEmpty) {
      setState(() => _error = 'অধ্যায়ের নম্বর লিখুন।');
      return;
    }
    if (name.isEmpty) {
      setState(() => _error = 'অধ্যায়ের নাম লিখুন।');
      return;
    }

    // Options are read here rather than in the model, because "at least two of
    // them" is a rule about what was typed, not about the question shape.
    final options = [for (final c in _optionCtrls) c.text.trim()];
    if (_kind == _ManualKind.mcq &&
        options.where((o) => o.isNotEmpty).length < 2) {
      setState(() => _error = 'অন্তত দুটি অপশন লিখুন।');
      return;
    }

    final subs = <CqSubQuestion>[];
    if (_kind == _ManualKind.cq) {
      for (var i = 0; i < _subs.length; i++) {
        final typed = _subs[i].textCtrl.text.trim();
        if (typed.isEmpty) continue;
        subs.add(CqSubQuestion(
          label: _letters[i],
          mark: int.tryParse(_subs[i].markCtrl.text.trim()) ?? 1,
          text: typed,
        ));
      }
      if (subs.isEmpty) {
        setState(() => _error = 'অন্তত একটি উপপ্রশ্ন লিখুন।');
        return;
      }
    }

    Navigator.of(context).pop(_editing
        ? HighSchoolQuestion.edited(
            original: widget.original!,
            chapterNumber: number,
            chapterName: name,
            text: text,
            stem: _kind == _ManualKind.mcq ? _stemCtrl.text : '',
            stemImageUrl: _kind == _ManualKind.sq ? '' : _imageCtrl.text.trim(),
            subQuestions: subs,
            options: options,
            correctAnswer: _correct >= 0 && _correct < options.length
                ? options[_correct]
                : '',
            shortMark: int.tryParse(_shortMarkCtrl.text.trim()) ?? 1,
          )
        : HighSchoolQuestion.manual(
            className: widget.className,
            subject: widget.subject,
            chapterNumber: number,
            chapterName: name,
            questionType: _kind.type,
            text: text,
            stem: _kind == _ManualKind.mcq ? _stemCtrl.text : '',
            stemImageUrl: _kind == _ManualKind.sq ? '' : _imageCtrl.text.trim(),
            subQuestions: subs,
            options: options,
            correctAnswer: _correct >= 0 && _correct < options.length
                ? options[_correct]
                : '',
            shortMark: int.tryParse(_shortMarkCtrl.text.trim()) ?? 1,
          ));
  }

  String _nameOf(String number) {
    for (final c in widget.chapters) {
      if (c.chapterNumber == number) return c.chapterName;
    }
    return '';
  }

  void _addSub() => setState(() => _subs.add(_ManualSubRow(1)));

  void _removeSub(int index) => setState(() => _subs.removeAt(index).dispose());

  // ── Fields ────────────────────────────────────────────────────────────────

  InputDecoration _decoration(String label, {String? helper}) =>
      InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13),
        helperText: helper,
        helperStyle: const TextStyle(fontSize: 10.5, color: _kSubText),
        helperMaxLines: 2,
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kPrimary, width: 1.6),
        ),
      );

  /// A text box, clearing any complaint as soon as the reader types again.
  Widget _field({
    required TextEditingController ctrl,
    required String label,
    String? helper,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) =>
      TextField(
        controller: ctrl,
        keyboardType: keyboardType,
        maxLines: maxLines,
        style: const TextStyle(color: _kDarkText, fontSize: 13.5),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        decoration: _decoration(label, helper: helper),
      );

  Widget _kindChip(_ManualKind kind) {
    final active = _kind == kind;
    return GestureDetector(
      onTap: () => setState(() {
        _kind = kind;
        _error = null;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? kind.color : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: active ? kind.color : Colors.grey.shade300, width: 1.5),
        ),
        child: Text(kind.title,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
                color: active ? Colors.white : _kSubText)),
      ),
    );
  }

  Widget _chapterField() => DropdownButtonFormField<String>(
        value: _chapter,
        isExpanded: true,
        style: const TextStyle(color: _kDarkText, fontSize: 13.5),
        decoration: _decoration('অধ্যায়'),
        items: [
          for (final c in widget.chapters)
            DropdownMenuItem(
              value: c.chapterNumber,
              child: Text('অধ্যায় ${c.chapterNumber}: ${c.chapterName}',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          const DropdownMenuItem(
              value: _newChapter, child: Text('নতুন অধ্যায় লিখুন…')),
        ],
        onChanged: (v) => setState(() {
          _chapter = v ?? _newChapter;
          _error = null;
        }),
      );

  List<Widget> _cqFields() => [
        const Text('উপপ্রশ্ন ও নম্বর',
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 13, color: _kDarkText)),
        const SizedBox(height: 8),
        for (var i = 0; i < _subs.length; i++) ...[
          Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: _kCqColor.withOpacity(0.14),
                child: Text(_letters[i],
                    style: const TextStyle(
                        fontSize: 11,
                        color: _kCqColor,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _field(
                    ctrl: _subs[i].textCtrl, label: 'উপপ্রশ্ন ${_letters[i]}'),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 74,
                child: _field(
                  ctrl: _subs[i].markCtrl,
                  label: 'নম্বর',
                  keyboardType: TextInputType.number,
                ),
              ),
              IconButton(
                tooltip: 'এই উপপ্রশ্নটি বাদ দিন',
                onPressed: _subs.length > 1 ? () => _removeSub(i) : null,
                icon: const Icon(Icons.remove_circle_outline, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('আরেকটি উপপ্রশ্ন'),
            onPressed: _subs.length < _letters.length ? _addSub : null,
          ),
        ),
      ];

  List<Widget> _mcqFields() => [
        const Text('চারটি অপশন — সঠিকটিতে টিক দিন',
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 13, color: _kDarkText)),
        const SizedBox(height: 8),
        for (var i = 0; i < _optionCount; i++) ...[
          Row(
            children: [
              SizedBox(
                width: 30,
                child: Text('(${_letters[i]})',
                    style: const TextStyle(fontSize: 13, color: _kSubText)),
              ),
              Expanded(
                child:
                    _field(ctrl: _optionCtrls[i], label: 'অপশন ${_letters[i]}'),
              ),
              IconButton(
                tooltip: 'সঠিক উত্তর',
                onPressed: () => setState(() => _correct = i),
                icon: Icon(
                  _correct == i
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  size: 20,
                  color: _correct == i ? _kRqColor : Colors.grey.shade400,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ];

  List<Widget> _sqFields() => [
        const Text('নম্বর',
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 13, color: _kDarkText)),
        const SizedBox(height: 8),
        SizedBox(
          width: 90,
          child: _field(
            ctrl: _shortMarkCtrl,
            label: 'নম্বর',
            keyboardType: TextInputType.number,
          ),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.92),
        decoration: const BoxDecoration(
          color: _kBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(_editing ? Icons.edit_rounded : Icons.edit_note_rounded,
                      color: _kPrimary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        _editing ? 'প্রশ্ন সম্পাদনা করুন' : 'নিজে প্রশ্ন লিখুন',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: _kDarkText)),
                  ),
                  IconButton(
                    tooltip: 'বন্ধ করুন',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: _kSubText),
                  ),
                ],
              ),
              Text(
                _editing
                    ? 'পরিবর্তন শুধু এই প্রশ্নপত্রে ছাপা হবে — ব্যাংকের শিট অপরিবর্তিত থাকবে।'
                    : 'ব্যাংকে না থাকা প্রশ্ন এই প্রশ্নপত্রে যোগ হবে — শিটে আপলোড হবে না।',
                style: const TextStyle(fontSize: 11.5, color: _kSubText),
              ),
              const SizedBox(height: 16),
              // An edit keeps the kind the bank row has: the type is the sheet's
              // column, and every field below follows from it.
              if (_editing)
                _kindChip(_kind)
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final k in _ManualKind.values) _kindChip(k),
                  ],
                ),
              const SizedBox(height: 16),
              _chapterField(),
              if (_chapter == _newChapter) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    SizedBox(
                      width: 110,
                      child: _field(
                        ctrl: _newNumberCtrl,
                        label: 'অধ্যায় নম্বর',
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _field(ctrl: _newNameCtrl, label: 'অধ্যায়ের নাম'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              if (_kind == _ManualKind.mcq) ...[
                _field(ctrl: _stemCtrl, label: 'উদ্দীপক (ঐচ্ছিক)', maxLines: 2),
                const Padding(
                  padding: EdgeInsets.only(top: 4, left: 4),
                  child: Text(
                    'একই উদ্দীপকের একাধিক প্রশ্ন হলে প্রতিটিতে একই উদ্দীপক লিখুন — '
                    'প্রশ্নপত্রে উদ্দীপকটি একবারই ছাপা হবে।',
                    style: TextStyle(fontSize: 11, color: _kSubText),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              _field(
                ctrl: _textCtrl,
                label: _kind.textLabel,
                maxLines: _kind == _ManualKind.cq ? 3 : 2,
              ),
              if (_kind != _ManualKind.sq) ...[
                const SizedBox(height: 12),
                _field(
                    ctrl: _imageCtrl,
                    label: 'ছবির লিংক (ঐচ্ছিক)',
                    helper: 'গুগল ড্রাইভ বা যেকোনো সরাসরি ছবির লিংক'),
              ],
              const SizedBox(height: 16),
              if (_kind == _ManualKind.cq)
                ..._cqFields()
              else if (_kind == _ManualKind.mcq)
                ..._mcqFields()
              else
                ..._sqFields(),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.error_outline,
                        size: 16, color: Colors.redAccent),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(_error!,
                          style: const TextStyle(
                              color: Colors.redAccent, fontSize: 12)),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  icon:
                      Icon(_editing ? Icons.check_rounded : Icons.add_rounded),
                  label: Text(
                      _editing
                          ? 'পরিবর্তন সংরক্ষণ করুন'
                          : 'প্রশ্নপত্রে যোগ করুন',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _save,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _editing
                    ? 'সংরক্ষণ করলে তালিকার ওই প্রশ্নটিই বদলে যাবে।'
                    : 'যোগ করলে প্রশ্নটি নির্বাচিত অবস্থায় তালিকায় আসবে।',
                style: const TextStyle(fontSize: 11, color: _kSubText),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
