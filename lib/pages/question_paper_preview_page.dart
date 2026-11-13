import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/highschool_question.dart';
import '../services/highschool_export_service.dart';
import '../services/highschool_file_export_service.dart';
import '../widgets/exact_html_preview.dart';
import '../widgets/delete_confirmation_dialog.dart';

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
    this.omrColumns = 4,
    this.fontStep = 0,
    this.cqFontStep = 0,
    this.rqFontStep = 0,
    this.mcqFontStep = 0,
    this.font = PaperFont.kalpurush,
    this.printSettings = const PaperPrintSettings(),
    this.settingsBuilder,
    this.liveHtmlBuilder,
    this.fileNameBuilder,
    this.onEditingModeChanged,
    this.onLiveHtmlChanged,
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

  /// How many columns the OMR bubble sheet prints, from one to five.
  final int omrColumns;

  /// How far every text size in the paper is moved from its tuned size, in
  /// points; see the font-size control on the generator page.
  final double fontStep;

  /// Extra steps for one question family, added to [fontStep]. The generator's
  /// CQ/SQ/MCQ size controls use these; they default to zero so a preview built
  /// without them prints exactly the old sheet.
  final double cqFontStep;
  final double rqFontStep;
  final double mcqFontStep;

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

  /// Names the saved file from the generator's current state.
  ///
  /// The preview's settings panel can change the sheet's title after the page
  /// opened, so the constructor's [examName] is not always the current one.
  final String Function()? fileNameBuilder;

  /// Tells the generator that the preview's floating edit button moved.
  ///
  /// The generator owns the sheet's `editingMode`; keeping the two in step means
  /// a reload or a later export starts in the same mode the reader left.
  final ValueChanged<bool>? onEditingModeChanged;

  /// Hands the live page back when the reader leaves the preview.
  ///
  /// A correction exists only inside the browser. Passing the cleaned snapshot
  /// back lets the studio's export and print actions use it after the preview
  /// has closed, instead of silently writing the pre-edit sheet.
  final ValueChanged<String>? onLiveHtmlChanged;

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

  /// The embedded Chromium runner on Linux, once it is ready.
  ///
  /// Android/iOS/macOS use [_controller]; Linux uses this instead, but both
  /// expose the same page scripts so live editing behaves identically.
  ExactHtmlPreviewController? _exactController;
  bool _isLoading = true;

  /// True until the shipped faces are in hand and the WebView is up with the
  /// sheet. Without it a reader would be told this platform has no preview for
  /// the moment the load takes.
  bool _preparing = true;

  Map<String, Uint8List> _stemImages = const {};

  /// The finished sheet. Linux hands it to the embedded Chromium; the other
  /// platforms load it into `webview_flutter` directly.
  String? _cachedHtml;

  /// Edits captured from the live sheet just before it is rebuilt for a new
  /// setting. They are put back once the new page has loaded, so changing a
  /// print option does not wipe text the reader has typed.
  String? _pendingEdits;

  /// Bumped for each requested reload. Dragging a slider asks for many, and only
  /// the newest one may replace the page; an older capture would restore stale
  /// text over the setting the reader just chose.
  int _reloadSerial = 0;

  /// Bumped when the embedded browser must reload even if the HTML string is
  /// unchanged (the refresh button is the common case).
  int _exactReloadToken = 0;

  /// Whether the floating edit button has live edit switched on.
  ///
  /// Kept here rather than in the settings sheet: on a phone the button rides
  /// the preview itself, so editing is never buried under a rebuild.
  bool _editingMode = false;

  /// Guards the asynchronous snapshot in [PopScope] against a second back tap.
  bool _leaving = false;

  // A preview is an editor too: keep a private, mutable copy of every paper
  // setting so the floating panel can update the sheet without navigating back.
  late StemImageSize _imageSize;
  late QuestionLayout _cqLayout;
  late QuestionLayout _mcqLayout;
  late QuestionLayout _rqLayout;
  late McqAnswerSheetStyle _answerSheet;
  late int _answerCount;
  late int _answerColumns;
  late double _fontStep;
  late double _cqFontStep;
  late double _rqFontStep;
  late double _mcqFontStep;
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
        omrColumns: _answerColumns,
        fontStep: _fontStep,
        cqFontStep: _cqFontStep,
        rqFontStep: _rqFontStep,
        mcqFontStep: _mcqFontStep,
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
    _answerColumns = widget.omrColumns;
    _fontStep = widget.fontStep;
    _cqFontStep = widget.cqFontStep;
    _rqFontStep = widget.rqFontStep;
    _mcqFontStep = widget.mcqFontStep;
    _font = widget.font;
    _printSettings = widget.printSettings;
    _editingMode = widget.printSettings.editingMode;
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
    late final WebViewController controller;
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'DeleteImageChannel',
        onMessageReceived: (message) {
          unawaited(_confirmDeleteImage(message.message));
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
            unawaited(_afterPageLoaded());
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
    final html = _html;
    final exact = _exactController;
    if (exact != null) {
      unawaited(_reloadExactWithEdits(exact, html));
      return;
    }
    final controller = _controller;
    if (controller != null) {
      unawaited(_reloadWithEdits(controller, html));
      return;
    }
    if (ExactHtmlPreview.supported) {
      // CEF is still starting. Its first load will pick up this signature.
      setState(() {
        _cachedHtml = html;
        _exactReloadToken += 1;
      });
    }
  }

  /// Capture the text typed into the live CEF sheet, rebuild it, then put that
  /// text back once Chromium reports the new page loaded.
  Future<void> _reloadExactWithEdits(
    ExactHtmlPreviewController exact,
    String html,
  ) async {
    final serial = ++_reloadSerial;
    String? edits;
    try {
      final raw = await exact.evaluateJavascript(
        'JSON.stringify(window.__piQbankCaptureEdits '
        '? window.__piQbankCaptureEdits() : null)',
      );
      edits = _decodeCapturedEdits(raw);
    } catch (_) {
      // The old page may already be going away; there is nothing to capture.
    }
    if (!mounted || serial != _reloadSerial) return;
    _pendingEdits = edits;
    setState(() {
      _cachedHtml = html;
      _exactReloadToken++;
    });
  }

  /// Capture the text typed into the live sheet, reload it, then put that text
  /// back once the new page is ready.
  ///
  /// A settings change has to rebuild the sheet from the app's state, but the
  /// reader's corrections only exist in the WebView. Without this hand-over a
  /// switch anywhere in the floating settings panel would look like the edit
  /// silently undid itself.
  Future<void> _reloadWithEdits(
    WebViewController controller,
    String html,
  ) async {
    final serial = ++_reloadSerial;
    String? edits;
    try {
      final raw = await controller.runJavaScriptReturningResult(
        'JSON.stringify(window.__piQbankCaptureEdits '
        '? window.__piQbankCaptureEdits() : null)',
      );
      edits = _decodeCapturedEdits(raw);
    } catch (_) {
      // A page that has not finished loading yet has nothing to capture.
    }
    if (!mounted || serial != _reloadSerial) return;
    _pendingEdits = edits;
    setState(() => _isLoading = true);
    await controller.loadHtmlString(html);
  }

  String? _decodeCapturedEdits(Object? raw) {
    if (raw is Map || raw is List) {
      if (raw is Map && raw.isEmpty) return null;
      return jsonEncode(raw);
    }
    if (raw is! String || raw.isEmpty || raw == 'null') return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is String) {
        return decoded.isEmpty || decoded == '{}' ? null : decoded;
      }
      if (decoded is Map && decoded.isEmpty) return null;
      if (decoded is Map || decoded is List) return raw;
    } on FormatException {
      return null;
    }
    return null;
  }

  /// Run JavaScript in whichever live view is hosting the sheet.
  Future<Object?> _evaluateJavascript(String code) async {
    final exact = _exactController;
    if (exact != null) return exact.evaluateJavascript(code);
    final controller = _controller;
    if (controller != null) {
      return controller.runJavaScriptReturningResult(code);
    }
    return null;
  }

  Future<void> _runJavascript(String code) async {
    final exact = _exactController;
    if (exact != null) {
      await exact.executeJavaScript(code);
      return;
    }
    await _controller?.runJavaScript(code);
  }

  Future<void> _afterPageLoaded() async {
    final exact = _exactController;
    if (exact != null) await _registerExactDeleteChannel(exact);
    await _restorePendingEdits();
    // A rebuild comes back in the generator's mode, which can lag the floating
    // button by one setting change. Put the button's mode back on top.
    if (_editingMode) await _setEditingMode(true);
  }

  Future<void> _restorePendingEdits() async {
    final edits = _pendingEdits;
    if (edits == null) return;
    _pendingEdits = null;
    try {
      await _runJavascript(
        'window.__piQbankRestoreEdits && '
        'window.__piQbankRestoreEdits(JSON.parse(${jsonEncode(edits)}));',
      );
    } catch (_) {
      // Nothing to restore into: the page never came up.
    }
  }

  /// Switch the floating edit button on or off.
  ///
  /// The page is changed in place: reloading it would rebuild the sheet from the
  /// generator's state and discard every word the reader has typed.
  void _toggleEditingMode() {
    final on = !_editingMode;
    setState(() => _editingMode = on);
    widget.onEditingModeChanged?.call(on);
    unawaited(_setEditingMode(on));
  }

  Future<void> _setEditingMode(bool on) async {
    if (_exactController == null && _controller == null) {
      // A host without a scriptable view cannot change the page in place; fall
      // back to rebuilding it so the button still has an effect there.
      _reload();
      return;
    }
    try {
      await _runJavascript(
        'window.__piQbankSetEditing && window.__piQbankSetEditing(${on ? 'true' : 'false'});',
      );
      // Finishing an edit is the reader saying the paper is right. Keep that
      // page in the studio now, not only when the preview route closes.
      if (!on) {
        final html = await _snapshotLiveHtml();
        if (mounted) widget.onLiveHtmlChanged?.call(html);
      }
    } catch (_) {
      // The view went away between the tap and the script.
    }
  }

  /// Ask before removing a picture from the live sheet.
  ///
  /// The page sends the request through `DeleteImageChannel`; the answer goes
  /// back with the same id so a confirmation that belongs to an older selection
  /// cannot delete the picture selected now.
  Future<void> _confirmDeleteImage(String requestId) async {
    if (!mounted) return;
    final confirmed = await showDeleteConfirmationDialog(
      context: context,
      title: 'ছবি মুছে ফেলবেন?',
      message:
          'এই ছবিটি প্রশ্নপত্রের প্রিভিউ থেকে স্থায়ীভাবে সরিয়ে দেওয়া হবে।',
    );
    if (!mounted) return;
    try {
      await _runJavascript(
        'window.__piQbankDeleteDecision && '
        'window.__piQbankDeleteDecision(${jsonEncode(requestId)}, '
        '${confirmed == true ? 'true' : 'false'});',
      );
    } catch (_) {
      // The preview closed while the dialog was open.
    }
  }

  Future<void> _registerExactDeleteChannel(
    ExactHtmlPreviewController controller,
  ) async {
    try {
      await controller.setJavaScriptChannel(
        'DeleteImageChannel',
        (message) => unawaited(_confirmDeleteImage(message)),
      );
      // CEF defines the channel as a function, while the sheet (and Android's
      // WebView) calls `postMessage`. Add the object-style method too, so a
      // preview generated by an older build keeps working after a reload.
      await controller.executeJavaScript(
        'if (typeof DeleteImageChannel === "function" && '
        '!DeleteImageChannel.postMessage) {'
        'DeleteImageChannel.postMessage = function (id) { '
        'DeleteImageChannel(id); };'
        '}',
      );
    } catch (_) {
      // The page is between loads; the next load registers it again.
    }
  }

  /// The sheet as it stands in the browser, with the editor's screen-only
  /// state removed.
  ///
  /// This is the only copy that carries text the reader typed. Printing,
  /// saving, and leaving the preview all use it, so a correction cannot be
  /// silently replaced by the original generated HTML.
  Future<String> _snapshotLiveHtml() async {
    var liveHtml = _cachedHtml ?? _html;
    try {
      final rawHtml = await _evaluateJavascript(
        'window.__piQbankSnapshotHtml ? window.__piQbankSnapshotHtml() '
        ': document.documentElement.outerHTML',
      );
      final snapshot = _decodeJavascriptString(rawHtml);
      if (snapshot != null && snapshot.isNotEmpty) liveHtml = snapshot;
    } catch (_) {
      // Fall back to the generated sheet if the host is between pages.
    }
    return _withDoctype(liveHtml);
  }

  /// Save the edited sheet wherever the reader chooses.
  Future<void> _saveLiveHtml() async {
    try {
      final html = await _snapshotLiveHtml();
      final name = widget.fileNameBuilder?.call() ?? widget.examName;
      final base = HighSchoolExportService.safeFileName(
        name.trim().isEmpty ? 'QuestionPaper' : name,
      );
      final file = await HighSchoolFileExportService.saveFileAs(
        // The preview hides its in-page toolbar; a saved file should keep the
        // print and edit controls it would have if exported directly.
        content: _withStandaloneToolbar(html),
        fileName: '$base.html',
      );
      if (!mounted || file == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('HTML সংরক্ষণ হয়েছে: ${file.path}'),
          backgroundColor: const Color(0xFF0E9F6E),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('HTML সংরক্ষণ করা যায়নি: $error'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Open the platform's print flow from the preview AppBar.
  Future<void> _printPreview() async {
    if (ExactHtmlPreview.supported) {
      // CEF does not implement `window.print()`; hand the same file to the
      // browser, whose print dialog is the real one.
      final liveHtml = await _snapshotLiveHtml();
      final file = await HighSchoolFileExportService.saveFile(
        content: liveHtml,
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
        final snapshot = _decodeJavascriptString(rawHtml);
        if (snapshot != null && snapshot.isNotEmpty) liveHtml = snapshot;
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
          'html': _withDoctype(liveHtml),
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

  /// WebView/CEF return either the raw string or a JSON-quoted string.
  String? _decodeJavascriptString(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is String && decoded.isNotEmpty) return decoded;
    } on FormatException {
      // Some WebView versions return the raw string instead of JSON.
    }
    return raw;
  }

  /// `outerHTML` omits the doctype; without it Chromium prints in quirks mode.
  String _withDoctype(String html) {
    final trimmed = html.trimLeft();
    if (trimmed.toLowerCase().startsWith('<!doctype')) return html;
    return '<!DOCTYPE html>\n$html';
  }

  String _withStandaloneToolbar(String html) => html.replaceFirstMapped(
        RegExp(r'<body([^>]*)>'),
        (match) => '<body'
            '${(match[1] ?? '').replaceFirst(' toolbar-hidden', '')}>',
      );

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
              if (widget.mcqAnswerSheetStyle == McqAnswerSheetStyle.omr)
                _previewSettingRow('OMR কলাম', '${widget.omrColumns}',
                    Icons.grid_view_rounded),
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _leaving) return;
        _leaving = true;
        final navigator = Navigator.of(context);
        // A correction lives only in the browser. Hand the cleaned page back
        // before the route disappears, so the studio can export it later.
        final liveHtml = await _snapshotLiveHtml();
        if (!mounted) return;
        widget.onLiveHtmlChanged?.call(liveHtml);
        navigator.pop(result);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F3FF),
        appBar: AppBar(
          title: const Text('প্রশ্নপত্র প্রিভিউ'),
          backgroundColor: const Color(0xFF5C35E3),
          foregroundColor: Colors.white,
          actions: [
            // Live edit belongs in the AppBar on every native preview, phones
            // included. It stays visible while the WebView loads and enables
            // itself once the controller is ready, so the toolbar does not
            // shift when the page finishes loading.
            if (!kIsWeb)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _buildTopEditAction(),
              ),
            IconButton(
              icon: const Icon(Icons.save_alt_rounded),
              tooltip: 'এডিট করা HTML সংরক্ষণ',
              onPressed: (_controller == null && !ExactHtmlPreview.supported)
                  ? null
                  : _saveLiveHtml,
            ),
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
        floatingActionButton: _buildFloatingActions(),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      ),
    );
  }

  /// The Linux preview keeps live edit in the AppBar, where the other page
  /// actions are. A phone uses the same AppBar action instead of a second
  /// floating control.
  Widget _buildTopEditAction() {
    final canEdit = _controller != null || _exactController != null;
    final on = _editingMode;
    final compact = MediaQuery.sizeOf(context).width < 640;

    if (compact) {
      return IconButton(
        tooltip: on ? 'এডিট শেষ' : 'লাইভ এডিট',
        color: Colors.white,
        onPressed: canEdit ? _toggleEditingMode : null,
        icon: Icon(
          on ? Icons.check_circle_rounded : Icons.edit_rounded,
          size: 21,
        ),
      );
    }

    return TextButton.icon(
      onPressed: canEdit ? _toggleEditingMode : null,
      icon: Icon(
        on ? Icons.check_circle_rounded : Icons.edit_rounded,
        size: 18,
      ),
      label: Text(on ? 'এডিট শেষ' : 'লাইভ এডিট'),
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white54,
        backgroundColor: Colors.white.withOpacity(on ? 0.20 : 0.12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
        ),
      ),
    );
  }

  /// The settings pill alone. Live edit lives in the AppBar on every platform,
  /// so the phone preview is not covered by a second floating control.
  Widget _buildFloatingActions() {
    // A phone gets a lower, slimmer settings pill; a wide desktop window keeps
    // the stock extended FAB.
    final mobile = !ExactHtmlPreview.supported &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS ||
            MediaQuery.sizeOf(context).width < 700);
    return _buildSettingsFab(compact: mobile);
  }

  Widget _buildSettingsFab({required bool compact}) {
    final fab = FloatingActionButton.extended(
      heroTag: 'preview-settings',
      onPressed: widget.settingsBuilder == null
          ? _showPreviewSettings
          : () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (context) =>
                    widget.settingsBuilder?.call(context, _reload) ??
                    _buildFallbackSettingsSheet(context),
              ),
      backgroundColor: const Color(0xFF5C35E3),
      foregroundColor: Colors.white,
      elevation: compact ? 3 : null,
      icon: Icon(Icons.tune_rounded, size: compact ? 17 : 19),
      label: Text(
        'সেটিংস',
        style: TextStyle(
          fontSize: compact ? 12.5 : null,
          fontWeight: FontWeight.w700,
          letterSpacing: compact ? 0.2 : null,
        ),
      ),
      extendedIconLabelSpacing: compact ? 6 : null,
      extendedPadding:
          compact ? const EdgeInsetsDirectional.only(start: 14, end: 16) : null,
    );
    if (!compact) return fab;

    // The extended FAB's height comes from the theme, not a constructor
    // argument. A local theme lets the phone pill sit lower than the stock
    // 56px one without changing the desktop preview.
    return Theme(
      data: Theme.of(context).copyWith(
        floatingActionButtonTheme:
            Theme.of(context).floatingActionButtonTheme.copyWith(
                  extendedSizeConstraints:
                      const BoxConstraints.tightFor(height: 44),
                ),
      ),
      child: fab,
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
            if (_answerSheet == McqAnswerSheetStyle.omr)
              Text('OMR কলাম: $_answerColumns'),
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
        signature: (html, _exactReloadToken),
        buildHtml: () => html,
        fileName: 'question_paper_preview.html',
        onControllerReady: (controller) {
          if (!mounted) return;
          setState(() => _exactController = controller);
          unawaited(_registerExactDeleteChannel(controller));
        },
        onPageFinished: () => unawaited(_afterPageLoaded()),
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
