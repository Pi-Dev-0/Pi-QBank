import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:pi_qbank/widgets/custom_app_bar.dart';
import 'package:pi_qbank/widgets/delete_confirmation_dialog.dart';

/// A calculator keypad the site can draw.
///
/// MathDA ships keypads modelled on the Casio machines students actually use,
/// and selects one with the `model` query parameter. [slug] is the form that
/// parameter expects: lower-case, without the `fx-` prefix.
class CalculatorModel {
  const CalculatorModel(this.label, this.slug);

  /// Shown in the app bar and the model menu.
  final String label;

  /// Value of the `model` query parameter, e.g. `991ex`.
  final String slug;
}

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

  /// The keypads offered in the app bar, grouped roughly as students meet
  /// them: the older ES PLUS boards, the EX generation, then the CW family.
  static const List<CalculatorModel> models = [
    CalculatorModel('fx-991ES PLUS', '991es'),
    CalculatorModel('fx-82ES PLUS', '82es'),
    CalculatorModel('fx-991EX', '991ex'),
    CalculatorModel('fx-570EX', '570ex'),
    CalculatorModel('fx-82EX', '82ex'),
    CalculatorModel('fx-991CW', '991cw'),
    CalculatorModel('fx-570CW', '570cw'),
    CalculatorModel('fx-83GT CW', '83gtcw'),
    CalculatorModel('fx-580VN X', '580vnx'),
    CalculatorModel('fx-570MY CW', '570mycw'),
    CalculatorModel('fx-97SG CW', '97sgcw'),
    CalculatorModel('fx-8200 AU II', '8200auii'),
  ];

  /// Used until the user picks one, and when a saved choice is unreadable.
  static const CalculatorModel defaultModel =
      CalculatorModel('fx-991EX', '991ex');

  /// The calculator with a specific keypad selected.
  ///
  /// The site reads `model` before it reads its own stored preference, so this
  /// wins over whatever was last used in the browser.
  static Uri uriFor(CalculatorModel model) => Uri.parse(
        'https://mathda.com/calculator/?model=${model.slug}'
        '&utm_source=landing-page',
      );

  @override
  State<CalculatorPage> createState() => _CalculatorPageState();
}

class _CalculatorPageState extends State<CalculatorPage> {
  static const String _prefsModelKey = 'calculator.model';

  WebViewController? _controller;

  /// The keypad currently shown. Restored on the next visit.
  CalculatorModel _model = CalculatorPage.defaultModel;

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
    _bootstrap();
  }

  /// Read the saved keypad before the first page load.
  ///
  /// The choice has to be known before the URL is built, otherwise the
  /// calculator would open with the wrong keypad and visibly re-draw itself
  /// once the preference arrived.
  Future<void> _bootstrap() async {
    final saved = await _loadSavedModel();
    if (!mounted) return;

    _model = saved;
    if (_isWebViewSupported) {
      _createController();
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<CalculatorModel> _loadSavedModel() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final slug = prefs.getString(_prefsModelKey);
      if (slug != null) {
        for (final model in CalculatorPage.models) {
          if (model.slug == slug) return model;
        }
      }
    } catch (_) {
      // A missing preference just means the default keypad.
    }
    return CalculatorPage.defaultModel;
  }

  Future<void> _saveModel(CalculatorModel model) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsModelKey, model.slug);
    } catch (_) {
      // Forgetting the choice is not worth an error on screen.
    }
  }

  /// Switch keypad without leaving the page.
  ///
  /// The site only reads `model` while it builds the page, so this reloads the
  /// calculator with the new parameter rather than trying to poke at its
  /// internal state.
  void _selectModel(CalculatorModel model) {
    if (model.slug == _model.slug) return;
    _saveModel(model);

    final controller = _controller;
    setState(() {
      _model = model;
      _hasError = false;
      _isLoading = true;
      _progress = 0;
    });
    controller?.loadRequest(CalculatorPage.uriFor(model));
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
      ..loadRequest(CalculatorPage.uriFor(_model));

    setState(() => _controller = controller);
  }

  void _reload() {
    if (_controller == null) return;
    setState(() {
      _hasError = false;
      _isLoading = true;
      _progress = 0;
    });
    _controller!.loadRequest(CalculatorPage.uriFor(_model));
  }

  Future<void> _openInBrowser() async {
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await launchUrl(
        CalculatorPage.uriFor(_model),
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

  /// The app's own bar, without the notification bell: back, the model
  /// selector, and a reload button. The calculator is the tool here, so the
  /// chrome around it stays out of the way.
  PreferredSizeWidget _miniAppBar({required bool showReload}) => CustomAppBar(
        title: 'Calculator',
        titleWidget: _modelSelector(),
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

  /// The keypad picker that takes the app bar's title slot.
  ///
  /// Tapping it opens the model list; picking one reloads the calculator with
  /// that keypad. It is a menu rather than a dropdown so the bar stays compact
  /// and the full list can scroll on a small screen.
  Widget _modelSelector() => PopupMenuButton<CalculatorModel>(
        tooltip: 'Calculator model',
        initialValue: _model,
        position: PopupMenuPosition.under,
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        onSelected: _selectModel,
        itemBuilder: (context) => [
          for (final model in CalculatorPage.models)
            PopupMenuItem<CalculatorModel>(
              value: model,
              child: Row(
                children: [
                  SizedBox(
                    width: 26,
                    child: model.slug == _model.slug
                        ? const Icon(Icons.check_rounded,
                            size: 18, color: Color(0xFF4F46E5))
                        : null,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    model.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: model.slug == _model.slug
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: const Color(0xFF1F2937),
                    ),
                  ),
                ],
              ),
            ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Text(
                  _model.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ),
              const SizedBox(width: 2),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: Color(0xFF475569),
              ),
            ],
          ),
        ),
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
