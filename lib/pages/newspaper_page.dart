import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:pi_qbank/widgets/loading_widget.dart';

class NewspaperPage extends StatefulWidget {
  final String name;
  final String url;

  const NewspaperPage({
    super.key,
    required this.name,
    required this.url,
  });

  @override
  State<NewspaperPage> createState() => _NewspaperPageState();
}

class _NewspaperPageState extends State<NewspaperPage>
    with TickerProviderStateMixin {
  // Controller is declared non-late and initialized synchronously to avoid
  // LateInitializationError when build() runs before async work completes.
  late final WebViewController _controller;
  bool _isLoading = true;
  double _progress = 0;
  bool _isPickerActive = false;
  List<String> _userRules = [];
  late String _siteKey;
  late AnimationController _bannerAnimController;
  late Animation<double> _bannerAnim;

  // ─── SharedPreferences helpers ────────────────────────────────────────────

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

  // ─── CSS injection ────────────────────────────────────────────────────────
  // Uses json.encode() to produce a safe JS string literal — handles quotes,
  // backslashes, and other special characters in selectors gracefully.
  // Clears previous interval via window.__piAdblockTimer to avoid accumulation.

  void _applyAllBlockRules() {
    if (_userRules.isEmpty) return;

    // Build the full CSS text and safely encode it as a JS string literal.
    final cssContent =
        '${_userRules.join(', ')} { display: none !important; visibility: hidden !important; opacity: 0 !important; max-height: 0 !important; overflow: hidden !important; }';
    final safeCSS = json.encode(cssContent); // produces "..." with escaping

    _controller.runJavaScript('''
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
      if (sel) AdBlockerChannel.postMessage(sel);
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
        if (sel) AdBlockerChannel.postMessage(sel);
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
    setState(() => _isPickerActive = !_isPickerActive);
    if (_isPickerActive) {
      _bannerAnimController.forward();
      _controller.runJavaScript(_pickerJS);
    } else {
      _bannerAnimController.reverse();
      _controller.runJavaScript(_disablePickerJS);
    }
  }

  void _disablePicker() {
    if (_isPickerActive) {
      setState(() => _isPickerActive = false);
      _bannerAnimController.reverse();
      _controller.runJavaScript(_disablePickerJS);
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.block, color: Colors.deepOrange.shade700, size: 22),
            const SizedBox(width: 8),
            const Text('Block this element?',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('CSS Selector:',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: SelectableText(
                selector,
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Color(0xFF1565C0)),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
                'This element will be hidden every time you visit this site.',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
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
          _controller.runJavaScript('''
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

    // ⚠️ Initialize controller SYNCHRONOUSLY so build() never sees it unready.
    _controller = WebViewController()
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
          },
          onWebResourceError: (WebResourceError error) {},
        ),
      )
      ..loadRequest(Uri.parse(widget.url));

    // Load persisted rules in background; _applyAllBlockRules() inside
    // _loadUserRules() will re-inject CSS if the page finishes first.
    _loadUserRules();
  }

  @override
  void dispose() {
    _bannerAnimController.dispose();
    super.dispose();
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;
        if (await _controller.canGoBack()) {
          _controller.goBack();
        } else {
          if (!context.mounted) return;
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Text(widget.name,
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          actions: [
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
            WebViewWidget(controller: _controller),
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
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Ad Blocker Bottom Sheet Panel ───────────────────────────────────────────

class _AdBlockerPanel extends StatelessWidget {
  final bool isPickerActive;
  final List<String> userRules;
  final VoidCallback onTogglePicker;
  final Future<void> Function(String) onDeleteRule;
  final VoidCallback onClearAll;

  const _AdBlockerPanel({
    required this.isPickerActive,
    required this.userRules,
    required this.onTogglePicker,
    required this.onDeleteRule,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
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
                        color: Colors.deepOrange.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.shield,
                          color: Colors.deepOrange.shade700, size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Ad Blocker',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          Text('Block unwanted elements on this site',
                              style:
                                  TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
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
                            : [Colors.grey.shade100, Colors.grey.shade50],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isPickerActive
                            ? Colors.deepOrange.shade400
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
                                      : Colors.black87,
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
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14),
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
              const Divider(height: 1),
              // Rules list
              Expanded(
                child: userRules.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.block,
                                size: 48, color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            Text('No custom rules yet',
                                style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 15)),
                            const SizedBox(height: 4),
                            Text('Use the element picker to block ads',
                                style: TextStyle(
                                    color: Colors.grey.shade400,
                                    fontSize: 12)),
                          ],
                        ),
                      )
                    : ListView.separated(
                        controller: scrollCtrl,
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
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border:
                                  Border.all(color: Colors.grey.shade200),
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
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      color: Color(0xFF1565C0),
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
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
            ],
          ),
        );
      },
    );
  }
}
