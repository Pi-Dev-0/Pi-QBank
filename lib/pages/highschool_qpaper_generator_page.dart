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

const _kPrimary = Color(0xFF5C35E3); // vibrant indigo-violet
const _kAccent = Color(0xFF00C6AB); // teal-mint accent
const _kCqColor = Color(0xFF3A7BF7); // blue for CQ
const _kMcqColor = Color(0xFFE86339); // warm orange for MCQ
const _kRqColor = Color(0xFF0E9F6E); // green for short questions (RQ)
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
  ],
};

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
    super.dispose();
  }

  // ── Derived counters ──────────────────────────────────────────────────────

  List<HighSchoolQuestion> get _selectedQuestions =>
      _fetchedQuestions.where((q) => q.isSelected).toList();

  List<HighSchoolQuestion> get _selectedCqs =>
      _selectedQuestions.where((q) => q.isCq).toList();

  List<HighSchoolQuestion> get _selectedMcqs =>
      _selectedQuestions.where((q) => q.isMcq).toList();

  List<HighSchoolQuestion> get _selectedShorts =>
      _selectedQuestions.where((q) => q.isShort).toList();

  int get _totalCqs => _fetchedQuestions.where((q) => q.isCq).length;
  int get _totalMcqs => _fetchedQuestions.where((q) => q.isMcq).length;
  int get _totalShorts => _fetchedQuestions.where((q) => q.isShort).length;

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
      setState(() => _availableChapters = chapters);
    } catch (e) {
      _showError('অধ্যায় লোড করতে ব্যর্থ: ${e.toString()}');
    } finally {
      setState(() => _loadingChapters = false);
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
        return;
      }
      setState(() {
        _fetchedQuestions = questions;
        _expandedCards.clear();
      });
      await _goToStep(1);
    } catch (e) {
      _showError('প্রশ্ন লোড করতে ব্যর্থ: ${e.toString()}');
    } finally {
      setState(() => _loadingQuestions = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Step 2 logic
  // ─────────────────────────────────────────────────────────────────────────

  void _toggleQuestion(HighSchoolQuestion q) {
    setState(() => q.isSelected = !q.isSelected);
  }

  void _selectAll() => setState(() {
        for (final q in _fetchedQuestions) {
          q.isSelected = true;
        }
      });
  void _deselectAll() => setState(() {
        for (final q in _fetchedQuestions) {
          q.isSelected = false;
        }
      });

  void _proceedToGenerate() {
    if (_selectedQuestions.isEmpty) {
      _showError('অন্তত একটি প্রশ্ন নির্বাচন করুন।');
      return;
    }
    _subjectCtrl.text = _selectedSubject ?? '';
    _classCtrl.text = _selectedClass ?? '';
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
        cqLayout: _cqLayout,
        mcqLayout: _mcqLayout,
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
        imageSize: _imageSize,
        cqLayout: _cqLayout,
        mcqLayout: _mcqLayout,
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
          imageSize: _imageSize,
          cqLayout: _cqLayout,
          mcqLayout: _mcqLayout,
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
      imageSize: _imageSize,
      cqLayout: _cqLayout,
      mcqLayout: _mcqLayout,
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
    );
    HighSchoolExportService.copyToClipboard(context, text);
  }

  /// Render a string that mixes Bangla and Latin in the PDF.
  ///
  /// See [buildPdfTextSpan] for why this is needed and for the copyWith/font-slot
  /// trap it works around.
  pw.TextSpan _mixedText(String text, pw.TextStyle style) {
    final bold = style.fontWeight == pw.FontWeight.bold;
    return buildPdfTextSpan(text, style, bold: bold);
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


  Future<Uint8List> _buildPdf() async {
    final doc = pw.Document();
    final cqs = _selectedCqs;
    final mcqs = _selectedMcqs;
    final shorts = _selectedShorts;

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

    final baseStyle = pw.TextStyle(
      font: banglaFont,
      fontFallback: fallback,
      fontSize: 11,
      color: PdfColors.black,
    );
    final boldStyle = pw.TextStyle(
      font: banglaFont,
      fontFallback: fallback,
      fontSize: 11,
      fontWeight: pw.FontWeight.bold,
    );
    final headerStyle = pw.TextStyle(
      font: banglaFont,
      fontFallback: fallback,
      fontSize: 14,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.black,
    );
    final smallStyle = pw.TextStyle(
      font: banglaFont,
      fontFallback: fallback,
      fontSize: 9,
      color: PdfColors.grey700,
    );

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 36),
      build: (ctx) {
        final widgets = <pw.Widget>[];

        // Replays the page fill so each block of columns is sized to the space
        // actually left. Without this the CQ block is budgeted for a whole page,
        // never fits under the masthead, and jumps to page 2 — leaving page 1
        // almost blank. See PdfPageFlow.
        final flow = PdfPageFlow(contentHeight: PdfLayout.contentHeight);
        final bannerHeight = PdfLayout.sectionBannerHeight(metrics);

        // ── Header ─────────────────────────────────────────────────────────
        widgets.add(_buildPdfHeader(
          schoolName: _schoolCtrl.text,
          examName: _examCtrl.text,
          subject: _subjectCtrl.text,
          className: _classCtrl.text,
          time: _timeCtrl.text,
          totalMarks: _marksCtrl.text,
          baseStyle: baseStyle,
          boldStyle: boldStyle,
          headerStyle: headerStyle,
          smallStyle: smallStyle,
        ));

        widgets.add(pw.SizedBox(height: 16));
        flow.consume(PdfLayout.headerHeight(
          metrics: metrics,
          schoolName: _schoolCtrl.text,
          examName: _examCtrl.text,
          subject: _subjectCtrl.text,
          className: _classCtrl.text,
          time: _timeCtrl.text,
          totalMarks: _marksCtrl.text,
        ) +
            16);

        // ── CQ Section ─────────────────────────────────────────────────────
        if (cqs.isNotEmpty) {
          widgets.add(_pdfSectionBanner(
              'ক-বিভাগ: সৃজনশীল প্রশ্ন (CQ)', boldStyle.copyWith(fontSize: 11)));
          // Optional "answer any N questions" note.
          final answerAny = _cqAnswerCount;
          if (answerAny > 0) {
            widgets.add(pw.SizedBox(height: 4));
            widgets.add(pw.RichText(
              text: _mixedText(
                  '[যেকোনো $answerAny টি প্রশ্নের উত্তর দাও]',
                  smallStyle.copyWith(fontStyle: pw.FontStyle.italic)),
              textAlign: pw.TextAlign.center,
            ));
            flow.consume(4 +
                metrics.lineHeight('[যেকোনো $answerAny টি প্রশ্নের উত্তর দাও]',
                    fontSize: PdfLayout.smallFontSize));
          }
          widgets.add(pw.SizedBox(height: 10));
          flow.consume(bannerHeight + 10);

          // Balanced newspaper columns rather than rows of two, so a short
          // question no longer inherits the full height of the tallest
          // question beside it. See [balanceColumns].
          final cqCols = _cqLayout.mcqColumns;
          final cqWidth = PdfLayout.columnWidth(cqCols);
          final cqRows = flow.layout(
            heights: [
              for (int i = 0; i < cqs.length; i++)
                // The gap is counted per card because the builder emits one
                // after every card, including the last in a column.
                PdfLayout.cqHeight(
                  index: i + 1,
                  question: cqs[i],
                  columnWidth: cqWidth,
                  metrics: metrics,
                  hasImage: stemImages.containsKey(
                      HighSchoolExportService.resolveImageUrl(
                          cqs[i].stemImageUrl)),
                  imageSize: _imageSize,
                ) +
                    PdfLayout.cqCardGap,
            ],
            columns: cqCols,
            trailingGap: 16,
          );

          // One unbreakable row of columns per page's worth of questions, so a long
          // section still flows instead of overflowing a single block.
          for (final row in cqRows) {
            final columns = <List<pw.Widget>>[];
            for (final group in row) {
              final column = <pw.Widget>[];
              for (final qIndex in group) {
                column.add(_buildPdfCqCard(
                  index: qIndex + 1,
                  question: cqs[qIndex],
                  baseStyle: baseStyle,
                  boldStyle: boldStyle,
                  smallStyle: smallStyle,
                  stemImages: stemImages,
                  imageSize: _imageSize,
                ));
                column.add(pw.SizedBox(height: PdfLayout.cqCardGap));
              }
              columns.add(column);
            }
            widgets.add(_pdfColumnRow(columns));
            widgets.add(pw.SizedBox(height: 16));
          }
        }

        // ── MCQ Section ────────────────────────────────────────────────────
        if (mcqs.isNotEmpty) {
          widgets.add(pw.SizedBox(height: 16));
          widgets.add(_pdfSectionBanner(
              'খ-বিভাগ: বহুনির্বাচনী প্রশ্ন (MCQ)',
              boldStyle.copyWith(fontSize: 11)));
          widgets.add(pw.SizedBox(height: 4));
          widgets.add(pw.RichText(
              text: _mixedText('[সঠিক উত্তরের পাশে টিক (✓) চিহ্ন দাও]',
                  smallStyle.copyWith(fontStyle: pw.FontStyle.italic)),
              textAlign: pw.TextAlign.center));
          widgets.add(pw.SizedBox(height: 10));
          flow.consume(16 +
              bannerHeight +
              4 +
              metrics.lineHeight('[সঠিক উত্তরের পাশে টিক (✓) চিহ্ন দাও]',
                  fontSize: PdfLayout.smallFontSize) +
              10);

          // MCQ arranged in balanced columns per the layout setting.
          final cols = _mcqLayout.mcqColumns;
          final stackOptions = cols > 1;
          final mcqWidth = PdfLayout.columnWidth(cols);
          final mcqRows = flow.layout(
            heights: [
              for (int i = 0; i < mcqs.length; i++)
                PdfLayout.mcqHeight(
                  index: i + 1,
                  question: mcqs[i],
                  columnWidth: mcqWidth,
                  metrics: metrics,
                  stackOptions: stackOptions,
                ),
            ],
            columns: cols,
            trailingGap: 12,
          );

          for (final row in mcqRows) {
            final columns = <List<pw.Widget>>[];
            for (final group in row) {
              final column = <pw.Widget>[];
              for (var k = 0; k < group.length; k++) {
                column.add(_buildPdfMcqItem(group[k] + 1, mcqs[group[k]],
                    baseStyle,
                    stackOptions: stackOptions));
                // The rule belongs *between* questions, so a column that ends
                // on a question is not left with a trailing divider.
                if (k < group.length - 1) {
                  column.add(pw.SizedBox(height: 6));
                  column.add(_pdfDashedLine());
                  column.add(pw.SizedBox(height: 6));
                }
              }
              columns.add(column);
            }
            widgets.add(_pdfColumnRow(columns));
            widgets.add(pw.SizedBox(height: 12));
          }
        }

        // ── Short question section (গ-বিভাগ) ───────────────────────────────
        if (shorts.isNotEmpty) {
          widgets.add(pw.SizedBox(height: 16));
          widgets.add(_pdfSectionBanner(
              'গ-বিভাগ: সংক্ষিপ্ত প্রশ্ন (RQ)', boldStyle.copyWith(fontSize: 11)));
          widgets.add(pw.SizedBox(height: 10));

          for (int i = 0; i < shorts.length; i++) {
            final data = shorts[i].shortData;
            if (data == null || data.text.trim().isEmpty) continue;
            widgets.add(pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.RichText(
                        text: _mixedText('${i + 1}. ${data.text}', baseStyle)),
                  ),
                  pw.SizedBox(width: 12),
                  pw.RichText(
                      text: _mixedText('[${data.mark}]', boldStyle)),
                ],
              ),
            ));
          }
        }

        widgets.add(pw.SizedBox(height: 12));
        widgets.add(pw.Divider(thickness: 0.8, color: PdfColors.grey300));
        widgets.add(pw.SizedBox(height: 6));
        widgets.add(pw.RichText(
          text: _mixedText('জেনারেট করা হয়েছে Pi-QBank প্ল্যাটফর্ম থেকে',
              smallStyle),
          textAlign: pw.TextAlign.center,
        ));

        return widgets;
      },
    ));

    return doc.save();
  }

  /// A dashed horizontal rule, matching the HTML export's dashed separators.
  pw.Widget _pdfDashedLine({PdfColor color = PdfColors.grey400}) {
    return pw.LayoutBuilder(builder: (ctx, constraints) {
      // LayoutBuilder hands back BoxConstraints (null outside a layout pass).
      final width = constraints?.maxWidth;
      const dash = 4.0;
      const gap = 3.0;
      final available =
          (width == null || width.isInfinite) ? 400.0 : width;
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
              text: _mixedText(schoolName, headerStyle.copyWith(fontSize: 15))),
        pw.SizedBox(height: 2),
        pw.RichText(
            text: _mixedText(examName, boldStyle.copyWith(fontSize: 12))),
        pw.SizedBox(height: 8),
        pw.Divider(thickness: 1.2, color: PdfColors.black),
        pw.SizedBox(height: 6),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.RichText(text: _mixedText('বিষয়: $subject', boldStyle)),
            pw.RichText(text: _mixedText('শ্রেণি: $className', boldStyle)),
            pw.RichText(text: _mixedText('সময়: $time', boldStyle)),
            pw.RichText(text: _mixedText('পূর্ণমান: $totalMarks', boldStyle)),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Divider(thickness: 1.2, color: PdfColors.black),
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
      Map<String, Uint8List> stemImages = const {},
      StemImageSize imageSize = StemImageSize.medium}) {
    final stemBytes = imageSize.isVisible
        ? stemImages[
            HighSchoolExportService.resolveImageUrl(question.stemImageUrl)]
        : null;

    // The board/year tag is deliberately not printed — it is editorial metadata,
    // not part of the question paper.
    final stemLabel = '$index. ${question.stemText}';

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      padding: const pw.EdgeInsets.all(8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
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
          pw.SizedBox(height: 4),
          // Sub-questions: text on the left, bold mark right-aligned.
          ...question.cqSubQuestions.map((sq) {
            return pw.Padding(
              padding: const pw.EdgeInsets.only(left: 6, top: 3),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.RichText(
                        text: _mixedText('(${sq.label}) ${sq.text}', baseStyle)),
                  ),
                  pw.SizedBox(width: 10),
                  pw.RichText(
                      text: _mixedText('[${sq.mark}]',
                          smallStyle.copyWith(fontWeight: pw.FontWeight.bold))),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  /// Mirrors the HTML `.mcq-card` / `.mcq-options`.
  pw.Widget _buildPdfMcqItem(
    int index,
    HighSchoolQuestion q,
    pw.TextStyle baseStyle, {
    bool stackOptions = false,
  }) {
    final mcq = q.mcqData;
    if (mcq == null) return pw.SizedBox();

    final letters = ['ক', 'খ', 'গ', 'ঘ'];
    final options = mcq.options;

    // Single column -> options two-per-row (as in the HTML). Double column ->
    // stack them, because a half-width cell cannot fit two side by side.
    final perRow = stackOptions ? 1 : 2;
    final rows = <pw.Widget>[];
    for (int i = 0; i < options.length; i += perRow) {
      final cells = <pw.Widget>[];
      for (int c = 0; c < perRow; c++) {
        final idx = i + c;
        if (idx >= options.length) break;
        final letter =
            idx < letters.length ? letters[idx] : (idx + 1).toString();
        cells.add(pw.Expanded(
          child: pw.RichText(
              text: _mixedText('($letter) ${options[idx]}', baseStyle)),
        ));
        if (c < perRow - 1 && idx + 1 < options.length) {
          cells.add(pw.SizedBox(width: 12));
        }
      }
      rows.add(pw.Padding(
        padding: const pw.EdgeInsets.only(left: 10, top: 2),
        child: pw.Row(children: cells),
      ));
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.RichText(text: _mixedText('$index. ${mcq.text}', baseStyle)),
        ...rows,
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Error helper
  // ─────────────────────────────────────────────────────────────────────────

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

  Widget _buildChapterSection() {
    if (_selectedClass == null || _selectedSubject == null) {
      return const SizedBox.shrink();
    }

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
            TextButton(
              onPressed: _selectedChapterNumbers.isEmpty
                  ? null
                  : () => setState(() => _selectedChapterNumbers.clear()),
              child: const Text('সব বাদ দিন'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_loadingChapters)
          const Center(
              child: Padding(
            padding: EdgeInsets.all(16.0),
            child: CircularProgressIndicator(color: _kAccent),
          ))
        else if (_availableChapters.isEmpty)
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
                        'কোনো অধ্যায় পাওয়া যায়নি — সব অধ্যায় থেকে প্রশ্ন লোড হবে।')),
              ],
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _availableChapters.map((ch) {
              final selected =
                  _selectedChapterNumbers.contains(ch.chapterNumber);
              return FilterChip(
                selected: selected,
                label: Text('অধ্যায় ${ch.chapterNumber}: ${ch.chapterName}'),
                selectedColor: _kPrimary.withOpacity(0.15),
                checkmarkColor: _kPrimary,
                side: BorderSide(
                    color: selected ? _kPrimary : Colors.grey.shade300),
                onSelected: (v) => setState(() {
                  if (v) {
                    _selectedChapterNumbers.add(ch.chapterNumber);
                  } else {
                    _selectedChapterNumbers.remove(ch.chapterNumber);
                  }
                }),
              );
            }).toList(),
          ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 2 — Interactive Question Picker
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStep2() {
    final byChapter = <String, List<HighSchoolQuestion>>{};
    for (final q in _fetchedQuestions) {
      byChapter.putIfAbsent(q.chapterNumber, () => []).add(q);
    }
    final chapterNumbers = byChapter.keys.toList()
      ..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));

    return Column(
      children: [
        // Sticky counter bar
        _buildStickyBar(),
        // Question list
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            children: [
              // Select all / none
              Row(
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.done_all_rounded, size: 18),
                    label: const Text('সব নির্বাচন'),
                    onPressed: _selectAll,
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.remove_done_rounded, size: 18),
                    label: const Text('বাদ দিন'),
                    style: TextButton.styleFrom(foregroundColor: Colors.grey),
                    onPressed: _deselectAll,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Chapter groups
              for (final chNum in chapterNumbers) ...[
                _ChapterGroupHeader(
                  chapterNumber: chNum,
                  chapterName: byChapter[chNum]!.first.chapterName,
                ),
                const SizedBox(height: 8),
                // CQ cards for this chapter
                ...byChapter[chNum]!
                    .where((q) => q.isCq)
                    .map((q) => _buildQuestionCard(q, _cardKey(q, _fetchedQuestions.indexOf(q)))),
                // MCQ cards for this chapter
                ...byChapter[chNum]!
                    .where((q) => q.isMcq)
                    .map((q) => _buildQuestionCard(q, _cardKey(q, _fetchedQuestions.indexOf(q)))),
                // Short-question cards for this chapter
                ...byChapter[chNum]!
                    .where((q) => q.isShort)
                    .map((q) => _buildQuestionCard(q, _cardKey(q, _fetchedQuestions.indexOf(q)))),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      ],
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
            child: const Text('PDF তৈরি করুন ➜',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  /// One-line summary shown in the collapsed question card.
  static String _previewText(HighSchoolQuestion q) {
    if (q.isShort) return q.shortData?.text ?? '';
    if (q.isCq) return q.stemText.isEmpty ? '(কোনো উদ্দীপক নেই)' : q.stemText;
    return q.mcqData?.text ?? '';
  }

  Widget _buildQuestionCard(HighSchoolQuestion q, String cardKey) {
    final isExpanded = _expandedCards[cardKey] == true;
    final typeColor = q.isCq
        ? _kCqColor
        : (q.isShort ? _kRqColor : _kMcqColor);

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
            child: Row(
              children: [
                if (q.boardYearTag.isNotEmpty)
                  _TagChip(
                      label: q.boardYearTag,
                      color: Colors.purple.shade100,
                      textColor: Colors.purple.shade800),
                const SizedBox(width: 6),
                _TagChip(
                    label: 'অধ্যায় ${q.chapterNumber}: ${q.chapterName}',
                    color: Colors.teal.shade50,
                    textColor: Colors.teal.shade700),
              ],
            ),
          ),
          // Expanded detail
          if (isExpanded) _buildExpandedDetail(q),
        ],
      ),
    );
  }

  Widget _buildExpandedDetail(HighSchoolQuestion q) {
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
      return Container(
        margin: const EdgeInsets.fromLTRB(56, 0, 12, 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(mcq.options.length, (i) {
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
        ),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 3 — Exam Header Config & PDF Generation
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
            ],
          ),
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
              label: 'যেকোনো কয়টি CQ-র উত্তর দিতে হবে (খালি রাখলে লেখা হবে না)',
              icon: Icons.rule_rounded,
              keyboardType: TextInputType.number,
              helperText: _selectedCqs.isEmpty
                  ? null
                  : 'সর্বোচ্চ ${_selectedCqs.length} — যেমন: যেকোনো ৫ টি প্রশ্নের উত্তর দাও'),
          const SizedBox(height: 18),

          // ── Stem image size ──────────────────────────────────────────────
          _buildImageSizeSelector(),
          const SizedBox(height: 14),

          // ── Column layout ───────────────────────────────────────────────
          _buildLayoutSelector(),
          const SizedBox(height: 28),

          // Primary Action: PDF View & Download
          SizedBox(
            width: double.infinity,
            height: 56,
            child: _generating
                ? const Center(
                    child: CircularProgressIndicator(color: _kPrimary))
                : ElevatedButton.icon(
                    icon: const Icon(Icons.picture_as_pdf_rounded, size: 22),
                    label: const Text('PDF দেখুন ও ডাউনলোড করুন',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPrimary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 6,
                      shadowColor: _kPrimary.withOpacity(0.5),
                    ),
                    onPressed: _generateAndPreviewPdf,
                  ),
          ),
          const SizedBox(height: 12),

          // Secondary Row: Quick Print & Share PDF
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
                    onPressed: _generating ? null : _generateAndPreviewPdf,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.share_rounded, size: 20),
                    label: const Text('PDF শেয়ার',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0284C7),
                      side: const BorderSide(
                          color: Color(0xFF0284C7), width: 1.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _generating ? null : _sharePdfFile,
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
            'পিডিএফ ছাড়াও ওয়ার্ড এডিটর, ব্রাউজার বা মেসেজিং অ্যাপের জন্য যেকোনো ফরম্যাটে প্রশ্নপত্র সংরক্ষণ ও শেয়ার করুন:',
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

          // Format Cards
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
            icon: Icons.language_rounded,
            accentColor: const Color(0xFFEA580C),
            title: 'Web Page (.html)',
            badge: 'ব্রাউজার ও প্রিন্ট উপযোগী',
            description:
                'যেকোনো ব্রাউজারে ওপেন করুন এবং কীবোর্ডে Ctrl+P চেপে সুন্দরভাবে প্রিন্ট করুন।',
            onOpen: () => _exportHtml(open: true),
            onShare: () => _exportHtml(open: false),
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

  /// One two-way column toggle for either section.
  Widget _buildLayoutRow({
    required String label,
    required int count,
    required String unit,
    required QuestionLayout value,
    required ValueChanged<QuestionLayout> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('$label কলাম',
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: _kDarkText)),
            const SizedBox(width: 8),
            Text(
              count > 0 ? '$count টি $unit' : 'কোনো $unit নেই',
              style: const TextStyle(fontSize: 11, color: _kSubText),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: QuestionLayout.values.map((option) {
            final selected = value == option;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => onChanged(option),
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
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Column glyph so the choice reads at a glance.
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: List.generate(
                            option.mcqColumns,
                            (_) => Container(
                              width: 9,
                              height: 20,
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 1.5),
                              decoration: BoxDecoration(
                                color: selected
                                    ? _kPrimary.withOpacity(0.55)
                                    : Colors.grey.shade400,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          option.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                selected ? FontWeight.bold : FontWeight.w500,
                            color: selected ? _kPrimary : _kDarkText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  /// Independent column controls for the CQ and MCQ sections.
  Widget _buildLayoutSelector() {
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
              const Text('প্রশ্নের কলাম',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: _kDarkText)),
            ],
          ),
          const SizedBox(height: 14),
          _buildLayoutRow(
            label: 'সৃজনশীল (CQ)',
            unit: 'CQ',
            count: _selectedCqs.length,
            value: _cqLayout,
            onChanged: (v) => setState(() => _cqLayout = v),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),
          _buildLayoutRow(
            label: 'বহুনির্বাচনি (MCQ)',
            unit: 'MCQ',
            count: _selectedMcqs.length,
            value: _mcqLayout,
            onChanged: (v) => setState(() => _mcqLayout = v),
          ),
          const SizedBox(height: 12),
          const Text(
            'CQ ও MCQ আলাদাভাবে সাজানো যায়। ছবি থাকলে ছোট কলামে ছবি ছোট দেখাবে।',
            style: TextStyle(fontSize: 11, color: _kSubText),
          ),
        ],
      ),
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
    const steps = ['ফিল্টার', 'প্রশ্ন বেছে নিন', 'PDF তৈরি'];
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

class _ChapterGroupHeader extends StatelessWidget {
  final String chapterNumber;
  final String chapterName;
  const _ChapterGroupHeader(
      {required this.chapterNumber, required this.chapterName});

  @override
  Widget build(BuildContext context) => Container(
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
            Text('অধ্যায় $chapterNumber: $chapterName',
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _kDarkText,
                    fontSize: 13)),
          ],
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
