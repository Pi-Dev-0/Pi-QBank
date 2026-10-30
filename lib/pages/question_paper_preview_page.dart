import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/highschool_question.dart';
import '../services/highschool_export_service.dart';
import '../services/highschool_file_export_service.dart';
import '../widgets/exact_html_preview.dart';

/// Full-fidelity, live preview of the generated question-paper HTML.
///
/// This renders the *same* HTML that the .html export writes, so what you see
/// here is what the student gets — including stem images and the print
/// stylesheet.
///
/// Linux hosts the file in an embedded Chromium (CEF) view; Android, iOS and
/// macOS use `webview_flutter`. Callers should check [supportsWebView] first
/// and offer "open externally" instead.
class QuestionPaperPreviewPage extends StatefulWidget {
  const QuestionPaperPreviewPage({
    super.key,
    required this.schoolName,
    required this.examName,
    required this.subject,
    required this.className,
    required this.time,
    required this.totalMarks,
    required this.questions,
    this.cqInstruction = '',
    this.setLabels = const [],
    this.sectionOrder = PaperSection.defaultOrder,
    this.imageSize = StemImageSize.small,
    this.cqLayout = QuestionLayout.single,
    this.mcqLayout = QuestionLayout.doubleColumn,
    this.rqLayout = QuestionLayout.single,
    this.mcqAnswerSheetStyle = McqAnswerSheetStyle.none,
    this.manualAnswerCount = 30,
    this.fontStep = 0,
    this.font = PaperFont.kalpurush,
    this.printSettings = const PaperPrintSettings(),
    this.settingsBuilder,
    this.liveHtmlBuilder,
  });

  final String schoolName;
  final String examName;
  final String subject;
  final String className;
  final String time;
  final String totalMarks;
  final List<HighSchoolQuestion> questions;

  /// The instruction shown in the CQ meta note, if one was entered.
  final String cqInstruction;

  /// Names of the sets the paper is printed as, in order. Empty for a
  /// single-set paper; see [HighSchoolExportService.generateHtml].
  final List<String> setLabels;

  /// The order the reader dragged the blocks into.
  final List<PaperSection> sectionOrder;

  final StemImageSize imageSize;
  final QuestionLayout cqLayout;
  final QuestionLayout mcqLayout;
  final QuestionLayout rqLayout;

  final McqAnswerSheetStyle mcqAnswerSheetStyle;

  final int manualAnswerCount;

  /// How far every text size in the paper is moved from its tuned size, in
  /// points; see the font-size control on the generator page.
  final double fontStep;

  /// The face the sheet is set in; see [PaperFont].
  final PaperFont font;

  /// The desktop settings panel's choices: paper stock, header toggles,
  /// watermark, page numbers, and so on.
  final PaperPrintSettings printSettings;

  /// Optional editor supplied by the generator. Keeping it injectable lets
  /// the preview reuse the generator's complete settings panel.
  final Widget Function(BuildContext, VoidCallback)? settingsBuilder;

  /// Rebuilds HTML from the generator's live state after a setting changes.
  final String Function()? liveHtmlBuilder;

  /// A WebView cannot be hosted on every platform this app targets.
  static bool get supportsWebView =>
      !kIsWeb &&
      (ExactHtmlPreview.supported || WebViewPlatform.instance != null);

  @override
  State<QuestionPaperPreviewPage> createState() =>
      _QuestionPaperPreviewPageState();
}

class _QuestionPaperPreviewPageState extends State<QuestionPaperPreviewPage> {
  static const _printChannel =
      MethodChannel('com.pi.mathematics/print_preview');
  WebViewController? _controller;
  bool _isLoading = true;

  /// True until the shipped faces are in hand and the WebView is up with the
  /// sheet. Without it a reader would be told this platform has no preview for
  /// the moment the load takes.
  bool _preparing = true;

  Map<String, Uint8List> _stemImages = const {};

  /// The finished sheet. Linux hands it to the embedded Chromium; the other
  /// platforms load it into `webview_flutter` directly.
  String? _cachedHtml;

  // A preview is an editor too: keep a private, mutable copy of every paper
  // setting so the floating panel can update the sheet without navigating back.
  late StemImageSize _imageSize;
  late QuestionLayout _cqLayout;
  late QuestionLayout _mcqLayout;
  late QuestionLayout _rqLayout;
  late McqAnswerSheetStyle _answerSheet;
  late int _answerCount;
  late double _fontStep;
  late PaperFont _font;
  late PaperPrintSettings _printSettings;

  String get _html =>
      widget.liveHtmlBuilder?.call() ??
      HighSchoolExportService.generateHtml(
        schoolName: widget.schoolName,
        examName: widget.examName,
        subject: widget.subject,
        className: widget.className,
        time: widget.time,
        totalMarks: widget.totalMarks,
        questions: widget.questions,
        cqInstruction: widget.cqInstruction,
        imageBytes: _stemImages,
        setLabels: widget.setLabels,
        sectionOrder: widget.sectionOrder,
        imageSize: _imageSize,
        cqLayout: _cqLayout,
        mcqLayout: _mcqLayout,
        rqLayout: _rqLayout,
        mcqAnswerSheetStyle: _answerSheet,
        manualAnswerCount: _answerCount,
        fontStep: _fontStep,
        font: _font,
        printSettings: _printSettings,
        // The preview shows the page as a desktop browser lays it out, not as a
        // phone-width WebView reflows it.
        desktopMode: true,
        compactToolbar: defaultTargetPlatform == TargetPlatform.android,
      );

  @override
  void initState() {
    super.initState();
    _imageSize = widget.imageSize;
    _cqLayout = widget.cqLayout;
    _mcqLayout = widget.mcqLayout;
    _rqLayout = widget.rqLayout;
    _answerSheet = widget.mcqAnswerSheetStyle;
    _answerCount = widget.manualAnswerCount;
    _fontStep = widget.fontStep;
    _font = widget.font;
    _printSettings = widget.printSettings;
    _start();
  }

  /// Load the shipped faces, then build the sheet and hand it to the WebView.
  ///
  /// The wait matters on a phone: the face has to be *in* the sheet (see
  /// [HighSchoolExportService.preloadPaperFonts]), because a phone has none of
  /// the faces this paper can be set in installed, and no way to install one.
  Future<void> _start() async {
    await HighSchoolExportService.preloadPaperFonts();
    if (widget.imageSize.isVisible) {
      _stemImages = await HighSchoolExportService.prefetchStemImages(
        widget.questions,
      );
    }
    if (!mounted) return;
    if (ExactHtmlPreview.supported) {
      // Embedded Chromium shows the file itself, so it only needs the finished
      // markup; it loads and reloads the sheet on its own.
      setState(() {
        _cachedHtml = _html;
        _preparing = false;
      });
      return;
    }
    if (!QuestionPaperPreviewPage.supportsWebView) {
      setState(() => _preparing = false);
      return;
    }
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
          // The preview is self-contained; never let it navigate away.
          onNavigationRequest: (NavigationRequest request) =>
              NavigationDecision.prevent,
        ),
      );

    if (!mounted) return;
    setState(() {
      _preparing = false;
      _controller = controller;
    });
    await controller.loadHtmlString(_html);
  }

  /// Re-render with the current header values (used after returning from edit).
  void _reload() {
    if (ExactHtmlPreview.supported) {
      setState(() => _cachedHtml = _html);
      return;
    }
    _controller?.loadHtmlString(_html);
    setState(() => _isLoading = true);
  }

  /// Open the platform's print flow from the preview AppBar.
  Future<void> _printPreview() async {
    if (ExactHtmlPreview.supported) {
      // CEF does not implement `window.print()`; hand the same file to the
      // browser, whose print dialog is the real one.
      final file = await HighSchoolFileExportService.saveFile(
        content: _cachedHtml ?? _html,
        fileName: 'question_paper_print.html',
      );
      if (!mounted) return;
      await HighSchoolFileExportService.openExportedFile(context, file);
      return;
    }
    final controller = _controller;
    if (controller == null) return;
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        // The preview toolbar changes the DOM at runtime. Printing the
        // original source would silently discard those changes on Android.
        var liveHtml = _html;
        final rawHtml = await controller.runJavaScriptReturningResult(
          'document.documentElement.outerHTML',
        );
        if (rawHtml is String && rawHtml.isNotEmpty) {
          try {
            final decoded = jsonDecode(rawHtml);
            if (decoded is String && decoded.isNotEmpty) {
              liveHtml = decoded;
            }
          } on FormatException {
            // Some WebView versions return the raw string instead of JSON.
            liveHtml = rawHtml;
          }
        }
        final rawPaperSize = await controller.runJavaScriptReturningResult(
          'document.documentElement.dataset.paperSize || "A4"',
        );
        var paperSize = 'A4';
        if (rawPaperSize is String && rawPaperSize.isNotEmpty) {
          try {
            final decoded = jsonDecode(rawPaperSize);
            paperSize = decoded is String ? decoded : rawPaperSize;
          } on FormatException {
            paperSize = rawPaperSize;
          }
        }
        await _printChannel.invokeMethod<void>('printHtml', <String, String>{
          'html': liveHtml,
          'paperSize': paperSize,
        });
      } on PlatformException catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'প্রিন্ট শুরু করা যায়নি: ${error.message ?? 'অজানা সমস্যা'}')),
        );
      }
      return;
    }
    await controller.runJavaScript('window.print();');
  }

  /// Keep the preview controls reachable without leaving the paper. The
  /// preview receives an immutable settings snapshot, so this is a compact
  /// summary; the actual editing controls remain on the generator page.
  void _showPreviewSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 34,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(Icons.tune_rounded,
                      color: Color(0xFF5C35E3), size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('প্রিভিউ সেটিংস',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    tooltip: 'বন্ধ করুন',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _previewSettingRow(
                  'ফন্ট', widget.font.label, Icons.text_fields_rounded),
              _previewSettingRow(
                  'ছবির আকার', widget.imageSize.label, Icons.image_outlined),
              _previewSettingRow(
                  'CQ কলাম', widget.cqLayout.label, Icons.view_column_outlined),
              _previewSettingRow(
                  'MCQ কলাম', widget.mcqLayout.label, Icons.view_week_outlined),
              _previewSettingRow(
                  'RQ কলাম', widget.rqLayout.label, Icons.subject_rounded),
              _previewSettingRow('MCQ উত্তরপত্র',
                  widget.mcqAnswerSheetStyle.label, Icons.fact_check_outlined),
              const SizedBox(height: 8),
              const Text('পরিবর্তন করতে আগের পাতায় ফিরে যান।',
                  style: TextStyle(fontSize: 11.5, color: Colors.black45)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _previewSettingRow(String label, String value, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F7FB),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: const Color(0xFF5C35E3)),
          const SizedBox(width: 9),
          Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
          ),
          Text(value,
              style:
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final withImages =
        widget.questions.where((q) => q.stemImageUrl.trim().isNotEmpty).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F3FF),
      appBar: AppBar(
        title: const Text('প্রশ্নপত্র প্রিভিউ'),
        backgroundColor: const Color(0xFF5C35E3),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.print_rounded),
            tooltip: 'প্রিন্ট করুন',
            onPressed: (_controller == null && !ExactHtmlPreview.supported)
                ? null
                : _printPreview,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'প্রিভিউ রিফ্রেশ করুন',
            onPressed: (_controller == null && !ExactHtmlPreview.supported)
                ? null
                : _reload,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildInfoBar(withImages),
          Expanded(child: _buildPreviewBody()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: widget.settingsBuilder == null
            ? _showPreviewSettings
            : () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) =>
                      widget.settingsBuilder?.call(
                        context,
                        _reload,
                      ) ??
                      _buildFallbackSettingsSheet(context),
                ),
        backgroundColor: const Color(0xFF5C35E3),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.tune_rounded, size: 19),
        label:
            const Text('সেটিংস', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildFallbackSettingsSheet(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('প্রিভিউ সেটিংস',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text('ফন্ট: ${_font.label}'),
            Text('ছবির আকার: ${_imageSize.label}'),
            Text(
                'CQ: ${_cqLayout.label} · MCQ: ${_mcqLayout.label} · RQ: ${_rqLayout.label}'),
            Text('MCQ উত্তরপত্র: ${_answerSheet.label}'),
            const SizedBox(height: 8),
            const Text('সম্পূর্ণ সেটিংস বদলাতে generator page ব্যবহার করুন।',
                style: TextStyle(fontSize: 11.5, color: Colors.black45)),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoBar(int withImages) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.white,
      child: Row(
        children: [
          const Icon(Icons.visibility_outlined,
              size: 18, color: Color(0xFF5C35E3)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'HTML প্রশ্নপত্রের প্রিভিউ'
              '${withImages > 0 ? ' • $withImages টি ছবি সহ' : ''}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B6880)),
            ),
          ),
          Chip(
            label: Text(widget.imageSize.label),
            visualDensity: VisualDensity.compact,
            labelStyle: const TextStyle(fontSize: 11, color: Color(0xFF5C35E3)),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewBody() {
    if (ExactHtmlPreview.supported) {
      final html = _cachedHtml;
      if (html == null) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(color: Color(0xFF5C35E3)),
          ),
        );
      }
      return ExactHtmlPreview(
        signature: html,
        buildHtml: () => html,
        fileName: 'question_paper_preview.html',
      );
    }
    if (_controller == null) {
      if (_preparing) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(color: Color(0xFF5C35E3)),
          ),
        );
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.desktop_access_disabled_outlined,
                  size: 48, color: Colors.grey),
              SizedBox(height: 12),
              Text(
                'এই প্ল্যাটফর্মে ইন-অ্যাপ প্রিভিউ চালু করা যায়নি।\n'
                'প্রিভিউ টি ব্রাউজারে খোলা হয়েছে।',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        WebViewWidget(controller: _controller!),
        if (_isLoading)
          const LinearProgressIndicator(
            backgroundColor: Color(0xFFEDE9FE),
            color: Color(0xFF5C35E3),
          ),
      ],
    );
  }
}
