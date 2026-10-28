// This is the browser-only entry point; dart:html is intentional here.
// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

import 'config/app_config.dart';
import 'models/highschool_question.dart';
import 'services/highschool_export_service.dart';
import 'services/highschool_qbank_service.dart';
import 'utils/math_rich_text.dart';

const _webClasses = [
  'Class 6',
  'Class 7',
  'Class 8',
  'Class (9-10) SSC',
  'Class (11-12) HSC',
];

const _webSubjects = <String, List<String>>{
  'Class 6': ['সাধারণ গণিত', 'বিজ্ঞান', 'বাংলা', 'English'],
  'Class 7': ['সাধারণ গণিত', 'বিজ্ঞান', 'বাংলা', 'English'],
  'Class 8': ['সাধারণ গণিত', 'বিজ্ঞান', 'বাংলা', 'English'],
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

void main() {
  runApp(const PiQBankWebApp());
}

class PiQBankWebApp extends StatelessWidget {
  const PiQBankWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pi-QBank Web',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4F46E5)),
        useMaterial3: true,
        fontFamily: 'HindSiliguri',
      ),
      home: const WebQuestionPaperPage(),
    );
  }
}

class WebQuestionPaperPage extends StatefulWidget {
  const WebQuestionPaperPage({super.key});

  @override
  State<WebQuestionPaperPage> createState() => _WebQuestionPaperPageState();
}

class _WebQuestionPaperPageState extends State<WebQuestionPaperPage> {
  final _schoolController = TextEditingController(text: 'Pi-QBank');
  final _examController = TextEditingController(text: 'বার্ষিক পরীক্ষা');
  final _classController = TextEditingController(text: 'Class 8');
  final _subjectController = TextEditingController(text: 'সাধারণ গণিত');
  final _iframeId = 'pi-qbank-web-preview';
  late final HighSchoolQBankService _qbank;
  html.IFrameElement? _iframe;

  List<HighSchoolQuestion> _questions = const [];
  final _selected = <String>{};
  bool _loading = false;
  String? _error;
  String _typeFilter = 'all';
  String _searchText = '';
  String _previewPaperSize = 'A4';
  bool _includeHeader = true;
  bool _includeMetadata = true;
  bool _includeInstructions = true;
  bool _includeImages = true;
  bool _editingMode = false;
  bool _rightSettingsOpen = true;
  bool _showQuestionSelection = false;

  @override
  void initState() {
    super.initState();
    _qbank = const HighSchoolQBankService(
      scriptUrl: AppConfig.highSchoolQBankApi,
    );
    ui_web.platformViewRegistry.registerViewFactory(_iframeId, (viewId) {
      final frame = html.IFrameElement()
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..setAttribute('title', 'Question paper preview');
      _iframe = frame;
      return frame;
    });
  }

  @override
  void dispose() {
    _schoolController.dispose();
    _examController.dispose();
    _classController.dispose();
    _subjectController.dispose();
    super.dispose();
  }

  Future<void> _loadQuestions() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final questions = await _qbank.fetchQuestions(
        className: _classController.text.trim(),
        subject: _subjectController.text.trim(),
      );
      setState(() {
        _questions = questions;
        // Start with an intentional blank paper. The user chooses exactly
        // which questions should appear in the preview.
        _selected.clear();
        _showQuestionSelection = true;
      });
      _renderPreview();
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _renderPreview() {
    final selected = _questions.where((q) => _selected.contains(q.id)).toList();
    final paper = HighSchoolExportService.generateHtml(
      schoolName: _schoolController.text,
      examName: _examController.text,
      subject: _subjectController.text,
      className: _classController.text,
      time: '২ ঘন্টা ৩০ মিনিট',
      totalMarks: '60',
      questions: selected,
      imageSize: StemImageSize.small,
      font: PaperFont.kalpurush,
      desktopMode: true,
      includeToolbar: false,
    );
    // Keep the generated markup intact; DocumentFragment.text would strip all
    // formatting and turn the paper into plain text.
    _iframe?.srcdoc = paper;
  }

  void _downloadHtml() {
    final selected = _questions.where((q) => _selected.contains(q.id)).toList();
    final paper = HighSchoolExportService.generateHtml(
      schoolName: _schoolController.text,
      examName: _examController.text,
      subject: _subjectController.text,
      className: _classController.text,
      time: '২ ঘন্টা ৩০ মিনিট',
      totalMarks: '60',
      questions: selected,
      imageSize: StemImageSize.small,
      font: PaperFont.kalpurush,
      desktopMode: true,
      includeToolbar: false,
    );
    final blob = html.Blob([paper], 'text/html;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..download = 'pi-qbank-question-paper.html'
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _selected.length;
    return Scaffold(
      backgroundColor: const Color(0xFFF1F3F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
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
            const Text('Pi-QBank',
                style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(width: 10),
            Text('Question Paper Studio',
                style: TextStyle(
                    color: Colors.blueGrey.shade500,
                    fontSize: 14,
                    fontWeight: FontWeight.w500)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _rightSettingsOpen ? 'সেটিংস গুটান' : 'সেটিংস খুলুন',
            onPressed: () =>
                setState(() => _rightSettingsOpen = !_rightSettingsOpen),
            icon: Icon(_rightSettingsOpen ? Icons.tune : Icons.tune_outlined),
          ),
          if (selectedCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Chip(
                  avatar: const Icon(Icons.check_circle_outline, size: 17),
                  label: Text('$selectedCount selected'),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          IconButton(
            tooltip: 'Download HTML',
            onPressed: selectedCount == 0 ? null : _downloadHtml,
            icon: const Icon(Icons.download_rounded),
          ),
          IconButton(
            tooltip: 'Print',
            onPressed: selectedCount == 0 ? null : () => html.window.print(),
            icon: const Icon(Icons.print_rounded),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 960;
          final controls = _buildControls(selectedCount);
          final previewCanvas = Container(
            margin: const EdgeInsets.fromLTRB(8, 16, 24, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x120F172A),
                    blurRadius: 24,
                    offset: Offset(0, 8)),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  decoration: const BoxDecoration(
                    border:
                        Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.visibility_outlined, size: 18),
                      const SizedBox(width: 8),
                      const Text('Live preview',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Text('A4 • Kalpurush',
                          style: TextStyle(
                              color: Colors.blueGrey.shade500, fontSize: 12)),
                    ],
                  ),
                ),
                Expanded(child: HtmlElementView(viewType: _iframeId)),
              ],
            ),
          );
          final preview = Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: previewCanvas),
                if (wide)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: _rightSettingsOpen ? 274 : 48,
                    child: _rightSettingsOpen
                        ? _buildPreviewSettings()
                        : _buildCollapsedSettingsRail(),
                  ),
              ],
            ),
          );
          final workspace = wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: controls),
                    preview,
                  ],
                )
              : Column(
                  children: [
                    SizedBox(
                        height: constraints.maxHeight < 720
                            ? constraints.maxHeight * .62
                            : 460,
                        child: controls),
                    preview,
                  ],
                );
          return workspace;
        },
      ),
    );
  }

  Widget _buildPreviewSettings() {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 16, 12, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD9E1EA)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0D0F172A), blurRadius: 14, offset: Offset(0, 5)),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.all(10),
        children: [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _previewCommand({'action': 'quickFix'}),
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: const Text('সেটিংস'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF102F50)),
              onPressed: _selected.isEmpty ? null : _downloadHtml,
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('ডাউনলোড'),
            ),
          ),
          const SizedBox(height: 16),
          _settingsHeading('দ্রুত সম্পাদনা'),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                    onPressed: () =>
                        _previewCommand({'action': 'demo', 'value': 'cq'}),
                    child: const Text('CQ')),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: OutlinedButton(
                    onPressed: () =>
                        _previewCommand({'action': 'demo', 'value': 'mcq'}),
                    child: const Text('MCQ')),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: OutlinedButton(
                    onPressed: () =>
                        _previewCommand({'action': 'demo', 'value': 'rq'}),
                    child: const Text('RQ')),
              ),
            ],
          ),
          const SizedBox(height: 5),
          OutlinedButton.icon(
            onPressed: () {
              setState(() => _editingMode = !_editingMode);
              _previewCommand({'action': 'edit'});
            },
            icon: Icon(_editingMode ? Icons.check : Icons.edit_outlined,
                size: 17),
            label: Text(_editingMode ? 'এডিট শেষ' : 'লাইভ এডিট'),
          ),
          if (_editingMode) ...[
            const SizedBox(height: 8),
            _buildInlineEditorToolbar(),
          ],
          const SizedBox(height: 5),
          FilledButton.icon(
            onPressed: () => _previewCommand({'action': 'print'}),
            icon: const Icon(Icons.print_outlined, size: 17),
            label: const Text('প্রিন্ট করুন'),
          ),
          const SizedBox(height: 12),
          _settingsHeading('কলাম বিন্যাস'),
          _columnChoiceGroup('CQ', 'cq'),
          _columnChoiceGroup('MCQ', 'mcq'),
          _columnChoiceGroup('RQ', 'rq'),
          const SizedBox(height: 12),
          _settingsHeading('প্রশ্ন সংযুক্তি'),
          _settingsSwitch('উত্তরপত্র', _includeHeader, (value) {
            setState(() => _includeHeader = value);
            _togglePreview('.mcq-answer-sheet', value);
          }),
          _settingsSwitch('গুরুত্বপূর্ণ প্রশ্ন', false, (value) {},
              icon: Icons.palette_outlined),
          _settingsSwitch('প্রশ্নের তথ্য', false, (value) {},
              icon: Icons.palette_outlined),
          _settingsSwitch('শিক্ষার্থীর তথ্য', false, (value) {}),
          _settingsSwitch('বিষয় কোড', false, (value) {}),
          _settingsSwitch('প্রাপ্ত নম্বর ঘর', false, (value) {
            _togglePreview('.rq-mark', value);
          }),
          const SizedBox(height: 14),
          _settingsHeading('প্রশ্নের মেটাডাটা (হেডার)'),
          _settingsDropdown('প্রতিষ্ঠানের নাম', _schoolController.text,
              [_schoolController.text], (_) {}),
          _settingsSwitch('শ্রেণির নাম', _includeMetadata, (value) {
            setState(() => _includeMetadata = value);
            _togglePreview('.meta-bar', value);
          }),
          _settingsSwitch('বিষয়ের নাম', _includeMetadata, (value) {
            setState(() => _includeMetadata = value);
            _togglePreview('.meta-bar', value);
          }),
          _settingsSwitch('অধ্যায়ের নাম', false, (value) {}),
          _settingsSwitch('সেট কোড', false, (value) {}),
          _settingsSwitch('প্রোগ্রাম/পরীক্ষার নাম', _includeMetadata, (value) {
            setState(() => _includeMetadata = value);
            _togglePreview('.meta-bar', value);
          }),
          _settingsSwitch('নির্দেশনা', _includeInstructions, (value) {
            setState(() => _includeInstructions = value);
            _togglePreview('.meta-note, .section-banner', value);
          }),
          const SizedBox(height: 14),
          _settingsHeading('ডকুমেন্ট কাস্টমাইজেশন'),
          _settingsSwitch('এডিটিং মোড', false, (_) {}),
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Text('টেক্সট এলাইনমেন্ট',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
          ),
          Row(
            children: [
              _alignButton(Icons.format_align_left),
              _alignButton(Icons.format_align_center),
              _alignButton(Icons.format_align_right),
              _alignButton(Icons.format_align_justify, selected: true),
            ],
          ),
          const SizedBox(height: 8),
          _settingsDropdown('পেপার সাইজ', _previewPaperSize,
              const ['A4', 'Letter', 'Legal', 'A3', 'A5'], (value) {
            if (value != null) {
              setState(() => _previewPaperSize = value);
              _previewCommand({
                'action': 'printOption',
                'id': 'printPaperSize',
                'value': value
              });
            }
          }),
          _settingsDropdown(
              'প্রিন্ট দিক', 'portrait', const ['portrait', 'landscape'],
              (value) {
            if (value != null) {
              _previewCommand({
                'action': 'printOption',
                'id': 'printOrientation',
                'value': value
              });
            }
          }),
          _settingsDropdown('প্রিন্ট স্কেল', '100',
              const ['50', '75', '90', '100', '110', '125', '150'], (value) {
            if (value != null) {
              _previewCommand({
                'action': 'printOption',
                'id': 'printScale',
                'value': value
              });
            }
          }),
          _settingsDropdown('মার্জিন', '0', const ['0', '8mm', '15mm'],
              (value) {
            if (value != null) {
              _previewCommand({
                'action': 'printOption',
                'id': 'printMargin',
                'value': value
              });
            }
          }),
          _settingsDropdown('ছবির আকার', 'small',
              const ['hidden', 'small', 'medium', 'large'], (value) {
            if (value != null) {
              _previewCommand({'action': 'imagePreset', 'value': value});
            }
          }),
          _settingsDropdown('লেখার আকার', '0', const [
            '-3',
            '-2',
            '-1',
            '0',
            '1',
            '2',
            '3',
            '4',
            '5',
            '6'
          ], (value) {
            if (value != null) {
              _previewCommand({'action': 'fontStep', 'value': value});
            }
          }),
          _settingsDropdown('ফন্ট', PaperFont.kalpurush.cssStack,
              [for (final font in PaperFont.values) font.cssStack], (value) {
            if (value != null) {
              _previewCommand({'action': 'font', 'value': value});
            }
          }),
          _settingsDropdown(
              'MCQ উত্তরপত্র', 'none', const ['none', 'omr', 'serialAnswer'],
              (value) {
            if (value != null) {
              _previewCommand({'action': 'answerSheet', 'value': value});
            }
          }),
          Container(
            margin: const EdgeInsets.only(bottom: 5),
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
                color: const Color(0xFFF1F3F6),
                borderRadius: BorderRadius.circular(5)),
            child: Row(
              children: [
                const Expanded(
                    child: Text('উত্তর আইটেম', style: TextStyle(fontSize: 13))),
                SizedBox(
                  width: 70,
                  child: TextField(
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        hintText: '30',
                        isDense: true,
                        border: InputBorder.none),
                    onChanged: (value) => _previewCommand(
                        {'action': 'answerCount', 'value': value}),
                  ),
                ),
              ],
            ),
          ),
          _settingsSwitch('ছবি দেখাবেন', _includeImages, (value) {
            setState(() => _includeImages = value);
            _togglePreview('.paper-image', value);
          }),
          const SizedBox(height: 8),
          _settingsSlider(
              'নির্বাচিত ছবির আকার',
              25,
              200,
              100,
              (value) => _previewCommand(
                  {'action': 'imageSize', 'value': value.round()})),
          _settingsSlider('কলামের গ্যাপ', 0, 15, 4, (_) {}),
        ],
      ),
    );
  }

  Widget _buildCollapsedSettingsRail() {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 16, 12, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD9E1EA)),
      ),
      child: Column(
        children: [
          IconButton(
            tooltip: 'সেটিংস খুলুন',
            onPressed: () => setState(() => _rightSettingsOpen = true),
            icon: const Icon(Icons.tune_outlined),
          ),
          const Divider(height: 1),
          IconButton(
            tooltip: 'প্রিন্ট',
            onPressed: () => _previewCommand({'action': 'print'}),
            icon: const Icon(Icons.print_outlined),
          ),
        ],
      ),
    );
  }

  void _previewCommand(Map<String, dynamic> command) {
    final frame = _iframe;
    if (frame == null) return;
    frame.contentWindow?.postMessage(
        <String, dynamic>{'source': 'pi-qbank-web-settings', ...command}, '*');
  }

  void _togglePreview(String selector, bool value) {
    _previewCommand({'action': 'toggle', 'selector': selector, 'value': value});
  }

  Widget _buildInlineEditorToolbar() {
    return Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD9E1EA)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x120F172A), blurRadius: 8, offset: Offset(0, 2))
        ],
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _editorIconButton(Icons.remove, 'fontSizeDelta', -2),
          const SizedBox(
              width: 28,
              child: Center(child: Text('18', style: TextStyle(fontSize: 12)))),
          _editorIconButton(Icons.add, 'fontSizeDelta', 2),
          _editorDivider(),
          _editorColorButton(const Color(0xFF111827), 'foreColor'),
          _editorColorButton(const Color(0xFFFDE047), 'hiliteColor'),
          _editorDivider(),
          _editorIconButton(Icons.format_bold, 'bold'),
          _editorIconButton(Icons.format_italic, 'italic'),
          _editorIconButton(Icons.format_underlined, 'underline'),
          _editorDivider(),
          _editorIconButton(Icons.format_align_left, 'justifyLeft'),
          _editorIconButton(Icons.format_align_center, 'justifyCenter'),
          _editorIconButton(Icons.format_align_right, 'justifyRight'),
          _editorDivider(),
          _editorIconButton(Icons.format_clear, 'removeFormat'),
        ],
      ),
    );
  }

  Widget _editorIconButton(IconData icon, String command, [dynamic value]) {
    return SizedBox(
      width: 29,
      height: 29,
      child: IconButton(
        padding: EdgeInsets.zero,
        tooltip: command,
        onPressed: () => _previewCommand({
          'action': command == 'fontSizeDelta' ? 'fontSizeDelta' : 'format',
          if (command != 'fontSizeDelta') 'command': command,
          'value': value,
        }),
        icon: Icon(icon, size: 17),
      ),
    );
  }

  Widget _editorColorButton(Color color, String command) {
    return SizedBox(
      width: 25,
      height: 25,
      child: IconButton(
        padding: EdgeInsets.zero,
        tooltip: command,
        onPressed: () => _previewCommand({
          'action': 'format',
          'command': command,
          'value': command == 'foreColor' ? '#111827' : '#FDE047',
        }),
        icon: Container(
          decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: const Color(0xFFCBD5E1))),
        ),
      ),
    );
  }

  Widget _editorDivider() {
    return Container(width: 1, height: 22, color: const Color(0xFFE2E8F0));
  }

  Widget _settingsHeading(String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
      decoration: const BoxDecoration(
        color: Color(0xFFE8F8F1),
        border: Border(top: BorderSide(color: Color(0xFF0F9F70))),
      ),
      child: Text(text,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
    );
  }

  Widget _settingsSwitch(String label, bool value, ValueChanged<bool> onChanged,
      {IconData? icon}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      decoration: BoxDecoration(
          color: const Color(0xFFF1F3F6),
          borderRadius: BorderRadius.circular(5)),
      child: Row(
        children: [
          Expanded(
              child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  child: Text(label, style: const TextStyle(fontSize: 13)))),
          if (icon != null)
            Icon(icon, size: 16, color: const Color(0xFF64748B)),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _columnChoiceGroup(String label, String kind) {
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: const Color(0xFFF1F3F6),
          borderRadius: BorderRadius.circular(5)),
      child: Row(
        children: [
          SizedBox(
              width: 42,
              child: Text(label, style: const TextStyle(fontSize: 13))),
          for (var columns = 1; columns <= 3; columns++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: OutlinedButton(
                  onPressed: () => _previewCommand({
                    'action': 'columns',
                    'kind': kind,
                    'value': columns,
                  }),
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      minimumSize: Size.zero),
                  child: Text('$columns'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _settingsDropdown(String label, String value, List<String> items,
      ValueChanged<String?> onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
          color: const Color(0xFFF1F3F6),
          borderRadius: BorderRadius.circular(5)),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          SizedBox(
            width: 112,
            child: DropdownButton<String>(
              value: items.contains(value) ? value : items.first,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              items: [
                for (final item in items)
                  DropdownMenuItem(
                      value: item,
                      child: Text(item, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingsSlider(String label, double min, double max, double value,
      ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(9, 4, 9, 0),
          child: Text(label,
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
        ),
        Slider(value: value, min: min, max: max, onChanged: onChanged),
      ],
    );
  }

  Widget _alignButton(IconData icon, {bool selected = false}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: IconButton(
          onPressed: () {},
          style: IconButton.styleFrom(
              backgroundColor:
                  selected ? const Color(0xFF0F9F70) : Colors.white,
              side: const BorderSide(color: Color(0xFFD9E1EA)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4))),
          icon: Icon(icon,
              size: 17,
              color: selected ? Colors.white : const Color(0xFF475569)),
        ),
      ),
    );
  }

  Widget _buildControls(int selectedCount) {
    return Card(
      margin: const EdgeInsets.fromLTRB(28, 22, 12, 20),
      elevation: 0,
      color: const Color(0xFFF8F8FA),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFD6DCE5)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_showQuestionSelection || _questions.isEmpty) ...[
              Container(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
                decoration: const BoxDecoration(
                  color: Color(0xFF102F50),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: const Column(
                  children: [
                    Text('এক ক্লিকে প্রশ্নপত্র তৈরি করুন!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800)),
                    SizedBox(height: 6),
                    Text(
                        'আপনার ক্লাসের প্রশ্নপত্র আরও স্মার্টভাবে তৈরি করুন 💻',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(color: Color(0xFFD7E4F2), fontSize: 15)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(
                    child: Text('নতুন প্রশ্নপত্র',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800)),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDE9FE),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      child: Text('DESKTOP',
                          style: TextStyle(
                              color: Color(0xFF4F46E5),
                              fontSize: 11,
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
                  if (_questions.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'Back to question selection',
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          setState(() => _showQuestionSelection = true),
                      icon: const Icon(Icons.arrow_forward_rounded),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text('তথ্য দিন, প্রশ্ন বাছাই করুন, তারপর প্রিন্ট করুন',
                  style:
                      TextStyle(color: Colors.blueGrey.shade500, fontSize: 13)),
              const SizedBox(height: 12),
              _field(_schoolController, 'প্রতিষ্ঠানের নাম'),
              _field(_examController, 'পরীক্ষার নাম'),
              _dropdownField(
                label: 'শ্রেণি',
                value: _classController.text,
                items: _webClasses,
                onChanged: (value) {
                  if (value == null) return;
                  final subjects = _webSubjects[value] ?? const <String>[];
                  setState(() {
                    _classController.text = value;
                    if (!subjects.contains(_subjectController.text)) {
                      _subjectController.text = subjects.first;
                    }
                  });
                },
              ),
              _dropdownField(
                label: 'বিষয়',
                value: _subjectController.text,
                items: _webSubjects[_classController.text] ?? const <String>[],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _subjectController.text = value);
                  }
                },
              ),
              FilledButton.icon(
                onPressed: _loading ? null : _loadQuestions,
                icon: _loading
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_download_outlined),
                label: Text(_loading ? 'লোড হচ্ছে…' : 'প্রশ্ন লোড করুন'),
              ),
            ] else ...[
              Row(
                children: [
                  const Expanded(
                    child: Text('প্রশ্ন বাছাই করুন',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    tooltip: 'Back to setup',
                    onPressed: () =>
                        setState(() => _showQuestionSelection = false),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                ],
              ),
              Text('${_classController.text} • ${_subjectController.text}',
                  style:
                      TextStyle(color: Colors.blueGrey.shade500, fontSize: 13)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: Colors.red.shade700)),
            ],
            if (_showQuestionSelection && _questions.isNotEmpty) ...[
              const Divider(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text('প্রশ্ন বাছাই করুন',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() => _selected
                          .addAll(_filteredQuestions.map((q) => q.id)));
                      _renderPreview();
                    },
                    child: const Text('সব'),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() => _selected.clear());
                      _renderPreview();
                    },
                    child: const Text('পরিষ্কার'),
                  ),
                ],
              ),
              Text('নির্বাচিত: $selectedCount / ${_questions.length}',
                  style:
                      TextStyle(color: Colors.blueGrey.shade500, fontSize: 12)),
              const SizedBox(height: 8),
              TextField(
                decoration: InputDecoration(
                  hintText: 'প্রশ্ন খুঁজুন…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                ),
                onChanged: (value) => setState(() => _searchText = value),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  _filterChip('all', 'সব'),
                  _filterChip('CQ', 'CQ'),
                  _filterChip('MCQ', 'MCQ'),
                  _filterChip('RQ', 'RQ'),
                ],
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 560,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F4F8),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFD9E1EA)),
                  ),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(10),
                    itemCount: _filteredQuestions.length,
                    itemBuilder: (context, index) {
                      final question = _filteredQuestions[index];
                      final selected = _selected.contains(question.id);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                if (selected) {
                                  _selected.remove(question.id);
                                } else {
                                  _selected.add(question.id);
                                }
                              });
                              _renderPreview();
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding:
                                  const EdgeInsets.fromLTRB(14, 12, 10, 12),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: selected
                                      ? const Color(0xFF4F46E5)
                                      : const Color(0xFFD9E1EA),
                                  width: selected ? 2 : 1,
                                ),
                                borderRadius: BorderRadius.circular(12),
                                color: selected
                                    ? const Color(0xFFF7F5FF)
                                    : Colors.white,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                      child: _questionSelectionCard(
                                          index, question)),
                                  const SizedBox(width: 8),
                                  Checkbox(
                                    value: selected,
                                    activeColor: const Color(0xFF4F46E5),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(5)),
                                    onChanged: (value) {
                                      setState(() {
                                        if (value == true) {
                                          _selected.add(question.id);
                                        } else {
                                          _selected.remove(question.id);
                                        }
                                      });
                                      _renderPreview();
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<HighSchoolQuestion> get _filteredQuestions {
    final query = _searchText.trim().toLowerCase();
    return _questions.where((question) {
      final type = question.isCq
          ? 'CQ'
          : question.isMcq
              ? 'MCQ'
              : 'RQ';
      final matchesType = _typeFilter == 'all' || type == _typeFilter;
      final label = _questionLabel(question).toLowerCase();
      return matchesType && (query.isEmpty || label.contains(query));
    }).toList();
  }

  String _questionLabel(HighSchoolQuestion question) {
    final text = question.paperQuestionText.trim();
    return text.isEmpty ? question.paperStemText.trim() : text;
  }

  Widget _questionSelectionCard(int index, HighSchoolQuestion question) {
    final imageUrl =
        HighSchoolExportService.resolveImageUrl(question.stemImageUrl);
    final optionData = question.mcqData;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: mathText(
                '${index + 1}. ${_questionLabel(question)}',
                style: const TextStyle(
                    fontSize: 15, height: 1.35, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
            _questionTypeBadge(question),
          ],
        ),
        if (optionData != null && optionData.options.isNotEmpty) ...[
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = (constraints.maxWidth - 8) / 2;
              return Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < optionData.options.length; i++)
                    Container(
                      width: itemWidth,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F3F6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: mathText(
                        '(${['ক', 'খ', 'গ', 'ঘ'][i]}) ${optionData.options[i]}',
                        style: const TextStyle(fontSize: 13, height: 1.2),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
        if (question.isCq && question.cqSubQuestions.isNotEmpty) ...[
          const SizedBox(height: 6),
          for (final sub in question.cqSubQuestions)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: mathText(
                '(${sub.label}) ${sub.text}',
                style: const TextStyle(fontSize: 13, height: 1.25),
              ),
            ),
        ],
        if (imageUrl.isNotEmpty) ...[
          const SizedBox(height: 8),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _showImagePreview(imageUrl),
              child: Container(
                height: 150,
                width: 250,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Center(
                    child:
                        Icon(Icons.broken_image_outlined, color: Colors.grey),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _questionTypeBadge(HighSchoolQuestion question) {
    final isMcq = question.isMcq;
    final isCq = question.isCq;
    final color = isMcq
        ? const Color(0xFF0F766E)
        : isCq
            ? const Color(0xFF4F46E5)
            : const Color(0xFF64748B);
    final label = isMcq
        ? 'MCQ'
        : isCq
            ? 'CQ'
            : 'RQ';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w800)),
    );
  }

  void _showImagePreview(String imageUrl) {
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
                  child: Image.network(imageUrl, fit: BoxFit.contain),
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

  Widget _filterChip(String value, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _typeFilter == value,
      onSelected: (_) => setState(() => _typeFilter = value),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _field(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder()),
        onSubmitted: (_) => _renderPreview(),
      ),
    );
  }

  Widget _dropdownField({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    final selected =
        items.contains(value) ? value : (items.isEmpty ? null : items.first);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        value: selected,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final item in items)
            DropdownMenuItem<String>(value: item, child: Text(item)),
        ],
        onChanged: onChanged,
      ),
    );
  }
}
