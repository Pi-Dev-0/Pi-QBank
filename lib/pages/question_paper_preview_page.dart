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
    this.fontStep = 0,
    this.font = PaperFont.kalpurush,
    this.printSettings = const PaperPrintSettings(),
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

  /// How far every text size in the paper is moved from its tuned size, in
  /// points; see the font-size control on the generator page.
  final double fontStep;

  /// The face the sheet is set in; see [PaperFont].
  final PaperFont font;

  /// The desktop settings panel's choices: paper stock, header toggles,
  /// watermark, page numbers, and so on.
  final PaperPrintSettings printSettings;

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

  String get _html => HighSchoolExportService.generateHtml(
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
        imageSize: widget.imageSize,
        cqLayout: widget.cqLayout,
        mcqLayout: widget.mcqLayout,
        rqLayout: widget.rqLayout,
        mcqAnswerSheetStyle: widget.mcqAnswerSheetStyle,
        fontStep: widget.fontStep,
        font: widget.font,
        printSettings: widget.printSettings,
        // The preview shows the page as a desktop browser lays it out, not as a
        // phone-width WebView reflows it.
        desktopMode: true,
        compactToolbar: defaultTargetPlatform == TargetPlatform.android,
      );

  @override
  void initState() {
    super.initState();
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
