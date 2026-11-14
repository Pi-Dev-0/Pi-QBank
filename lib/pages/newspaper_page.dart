import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_cef/webview_cef.dart' as cef;
import 'package:pi_qbank/widgets/loading_widget.dart';

class NewspaperPage extends StatefulWidget {
  final String name;
  final String url;

  const NewspaperPage({
    super.key,
    required this.name,
    required this.url,
  });

  @visibleForTesting
  static void resetCefInitialization() {
    _NewspaperPageState._cefInitializing = null;
  }

  @override
  State<NewspaperPage> createState() => _NewspaperPageState();
}

class _NewspaperPageState extends State<NewspaperPage>
    with TickerProviderStateMixin {
  static const String _darkModePrefKey = 'newspaper_dark_mode';

  // Controllers for the two supported embedded-webview backends.
  // webview_flutter is used on mobile/desktop (non-Linux); CEF is used on Linux.
  WebViewController? _webController;
  cef.WebViewController? _cefController;
  static Future<void>? _cefInitializing;
  bool _cefFailed = false;
  bool _isLoading = true;
  double _progress = 0;
  bool _isPickerActive = false;
  bool _isDarkMode = false;
  List<String> _userRules = [];
  late String _siteKey;
  late AnimationController _bannerAnimController;
  late Animation<double> _bannerAnim;

  bool get _hasController => _webController != null || _cefController != null;

  bool get _isEmbeddedWebViewSupported =>
      !kIsWeb &&
      ((defaultTargetPlatform != TargetPlatform.linux &&
              WebViewPlatform.instance != null) ||
          (defaultTargetPlatform == TargetPlatform.linux));

  bool get _isCefPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

  // ─── SharedPreferences helpers ────────────────────────────────────────────

  Future<void> _runJavaScript(String code) async {
    try {
      if (_webController != null) {
        await _webController!.runJavaScript(code);
      } else if (_cefController != null) {
        await _cefController!.executeJavaScript(code);
      }
    } catch (_) {
      // Ignore JS errors before the page is ready.
    }
  }

  Future<bool> _canGoBack() async {
    if (_webController != null) {
      try {
        return await _webController!.canGoBack();
      } catch (_) {
        return false;
      }
    }
    if (_cefController != null) {
      try {
        final result = await _cefController!.evaluateJavascript(
          'Boolean(window.navigation ? window.navigation.canGoBack : (window.history.length > 1))',
        );
        return result == true || result == 'true';
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  Future<void> _goBack() async {
    if (_webController != null) {
      _webController!.goBack();
    } else if (_cefController != null) {
      await _cefController!.goBack();
    }
  }

  Future<void> _loadDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_darkModePrefKey) ?? false;
    if (!mounted) return;
    setState(() => _isDarkMode = enabled);
    if (_webController != null) {
      try {
        await _webController!.setBackgroundColor(
          enabled ? const Color(0xFF121212) : Colors.white,
        );
      } catch (_) {}
    }
    if (_hasController && enabled) _applyDarkMode();
  }

  Future<void> _toggleDarkMode() async {
    final next = !_isDarkMode;
    setState(() => _isDarkMode = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_darkModePrefKey, next);
    if (_webController != null) {
      try {
        await _webController!.setBackgroundColor(
          next ? const Color(0xFF121212) : Colors.white,
        );
      } catch (_) {}
    }
    if (_hasController) _applyDarkMode();
  }

  Future<void> _loadUserRules() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_siteKey);
    if (raw != null) {
      final List<dynamic> decoded = json.decode(raw);
      if (mounted) {
        setState(() => _userRules = decoded.cast<String>());
        // If the page is already done loading, re-apply rules now.
        if (!_isLoading) _applyAllBlockRules();
      }
    }
  }

  Future<void> _saveUserRules() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_siteKey, json.encode(_userRules));
  }

  // ─── Dark Mode CSS injection ──────────────────────────────────────────────

  void _applyDarkMode() {
    if (!_hasController) return;

    if (!_isDarkMode) {
      _runJavaScript('''
        (function() {
          if (window.__piDarkModeTimer) {
            clearInterval(window.__piDarkModeTimer);
            window.__piDarkModeTimer = null;
          }
          var el = document.getElementById('pi-darkmode-style');
          if (el && el.parentNode) {
            el.parentNode.removeChild(el);
          }
        })();
      ''');
      return;
    }

    const darkCss = 'html { filter: invert(1) hue-rotate(180deg) !important; background-color: #f3f3f3 !important; color-scheme: dark !important; } '
        'img, video, canvas, iframe, [style*="background-image"] { filter: invert(1) hue-rotate(180deg) !important; } '
        '[style*="background-image"] img, [style*="background-image"] video, [style*="background-image"] canvas, iframe img { filter: none !important; }';
    final safeDarkCSS = json.encode(darkCss);

    _runJavaScript('''
      (function() {
        var styleId = 'pi-darkmode-style';
        var cssText = $safeDarkCSS;

        if (window.__piDarkModeTimer) {
          clearInterval(window.__piDarkModeTimer);
        }

        function applyDarkStyle() {
          var target = document.head || document.documentElement;
          if (!target) return;
          var el = document.getElementById(styleId);
          if (!el) {
            el = document.createElement('style');
            el.id = styleId;
            target.appendChild(el);
          }
          if (el.innerHTML !== cssText) {
            el.innerHTML = cssText;
          }
        }

        applyDarkStyle();
        window.__piDarkModeTimer = setInterval(applyDarkStyle, 1000);
      })();
    ''');
  }

  // ─── CSS injection ────────────────────────────────────────────────────────
  // Uses json.encode() to produce a safe JS string literal — handles quotes,
  // backslashes, and other special characters in selectors gracefully.
  // Clears previous interval via window.__piAdblockTimer to avoid accumulation.

  void _applyAllBlockRules() {
    if (!_hasController || _userRules.isEmpty) return;

    // Build the full CSS text and safely encode it as a JS string literal.
    final cssContent =
        '${_userRules.join(', ')} { display: none !important; visibility: hidden !important; opacity: 0 !important; max-height: 0 !important; overflow: hidden !important; }';
    final safeCSS = json.encode(cssContent); // produces "..." with escaping

    _runJavaScript('''
      (function() {
        var styleId = 'pi-adblock-style';
        var cssText = $safeCSS;

        // Clear any previously set interval to avoid accumulation
        if (window.__piAdblockTimer) {
          clearInterval(window.__piAdblockTimer);
        }

        function applyStyle() {
          var el = document.getElementById(styleId);
          if (!el) {
            el = document.createElement('style');
            el.id = styleId;
            document.head.appendChild(el);
          }
          if (el.innerHTML !== cssText) {
            el.innerHTML = cssText;
          }
        }

        applyStyle();
        // Keep re-applying to fight dynamically injected content
        window.__piAdblockTimer = setInterval(applyStyle, 1000);
      })();
    ''');
  }

  // ─── Element picker JavaScript ────────────────────────────────────────────
  // On mobile (touchstart), uses elementFromPoint for accurate target detection.
  // Sends the CSS selector back to Flutter via AdBlockerChannel.postMessage().

  static const String _pickerJS = r"""
  (function() {
    if (window.__piPickerActive) return;
    window.__piPickerActive = true;

    var _highlighted = null;

    function sanitizeClass(cls) {
      // Escape CSS-invalid characters in class names
      return cls.replace(/([!"#$%&'()*+,.\/:;<=>?@[\\\]^`{|}~])/g, '\\$1');
    }

    function getSelector(el) {
      if (!el || el.nodeType !== 1) return '';
      if (el.id) return '#' + el.id;
      var path = [];
      var current = el;
      while (current && current.nodeType === 1 && current !== document.body) {
        var sel = current.nodeName.toLowerCase();
        if (current.id) {
          path.unshift('#' + current.id);
          break;
        }
        if (current.className && typeof current.className === 'string') {
          var classes = current.className.trim().split(/\s+/)
            .filter(function(c) { return c.length > 0; })
            .slice(0, 2)
            .map(sanitizeClass)
            .join('.');
          if (classes) sel += '.' + classes;
        }
        // nth-of-type for uniqueness
        var sib = current;
        var nth = 1;
        while ((sib = sib.previousElementSibling)) {
          if (sib.nodeName === current.nodeName) nth++;
        }
        if (nth > 1) sel += ':nth-of-type(' + nth + ')';
        path.unshift(sel);
        current = current.parentElement;
        if (path.length >= 3) break;
      }
      return path.join(' > ');
    }

    function highlight(el) {
      if (_highlighted && _highlighted !== el) {
        _highlighted.style.outline = '';
        _highlighted.style.outlineOffset = '';
        _highlighted.style.cursor = '';
      }
      if (el && el !== document.body && el !== document.documentElement) {
        _highlighted = el;
        el.style.outline = '3px solid #FF6F00';
        el.style.outlineOffset = '2px';
        el.style.cursor = 'crosshair';
      }
    }

    function cleanup() {
      document.removeEventListener('mouseover', onOver, true);
      document.removeEventListener('mouseout', onOut, true);
      document.removeEventListener('click', onClick, true);
      document.removeEventListener('touchend', onTouch, true);
      if (_highlighted) {
        _highlighted.style.outline = '';
        _highlighted.style.outlineOffset = '';
        _highlighted.style.cursor = '';
      }
      window.__piPickerActive = false;
    }

    function onOver(e) { highlight(e.target); e.stopPropagation(); }
    function onOut(e) {
      if (e.target === _highlighted) {
        e.target.style.outline = '';
        e.target.style.outlineOffset = '';
        e.target.style.cursor = '';
      }
    }

    function onClick(e) {
      e.preventDefault();
      e.stopPropagation();
      var sel = getSelector(e.target);
      if (sel) {
        if (typeof AdBlockerChannel === 'function') AdBlockerChannel(sel);
        else if (AdBlockerChannel && typeof AdBlockerChannel.postMessage === 'function') AdBlockerChannel.postMessage(sel);
      }
      cleanup();
    }

    function onTouch(e) {
      e.preventDefault();
      e.stopPropagation();
      var touch = e.changedTouches[0];
      // elementFromPoint gives the actual element under the finger
      var el = document.elementFromPoint(touch.clientX, touch.clientY);
      if (el) {
        var sel = getSelector(el);
        if (sel) {
          if (typeof AdBlockerChannel === 'function') AdBlockerChannel(sel);
          else if (AdBlockerChannel && typeof AdBlockerChannel.postMessage === 'function') AdBlockerChannel.postMessage(sel);
        }
      }
      cleanup();
    }

    document.addEventListener('mouseover', onOver, true);
    document.addEventListener('mouseout', onOut, true);
    document.addEventListener('click', onClick, true);
    document.addEventListener('touchend', onTouch, { capture: true, passive: false });
  })();
  """;

  static const String _disablePickerJS = r"""
  (function() {
    window.__piPickerActive = false;
    // Remove highlight from any lingering element
    document.querySelectorAll('[style*="outline"]').forEach(function(el) {
      el.style.outline = '';
      el.style.outlineOffset = '';
      el.style.cursor = '';
    });
  })();
  """;

  // ─── Picker toggle ────────────────────────────────────────────────────────

  void _togglePicker() {
    if (!_hasController) return;
    setState(() => _isPickerActive = !_isPickerActive);
    if (_isPickerActive) {
      _bannerAnimController.forward();
      _runJavaScript(_pickerJS);
    } else {
      _bannerAnimController.reverse();
      _runJavaScript(_disablePickerJS);
    }
  }

  void _disablePicker() {
    if (!_hasController) return;
    if (_isPickerActive) {
      setState(() => _isPickerActive = false);
      _bannerAnimController.reverse();
      _runJavaScript(_disablePickerJS);
    }
  }

  // ─── Receiving a selector from JS ─────────────────────────────────────────

  void _onSelectorReceived(String selector) {
    _disablePicker();
    if (selector.isNotEmpty) {
      _showConfirmBlockDialog(selector);
    }
  }

  Future<void> _showConfirmBlockDialog(String selector) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _isDarkMode ? const Color(0xFF1E1E1E) : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.block, color: Colors.deepOrange.shade700, size: 22),
            const SizedBox(width: 8),
            Text(
              'Block this element?',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: _isDarkMode ? Colors.white : null,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('CSS Selector:',
                style: TextStyle(
                    fontSize: 12,
                    color: _isDarkMode ? Colors.grey.shade400 : Colors.grey)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _isDarkMode
                    ? const Color(0xFF2A2A2A)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _isDarkMode
                      ? Colors.grey.shade700
                      : Colors.grey.shade300,
                ),
              ),
              child: SelectableText(
                selector,
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: _isDarkMode
                        ? const Color(0xFF64B5F6)
                        : const Color(0xFF1565C0)),
              ),
            ),
            const SizedBox(height: 10),
            Text(
                'This element will be hidden every time you visit this site.',
                style: TextStyle(
                    fontSize: 13,
                    color: _isDarkMode ? Colors.grey.shade400 : Colors.grey)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(color: _isDarkMode ? Colors.grey.shade300 : null),
            ),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.block, size: 18),
            label: const Text('Block'),
            style: FilledButton.styleFrom(
                backgroundColor: Colors.deepOrange.shade700),
          ),
        ],
      ),
    );

    if (confirmed == true && !_userRules.contains(selector)) {
      setState(() => _userRules.add(selector));
      await _saveUserRules();
      _applyAllBlockRules();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('✅ Element blocked!'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // ─── Ad Blocker bottom-sheet panel ───────────────────────────────────────

  void _showAdBlockerPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AdBlockerPanel(
        isDarkMode: _isDarkMode,
        isPickerActive: _isPickerActive,
        userRules: List.from(_userRules),
        onTogglePicker: () {
          Navigator.of(ctx).pop();
          _togglePicker();
        },
        onDeleteRule: (rule) async {
          setState(() => _userRules.remove(rule));
          await _saveUserRules();
          _applyAllBlockRules();
          if (ctx.mounted) Navigator.of(ctx).pop();
          if (mounted) _showAdBlockerPanel();
        },
        onClearAll: () async {
          setState(() => _userRules.clear());
          await _saveUserRules();
          // Remove the style tag entirely when there are no custom rules
          _runJavaScript('''
            (function() {
              if (window.__piAdblockTimer) clearInterval(window.__piAdblockTimer);
              var el = document.getElementById('pi-adblock-style');
              if (el) el.parentNode.removeChild(el);
              // Re-apply server-side rules if any
            })();
          ''');
          // Re-apply only server-side rules
          _applyAllBlockRules();
          if (ctx.mounted) Navigator.of(ctx).pop();
        },
      ),
    );
  }

  // ─── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _siteKey = 'adblock_rules_${Uri.parse(widget.url).host}';

    _bannerAnimController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _bannerAnim =
        CurvedAnimation(parent: _bannerAnimController, curve: Curves.easeOut);

    if (_isCefPlatform) {
      _isLoading = true;
      _startCef();
    } else if (_isEmbeddedWebViewSupported) {
      _webController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..addJavaScriptChannel(
          'AdBlockerChannel',
          onMessageReceived: (JavaScriptMessage msg) {
            _onSelectorReceived(msg.message);
          },
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (int progress) {
              setState(() => _progress = progress / 100);
              if (_isDarkMode && progress >= 30) {
                _applyDarkMode();
              }
            },
            onPageStarted: (String url) {
              setState(() {
                _isLoading = true;
                _progress = 0;
                _isPickerActive = false;
              });
              _bannerAnimController.reset();
            },
            onPageFinished: (String url) {
              setState(() => _isLoading = false);
              // Apply merged rules (server + user) once page DOM is ready
              _applyAllBlockRules();
              if (_isDarkMode) _applyDarkMode();
            },
            onWebResourceError: (WebResourceError error) {},
          ),
        )
        ..loadRequest(Uri.parse(widget.url));

      // Load persisted rules in background; _applyAllBlockRules() inside
      // _loadUserRules() will re-inject CSS if the page finishes first.
      _loadUserRules();
    } else {
      _isLoading = false;
    }

    _loadDarkMode();
  }

  Future<void> _startCef() async {
    try {
      if (!cef.WebviewManager().value) {
        _cefInitializing ??= cef.WebviewManager().initialize();
        await _cefInitializing;
      }
      if (!mounted) return;

      final controller = cef.WebviewManager().createWebView();
      controller.setWebviewListener(
        cef.WebviewEventsListener(
          onLoadStart: (_, __) {
            if (!mounted) return;
            setState(() {
              _isLoading = true;
              _progress = 0;
              _isPickerActive = false;
            });
            _bannerAnimController.reset();
          },
          onLoadEnd: (_, __) {
            if (!mounted) return;
            setState(() => _isLoading = false);
            _registerCefChannels(controller);
            _applyAllBlockRules();
            if (_isDarkMode) _applyDarkMode();
          },
        ),
      );

      await controller.initialize(widget.url);
      if (!mounted) {
        await controller.dispose();
        return;
      }

      await _registerCefChannels(controller);

      setState(() {
        _cefController = controller;
      });

      // Load persisted rules in background.
      _loadUserRules();
    } catch (e, stack) {
      debugPrint('Failed to initialize CEF for NewspaperPage: $e\n$stack');
      _cefInitializing = null;
      if (!mounted) return;
      setState(() {
        _cefFailed = true;
        _isLoading = false;
      });
    }
  }

  Future<void> _registerCefChannels(cef.WebViewController controller) async {
    try {
      await controller.setJavaScriptChannels({
        cef.JavascriptChannel(
          name: 'AdBlockerChannel',
          onMessageReceived: (cef.JavascriptMessage msg) {
            var value = msg.message;
            try {
              final decoded = jsonDecode(value);
              if (decoded is String) value = decoded;
            } on FormatException {
              // Already a bare string.
            }
            _onSelectorReceived(value);
          },
        ),
      });
    } catch (e) {
      debugPrint('Failed to set CEF JavaScript channels: $e');
    }
  }

  Future<void> _openInBrowser() async {
    final uri = Uri.parse(widget.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  void dispose() {
    _bannerAnimController.dispose();
    _cefController?.dispose();
    super.dispose();
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_isEmbeddedWebViewSupported || _cefFailed) {
      return Scaffold(
        backgroundColor:
            _isDarkMode ? const Color(0xFF121212) : Colors.grey.shade50,
        appBar: AppBar(
          backgroundColor: _isDarkMode ? const Color(0xFF1E1E1E) : null,
          foregroundColor: _isDarkMode ? Colors.white : null,
          title: Text(widget.name,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          actions: [
            IconButton(
              tooltip: _isDarkMode ? 'Light mode' : 'Dark mode',
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Icon(
                  _isDarkMode
                      ? Icons.light_mode_rounded
                      : Icons.dark_mode_rounded,
                  key: ValueKey(_isDarkMode),
                ),
              ),
              onPressed: _toggleDarkMode,
            ),
            IconButton(
              tooltip: 'Open in Browser',
              icon: const Icon(Icons.open_in_browser),
              onPressed: _openInBrowser,
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Card(
                color: _isDarkMode ? const Color(0xFF1E1E1E) : null,
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(28.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _isDarkMode
                              ? Colors.deepOrange.shade900.withOpacity(0.3)
                              : Colors.deepOrange.shade50,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.newspaper,
                            size: 48, color: Colors.deepOrange.shade700),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        widget.name,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: _isDarkMode ? Colors.white : null,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.url,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13,
                            color: _isDarkMode
                                ? Colors.grey.shade400
                                : Colors.grey.shade600),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _isCefPlatform
                            ? 'Embedded web view could not be loaded. You can read ${widget.name} directly in your default browser.'
                            : 'Embedded web view is not supported on this platform. You can read ${widget.name} directly in your default browser.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 14,
                            color: _isDarkMode
                                ? Colors.grey.shade300
                                : Colors.grey.shade700,
                            height: 1.4),
                      ),
                      const SizedBox(height: 28),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _openInBrowser,
                            icon: const Icon(Icons.open_in_browser),
                            label: const Text('Open in Browser'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepOrange.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: OutlinedButton.styleFrom(
                              foregroundColor:
                                  _isDarkMode ? Colors.white70 : null,
                              side: _isDarkMode
                                  ? BorderSide(color: Colors.grey.shade700)
                                  : null,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('Back'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (_isCefPlatform && _cefController == null && !_cefFailed) {
      return Scaffold(
        backgroundColor:
            _isDarkMode ? const Color(0xFF121212) : Colors.grey.shade50,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;
        if (await _canGoBack()) {
          await _goBack();
        } else {
          if (!context.mounted) return;
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor:
            _isDarkMode ? const Color(0xFF121212) : Colors.white,
        appBar: MediaQuery.orientationOf(context) == Orientation.landscape
            ? null
            : AppBar(
          backgroundColor: _isDarkMode ? const Color(0xFF1E1E1E) : null,
          foregroundColor: _isDarkMode ? Colors.white : null,
          title: Text(widget.name,
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          actions: [
            IconButton(
              tooltip: _isDarkMode ? 'Light mode' : 'Dark mode',
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Icon(
                  _isDarkMode
                      ? Icons.light_mode_rounded
                      : Icons.dark_mode_rounded,
                  key: ValueKey(_isDarkMode),
                ),
              ),
              onPressed: _toggleDarkMode,
            ),
            IconButton(
              tooltip: 'Open in Browser',
              icon: const Icon(Icons.open_in_browser),
              onPressed: _openInBrowser,
            ),
            Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  tooltip: 'Ad Blocker',
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Icon(
                      _isPickerActive
                          ? Icons.shield
                          : Icons.shield_outlined,
                      key: ValueKey(_isPickerActive),
                      color: _isPickerActive
                          ? Colors.deepOrange.shade600
                          : null,
                    ),
                  ),
                  onPressed: _showAdBlockerPanel,
                ),
                if (_userRules.isNotEmpty)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.deepOrange.shade700,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        body: Stack(
          children: [
            if (_webController != null)
              Positioned.fill(
                child: WebViewWidget(controller: _webController!),
              ),
            if (_cefController != null)
              Positioned.fill(
                child: Container(
                  color: _isDarkMode ? const Color(0xFF121212) : Colors.white,
                  child: _cefController!.webviewWidget,
                ),
              ),
            if (_isLoading) LoadingWidget(progress: _progress),
            // Picker active banner
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _bannerAnim,
                child: SizeTransition(
                  sizeFactor: _bannerAnim,
                  axisAlignment: -1,
                  child: Material(
                    color: Colors.deepOrange.shade700,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          const Icon(Icons.touch_app,
                              color: Colors.white, size: 20),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Tap any element to block it',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14),
                            ),
                          ),
                          GestureDetector(
                            onTap: _disablePicker,
                            child: const Icon(Icons.close,
                                color: Colors.white, size: 20),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
        )],
        ),
        floatingActionButton: MediaQuery.orientationOf(context) == Orientation.landscape
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton(
                    heroTag: 'newspaper_dark_mode_fab',
                    mini: true,
                    tooltip: _isDarkMode ? 'Light mode' : 'Dark mode',
                    onPressed: _toggleDarkMode,
                    backgroundColor:
                        _isDarkMode ? const Color(0xFF2C2C2C) : Colors.white,
                    elevation: 4,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Icon(
                        _isDarkMode
                            ? Icons.light_mode_rounded
                            : Icons.dark_mode_rounded,
                        key: ValueKey(_isDarkMode),
                        color: _isDarkMode
                            ? Colors.amber.shade400
                            : Colors.deepOrange.shade700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton(
                    heroTag: 'newspaper_open_in_browser_fab',
                    mini: true,
                    tooltip: 'Open in Browser',
                    onPressed: _openInBrowser,
                    backgroundColor:
                        _isDarkMode ? const Color(0xFF2C2C2C) : Colors.white,
                    elevation: 4,
                    child: Icon(
                      Icons.open_in_browser,
                      color: Colors.deepOrange.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton(
                    heroTag: 'newspaper_ad_blocker_fab',
                    mini: true,
                    onPressed: _showAdBlockerPanel,
                    backgroundColor:
                        _isDarkMode ? const Color(0xFF2C2C2C) : Colors.white,
                    elevation: 4,
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: Icon(
                            _isPickerActive
                                ? Icons.shield
                                : Icons.shield_outlined,
                            key: ValueKey(_isPickerActive),
                            color: Colors.deepOrange.shade700,
                          ),
                        ),
                        if (_userRules.isNotEmpty)
                          Positioned(
                            top: -2,
                            right: -2,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: Colors.deepOrange.shade700,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _isDarkMode
                                      ? const Color(0xFF2C2C2C)
                                      : Colors.white,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              )
            : null,
      ),
    );
  }
}

// ─── Ad Blocker Bottom Sheet Panel ───────────────────────────────────────────

class _AdBlockerPanel extends StatelessWidget {
  final bool isDarkMode;
  final bool isPickerActive;
  final List<String> userRules;
  final VoidCallback onTogglePicker;
  final Future<void> Function(String) onDeleteRule;
  final VoidCallback onClearAll;

  const _AdBlockerPanel({
    required this.isDarkMode,
    required this.isPickerActive,
    required this.userRules,
    required this.onTogglePicker,
    required this.onDeleteRule,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    final sheetBg = isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;
    final titleColor = isDarkMode ? Colors.white : Colors.black87;
    final subColor = isDarkMode ? Colors.grey.shade400 : Colors.grey;
    final dividerColor = isDarkMode ? Colors.grey.shade800 : null;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: sheetBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            controller: scrollCtrl,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDarkMode ? Colors.grey.shade700 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              // Header
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isDarkMode
                            ? Colors.deepOrange.shade900.withOpacity(0.3)
                            : Colors.deepOrange.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.shield,
                          color: Colors.deepOrange.shade700, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Ad Blocker',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: titleColor)),
                          Text('Block unwanted elements on this site',
                              style: TextStyle(fontSize: 12, color: subColor)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: dividerColor),
              // Picker toggle
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: onTogglePicker,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isPickerActive
                            ? [
                                Colors.deepOrange.shade600,
                                Colors.orange.shade500
                              ]
                            : isDarkMode
                                ? [
                                    const Color(0xFF2A2A2A),
                                    const Color(0xFF242424),
                                  ]
                                : [Colors.grey.shade100, Colors.grey.shade50],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isPickerActive
                            ? Colors.deepOrange.shade400
                            : isDarkMode
                                ? Colors.grey.shade700
                                : Colors.grey.shade200,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isPickerActive ? Icons.touch_app : Icons.ads_click,
                          color: isPickerActive
                              ? Colors.white
                              : Colors.deepOrange.shade700,
                          size: 22,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isPickerActive
                                    ? 'Picker Mode Active — tap to stop'
                                    : 'Enable Element Picker',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: isPickerActive
                                      ? Colors.white
                                      : titleColor,
                                ),
                              ),
                              Text(
                                isPickerActive
                                    ? 'Now tap any element on the page'
                                    : 'Tap to activate — then pick any element',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isPickerActive
                                      ? Colors.white70
                                      : isDarkMode
                                          ? Colors.grey.shade400
                                          : Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          isPickerActive
                              ? Icons.stop_circle_outlined
                              : Icons.play_circle_outline,
                          color: isPickerActive
                              ? Colors.white
                              : Colors.deepOrange.shade700,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Rules header
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Blocked Elements (${userRules.length})',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: titleColor),
                    ),
                    if (userRules.isNotEmpty)
                      TextButton.icon(
                        onPressed: onClearAll,
                        icon: const Icon(Icons.delete_sweep,
                            size: 16, color: Colors.red),
                        label: const Text('Clear All',
                            style:
                                TextStyle(color: Colors.red, fontSize: 13)),
                        style: TextButton.styleFrom(
                            minimumSize: Size.zero,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4)),
                      ),
                  ],
                ),
              ),
              Divider(height: 1, color: dividerColor),
              // Rules list
              userRules.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.block,
                              size: 48,
                              color: isDarkMode
                                  ? Colors.grey.shade700
                                  : Colors.grey.shade300),
                          const SizedBox(height: 12),
                          Text('No custom rules yet',
                              style: TextStyle(
                                  color: isDarkMode
                                      ? Colors.grey.shade400
                                      : Colors.grey.shade500,
                                  fontSize: 15)),
                          const SizedBox(height: 4),
                          Text('Use the element picker to block ads',
                              style: TextStyle(
                                  color: isDarkMode
                                      ? Colors.grey.shade600
                                      : Colors.grey.shade400,
                                  fontSize: 12)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                        itemCount: userRules.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 6),
                        itemBuilder: (_, i) {
                          final rule = userRules[i];
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: isDarkMode
                                  ? const Color(0xFF2A2A2A)
                                  : Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isDarkMode
                                    ? Colors.grey.shade700
                                    : Colors.grey.shade200,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.block,
                                    size: 16,
                                    color: Colors.deepOrange.shade400),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    rule,
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      color: isDarkMode
                                          ? const Color(0xFF64B5F6)
                                          : const Color(0xFF1565C0),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 2,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => onDeleteRule(rule),
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: Icon(Icons.remove_circle_outline,
                                        size: 20,
                                        color: Colors.red.shade400),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
            ],
            ),
          ),
        );
      },
    );
  }
}
