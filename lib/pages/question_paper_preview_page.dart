import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/highschool_question.dart';
import '../services/highschool_export_service.dart';

/// Full-fidelity, live preview of the generated question-paper HTML.
///
/// This renders the *same* HTML that the .html export writes, inside a WebView,
/// so what you see here is what the student gets — including stem images and the
/// print stylesheet.
///
/// The WebView is hidden (not rebuilt) on unsupported platforms such as Linux
/// desktop and web, because a WebView cannot be hosted there. Callers should
/// check [supportsWebView] first and offer "open externally" instead.
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
    this.setLabels = const [],
    this.sectionOrder = PaperSection.defaultOrder,
    this.imageSize = StemImageSize.medium,
    this.cqLayout = QuestionLayout.single,
    this.mcqLayout = QuestionLayout.doubleColumn,
    this.rqLayout = QuestionLayout.single,
    this.fontStep = 0,
  });

  final String schoolName;
  final String examName;
  final String subject;
  final String className;
  final String time;
  final String totalMarks;
  final List<HighSchoolQuestion> questions;

  /// Names of the sets the paper is printed as, in order. Empty for a
  /// single-set paper; see [HighSchoolExportService.generateHtml].
  final List<String> setLabels;

  /// The order the reader dragged the blocks into.
  final List<PaperSection> sectionOrder;

  final StemImageSize imageSize;
  final QuestionLayout cqLayout;
  final QuestionLayout mcqLayout;
  final QuestionLayout rqLayout;

  /// How far every text size in the paper is moved from its tuned size, in
  /// points. The PDF is built at the same step; see the font-size control on
  /// the generator page.
  final double fontStep;

  /// A WebView cannot be hosted on every platform this app targets.
  static bool get supportsWebView =>
      !kIsWeb &&
      defaultTargetPlatform != TargetPlatform.linux &&
      WebViewPlatform.instance != null;

  @override
  State<QuestionPaperPreviewPage> createState() =>
      _QuestionPaperPreviewPageState();
}

class _QuestionPaperPreviewPageState extends State<QuestionPaperPreviewPage> {
  WebViewController? _controller;
  bool _isLoading = true;

  String get _html => HighSchoolExportService.generateHtml(
        schoolName: widget.schoolName,
        examName: widget.examName,
        subject: widget.subject,
        className: widget.className,
        time: widget.time,
        totalMarks: widget.totalMarks,
        questions: widget.questions,
        setLabels: widget.setLabels,
        sectionOrder: widget.sectionOrder,
        imageSize: widget.imageSize,
        cqLayout: widget.cqLayout,
        mcqLayout: widget.mcqLayout,
        rqLayout: widget.rqLayout,
        fontStep: widget.fontStep,
        // The preview shows the page as a desktop browser lays it out, not as a
        // phone-width WebView reflows it.
        desktopMode: true,
      );

  @override
  void initState() {
    super.initState();
    if (QuestionPaperPreviewPage.supportsWebView) {
      _controller = WebViewController()
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
        )
        ..loadHtmlString(_html);
    }
  }

  /// Re-render with the current header values (used after returning from edit).
  void _reload() {
    _controller?.loadHtmlString(_html);
    setState(() => _isLoading = true);
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
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'প্রিভিউ রিফ্রেশ করুন',
            onPressed: _controller == null ? null : _reload,
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
              'এটি ঠিক যেভাবে HTML/PDF এক্সপোর্ট হবে'
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
    if (_controller == null) {
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
