import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_cef/webview_cef.dart';

/// Shows a generated sheet exactly as a browser lays it out.
///
/// The sheet is written to a temporary file and loaded into an embedded
/// Chromium (CEF) view, so the preview *is* the exported file: the same HTML,
/// the same CSS, the same fonts, the same line breaks. It replaces the second,
/// hand-drawn rendering of the same model the studio used to show.
///
/// Only Linux is enabled: that is the desktop target the app ships, and the
/// plugin needs C++ hooks in the runner that only the Linux build has.
class ExactHtmlPreview extends StatefulWidget {
  const ExactHtmlPreview({
    super.key,
    required this.signature,
    required this.buildHtml,
    this.fileName = 'preview.html',
    this.placeholderBuilder,
    this.fallbackBuilder,
  });

  /// A cheap value that changes whenever the sheet would change.
  ///
  /// The browser is reloaded only when this moves, so scrolling or hovering
  /// does not rebuild a megabyte of HTML.
  final Object signature;

  /// Builds the sheet. Called only when [signature] changes, never from build.
  final String Function() buildHtml;

  /// File name used inside the temporary directory.
  final String fileName;

  /// Shown while the browser starts. The studio passes its native preview so
  /// the pane is never blank.
  final WidgetBuilder? placeholderBuilder;

  /// Shown when CEF cannot start, for example on a machine without its runtime.
  final WidgetBuilder? fallbackBuilder;

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

  @override
  State<ExactHtmlPreview> createState() => _ExactHtmlPreviewState();
}

class _ExactHtmlPreviewState extends State<ExactHtmlPreview> {
  /// CEF is process-wide: it is started once and shared by every preview.
  static Future<void>? _initializing;

  WebViewController? _controller;
  Object? _renderedSignature;
  File? _file;
  Timer? _debounce;
  bool _failed = false;
  bool _starting = true;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant ExactHtmlPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.signature == widget.signature) return;
    // The studio rebuilds the sheet on every keystroke; a short pause keeps
    // the browser from reloading mid-word.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _renderNow);
  }

  Future<void> _start() async {
    try {
      _initializing ??= WebviewManager().initialize();
      await _initializing;
      if (!mounted) return;
      // Take the sheet as it is now: the studio can change it again while the
      // browser is starting, and the check after the load catches that.
      final signature = widget.signature;
      final file = await _write(widget.buildHtml());
      final controller = WebviewManager().createWebView();
      await controller.initialize(Uri.file(file.path).toString());
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _file = file;
        _renderedSignature = signature;
        _starting = false;
      });
      if (_renderedSignature != widget.signature) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 50), _renderNow);
      }
    } catch (_) {
      // A failed start must not poison the next attempt.
      _initializing = null;
      if (!mounted) return;
      setState(() {
        _failed = true;
        _starting = false;
      });
    }
  }

  Future<void> _renderNow() async {
    final controller = _controller;
    if (controller == null) return;
    if (_renderedSignature == widget.signature) return;
    try {
      final file = await _write(widget.buildHtml());
      await controller.loadUrl(Uri.file(file.path).toString());
      if (!mounted) return;
      setState(() {
        _file = file;
        _renderedSignature = widget.signature;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  Future<File> _write(String html) async {
    final dir = await getTemporaryDirectory();
    final safeName = widget.fileName.replaceAll(RegExp(r'[^\w.-]'), '_');
    final file = File('${dir.path}/pi_qbank_$safeName');
    await file.writeAsString(html, flush: true);
    return file;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller?.dispose();
    final file = _file;
    if (file != null) {
      file.delete().ignore();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return widget.fallbackBuilder?.call(context) ?? _buildFailure();
    }
    final controller = _controller;
    if (_starting || controller == null) {
      return widget.placeholderBuilder?.call(context) ??
          const Center(
            child: CircularProgressIndicator(color: Color(0xFF5C35E3)),
          );
    }
    return controller.webviewWidget;
  }

  Widget _buildFailure() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.desktop_access_disabled_outlined,
                  size: 44, color: Colors.grey),
              SizedBox(height: 12),
              Text(
                'ইন-অ্যাপ প্রিভিউ চালু করা যায়নি।\n'
                'ফাইলটি ব্রাউজারে খুলে দেখা যাবে।',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
}
