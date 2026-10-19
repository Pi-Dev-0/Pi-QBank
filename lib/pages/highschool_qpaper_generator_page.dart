import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/highschool_question.dart';
import '../services/highschool_qbank_service.dart';
import '../services/highschool_export_service.dart';
import '../pages/question_paper_preview_page.dart';
import '../utils/pdf_column_layout.dart';
import '../utils/pdf_mixed_text.dart';
import '../utils/pdf_text_metrics.dart';
import '../widgets/custom_app_bar.dart';
import '../config/app_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Colour & design tokens
// ─────────────────────────────────────────────────────────────────────────────

/// Set to true to print a per-block trace of the PDF page layout.
///
/// Off by default. Turn it on when a page comes out with a band of blank space
/// and the report has to say how much was measured against how much was drawn:
/// the difference between the two is the drift, and the drift is the bug.
///
/// See [PdfPageFlow.layoutFragments], which emits the line.
const bool kTracePdfLayout = false;

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
  int _currentStep = 0; // 0 = filter, 1 = picker, 2 = generate PDF

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

  // ── Step 3 state ──────────────────────────────────────────────────────────
  final _schoolCtrl = TextEditingController();
  final _examCtrl = TextEditingController(text: 'বার্ষিক পরীক্ষা ২০২৬');
  final _subjectCtrl = TextEditingController();
  final _classCtrl = TextEditingController();
  final _timeCtrl = TextEditingController(text: '২ ঘন্টা ৩০ মিনিট');
  final _marksCtrl = TextEditingController();

  /// "যেকোনো N টি প্রশ্নের উত্তর দাও" — leave blank (or 0) to omit the note.
  final _cqAnswerAnyCtrl = TextEditingController();
  int get _cqAnswerCount => int.tryParse(_cqAnswerAnyCtrl.text.trim()) ?? 0;

  bool _generating = false;

  /// How stem images are sized across PDF / Word / HTML exports.
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
  /// text and the marks, in the PDF and the HTML alike (the sheet carries it as
  /// `calc(… + Npt)`), so the two exports stay the same size. It also reaches
  /// [PdfLayout]'s height estimators — budgeting room for 11pt text and drawing
  /// 13pt text is what makes a column overflow its allowance.
  double _fontStep = 0;

  /// The range the control allows. Below −3 the text stops being comfortable on
  /// paper; +6 is already half again the height of a paper at 0.
  static const double _fontStepMin = -3;
  static const double _fontStepMax = 6;

  /// The size a paper text style prints at: its tuned base plus [_fontStep].
  double _typeSize(double base) => base + _fontStep;

  /// The face the paper is set in — the HTML sheet and the Word file; the PDF
  /// keeps its own embedded Bijoy face. See [PaperFont].
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
    _chapterSearchCtrl.dispose();
    _pickSearchCtrl.dispose();
    super.dispose();
  }

  // ── Derived counters ──────────────────────────────────────────────────────

  List<HighSchoolQuestion> get _selectedQuestions =>
      _fetchedQuestions.where((q) => q.isSelected).toList();

  // ── Question sets ────────────────────────────────────────────────────────
  //
  // A paper can be printed as two variants ("ক" / "খ") so that two
  // students sitting next to each other are not handed the same paper. Both
  // sets go into one document: generating two PDFs separately wastes a page
  // each, because a set with only a few questions never fills its sheet.

  /// When false the paper is a single set, exactly as before.
  bool _twoSets = false;

  /// Font metrics for the export currently being built, or null outside one.
  ///
  /// Set by [_buildPdf] so [_mixedText] can measure a typeset fraction without
  /// every call site having to thread the measurer through.
  PdfTextMetrics? _activeMetrics;
  pw.Font? _activeMathFont;
  Set<int>? _activeSymbolCoverage;

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
    _classCtrl.text = _selectedClass == null ? '' : _classLabel(_selectedClass!);
    _marksCtrl.text = '$_totalSelectedMarks';
    _goToStep(2);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Step 3 — Multi-format generation & export
  // ─────────────────────────────────────────────────────────────────────────

  String _getBaseFileName() {
    final sub = _subjectCtrl.text.trim().isNotEmpty
        ? _subjectCtrl.text.trim()
        : 'QuestionPaper';
    final exam =
        _examCtrl.text.trim().isNotEmpty ? '_${_examCtrl.text.trim()}' : '';
    return '$sub$exam'.replaceAll(RegExp(r'[^\w\u0980-\u09FF-]'), '_');
  }

  Future<void> _generateAndPreviewPdf() async {
    setState(() => _generating = true);
    try {
      final pdfBytes = await _buildPdf();
      if (!mounted) return;
      await Printing.layoutPdf(onLayout: (_) => pdfBytes);
    } catch (e) {
      _showError('PDF তৈরি করতে ব্যর্থ: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _sharePdfFile() async {
    setState(() => _generating = true);
    try {
      final pdfBytes = await _buildPdf();
      final file = await HighSchoolExportService.saveFile(
        content: '',
        fileName: '${_getBaseFileName()}.pdf',
        bytes: pdfBytes,
      );
      if (!mounted) return;
      await HighSchoolExportService.shareExportedFile(
        file,
        text:
            '${_examCtrl.text.trim().isNotEmpty ? _examCtrl.text : "Question Paper"} - PDF Document',
      );
    } catch (e) {
      _showError('PDF শেয়ার করতে ব্যর্থ: $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _exportWord({bool open = true}) async {
    try {
      // Word will not reliably render a remote <img>, so embed the bytes.
      final stemImages = _imageSize.isVisible
          ? await HighSchoolExportService.prefetchStemImages(_selectedQuestions)
          : <String, Uint8List>{};
      final doc = HighSchoolExportService.generateWordDoc(
        schoolName: _schoolCtrl.text,
        examName: _examCtrl.text,
        subject: _subjectCtrl.text,
        className: _classCtrl.text,
        time: _timeCtrl.text,
        totalMarks: _marksCtrl.text,
        questions: _selectedQuestions,
        imageBytes: stemImages,
        imageSize: _imageSize,
        setLabels: _twoSets ? _setLabels : const [],
        sectionOrder: _paperSectionOrder,
        cqLayout: _cqLayout,
        mcqLayout: _mcqLayout,
        rqLayout: _rqLayout,
        font: _paperFont,
      );
      final file = await HighSchoolExportService.saveFile(
        content: doc,
        fileName: '${_getBaseFileName()}.doc',
      );
      if (!mounted) return;
      if (open) {
        await HighSchoolExportService.openExportedFile(context, file);
      } else {
        await HighSchoolExportService.shareExportedFile(
          file,
          text: '${_examCtrl.text} - Word Document',
        );
      }
    } catch (e) {
      _showError('Word ফাইল তৈরি করতে সমস্যা: $e');
    }
  }

  Future<void> _exportHtml({bool open = true}) async {
    try {
      final html = HighSchoolExportService.generateHtml(
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

  Future<void> _exportText({bool open = true}) async {
    try {
      final text = HighSchoolExportService.generatePlainText(
        schoolName: _schoolCtrl.text,
        examName: _examCtrl.text,
        subject: _subjectCtrl.text,
        className: _classCtrl.text,
        time: _timeCtrl.text,
        totalMarks: _marksCtrl.text,
        questions: _selectedQuestions,
        imageSize: _imageSize,
        setLabels: _twoSets ? _setLabels : const [],
        sectionOrder: _paperSectionOrder,
      );
      final file = await HighSchoolExportService.saveFile(
        content: text,
        fileName: '${_getBaseFileName()}.txt',
      );
      if (!mounted) return;
      if (open) {
        await HighSchoolExportService.openExportedFile(context, file);
      } else {
        await HighSchoolExportService.shareExportedFile(
          file,
          text: '${_examCtrl.text} - Plain Text',
        );
      }
    } catch (e) {
      _showError('টেক্সট ফাইল তৈরি করতে সমস্যা: $e');
    }
  }

  Future<void> _exportMarkdown({bool open = true}) async {
    try {
      final md = HighSchoolExportService.generateMarkdown(
        schoolName: _schoolCtrl.text,
        examName: _examCtrl.text,
        subject: _subjectCtrl.text,
        className: _classCtrl.text,
        time: _timeCtrl.text,
        totalMarks: _marksCtrl.text,
        questions: _selectedQuestions,
        imageSize: _imageSize,
        setLabels: _twoSets ? _setLabels : const [],
        sectionOrder: _paperSectionOrder,
      );
      final file = await HighSchoolExportService.saveFile(
        content: md,
        fileName: '${_getBaseFileName()}.md',
      );
      if (!mounted) return;
      if (open) {
        await HighSchoolExportService.openExportedFile(context, file);
      } else {
        await HighSchoolExportService.shareExportedFile(
          file,
          text: '${_examCtrl.text} - Markdown Document',
        );
      }
    } catch (e) {
      _showError('Markdown ফাইল তৈরি করতে সমস্যা: $e');
    }
  }

  Future<void> _exportJson({bool open = true}) async {
    try {
      final json = HighSchoolExportService.generateJson(
        schoolName: _schoolCtrl.text,
        examName: _examCtrl.text,
        subject: _subjectCtrl.text,
        className: _classCtrl.text,
        time: _timeCtrl.text,
        totalMarks: _marksCtrl.text,
        questions: _selectedQuestions,
      );
      final file = await HighSchoolExportService.saveFile(
        content: json,
        fileName: '${_getBaseFileName()}.json',
      );
      if (!mounted) return;
      if (open) {
        await HighSchoolExportService.openExportedFile(context, file);
      } else {
        await HighSchoolExportService.shareExportedFile(
          file,
          text: '${_examCtrl.text} - JSON Data',
        );
      }
    } catch (e) {
      _showError('JSON ফাইল তৈরি করতে সমস্যা: $e');
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
    final html = HighSchoolExportService.generateHtml(
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

  void _copyAllText() {
    final text = HighSchoolExportService.generatePlainText(
      schoolName: _schoolCtrl.text,
      examName: _examCtrl.text,
      subject: _subjectCtrl.text,
      className: _classCtrl.text,
      time: _timeCtrl.text,
      totalMarks: _marksCtrl.text,
      questions: _selectedQuestions,
      imageSize: _imageSize,
      setLabels: _twoSets ? _setLabels : const [],
      sectionOrder: _paperSectionOrder,
    );
    HighSchoolExportService.copyToClipboard(context, text);
  }

  /// Render a string that mixes Bangla and Latin in the PDF.
  ///
  /// See [buildPdfTextSpan] for why this is needed and for the copyWith/font-slot
  /// trap it works around.
  pw.TextSpan _mixedText(String text, pw.TextStyle style) {
    final bold = style.fontWeight == pw.FontWeight.bold;
    return buildPdfTextSpan(text, style,
        bold: bold, measure: _measureForRender, symbolFont: _activeMathFont, symbolCoverage: _activeSymbolCoverage);
  }

  /// Measures text with the same engine the layout uses, so a typeset
  /// fraction's rule is exactly as wide as the estimator believes it is.
  ///
  /// Valid only while [_buildPdf] is running, which is when every widget is
  /// built; [PdfTextMetrics] needs font tables parsed once per export rather
  /// than once per string.
  double _measureForRender(String text, double fontSize, bool bold) {
    final metrics = _activeMetrics;
    if (metrics == null) return 0;
    return metrics.textWidth(text, fontSize: fontSize, bold: bold);
  }

  // ── Multi-column geometry ────────────────────────────────────────────────
  //
  // Widths and height estimates come from PdfLayout so the split is computed
  // against the same numbers the widgets below are built with.

  /// Lay out pre-balanced columns side by side.
  static pw.Widget _pdfColumnRow(List<List<pw.Widget>> columns) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < columns.length; i++) ...[
          if (i > 0) pw.SizedBox(width: PdfLayout.gutter),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.start,
              children: columns[i],
            ),
          ),
        ],
      ],
    );
  }

  /// Turn a column of [PdfFlowFragment]s into widgets.
  ///
  /// Consecutive fragments belonging to the same question are rebuilt as one
  /// widget, so a question that fits is drawn exactly as it always was. Only a
  /// question that genuinely straddles a column boundary is drawn as more than
  /// one piece, and it keeps its number in each piece.
  ///
  /// [afterQuestion] is emitted only when a question actually ends in this
  /// column. That mirrors the height estimates, which fold the trailing gap
  /// into a question's final fragment only — so a question split across
  /// columns carries its gap on the continuation, never on both halves.
  List<pw.Widget> _buildPdfFragmentColumn(
    List<PdfFlowFragment> column, {
    required pw.Widget Function(int index, int from, int to) itemBuilder,
    required pw.Widget Function() afterQuestion,
  }) {
    final widgets = <pw.Widget>[];
    var i = 0;

    while (i < column.length) {
      final question = column[i].question;
      var j = i;
      while (j + 1 < column.length && column[j + 1].question == question) {
        j++;
      }
      widgets.add(itemBuilder(
          question, column[i].indexInQuestion, column[j].indexInQuestion));
      if (column[j].isLast) widgets.add(afterQuestion());
      i = j + 1;
    }

    return widgets;
  }

  /// Append one set's masthead, set label and question sections to [widgets].
  ///
  /// [flow] is shared across sets on purpose: set খ has to know how much of the
  /// page set ক left, otherwise it would budget a full page, fail to fit under
  /// what is actually there, and jump to the next one — the blank-page problem
  /// the flow exists to prevent.
  /// Whether a section heading should sit inside the left column instead of
  /// spanning the page.
  ///
  /// Whether a section's heading is drawn at the top of the first column
  /// rather than spanning the page.
  bool _inlineSectionBanner(int columns, _SectionKind kind) {
    if (columns < 2) return false;

    // Only the heading that opens the page.
    //
    // A full-width bar across a multi-column section wastes a line and reads as
    // a page header rather than a question heading. That is fine for the
    // sections that follow, where the bar separates them from what came before
    // — but the one at the very top has nothing to separate, and a bar there
    // spans half a sheet of nothing.
    //
    // This is why CQ looked right when it was placed first and SQ did not:
    // CQ and the short questions merge into one flow that always draws its
    // headings inside the columns, while a short-question section printed on
    // its own was judged by a rule that also required two sets.
    return _activeSections.isNotEmpty && _activeSections.first == kind;
  }

  /// Prints a layout trace line, tagged so it is easy to filter.
  static void debugPrintTrace(String line) => debugPrint('[pdf-layout] $line');

  /// Start a new page when a section heading would be stranded at the foot of
  /// this one.
  ///
  /// Whole-question packing will not split a question across a page boundary,
  /// so a heading laid into the last few points of a page ends up alone on it
  /// with every one of its questions overleaf — a bar of text at the bottom of
  /// the sheet and nothing to introduce.
  ///
  /// The test is whether the heading plus the first question still fit. Without
  /// it the heading is emitted unconditionally and the decision is left to the
  /// packer, which then jumps.
  ///
  /// Both halves have to agree on the break: `pw.NewPage` makes the pdf package
  /// start a sheet, `flow.breakPage` stops the estimator packing against the
  /// page it has just left.
  void _keepHeadingWithContent({
    required List<pw.Widget> widgets,
    required PdfPageFlow flow,
    required double headingHeight,
    required double firstUnitHeight,
  }) {
    if (firstUnitHeight <= 0) return;

    final remaining = PdfLayout.contentHeight - flow.used - flow.margin;
    if (headingHeight + firstUnitHeight <= remaining) return;

    widgets.add(pw.NewPage());
    flow.breakPage();
  }

  /// Appends one set's masthead and sections.
  void _appendPdfSet(
    List<pw.Widget> widgets,
    PdfPageFlow flow, {
    required List<HighSchoolQuestion> cqs,
    required List<HighSchoolQuestion> mcqs,
    required List<HighSchoolQuestion> shorts,
    required String setLabel,
    required bool isFirstSet,
    required pw.TextStyle baseStyle,
    required pw.TextStyle boldStyle,
    required pw.TextStyle smallStyle,
    required pw.TextStyle headerStyle,
    required pw.TextStyle cqMarkStyle,
    required pw.TextStyle rqMarkStyle,
    required PdfTextMetrics metrics,
    required double bannerHeight,
    required Map<String, Uint8List> stemImages,
  }) {
    // ── Header ─────────────────────────────────────────────────────────
    widgets.add(_buildPdfHeader(
      schoolName: _schoolCtrl.text,
      examName: _examCtrl.text,
      subject: _subjectCtrl.text,
      setLabel: setLabel,
      className: _classCtrl.text,
      time: _timeCtrl.text,
      totalMarks: _marksCtrl.text,
      baseStyle: baseStyle,
      boldStyle: boldStyle,
      headerStyle: headerStyle,
      smallStyle: smallStyle,
    ));

    widgets.add(pw.SizedBox(height: PdfLayout.headerAfterGap));
    flow.consume(PdfLayout.headerHeight(
          metrics: metrics,
          fontStep: _fontStep,
          schoolName: _schoolCtrl.text,
          examName: _examCtrl.text,
          subject: _subjectCtrl.text,
          className: _classCtrl.text,
          time: _timeCtrl.text,
          totalMarks: _marksCtrl.text,
        ) +
        PdfLayout.headerAfterGap);

    // A set that holds one type of question has nothing to tell apart, so its
    // lone declaration — «ক-বিভাগ: বহুনির্বাচনী প্রশ্ন (MCQ)» — is dropped and
    // the questions print on their own. The instruction line under the bar
    // stays: it is a directive, not a label. The air that separates one block
    // from the next stays too. The export service reads it the same way, so a
    // sheet looks the same on paper as it does in the browser.
    final declares = [cqs, shorts, mcqs].where((l) => l.isNotEmpty).length > 1;
    final double bandHeight = declares ? bannerHeight : 0;

    // The sections are declared below as closures and dispatched in the order
    // the reader arranged them, so dragging one in the last step really does
    // move it on the page. CQ and the short questions share one continuous
    // flow only while they sit next to each other; see [_mergesCqAndShorts].

    // ── CQ Section ─────────────────────────────────────────────────────
    void emitCq() {
      if (cqs.isNotEmpty) {
        final cqBanner = _pdfSectionBanner(
            '${_sectionLetter(_SectionKind.cq)}-বিভাগ: সৃজনশীল প্রশ্ন (CQ)',
            boldStyle.copyWith(fontSize: _typeSize(PdfLayout.bodyFontSize)));
        // Inline means the heading rides at the top of the first block's left
        // column instead of spanning the page — see the insert below. A
        // full-width box thrown across a narrow half-sheet wastes a line.
        final cqCols = _cqLayout.mcqColumns;
        final cqInline = _inlineSectionBanner(cqCols, _SectionKind.cq);
        // Optional "answer any N questions" note. Its height is needed before
        // the heading is placed, so it is measured first.
        final answerAny = _cqAnswerCount;
        final answerAnyText = '[যেকোনো $answerAny টি প্রশ্নের উত্তর দাও]';
        final noteHeight = answerAny > 0
            ? 4 +
                metrics.lineHeight(answerAnyText,
                    fontSize: _typeSize(PdfLayout.smallFontSize))
            : 0.0;

        // Balanced newspaper columns rather than rows of two, so a short
        // question no longer inherits the full height of the tallest
        // question beside it. Questions are packed as fragments, which lets
        // the foot of a page be filled instead of left blank. See
        // [balanceColumns] and [PdfPageFlow].
        //
        // Measured before the heading is drawn, because whether the heading
        // fits on this page at all depends on the first question's height.
        final cqWidth = PdfLayout.columnWidth(cqCols);
        final cqFragments = <PdfFlowFragment>[];
        for (int i = 0; i < cqs.length; i++) {
          final parts = PdfLayout.cqFragments(
            index: i + 1,
            question: cqs[i],
            columnWidth: cqWidth,
            metrics: metrics,
            hasImage: stemImages.containsKey(
                HighSchoolExportService.resolveImageUrl(cqs[i].stemImageUrl)),
            imageSize: _imageSize,
            fontStep: _fontStep,
          );
          for (var p = 0; p < parts.length; p++) {
            cqFragments.add(PdfFlowFragment(
              height: parts[p],
              question: i,
              indexInQuestion: p,
              isFirst: p == 0,
              isLast: p == parts.length - 1,
            ));
          }
        }

        _keepHeadingWithContent(
          widgets: widgets,
          flow: flow,
          headingHeight: bandHeight +
              (declares ? PdfLayout.sectionBannerGap : 0) +
              noteHeight,
          firstUnitHeight: cqFragments.isEmpty ? 0 : cqFragments.first.height,
        );

        if (!cqInline && declares) {
          widgets.add(cqBanner);
        }
        if (answerAny > 0) {
          widgets.add(pw.SizedBox(height: 4));
          widgets.add(pw.RichText(
            text: _mixedText(answerAnyText,
                smallStyle.copyWith(fontStyle: pw.FontStyle.italic)),
            textAlign: pw.TextAlign.center,
          ));
          flow.consume(noteHeight);
        }
        // The heading needs air *under* it. When it is inline it is drawn
        // inside the first column, so a SizedBox added here would sit above the
        // heading and leave it flush against the first question — which is
        // exactly what it looked like.
        if (!cqInline && declares) {
          widgets.add(pw.SizedBox(height: PdfLayout.sectionBannerGap));
        }
        // The declaration band is charged here and nowhere else. The
        // inline/full-width branch used to charge it as well, so the flow
        // reserved the heading's height twice in the two-set layout and every
        // column came up short.
        flow.consume(bandHeight + (declares ? PdfLayout.sectionBannerGap : 0));

        final cqRows = flow.layoutFragments(
            fragments: cqFragments,
            columns: cqCols,
            trailingGap: 16,
            trace: kTracePdfLayout ? debugPrintTrace : null);

        // One unbreakable row of columns per page's worth of questions, so a
        // long section still flows instead of overflowing a single block.
        for (var bi = 0; bi < cqRows.length; bi++) {
          final row = cqRows[bi];
          final columns = <List<pw.Widget>>[];
          for (final column in row) {
            columns.add(_buildPdfFragmentColumn(
              column,
              itemBuilder: (qIndex, from, to) => _buildPdfCqCard(
                index: qIndex + 1,
                question: cqs[qIndex],
                baseStyle: baseStyle,
                boldStyle: boldStyle,
                smallStyle: smallStyle,
                markStyle: cqMarkStyle,
                stemImages: stemImages,
                imageSize: _imageSize,
                partFrom: from,
                partTo: to,
              ),
              afterQuestion: () => pw.SizedBox(height: PdfLayout.cqCardGap),
            ));
          }
          if (bi == 0 && cqInline && declares && columns.isNotEmpty) {
            // The heading carries its own gap into the column, so it reads the
            // same as a full-width one.
            columns.first.insertAll(0, [
              cqBanner,
              pw.SizedBox(height: PdfLayout.sectionBannerGap),
            ]);
          }
          widgets.add(_pdfColumnRow(columns));
          widgets.add(pw.SizedBox(height: 16));
        }
      }
    }

    // ── MCQ Section ────────────────────────────────────────────────────
    void emitMcq() {
      _appendPdfMcqSection(
        widgets,
        flow,
        mcqs: mcqs,
        baseStyle: baseStyle,
        boldStyle: boldStyle,
        smallStyle: smallStyle,
        bannerHeight: bandHeight,
        declares: declares,
        metrics: metrics,
        stemImages: stemImages,
        imageSize: _imageSize,
      );
    }

    // ── Short question section (গ-বিভাগ) ───────────────────────────────
    void emitRq() {
      if (shorts.isNotEmpty) {
        final rqBanner = _pdfSectionBanner(
            '${_sectionLetter(_SectionKind.rq)}-বিভাগ: সংক্ষিপ্ত প্রশ্ন (SQ)',
            boldStyle.copyWith(fontSize: _typeSize(PdfLayout.bodyFontSize)));
        final rqCols = _rqLayout.mcqColumns;
        final rqInline = _inlineSectionBanner(rqCols, _SectionKind.rq);

        final rqWidth = PdfLayout.columnWidth(rqCols);
        // Measured first: the heading only belongs on this page if the first
        // question fits beside it.
        final rqHeights = [
          for (int i = 0; i < shorts.length; i++)
            PdfLayout.rqHeight(
              index: i + 1,
              question: shorts[i],
              columnWidth: rqWidth,
              metrics: metrics,
              fontStep: _fontStep,
            ),
        ];

        _keepHeadingWithContent(
          widgets: widgets,
          flow: flow,
          headingHeight: (rqInline ? 0 : PdfLayout.sectionGap) +
              bandHeight +
              (declares ? PdfLayout.sectionBannerGap : 0),
          firstUnitHeight: rqHeights.isEmpty ? 0 : rqHeights.first,
        );

        if (!rqInline) {
          widgets.add(pw.SizedBox(height: PdfLayout.sectionGap));
          if (declares) widgets.add(rqBanner);
        }
        // Under the heading, which is inside the column when rqInline — see
        // the insert below.
        if (!rqInline && declares) {
          widgets.add(pw.SizedBox(height: PdfLayout.sectionBannerGap));
        }
        flow.consume((rqInline ? 0 : PdfLayout.sectionGap) +
            bandHeight +
            (declares ? PdfLayout.sectionBannerGap : 0));

        final rqRows = flow.layout(
          heights: rqHeights,
          columns: rqCols,
          trailingGap: 0,
        );

        for (var bi = 0; bi < rqRows.length; bi++) {
          final row = rqRows[bi];
          final columns = <List<pw.Widget>>[];
          for (final column in row) {
            columns.add(_buildPdfFragmentColumn(
              column,
              // A short question is a single line, so it is never split.
              itemBuilder: (i, from, to) {
                final data = shorts[i].shortData;
                return pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: PdfLayout.rqGap),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: pw.RichText(
                            text: _mixedText(
                                '${i + 1}. ${data!.text}', baseStyle)),
                      ),
                      pw.SizedBox(width: 12),
                      pw.RichText(
                          text: _mixedText('[${data.mark}]', rqMarkStyle)),
                    ],
                  ),
                );
              },
              afterQuestion: () => pw.SizedBox.shrink(),
            ));
          }
          if (bi == 0 && rqInline && declares && columns.isNotEmpty) {
            columns.first.insertAll(0, [
              rqBanner,
              pw.SizedBox(height: PdfLayout.sectionBannerGap),
            ]);
          }
          widgets.add(_pdfColumnRow(columns));
        }
      }
    }

    // ── Dispatch, in the order the reader arranged ─────────────────────
    //
    // CQ and the short questions are emitted as one continuous run of blocks
    // when they sit next to each other on a two-set, two-column sheet; the
    // heading for each then lands wherever that flow reaches its type instead
    // of each section starting a fresh full-width row. Separating them with a
    // drag turns the merge off and both print as ordinary sections.
    final mergeCqAndShorts = _mergesCqAndShorts &&
        _cqLayout.mcqColumns > 1 &&
        _rqLayout.mcqColumns > 1;

    if (mergeCqAndShorts) {
      // A merged run is one continuous flow, so MCQ cannot be spliced into the
      // middle of it. Whatever the reader put *before* the run is emitted
      // first; anything after it lands after, as before.
      final mcqOpens =
          _activeSections.isNotEmpty && _activeSections.first.isMcq;
      if (mcqOpens) emitMcq();

      _appendPdfCqAndShortSection(
        widgets,
        flow,
        cqs: cqs,
        shorts: shorts,
        baseStyle: baseStyle,
        boldStyle: boldStyle,
        smallStyle: smallStyle,
        cqMarkStyle: cqMarkStyle,
        rqMarkStyle: rqMarkStyle,
        metrics: metrics,
        bannerHeight: bandHeight,
        declares: declares,
        stemImages: stemImages,
      );

      if (!mcqOpens) {
        for (final kind in _activeSections) {
          if (kind.isMcq) emitMcq();
        }
      }
      return;
    }

    for (final kind in _activeSections) {
      if (kind.isCq) {
        emitCq();
      } else if (kind.isMcq) {
        emitMcq();
      } else {
        emitRq();
      }
    }
  }

  /// The MCQ section as its own block.
  ///
  /// Extracted so it can be emitted anywhere the dispatch puts it, or — when
  /// CQ and the short questions share a flow — after them.
  void _appendPdfMcqSection(
    List<pw.Widget> widgets,
    PdfPageFlow flow, {
    required List<HighSchoolQuestion> mcqs,
    required pw.TextStyle baseStyle,
    required pw.TextStyle boldStyle,
    required pw.TextStyle smallStyle,
    required PdfTextMetrics metrics,
    required double bannerHeight,

    /// False when this set holds nothing but MCQs, so the block prints without
    /// its declaration. See the call site in [_appendPdfSet].
    required bool declares,
    required Map<String, Uint8List> stemImages,
    required StemImageSize imageSize,
  }) {
    // ── MCQ Section ────────────────────────────────────────────────────
    if (mcqs.isNotEmpty) {
      final mcqBanner = _pdfSectionBanner(
          '${_sectionLetter(_SectionKind.mcq)}-বিভাগ: বহুনির্বাচনী প্রশ্ন (MCQ)',
          boldStyle.copyWith(fontSize: _typeSize(PdfLayout.bodyFontSize)));
      // MCQ arranged in balanced columns per the layout setting.
      final cols = _mcqLayout.mcqColumns;
      final mcqInline = _inlineSectionBanner(cols, _SectionKind.mcq);
      const tickNote = '[সঠিক উত্তরের পাশে টিক (✓) চিহ্ন দাও]';

      final mcqWidth = PdfLayout.columnWidth(cols);

      // How a group of MCQs under one উদ্দীপক is printed: the intro and its
      // figure ride at the head of the question that opens the group, and the
      // questions under it print bare. Both the estimator and the item ask
      // these, so the room budgeted for a question is the room it draws.
      bool opensStem(int i) =>
          mcqs[i].opensMcqStemGroup(i == 0 ? null : mcqs[i - 1]);

      /// The intro as it prints: a shared উদ্দীপক names the numbers the paper
      /// gives the questions under it, not the ones the bank copied out of the
      /// board paper. Both the estimator and the card read this, so the room
      /// booked for the intro is the room it draws.
      String stemTextOf(int i) => opensStem(i)
          ? HighSchoolExportService.stemWithNumbers(
              mcqs[i].mcqStemText,
              HighSchoolExportService.mcqStemRunNumbers(mcqs, i))
          : '';

      bool hasStemImage(int i) =>
          opensStem(i) &&
          imageSize.isVisible &&
          HighSchoolExportService.resolveImageUrl(mcqs[i].stemImageUrl)
              .isNotEmpty;
      Uint8List? stemBytesOf(int i) => hasStemImage(i)
          ? stemImages[
              HighSchoolExportService.resolveImageUrl(mcqs[i].stemImageUrl)]
          : null;

      // The packer fills the foot of a page one *fragment* at a time — a stem
      // can sit at the bottom with its options continuing overleaf — so the
      // heading is judged against the same unit. Asking for the whole first
      // question here was stricter than the packer it guards: with room for the
      // heading and the stem but not all four options, the heading was pushed to
      // the next sheet and left a band of blank paper at the foot of this one.
      // The CQ guard has always measured its first fragment this way.
      final firstMcqParts = mcqs.isEmpty
          ? const <double>[]
          : PdfLayout.mcqFragments(
              index: 1,
              question: mcqs.first,
              columnWidth: mcqWidth,
              metrics: metrics,
              fontStep: _fontStep,
              withStem: opensStem(0),
              stemText: stemTextOf(0),
              hasImage: hasStemImage(0),
              imageSize: imageSize,
            );

      _keepHeadingWithContent(
        widgets: widgets,
        flow: flow,
        headingHeight: (mcqInline ? 0 : PdfLayout.sectionGap) +
            bannerHeight +
            4 +
            metrics.lineHeight(tickNote,
                fontSize: _typeSize(PdfLayout.smallFontSize)) +
            (declares ? PdfLayout.sectionBannerGap : 0),
        firstUnitHeight: firstMcqParts.isEmpty ? 0 : firstMcqParts.first,
      );

      if (!mcqInline) {
        widgets.add(pw.SizedBox(height: PdfLayout.sectionGap));
        if (declares) widgets.add(mcqBanner);
      }
      widgets.add(pw.SizedBox(height: 4));
      widgets.add(pw.RichText(
          text: _mixedText(
              tickNote, smallStyle.copyWith(fontStyle: pw.FontStyle.italic)),
          textAlign: pw.TextAlign.center));
      // Under the heading, which is inside the column when mcqInline — see the
      // insert below.
      if (!mcqInline && declares) {
        widgets.add(pw.SizedBox(height: PdfLayout.sectionBannerGap));
      }
      // Charge exactly what is drawn: the leading gap only exists when the
      // banner spans the page, because an inline banner sits inside the first
      // column instead.
      flow.consume((mcqInline ? 0 : PdfLayout.sectionGap) +
          bannerHeight +
          4 +
          metrics.lineHeight(tickNote,
              fontSize: _typeSize(PdfLayout.smallFontSize)) +
          (declares ? PdfLayout.sectionBannerGap : 0));

      final mcqFragments = <PdfFlowFragment>[];
      for (int i = 0; i < mcqs.length; i++) {
        final parts = PdfLayout.mcqFragments(
          index: i + 1,
          question: mcqs[i],
          columnWidth: mcqWidth,
          metrics: metrics,
          fontStep: _fontStep,
          withStem: opensStem(i),
          stemText: stemTextOf(i),
          hasImage: hasStemImage(i),
          imageSize: imageSize,
        );
        for (var p = 0; p < parts.length; p++) {
          mcqFragments.add(PdfFlowFragment(
            height: parts[p],
            question: i,
            indexInQuestion: p,
            isFirst: p == 0,
            isLast: p == parts.length - 1,
          ));
        }
      }

      final mcqRows = flow.layoutFragments(
          fragments: mcqFragments, columns: cols, trailingGap: 12);

      for (var bi = 0; bi < mcqRows.length; bi++) {
        final row = mcqRows[bi];
        final columns = <List<pw.Widget>>[];
        for (final column in row) {
          columns.add(_buildPdfFragmentColumn(
            column,
            itemBuilder: (qIndex, from, to) => _buildPdfMcqItem(
                qIndex + 1, mcqs[qIndex], baseStyle,
                columnWidth: mcqWidth,
                metrics: metrics,
                withStem: opensStem(qIndex),
                stemText: stemTextOf(qIndex),
                stemBytes: stemBytesOf(qIndex),
                imageSize: imageSize,
                partFrom: from,
                partTo: to),
            // The rule belongs *between* questions, so a column that ends
            // on a question is not left with a trailing divider.
            afterQuestion: () => pw.Padding(
              padding: const pw.EdgeInsets.only(top: 6, bottom: 6),
              child: _pdfDashedLine(),
            ),
          ));
        }
        if (bi == 0 && mcqInline && declares && columns.isNotEmpty) {
          columns.first.insertAll(0, [
            mcqBanner,
            pw.SizedBox(height: PdfLayout.sectionBannerGap),
          ]);
        }
        widgets.add(_pdfColumnRow(columns));
        widgets.add(pw.SizedBox(height: 12));
      }
    }
  }

  /// CQ and short questions as one continuous flow.
  ///
  /// The two sections are packed together, so the short-question heading is
  /// emitted exactly where the creative questions run out — mid-column or at
  /// the head of the next one — instead of the short questions always starting
  /// a fresh full-width row below whatever the CQ block left over.
  ///
  /// Only used for a two-set, two-column paper; anything else keeps the
  /// familiar ক-বিভাগ → খ-বিভাগ → গ-বিভাগ order.
  void _appendPdfCqAndShortSection(
    List<pw.Widget> widgets,
    PdfPageFlow flow, {
    required List<HighSchoolQuestion> cqs,
    required List<HighSchoolQuestion> shorts,
    required pw.TextStyle baseStyle,
    required pw.TextStyle boldStyle,
    required pw.TextStyle smallStyle,
    required pw.TextStyle cqMarkStyle,
    required pw.TextStyle rqMarkStyle,
    required PdfTextMetrics metrics,
    required double bannerHeight,

    /// Whether the blocks print their declarations. See [_appendPdfSet].
    required bool declares,
    required Map<String, Uint8List> stemImages,
  }) {
    final cqCols = _cqLayout.mcqColumns;
    final cqWidth = PdfLayout.columnWidth(cqCols);
    final rqWidth = PdfLayout.columnWidth(_rqLayout.mcqColumns);

    // A pseudo question id for each heading. Fragments are grouped by question
    // when they are turned back into widgets, so giving the headings an id of
    // their own lets them ride in the flow and land wherever the packer puts
    // them, still in reading order.
    final cqBannerId = cqs.length + shorts.length;
    final rqBannerId = cqBannerId + 1;

    final fragments = <PdfFlowFragment>[];
    void add(double height, int question, int part, bool first, bool last) =>
        fragments.add(PdfFlowFragment(
            height: height,
            question: question,
            // Which part of the question this is. The renderer slices a card
            // from [partFrom, partTo], so a wrong index here draws the stem
            // where a sub-question belongs — and, when the card straddles a
            // column boundary, draws the stem twice.
            indexInQuestion: part,
            isFirst: first,
            isLast: last));

    // In the reader's order, so that placing the short questions first makes
    // the CQ part begin where they end rather than starting the flow afresh.
    for (final kind in _activeSections) {
      if (kind.isCq) {
        // The merged run only exists between two blocks, so there is always a
        // declaration here — but the flag is read rather than assumed.
        if (declares) {
          add(bannerHeight + PdfLayout.mergedHeadingGap, cqBannerId, 0, true,
              true);
        }
        for (int i = 0; i < cqs.length; i++) {
          final parts = PdfLayout.cqFragments(
            index: i + 1,
            question: cqs[i],
            columnWidth: cqWidth,
            metrics: metrics,
            hasImage: stemImages.containsKey(
                HighSchoolExportService.resolveImageUrl(cqs[i].stemImageUrl)),
            imageSize: _imageSize,
            fontStep: _fontStep,
          );
          for (var p = 0; p < parts.length; p++) {
            add(parts[p], i, p, p == 0, p == parts.length - 1);
          }
        }
      } else if (kind.isRq) {
        // MCQ must not fall into this branch. It is not part of the merged run
        // — the dispatcher emits it on its own — and letting it through here
        // printed the whole short-question section a second time, once for the
        // MCQ entry and once for the SQ entry.
        if (declares) {
          add(bannerHeight + PdfLayout.mergedHeadingGap, rqBannerId, 0, true,
              true);
        }
        for (int i = 0; i < shorts.length; i++) {
          final parts = PdfLayout.rqFragments(
            index: i + 1,
            question: shorts[i],
            columnWidth: rqWidth,
            metrics: metrics,
            fontStep: _fontStep,
          );
          for (var p = 0; p < parts.length; p++) {
            add(parts[p], cqs.length + i, p, p == 0, p == parts.length - 1);
          }
        }
      }
    }

    final rows = flow.layoutFragments(
      fragments: fragments,
      columns: cqCols,
      trailingGap: 16,
      trace: kTracePdfLayout ? debugPrintTrace : null,
    );

    // Set by the item builder so the trailing gap knows what just ended.
    var lastQuestion = -1;
    for (var bi = 0; bi < rows.length; bi++) {
      final columns = <List<pw.Widget>>[];
      for (final column in rows[bi]) {
        columns.add(_buildPdfFragmentColumn(
          column,
          itemBuilder: (qIndex, from, to) {
            lastQuestion = qIndex;
            // The gap has to be a real widget, not just extra height booked
            // on the fragment: children of a pw.Column are placed at their own
            // heights, so reserving space in the flow alone draws nothing.
            if (qIndex == cqBannerId || qIndex == rqBannerId) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _pdfSectionBanner(
                      qIndex == cqBannerId
                          ? '${_sectionLetter(_SectionKind.cq)}-বিভাগ: সৃজনশীল প্রশ্ন (CQ)'
                          : '${_sectionLetter(_SectionKind.rq)}-বিভাগ: সংক্ষিপ্ত প্রশ্ন (SQ)',
                      boldStyle.copyWith(
                          fontSize: _typeSize(PdfLayout.bodyFontSize))),
                  pw.SizedBox(height: PdfLayout.mergedHeadingGap),
                ],
              );
            }
            if (qIndex >= cqs.length) {
              final i = qIndex - cqs.length;
              final data = shorts[i].shortData;
              return pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: PdfLayout.rqGap),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: pw.RichText(
                          text:
                              _mixedText('${i + 1}. ${data!.text}', baseStyle)),
                    ),
                    pw.SizedBox(width: 12),
                    pw.RichText(
                        text: _mixedText('[${data.mark}]', rqMarkStyle)),
                  ],
                ),
              );
            }
            return _buildPdfCqCard(
              index: qIndex + 1,
              question: cqs[qIndex],
              baseStyle: baseStyle,
              boldStyle: boldStyle,
              smallStyle: smallStyle,
              markStyle: cqMarkStyle,
              stemImages: stemImages,
              imageSize: _imageSize,
              partFrom: from,
              partTo: to,
            );
          },
          // Short questions carry their own bottom padding; only the CQ cards
          // need a gap after them.
          afterQuestion: () => pw.SizedBox(
              height: lastQuestion < cqs.length ? PdfLayout.cqCardGap : 0),
        ));
      }
      widgets.add(_pdfColumnRow(columns));
      widgets.add(pw.SizedBox(height: 16));
    }
  }

  Future<Uint8List> _buildPdf() async {
    final doc = pw.Document();

    // Stem images must be downloaded up front: the pdf package renders from
    // bytes, and MultiPage.build() is synchronous so it cannot fetch there.
    final stemImages = _imageSize.isVisible
        ? await HighSchoolExportService.prefetchStemImages(_selectedQuestions)
        : <String, Uint8List>{};

    // Bangla: SutonnyMJ (Bijoy-ANSI encoding).
    pw.Font? banglaFont;
    ByteData? banglaFontData;
    try {
      final fontData =
          await rootBundle.load('assets/fonts/SutonnyMJ Regular.ttf');
      banglaFontData = fontData;
      banglaFont = pw.Font.ttf(fontData);
    } catch (_) {
      // Font not found – PDF will show blank for Bangla text
    }

    // Math glyphs (∩ ∪ ∈ ∅ ≠ ≤ ≥ × √ Σ − α β ² → ≈ ± …). Neither SutonnyMJ nor
    // the PDF base-14 fonts carry them, so without this the pdf package logs
    // "Unable to find a font to draw ..." and draws nothing.
    pw.Font? mathFont;
    ByteData? mathFontData;
    try {
      final fontData = await rootBundle.load('assets/fonts/MathSymbols.ttf');
      mathFontData = fontData;
      mathFont = pw.Font.ttf(fontData);
    } catch (_) {
      // Font not found – math symbols will be skipped
    }
    final fallback = mathFont == null ? const <pw.Font>[] : <pw.Font>[mathFont];

    // Measures text with the very fonts used below, so the multi-column split
    // is computed from real glyph widths rather than a character-count guess.
    // The symbol font is needed here too: base-14 fonts throw outright on
    // anything outside Latin-1, so ≤ √ π − must be measured with a TTF.
    final metrics = PdfTextMetrics(
      banglaFontData: banglaFontData,
      symbolFontData: mathFontData,
    );
    // Available to _mixedText for the whole build, so a typeset fraction can be
    // measured with the same engine the layout used.
    _activeMetrics = metrics;
    _activeMathFont = mathFont;
    if (mathFontData != null) {
      try {
        // Read the symbol font's cmap so the renderer can route math glyphs
        // to it instead of leaving them in Helvetica (which has no ∪ ∩ ≤ …).
        // TtfParser is internal to the pdf package but exposes exactly this.
        final parser = TtfParser(mathFontData);
        _activeSymbolCoverage = parser.charToGlyphIndexMap.keys.toSet();
      } catch (_) {
        _activeSymbolCoverage = null;
      }
    } else {
      _activeSymbolCoverage = null;
    }

    // Every size here is the paper's *base* size; _typeSize shifts them all by
    // the same step. The step reaches PdfLayout's height estimators too, so what
    // is drawn and what the flow budgeted for stay the same number.
    final baseStyle = pw.TextStyle(
      font: banglaFont,
      fontFallback: fallback,
      fontSize: _typeSize(PdfLayout.bodyFontSize),
      color: PdfColors.black,
    );
    final boldStyle = pw.TextStyle(
      font: banglaFont,
      fontFallback: fallback,
      fontSize: _typeSize(PdfLayout.bodyFontSize),
      fontWeight: pw.FontWeight.bold,
    );
    final headerStyle = pw.TextStyle(
      font: banglaFont,
      fontFallback: fallback,
      fontSize: _typeSize(14),
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.black,
    );
    final smallStyle = pw.TextStyle(
      font: banglaFont,
      fontFallback: fallback,
      fontSize: _typeSize(PdfLayout.smallFontSize),
      color: PdfColors.grey700,
    );
    // Marks are annotations, not content: normal weight and a soft grey, so a
    // printed paper's question text reads before its `[2]` / `[3]` labels.
    // Deliberately neither black nor grey700 — the two extremes that made the
    // marks either shout or disappear on paper.
    final markColor = PdfColors.grey500;
    final cqMarkStyle = pw.TextStyle(
      font: banglaFont,
      fontFallback: fallback,
      fontSize: _typeSize(PdfLayout.smallFontSize),
      color: markColor,
    );
    final rqMarkStyle = pw.TextStyle(
      font: banglaFont,
      fontFallback: fallback,
      fontSize: _typeSize(PdfLayout.bodyFontSize),
      color: markColor,
    );

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      // Bound to PdfLayout so the page and the flow simulation can never
      // disagree about how much room a page actually has.
      margin: const pw.EdgeInsets.only(
        left: PdfLayout.pageMarginH,
        right: PdfLayout.pageMarginH,
        top: PdfLayout.pageMarginTop,
        bottom: PdfLayout.pageMarginBottom,
      ),
      build: (ctx) {
        final widgets = <pw.Widget>[];

        // Replays the page fill so each block of columns is sized to the space
        // actually left. Without this the CQ block is budgeted for a whole page,
        // never fits under the masthead, and jumps to page 2 — leaving page 1
        // almost blank. See PdfPageFlow.
        final flow = PdfPageFlow(contentHeight: PdfLayout.contentHeight);
        final bannerHeight =
            PdfLayout.sectionBannerHeight(metrics, fontStep: _fontStep);
        final labels = _setLabels;

        // One set, or two variants of the same paper on the same document.
        void addSet(List<pw.Widget> into, PdfPageFlow intoFlow, int s) {
          final setQuestions = _questionsForSet(s);
          _appendPdfSet(
            into,
            intoFlow,
            cqs: setQuestions.where((q) => q.isCq).toList(),
            mcqs: setQuestions.where((q) => q.isMcq).toList(),
            shorts: setQuestions.where((q) => q.isShort).toList(),
            setLabel: labels.length > 1 ? labels[s] : '',
            isFirstSet: s == 0,
            baseStyle: baseStyle,
            boldStyle: boldStyle,
            smallStyle: smallStyle,
            headerStyle: headerStyle,
            cqMarkStyle: cqMarkStyle,
            rqMarkStyle: rqMarkStyle,
            metrics: metrics,
            bannerHeight: bannerHeight,
            stemImages: stemImages,
          );
        }

        for (var s = 0; s < labels.length; s++) {
          if (s > 0) {
            // Share the sheet if this set fits in what is left of it, otherwise
            // start a fresh one.
            //
            // It has to be measured first. Whole-question packing refuses to
            // split a question across a boundary, so when the first question of
            // the second set would not fit, it used to jump to a new page and
            // leave a large blank behind — often stranding the masthead alone at
            // the foot of the first page with its questions overleaf.
            //
            // Laid out against a page of its own to find out what it needs.
            // Building widgets costs nothing; only drawing them does.
            final probe = <pw.Widget>[];
            final probeFlow =
                PdfPageFlow(contentHeight: PdfLayout.contentHeight);
            addSet(probe, probeFlow, s);

            final remaining = PdfLayout.contentHeight - flow.used - flow.margin;
            final divider = labels.length > 1
                ? PdfLayout.setDividerGapAbove +
                    PdfLayout.setDividerGapBelow +
                    1
                : 0.0;

            if (probeFlow.used + divider > remaining) {
              // Both halves must agree on the break: `pw.NewPage` makes the pdf
              // package start a sheet, and `flow.breakPage` stops the estimator
              // packing against the page it has just left. Telling only one
              // leaves the two disagreeing about where the page ended.
              widgets.add(pw.NewPage());
              flow.breakPage();
            } else if (divider > 0) {
              // A fixed rule, not one sized from the leftover height: a computed
              // gap is what pushes content onto the next page when the estimate
              // runs out.
              widgets.add(pw.SizedBox(height: PdfLayout.setDividerGapAbove));
              widgets.add(_pdfDashedLine(color: PdfColors.grey500));
              widgets.add(pw.SizedBox(height: PdfLayout.setDividerGapBelow));
              flow.consume(divider);
            }
          }
          addSet(widgets, flow, s);
        }

        return widgets;
      },
    ));

    return await doc.save();
  }

  /// A dashed horizontal rule, matching the HTML export's dashed separators.
  pw.Widget _pdfDashedLine({PdfColor color = PdfColors.grey400}) {
    return pw.LayoutBuilder(builder: (ctx, constraints) {
      // LayoutBuilder hands back BoxConstraints (null outside a layout pass).
      final width = constraints?.maxWidth;
      const dash = 4.0;
      const gap = 3.0;
      final available = (width == null || width.isInfinite) ? 400.0 : width;
      final count = (available / (dash + gap)).floor().clamp(1, 400);
      return pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: List.generate(
          count,
          (_) => pw.Container(width: dash, height: 0.6, color: color),
        ),
      );
    });
  }

  /// Grey section heading bar, mirroring the HTML `.section-banner`.
  pw.Widget _pdfSectionBanner(String label, pw.TextStyle style) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey200,
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.RichText(
        text: _mixedText(label, style),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  /// Mirrors the HTML header: big centred titles above a ruled meta bar.
  pw.Widget _buildPdfHeader({
    required String schoolName,
    required String examName,
    required String subject,
    required String className,
    String setLabel = '',
    required String time,
    required String totalMarks,
    required pw.TextStyle baseStyle,
    required pw.TextStyle boldStyle,
    required pw.TextStyle headerStyle,
    required pw.TextStyle smallStyle,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (schoolName.trim().isNotEmpty)
          pw.RichText(
              text: _mixedText(
                  schoolName, headerStyle.copyWith(fontSize: _typeSize(15)))),
        pw.SizedBox(height: PdfLayout.headerTitleGap),
        pw.RichText(
            text: _mixedText(
                examName, boldStyle.copyWith(fontSize: _typeSize(12)))),
        pw.SizedBox(height: PdfLayout.headerExamGap),
        // `height` must be given: dart_pdf's Divider defaults to *16pt* tall and
        // centres the rule inside that, so each of the masthead's two rules
        // carried ~7.4pt of padding above and below it that [headerHeight] never
        // charged — about 30pt of unaccounted masthead on page 1, which is the
        // kind of drift that costs a whole block at the foot of the sheet.
        pw.Divider(
            height: PdfLayout.headerDivider,
            thickness: PdfLayout.headerDivider,
            color: PdfColors.black),
        pw.SizedBox(height: PdfLayout.headerMetaGap),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            // The set name rides in the meta bar rather than taking a banner of
            // its own: a fifth field costs nothing vertically, and every point
            // of masthead is a point the questions cannot use.
            if (setLabel.isNotEmpty)
              pw.RichText(
                  text: _mixedText('সেট: $setLabel',
                      boldStyle.copyWith(color: PdfColors.grey700))),
            pw.RichText(text: _mixedText('বিষয়: $subject', boldStyle)),
            // Class and total marks are metadata, not headings. Bolding every
            // field made the meta bar compete with the exam name above it.
            pw.RichText(text: _mixedText('শ্রেণি: $className', baseStyle)),
            pw.RichText(text: _mixedText('সময়: $time', boldStyle)),
            pw.RichText(text: _mixedText('পূর্ণমান: $totalMarks', baseStyle)),
          ],
        ),
        pw.SizedBox(height: PdfLayout.headerMetaGap),
        // Sized, like the rule above it — see the note there.
        pw.Divider(
            height: PdfLayout.headerDivider,
            thickness: PdfLayout.headerDivider,
            color: PdfColors.black),
      ],
    );
  }

  /// Mirrors the HTML `.cq-card`: plain border, no badges, no colour.
  pw.Widget _buildPdfCqCard(
      {required int index,
      required HighSchoolQuestion question,
      required pw.TextStyle baseStyle,
      required pw.TextStyle boldStyle,
      required pw.TextStyle smallStyle,
      required pw.TextStyle markStyle,
      Map<String, Uint8List> stemImages = const {},
      StemImageSize imageSize = StemImageSize.medium,
      int partFrom = 0,
      int partTo = 1 << 20}) {
    final stemBytes = imageSize.isVisible
        ? stemImages[
            HighSchoolExportService.resolveImageUrl(question.stemImageUrl)]
        : null;

    // The board/year tag is deliberately not printed — it is editorial metadata,
    // not part of the question paper. The sheet also has a copy pasted onto the
    // end of the stem, so the stem is taken from [paperStemText], which trims
    // that copy off.
    final stemLabel = '$index. ${question.paperStemText}';

    // Part 0 is the stem (with its figure); part `p` (p >= 1) is sub-question
    // `p - 1`. So the parts in [partFrom, partTo] cover sub-questions
    // [partFrom - 1, partTo - 1] — meaning the last one drawn has index
    // `partTo - 1` and the loop bound is `partTo`, not `partTo - 1`.
    final subs = question.cqSubQuestions;
    final showStem = partFrom == 0;
    final subStart = partFrom <= 1 ? 0 : partFrom - 1;
    final subEnd = partTo > subs.length ? subs.length : partTo;

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      padding: const pw.EdgeInsets.all(8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (showStem) ...[
            pw.RichText(text: _mixedText(stemLabel, baseStyle)),
            if (stemBytes != null) ...[
              pw.SizedBox(height: 6),
              pw.Container(
                alignment: pw.Alignment.center,
                child: pw.Image(
                  pw.MemoryImage(stemBytes),
                  height: imageSize.maxHeightPt,
                  fit: pw.BoxFit.contain,
                ),
              ),
            ],
          ],
          if (subEnd > subStart) pw.SizedBox(height: 4),
          // Sub-questions: text on the left, bold mark right-aligned.
          for (int k = subStart; k < subEnd && k < subs.length; k++)
            pw.Padding(
              padding: const pw.EdgeInsets.only(left: 6, top: 3),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.RichText(
                        text: _mixedText(
                            '(${subs[k].label}) ${subs[k].text}', baseStyle)),
                  ),
                  pw.SizedBox(width: 10),
                  pw.RichText(text: _mixedText('[${subs[k].mark}]', markStyle)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Mirrors the HTML `.mcq-card` / `.mcq-options`.
  ///
  /// [withStem] draws the question's own উদ্দীপক above it — set for the question
  /// that opens a group, so a shared intro prints once over the questions it
  /// introduces. [stemBytes] is that intro's figure, already downloaded.
  pw.Widget _buildPdfMcqItem(
    int index,
    HighSchoolQuestion q,
    pw.TextStyle baseStyle, {
    required double columnWidth,
    required PdfTextMetrics metrics,
    bool withStem = false,
    String? stemText,
    Uint8List? stemBytes,
    StemImageSize imageSize = StemImageSize.medium,
    int partFrom = 0,
    int partTo = 1 << 20,
  }) {
    final mcq = q.mcqData;
    if (mcq == null) return pw.SizedBox();

    final options = mcq.options;
    final stem = withStem ? (stemText ?? q.mcqStemText) : '';

    // Four options on a line where the four fit, two where they do not, one
    // where even two will not sit side by side — measured from the room the
    // block has, so a narrow column pairs the short ones up just the same. The
    // estimator asks the same question of the same text, so the room the packer
    // budgeted for a question is the room the row actually takes.
    final perRow = PdfLayout.mcqOptionsPerRow(
      options: options,
      columnWidth: columnWidth,
      metrics: metrics,
      fontStep: _fontStep,
    );

    // Part 0 is the stem; the remaining parts are successive rows of options.
    // Rendering a slice lets a question continue into the next column or page
    // rather than leaving the foot of this one empty.
    final rowStart = partFrom <= 0 ? 0 : (partFrom - 1) * perRow;
    final rowEnd = partTo <= 1 ? 0 : partTo * perRow;
    final lastRow = rowEnd > options.length
        ? (options.length / perRow).ceil()
        : rowEnd ~/ perRow;

    final rows = <pw.Widget>[];
    for (int i = rowStart;
        i < lastRow * perRow && i < options.length;
        i += perRow) {
      final cells = <pw.Widget>[];
      for (int c = 0; c < perRow; c++) {
        final idx = i + c;
        if (idx >= options.length) break;
        cells.add(pw.Expanded(
          child: pw.RichText(
              text: _mixedText(
                  PdfLayout.mcqOptionText(idx, options[idx]), baseStyle)),
        ));
        if (c < perRow - 1 && idx + 1 < options.length) {
          cells.add(pw.SizedBox(width: PdfLayout.mcqOptionGap));
        }
      }
      rows.add(pw.Padding(
        padding: const pw.EdgeInsets.only(
            left: PdfLayout.mcqOptionIndent, top: PdfLayout.mcqOptionTop),
        child: pw.Row(children: cells),
      ));
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (partFrom == 0) ...[
          // The intro carries no number: it belongs to the questions under it,
          // not to one of them.
          if (stem.isNotEmpty)
            pw.RichText(text: _mixedText(stem, baseStyle)),
          if (stem.isNotEmpty && stemBytes != null) ...[
            pw.SizedBox(height: PdfLayout.cqImageGap),
            pw.Container(
              alignment: pw.Alignment.center,
              child: pw.Image(
                pw.MemoryImage(stemBytes),
                height: imageSize.maxHeightPt,
                fit: pw.BoxFit.contain,
              ),
            ),
          ],
          if (stem.isNotEmpty) pw.SizedBox(height: PdfLayout.mcqStemGap),
          pw.RichText(
              text: _mixedText('$index. ${q.paperQuestionText}', baseStyle)),
        ],
        ...rows,
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Error helper
  // ─────────────────────────────────────────────────────────────────────────

  /// Turn an exception into something the reader can act on.
  ///
  /// `e.toString()` on a failed HTTP call exposes `dart:io` internals ("Only
  /// HTTP and HTTPS URLs are supported", raw socket errors), which explains
  /// nothing. The two cases worth separating are a build with no endpoint
  /// configured and a genuine network problem.
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
            child: const Text('প্রশ্নপত্র তৈরি করুন ➜',
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
        color: _kCardBg,
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
        child: Row(
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
            if (q.stemImageUrl.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  q.stemImageUrl,
                  height: 160,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.grey),
                ),
              ),
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
            if (q.stemImageUrl.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  q.stemImageUrl,
                  height: 160,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.grey),
                ),
              ),
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

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 3 — Exam Header Config & Export
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStep3() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
              icon: Icons.edit_document, label: 'পরীক্ষার তথ্য পূরণ করুন'),
          const SizedBox(height: 16),

          // Summary chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(
                  icon: Icons.quiz_rounded,
                  label: 'CQ: ${_selectedCqs.length}টি'),
              _InfoChip(
                  icon: Icons.format_list_bulleted_rounded,
                  label: 'MCQ: ${_selectedMcqs.length}টি'),
              _InfoChip(
                  icon: Icons.short_text_rounded,
                  label: 'RQ: ${_selectedShorts.length}টি'),
              _InfoChip(
                  icon: Icons.star_rounded,
                  label: 'মোট নম্বর: $_totalSelectedMarks'),
              // A single total cannot be checked against the cards on screen,
              // so break it down by type before the paper is generated.
              if (_marksBreakdown.cq > 0)
                _InfoChip(
                    icon: Icons.calculate_outlined,
                    label: 'CQ নম্বর: ${_marksBreakdown.cq}'),
              if (_marksBreakdown.mcq > 0)
                _InfoChip(
                    icon: Icons.checklist_outlined,
                    label: 'MCQ নম্বর: ${_marksBreakdown.mcq}'),
              if (_marksBreakdown.rq > 0)
                _InfoChip(
                    icon: Icons.short_text_rounded,
                    label: 'RQ নম্বর: ${_marksBreakdown.rq}'),
            ],
          ),
          const SizedBox(height: 18),

          _buildSectionCard(),
          const SizedBox(height: 20),

          _buildTextField(
              ctrl: _schoolCtrl,
              label: 'শিক্ষা প্রতিষ্ঠানের নাম',
              icon: Icons.account_balance_rounded),
          const SizedBox(height: 14),
          _buildTextField(
              ctrl: _examCtrl,
              label: 'পরীক্ষার নাম',
              icon: Icons.description_rounded),
          const SizedBox(height: 14),
          _buildTextField(
              ctrl: _subjectCtrl, label: 'বিষয়', icon: Icons.book_rounded),
          const SizedBox(height: 14),
          _buildTextField(
              ctrl: _classCtrl,
              label: 'শ্রেণি ও শাখা',
              icon: Icons.class_rounded),
          const SizedBox(height: 14),
          _buildTextField(
              ctrl: _timeCtrl, label: 'সময়', icon: Icons.access_time_rounded),
          const SizedBox(height: 14),
          _buildTextField(
              ctrl: _marksCtrl,
              label: 'পূর্ণমান',
              icon: Icons.stars_rounded,
              keyboardType: TextInputType.number),
          const SizedBox(height: 14),
          _buildTextField(
              ctrl: _cqAnswerAnyCtrl,
              label:
                  'যেকোনো কয়টি CQ-র উত্তর দিতে হবে (খালি রাখলে লেখা হবে না)',
              icon: Icons.rule_rounded,
              keyboardType: TextInputType.number,
              helperText: _selectedCqs.isEmpty
                  ? null
                  : 'সর্বোচ্চ ${_selectedCqs.length} — যেমন: যেকোনো ৫ টি প্রশ্নের উত্তর দাও'),
          const SizedBox(height: 18),

          // ── Stem image size ──────────────────────────────────────────────
          _buildImageSizeSelector(),
          const SizedBox(height: 14),

          // ── Paper font size ──────────────────────────────────────────────
          _buildFontSizeSelector(),
          const SizedBox(height: 28),

          // The sheet is the default export: print it, or share the file. A
          // "view & download" button of its own would only repeat those two.
          if (_generating) ...[
            const LinearProgressIndicator(color: _kPrimary),
            const SizedBox(height: 12),
          ],

          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.print_rounded, size: 20),
                    label: const Text('প্রিন্ট করুন',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kPrimary,
                      side: const BorderSide(color: _kPrimary, width: 1.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _generating ? null : _exportHtml,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.share_rounded, size: 20),
                    label: const Text('HTML শেয়ার',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0284C7),
                      side: const BorderSide(
                          color: Color(0xFF0284C7), width: 1.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed:
                        _generating ? null : () => _exportHtml(open: false),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // ── Multi-Format Export Section ──────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.visibility_rounded, size: 20),
              label: const Text('লাইভ প্রিভিউ দেখুন',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 3,
                shadowColor: _kAccent.withOpacity(0.4),
              ),
              onPressed: _openLivePreview,
            ),
          ),
          const SizedBox(height: 10),
          _SectionHeader(
              icon: Icons.file_download_rounded,
              label: 'অন্যান্য ফরম্যাটে এক্সপোর্ট ও সংরক্ষণ'),
          const SizedBox(height: 6),
          const Text(
            'প্রশ্নপত্রটি HTML ছাড়াও ওয়ার্ড এডিটর, পিডিএফ বা নোট অ্যাপের জন্য যেকোনো ফরম্যাটে সংরক্ষণ ও শেয়ার করুন:',
            style: TextStyle(fontSize: 13, color: _kSubText),
          ),
          const SizedBox(height: 16),

          // Copy All Text Banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFA7F3D0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.copy_all_rounded,
                    color: Color(0xFF059669), size: 24),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'সম্পূর্ণ প্রশ্নপত্রের টেক্সট কপি করুন (WhatsApp / Messenger / Notepad)',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF065F46)),
                  ),
                ),
                ElevatedButton(
                  onPressed: _copyAllText,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('কপি',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Format Cards. The page-exact PDF leads the list: it is the other
          // export a reader reaches for, right after the default HTML sheet.
          _ExportFormatCard(
            icon: Icons.picture_as_pdf_rounded,
            accentColor: const Color(0xFFDC2626),
            title: 'PDF ফাইল (.pdf)',
            badge: 'পেজ-এক্সাক্ট A4 ফাইল',
            description:
                'অফলাইনে সংরক্ষণ, শেয়ার বা সরাসরি প্রিন্টের জন্য প্রিন্টার-রেডি ফাইল।',
            onOpen: _generateAndPreviewPdf,
            onShare: _sharePdfFile,
          ),
          const SizedBox(height: 10),

          _ExportFormatCard(
            icon: Icons.article_rounded,
            accentColor: const Color(0xFF2B579A),
            title: 'Microsoft Word (.doc)',
            badge: 'এডিটেবল ওয়ার্ড ফাইল',
            description:
                'কম্পিউটার বা ফোনে MS Word/WPS/Docs এ প্রশ্ন এডিট ও প্রিন্ট করার জন্য।',
            onOpen: () => _exportWord(open: true),
            onShare: () => _exportWord(open: false),
          ),
          const SizedBox(height: 10),

          _ExportFormatCard(
            icon: Icons.text_snippet_rounded,
            accentColor: const Color(0xFF475569),
            title: 'Plain Text (.txt)',
            badge: 'নোটপ্যাড বা হালকা ফাইল',
            description:
                'সব ডিভাইসে কোনো ফরম্যাটিং ঝামেলা ছাড়াই সাধারণ টেক্সট হিসেবে পড়ার জন্য।',
            onOpen: () => _exportText(open: true),
            onShare: () => _exportText(open: false),
          ),
          const SizedBox(height: 10),

          _ExportFormatCard(
            icon: Icons.code_rounded,
            accentColor: const Color(0xFF7C3AED),
            title: 'Markdown (.md)',
            badge: 'নোশন ও ডিজিটাল নোট',
            description:
                'Notion, Obsidian, GitHub বা অন্যান্য মার্কডাউন নোট অ্যাপে সংরক্ষণের জন্য।',
            onOpen: () => _exportMarkdown(open: true),
            onShare: () => _exportMarkdown(open: false),
          ),
          const SizedBox(height: 10),

          _ExportFormatCard(
            icon: Icons.data_object_rounded,
            accentColor: const Color(0xFF059669),
            title: 'JSON Data (.json)',
            badge: 'ডিজিটাল ব্যাকআপ',
            description:
                'প্রশ্নের ডেটাবেজ ব্যাকআপ ও ডিজিটাল আদান-প্রদানের জন্য সম্পূর্ণ স্ট্রাকচার্ড ডেটা।',
            onOpen: () => _exportJson(open: true),
            onShare: () => _exportJson(open: false),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// Lets the user control how large stem images appear in every export format.
  Widget _buildImageSizeSelector() {
    final withImages = _selectedQuestions
        .where((q) => q.stemImageUrl.trim().isNotEmpty)
        .length;

    return Container(
      padding: const EdgeInsets.all(14),
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
              const Icon(Icons.image_outlined, size: 18, color: _kPrimary),
              const SizedBox(width: 8),
              const Text('উদ্দীপক ছবির আকার',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: _kDarkText)),
              const Spacer(),
              Text(
                withImages > 0 ? '$withImages টি ছবি' : 'কোনো ছবি নেই',
                style: TextStyle(fontSize: 11, color: _kSubText),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: StemImageSize.values.map((size) {
              final selected = _imageSize == size;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(() => _imageSize = size),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: selected
                            ? _kPrimary.withOpacity(0.10)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected ? _kPrimary : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            size.label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight:
                                  selected ? FontWeight.bold : FontWeight.w500,
                              color: selected ? _kPrimary : _kDarkText,
                            ),
                          ),
                          if (size.isVisible) ...[
                            const SizedBox(height: 5),
                            // Proportional height bar so the sizes are visual.
                            Container(
                              width: 22,
                              height: 22 * (size.maxHeightPt / 220),
                              decoration: BoxDecoration(
                                color: selected
                                    ? _kPrimary.withOpacity(0.35)
                                    : Colors.grey.shade400,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Text(
            _imageSize.description,
            style: const TextStyle(fontSize: 11, color: _kSubText),
          ),
        ],
      ),
    );
  }

  /// The paper's font-size control: one step moves every text size in the paper
  /// — masthead, section banners, question text and marks — by a single point,
  /// in the PDF and the HTML alike.
  ///
  /// The paper is tuned at step 0, which is why the control ships at 0 rather
  /// than at a "small / medium / large" default nobody can compare against.
  Widget _buildFontSizeSelector() {
    final label = _fontStep == 0
        ? 'স্বাভাবিক'
        : '${_fontStep > 0 ? '+' : '−'}${_fontStep.abs().toStringAsFixed(0)} pt';

    return Container(
      padding: const EdgeInsets.all(14),
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
              const Icon(Icons.format_size_rounded, size: 18, color: _kPrimary),
              const SizedBox(width: 8),
              const Text('লেখার আকার ও ফন্ট',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: _kDarkText)),
              const Spacer(),
              Text(label, style: TextStyle(fontSize: 11, color: _kSubText)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildFontStepButton(
                  icon: Icons.remove_rounded,
                  delta: -1,
                  enabled: _fontStep > _fontStepMin),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  alignment: Alignment.center,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  // Drawn at the paper's own size: the HTML sheet prints
                  // question text at 15px and a step is one point (96/72 px), so
                  // the sample grows by exactly what the paper will.
                  child: Text(
                    '১. সংক্ষিপ্ত প্রশ্নের নমুনা লেখা',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 15 + _fontStep * 96 / 72, color: _kDarkText),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _buildFontStepButton(
                  icon: Icons.add_rounded,
                  delta: 1,
                  enabled: _fontStep < _fontStepMax),
            ],
          ),
          const SizedBox(height: 12),
          _buildFontPicker(),
          const SizedBox(height: 8),
          const Text(
            'প্রতিটি ধাপে প্রশ্নপত্রের সব লেখা একসাথে এক পয়েন্ট বড় বা ছোট হয়। '
            'PDF আর HTML — দুই এক্সপোর্টেই একই আকারে ছাপা হবে।',
            style: TextStyle(fontSize: 11, color: _kSubText),
          ),
          const SizedBox(height: 3),
          const Text(
            'ফন্ট বাছাই HTML ও ওয়ার্ডে কাজ করে; PDF নিজের এমবেড করা ফন্টে ছাপে। '
            'কলপুরুষ, সলাইমানলিপি ও নির্মলা ইউআই ফাইলটি যে ডিভাইসে খোলা হবে সেখানে '
            'ইনস্টল থাকলে তবেই হুবহু দেখাবে — নাহলে হিন্দ শিলিগুড়িতে ছাপা হবে।',
            style: TextStyle(fontSize: 11, color: _kSubText),
          ),
        ],
      ),
    );
  }

  /// The face the paper is set in, as a row of names.
  ///
  /// A wrap of chips rather than a menu: the reader is choosing by eye, and a
  /// menu has to be opened before the options can be read at all. The faces the
  /// browser cannot fetch are marked, so nobody is left wondering why a file
  /// opened on another machine looks different.
  Widget _buildFontPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ফন্ট',
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: _kSubText)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [for (final font in PaperFont.values) _buildFontChip(font)],
        ),
      ],
    );
  }

  /// One face in the picker. A face that has to be installed on the machine
  /// reading the file carries a small desktop mark.
  Widget _buildFontChip(PaperFont font) {
    final selected = font == _paperFont;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _paperFont = font),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? _kPrimary.withOpacity(0.10) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? _kPrimary : Colors.transparent, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!font.isWebFont) ...[
              Icon(Icons.computer_rounded,
                  size: 12, color: selected ? _kPrimary : _kSubText),
              const SizedBox(width: 5),
            ],
            Text(
              font.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? _kPrimary : _kDarkText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One end of the font-size stepper, greyed out at its limit.
  Widget _buildFontStepButton({
    required IconData icon,
    required double delta,
    required bool enabled,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: enabled
          ? () => setState(() => _fontStep =
              (_fontStep + delta).clamp(_fontStepMin, _fontStepMax).toDouble())
          : null,
      child: Container(
        width: 46,
        height: 42,
        decoration: BoxDecoration(
          color: enabled ? _kPrimary.withOpacity(0.10) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: enabled ? _kPrimary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Icon(icon,
            size: 20, color: enabled ? _kPrimary : Colors.grey.shade400),
      ),
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
      padding: const EdgeInsets.all(14),
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
                  size: 18, color: _kPrimary),
              const SizedBox(width: 8),
              const Text('বিভাগ ও কলাম',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: _kDarkText)),
              const Spacer(),
              Text('ধরে টেনে ক্রম বদলাও',
                  style: TextStyle(fontSize: 11, color: _kSubText)),
            ],
          ),
          const SizedBox(height: 10),
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
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: _kPrimary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(8),
            ),
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
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 14),
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
    required IconData icon,
    TextInputType? keyboardType,
    String? helperText,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      style: const TextStyle(color: _kDarkText),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: _kPrimary),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kPrimary, width: 2),
        ),
        helperText: helperText,
        helperStyle: const TextStyle(fontSize: 11, color: _kSubText),
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: empty ? Colors.grey.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: empty ? Colors.grey.shade300 : kind.color.withOpacity(0.35),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
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
                            size: 20,
                            color: empty ? Colors.grey.shade400 : kind.color),
                        const SizedBox(width: 8),
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
                              const SizedBox(height: 2),
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
              const SizedBox(width: 8),
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                      height: 15,
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

class _ExportFormatCard extends StatelessWidget {
  final IconData icon;
  final Color accentColor;
  final String title;
  final String badge;
  final String description;
  final VoidCallback onOpen;
  final VoidCallback onShare;

  const _ExportFormatCard({
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.badge,
    required this.description,
    required this.onOpen,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accentColor, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _kDarkText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: accentColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        badge,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: accentColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(fontSize: 12, color: _kSubText),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.folder_open_rounded, size: 16),
                    label: const Text('ওপেন করুন',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: onOpen,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: OutlinedButton.icon(
                    icon:
                        Icon(Icons.share_rounded, size: 16, color: accentColor),
                    label: Text('শেয়ার',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: accentColor)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: accentColor.withOpacity(0.5)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: onShare,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
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
