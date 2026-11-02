import 'dart:async';
import 'dart:convert';
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
    this.onControllerReady,
    this.onPageFinished,
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

  /// Hands the caller a script runner once the embedded browser is up.
  ///
  /// The preview page uses this for live editing: the same `window.__piQbank…`
  /// helpers the Android WebView calls can then run inside CEF too, so a
  /// toggle or a settings change no longer rebuilds the page and discards the
  /// reader's typing.
  final ValueChanged<ExactHtmlPreviewController>? onControllerReady;

  /// Called after every completed page load, including reloads triggered by a
  /// new [signature]. The preview page uses it to put captured edits back.
  final VoidCallback? onPageFinished;

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

  @override
  State<ExactHtmlPreview> createState() => _ExactHtmlPreviewState();
}

/// A tiny shell around the CEF controller, exposing only the two JavaScript
/// calls the preview needs.
class ExactHtmlPreviewController {
  ExactHtmlPreviewController(this._controller);

  final WebViewController _controller;

  Future<dynamic> evaluateJavascript(String code) =>
      _controller.evaluateJavascript(code);

  Future<void> executeJavaScript(String code) =>
      _controller.executeJavaScript(code);

  /// Register a one-way bridge from the page back to Flutter.
  ///
  /// CEF defines the channel as a global function, unlike Android's
  /// `postMessage` object; the generated sheet handles both shapes.
  Future<void> setJavaScriptChannel(
    String name,
    void Function(String message) onMessage,
  ) {
    return _controller.setJavaScriptChannels({
      JavascriptChannel(
        name: name,
        onMessageReceived: (message) {
          // CEF serialises the argument with JSON.stringify, so a string comes
          // back as `"1"`; Android's WebView channel gives the bare `1`.
          var value = message.message;
          try {
            final decoded = jsonDecode(value);
            if (decoded is String) value = decoded;
          } on FormatException {
            // Already a bare string.
          }
          onMessage(value);
        },
      ),
    });
  }
}

class _ExactHtmlPreviewState extends State<ExactHtmlPreview> {
  /// CEF is process-wide: it is started once and shared by every preview.
  static Future<void>? _initializing;

  WebViewController? _controller;
  Object? _renderedSignature;
  String? _loadedUrl;
  File? _file;
  Timer? _debounce;
  bool _failed = false;
  bool _starting = true;
  bool? _controllerAnnounced;

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
      final url = Uri.file(file.path).toString();
      // Mark the page before asking Chromium to load it: `onLoadEnd` can arrive
      // while the initialize call is still in flight.
      _renderedSignature = signature;
      _loadedUrl = url;
      final controller = WebviewManager().createWebView();
      controller.setWebviewListener(
        WebviewEventsListener(
          onLoadEnd: (_, loadedUrl) {
            if (!mounted) return;
            // Ignore the tail of an old navigation when a newer page is
            // already on its way; restoring into the wrong document would lose
            // the edit the newer page is waiting for.
            if (loadedUrl != _loadedUrl) return;
            if (_renderedSignature != widget.signature) return;
            widget.onPageFinished?.call();
          },
        ),
      );
      await controller.initialize(url);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _file = file;
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
    final signature = widget.signature;
    try {
      final file = await _write(widget.buildHtml());
      if (!mounted) return;
      final url = Uri.file(file.path).toString();
      // See _start: tag the navigation before loadUrl so a fast onLoadEnd can
      // recognise the page that is actually current.
      _renderedSignature = signature;
      _loadedUrl = url;
      _file = file;
      await controller.loadUrl(url);
      if (!mounted) return;
      if (widget.signature != signature) {
        // The sheet changed while the file was being written; load the newest
        // one instead of marking the stale page as rendered.
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 50), _renderNow);
      }
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
    // Announce from build, not only from _start: a hot reload (or a callback
    // added after the browser came up) must still hand the existing controller
    // to the preview page. Deferring avoids a setState during build.
    if (_controllerAnnounced != true && widget.onControllerReady != null) {
      _controllerAnnounced = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onControllerReady
              ?.call(ExactHtmlPreviewController(controller));
        }
      });
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
