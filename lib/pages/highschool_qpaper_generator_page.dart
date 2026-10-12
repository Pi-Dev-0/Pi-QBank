import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/highschool_question.dart';
import '../services/highschool_qbank_service.dart';
import '../widgets/custom_app_bar.dart';
import '../config/app_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Colour & design tokens
// ─────────────────────────────────────────────────────────────────────────────

const _kPrimary   = Color(0xFF5C35E3); // vibrant indigo-violet
const _kAccent    = Color(0xFF00C6AB); // teal-mint accent
const _kCqColor   = Color(0xFF3A7BF7); // blue for CQ
const _kMcqColor  = Color(0xFFE86339); // warm orange for MCQ
const _kBg        = Color(0xFFF4F3FF);
const _kCardBg    = Colors.white;
const _kDarkText  = Color(0xFF1E1B3A);
const _kSubText   = Color(0xFF6B6880);

// ─────────────────────────────────────────────────────────────────────────────
// Available options
// ─────────────────────────────────────────────────────────────────────────────

const _kClasses = [
  'Class 6-8',
  'Class 9-10',
  'Class 11-12 (HSC)',
];

const _kSubjectsByClass = {
  'Class 6-8': [
    'সাধারণ গণিত',
    'বিজ্ঞান',
    'বাংলা',
    'English',
  ],
  'Class 9-10': [
    'উচ্চতর গণিত',
    'সাধারণ গণিত',
    'পদার্থবিজ্ঞান',
    'রসায়ন',
    'জীববিজ্ঞান',
    'বাংলা',
    'English',
    'হিসাববিজ্ঞান',
  ],
  'Class 11-12 (HSC)': [
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
    extends State<HighSchoolQPaperGeneratorPage>
    with TickerProviderStateMixin {
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
  final _schoolCtrl   = TextEditingController();
  final _examCtrl     = TextEditingController(text: 'বার্ষিক পরীক্ষা ২০২৬');
  final _subjectCtrl  = TextEditingController();
  final _classCtrl    = TextEditingController();
  final _timeCtrl     = TextEditingController(text: '২ ঘন্টা ৩০ মিনিট');
  final _marksCtrl    = TextEditingController();
  bool _generating    = false;

  // ── Animation ─────────────────────────────────────────────────────────────
  late final AnimationController _stepAnim =
    AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
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
    super.dispose();
  }

  // ── Derived counters ──────────────────────────────────────────────────────

  List<HighSchoolQuestion> get _selectedQuestions =>
    _fetchedQuestions.where((q) => q.isSelected).toList();

  List<HighSchoolQuestion> get _selectedCqs =>
    _selectedQuestions.where((q) => q.isCq).toList();

  List<HighSchoolQuestion> get _selectedMcqs =>
    _selectedQuestions.where((q) => q.isMcq).toList();

  int get _totalCqs  => _fetchedQuestions.where((q) => q.isCq).length;
  int get _totalMcqs => _fetchedQuestions.where((q) => q.isMcq).length;

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

  void _selectAll()   => setState(() { for (final q in _fetchedQuestions) { q.isSelected = true; } });
  void _deselectAll() => setState(() { for (final q in _fetchedQuestions) { q.isSelected = false; } });

  void _proceedToGenerate() {
    if (_selectedQuestions.isEmpty) {
      _showError('অন্তত একটি প্রশ্ন নির্বাচন করুন।');
      return;
    }
    _subjectCtrl.text = _selectedSubject ?? '';
    _classCtrl.text   = _selectedClass ?? '';
    _marksCtrl.text   = '$_totalSelectedMarks';
    _goToStep(2);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Step 3 — PDF generation
  // ─────────────────────────────────────────────────────────────────────────

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

  Future<Uint8List> _buildPdf() async {
    final doc  = pw.Document();
    final cqs  = _selectedCqs;
    final mcqs = _selectedMcqs;

    // Load a Bangla-compatible font from assets
    // (SutonnyMJ is already declared in pubspec.yaml)
    // For full Unicode Bangla we use a Google Noto font loaded from network.
    // Fallback gracefully if unavailable.
    pw.Font? banglaFont;
    try {
      final fontData = await rootBundle.load('assets/fonts/SutonnyMJ Regular.ttf');
      banglaFont = pw.Font.ttf(fontData);
    } catch (_) {
      // Font not found – use default
    }

    final baseStyle = pw.TextStyle(
      font: banglaFont,
      fontSize: 11,
      color: PdfColors.black,
    );
    final boldStyle = pw.TextStyle(
      font: banglaFont,
      fontSize: 11,
      fontWeight: pw.FontWeight.bold,
    );
    final headerStyle = pw.TextStyle(
      font: banglaFont,
      fontSize: 14,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.black,
    );
    final smallStyle = pw.TextStyle(
      font: banglaFont,
      fontSize: 9,
      color: PdfColors.grey700,
    );

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 36),
      build: (ctx) {
        final widgets = <pw.Widget>[];

        // ── Header ─────────────────────────────────────────────────────────
        widgets.add(_buildPdfHeader(
          schoolName: _schoolCtrl.text,
          examName:   _examCtrl.text,
          subject:    _subjectCtrl.text,
          className:  _classCtrl.text,
          time:       _timeCtrl.text,
          totalMarks: _marksCtrl.text,
          baseStyle:  baseStyle,
          boldStyle:  boldStyle,
          headerStyle: headerStyle,
          smallStyle: smallStyle,
        ));

        widgets.add(pw.SizedBox(height: 12));
        widgets.add(pw.Divider(thickness: 1.5, color: PdfColors.black));
        widgets.add(pw.SizedBox(height: 10));

        // ── CQ Section ─────────────────────────────────────────────────────
        if (cqs.isNotEmpty) {
          widgets.add(pw.Text('সৃজনশীল প্রশ্নাবলি (CQ)', style: boldStyle.copyWith(fontSize: 12)));
          widgets.add(pw.SizedBox(height: 8));

          for (int i = 0; i < cqs.length; i++) {
            final q = cqs[i];
            widgets.add(
              _buildPdfCqCard(
                index: i + 1,
                question: q,
                baseStyle: baseStyle,
                boldStyle: boldStyle,
                smallStyle: smallStyle,
              ),
            );
            widgets.add(pw.SizedBox(height: 12));
          }
        }

        // ── MCQ Section ────────────────────────────────────────────────────
        if (mcqs.isNotEmpty) {
          widgets.add(pw.Divider());
          widgets.add(pw.SizedBox(height: 6));
          widgets.add(pw.Text('বহুনির্বাচনি প্রশ্নাবলি (MCQ)', style: boldStyle.copyWith(fontSize: 12)));
          widgets.add(pw.SizedBox(height: 8));

          // MCQ in 2-column grid
          final mcqRows = <pw.Widget>[];
          for (int i = 0; i < mcqs.length; i += 2) {
            final left  = _buildPdfMcqItem(i + 1,     mcqs[i],     baseStyle, boldStyle);
            final right = (i + 1 < mcqs.length)
              ? _buildPdfMcqItem(i + 2, mcqs[i + 1], baseStyle, boldStyle)
              : pw.SizedBox();
            mcqRows.add(pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(child: left),
                pw.SizedBox(width: 16),
                pw.Expanded(child: right),
              ],
            ));
            mcqRows.add(pw.SizedBox(height: 8));
          }
          widgets.addAll(mcqRows);
        }

        return widgets;
      },
    ));

    return doc.save();
  }

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
        if (schoolName.isNotEmpty)
          pw.Text(schoolName, style: headerStyle.copyWith(fontSize: 16)),
        pw.SizedBox(height: 4),
        pw.Text(examName, style: boldStyle.copyWith(fontSize: 13)),
        pw.SizedBox(height: 6),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('বিষয়: $subject', style: baseStyle),
            pw.Text('শ্রেণি: $className', style: baseStyle),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('সময়: $time', style: baseStyle),
            pw.Text('পূর্ণমান: $totalMarks', style: boldStyle),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildPdfCqCard(
    {required int index,
    required HighSchoolQuestion question,
    required pw.TextStyle baseStyle,
    required pw.TextStyle boldStyle,
    required pw.TextStyle smallStyle}) {
    final totalMark = question.totalMarks;

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      padding: const pw.EdgeInsets.all(8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Badge row
          pw.Row(
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: pw.BoxDecoration(
                  color: PdfColors.blue100,
                  borderRadius: pw.BorderRadius.circular(3),
                ),
                child: pw.Text('CQ', style: smallStyle.copyWith(color: PdfColors.blue800)),
              ),
              pw.SizedBox(width: 6),
              if (question.boardYearTag.isNotEmpty)
                pw.Text(question.boardYearTag, style: smallStyle),
              pw.Spacer(),
              pw.Text('মোট: $totalMark নম্বর', style: smallStyle.copyWith(fontWeight: pw.FontWeight.bold)),
            ],
          ),
          pw.SizedBox(height: 6),
          // Stem
          pw.Text('$index. ${question.stemText}', style: baseStyle),
          pw.SizedBox(height: 6),
          // Sub-questions
          ...question.cqSubQuestions.map((sq) {
            return pw.Padding(
              padding: const pw.EdgeInsets.only(left: 12, bottom: 3),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('${sq.label}. ', style: boldStyle),
                  pw.Expanded(child: pw.Text(sq.text, style: baseStyle)),
                  pw.SizedBox(width: 8),
                  pw.Text('[${sq.mark}]', style: smallStyle),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  pw.Widget _buildPdfMcqItem(
    int index,
    HighSchoolQuestion q,
    pw.TextStyle baseStyle,
    pw.TextStyle boldStyle,
  ) {
    final mcq = q.mcqData;
    if (mcq == null) return pw.SizedBox();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('$index. ${mcq.text}', style: baseStyle),
        pw.SizedBox(height: 3),
        ...List.generate(mcq.options.length, (i) {
          final letters = ['ক', 'খ', 'গ', 'ঘ'];
          final letter = i < letters.length ? letters[i] : '${i + 1}';
          return pw.Padding(
            padding: const pw.EdgeInsets.only(left: 10, bottom: 2),
            child: pw.Text('$letter. ${mcq.options[i]}', style: baseStyle),
          );
        }),
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
      case 0: return _buildStep1();
      case 1: return _buildStep2();
      case 2: return _buildStep3();
      default: return const SizedBox.shrink();
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
          _SectionHeader(icon: Icons.filter_list_rounded, label: 'ফিল্টার ও নির্বাচন'),
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
              ? const Center(child: CircularProgressIndicator(color: _kPrimary))
              : ElevatedButton.icon(
                  icon: const Icon(Icons.cloud_download_rounded),
                  label: const Text('প্রশ্ন লোড করুন', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: DropdownButtonFormField<T>(
        value: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: _kPrimary),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          filled: true,
          fillColor: _kCardBg,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        items: items.map((item) => DropdownMenuItem<T>(
          value: item,
          child: Text(displayText(item)),
        )).toList(),
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
            const Text('অধ্যায় নির্বাচন করুন', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _kDarkText)),
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
          const Center(child: Padding(
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
                Expanded(child: Text('কোনো অধ্যায় পাওয়া যায়নি — সব অধ্যায় থেকে প্রশ্ন লোড হবে।')),
              ],
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _availableChapters.map((ch) {
              final selected = _selectedChapterNumbers.contains(ch.chapterNumber);
              return FilterChip(
                selected: selected,
                label: Text('অধ্যায় ${ch.chapterNumber}: ${ch.chapterName}'),
                selectedColor: _kPrimary.withOpacity(0.15),
                checkmarkColor: _kPrimary,
                side: BorderSide(color: selected ? _kPrimary : Colors.grey.shade300),
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
                ...byChapter[chNum]!.where((q) => q.isCq).map((q) => _buildQuestionCard(q)),
                // MCQ cards for this chapter
                ...byChapter[chNum]!.where((q) => q.isMcq).map((q) => _buildQuestionCard(q)),
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
        boxShadow: [BoxShadow(color: _kPrimary.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _CountBadge(label: 'CQ', selected: _selectedCqs.length, total: _totalCqs, color: _kCqColor),
                _CountBadge(label: 'MCQ', selected: _selectedMcqs.length, total: _totalMcqs, color: _kMcqColor),
                Text('মোট নম্বর: $_totalSelectedMarks', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _proceedToGenerate,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            child: const Text('PDF তৈরি করুন ➜', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(HighSchoolQuestion q) {
    final isExpanded = _expandedCards[q.id] == true;
    final typeColor  = q.isCq ? _kCqColor : _kMcqColor;

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
            color: q.isSelected ? _kPrimary.withOpacity(0.12) : Colors.black.withOpacity(0.05),
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
            onTap: () => setState(() => _expandedCards[q.id] = !isExpanded),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Checkbox(
                    value: q.isSelected,
                    activeColor: _kPrimary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                    onChanged: (_) => _toggleQuestion(q),
                  ),
                  const SizedBox(width: 4),
                  // Type badge
                  _TypeBadge(type: q.questionType, color: typeColor),
                  const SizedBox(width: 8),
                  // Preview text
                  Expanded(
                    child: Text(
                      q.isCq
                        ? (q.stemText.isEmpty ? '(কোনো উদ্দীপক নেই)' : q.stemText)
                        : (q.mcqData?.text ?? ''),
                      maxLines: isExpanded ? 10 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: _kDarkText),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    children: [
                      Text('${q.totalMarks}', style: const TextStyle(fontWeight: FontWeight.bold, color: _kPrimary, fontSize: 15)),
                      const Text('নম্বর', style: TextStyle(fontSize: 10, color: _kSubText)),
                    ],
                  ),
                  const SizedBox(width: 4),
                  Icon(isExpanded ? Icons.expand_less : Icons.expand_more, color: _kSubText),
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
                  _TagChip(label: q.boardYearTag, color: Colors.purple.shade100, textColor: Colors.purple.shade800),
                const SizedBox(width: 6),
                _TagChip(label: 'অধ্যায় ${q.chapterNumber}: ${q.chapterName}', color: Colors.teal.shade50, textColor: Colors.teal.shade700),
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
                child: Image.network(q.stemImageUrl, height: 160, fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: Colors.grey),
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
                    width: 22, height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: _kCqColor, borderRadius: BorderRadius.circular(4)),
                    child: Text(sq.label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(sq.text, style: const TextStyle(fontSize: 13))),
                  const SizedBox(width: 8),
                  Text('[${sq.mark}]', style: const TextStyle(color: _kSubText, fontSize: 12)),
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
                    width: 22, height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isCorrect ? Colors.green.shade400 : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(letter, style: TextStyle(color: isCorrect ? Colors.white : Colors.black87, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(mcq.options[i], style: TextStyle(fontSize: 13, color: isCorrect ? Colors.green.shade700 : Colors.black87))),
                  if (isCorrect) const Icon(Icons.check_circle, size: 16, color: Colors.green),
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
          _SectionHeader(icon: Icons.edit_document, label: 'পরীক্ষার তথ্য পূরণ করুন'),
          const SizedBox(height: 16),

          // Summary chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(icon: Icons.quiz_rounded, label: 'CQ: ${_selectedCqs.length}টি'),
              _InfoChip(icon: Icons.format_list_bulleted_rounded, label: 'MCQ: ${_selectedMcqs.length}টি'),
              _InfoChip(icon: Icons.star_rounded, label: 'মোট নম্বর: $_totalSelectedMarks'),
            ],
          ),
          const SizedBox(height: 20),

          _buildTextField(ctrl: _schoolCtrl, label: 'শিক্ষা প্রতিষ্ঠানের নাম', icon: Icons.account_balance_rounded),
          const SizedBox(height: 14),
          _buildTextField(ctrl: _examCtrl, label: 'পরীক্ষার নাম', icon: Icons.description_rounded),
          const SizedBox(height: 14),
          _buildTextField(ctrl: _subjectCtrl, label: 'বিষয়', icon: Icons.book_rounded),
          const SizedBox(height: 14),
          _buildTextField(ctrl: _classCtrl, label: 'শ্রেণি ও শাখা', icon: Icons.class_rounded),
          const SizedBox(height: 14),
          _buildTextField(ctrl: _timeCtrl, label: 'সময়', icon: Icons.access_time_rounded),
          const SizedBox(height: 14),
          _buildTextField(ctrl: _marksCtrl, label: 'পূর্ণমান', icon: Icons.stars_rounded, keyboardType: TextInputType.number),
          const SizedBox(height: 28),

          // Generate PDF button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: _generating
              ? const Center(child: CircularProgressIndicator(color: _kPrimary))
              : ElevatedButton.icon(
                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 22),
                  label: const Text('PDF দেখুন ও ডাউনলোড করুন', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 6,
                    shadowColor: _kPrimary.withOpacity(0.5),
                  ),
                  onPressed: _generateAndPreviewPdf,
                ),
          ),
          const SizedBox(height: 12),

          // Print button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.print_rounded),
              label: const Text('প্রিন্ট করুন', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                foregroundColor: _kPrimary,
                side: const BorderSide(color: _kPrimary, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _generating ? null : _generateAndPreviewPdf,
            ),
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
                color: stepIndex < currentStep ? _kPrimary : Colors.grey.shade200,
              ),
            );
          }
          final stepIndex = i ~/ 2;
          final active = stepIndex == currentStep;
          final done   = stepIndex < currentStep;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 32, height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? _kAccent : (active ? _kPrimary : Colors.grey.shade200),
                ),
                child: Center(
                  child: done
                    ? const Icon(Icons.check, size: 18, color: Colors.white)
                    : Text('${stepIndex + 1}', style: TextStyle(color: active ? Colors.white : Colors.grey.shade500, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 4),
              Text(steps[stepIndex], style: TextStyle(fontSize: 10, color: active ? _kPrimary : Colors.grey.shade500, fontWeight: active ? FontWeight.bold : FontWeight.normal)),
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
        decoration: BoxDecoration(color: _kPrimary.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: _kPrimary, size: 22),
      ),
      const SizedBox(width: 12),
      Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _kDarkText)),
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
      gradient: LinearGradient(colors: [_kPrimary.withOpacity(0.1), _kAccent.withOpacity(0.1)]),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _kPrimary.withOpacity(0.2)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: _kPrimary),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: _kDarkText, fontWeight: FontWeight.w500)),
      ],
    ),
  );
}

class _ChapterGroupHeader extends StatelessWidget {
  final String chapterNumber;
  final String chapterName;
  const _ChapterGroupHeader({required this.chapterNumber, required this.chapterName});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [_kPrimary.withOpacity(0.08), _kAccent.withOpacity(0.05)]),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _kPrimary.withOpacity(0.15)),
    ),
    child: Row(
      children: [
        const Icon(Icons.folder_special_rounded, color: _kPrimary, size: 18),
        const SizedBox(width: 8),
        Text('অধ্যায় $chapterNumber: $chapterName',
          style: const TextStyle(fontWeight: FontWeight.bold, color: _kDarkText, fontSize: 13)),
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
    child: Text(type, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
  );
}

class _TagChip extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;
  const _TagChip({required this.label, required this.color, required this.textColor});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
    child: Text(label, style: TextStyle(fontSize: 10, color: textColor)),
  );
}

class _CountBadge extends StatelessWidget {
  final String label;
  final int selected;
  final int total;
  final Color color;
  const _CountBadge({required this.label, required this.selected, required this.total, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
    child: Text('$label: $selected/$total', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
  );
}
