import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/highschool_question.dart';
import '../services/highschool_qbank_service.dart';
import '../services/highschool_export_service.dart';
import '../services/highschool_file_export_service.dart';
import '../pages/question_paper_preview_page.dart';
import '../widgets/exact_html_preview.dart';
import '../config/app_config.dart';
import '../utils/math_rich_text.dart';

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
const _kSheetSoft = Color(0xFFF5F4FC);
const _kSheetLine = Color(0xFFE3E0F2);

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

  /// Steps the wizard has already shown.
  ///
  /// Going back is cheap, but going forward again should not rebuild the page
  /// the reader just came from: the picker would re-fetch and lose every tick,
  /// and the arrange page would overwrite fields that were typed there. A
  /// visited step is therefore reopened as-is, so back/forward behaves like
  /// history rather than a reset.
  final Set<int> _visitedSteps = {0};

  /// The class/subject/chapter set the picker was last loaded with, or null
  /// before the first fetch. Compared on every forward press so a changed
  /// filter still triggers a real reload.
  String? _loadedFilterSignature;

  /// The selection the arrange step last opened with, or null before it was
  /// first reached. A different selection means the arrange page has to be
  /// refreshed rather than merely reopened.
  String? _arrangedSelectionSignature;

  // ── Step 1 state ──────────────────────────────────────────────────────────
  String? _selectedClass;
  String? _selectedSubject;
  List<ChapterInfo> _availableChapters = [];
  final Set<String> _selectedChapterNumbers = {};
  bool _loadingChapters = false;

  // ── Step 2 state ──────────────────────────────────────────────────────────
  List<HighSchoolQuestion> _fetchedQuestions = [];
  bool _loadingQuestions = false;

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
  _ImageFilter _imageFilter = _ImageFilter.all;
  final _pickSearchCtrl = TextEditingController();
  String _pickSearchQuery = '';

  /// How many questions the "এলোমেলো নির্বাচন" bar should draw.
  final _randomCqCtrl = TextEditingController();
  final _randomMcqCtrl = TextEditingController();
  final _randomRqCtrl = TextEditingController();

  /// Whether the phone picker is showing the random draw's count boxes.
  ///
  /// The bar keeps its header visible either way, so the draw is one tap away;
  /// folding the three fields away by default leaves the question list the
  /// screen it needs on a phone.
  bool _randomSelectorOpen = false;

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
    return '$number'.split('').map((d) => digits[int.parse(d)]).join();
  }

  /// How stem images are sized in the HTML paper.
  StemImageSize _imageSize = StemImageSize.small;

  /// How CQ questions are arranged (single or double column).
  QuestionLayout _cqLayout = QuestionLayout.single;

  /// How MCQ questions are arranged (single or double column).
  QuestionLayout _mcqLayout = QuestionLayout.doubleColumn;

  /// Short questions stay single-column by default: they are one line each, so
  /// two columns only helps when there are many of them.
  QuestionLayout _rqLayout = QuestionLayout.single;

  /// Optional answer sheet appended after the MCQ section in the HTML paper.
  McqAnswerSheetStyle _mcqAnswerSheetStyle = McqAnswerSheetStyle.none;

  /// Number of blank OMR/answer rows when no MCQ questions are selected.
  int _manualAnswerItemCount = 30;

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
  PaperFont _paperFont = PaperFont.kalpurush;

  // ── Print settings ────────────────────────────────────────────────────────
  //
  // The desktop studio's settings panel. The values are collected into a
  // [PaperPrintSettings] and handed to the HTML writer, so the sheet on screen,
  // the exported file and the print view all carry the same choices.

  PaperSize _paperSize = PaperSize.a4;
  PaperTextAlign _textAlign = PaperTextAlign.justify;
  bool _pageNumbers = false;
  McqOptionStyle _optionStyle = McqOptionStyle.parentheses;
  bool _columnDivider = true;
  double _questionGap = 0;
  double _columnGap = 15;

  bool _showSchool = true;
  bool _showExam = true;
  bool _showSubject = true;
  bool _showClass = true;
  bool _showSet = true;
  bool _showInstructions = true;
  bool _showChapter = false;
  bool _showSubjectCode = false;
  bool _showStudentInfo = false;
  bool _showObtainedMarks = false;
  bool _showQuestionInfo = false;
  bool _showImportant = false;
  bool _editingMode = false;

  bool _showLogo = false;
  bool _showHeader = false;
  bool _showFooter = false;
  bool _showWatermark = false;
  bool _showAddress = false;

  bool _detectRepeated = false;
  bool _shortcutHints = false;

  final _subjectCodeCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _headerNoteCtrl = TextEditingController();
  final _watermarkCtrl = TextEditingController(text: 'নমুনা');
  String _logoDataUri = '';
  String _logoName = '';

  /// The chapter names the selected questions come from, for the header toggle.
  String get _chapterLabel {
    final names = <String>{};
    for (final q in _selectedQuestions) {
      final name = q.chapterName.trim();
      if (name.isNotEmpty) names.add(name);
    }
    return names.join(', ');
  }

  /// Selected rows whose printed text is the same, so the detect-repeats
  /// helper can point them out before they reach the sheet.
  List<HighSchoolQuestion> get _repeatedQuestions {
    final byText = <String, List<HighSchoolQuestion>>{};
    for (final q in _selectedQuestions) {
      final text = q.paperQuestionText.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (text.isEmpty) continue;
      byText.putIfAbsent(text, () => []).add(q);
    }
    return [
      for (final group in byText.values)
        if (group.length > 1) ...group,
    ];
  }

  /// The settings panel's choices, in the shape the HTML writer wants.
  PaperPrintSettings get _printSettings => PaperPrintSettings(
        paperSize: _paperSize,
        textAlign: _textAlign,
        pageNumbers: _pageNumbers,
        optionStyle: _optionStyle,
        columnDivider: _columnDivider,
        questionGap: _questionGap,
        columnGap: _columnGap,
        showSchool: _showSchool,
        showExam: _showExam,
        showSubject: _showSubject,
        showClass: _showClass,
        showSet: _showSet,
        showInstructions: _showInstructions,
        showChapter: _showChapter,
        showSubjectCode: _showSubjectCode,
        showStudentInfo: _showStudentInfo,
        showObtainedMarks: _showObtainedMarks,
        showQuestionInfo: _showQuestionInfo,
        showImportant: _showImportant,
        editingMode: _editingMode,
        showLogo: _showLogo,
        showHeader: _showHeader,
        showFooter: _showFooter,
        showWatermark: _showWatermark,
        showAddress: _showAddress,
        chapter: _chapterLabel,
        subjectCode: _subjectCodeCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        headerNote: _headerNoteCtrl.text.trim(),
        watermarkText: _watermarkCtrl.text.trim(),
        logoDataUri: _logoDataUri,
      );

  /// Whether the print settings differ from the shipped defaults.
  ///
  /// The floating button on a phone shows a small dot while this is true, so a
  /// paper that was tweaked once does not look untouched on the next visit.
  bool get _settingsDifferFromDefaults =>
      _cqLayout != QuestionLayout.single ||
      _mcqLayout != QuestionLayout.doubleColumn ||
      _rqLayout != QuestionLayout.single ||
      _paperSize != PaperSize.a4 ||
      _textAlign != PaperTextAlign.justify ||
      _pageNumbers ||
      _optionStyle != McqOptionStyle.parentheses ||
      !_columnDivider ||
      _questionGap != 0 ||
      _columnGap != 15 ||
      _fontStep != 0 ||
      _paperFont != PaperFont.kalpurush ||
      !_showSchool ||
      !_showExam ||
      !_showSubject ||
      !_showClass ||
      !_showSet ||
      !_showInstructions ||
      _showChapter ||
      _showSubjectCode ||
      _showStudentInfo ||
      _showObtainedMarks ||
      _showQuestionInfo ||
      _showImportant ||
      _editingMode ||
      _imageSize != StemImageSize.small ||
      _mcqAnswerSheetStyle != McqAnswerSheetStyle.none ||
      _detectRepeated;

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
    // The live preview shows the exported file itself, so the faces it embeds
    // have to be in hand before the first sheet is built.
    unawaited(HighSchoolExportService.preloadPaperFonts().then((_) {
      if (mounted) setState(() => _paperFontsReady = true);
    }));
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
    _subjectCodeCtrl.dispose();
    _addressCtrl.dispose();
    _headerNoteCtrl.dispose();
    _watermarkCtrl.dispose();
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

  /// True once the shipped paper faces are embedded, so the live preview's
  /// HTML carries them.
  bool _paperFontsReady = false;

  /// Desktop settings rail state. The browser studio folds this rail away to
  /// give the preview the whole width; the same toggle lives in the app bar.
  bool _desktopSettingsOpen = true;

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

  /// Shuffle the selected questions, then deal them into the two sets.
  ///
  /// The paper's own order still follows the section/chapter sort; what changes
  /// is which set each question lands in, so the two papers carry a different
  /// mix without losing the section order.
  void _shuffleIntoTwoSets() {
    final selected = List<HighSchoolQuestion>.of(_selectedQuestions);
    if (selected.length < 2) return;
    selected.shuffle(Random());
    setState(() {
      _twoSets = true;
      for (var i = 0; i < selected.length; i++) {
        selected[i].setLabel = _setLabels[i % 2];
      }
    });
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
    setState(() {
      _currentStep = step;
      _visitedSteps.add(step);
    });
    _stepAnim.forward();
  }

  /// A fingerprint of the inputs the picker is fetched from. Used only to tell
  /// "the same query as last time" from "the filters changed".
  String _filterSignature() {
    final chapters = _selectedChapterNumbers.toList()..sort();
    return '${_selectedClass ?? ''}|${_selectedSubject ?? ''}|${chapters.join(',')}';
  }

  /// A fingerprint of what the arrange step derives from the picker: the
  /// selected question ids, in picker order.
  String _selectionSignature() =>
      [for (final q in _selectedQuestions) q.id].join('|');

  /// Advance one step, reusing the visited page when nothing upstream changed.
  ///
  /// First visit runs the step's own entry action (fetch the bank, or seed the
  /// arrange fields). A later visit after a back press only pages forward, so
  /// the picker keeps its ticks and the arrange page keeps its edits.
  void _goForward() {
    switch (_currentStep) {
      case 0:
        final reusable = _visitedSteps.contains(1) &&
            _loadedFilterSignature != null &&
            _loadedFilterSignature == _filterSignature();
        if (reusable) {
          _goToStep(1);
        } else {
          _fetchQuestions();
        }
      case 1:
        final reusable = _visitedSteps.contains(2) &&
            _arrangedSelectionSignature != null &&
            _arrangedSelectionSignature == _selectionSignature();
        if (reusable) {
          _goToStep(2);
        } else {
          _proceedToGenerate();
        }
    }
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
      // The studio draws its masthead straight from the paper fields, so the
      // class the picker lists is written the way the paper prints it as soon
      // as it is chosen. Step 3 still lets the reader override it.
      _classCtrl.text = value == null ? '' : _classLabel(value);
    });
  }

  Future<void> _onSubjectChanged(String? value) async {
    setState(() {
      _selectedSubject = value;
      _availableChapters = [];
      _selectedChapterNumbers.clear();
      _subjectCtrl.text = value ?? '';
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
    final signature = _filterSignature();
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
        setState(() {
          _loadedFilterSignature = signature;
          _arrangedSelectionSignature = null;
        });
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
        _loadedFilterSignature = signature;
        _arrangedSelectionSignature = null;
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
      if (!_imageFilter.matches(q)) return false;
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
      _pickFilter != _PickFilter.all ||
      _imageFilter != _ImageFilter.all ||
      _pickSearchQuery.trim().isNotEmpty;

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

  void _selectChapter(String chapterNumber) {
    final runs = _mcqStemRuns();
    setState(() {
      for (final q
          in _visibleQuestions.where((q) => q.chapterNumber == chapterNumber)) {
        _applySelection(q, true, runs);
      }
    });
  }

  void _deselectChapter(String chapterNumber) {
    final runs = _mcqStemRuns();
    setState(() {
      for (final q
          in _visibleQuestions.where((q) => q.chapterNumber == chapterNumber)) {
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
    if (pools.isEmpty && cqCount <= 0 && mcqCount <= 0 && rqCount <= 0) {
      return const [];
    }

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
  Future<void> _openManualQuestion({String? initialChapter}) async {
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
        initialChapter: initialChapter ??
            (_selectedChapterNumbers.length == 1
                ? _selectedChapterNumbers.first
                : null),
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
      _fetchedQuestions = [..._fetchedQuestions]..[index] = edited;
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
    // Record what the arrange page was seeded from, so a later back/forward
    // pair can reopen it untouched while a changed selection still refreshes it.
    _arrangedSelectionSignature = _selectionSignature();
    // The studio keeps its settings in the right-hand rail rather than on a
    // step of its own, so "প্রশ্নপত্র সাজান" opens that rail instead of paging.
    setState(() => _desktopSettingsOpen = true);
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
        mcqAnswerSheetStyle: _mcqAnswerSheetStyle,
        manualAnswerCount: _manualAnswerItemCount,
        fontStep: _fontStep,
        font: _paperFont,
        cqInstruction: _cqInstruction,
        printSettings: _printSettings,
      );
      final file = await HighSchoolFileExportService.saveFile(
        content: html,
        fileName: '${_getBaseFileName()}.html',
      );
      if (!mounted) return;
      if (open) {
        await HighSchoolFileExportService.openExportedFile(context, file);
      } else {
        await HighSchoolFileExportService.shareExportedFile(
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
          cqInstruction: _cqInstruction,
          printSettings: _printSettings,
          setLabels: _twoSets ? _setLabels : const [],
          sectionOrder: _paperSectionOrder,
          imageSize: _imageSize,
          cqLayout: _cqLayout,
          mcqLayout: _mcqLayout,
          rqLayout: _rqLayout,
          mcqAnswerSheetStyle: _mcqAnswerSheetStyle,
          manualAnswerCount: _manualAnswerItemCount,
          fontStep: _fontStep,
          font: _paperFont,
          settingsBuilder: (context, onChanged) => _MobileSettingsSheet(
            parent: this,
            onChanged: onChanged,
          ),
          liveHtmlBuilder: _buildPaperHtml,
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
      mcqAnswerSheetStyle: _mcqAnswerSheetStyle,
      manualAnswerCount: _manualAnswerItemCount,
      fontStep: _fontStep,
      font: _paperFont,
      cqInstruction: _cqInstruction,
      printSettings: _printSettings,
      // Desktop-width layout, as in the in-app preview: the file opens in a
      // browser, and a phone-width one should still show the printed page.
      desktopMode: true,
    );
    final file = await HighSchoolFileExportService.saveFile(
      content: html,
      fileName: '${_getBaseFileName()}_preview.html',
    );
    if (!mounted) return;
    await HighSchoolFileExportService.openExportedFile(context, file);
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
    // The studio is a desktop layout: the sidebar, the control card and the
    // live preview side by side. A narrow window keeps the wizard, which is the
    // shape the phone has always had.
    // Three panes need room to breathe; below this the wizard is the better
    // layout, so the studio only takes over once the window can hold it.
    final desktop = MediaQuery.sizeOf(context).width >= 1200;

    return Scaffold(
      backgroundColor: desktop ? const Color(0xFFF1F3F7) : _kBg,
      appBar: desktop ? _buildStudioAppBar() : _buildWizardAppBar(),
      body: desktop
          ? _buildStudioBody()
          : Column(
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
      floatingActionButton: desktop || _currentStep != 2
          ? null
          : _MobileSettingsButton(
              showDot: _settingsDifferFromDefaults,
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => _MobileSettingsSheet(parent: this),
              ),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MOBILE APP BAR — the picker's numbers ride here, not in a second bar.
  // ═══════════════════════════════════════════════════════════════════════════

  /// The wizard's own app bar.
  ///
  /// Step 2 used to pin a purple counter bar above the list, spending a whole
  /// row on numbers the app bar could already hold. The counts and the
  /// "সাজান" action now sit in the app bar itself, so the list starts higher and
  /// the paper-in-progress is visible on every scroll position.
  AppBar _buildWizardAppBar() {
    final picking = _currentStep == 1;

    return AppBar(
      toolbarHeight: 64,
      backgroundColor: _kPrimary,
      surfaceTintColor: _kPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: 0,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      iconTheme: const IconThemeData(color: Colors.white),
      flexibleSpace: const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_kPrimary, Color(0xFF7C5CF0)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
        ),
      ),
      leading: _currentStep > 0
          ? IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              tooltip: 'আগের ধাপ',
              onPressed: () => _goToStep(_currentStep - 1),
            )
          : null,
      title: picking
          ? _buildAppBarStats()
          : const Text(
              'প্রশ্নপত্র তৈরি করুন',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
      actions: [
        if (_currentStep == 0)
          _appBarAction(
            label: 'পরবর্তী',
            tooltip: 'পরবর্তী ধাপ',
            busy: _loadingQuestions,
            onPressed: _loadingQuestions ? null : _goForward,
          ),
        if (_currentStep == 1)
          _appBarAction(
            label: 'সাজান',
            tooltip: 'প্রশ্নপত্র সাজান',
            onPressed: _goForward,
          ),
      ],
    );
  }

  /// The white pill on the app bar's right edge. It carries the forward action
  /// for the current step — "পরবর্তী" on the filters, "সাজান" on the picker —
  /// so the wizard can be driven from the top as well as from its buttons.
  Widget _appBarAction({
    required String label,
    required String tooltip,
    required VoidCallback? onPressed,
    bool busy = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Tooltip(
        message: tooltip,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: _kPrimary,
            disabledBackgroundColor: Colors.white.withOpacity(0.55),
            padding: const EdgeInsets.symmetric(horizontal: 11),
            minimumSize: const Size(0, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _kPrimary,
                  ),
                )
              else ...[
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward_rounded, size: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Two tight rows — one count per type, then the running total — sized to a
  /// phone's app bar. Each chip shrinks with an ellipsis before anything is
  /// pushed off the bar.
  Widget _buildAppBarStats() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _appBarCount('CQ', _selectedCqs.length, _totalCqs, _kCqColor),
            const SizedBox(width: 5),
            _appBarCount('MCQ', _selectedMcqs.length, _totalMcqs, _kMcqColor),
            if (_totalShorts > 0) ...[
              const SizedBox(width: 5),
              _appBarCount(
                'RQ',
                _selectedShorts.length,
                _totalShorts,
                _kRqColor,
              ),
            ],
          ],
        ),
        const SizedBox(height: 3),
        Text(
          'মোট নম্বর: $_totalSelectedMarks',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _appBarCount(String label, int selected, int total, Color color) {
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.16),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                '$label $selected/$total',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DESKTOP STUDIO — the browser edition's shell, drawn in Flutter
  // ═══════════════════════════════════════════════════════════════════════════
  //
  // The browser build (web_main.dart) lays the paper studio out as a navy
  // sidebar, a control card and a live preview with a settings rail. Linux has
  // no WebView host, so the preview is drawn natively here instead of in an
  // iframe — but the shell around it is the same, pane for pane.

  PreferredSizeWidget _buildStudioAppBar() {
    final selectedCount = _selectedQuestions.length;
    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 18,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF4F46E5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.auto_stories_rounded,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          const Text('Pi-QBank', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(width: 10),
          Text(
            'Question Paper Studio',
            style: TextStyle(
              color: Colors.blueGrey.shade500,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: _desktopSettingsOpen ? 'সেটিংস গুটান' : 'সেটিংস খুলুন',
          onPressed: () =>
              setState(() => _desktopSettingsOpen = !_desktopSettingsOpen),
          icon: Icon(_desktopSettingsOpen ? Icons.tune : Icons.tune_outlined),
        ),
        if (selectedCount > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Chip(
                avatar: const Icon(Icons.check_circle_outline, size: 17),
                label: Text('$selectedCount নির্বাচিত'),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        IconButton(
          tooltip: 'HTML ডাউনলোড',
          onPressed: selectedCount == 0 ? null : () => _exportHtml(),
          icon: const Icon(Icons.download_rounded),
        ),
        IconButton(
          tooltip: 'প্রিভিউ ও প্রিন্ট',
          onPressed: selectedCount == 0 ? null : _openLivePreview,
          icon: const Icon(Icons.print_rounded),
        ),
        const SizedBox(width: 6),
      ],
    );
  }

  Widget _buildStudioBody() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _buildStudioControls()),
        Expanded(child: _buildStudioPreview()),
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: _desktopSettingsOpen ? 300 : 48,
          child: _desktopSettingsOpen
              ? _buildStudioSettingsRail()
              : _buildCollapsedSettingsRail(),
        ),
      ],
    );
  }

  // ── Centre card: the paper's setup, then the picker ────────────────────────

  Widget _buildStudioControls() {
    return Card(
      margin: const EdgeInsets.fromLTRB(24, 18, 12, 18),
      elevation: 0,
      color: const Color(0xFFF8F8FA),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFD6DCE5)),
      ),
      child: _currentStep >= 1 ? _buildStudioPicker() : _buildStudioSetup(),
    );
  }

  Widget _buildStudioSetup() {
    final subjects = _selectedClass == null
        ? const <String>[]
        : (_kSubjectsByClass[_selectedClass] ?? const <String>[]);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStudioHero(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('নতুন প্রশ্নপত্র',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w800)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEDE9FE),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('DESKTOP',
                          style: TextStyle(
                              color: Color(0xFF4F46E5),
                              fontSize: 11,
                              fontWeight: FontWeight.w800)),
                    ),
                    if (_fetchedQuestions.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: 'Back to question selection',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _goToStep(1),
                        icon: const Icon(Icons.arrow_forward_rounded),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'তথ্য দিন, প্রশ্ন বাছাই করুন, তারপর প্রিন্ট করুন',
                  style:
                      TextStyle(color: Colors.blueGrey.shade500, fontSize: 13),
                ),
                const SizedBox(height: 16),
                _buildStudioDropdownField(
                  key: const ValueKey('studio-class-field'),
                  label: 'শ্রেণি',
                  value: _selectedClass,
                  items: _kClasses,
                  onChanged: _onClassChanged,
                ),
                const SizedBox(height: 10),
                _buildStudioDropdownField(
                  key: const ValueKey('studio-subject-field'),
                  label: 'বিষয়',
                  value: _selectedSubject,
                  items: subjects,
                  onChanged: _onSubjectChanged,
                ),
                if (_selectedClass != null && _selectedSubject != null) ...[
                  const SizedBox(height: 18),
                  _buildChapterSection(),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: _loadingQuestions ? null : _fetchQuestions,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: _loadingQuestions
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.cloud_download_outlined),
                    label: Text(
                        _loadingQuestions ? 'লোড হচ্ছে…' : 'প্রশ্ন লোড করুন',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudioHero() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 26),
      decoration: const BoxDecoration(color: Color(0xFF102F50)),
      child: const Column(
        children: [
          Text(
            'এক ক্লিকে প্রশ্নপত্র তৈরি করুন!',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 6),
          Text(
            'আপনার ক্লাসের প্রশ্নপত্র আরও স্মার্টভাবে তৈরি করুন 💻',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFFD7E4F2), fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildStudioDropdownField({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    Key? key,
  }) {
    return DropdownButtonFormField<String>(
      key: key,
      value: items.contains(value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.6),
        ),
      ),
      items: [
        for (final item in items)
          DropdownMenuItem<String>(value: item, child: Text(item)),
      ],
      onChanged: items.isEmpty ? null : onChanged,
    );
  }

  Widget _buildStudioPicker() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 10, 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('প্রশ্ন বাছাই করুন',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800)),
                    Text(
                      '${_selectedClass ?? ''} • ${_selectedSubject ?? ''}',
                      style: TextStyle(
                          color: Colors.blueGrey.shade500, fontSize: 13),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Back to setup',
                onPressed: () => _goToStep(0),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            ],
          ),
        ),
        // The left pane is the selection itself; the filters live in the rail.
        _buildStickyBar(),
        Expanded(child: _buildPickerList()),
      ],
    );
  }

  // ── Right-hand preview ─────────────────────────────────────────────────────

  Widget _buildStudioPreview() {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 18, 12, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
              color: Color(0x120F172A), blurRadius: 24, offset: Offset(0, 8)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
            ),
            child: Row(
              children: [
                const Icon(Icons.visibility_outlined, size: 18),
                const SizedBox(width: 8),
                const Text('Live preview',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                Flexible(
                  child: Text(
                    '${_paperFont.label} • ${_imageSize.label}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        color: Colors.blueGrey.shade500, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: const Color(0xFFEDF0F5),
              child: _buildPaperPreview(),
            ),
          ),
        ],
      ),
    );
  }

  /// The paper as the reader will get it.
  ///
  /// The browser studio hosts the exported HTML in an iframe; Linux now does
  /// the same in an embedded Chromium view, so the pane shows the file itself.
  /// The Flutter drawing below stays as the placeholder while Chromium starts
  /// and as the fallback if it cannot.
  Widget _buildPaperPreview() {
    if (ExactHtmlPreview.supported && _selectedQuestions.isNotEmpty) {
      return ExactHtmlPreview(
        signature: _paperPreviewSignature,
        buildHtml: _buildPaperHtml,
        fileName: 'studio_live_preview.html',
        placeholderBuilder: (_) => _buildNativePaperPreview(),
        fallbackBuilder: (_) => _buildNativePaperPreview(),
      );
    }
    return _buildNativePaperPreview();
  }

  /// A cheap value that moves whenever the exported sheet would change.
  ///
  /// The embedded browser reloads only when this moves, so a hover or a scroll
  /// does not rebuild a megabyte of HTML.
  String get _paperPreviewSignature {
    final parts = <Object?>[
      _schoolCtrl.text,
      _examCtrl.text,
      _subjectCtrl.text,
      _classCtrl.text,
      _timeCtrl.text,
      _marksCtrl.text,
      _cqInstruction,
      _twoSets,
      _twoSets ? _setLabels.join('|') : '',
      _paperSectionOrder.join(','),
      _imageSize.name,
      _cqLayout.name,
      _mcqLayout.name,
      _rqLayout.name,
      _mcqAnswerSheetStyle.name,
      _fontStep,
      _paperFont.name,
      _paperFontsReady,
      _printSettings.signature,
    ];
    for (final q in _selectedQuestions) {
      parts.add('${q.id}:${q.setLabel}:${q.hashCode}:${q.isImportant}');
    }
    return parts.join('~');
  }

  /// The exact sheet the export writes, with the live preview's settings.
  String _buildPaperHtml() => HighSchoolExportService.generateHtml(
        schoolName: _schoolCtrl.text,
        examName: _examCtrl.text,
        subject: _subjectCtrl.text,
        className: _classCtrl.text,
        time: _timeCtrl.text,
        totalMarks: _marksCtrl.text,
        questions: _selectedQuestions,
        cqInstruction: _cqInstruction,
        printSettings: _printSettings,
        setLabels: _twoSets ? _setLabels : const [],
        sectionOrder: _paperSectionOrder,
        imageSize: _imageSize,
        cqLayout: _cqLayout,
        mcqLayout: _mcqLayout,
        rqLayout: _rqLayout,
        mcqAnswerSheetStyle: _mcqAnswerSheetStyle,
        manualAnswerCount: _manualAnswerItemCount,
        fontStep: _fontStep,
        font: _paperFont,
        desktopMode: true,
        // The browser studio moves the toolbar into its settings rail; the
        // pane is the paper, not the editor.
        includeToolbar: false,
      );

  /// The same sheet drawn in Flutter: the placeholder and the fallback.
  Widget _buildNativePaperPreview() {
    final questions = _questionsForSet(0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = min(constraints.maxWidth - 32, 780.0);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Container(
              width: width,
              constraints: BoxConstraints(minHeight: width * 1.414),
              padding: EdgeInsets.fromLTRB(
                  width * 0.06, width * 0.05, width * 0.06, width * 0.06),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                      color: Color(0x1F0F172A),
                      blurRadius: 14,
                      offset: Offset(0, 4)),
                ],
              ),
              child: questions.isEmpty
                  ? _buildEmptyPreview(width)
                  : _buildPaperSheet(questions, width),
            ),
          ),
        );
      },
    );
  }

  /// Text drawn on the preview sheet.
  ///
  /// The sheet is a document mock-up, so its wording is laid out as a
  /// [RichText] span rather than as a [Text] label the app's own widgets answer
  /// to. That keeps the paper's copy out of the widget tree the rest of the
  /// screen is built and queried from.
  Widget _sheetText(
    String text, {
    TextStyle? style,
    TextAlign? textAlign,
    int? maxLines,
    TextOverflow? overflow,
  }) {
    // A [RichText] does not inherit the ambient style the way a [Text] does,
    // so the paper is given the app's font by hand; otherwise the preview would
    // fall back to the platform default and lose HindSiliguri.
    final base = Theme.of(context).textTheme.bodyMedium ??
        DefaultTextStyle.of(context).style;
    return RichText(
      text: TextSpan(
        text: text,
        style: base.merge(style).copyWith(
              color: style?.color ?? const Color(0xFF1F2937),
            ),
      ),
      textAlign: textAlign ?? TextAlign.start,
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
      softWrap: true,
    );
  }

  Widget _buildEmptyPreview(double width) {
    final scale = width / 780.0;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.description_outlined,
              size: 56 * scale, color: const Color(0xFFCBD5E1)),
          SizedBox(height: 12 * scale),
          _sheetText(
            'প্রশ্ন বাছাই করলে এখানেই প্রশ্নপত্র দেখা যাবে',
            textAlign: TextAlign.center,
            style:
                TextStyle(color: const Color(0xFF94A3B8), fontSize: 13 * scale),
          ),
        ],
      ),
    );
  }

  Widget _buildPaperSheet(List<HighSchoolQuestion> questions, double width) {
    final scale = width / 780.0;
    double s(double value) => value * scale;

    final sections = _activeSections;
    final subject = _subjectCtrl.text.trim();
    final className = _classCtrl.text.trim();
    final time = _timeCtrl.text.trim();
    final totalMarks = _marksCtrl.text.trim();
    final instruction = _cqInstruction;

    final meta = <String>[
      if (subject.isNotEmpty) 'বিষয়: $subject',
      if (className.isNotEmpty) 'শ্রেণি: $className',
      if (time.isNotEmpty) 'সময়: $time',
      if (totalMarks.isNotEmpty) 'পূর্ণমান: $totalMarks',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_schoolCtrl.text.trim().isNotEmpty)
          _sheetText(
            _schoolCtrl.text.trim(),
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: s(19), fontWeight: FontWeight.w800, height: 1.2),
          ),
        if (_examCtrl.text.trim().isNotEmpty) ...[
          SizedBox(height: s(3)),
          _sheetText(
            _examCtrl.text.trim(),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: s(13.5), height: 1.2),
          ),
        ],
        SizedBox(height: s(8)),
        Container(
          padding: EdgeInsets.symmetric(vertical: s(4)),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: const Color(0xFF1F2937), width: s(1.4)),
              bottom: BorderSide(color: const Color(0xFF1F2937), width: s(1.4)),
            ),
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: s(10),
            runSpacing: s(2),
            children: [
              for (final item in meta)
                _sheetText(
                  item,
                  style:
                      TextStyle(fontSize: s(12), fontWeight: FontWeight.w700),
                ),
            ],
          ),
        ),
        if (instruction.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: s(4)),
            child: _sheetText(
              instruction,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: s(11), fontStyle: FontStyle.italic, height: 1.3),
            ),
          ),
        SizedBox(height: s(14)),
        if (sections.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: s(20)),
            child: _sheetText(
              'কোনো প্রশ্ন নির্বাচন করা হয়নি।',
              textAlign: TextAlign.center,
              style: TextStyle(color: const Color(0xFF94A3B8), fontSize: s(12)),
            ),
          ),
        for (final kind in sections) ...[
          Center(
            child: _sheetText(
              '${_sectionLetter(kind)}-বিভাগ: ${kind.title}',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: s(13), fontWeight: FontWeight.w800, height: 1.2),
            ),
          ),
          SizedBox(height: s(8)),
          ..._buildPreviewSection(
            kind,
            questions
                .where((q) => kind.isCq
                    ? q.isCq
                    : kind.isMcq
                        ? q.isMcq
                        : q.isShort)
                .toList(),
            s,
          ),
          SizedBox(height: s(14)),
        ],
      ],
    );
  }

  List<Widget> _buildPreviewSection(
    _SectionKind kind,
    List<HighSchoolQuestion> questions,
    double Function(double) s,
  ) {
    if (kind.isCq) {
      final out = <Widget>[];
      for (var i = 0; i < questions.length; i++) {
        final q = questions[i];
        out.addAll([
          _sheetText(
            '${_bengaliNumber(i + 1)}. ${q.paperStemText}',
            style: TextStyle(fontSize: s(12), height: 1.45),
          ),
          if (q.stemImageUrl.trim().isNotEmpty && _imageSize.isVisible)
            _buildPreviewImage(q.stemImageUrl, s),
          for (final sub in q.cqSubQuestions)
            Padding(
              padding: EdgeInsets.only(top: s(2), left: s(10)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _sheetText(
                      '(${sub.label}) ${sub.text}',
                      style: TextStyle(fontSize: s(11.5), height: 1.4),
                    ),
                  ),
                  SizedBox(width: s(6)),
                  _sheetText(
                    _bengaliNumber(sub.mark),
                    style: TextStyle(
                        fontSize: s(11.5), fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          SizedBox(height: s(8)),
        ]);
      }
      return out;
    }

    if (kind.isMcq) {
      final out = <Widget>[];
      for (var i = 0; i < questions.length; i++) {
        final q = questions[i];
        final mcq = q.mcqData;
        final opens = q.opensMcqStemGroup(i == 0 ? null : questions[i - 1]);
        out.addAll([
          if (opens) ...[
            _sheetText(
              q.mcqStemText,
              style: TextStyle(
                  fontSize: s(12), height: 1.4, fontWeight: FontWeight.w600),
            ),
            if (q.stemImageUrl.trim().isNotEmpty && _imageSize.isVisible)
              _buildPreviewImage(q.stemImageUrl, s),
          ],
          _sheetText(
            '${_bengaliNumber(i + 1)}. ${mcq?.text ?? ''}',
            style: TextStyle(fontSize: s(12), height: 1.45),
          ),
          if (mcq != null && mcq.options.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: s(3), left: s(14), bottom: s(6)),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final itemWidth = (constraints.maxWidth - s(10)) / 2;
                  const letters = ['ক', 'খ', 'গ', 'ঘ'];
                  return Wrap(
                    spacing: s(10),
                    runSpacing: s(2),
                    children: [
                      for (var o = 0; o < mcq.options.length; o++)
                        SizedBox(
                          width: itemWidth,
                          child: _sheetText(
                            '${o < letters.length ? letters[o] : o + 1}) '
                            '${mcq.options[o]}',
                            style: TextStyle(fontSize: s(11.5), height: 1.35),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
        ]);
      }
      return out;
    }

    return [
      for (var i = 0; i < questions.length; i++)
        Padding(
          padding: EdgeInsets.only(bottom: s(5)),
          child: _sheetText(
            '${_bengaliNumber(i + 1)}. ${questions[i].shortData?.text ?? ''}',
            style: TextStyle(fontSize: s(12), height: 1.45),
          ),
        ),
    ];
  }

  Widget _buildPreviewImage(String rawUrl, double Function(double) s) {
    final url = HighSchoolExportService.resolveImageUrl(rawUrl);
    if (url.isEmpty) return const SizedBox.shrink();
    final height = switch (_imageSize) {
      StemImageSize.hidden => 0.0,
      StemImageSize.small => s(90),
      StemImageSize.medium => s(130),
      StemImageSize.large => s(180),
    };
    if (height <= 0) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.symmetric(vertical: s(5)),
      child: Center(
        child: Image.network(
          url,
          height: height,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      ),
    );
  }

  // ── Right-hand settings rail ───────────────────────────────────────────────

  Widget _buildStudioSettingsRail() {
    final selected = _selectedQuestions.length;

    return Container(
      margin: const EdgeInsets.fromLTRB(0, 18, 12, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD9E1EA)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0D0F172A), blurRadius: 14, offset: Offset(0, 5)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            child: Row(
              children: [
                const Icon(Icons.tune_rounded, size: 17, color: _kPrimary),
                const SizedBox(width: 7),
                const Expanded(
                  child: Text('সেটিংস',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                ),
                IconButton(
                  tooltip: 'সেটিংস গুটান',
                  onPressed: () => setState(() => _desktopSettingsOpen = false),
                  icon: const Icon(Icons.tune, size: 19),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              key: const PageStorageKey('studio-settings-rail'),
              padding: const EdgeInsets.all(10),
              children: [
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF102F50)),
                    onPressed: selected == 0 ? null : () => _exportHtml(),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('HTML ডাউনলোড'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: selected == 0 ? null : _openLivePreview,
                    icon: const Icon(Icons.print_outlined, size: 18),
                    label: const Text('প্রিভিউ ও প্রিন্ট'),
                  ),
                ),
                if (_currentStep >= 1) ...[
                  _buildRailHeading('ফিল্টার'),
                  _buildRailFilters(),
                  const SizedBox(height: 8),
                  _buildRailRandomSelector(),
                  _buildRailHeading('Select'),
                  _buildPickerActions(),
                ],
                _buildRailHeading('পরীক্ষার তথ্য'),
                _buildRailPaperInfo(),
                _buildRailHeading('বিভাগ ও কলাম'),
                _buildSectionCard(),
                _buildRailHeading('প্রিন্ট সেটিংস'),
                _buildPrintSettings(),
                _buildRailHeading('সেট'),
                _buildRailSets(),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The picker's filters, sized for the settings rail.
  ///
  /// The wizard keeps these above the list; the desktop studio moves them here
  /// so the left pane is nothing but the questions being chosen.
  Widget _buildRailFilters() {
    int countOf(_PickFilter f) => _fetchedQuestions.where(f.matches).length;
    final chapterNumbers = _pickerChapterNumbers;
    final allChapters = _pickerChapterFilter.isEmpty ||
        _pickerChapterFilter.containsAll(chapterNumbers);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ফিল্টার',
            style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w700, color: _kSubText)),
        const SizedBox(height: 5),
        SizedBox(
          height: 30,
          child: TextField(
            controller: _pickSearchCtrl,
            onChanged: (v) => setState(() => _pickSearchQuery = v),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              prefixIcon: const Icon(Icons.search, size: 16),
              hintText: 'অনুসন্ধান…',
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: BorderSide.none,
              ),
              suffixIcon: _pickSearchQuery.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () {
                        _pickSearchCtrl.clear();
                        setState(() => _pickSearchQuery = '');
                      },
                    ),
            ),
          ),
        ),
        const SizedBox(height: 5),
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: [
            for (final f in _PickFilter.values)
              _PickFilterChip(
                label: f.badge,
                title: f.title,
                count: countOf(f),
                color: f.color,
                selected: _pickFilter == f,
                onTap: () => setState(() => _pickFilter = f),
              ),
          ],
        ),
        if (_pickIsNarrowed) ...[
          const SizedBox(height: 3),
          Text('${_visibleQuestions.length} টি দেখানো হচ্ছে',
              style: const TextStyle(fontSize: 10, color: _kSubText)),
        ],
        const SizedBox(height: 5),
        Wrap(
          spacing: 5,
          runSpacing: 5,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('ছবি:',
                style: TextStyle(fontSize: 10, color: _kSubText)),
            for (final f in _ImageFilter.values)
              _PickFilterChip(
                label: f.badge,
                title: f.title,
                count: _fetchedQuestions.where(f.matches).length,
                color: f.color,
                selected: _imageFilter == f,
                onTap: () => setState(() => _imageFilter = f),
              ),
          ],
        ),
        if (chapterNumbers.length >= 2) ...[
          const SizedBox(height: 5),
          Row(
            children: [
              const Icon(Icons.filter_alt_outlined, size: 13, color: _kSubText),
              const SizedBox(width: 4),
              const Text('অধ্যায়',
                  style: TextStyle(fontSize: 10, color: _kSubText)),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() {
                  if (allChapters) {
                    _pickerChapterFilter.clear();
                  } else {
                    _pickerChapterFilter
                      ..clear()
                      ..addAll(chapterNumbers);
                  }
                }),
                child: Text(
                  allChapters ? 'সব দেখান' : 'শুধু এগুলো',
                  style: const TextStyle(
                      fontSize: 10,
                      color: _kPrimary,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              for (final c in chapterNumbers)
                _PickerChapterChip(
                  chapterNumber: c,
                  count: _fetchedQuestions
                      .where((q) => q.chapterNumber == c)
                      .length,
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
            ],
          ),
        ],
        if (_marksBreakdown.hidden > 0) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 14, color: Colors.amber),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'ফিল্টারের বাইরে ${_marksBreakdown.hidden} নম্বরের নির্বাচিত '
                    'প্রশ্ন আছে — মোট নম্বরে ধরা হয়েছে।',
                    style: const TextStyle(fontSize: 10.5, color: Colors.amber),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// The random draw, stacked for the rail rather than one long row.
  Widget _buildRailRandomSelector() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: _kPrimary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: _kPrimary.withOpacity(0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.casino_outlined, size: 16, color: _kPrimary),
              const SizedBox(width: 6),
              const Text('এলোমেলো নির্বাচন',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
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
          const SizedBox(height: 8),
          SizedBox(
            height: 32,
            child: ElevatedButton(
              onPressed: _pickRandomQuestions,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9)),
              ),
              child: const Text('বাছাই',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollapsedSettingsRail() {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 18, 12, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD9E1EA)),
      ),
      child: Column(
        children: [
          IconButton(
            tooltip: 'সেটিংস খুলুন',
            onPressed: () => setState(() => _desktopSettingsOpen = true),
            icon: const Icon(Icons.tune_outlined),
          ),
          const Divider(height: 1),
          IconButton(
            tooltip: 'প্রিভিউ ও প্রিন্ট',
            onPressed: _selectedQuestions.isEmpty ? null : _openLivePreview,
            icon: const Icon(Icons.print_outlined),
          ),
        ],
      ),
    );
  }

  /// The mint heading the browser rail uses to separate its groups.
  Widget _buildRailHeading(String text) {
    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFFE8F8F1),
        border: Border(top: BorderSide(color: Color(0xFF0F9F70))),
      ),
      child: Text(text,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
    );
  }

  Widget _buildRailPaperInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTextField(
            ctrl: _schoolCtrl,
            label: 'শিক্ষা প্রতিষ্ঠানের নাম',
            onChanged: (_) => setState(() {})),
        const SizedBox(height: 8),
        _buildTextField(
            ctrl: _examCtrl,
            label: 'পরীক্ষার নাম',
            onChanged: (_) => setState(() {})),
        const SizedBox(height: 8),
        _buildTextField(
            ctrl: _subjectCtrl,
            label: 'বিষয়',
            onChanged: (_) => setState(() {})),
        const SizedBox(height: 8),
        _buildTextField(
            ctrl: _classCtrl,
            label: 'শ্রেণি ও শাখা',
            onChanged: (_) => setState(() {})),
        const SizedBox(height: 8),
        _buildTextField(
            ctrl: _timeCtrl, label: 'সময়', onChanged: (_) => setState(() {})),
        const SizedBox(height: 8),
        _buildTextField(
          ctrl: _marksCtrl,
          label: 'পূর্ণমান',
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        _buildTextField(
          ctrl: _cqAnswerAnyCtrl,
          label: 'যেকোনো কয়টি CQ-র উত্তর দিতে হবে',
          keyboardType: TextInputType.text,
          hintText: 'যেমন: ৫ অথবা নিজের নির্দেশনা',
          helperText: 'খালি রাখলে লেখা হবে না।'
              '${_selectedCqs.isEmpty ? '' : ' সর্বোচ্চ ${_selectedCqs.length}টি দেওয়া যাবে।'}',
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  /// The reference panel's A button: add one free line under the exam title.
  Future<void> _editHeaderNote() async {
    final ctrl = TextEditingController(text: _headerNoteCtrl.text);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('অতিরিক্ত হেডার লাইন'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'যেমন: শিক্ষা সপ্তাহ ২০২৬',
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('বাতিল'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(ctrl.text),
            child: const Text('যোগ করুন'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null) return;
    setState(() => _headerNoteCtrl.text = result.trim());
  }

  /// Pick a logo for the branding band and carry it as a data URI, so the
  /// exported HTML is a single self-contained file.
  Future<void> _pickLogo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      _showError('লোগোর ছবিটি পড়া যায়নি।');
      return;
    }
    final ext = (file.extension ?? 'png').toLowerCase();
    final mime = switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      _ => 'image/png',
    };
    setState(() {
      _logoDataUri = 'data:$mime;base64,${base64Encode(bytes)}';
      _logoName = file.name;
      _showLogo = true;
    });
  }

  /// The desktop settings panel: the same choices the browser studio's rail
  /// offers, grouped the way the reference panel groups them.
  Widget _buildPrintSettings() {
    final repeated = _repeatedQuestions;
    final globalColumns = _cqLayout == _mcqLayout && _mcqLayout == _rqLayout
        ? _cqLayout
        : _mcqLayout;
    final fontSize = (14 + _fontStep).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _railSubheading('প্রশ্ন সংযুক্তি'),
        _railSwitch(
          'গুরুত্বপূর্ণ প্রশ্ন',
          _showImportant,
          (value) => setState(() => _showImportant = value),
        ),
        _railSwitch(
          'প্রশ্নের তথ্য',
          _showQuestionInfo,
          (value) => setState(() => _showQuestionInfo = value),
        ),
        _railSwitch(
          'শিক্ষার্থীর তথ্য',
          _showStudentInfo,
          (value) => setState(() => _showStudentInfo = value),
        ),
        _railSwitch(
          'বিষয় কোড',
          _showSubjectCode,
          (value) => setState(() => _showSubjectCode = value),
        ),
        if (_showSubjectCode) ...[
          const SizedBox(height: 4),
          _buildTextField(
            ctrl: _subjectCodeCtrl,
            label: 'বিষয় কোড',
            hintText: 'যেমন: ১০১',
            onChanged: (_) => setState(() {}),
          ),
        ],
        _railSwitch(
          'প্রাপ্ত নম্বর ঘর',
          _showObtainedMarks,
          (value) => setState(() => _showObtainedMarks = value),
        ),
        _railSubheading('প্রশ্নের মেটাডেটা (হেডার)'),
        _railSwitch(
          'প্রতিষ্ঠানের নাম',
          _showSchool,
          (value) => setState(() => _showSchool = value),
          trailing: IconButton(
            tooltip: 'অতিরিক্ত হেডার লাইন যোগ করুন',
            onPressed: _editHeaderNote,
            icon: const Text(
              'A',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ),
        _railSwitch('শ্রেণির নাম', _showClass,
            (value) => setState(() => _showClass = value)),
        _railSwitch('বিষয়ের নাম', _showSubject,
            (value) => setState(() => _showSubject = value)),
        _railSwitch('অধ্যায়ের নাম', _showChapter,
            (value) => setState(() => _showChapter = value)),
        _railSwitch(
            'সেট কোড', _showSet, (value) => setState(() => _showSet = value)),
        _railSwitch('প্রোগ্রাম/পরীক্ষার নাম', _showExam,
            (value) => setState(() => _showExam = value)),
        _railSwitch('নির্দেশনা', _showInstructions,
            (value) => setState(() => _showInstructions = value)),
        _railSubheading('ডকুমেন্ট কাস্টমাইজেশন'),
        _railSwitch('এডিটিং মোড', _editingMode,
            (value) => setState(() => _editingMode = value)),
        _railSegmented<PaperTextAlign>(
          label: 'টেক্সট এলাইনমেন্ট',
          value: _textAlign,
          items: PaperTextAlign.values,
          itemLabel: (align) => align.label,
          onChanged: (value) => setState(() => _textAlign = value),
        ),
        _railSegmented<PaperSize>(
          label: 'পেপার সাইজ',
          value: _paperSize,
          items: PaperSize.values,
          itemLabel: (size) => size.label,
          onChanged: (value) => setState(() => _paperSize = value),
        ),
        _railButton(
          label: 'পেজ সেটআপ (প্রিভিউ)',
          icon: Icons.tune_rounded,
          onPressed: _selectedQuestions.isEmpty ? null : _openLivePreview,
        ),
        _railSwitch('পৃষ্ঠা নম্বর', _pageNumbers,
            (value) => setState(() => _pageNumbers = value)),
        _railSubheading('টাইপোগ্রাফি ও কলাম'),
        _railSegmented<McqOptionStyle>(
          label: 'অপশন স্টাইল',
          value: _optionStyle,
          items: McqOptionStyle.values,
          itemLabel: (style) => style.label,
          onChanged: (value) => setState(() => _optionStyle = value),
        ),
        _buildRailDropdown<PaperFont>(
          label: 'ফন্ট পরিবর্তন',
          value: _paperFont,
          items: PaperFont.values,
          itemLabel: (font) => font.label,
          onChanged: (value) {
            if (value != null) setState(() => _paperFont = value);
          },
        ),
        _railStepper(
          label: 'ফন্ট সাইজ',
          value: fontSize,
          min: (14 + _fontStepMin).round(),
          max: (14 + _fontStepMax).round(),
          onChanged: (value) => setState(() => _fontStep = value - 14.0),
        ),
        _railSegmented<QuestionLayout>(
          label: 'কলাম (সব বিভাগে)',
          value: globalColumns,
          items: const [
            QuestionLayout.single,
            QuestionLayout.doubleColumn,
            QuestionLayout.tripleColumn,
          ],
          itemLabel: (layout) => layout.mcqColumns.toString(),
          onChanged: (value) => setState(() {
            _cqLayout = value;
            _mcqLayout = value;
            _rqLayout = value;
          }),
        ),
        _railSwitch('কলাম ডিভাইডার', _columnDivider,
            (value) => setState(() => _columnDivider = value)),
        _railSlider(
          label: 'প্রশ্নের নিচের গ্যাপ',
          value: _questionGap,
          min: 0,
          max: 24,
          onChanged: (value) => setState(() => _questionGap = value),
        ),
        _railSlider(
          label: 'কলামের গ্যাপ',
          value: _columnGap,
          min: 0,
          max: 40,
          onChanged: (value) => setState(() => _columnGap = value),
        ),
        _buildRailDropdown<StemImageSize>(
          label: 'ছবির আকার',
          value: _imageSize,
          items: StemImageSize.values,
          itemLabel: (size) =>
              size == StemImageSize.hidden ? 'বন্ধ' : size.label,
          onChanged: (value) {
            if (value != null) setState(() => _imageSize = value);
          },
        ),
        _buildRailDropdown<McqAnswerSheetStyle>(
          label: 'MCQ উত্তরপত্র',
          value: _mcqAnswerSheetStyle,
          items: McqAnswerSheetStyle.values,
          itemLabel: (style) => style.label,
          onChanged: (value) {
            if (value != null) {
              setState(() => _mcqAnswerSheetStyle = value);
            }
          },
        ),
        if (_selectedMcqs.isEmpty &&
            _mcqAnswerSheetStyle == McqAnswerSheetStyle.omr)
          _buildManualAnswerCountField(),
        _railSubheading('সহায়ক টুলস'),
        _railSwitch('পুনরাবৃত্ত প্রশ্ন শনাক্ত', _detectRepeated,
            (value) => setState(() => _detectRepeated = value)),
        if (_detectRepeated)
          Container(
            margin: const EdgeInsets.only(bottom: 5),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: repeated.isEmpty
                  ? const Color(0xFFECFDF5)
                  : const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              repeated.isEmpty
                  ? 'কোনো পুনরাবৃত্ত প্রশ্ন পাওয়া যায়নি।'
                  : '${repeated.length}টি প্রশ্নের পাঠ একই — এগুলো একবারই রাখুন।',
              style: const TextStyle(fontSize: 11.5, color: _kSubText),
            ),
          ),
        _railSwitch('শর্টকাট', _shortcutHints,
            (value) => setState(() => _shortcutHints = value)),
        if (_shortcutHints)
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: _selectAll,
                icon: const Icon(Icons.done_all_rounded, size: 16),
                label:
                    const Text('সব নির্বাচন', style: TextStyle(fontSize: 11.5)),
              ),
              TextButton.icon(
                onPressed: _pickRandomQuestions,
                icon: const Icon(Icons.shuffle_rounded, size: 16),
                label: const Text('এলোমেলো', style: TextStyle(fontSize: 11.5)),
              ),
            ],
          ),
        _railButton(
          label: 'শাফল (সেট কোড তৈরি)',
          icon: Icons.shuffle_rounded,
          onPressed: _selectedQuestions.length < 2 ? null : _shuffleIntoTwoSets,
        ),
        _railSubheading('ব্র্যান্ডিং'),
        _railSwitch(
            'লোগো', _showLogo, (value) => setState(() => _showLogo = value)),
        if (_showLogo)
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickLogo,
                  icon: const Icon(Icons.image_outlined, size: 16),
                  label: Text(
                    _logoName.isEmpty ? 'লোগো নির্বাচন' : _logoName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
              ),
              if (_logoDataUri.isNotEmpty)
                IconButton(
                  tooltip: 'লোগো সরান',
                  onPressed: () => setState(() {
                    _logoDataUri = '';
                    _logoName = '';
                  }),
                  icon: const Icon(Icons.close_rounded, size: 16),
                ),
            ],
          ),
        _railSwitch('হেডার', _showHeader,
            (value) => setState(() => _showHeader = value)),
        _railSwitch('ফুটার', _showFooter,
            (value) => setState(() => _showFooter = value)),
        _railSwitch('জলছাপ', _showWatermark,
            (value) => setState(() => _showWatermark = value)),
        if (_showWatermark) ...[
          const SizedBox(height: 4),
          _buildTextField(
            ctrl: _watermarkCtrl,
            label: 'জলছাপের লেখা',
            hintText: 'যেমন: নমুনা',
            onChanged: (_) => setState(() {}),
          ),
        ],
        _railSwitch('ঠিকানা', _showAddress,
            (value) => setState(() => _showAddress = value)),
        if (_showAddress) ...[
          const SizedBox(height: 4),
          _buildTextField(
            ctrl: _addressCtrl,
            label: 'প্রতিষ্ঠানের ঠিকানা',
            hintText: 'গ্রাম/শহর, উপজেলা',
            onChanged: (_) => setState(() {}),
          ),
        ],
      ],
    );
  }

  Widget _railSubheading(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: _kSubText,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _railSwitch(
    String label,
    bool value,
    ValueChanged<bool> onChanged, {
    Widget? trailing,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12.5, color: _kDarkText),
            ),
          ),
          if (trailing != null) trailing,
          Transform.scale(
            scale: 0.78,
            child: Switch.adaptive(
              value: value,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  Widget _railSegmented<T>({
    required String label,
    required T value,
    required List<T> items,
    required String Function(T) itemLabel,
    required ValueChanged<T> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F3F6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12.5, color: _kDarkText),
          ),
          const SizedBox(height: 5),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final item in items)
                InkWell(
                  onTap: () => onChanged(item),
                  borderRadius: BorderRadius.circular(5),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: item == value ? _kPrimary : Colors.white,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color:
                            item == value ? _kPrimary : const Color(0xFFD9E1EA),
                      ),
                    ),
                    child: Text(
                      itemLabel(item),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: item == value ? Colors.white : _kDarkText,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _railSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 12.5, color: _kDarkText),
              ),
            ),
            Text(
              '${value.round()}px',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: _kPrimary,
              ),
            ),
          ],
        ),
        SizedBox(
          height: 28,
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: (max - min).round(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _railStepper({
    required String label,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F3F6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12.5, color: _kDarkText),
            ),
          ),
          IconButton(
            onPressed: value > min ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove_circle_outline, size: 18),
            visualDensity: VisualDensity.compact,
          ),
          SizedBox(
            width: 28,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: _kPrimary,
              ),
            ),
          ),
          IconButton(
            onPressed: value < max ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add_circle_outline, size: 18),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _railButton({
    required String label,
    required IconData icon,
    VoidCallback? onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 16),
          label: Text(label, style: const TextStyle(fontSize: 12)),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 8),
            visualDensity: VisualDensity.compact,
          ),
        ),
      ),
    );
  }

  Widget _buildRailDropdown<T>({
    required String label,
    required T value,
    required List<T> items,
    required String Function(T) itemLabel,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F3F6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 12.5, color: _kDarkText)),
          ),
          SizedBox(
            width: 130,
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              iconSize: 19,
              style: const TextStyle(fontSize: 12.5, color: _kDarkText),
              items: [
                for (final item in items)
                  DropdownMenuItem<T>(
                    value: item,
                    child: Text(itemLabel(item),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualAnswerCountField() {
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F3F6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text('OMR আইটেম',
                style: TextStyle(fontSize: 12.5, color: _kDarkText)),
          ),
          SizedBox(
            width: 86,
            child: TextFormField(
              key: const ValueKey('manual-omr-count'),
              initialValue: '$_manualAnswerItemCount',
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                final count = int.tryParse(value);
                if (count != null) {
                  setState(() => _manualAnswerItemCount = count.clamp(1, 200));
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRailSets() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F3F6),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 9),
                  child: Text('দুইটি সেটে প্রশ্নপত্র',
                      style: TextStyle(fontSize: 12.5, color: _kDarkText)),
                ),
              ),
              Transform.scale(
                scale: 0.8,
                child: Switch(
                  value: _twoSets,
                  activeColor: _kPrimary,
                  onChanged: (v) => setState(() {
                    _twoSets = v;
                    if (!v) _assignAllToFirstSet();
                  }),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'ক ও খ একই পেজে তৈরি হবে — আলাদা করে তৈরি করলে প্রতিটির একটা পেজ নষ্ট হয়।',
          style: TextStyle(fontSize: 11, color: _kSubText),
        ),
        if (_twoSets) ...[
          const SizedBox(height: 8),
          _buildTextField(
            ctrl: _setLabelControllers[0],
            label: 'প্রথম সেটের নাম',
            icon: Icons.looks_one,
          ),
          const SizedBox(height: 8),
          _buildTextField(
            ctrl: _setLabelControllers[1],
            label: 'দ্বিতীয় সেটের নাম',
            icon: Icons.looks_two,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed:
                _selectedQuestions.length < 2 ? null : _splitSelectedEvenly,
            icon: const Icon(Icons.balance, size: 16),
            label: Text('অর্ধেক ভাগ করো (${_selectedQuestions.length} টি)'),
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: _assignAllToFirstSet,
            icon: const Icon(Icons.merge_type, size: 16),
            label: const Text('সব প্রশ্ন প্রথম সেটে'),
          ),
          const SizedBox(height: 10),
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
                  Expanded(
                    child: Text(
                      '${_questionsForSet(i).length} টি প্রশ্ন'
                      '  ·  ${_questionsForSet(i).fold(0, (s, q) => s + q.totalMarks)} নম্বর',
                      style: const TextStyle(fontSize: 11, color: _kSubText),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          const Text(
            'প্রতিটি প্রশ্নের কার্ডে সেট বদলাতে পারেন।',
            style: TextStyle(fontSize: 11, color: _kSubText),
          ),
        ],
      ],
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
            const Expanded(
              child: Text('অধ্যায় নির্বাচন করুন',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: _kDarkText)),
            ),
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
      padding: const EdgeInsets.fromLTRB(10, 2, 6, 2),
      decoration: BoxDecoration(
        color: _kPrimary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kPrimary.withOpacity(0.16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The whole header is the target: the chevron is the affordance,
          // but a thumb should not have to find it on a phone.
          InkWell(
            key: const ValueKey('random-selector-toggle'),
            onTap: () =>
                setState(() => _randomSelectorOpen = !_randomSelectorOpen),
            borderRadius: BorderRadius.circular(9),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(Icons.casino_outlined, size: 15, color: _kPrimary),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'এলোমেলো নির্বাচন',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: _kDarkText,
                      ),
                    ),
                  ),
                  Text(
                    _randomSelectorOpen ? 'গুটান' : 'খুলুন',
                    style: const TextStyle(fontSize: 10.5, color: _kSubText),
                  ),
                  const SizedBox(width: 2),
                  AnimatedRotation(
                    turns: _randomSelectorOpen ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(Icons.keyboard_arrow_down_rounded,
                        size: 17, color: _kSubText),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _randomSelectorOpen
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Row(
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
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(9),
                              ),
                            ),
                            child: const Text(
                              'বাছাই',
                              style: TextStyle(
                                  fontSize: 12.5, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  /// Step 2 of the wizard: the filters, the actions and the question list.
  ///
  /// The desktop studio splits this apart — the list keeps the left pane and
  /// the filters move into the settings rail — but the wizard needs it whole.
  Widget _buildStep2() {
    final visible = _visibleQuestions;
    return Column(
      children: [
        // Chapter filter, when the paper draws on more than one
        _buildPickerChapterBar(_pickerChapterNumbers),
        // Type filter + search
        _buildPickFilterBar(visible.length),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
          child: _buildRandomSelectorBar(),
        ),
        Expanded(child: _buildPickerList()),
      ],
    );
  }

  /// Every chapter the fetched questions come from, in paper order.
  List<String> get _pickerChapterNumbers => [
        for (final c in _fetchedQuestions.map((q) => q.chapterNumber).toSet()) c
      ]..sort(compareChapterNumbers);

  /// Select all / none, plus hand entry.
  ///
  /// The rail is narrow, so the three actions sit two-up over one full-width
  /// row rather than each taking a line of its own. Compact tap targets keep
  /// the block short without making the buttons hard to hit.
  Widget _buildPickerActions() {
    final style = TextButton.styleFrom(
      minimumSize: const Size(0, 30),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      alignment: Alignment.centerLeft,
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    );
    final allLabel = _pickIsNarrowed ? 'Select list' : 'Select all';
    final noneLabel = _pickIsNarrowed ? 'Exclude list' : 'Clear';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextButton.icon(
                icon: const Icon(Icons.done_all_rounded, size: 16),
                label: Text(allLabel,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                style: style,
                onPressed: _selectAll,
              ),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: TextButton.icon(
                icon: const Icon(Icons.remove_done_rounded, size: 16),
                label: Text(noneLabel,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                style: style.copyWith(
                    foregroundColor: WidgetStatePropertyAll(Colors.grey)),
                onPressed: _deselectAll,
              ),
            ),
          ],
        ),
        TextButton.icon(
          icon: const Icon(Icons.edit_note_rounded, size: 16),
          label: const Text('Add question'),
          style: style.copyWith(
              foregroundColor: WidgetStatePropertyAll(_kPrimary)),
          onPressed: _openManualQuestion,
        ),
      ],
    );
  }

  /// The scrolling question list, on the same light panel the browser studio
  /// uses. It is the whole left pane of the desktop studio, and the bottom half
  /// of step 2 in the wizard.
  Widget _buildPickerList() {
    final visible = _visibleQuestions;
    final byChapter = <String, List<HighSchoolQuestion>>{};
    for (final q in visible) {
      byChapter.putIfAbsent(q.chapterNumber, () => []).add(q);
    }
    final chapterNumbers = byChapter.keys.toList()..sort(compareChapterNumbers);

    // The উদ্দীপক runs, so a card can say it is one of a shared pair and a click
    // on it can take the pair along.
    final stemRuns = _mcqStemRuns();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 2, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F4F8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD9E1EA)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: ListView(
          key: const ValueKey('studio-picker-list'),
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 100),
          children: [
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
                onSelect: () => _selectChapter(chNum),
                onExclude: () => _deselectChapter(chNum),
                onAdd: () => _openManualQuestion(initialChapter: chNum),
              ),
              const SizedBox(height: 8),
              // A folded chapter shows its header and nothing else.
              if (!_collapsedChapters.contains(chNum)) ...[
                for (final q in _pickerOrder(byChapter[chNum]!))
                  _buildQuestionCard(
                      q, _cardKey(q, _fetchedQuestions.indexOf(q)),
                      run: stemRuns[q.id]),
              ],
              const SizedBox(height: 12),
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Single compact row: search + both dropdowns ──────────────────
          Row(
            children: [
              // Search field — takes the remaining width
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _pickSearchCtrl,
                    onChanged: (v) => setState(() => _pickSearchQuery = v),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: const Icon(Icons.search, size: 17),
                      hintText: 'অনুসন্ধান…',
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: _pickSearchQuery.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close, size: 15),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                _pickSearchCtrl.clear();
                                setState(() => _pickSearchQuery = '');
                              },
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Question-type dropdown — compact fixed width
              _CompactFilterDropdown<_PickFilter>(
                value: _pickFilter,
                items: _PickFilter.values,
                displayText: (f) => f == _PickFilter.all
                    ? 'সব'
                    : '${f.badge} ${countOf(f)}',
                itemLabel: (f) => '${f.badge} ${countOf(f)}',
                itemColor: (f) => f.color,
                onChanged: (f) => setState(() => _pickFilter = f!),
              ),
              const SizedBox(width: 6),
              // Image filter dropdown — compact fixed width
              _CompactFilterDropdown<_ImageFilter>(
                value: _imageFilter,
                items: _ImageFilter.values,
                displayText: (f) => f == _ImageFilter.all
                    ? 'ছবি'
                    : f.badge,
                itemLabel: (f) =>
                    '${f.badge} ${_fetchedQuestions.where(f.matches).length}',
                itemColor: (f) => f.color,
                onChanged: (f) => setState(() => _imageFilter = f!),
                icon: Icons.image_outlined,
              ),
            ],
          ),
          // Narrowed-count notice
          if (_pickIsNarrowed) ...[
            const SizedBox(height: 4),
            Text('$visibleCount টি দেখানো হচ্ছে',
                style: const TextStyle(fontSize: 10, color: _kSubText)),
          ],
          // Hidden-selection warning
          if (_marksBreakdown.hidden > 0) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 14, color: Colors.amber),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'ফিল্টারের বাইরে ${_marksBreakdown.hidden} নম্বরের নির্বাচিত '
                      'প্রশ্ন আছে — মোট নম্বরে ধরা হয়েছে।',
                      style: const TextStyle(
                          fontSize: 10.5, color: Colors.amber),
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
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF5C35E3), Color(0xFF7C5CF0)],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: _kPrimary.withOpacity(0.28),
              blurRadius: 14,
              offset: const Offset(0, 5))
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 12,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
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
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _proceedToGenerate,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: _kPrimary,
              elevation: 0,
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

  /// One question in the picker.
  ///
  /// Laid out like the browser studio's card: the question text leads, the type
  /// sits as a pill on the right, and the options or sub-questions are shown
  /// inline so the reader can tell what a tick would put on the paper without
  /// opening anything. Tapping anywhere on the card ticks it; tapping the
  /// figure opens the figure instead.
  Widget _buildQuestionCard(HighSchoolQuestion q, String cardKey,
      {List<HighSchoolQuestion>? run}) {
    final typeColor = q.isCq ? _kCqColor : (q.isShort ? _kRqColor : _kMcqColor);
    // An MCQ's shared উদ্দীপক is worth reading before ticking, so it rides
    // above the question rather than being hidden behind a disclosure.
    final intro = q.isMcq ? q.mcqStemText.trim() : '';

    return AnimatedContainer(
      key: ValueKey('question-card-$cardKey'),
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: q.isSelected ? const Color(0xFFF7F5FF) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: q.isSelected ? _kPrimary : const Color(0xFFD9E1EA),
          width: q.isSelected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: q.isSelected
                ? _kPrimary.withOpacity(0.10)
                : Colors.black.withOpacity(0.035),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            // Anywhere on the card ticks it, the way the browser studio does.
            // The figure keeps its own tap, so a click there opens the image
            // instead of selecting the question.
            onTap: () => _toggleQuestion(q),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 6, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: q.isSelected,
                    activeColor: _kPrimary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5)),
                    onChanged: (_) => _toggleQuestion(q),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        if (intro.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 5),
                            child: Text(
                              intro,
                              style: const TextStyle(
                                  fontSize: 12, height: 1.3, color: _kSubText),
                            ),
                          ),
                        Text(
                          _previewText(q),
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.35,
                            fontWeight: FontWeight.w700,
                            color: _kDarkText,
                          ),
                        ),
                        if (q.isMcq) _buildCardOptions(q),
                        if (q.isCq) _buildCardSubQuestions(q),
                        if (q.stemImageUrl.trim().isNotEmpty)
                          _buildCardThumbnail(q),
                        const SizedBox(height: 7),
                        _buildCardTags(q, run),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _TypeBadge(type: q.questionType, color: typeColor),
                      const SizedBox(height: 8),
                      _MarksBadge(marks: q.totalMarks),
                    ],
                  ),
                  if (_showImportant)
                    IconButton(
                      tooltip: q.isImportant
                          ? 'গুরুত্বপূর্ণ চিহ্ন সরান'
                          : 'গুরুত্বপূর্ণ হিসেবে চিহ্নিত করুন',
                      onPressed: () =>
                          setState(() => q.isImportant = !q.isImportant),
                      icon: Icon(
                        q.isImportant
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        size: 18,
                      ),
                      color:
                          q.isImportant ? const Color(0xFFD97706) : _kSubText,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  IconButton(
                    tooltip: 'সম্পাদনা করুন',
                    onPressed: () => _openEditQuestion(q),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    color: _kPrimary,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The four options, in the two-column grid the browser studio uses.
  Widget _buildCardOptions(HighSchoolQuestion q) {
    final mcq = q.mcqData;
    if (mcq == null || mcq.options.isEmpty) return const SizedBox.shrink();
    const letters = ['ক', 'খ', 'গ', 'ঘ'];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = constraints.maxWidth <= 8
              ? constraints.maxWidth
              : (constraints.maxWidth - 8) / 2;
          return Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (var i = 0; i < mcq.options.length; i++)
                Builder(builder: (context) {
                  final isCorrect = mcq.options[i] == mcq.correctAns;
                  return Container(
                    width: itemWidth,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: isCorrect
                          ? _kRqColor.withOpacity(0.10)
                          : const Color(0xFFF1F3F6),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isCorrect
                            ? _kRqColor.withOpacity(0.55)
                            : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 18,
                          height: 18,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isCorrect ? _kRqColor : Colors.white,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isCorrect
                                  ? _kRqColor
                                  : const Color(0xFFD9E1EA),
                            ),
                          ),
                          child: Text(
                            i < letters.length ? letters[i] : '${i + 1}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: isCorrect ? Colors.white : _kSubText,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: mathText(
                            mcq.options[i],
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.2,
                              fontWeight:
                                  isCorrect ? FontWeight.w700 : FontWeight.w400,
                              color: isCorrect ? _kRqColor : _kDarkText,
                            ),
                          ),
                        ),
                        if (isCorrect)
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(Icons.check_circle,
                                size: 14, color: _kRqColor),
                          ),
                      ],
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }

  /// A CQ's sub-questions, with their marks, under the উদ্দীপক.
  Widget _buildCardSubQuestions(HighSchoolQuestion q) {
    final subs = q.cqSubQuestions;
    if (subs.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final sub in subs)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _kCqColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      sub.label,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: _kCqColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      sub.text,
                      style: const TextStyle(fontSize: 13, height: 1.3),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('[${sub.mark}]',
                      style: const TextStyle(fontSize: 11, color: _kSubText)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// A small figure on the card, the way the browser studio shows one.
  Widget _buildCardThumbnail(HighSchoolQuestion q) {
    final imageUrl = HighSchoolExportService.resolveImageUrl(q.stemImageUrl);
    if (imageUrl.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => _showCardImage(imageUrl),
          child: Container(
            height: 120,
            width: 200,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Image.network(
              imageUrl,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Center(
                child: Icon(Icons.broken_image_outlined,
                    color: Colors.grey, size: 20),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Chapter, source and set chips under the question text.
  Widget _buildCardTags(HighSchoolQuestion q, List<HighSchoolQuestion>? run) {
    return Wrap(
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
        // Where the row came from, so a hand-typed question is not mistaken
        // for one that is in the bank.
        if (q.isManual)
          _TagChip(
              label: 'নিজে লেখা',
              color: Colors.amber.shade100,
              textColor: Colors.amber.shade900),
        // Corrected here without touching the sheet, so it is worth saying
        // which rows differ from the bank.
        if (q.isEdited)
          _TagChip(
              label: 'সম্পাদিত',
              color: Colors.deepOrange.shade50,
              textColor: Colors.deepOrange.shade700),
        // One উদ্দীপক over several questions: the run is selected whole, so say
        // which run this card is part of rather than letting a second question
        // tick itself without explanation.
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
              label:
                  _setLabels[i].isEmpty ? (i == 0 ? 'ক' : 'খ') : _setLabels[i],
              active: q.setLabel == _setLabels[i],
              selected: q.isSelected,
              onTap: () {
                _toggleQuestion(q);
                _toggleQuestionSet(q, i);
              },
            ),
      ],
    );
  }

  /// The sheet that opens when a card's figure is tapped.
  void _showCardImage(String imageUrl) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: Stack(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900, maxHeight: 680),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4,
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.grey),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: IconButton(
                tooltip: 'বন্ধ করুন',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 3 — Exam Header Config & Export
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStep3() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
              icon: Icons.edit_document, label: 'পরীক্ষার তথ্য পূরণ করুন'),
          const SizedBox(height: 8),

          // The paper in one glance, before anything is written.
          _buildSummaryChips(),
          const SizedBox(height: 10),

          // Everything the paper's masthead prints, in one card.
          _buildPaperInfoCard(),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kPrimary.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.analytics_outlined, size: 16, color: _kPrimary),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'নির্বাচনের সারাংশ',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: _kDarkText,
                  ),
                ),
              ),
              _SummaryChip(
                icon: Icons.star_rounded,
                label: 'মোট $_totalSelectedMarks',
                emphasized: true,
              ),
            ],
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              _SummaryChip(
                icon: Icons.quiz_rounded,
                label: 'CQ ${_selectedCqs.length}টি · ${marks.cq}',
              ),
              _SummaryChip(
                icon: Icons.format_list_bulleted_rounded,
                label: 'MCQ ${_selectedMcqs.length}টি · ${marks.mcq}',
              ),
              _SummaryChip(
                icon: Icons.short_text_rounded,
                label: 'RQ ${_selectedShorts.length}টি · ${marks.rq}',
              ),
            ],
          ),
        ],
      ),
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
            keyboardType: TextInputType.text,
            hintText: 'যেমন: ৫ অথবা নিজের নির্দেশনা',
            // The remark sits under the field, not in the label: the label
            // would otherwise be too long to float above the box.
            helperText: 'খালি রাখলে লেখা হবে না।'
                '${_selectedCqs.isEmpty ? '' : ' সর্বোচ্চ ${_selectedCqs.length}টি দেওয়া যাবে।'}',
          ),
        ],
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
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          const SizedBox(height: 4),
          const Text(
            'ধরে টেনে ক্রম বদলাও। প্রতিটি বিভাগ আলাদাভাবে এক বা দুই কলামে বসানো যায়। ছবি থাকলে ছোট কলামে ছবি ছোট দেখাবে।',
            style: TextStyle(fontSize: 11, color: _kSubText),
          ),
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

  Widget _buildTextField({
    required TextEditingController ctrl,
    required String label,
    IconData? icon,
    TextInputType? keyboardType,
    String? hintText,
    String? helperText,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      onChanged: onChanged,
      style: const TextStyle(color: _kDarkText, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        labelStyle: const TextStyle(fontSize: 13.5, color: _kSubText),
        floatingLabelStyle: const TextStyle(
            fontSize: 13, color: _kPrimary, fontWeight: FontWeight.w600),
        prefixIcon:
            icon == null ? null : Icon(icon, color: _kPrimary, size: 20),
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
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(steps.length * 2 - 1, (i) {
          if (i.isOdd) {
            final stepIndex = i ~/ 2;
            final filled = stepIndex < currentStep;
            return Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 1.5,
                color: filled ? _kPrimary : Colors.grey.shade200,
              ),
            );
          }
          final stepIndex = i ~/ 2;
          final active = stepIndex == currentStep;
          final done = stepIndex < currentStep;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done
                      ? _kAccent
                      : (active ? _kPrimary : Colors.grey.shade200),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: _kPrimary.withOpacity(0.35),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          )
                        ]
                      : null,
                ),
                child: Center(
                  child: done
                      ? const Icon(Icons.check_rounded,
                          size: 13, color: Colors.white)
                      : Text(
                          '${stepIndex + 1}',
                          style: TextStyle(
                            fontSize: 11,
                            color: active
                                ? Colors.white
                                : Colors.grey.shade500,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              // Show label only for the active step, right next to the circle.
              if (active) ...[
                const SizedBox(width: 5),
                Text(
                  steps[stepIndex],
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _kPrimary,
                  ),
                ),
              ],
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
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _kDarkText)),
          ),
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
              Icon(icon, size: 11, color: _kPrimary),
              const SizedBox(width: 4),
            ],
            Text(label,
                style: TextStyle(
                    fontSize: 11,
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
  final VoidCallback onSelect;
  final VoidCallback onExclude;
  final VoidCallback onAdd;

  const _ChapterGroupHeader({
    super.key,
    required this.chapterNumber,
    required this.chapterName,
    required this.total,
    required this.selected,
    required this.collapsed,
    required this.onToggle,
    required this.onSelect,
    required this.onExclude,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
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
          child: Column(
            children: [
              InkWell(
                onTap: onToggle,
                borderRadius: BorderRadius.circular(8),
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
                      message:
                          collapsed ? 'প্রশ্নগুলো দেখান' : 'প্রশ্নগুলো লুকান',
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
              const Divider(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _chapterAction(
                        Icons.done_all_rounded, 'Select', onSelect),
                  ),
                  Expanded(
                    child: _chapterAction(
                        Icons.remove_done_rounded, 'Exclude', onExclude),
                  ),
                  Expanded(
                    child:
                        _chapterAction(Icons.edit_note_rounded, 'Add', onAdd),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _chapterAction(IconData icon, String label, VoidCallback onPressed) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 15),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        minimumSize: const Size(0, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// The CQ / MCQ / RQ pill on a picker card.
class _TypeBadge extends StatelessWidget {
  final String type;
  final Color color;
  const _TypeBadge({required this.type, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.22)),
        ),
        child: Text(type,
            style: TextStyle(
                color: color,
                fontSize: 10.5,
                letterSpacing: .3,
                fontWeight: FontWeight.w800)),
      );
}

/// The mark a card carries, in a quiet little box beside the type pill.
class _MarksBadge extends StatelessWidget {
  final int marks;
  const _MarksBadge({required this.marks});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F4F8),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$marks',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: _kPrimary)),
            const SizedBox(width: 3),
            const Text('নম্বর',
                style: TextStyle(fontSize: 9.5, color: _kSubText)),
          ],
        ),
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

/// An independent image filter, so it can be combined with CQ/MCQ/RQ.
enum _ImageFilter {
  all('সব', 'ছবি: সব', _kPrimary),
  withImage('ছবিসহ', 'যেসব প্রশ্নে ছবি আছে', _kCqColor),
  withoutImage('ছবিহীন', 'যেসব প্রশ্নে ছবি নেই', _kSubText);

  const _ImageFilter(this.badge, this.title, this.color);

  final String badge;
  final String title;
  final Color color;

  bool matches(HighSchoolQuestion q) {
    final hasImage = q.stemImageUrl.trim().isNotEmpty;
    return switch (this) {
      _ImageFilter.all => true,
      _ImageFilter.withImage => hasImage,
      _ImageFilter.withoutImage => !hasImage,
    };
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
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
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
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: fg,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
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

/// A slim pill-shaped dropdown button used inline next to the search bar.
///
/// Shows only the short [displayText] for the selected item, keeping the
/// button narrow enough to sit alongside the search field. The open menu
/// uses [itemLabel] (full label + count) with a color dot so it remains as
/// informative as the old chip row.
class _CompactFilterDropdown<T> extends StatelessWidget {
  final T value;
  final List<T> items;
  final String Function(T) displayText;
  final String Function(T) itemLabel;
  final Color Function(T) itemColor;
  final ValueChanged<T?> onChanged;
  final IconData icon;

  const _CompactFilterDropdown({
    required this.value,
    required this.items,
    required this.displayText,
    required this.itemLabel,
    required this.itemColor,
    required this.onChanged,
    this.icon = Icons.filter_list_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final selectedColor = itemColor(value);
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: selectedColor.withOpacity(0.5), width: 1.2),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          isExpanded: false,
          menuWidth: 130,
          borderRadius: BorderRadius.circular(10),
          icon: Icon(Icons.expand_more_rounded,
              size: 14, color: selectedColor),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          selectedItemBuilder: (_) => items
              .map((item) => Center(
                    child: Text(
                      displayText(item),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: itemColor(item),
                      ),
                    ),
                  ))
              .toList(),
          items: items.map((item) {
            final c = itemColor(item);
            final isSelected = item == value;
            return DropdownMenuItem<T>(
              value: item,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration:
                        BoxDecoration(color: c, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      itemLabel(item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? c : Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

///
/// The paper used to hard-code one order, and a different one when CQ and the
/// short questions were merged, so there was no way to print the sections in
/// the order a particular exam wanted.
enum _SectionKind {
  cq('সৃজনশীল প্রশ্ন (CQ)', 'সৃজনশীল প্রশ্ন', 'সৃজনশীল (CQ)', _kCqColor),
  rq('সংক্ষিপ্ত প্রশ্ন (SQ)', 'সংক্ষিপ্ত প্রশ্ন', 'সংক্ষিপ্ত (SQ)', _kRqColor),
  mcq('বহুনির্বাচনী প্রশ্ন (MCQ)', 'বহুনির্বাচনী প্রশ্ন', 'বহুনির্বাচনী (MCQ)',
      _kMcqColor);

  const _SectionKind(this.title, this.shortName, this.compactTitle, this.color);

  /// The block's name as the printed banner spells it, minus the `ক-বিভাগ:`
  /// prefix. The letter comes from the block's *place* in the printed order, so
  /// it can only be added once the row knows where it sits.
  final String title;

  /// Compact name, for a row that has no questions to count.
  final String shortName;

  /// One-line name for the narrow settings rail, where the full title would
  /// wrap onto three lines and make every row needlessly tall.
  final String compactTitle;

  final Color color;

  bool get isCq => this == _SectionKind.cq;
  bool get isMcq => this == _SectionKind.mcq;
  bool get isRq => this == _SectionKind.rq;

  /// Stable prefix for the column pills' widget keys.
  String get toggleKey => switch (this) {
        _SectionKind.cq => 'CQ',
        _SectionKind.mcq => 'MCQ',
        _SectionKind.rq => 'সংক্ষিপ্ত',
      };
}

/// One block of the paper: where it prints, what it holds and how wide it runs.
///
/// On the desktop rail the row itself is the drag handle. In the phone settings
/// sheet drag gestures compete with the sheet's scroll, so the sheet asks for
/// explicit up/down buttons instead.
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
    this.compactToggle = true,
    this.toggleKeyPrefix,
    this.reorderable = true,
    this.onMoveUp,
    this.onMoveDown,
  });

  final _SectionKind kind;
  final int questionCount;
  final int marks;

  /// The বাংলা letter this block prints under, or empty when it holds nothing
  /// and is skipped on the page.
  final String letter;
  final int index;

  /// The section's column choice.
  final QuestionLayout layout;
  final ValueChanged<QuestionLayout> onLayout;

  /// Whether the column pills use the tighter desktop size.
  final bool compactToggle;

  /// Prefix for the column pills' keys, when the caller needs to find them.
  final String? toggleKeyPrefix;

  /// When false, the row shows [onMoveUp]/[onMoveDown] buttons rather than a
  /// drag handle, because it lives in a sheet that already scrolls.
  final bool reorderable;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    final empty = questionCount == 0;

    final content = Row(
      children: [
        if (reorderable)
          Icon(Icons.drag_indicator_rounded,
              size: 16, color: empty ? Colors.grey.shade400 : kind.color)
        else
          _moveButtons(empty),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                letter.isEmpty
                    ? kind.compactTitle
                    : '$letter-বিভাগ: ${kind.compactTitle}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11.5,
                    height: 1.15,
                    fontWeight: FontWeight.bold,
                    color: empty ? _kSubText : _kDarkText),
              ),
              Text(
                empty
                    ? 'কোনো ${kind.shortName} নেই'
                    : '$questionCount টি · $marks নম্বর',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 10.5, height: 1.2, color: _kSubText),
              ),
            ],
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        decoration: BoxDecoration(
          color: empty ? Colors.grey.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: empty ? Colors.grey.shade300 : kind.color.withOpacity(0.35),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
          child: Row(
            children: [
              Expanded(
                child: reorderable
                    ? ReorderableDragStartListener(
                        index: index,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.grab,
                          child: content,
                        ),
                      )
                    : content,
              ),
              const SizedBox(width: 6),
              _ColumnToggle(
                value: layout,
                onChanged: onLayout,
                compact: compactToggle,
                keyPrefix: toggleKeyPrefix,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Up/down buttons for the sheet, where a drag would fight its scroll.
  Widget _moveButtons(bool empty) {
    final color = empty ? Colors.grey.shade400 : kind.color;
    return SizedBox(
      width: 30,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _moveButton(
            keyName: 'move-up-${kind.name}',
            icon: Icons.keyboard_arrow_up_rounded,
            tooltip: 'উপরে সরান',
            onTap: onMoveUp,
            enabledColor: color,
          ),
          _moveButton(
            keyName: 'move-down-${kind.name}',
            icon: Icons.keyboard_arrow_down_rounded,
            tooltip: 'নিচে সরান',
            onTap: onMoveDown,
            enabledColor: color,
          ),
        ],
      ),
    );
  }

  Widget _moveButton({
    required String keyName,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
    required Color enabledColor,
  }) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: onTap != null,
        label: tooltip,
        child: InkWell(
          key: ValueKey(keyName),
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 30,
            height: 20,
            child: Icon(
              icon,
              size: 18,
              color: onTap == null ? Colors.grey.shade300 : enabledColor,
            ),
          ),
        ),
      ),
    );
  }
}

/// The one-, two- or three-column choice for a section, as glyph pills.
///
/// Each pill draws the same bars the paper itself is laid out with, so two bars
/// read as "two columns" without a word beside them. The chosen pill is tinted
/// and outlined in the app's primary colour; the rest sit on the sheet's soft
/// surface, which keeps the three choices visible without turning them into
/// three heavy buttons.
class _ColumnToggle extends StatelessWidget {
  const _ColumnToggle({
    required this.value,
    required this.onChanged,
    this.keyPrefix,
    this.compact = false,
  });

  final QuestionLayout value;
  final ValueChanged<QuestionLayout> onChanged;

  /// Prefix for the tap targets' keys, so the CQ and MCQ toggles can be told
  /// apart by tests and by the semantics tree.
  final String? keyPrefix;

  /// Draws the older, tighter pills. The desktop rail uses this so its section
  /// rows keep the height they had before the sheet was restyled.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < QuestionLayout.values.length; i++) ...[
          if (i > 0) SizedBox(width: compact ? 4 : 5),
          _pill(QuestionLayout.values[i]),
        ],
      ],
    );
  }

  Widget _pill(QuestionLayout layout) {
    final selected = layout == value;
    final columns = layout.mcqColumns;
    final radius = compact ? 8.0 : 10.0;
    return Tooltip(
      message: layout.label,
      child: Semantics(
        button: true,
        selected: selected,
        label: layout.label,
        child: InkWell(
          key: keyPrefix == null
              ? null
              : ValueKey('layout-$keyPrefix-${layout.name}'),
          onTap: () => onChanged(layout),
          borderRadius: BorderRadius.circular(radius),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            width: compact ? null : 42,
            height: compact ? null : 36,
            padding: compact
                ? const EdgeInsets.symmetric(horizontal: 6, vertical: 4)
                : null,
            decoration: BoxDecoration(
              color: selected
                  ? _kPrimary.withOpacity(0.10)
                  : (compact ? Colors.grey.shade100 : _kSheetSoft),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: selected
                    ? _kPrimary
                    : (compact ? Colors.transparent : _kSheetLine),
                width: selected ? (compact ? 1.5 : 1.6) : 1.2,
              ),
              boxShadow: selected && !compact
                  ? [
                      BoxShadow(
                        color: _kPrimary.withOpacity(0.10),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < columns; i++) ...[
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: compact ? 6 : 5,
                      height: compact ? 12 : 18,
                      margin: compact
                          ? const EdgeInsets.symmetric(horizontal: 1)
                          : null,
                      decoration: BoxDecoration(
                        color: selected
                            ? (compact
                                ? _kPrimary.withOpacity(0.55)
                                : _kPrimary)
                            : (compact
                                ? Colors.grey.shade400
                                : const Color(0xFFB8B2D6)),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    if (i != columns - 1 && !compact) const SizedBox(width: 3),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
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
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? _kPrimary : Colors.grey.shade300,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('অধ্যায় $chapterNumber',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: selected ? _kPrimary : _kSubText,
                  )),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: _kSubText.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text('$count',
                    style: const TextStyle(fontSize: 9.5, color: _kSubText)),
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
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.16),
            borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text('$label: $selected/$total',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700)),
          ],
        ),
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

/// The floating entry point to the mobile settings sheet.
///
/// A stock [FloatingActionButton.extended] cannot carry the sheet's gradient
/// and change dot, so this is a small hand-drawn pill that keeps the same
/// elevation and tap target.
class _MobileSettingsButton extends StatelessWidget {
  const _MobileSettingsButton({required this.onPressed, this.showDot = false});

  final VoidCallback onPressed;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_kPrimary, Color(0xFF7C5CFC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: _kPrimary.withOpacity(0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 13, 18, 13),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.tune_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'সেটিংস',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                if (showDot) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The desktop settings rail, compressed into a mobile bottom sheet and opened
/// from the floating "সেটিংস" button on narrow screens.
///
/// The sheet keeps its own build loop instead of leaning on the page: tapping a
/// control calls [_apply], which updates the page (the preview behind the sheet
/// repaints at once) *and* rebuilds the sheet so the chosen option lights up.
/// Reaching into the page's state is deliberate — the two live in one file and
/// the sheet is nothing but a mobile face for those very fields.
class _MobileSettingsSheet extends StatefulWidget {
  const _MobileSettingsSheet({required this.parent, this.onChanged});

  final _HighSchoolQPaperGeneratorPageState parent;
  final VoidCallback? onChanged;

  @override
  State<_MobileSettingsSheet> createState() => _MobileSettingsSheetState();
}

class _MobileSettingsSheetState extends State<_MobileSettingsSheet> {
  static const _ink = Color(0xFF1E1B3A);
  static const _muted = Color(0xFF6B6880);
  static const _line = Color(0xFFE9E6F7);
  static const _soft = _kSheetSoft;
  static const _softLine = _kSheetLine;

  _HighSchoolQPaperGeneratorPageState get page => widget.parent;

  void _apply(VoidCallback change) {
    page.setState(change);
    widget.onChanged?.call();
    setState(() {});
  }

  /// Runs a page action that already calls its own `setState`, then refreshes
  /// the sheet so a set split or shuffle is visible without closing it.
  void _runPageAction(VoidCallback action) {
    action();
    widget.onChanged?.call();
    setState(() {});
  }

  void _resetToDefaults() {
    _apply(() {
      page
        .._cqLayout = QuestionLayout.single
        .._mcqLayout = QuestionLayout.doubleColumn
        .._rqLayout = QuestionLayout.single
        .._paperSize = PaperSize.a4
        .._textAlign = PaperTextAlign.justify
        .._pageNumbers = false
        .._optionStyle = McqOptionStyle.parentheses
        .._columnDivider = true
        .._questionGap = 0
        .._columnGap = 15
        .._fontStep = 0
        .._paperFont = PaperFont.kalpurush
        .._showSchool = true
        .._showExam = true
        .._showSubject = true
        .._showClass = true
        .._showSet = true
        .._showInstructions = true
        .._showChapter = false
        .._showSubjectCode = false
        .._showStudentInfo = false
        .._showObtainedMarks = false
        .._showQuestionInfo = false
        .._showImportant = false
        .._showLogo = false
        .._showHeader = false
        .._showFooter = false
        .._showWatermark = false
        .._showAddress = false
        .._twoSets = false
        .._editingMode = false
        .._imageSize = StemImageSize.small
        .._mcqAnswerSheetStyle = McqAnswerSheetStyle.none
        .._detectRepeated = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return Container(
      height: height * 0.92,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: _kBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Column(
        children: [
          const SizedBox(
            height: 10,
            child: Center(
              child: SizedBox(
                width: 42,
                height: 4.5,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0xFFD6D2EC),
                    borderRadius: BorderRadius.all(Radius.circular(3)),
                  ),
                ),
              ),
            ),
          ),
          _header(),
          Expanded(
            child: ListView(
              key: const ValueKey('mobile-settings-list'),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              children: [
                _summaryStrip(),
                _sectionsCard(),
                _pageCard(),
                _typographyCard(),
                _optionCard(),
                _headerCard(),
                _brandingCard(),
                _extrasCard(),
                _mediaCard(),
                _setsCard(),
                _toolsCard(),
              ],
            ),
          ),
          _footer(context),
        ],
      ),
    );
  }

  // ── Chrome ────────────────────────────────────────────────────────────────

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 10, 12),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_kPrimary, Color(0xFF8B6BFF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: _kPrimary.withOpacity(0.30),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child:
                const Icon(Icons.tune_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'প্রশ্নপত্র সেটিংস',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'পরিবর্তন সাথে সাথেই প্রিভিউতে দেখা যাবে',
                  style: TextStyle(fontSize: 11.5, color: _muted),
                ),
              ],
            ),
          ),
          _circleButton(Icons.close_rounded, () => Navigator.of(context).pop()),
        ],
      ),
    );
  }

  Widget _circleButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(side: BorderSide(color: _line)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, size: 20, color: _muted),
        ),
      ),
    );
  }

  Widget _footer(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.paddingOf(context).bottom + 12,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEDEAF9))),
        boxShadow: [
          BoxShadow(
            color: Color(0x0F1E1B3A),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          OutlinedButton.icon(
            onPressed: _resetToDefaults,
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: const Text('রিসেট'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _muted,
              side: const BorderSide(color: Color(0xFFDCD8EF)),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              minimumSize: const Size(0, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_kPrimary, Color(0xFF7C5CFC)],
                ),
                borderRadius: BorderRadius.circular(13),
                boxShadow: [
                  BoxShadow(
                    color: _kPrimary.withOpacity(0.30),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: BorderRadius.circular(13),
                  onTap: () => Navigator.of(context).pop(),
                  child: const SizedBox(
                    height: 48,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'সেভ করুন',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section shell ─────────────────────────────────────────────────────────

  Widget _card({
    required IconData icon,
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A1E1B3A),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 11),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: _kPrimary.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 17, color: _kPrimary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 1),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: _muted,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFF1EFFA)),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: _muted,
        letterSpacing: 0.2,
      ),
    );
  }

  Widget _hair() =>
      const Divider(height: 14, thickness: 1, color: Color(0xFFF3F1FB));

  /// One-line text field for the sheet's branding inputs.
  ///
  /// The desktop rail uses the page's own field builder; this one is tuned to
  /// the sheet's tighter cards and softer surface.
  Widget _textField({
    required TextEditingController controller,
    required String label,
    required String hint,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 13, color: _ink),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(fontSize: 12, color: _muted),
        floatingLabelStyle: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: _kPrimary,
        ),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        filled: true,
        fillColor: _soft,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _softLine),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kPrimary, width: 1.4),
        ),
      ),
    );
  }

  // ── Sections ──────────────────────────────────────────────────────────────

  /// A live one-line digest of the three choices that show up first on paper:
  /// the stock, the MCQ column count and the face. It updates with the cards
  /// below, giving the sheet a dashboard feel instead of a bare form.
  Widget _summaryStrip() {
    final face = page._paperFont.label.split(' (').first;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _kPrimary.withOpacity(0.10),
            _kPrimary.withOpacity(0.035),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kPrimary.withOpacity(0.16)),
      ),
      child: Row(
        children: [
          _summaryItem(Icons.description_rounded, page._paperSize.label),
          _summaryRule(),
          _summaryItem(
            Icons.view_column_rounded,
            '${page._mcqLayout.mcqColumns} কলাম',
          ),
          _summaryRule(),
          _summaryItem(Icons.text_fields_rounded, face),
        ],
      ),
    );
  }

  Widget _summaryItem(IconData icon, String text) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: _kPrimary),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _kPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRule() {
    return Container(
      width: 1,
      height: 16,
      color: _kPrimary.withOpacity(0.16),
    );
  }

  /// The sections' order and column counts in one card.
  ///
  /// The phone's arrange page used to carry this list; moving it here keeps the
  /// wizard focused on the paper's text and gives the reader one place to tune
  /// how the paper is printed.
  Widget _sectionsCard() {
    return _card(
      icon: Icons.reorder_rounded,
      title: 'বিভাগ ও ক্রম',
      subtitle: 'উপর-নিচে সরিয়ে ক্রম বদলাও, পাশে কলাম বেছে নাও',
      children: [
        for (var index = 0; index < page._sectionOrder.length; index++)
          _sectionRow(index),
        const SizedBox(height: 4),
        const Text(
          'প্রতিটি বিভাগের কলাম আলাদাভাবে বদলানো যায়।',
          style: TextStyle(fontSize: 10.5, height: 1.3, color: _muted),
        ),
      ],
    );
  }

  Widget _sectionRow(int index) {
    final kind = page._sectionOrder[index];
    final count = page._questionsOf(kind).length;
    return _SectionCardRow(
      key: ValueKey(kind),
      kind: kind,
      index: index,
      questionCount: count,
      marks: page._marksOf(kind),
      letter: count == 0 ? '' : page._sectionLetter(kind),
      layout: page._layoutOf(kind),
      onLayout: (v) => _apply(() => page._setLayoutOf(kind, v)),
      compactToggle: false,
      toggleKeyPrefix: kind.toggleKey,
      reorderable: false,
      onMoveUp: index == 0 ? null : () => _moveSection(index, index - 1),
      onMoveDown: index == page._sectionOrder.length - 1
          ? null
          : () => _moveSection(index, index + 1),
    );
  }

  void _moveSection(int from, int to) {
    _apply(() {
      page._sectionOrder.insert(to, page._sectionOrder.removeAt(from));
    });
  }

  Widget _pageCard() {
    return _card(
      icon: Icons.description_rounded,
      title: 'পেজ সেটআপ',
      subtitle: 'কাগজের আকার ও লেখার বিন্যাস',
      children: [
        _fieldLabel('পেজ সাইজ'),
        const SizedBox(height: 7),
        _segmented<PaperSize>(
          values: PaperSize.values,
          value: page._paperSize,
          label: (s) => s.label,
          onChanged: (v) => _apply(() => page._paperSize = v),
        ),
        const SizedBox(height: 14),
        _fieldLabel('টেক্সট এলাইনমেন্ট'),
        const SizedBox(height: 7),
        _segmented<PaperTextAlign>(
          values: PaperTextAlign.values,
          value: page._textAlign,
          label: (s) => s.label,
          onChanged: (v) => _apply(() => page._textAlign = v),
        ),
        _hair(),
        _toggleRow(
          'পৃষ্ঠা নম্বর',
          'প্রতিটি পাতার নিচে নম্বর বসবে',
          page._pageNumbers,
          (v) => _apply(() => page._pageNumbers = v),
          icon: Icons.numbers_rounded,
        ),
      ],
    );
  }

  Widget _typographyCard() {
    return _card(
      icon: Icons.text_fields_rounded,
      title: 'টাইপোগ্রাফি ও ফাঁক',
      subtitle: 'ফন্ট, আকার এবং কলামের দূরত্ব',
      children: [
        _fieldLabel('ফন্ট'),
        const SizedBox(height: 7),
        _fontDropdown(),
        const SizedBox(height: 14),
        _fieldLabel('ফন্ট সাইজ'),
        const SizedBox(height: 7),
        _fontSizeRow(),
        _hair(),
        _sliderRow(
          'প্রশ্নের নিচের গ্যাপ',
          page._questionGap,
          0,
          24,
          (v) => _apply(() => page._questionGap = v),
        ),
        _sliderRow(
          'কলামের গ্যাপ',
          page._columnGap,
          0,
          40,
          (v) => _apply(() => page._columnGap = v),
        ),
        _toggleRow(
          'কলাম ডিভাইডার',
          'কলামের মাঝে সরু দাগ থাকবে',
          page._columnDivider,
          (v) => _apply(() => page._columnDivider = v),
          icon: Icons.vertical_split_rounded,
        ),
      ],
    );
  }

  Widget _optionCard() {
    return _card(
      icon: Icons.format_list_bulleted_rounded,
      title: 'MCQ অপশন স্টাইল',
      subtitle: 'উত্তরগুলোর চিহ্ন কীভাবে ছাপা হবে',
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final style in McqOptionStyle.values)
              _selectChip(
                item: style,
                value: page._optionStyle,
                label: style.prefix('ক'),
                onChanged: (v) => _apply(() => page._optionStyle = v),
              ),
          ],
        ),
      ],
    );
  }

  Widget _headerCard() {
    return _card(
      icon: Icons.web_rounded,
      title: 'হেডার তথ্য',
      subtitle: 'প্রশ্নপত্রের উপরে কোন তথ্য থাকবে',
      children: [
        _toggleRow('প্রতিষ্ঠানের নাম', null, page._showSchool,
            (v) => _apply(() => page._showSchool = v)),
        _toggleRow('শ্রেণির নাম', null, page._showClass,
            (v) => _apply(() => page._showClass = v)),
        _toggleRow('বিষয়ের নাম', null, page._showSubject,
            (v) => _apply(() => page._showSubject = v)),
        _toggleRow('অধ্যায়ের নাম', null, page._showChapter,
            (v) => _apply(() => page._showChapter = v)),
        _toggleRow('সেট কোড', null, page._showSet,
            (v) => _apply(() => page._showSet = v)),
        _toggleRow('প্রোগ্রাম / পরীক্ষার নাম', null, page._showExam,
            (v) => _apply(() => page._showExam = v)),
        _toggleRow('নির্দেশনা', null, page._showInstructions,
            (v) => _apply(() => page._showInstructions = v)),
      ],
    );
  }

  Widget _brandingCard() {
    return _card(
      icon: Icons.workspace_premium_rounded,
      title: 'ব্র্যান্ডিং',
      subtitle: 'লোগো, হেডার, ফুটার, জলছাপ ও ঠিকানা',
      children: [
        _toggleRow(
          'লোগো',
          'প্রতিষ্ঠানের লোগো ছাপা হবে',
          page._showLogo,
          (v) => _apply(() => page._showLogo = v),
          switchKey: const ValueKey('branding-logo-switch'),
        ),
        if (page._showLogo) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await page._pickLogo();
                    if (mounted) setState(() {});
                  },
                  icon: const Icon(Icons.upload_file_rounded, size: 16),
                  label: Text(
                    page._logoName.isEmpty ? 'লোগো নির্বাচন' : page._logoName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              if (page._logoDataUri.isNotEmpty)
                IconButton(
                  tooltip: 'লোগো সরান',
                  onPressed: () => _apply(() {
                    page._logoDataUri = '';
                    page._logoName = '';
                  }),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
            ],
          ),
          const SizedBox(height: 2),
        ],
        _toggleRow(
          'হেডার',
          'উপরের ব্র্যান্ডিং পটি',
          page._showHeader,
          (v) => _apply(() => page._showHeader = v),
          switchKey: const ValueKey('branding-header-switch'),
        ),
        _toggleRow(
          'ফুটার',
          'নিচের ব্র্যান্ডিং পটি',
          page._showFooter,
          (v) => _apply(() => page._showFooter = v),
          switchKey: const ValueKey('branding-footer-switch'),
        ),
        _toggleRow(
          'জলছাপ',
          'পাতার মাঝে হালকা লেখা',
          page._showWatermark,
          (v) => _apply(() => page._showWatermark = v),
          switchKey: const ValueKey('branding-watermark-switch'),
        ),
        if (page._showWatermark) ...[
          const SizedBox(height: 6),
          _textField(
            controller: page._watermarkCtrl,
            label: 'জলছাপের লেখা',
            hint: 'যেমন: নমুনা',
            onChanged: (_) => _apply(() {}),
          ),
        ],
        _toggleRow(
          'ঠিকানা',
          'প্রতিষ্ঠানের ঠিকানা ছাপা হবে',
          page._showAddress,
          (v) => _apply(() => page._showAddress = v),
          switchKey: const ValueKey('branding-address-switch'),
        ),
        if (page._showAddress) ...[
          const SizedBox(height: 6),
          _textField(
            controller: page._addressCtrl,
            label: 'প্রতিষ্ঠানের ঠিকানা',
            hint: 'গ্রাম/শহর, উপজেলা',
            onChanged: (_) => _apply(() {}),
          ),
        ],
      ],
    );
  }

  Widget _extrasCard() {
    return _card(
      icon: Icons.sell_rounded,
      title: 'প্রশ্নের সংযুক্তি',
      subtitle: 'প্রতিটি প্রশ্নের সাথে অতিরিক্ত তথ্য',
      children: [
        _toggleRow('গুরুত্বপূর্ণ প্রশ্ন', 'তাৎপর্যপূর্ণ প্রশ্ন চিহ্নিত হবে',
            page._showImportant, (v) => _apply(() => page._showImportant = v)),
        _toggleRow('প্রশ্নের তথ্য', null, page._showQuestionInfo,
            (v) => _apply(() => page._showQuestionInfo = v)),
        _toggleRow('শিক্ষার্থীর তথ্য', null, page._showStudentInfo,
            (v) => _apply(() => page._showStudentInfo = v)),
        _toggleRow('বিষয় কোড', null, page._showSubjectCode,
            (v) => _apply(() => page._showSubjectCode = v)),
        _toggleRow('প্রাপ্ত নম্বর ঘর', null, page._showObtainedMarks,
            (v) => _apply(() => page._showObtainedMarks = v)),
      ],
    );
  }

  Widget _mediaCard() {
    return _card(
      icon: Icons.image_rounded,
      title: 'ছবি ও উত্তরপত্র',
      subtitle: 'প্রশ্নের ছবি এবং MCQ উত্তরপত্রের ধরন',
      children: [
        _fieldLabel('প্রশ্নের ছবির আকার'),
        const SizedBox(height: 7),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final size in StemImageSize.values)
              _selectChip(
                item: size,
                value: page._imageSize,
                label: size == StemImageSize.hidden ? 'বন্ধ' : size.label,
                onChanged: (v) => _apply(() => page._imageSize = v),
              ),
          ],
        ),
        const SizedBox(height: 14),
        _fieldLabel('MCQ উত্তরপত্র'),
        const SizedBox(height: 7),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final style in McqAnswerSheetStyle.values)
              _selectChip(
                item: style,
                value: page._mcqAnswerSheetStyle,
                label: style.label,
                onChanged: (v) => _apply(() => page._mcqAnswerSheetStyle = v),
              ),
          ],
        ),
      ],
    );
  }

  Widget _setsCard() {
    return _card(
      icon: Icons.copy_all_rounded,
      title: 'সেট',
      subtitle: 'একই প্রশ্নপত্রের ক ও খ সংস্করণ',
      children: [
        _toggleRow(
          'দুইটি সেটে প্রশ্নপত্র',
          'ক ও খ একই পেজে তৈরি হবে',
          page._twoSets,
          (v) => _apply(() => page._twoSets = v),
          switchKey: const ValueKey('two-sets-switch'),
        ),
        const SizedBox(height: 2),
        const Text(
          'ক ও খ একই পেজে তৈরি হবে — আলাদা করে তৈরি করলে প্রতিটির একটা পেজ নষ্ট হয়।',
          style: TextStyle(fontSize: 10.5, height: 1.35, color: _muted),
        ),
        if (page._twoSets) ...[
          const SizedBox(height: 10),
          _textField(
            controller: page._setLabelControllers[0],
            label: 'প্রথম সেটের নাম',
            hint: 'ক',
            onChanged: (_) => _apply(() {}),
          ),
          const SizedBox(height: 8),
          _textField(
            controller: page._setLabelControllers[1],
            label: 'দ্বিতীয় সেটের নাম',
            hint: 'খ',
            onChanged: (_) => _apply(() {}),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: page._selectedQuestions.length < 2
                ? null
                : () => _runPageAction(page._shuffleIntoTwoSets),
            icon: const Icon(Icons.shuffle_rounded, size: 16),
            label:
                const Text('এলোমেলো ভাগ করো', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: page._selectedQuestions.length < 2
                ? null
                : () => _runPageAction(page._splitSelectedEvenly),
            icon: const Icon(Icons.balance, size: 16),
            label: Text('অর্ধেক ভাগ করো (${page._selectedQuestions.length} টি)',
                style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: () => _runPageAction(page._assignAllToFirstSet),
            icon: const Icon(Icons.merge_type, size: 16),
            label: const Text('সব প্রশ্ন প্রথম সেটে',
                style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < 2; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
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
                      page._setLabels[i].isEmpty
                          ? (i == 0 ? 'ক' : 'খ')
                          : page._setLabels[i],
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: i == 0 ? _kPrimary : Colors.teal.shade700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${page._questionsForSet(i).length} টি প্রশ্ন'
                      '  ·  ${page._questionsForSet(i).fold(0, (s, q) => s + q.totalMarks)} নম্বর',
                      style: const TextStyle(fontSize: 11, color: _muted),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 2),
          const Text(
            'প্রতিটি প্রশ্নের কার্ডে সেট বদলাতে পারেন।',
            style: TextStyle(fontSize: 10.5, height: 1.35, color: _muted),
          ),
        ],
      ],
    );
  }

  Widget _toolsCard() {
    return _card(
      icon: Icons.tune_rounded,
      title: 'সহায়ক টুলস',
      subtitle: 'এডিটিং ও পুনরাবৃত্তি শনাক্তকরণ',
      children: [
        _toggleRow(
          'এডিটিং মোড',
          'প্রিভিউতে সরাসরি সম্পাদনা করা যাবে',
          page._editingMode,
          (v) => _apply(() => page._editingMode = v),
          icon: Icons.edit_rounded,
        ),
        _toggleRow(
          'পুনরাবৃত্ত প্রশ্ন শনাক্ত',
          'একই প্রশ্ন দুবার থাকলে দেখাবে',
          page._detectRepeated,
          (v) => _apply(() => page._detectRepeated = v),
          icon: Icons.content_copy_rounded,
        ),
      ],
    );
  }

  // ── Controls ──────────────────────────────────────────────────────────────

  Widget _segmented<T>({
    required List<T> values,
    required T value,
    required String Function(T) label,
    required ValueChanged<T> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F1FB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final item in values)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(item),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  decoration: BoxDecoration(
                    color: item == value ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: item == value
                        ? const [
                            BoxShadow(
                              color: Color(0x141E1B3A),
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label(item),
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight:
                            item == value ? FontWeight.w800 : FontWeight.w500,
                        color: item == value ? _kPrimary : _muted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _selectChip<T>({
    required T item,
    required T value,
    required String label,
    required ValueChanged<T> onChanged,
  }) {
    final selected = item == value;
    return GestureDetector(
      onTap: () => onChanged(item),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? _kPrimary.withOpacity(0.10) : _soft,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? _kPrimary : _softLine,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: selected ? _kPrimary : _muted,
          ),
        ),
      ),
    );
  }

  Widget _fontDropdown() {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _soft,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: _softLine),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<PaperFont>(
          value: page._paperFont,
          isExpanded: true,
          borderRadius: BorderRadius.circular(12),
          icon: const Icon(Icons.expand_more_rounded, color: _muted),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _ink,
          ),
          items: [
            for (final font in PaperFont.values)
              DropdownMenuItem(
                value: font,
                child: Text(font.label, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) {
            if (v != null) _apply(() => page._paperFont = v);
          },
        ),
      ),
    );
  }

  Widget _fontSizeRow() {
    final size = (14 + page._fontStep).clamp(10, 26).toDouble();
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _soft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _softLine),
      ),
      child: Row(
        children: [
          _stepButton(
            Icons.remove_rounded,
            page._fontStep > _HighSchoolQPaperGeneratorPageState._fontStepMin
                ? () => _apply(() => page._fontStep -= 1)
                : null,
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  'আ',
                  style: TextStyle(
                    fontSize: size,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${(14 + page._fontStep).round()} px',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _kPrimary,
                  ),
                ),
              ],
            ),
          ),
          _stepButton(
            Icons.add_rounded,
            page._fontStep < _HighSchoolQPaperGeneratorPageState._fontStepMax
                ? () => _apply(() => page._fontStep += 1)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _stepButton(IconData icon, VoidCallback? onTap) {
    final disabled = onTap == null;
    return Material(
      color: disabled ? const Color(0xFFEDEBF7) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: _softLine),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(
            icon,
            size: 20,
            color: disabled ? const Color(0xFFB8B2D6) : _kPrimary,
          ),
        ),
      ),
    );
  }

  Widget _sliderRow(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _ink,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: _kPrimary.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${value.round()}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: _kPrimary,
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: _kPrimary,
              inactiveTrackColor: const Color(0xFFE3E0F2),
              thumbColor: _kPrimary,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: (max - min).round(),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleRow(
    String label,
    String? subtitle,
    bool value,
    ValueChanged<bool> onChanged, {
    IconData? icon,
    Key? switchKey,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 17, color: _muted),
            const SizedBox(width: 9),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: _ink,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: _muted,
                      height: 1.25,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Transform.scale(
            scale: 0.85,
            child: Switch.adaptive(
              key: switchKey,
              value: value,
              onChanged: onChanged,
              activeColor: _kPrimary,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}
