import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:pi_qbank/widgets/custom_app_bar.dart';
import 'package:pi_qbank/widgets/delete_confirmation_dialog.dart';

/// The scientific calculator, opened inside the app.
///
/// It used to be launched into an external browser. On a phone that meant
/// leaving Pi-QBank entirely, and on a device with no browser resolved it did
/// not open at all — so the tool was there but unusable. The page below keeps
/// it in the app instead.
///
/// Android and iOS get an embedded WebView. Linux desktop has no
/// `webview_flutter` implementation, so it falls back to the browser rather
/// than showing a blank rectangle.
class CalculatorPage extends StatefulWidget {
  const CalculatorPage({super.key});

  /// The calculator itself.
  static final Uri calculatorUri = Uri.parse(
    'https://mathda.com/calculator/?utm_source=landing-page',
  );

  @override
  State<CalculatorPage> createState() => _CalculatorPageState();
}

class _CalculatorPageState extends State<CalculatorPage> {
  WebViewController? _controller;

  bool _isLoading = true;
  bool _hasError = false;
  double _progress = 0;

  /// Guards against stacking the leave prompt when back is pressed twice.
  bool _leaving = false;

  /// `webview_flutter` ships Android and iOS implementations only. Treat the
  /// Linux desktop build as unsupported even when a platform instance exists,
  /// because the CEF plugin is wired through a different widget.
  bool get _isWebViewSupported =>
      !kIsWeb &&
      defaultTargetPlatform != TargetPlatform.linux &&
      WebViewPlatform.instance != null;

  @override
  void initState() {
    super.initState();
    if (_isWebViewSupported) {
      _createController();
    } else {
      _isLoading = false;
    }
  }

  void _createController() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      // The calculator is a normal touch web app; a mobile user-agent keeps it
      // from serving a desktop layout squeezed into a phone-width view.
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (!mounted) return;
            setState(() => _progress = progress / 100);
          },
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _isLoading = true;
              _hasError = false;
            });
          },
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() {
              _isLoading = false;
              _progress = 1;
            });
          },
          onWebResourceError: (error) {
            // A sub-resource failing is not a dead page; only the main frame
            // failing means there is nothing to show.
            if (error.isForMainFrame != true || !mounted) return;
            setState(() {
              _isLoading = false;
              _hasError = true;
            });
          },
          onNavigationRequest: (_) => NavigationDecision.navigate,
        ),
      )
      ..loadRequest(CalculatorPage.calculatorUri);

    setState(() => _controller = controller);
  }

  void _reload() {
    if (_controller == null) return;
    setState(() {
      _hasError = false;
      _isLoading = true;
      _progress = 0;
    });
    _controller!.loadRequest(CalculatorPage.calculatorUri);
  }

  Future<void> _openInBrowser() async {
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await launchUrl(
        CalculatorPage.calculatorUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!opened) {
      messenger.showSnackBar(
        const SnackBar(content: Text('ক্যালকুলেটর খোলা যায়নি।')),
      );
    }
  }

  /// Ask before leaving the calculator.
  ///
  /// Back is the only way out, and an accidental press would throw away the
  /// expression being worked on. The shared confirmation dialog is reused here
  /// with its wording overridden: Cancel keeps the user on the page, Leave
  /// closes it.
  Future<void> _confirmLeave() async {
    if (_leaving) return;
    _leaving = true;

    final navigator = Navigator.of(context);
    final bool? leave;
    try {
      leave = await showDeleteConfirmationDialog(
        context: context,
        title: 'Leave Calculator?',
        message: 'Do you want to close the calculator?',
        confirmLabel: 'Leave',
        confirmIcon: Icons.logout_rounded,
      );
    } finally {
      _leaving = false;
    }

    if (leave == true) {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _confirmLeave();
      },
      child: _isWebViewSupported ? _webViewScaffold() : _unsupportedScaffold(),
    );
  }

  /// The app's own bar, without the notification bell: back, the name, and a
  /// reload button. The calculator is the tool here, so the chrome around it
  /// stays out of the way.
  PreferredSizeWidget _miniAppBar({required bool showReload}) => CustomAppBar(
        title: 'Calculator',
        showNotification: false,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: _confirmLeave,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: [
          if (showReload)
            IconButton(
              tooltip: 'Reload',
              onPressed: _reload,
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      );

  Widget _webViewScaffold() => Scaffold(
        backgroundColor: Colors.white,
        appBar: _miniAppBar(showReload: true),
        body: SafeArea(
          top: false,
          bottom: false,
          child: Column(
            children: [
              if (_isLoading)
                LinearProgressIndicator(
                  value: _progress > 0 && _progress < 1 ? _progress : null,
                  minHeight: 2.5,
                  backgroundColor: Colors.indigo.shade50,
                  color: Colors.indigo,
                ),
              Expanded(
                child: _hasError
                    ? _errorView()
                    : (_controller == null
                        ? const Center(child: CircularProgressIndicator())
                        : WebViewWidget(controller: _controller!)),
              ),
            ],
          ),
        ),
      );

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.wifi_off_rounded,
                    size: 44, color: Colors.amber.shade800),
              ),
              const SizedBox(height: 18),
              const Text(
                'Could not load the calculator',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Check your internet connection and try again.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13.5, color: Colors.grey.shade600, height: 1.4),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: _reload,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _openInBrowser,
                icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                label: const Text('Open in browser'),
              ),
            ],
          ),
        ),
      );

  /// Linux desktop has no embedded WebView, so explain that and offer the
  /// browser instead of an empty pane.
  Widget _unsupportedScaffold() => Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: _miniAppBar(showReload: false),
        body: SafeArea(
          top: false,
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.calculate_rounded,
                              size: 44, color: Colors.amber),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Scientific calculator',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'The in-app calculator is available on Android and '
                          'iOS. On this desktop build you can open it in your '
                          'browser.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade700,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 22),
                        FilledButton.icon(
                          onPressed: _openInBrowser,
                          icon: const Icon(Icons.open_in_browser_rounded),
                          label: const Text('Open calculator'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
