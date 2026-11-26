import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/custom_app_bar.dart';
import '../widgets/loading_widget.dart';

/// Page colour treatments offered by the reader.
///
/// The chrome colours travel with the treatment so the app bar, search field,
/// scrubber and floating controls stay legible against the tinted page.
enum _PdfColorMode {
  normal,
  night,
  sepia;

  String get label => switch (this) {
        _PdfColorMode.normal => 'Normal',
        _PdfColorMode.night => 'Night',
        _PdfColorMode.sepia => 'Sepia',
      };

  IconData get icon => switch (this) {
        _PdfColorMode.normal => Icons.light_mode_rounded,
        _PdfColorMode.night => Icons.dark_mode_rounded,
        _PdfColorMode.sepia => Icons.local_cafe_rounded,
      };

  String get tooltip => switch (this) {
        _PdfColorMode.normal => 'Normal colours',
        _PdfColorMode.night => 'Inverted night colours',
        _PdfColorMode.sepia => 'Warm, higher-contrast sepia',
      };

  bool get isDark => this == _PdfColorMode.night;

  Color get scaffoldBackground => switch (this) {
        _PdfColorMode.normal => const Color(0xFFE8EBEF),
        _PdfColorMode.night => const Color(0xFF121212),
        _PdfColorMode.sepia => const Color(0xFFE7D9BE),
      };

  Color get surface => switch (this) {
        _PdfColorMode.normal => Colors.white,
        _PdfColorMode.night => const Color(0xFF1E1E1E),
        _PdfColorMode.sepia => const Color(0xFFF7EFDD),
      };

  Color get fieldFill => switch (this) {
        _PdfColorMode.normal => const Color(0xFFF2F4F7),
        _PdfColorMode.night => const Color(0xFF2A2A2A),
        _PdfColorMode.sepia => const Color(0xFFEDE0C6),
      };

  Color get foreground => switch (this) {
        _PdfColorMode.normal => Colors.black87,
        _PdfColorMode.night => Colors.white,
        _PdfColorMode.sepia => const Color(0xFF4A3B2A),
      };

  Color get subtitle => switch (this) {
        _PdfColorMode.normal => Colors.black54,
        _PdfColorMode.night => Colors.white60,
        _PdfColorMode.sepia => const Color(0xB34A3B2A),
      };

  Color get border => switch (this) {
        _PdfColorMode.normal => const Color(0x0F000000),
        _PdfColorMode.night => const Color(0x1AFFFFFF),
        _PdfColorMode.sepia => const Color(0x2E4A3B2A),
      };

  Color get track => switch (this) {
        _PdfColorMode.normal => const Color(0x1A000000),
        _PdfColorMode.night => const Color(0x38FFFFFF),
        _PdfColorMode.sepia => const Color(0x2E4A3B2A),
      };

  Color get thumbBorder => switch (this) {
        _PdfColorMode.normal => const Color(0xD9FFFFFF),
        _PdfColorMode.night => const Color(0x47FFFFFF),
        _PdfColorMode.sepia => const Color(0xD9FFF3DF),
      };
}

/// An in-app PDF viewer for local and online PDFs.
///
/// This PDFium-based viewer is built on `pdfrx` and is shared by every
/// supported platform. It provides continuous scrolling, pinch/scroll zoom,
/// page navigation, full-text search, bookmarks and lazy page rendering for
/// long textbooks.
class InAppPdfViewerPage extends StatefulWidget {
  const InAppPdfViewerPage({
    super.key,
    this.filePath,
    this.pdfUrl,
    this.password,
    required this.title,
  }) : assert(
          filePath != null || pdfUrl != null,
          'Either filePath or pdfUrl must be provided.',
        );

  /// A local PDF file. Takes precedence over [pdfUrl] when both are set.
  final String? filePath;

  /// A remote PDF, or a Google Drive share/download link.
  final String? pdfUrl;

  /// An optional password supplied by the caller. If it is not valid, the
  /// viewer asks the user for a password.
  final String? password;

  final String title;

  @override
  State<InAppPdfViewerPage> createState() => _InAppPdfViewerPageState();
}

class _InAppPdfViewerPageState extends State<InAppPdfViewerPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const ColorFilter _nightModeFilter = ColorFilter.matrix([
    -1,
    0,
    0,
    0,
    255,
    0,
    -1,
    0,
    0,
    255,
    0,
    0,
    -1,
    0,
    255,
    0,
    0,
    0,
    1,
    0,
  ]);

  /// Maps luminance onto a warm paper/ink ramp (#F4ECD8 paper, #3B2F2A ink)
  /// so sepia keeps strong text contrast instead of merely tinting the page.
  static const ColorFilter _sepiaModeFilter = ColorFilter.matrix([
    0.217,
    0.426,
    0.083,
    0,
    59,
    0.222,
    0.435,
    0.085,
    0,
    47,
    0.204,
    0.401,
    0.078,
    0,
    42,
    0,
    0,
    0,
    1,
    0,
  ]);

  final PdfViewerController _controller = PdfViewerController();
  late final PdfTextSearcher _searcher;
  late final List<PdfViewerPagePaintCallback> _pagePaintCallbacks;
  late final VoidCallback _removeSearchListener;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  /// Turns a silently blank document into an actionable error + retry.
  Timer? _readyWatchdog;

  Uint8List? _bytes;
  bool _loading = true;
  double? _downloadProgress;
  String? _error;

  int? _totalPages;
  int _currentPage = 1;
  bool _ready = false;
  bool _textSelectionEnabled = false;
  bool _askingPassword = false;
  _PdfColorMode _colorMode = _PdfColorMode.normal;
  bool _isFullscreen = false;
  bool _appBarVisible = true;
  bool _searchVisible = false;

  // Raw pointer tracking for tap-to-toggle chrome. A Listener is used instead
  // of a GestureDetector so pdfrx keeps receiving its own gestures.
  int _documentPointers = 0;
  Offset? _documentTapStart;
  DateTime? _documentTapStartTime;
  bool _documentTapMoved = false;
  bool _searchPending = false;
  String _lastQuery = '';
  String? _initialPassword;

  late final Ticker _autoScrollTicker;
  bool _autoScrollEnabled = false;
  bool _autoScrollPaused = false;
  int _autoScrollSpeedIndex = 1;
  Duration _autoScrollLastElapsed = Duration.zero;

  static const List<String> _autoScrollSpeedLabels = [
    '0.5×',
    '1×',
    '1.5×',
    '2×',
    '3×',
  ];
  static const List<double> _autoScrollSpeedValues = [
    0.5,
    1,
    1.5,
    2,
    3,
  ];
  static const double _autoScrollBasePixelsPerSecond = 30;

  final Set<int> _bookmarkedPages = <int>{};
  SharedPreferences? _prefs;

  // Changing this gives pdfrx a fresh source name, which forces it to retry a
  // document that previously failed to parse.
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialPassword = widget.password;
    _searcher = PdfTextSearcher(_controller);
    _pagePaintCallbacks = [
      _searcher.pageTextMatchPaintCallback,
    ];
    _removeSearchListener = _searcher.addListener(_handleSearchChanged);
    _autoScrollTicker = createTicker(_handleAutoScrollTick);
    _loadBookmarks();
    _load(initial: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_isFullscreen) {
      // Never leave the system UI hidden after the reader is closed.
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _readyWatchdog?.cancel();
    _autoScrollTicker.dispose();
    _removeSearchListener();
    _searcher.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android can restore the system bars after the app returns from the
    // background; re-apply immersive mode so fullscreen survives the trip.
    if (state == AppLifecycleState.resumed && _isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  ColorFilter? get _activeColorFilter => switch (_colorMode) {
        _PdfColorMode.normal => null,
        _PdfColorMode.night => _nightModeFilter,
        _PdfColorMode.sepia => _sepiaModeFilter,
      };

  /// The search app bar must stay visible while typing, even in fullscreen.
  bool get _showAppBar => _searchVisible || (!_isFullscreen && _appBarVisible);

  /// Sepia maps every colour onto a warm luminance ramp, so the usual yellow
  /// highlight would blend into the paper. Use a darker amber instead.
  Color get _matchHighlightColor => _colorMode == _PdfColorMode.sepia
      ? const Color(0x99B45309)
      : Colors.yellow.withOpacity(0.55);

  Color get _activeMatchHighlightColor => _colorMode == _PdfColorMode.sepia
      ? const Color(0xCC92400E)
      : Colors.orange.withOpacity(0.65);

  String get _autoScrollSpeedLabel =>
      _autoScrollSpeedLabels[_autoScrollSpeedIndex];

  String get _sourceName {
    final base = widget.filePath ?? widget.pdfUrl ?? widget.title;
    return '$base#viewer=$_loadGeneration';
  }

  String get _bookmarkKey =>
      'bookmarks_${(widget.filePath ?? widget.pdfUrl ?? widget.title).hashCode}';

  Future<void> _load({bool initial = false}) async {
    _resetSearch();
    _cancelReadyWatchdog();
    if (_autoScrollEnabled) _stopAutoScroll();

    final generation = _loadGeneration + 1;
    if (initial) {
      _loadGeneration = generation;
    } else {
      setState(() {
        _loadGeneration = generation;
        _loading = true;
        _error = null;
        _downloadProgress = null;
        _bytes = null;
        _ready = false;
        _totalPages = null;
        _currentPage = 1;
      });
    }

    try {
      final Uint8List bytes;
      if (widget.filePath != null) {
        final file = File(widget.filePath!);
        if (!await file.exists()) {
          throw const _PdfViewerException(
            'The PDF file could not be found on this device.',
          );
        }
        bytes = await file.readAsBytes();
      } else {
        bytes = await _downloadPdf(widget.pdfUrl!);
      }

      if (!_looksLikePdf(bytes)) {
        throw _PdfViewerException(
          widget.filePath != null
              ? 'This file is not a valid PDF.'
              : 'The link did not return a PDF file. Try opening it in a browser.',
        );
      }
      if (!mounted || generation != _loadGeneration) return;

      setState(() {
        _bytes = bytes;
        _loading = false;
        _error = null;
      });
      _startReadyWatchdog(generation);
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error = e is _PdfViewerException
            ? e.message
            : widget.filePath != null
                ? 'Could not open the PDF. It may be damaged or password protected.'
                : 'Could not download the PDF. Check your connection and try again.';
      });
    }
  }

  void _startReadyWatchdog(int generation) {
    _readyWatchdog?.cancel();
    _readyWatchdog = Timer(const Duration(seconds: 20), () {
      if (!mounted ||
          generation != _loadGeneration ||
          _ready ||
          _bytes == null) {
        return;
      }
      if (_askingPassword) {
        // The reader is waiting for the user; give them more time.
        _startReadyWatchdog(generation);
        return;
      }
      // Some damaged or unsupported PDFs make PDFium fail silently, leaving
      // the viewer blank. Surface a retry instead of a white screen.
      setState(() {
        _error =
            'This PDF could not be displayed. Try opening it in another app.';
      });
    });
  }

  void _cancelReadyWatchdog() {
    _readyWatchdog?.cancel();
    _readyWatchdog = null;
  }

  Future<Uint8List> _downloadPdf(String url) async {
    final client = http.Client();
    try {
      final original = Uri.parse(_normaliseUrl(url));
      final bytes = await _downloadBytes(original, client);
      if (_looksLikePdf(bytes)) return bytes;

      // Large Google Drive files answer with an HTML "virus scan" page instead
      // of the PDF. Follow its confirmation form once and use the real file.
      final confirmationUrl = _extractDriveConfirmationUrl(bytes, original);
      if (confirmationUrl != null) {
        if (mounted) setState(() => _downloadProgress = null);
        return _downloadBytes(confirmationUrl, client);
      }
      return bytes;
    } finally {
      client.close();
    }
  }

  Future<Uint8List> _downloadBytes(Uri uri, http.Client client) async {
    final request = http.Request('GET', uri);
    request.headers['User-Agent'] = 'Pi-QBank PDF Viewer';
    final response = await client.send(request);

    if (response.statusCode != 200) {
      throw _PdfViewerException(
        'Could not download the PDF (HTTP ${response.statusCode}).',
      );
    }

    final total = response.contentLength ?? 0;
    var received = 0;
    final builder = BytesBuilder(copy: false);

    await for (final chunk in response.stream) {
      builder.add(chunk);
      received += chunk.length;
      if (total > 0 && mounted) {
        final progress = received / total;
        final previous = _downloadProgress;
        if (previous == null || progress - previous >= 0.01) {
          setState(() => _downloadProgress = progress);
        }
      }
    }

    return builder.takeBytes();
  }

  /// Turn the common Google Drive share links into direct downloads. The
  /// `/file/d/<id>/view` form returns an HTML page, which PDFium cannot read.
  String _normaliseUrl(String url) {
    final uri = Uri.parse(url);
    if (uri.host != 'drive.google.com') return url;

    final id = uri.queryParameters['id'] ??
        RegExp(r'^/file/d/([^/]+)').firstMatch(uri.path)?.group(1);
    if (id != null && id.isNotEmpty) {
      return 'https://drive.google.com/uc?export=download&id=$id';
    }
    return url;
  }

  Uri? _extractDriveConfirmationUrl(Uint8List bytes, Uri original) {
    if (original.host != 'drive.google.com' &&
        original.host != 'drive.usercontent.google.com') {
      return null;
    }

    final html = utf8.decode(bytes, allowMalformed: true);
    final form = RegExp(
      r'<form[^>]+action="([^"]+)"[^>]*>(.*?)</form>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(html);
    if (form == null) return null;

    final action = form.group(1);
    final formBody = form.group(2);
    if (action == null || formBody == null) return null;

    final params = <String, String>{};
    for (final input in RegExp(
      r'<input[^>]*>',
      caseSensitive: false,
    ).allMatches(formBody)) {
      final tag = input.group(0);
      if (tag == null) continue;
      final name = RegExp(
        r'name="([^"]+)"',
        caseSensitive: false,
      ).firstMatch(tag)?.group(1);
      final value = RegExp(
        r'value="([^"]*)"',
        caseSensitive: false,
      ).firstMatch(tag)?.group(1);
      if (name != null && value != null) {
        params[name] = _decodeHtmlAttribute(value);
      }
    }

    if (params['id'] == null) return null;

    final base = original.resolve(_decodeHtmlAttribute(action));
    return base.replace(queryParameters: {
      ...base.queryParameters,
      ...params,
      'export': params['export'] ?? 'download',
    });
  }

  String _decodeHtmlAttribute(String value) => value
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");

  bool _looksLikePdf(Uint8List bytes) {
    final limit = bytes.length < 1024 ? bytes.length : 1024;
    final header = latin1.decode(bytes.sublist(0, limit), allowInvalid: true);
    return header.contains('%PDF-');
  }

  Future<void> _loadBookmarks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;
      final saved = prefs.getStringList(_bookmarkKey) ?? const <String>[];
      if (!mounted) return;
      setState(() {
        _bookmarkedPages
          ..clear()
          ..addAll(saved.map(int.tryParse).whereType<int>());
      });
    } catch (_) {
      // Bookmarks are an optional convenience; storage errors must not stop
      // the document from opening.
    }
  }

  Future<void> _saveBookmarks() async {
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      _prefs = prefs;
      final pages = _bookmarkedPages.toList()..sort();
      await prefs.setStringList(
        _bookmarkKey,
        pages.map((page) => '$page').toList(),
      );
    } catch (_) {
      // Same as above: failing to persist a bookmark is not fatal.
    }
  }

  Future<void> _toggleBookmark() async {
    if (!_ready || (_totalPages ?? 0) == 0) {
      _showMessage('The document is still loading.');
      return;
    }
    if (_autoScrollEnabled) _stopAutoScroll();

    final page = _currentPage;
    final adding = !_bookmarkedPages.contains(page);
    setState(() {
      if (adding) {
        _bookmarkedPages.add(page);
      } else {
        _bookmarkedPages.remove(page);
      }
    });
    await _saveBookmarks();

    if (!mounted) return;
    if (adding) {
      _showMessage(
        'Page $page bookmarked',
        icon: Icons.bookmark_added_rounded,
        color: Colors.blue.shade700,
      );
    } else {
      _showMessage(
        'Bookmark removed',
        icon: Icons.bookmark_remove_rounded,
        color: Colors.grey.shade800,
      );
    }
  }

  Future<void> _showBookmarksList() async {
    var pages = _bookmarkedPages.toList()..sort();
    if (!mounted) return;

    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: _colorMode.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        final foreground = _colorMode.foreground;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(top: 10, bottom: 8),
                    decoration: BoxDecoration(
                      color: foreground.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
                    child: Row(
                      children: [
                        Icon(Icons.bookmarks_rounded, color: foreground),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Bookmarks',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: foreground,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          icon: Icon(Icons.close_rounded, color: foreground),
                          onPressed: () => Navigator.of(sheetContext).pop(),
                        ),
                      ],
                    ),
                  ),
                  if (pages.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                      child: Text(
                        'No bookmarks yet.\nTap the bookmark icon to save the current page.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: foreground.withOpacity(0.65),
                          height: 1.4,
                        ),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.only(bottom: 12),
                        itemCount: pages.length,
                        itemBuilder: (context, index) {
                          final page = pages[index];
                          final current = page == _currentPage;
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              Icons.bookmark_rounded,
                              color: current
                                  ? Theme.of(context).colorScheme.primary
                                  : foreground.withOpacity(0.65),
                            ),
                            title: Text(
                              'Page $page',
                              style: TextStyle(
                                color: foreground,
                                fontWeight:
                                    current ? FontWeight.w700 : FontWeight.w500,
                              ),
                            ),
                            subtitle: current
                                ? Text(
                                    'Current page',
                                    style: TextStyle(
                                      color: foreground.withOpacity(0.6),
                                      fontSize: 12,
                                    ),
                                  )
                                : null,
                            trailing: IconButton(
                              tooltip: 'Remove bookmark',
                              icon: const Icon(Icons.delete_outline_rounded),
                              color: Colors.red.shade400,
                              onPressed: () async {
                                setState(() => _bookmarkedPages.remove(page));
                                setSheetState(
                                  () =>
                                      pages = _bookmarkedPages.toList()..sort(),
                                );
                                await _saveBookmarks();
                              },
                            ),
                            onTap: () => Navigator.of(sheetContext).pop(page),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );

    if (selected != null && mounted) await _goToPage(selected);
  }

  Future<void> _sharePdf() async {
    try {
      if (widget.filePath != null) {
        await Share.shareXFiles(
          [XFile(widget.filePath!)],
          subject: widget.title,
          text: 'Sharing PDF: ${widget.title}',
        );
      } else if (widget.pdfUrl != null) {
        await Share.share(widget.pdfUrl!, subject: widget.title);
      }
    } catch (_) {
      if (mounted) {
        _showMessage('Sharing is not available on this device.');
      }
    }
  }

  void _handleViewerReady(
    PdfDocument document,
    PdfViewerController controller,
  ) {
    if (!mounted) return;
    _cancelReadyWatchdog();
    final total = document.pages.length;
    if (total == 0) {
      setState(() {
        _ready = true;
        _totalPages = 0;
        _currentPage = 1;
      });
      return;
    }
    final page = (controller.pageNumber ?? 1).clamp(1, total);
    setState(() {
      _ready = true;
      _totalPages = total;
      _currentPage = page;
    });
  }

  void _handleDocumentChanged(PdfDocument? document) {
    if (!mounted) return;
    final pages = document?.pages.length;
    if (pages == null) {
      if (_autoScrollEnabled) _stopAutoScroll();
      if (_searchVisible || _searcher.matches.isNotEmpty) {
        _resetSearch();
      }
      if (_totalPages != null || _ready) {
        setState(() {
          _totalPages = null;
          _ready = false;
        });
      }
      return;
    }
    _cancelReadyWatchdog();
    if (pages == _totalPages) return;

    setState(() {
      _totalPages = pages;
      if (pages > 0) {
        _currentPage = _currentPage.clamp(1, pages);
      } else {
        _currentPage = 1;
      }
    });
  }

  void _handlePageChanged(int? pageNumber) {
    if (!mounted || pageNumber == null) return;
    final total = _totalPages;
    if (total != null && total < 1) return;
    final page = total == null ? pageNumber : pageNumber.clamp(1, total);
    if (page == _currentPage) return;
    setState(() => _currentPage = page);
  }

  Future<String?> _askForPassword() async {
    if (_initialPassword != null) {
      final password = _initialPassword;
      _initialPassword = null;
      return password;
    }
    if (_askingPassword || !mounted) return null;
    _askingPassword = true;

    final textController = TextEditingController();
    try {
      final password = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Password required'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('This PDF is password protected.'),
              const SizedBox(height: 16),
              TextField(
                controller: textController,
                autofocus: true,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (value) {
                  if (value.isNotEmpty) {
                    Navigator.of(dialogContext).pop(value);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (textController.text.isNotEmpty) {
                  Navigator.of(dialogContext).pop(textController.text);
                }
              },
              child: const Text('Open'),
            ),
          ],
        ),
      );
      return password;
    } finally {
      textController.dispose();
      _askingPassword = false;
    }
  }

  Future<void> _goToPage(int page) async {
    if (_autoScrollEnabled) _stopAutoScroll();
    final total = _totalPages;
    if (!_ready || total == null || total == 0) return;
    final target = page.clamp(1, total);
    await _controller.goToPage(
      pageNumber: target,
      duration: const Duration(milliseconds: 260),
    );
  }

  Future<void> _previousPage() => _goToPage(_currentPage - 1);

  Future<void> _nextPage() => _goToPage(_currentPage + 1);

  Future<void> _firstPage() => _goToPage(1);

  Future<void> _lastPage() async {
    final total = _totalPages;
    if (total == null) return;
    await _goToPage(total);
  }

  Future<void> _zoomIn() async {
    if (_autoScrollEnabled) _stopAutoScroll();
    if (!_ready) return;
    await _controller.zoomUp();
  }

  Future<void> _zoomOut() async {
    if (_autoScrollEnabled) _stopAutoScroll();
    if (!_ready) return;
    await _controller.zoomDown();
  }

  Future<void> _fitWidth() async {
    if (_autoScrollEnabled) _stopAutoScroll();
    if (!_ready) return;
    final total = _totalPages ?? _controller.pageCount;
    if (total < 1) return;
    final page = (_controller.pageNumber ?? _currentPage).clamp(1, total);
    await _controller.goTo(
      _controller.calcMatrixFitWidthForPage(pageNumber: page),
      duration: const Duration(milliseconds: 240),
    );
  }

  Future<void> _fitPage() async {
    if (_autoScrollEnabled) _stopAutoScroll();
    if (!_ready) return;
    final total = _totalPages ?? _controller.pageCount;
    if (total < 1) return;
    final page = (_controller.pageNumber ?? _currentPage).clamp(1, total);
    await _controller.goTo(
      _controller.calcMatrixForFit(pageNumber: page),
      duration: const Duration(milliseconds: 240),
    );
  }

  Future<void> _actualSize() async {
    if (_autoScrollEnabled) _stopAutoScroll();
    if (!_ready) return;
    final total = _totalPages ?? _controller.pageCount;
    if (total < 1) return;
    final page = (_controller.pageNumber ?? _currentPage).clamp(1, total);
    final pageRect = _controller.layout.pageLayouts[page - 1];
    await _controller.goTo(
      _controller.calcMatrixFor(pageRect.center, zoom: 1),
      duration: const Duration(milliseconds: 220),
    );
  }

  Future<void> _scrollBy(double dx, double dy) async {
    if (_autoScrollEnabled) _stopAutoScroll();
    if (!_ready) return;
    final matrix = _controller.value.clone()..translate(dx, dy);
    await _controller.goTo(
      _controller.makeMatrixInSafeRange(matrix),
      duration: const Duration(milliseconds: 110),
    );
  }

  void _toggleAutoScroll() {
    if (_autoScrollEnabled) {
      _stopAutoScroll();
      return;
    }
    _startAutoScroll();
  }

  void _startAutoScroll() {
    if (_autoScrollEnabled) return;
    if (!_ready) {
      _showMessage('The document is still loading.');
      return;
    }

    final viewRect = _controller.visibleRect;
    final documentSize = _controller.documentSize;
    if (documentSize.height - viewRect.height <= 1) {
      _showMessage('This document fits on screen; nothing to auto-scroll.');
      return;
    }
    if (viewRect.bottom >= documentSize.height - 1) {
      _showMessage(
        'You are at the end of the document.',
        icon: Icons.info_outline_rounded,
        color: Colors.orange.shade700,
      );
      return;
    }

    _autoScrollLastElapsed = Duration.zero;
    setState(() {
      _autoScrollEnabled = true;
      _autoScrollPaused = false;
    });
    _autoScrollTicker.start();
    HapticFeedback.mediumImpact();
  }

  void _pauseAutoScroll() {
    if (!_autoScrollEnabled || _autoScrollPaused) return;
    _autoScrollTicker.stop();
    if (mounted) {
      setState(() => _autoScrollPaused = true);
    }
    HapticFeedback.selectionClick();
  }

  void _resumeAutoScroll() {
    if (!_autoScrollEnabled || !_autoScrollPaused) return;
    _autoScrollLastElapsed = Duration.zero;
    setState(() => _autoScrollPaused = false);
    _autoScrollTicker.start();
    HapticFeedback.selectionClick();
  }

  void _toggleAutoScrollPause() {
    if (_autoScrollPaused) {
      _resumeAutoScroll();
    } else {
      _pauseAutoScroll();
    }
  }

  void _stopAutoScroll() {
    if (!_autoScrollEnabled) return;
    _autoScrollTicker.stop();
    if (mounted) {
      setState(() {
        _autoScrollEnabled = false;
        _autoScrollPaused = false;
      });
    }
  }

  void _handleAutoScrollTick(Duration elapsed) {
    if (!_autoScrollEnabled || _autoScrollPaused) return;
    if (!_ready) {
      _stopAutoScroll();
      return;
    }

    final rawDeltaSeconds = (elapsed - _autoScrollLastElapsed).inMicroseconds /
        Duration.microsecondsPerSecond;
    _autoScrollLastElapsed = elapsed;
    if (rawDeltaSeconds <= 0) return;
    // Keep a long frame (or a trip to the background) from making the page
    // jump a long way in one step.
    final deltaSeconds = math.min(rawDeltaSeconds, 0.1);

    final pixels = _autoScrollBasePixelsPerSecond *
        _autoScrollSpeedValues[_autoScrollSpeedIndex] *
        deltaSeconds;
    final before = _controller.visibleRect;
    final documentHeight = _controller.documentSize.height;
    final matrix = _controller.value.clone()..translate(0.0, -pixels);
    _controller.value = matrix;
    final after = _controller.visibleRect;

    final reachedEnd = after.bottom >= documentHeight - 1;
    final didNotMove = (after.top - before.top).abs() < 0.01;
    if (reachedEnd || didNotMove) {
      _stopAutoScroll();
      _showMessage(
        'Auto-scroll finished',
        icon: Icons.check_circle_rounded,
        color: Colors.green.shade700,
      );
    }
  }

  void _cycleAutoScrollSpeed() {
    setState(() {
      _autoScrollSpeedIndex =
          (_autoScrollSpeedIndex + 1) % _autoScrollSpeedLabels.length;
    });
    HapticFeedback.selectionClick();
  }

  Future<void> _showGoToPageDialog() async {
    final total = _totalPages;
    if (!_ready || total == null || total < 1) return;

    final textController = TextEditingController(text: '$_currentPage');
    textController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: textController.text.length,
    );

    final page = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Go to page'),
        content: TextField(
          controller: textController,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            hintText: 'Page number',
            helperText: '1 – $total',
          ),
          onSubmitted: (value) {
            final page = int.tryParse(value);
            if (page != null) Navigator.of(dialogContext).pop(page);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final page = int.tryParse(textController.text);
              if (page != null) Navigator.of(dialogContext).pop(page);
            },
            child: const Text('Go'),
          ),
        ],
      ),
    );
    textController.dispose();

    if (!mounted) return;
    if (page == null) return;
    if (page < 1 || page > total) {
      _showMessage('Enter a page number between 1 and $total.');
      return;
    }
    await _goToPage(page);
  }

  void _openSearch() {
    if (!_ready) return;
    if (_autoScrollEnabled) _stopAutoScroll();
    setState(() {
      _searchVisible = true;
      _appBarVisible = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _searchVisible) _searchFocusNode.requestFocus();
    });
  }

  void _closeSearch() {
    _searchFocusNode.unfocus();
    _resetSearch();
  }

  void _resetSearch() {
    final hadSearch = _searchVisible ||
        _searchPending ||
        _searchController.text.isNotEmpty ||
        _searcher.matches.isNotEmpty;

    _lastQuery = '';
    _searchVisible = false;
    _searchPending = false;
    _searcher.resetTextSearch();
    _searchController.clear();

    if (hadSearch && mounted) setState(() {});
  }

  void _handleSearchChanged() {
    if (!mounted) return;

    // A cancelled search can still publish one stale page result: pdfrx
    // checks its session before loading a page, but not after. Clear it so
    // highlights cannot reappear after the search bar has been closed.
    if (!_searchVisible && _searchController.text.trim().isEmpty) {
      if (_searcher.matches.isNotEmpty) {
        _searcher.resetTextSearch();
      }
      return;
    }

    final wasPending = _searchPending;
    if (_searcher.matches.isNotEmpty || !_searcher.isSearching) {
      _searchPending = false;
    }
    if (_searchVisible || wasPending != _searchPending) {
      setState(() {});
    }
  }

  Future<void> _goToNextMatch() async {
    if (!_ready || _searcher.matches.isEmpty) return;
    if (_autoScrollEnabled) _stopAutoScroll();
    await _searcher.goToNextMatch();
    if (mounted) setState(() {});
  }

  Future<void> _goToPrevMatch() async {
    if (!_ready || _searcher.matches.isEmpty) return;
    if (_autoScrollEnabled) _stopAutoScroll();
    await _searcher.goToPrevMatch();
    if (mounted) setState(() {});
  }

  void _onSearchChanged(String value) {
    if (!_ready) return;
    final query = value.trim();

    if (query.isEmpty) {
      _lastQuery = '';
      _searcher.resetTextSearch();
      setState(() => _searchPending = false);
      return;
    }

    if (query == _lastQuery) return;

    _lastQuery = query;
    _searcher.resetTextSearch();
    setState(() => _searchPending = true);
    _searcher.startTextSearch(query, caseInsensitive: true);
  }

  void _handleEscape() {
    if (_searchVisible) {
      _closeSearch();
      return;
    }
    if (_isFullscreen) _exitFullscreen();
  }

  /// Enters or leaves distraction-free reading.
  ///
  /// On mobile this also hides the status and navigation bars; on desktop it
  /// hides the in-app chrome, which is as close to fullscreen as the platform
  /// allows without a window-management plugin.
  void _toggleFullscreen() {
    final next = !_isFullscreen;
    setState(() {
      _isFullscreen = next;
      // Returning from fullscreen should always bring the chrome back.
      if (!next) _appBarVisible = true;
    });

    if (next) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    HapticFeedback.selectionClick();
  }

  void _exitFullscreen() {
    if (!_isFullscreen) return;
    _toggleFullscreen();
  }

  void _setColorMode(_PdfColorMode mode) {
    if (mode == _colorMode) return;
    setState(() => _colorMode = mode);
    HapticFeedback.selectionClick();
  }

  void _handleDocumentPointerDown(PointerDownEvent event) {
    _documentPointers++;
    if (_documentPointers > 1) {
      // Pinch/zoom and multi-touch selection are not taps.
      _documentTapMoved = true;
      return;
    }
    _documentTapStart = event.position;
    _documentTapStartTime = DateTime.now();
    _documentTapMoved = false;
  }

  void _handleDocumentPointerMove(PointerMoveEvent event) {
    final start = _documentTapStart;
    if (start == null || _documentTapMoved) return;
    if ((event.position - start).distance > 10) {
      _documentTapMoved = true;
    }
  }

  void _handleDocumentPointerUp(PointerUpEvent event) {
    _documentPointers = math.max(0, _documentPointers - 1);
    if (_documentPointers > 0) return;

    final start = _documentTapStart;
    final startedAt = _documentTapStartTime;
    final moved = _documentTapMoved;
    _documentTapStart = null;
    _documentTapStartTime = null;
    _documentTapMoved = false;

    if (start == null || startedAt == null || moved) return;
    if ((event.position - start).distance > 10) return;
    if (DateTime.now().difference(startedAt) >
        const Duration(milliseconds: 350)) {
      return;
    }
    _toggleAppBar();
  }

  void _handleDocumentPointerCancel(PointerCancelEvent event) {
    _documentPointers = math.max(0, _documentPointers - 1);
    if (_documentPointers == 0) {
      _documentTapStart = null;
      _documentTapStartTime = null;
      _documentTapMoved = false;
    }
  }

  void _toggleAppBar() {
    // Search needs the app bar, and fullscreen already hides it on purpose.
    if (_searchVisible || _isFullscreen) return;
    setState(() => _appBarVisible = !_appBarVisible);
  }

  Future<void> _openExternally() async {
    try {
      if (widget.filePath != null) {
        final result = await OpenFile.open(widget.filePath!);
        if (result.type == ResultType.done) return;
      } else if (widget.pdfUrl != null) {
        final uri = Uri.parse(widget.pdfUrl!);
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          return;
        }
      }
    } catch (_) {
      // Fall through to the message below.
    }

    if (!mounted) return;
    _showMessage('Could not open the PDF in another application.');
  }

  void _retryViewer() {
    _resetSearch();
    if (_autoScrollEnabled) _stopAutoScroll();
    setState(() {
      _loadGeneration++;
      _ready = false;
      _totalPages = null;
      _currentPage = 1;
    });
  }

  void _showMessage(
    String message, {
    IconData? icon,
    Color? color,
  }) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 10),
              ],
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.arrowLeft): _previousPage,
        const SingleActivator(LogicalKeyboardKey.arrowRight): _nextPage,
        const SingleActivator(LogicalKeyboardKey.pageUp): _previousPage,
        const SingleActivator(LogicalKeyboardKey.pageDown): _nextPage,
        const SingleActivator(LogicalKeyboardKey.home): _firstPage,
        const SingleActivator(LogicalKeyboardKey.end): _lastPage,
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _scrollBy(0, -48),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _scrollBy(0, 48),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _openSearch,
        const SingleActivator(LogicalKeyboardKey.f11): _toggleFullscreen,
        const SingleActivator(LogicalKeyboardKey.escape): _handleEscape,
        const SingleActivator(LogicalKeyboardKey.equal, control: true): _zoomIn,
        const SingleActivator(
          LogicalKeyboardKey.equal,
          control: true,
          shift: true,
        ): _zoomIn,
        const SingleActivator(LogicalKeyboardKey.add, control: true): _zoomIn,
        const SingleActivator(LogicalKeyboardKey.numpadAdd, control: true):
            _zoomIn,
        const SingleActivator(LogicalKeyboardKey.minus, control: true):
            _zoomOut,
        const SingleActivator(LogicalKeyboardKey.numpadSubtract, control: true):
            _zoomOut,
        const SingleActivator(LogicalKeyboardKey.digit0, control: true):
            _fitPage,
        const SingleActivator(LogicalKeyboardKey.digit1, control: true):
            _fitWidth,
        const SingleActivator(LogicalKeyboardKey.digit2, control: true):
            _actualSize,
      },
      child: Focus(
        autofocus: true,
        child: PopScope(
          canPop: !_searchVisible && !_isFullscreen,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            if (_searchVisible) {
              _closeSearch();
            } else if (_isFullscreen) {
              _exitFullscreen();
            }
          },
          child: Scaffold(
            backgroundColor: _colorMode.scaffoldBackground,
            appBar: !_showAppBar
                ? null
                : _searchVisible
                    ? _buildSearchAppBar()
                    : CustomAppBar(
                        title: widget.title,
                        showNotification: false,
                        actions: [
                          IconButton(
                            tooltip: _searchVisible ? 'Close search' : 'Search',
                            icon: Icon(
                              _searchVisible
                                  ? Icons.search_off_rounded
                                  : Icons.search_rounded,
                            ),
                            onPressed: _ready
                                ? (_searchVisible ? _closeSearch : _openSearch)
                                : null,
                          ),
                          IconButton(
                            tooltip: _bookmarkedPages.contains(_currentPage)
                                ? 'Remove bookmark'
                                : 'Bookmark this page',
                            icon: Icon(
                              _bookmarkedPages.contains(_currentPage)
                                  ? Icons.bookmark_rounded
                                  : Icons.bookmark_border_rounded,
                            ),
                            onPressed: _ready && (_totalPages ?? 0) > 0
                                ? _toggleBookmark
                                : null,
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'View options',
                            icon: const Icon(Icons.more_vert_rounded),
                            menuPadding:
                                const EdgeInsets.symmetric(vertical: 6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant
                                    .withOpacity(0.5),
                              ),
                            ),
                            elevation: 14,
                            shadowColor: Colors.black.withOpacity(0.25),
                            surfaceTintColor: Colors.transparent,
                            color: Theme.of(context).colorScheme.surface,
                            constraints: const BoxConstraints(
                              minWidth: 280,
                              maxWidth: 320,
                            ),
                            onSelected: (value) {
                              // Any menu action other than the reading-flow controls
                              // is an explicit interruption of the reading flow.
                              const readingFlowActions = <String>{
                                'autoscroll-toggle',
                                'autoscroll-speed',
                                'fullscreen',
                                'color-normal',
                                'color-night',
                                'color-sepia',
                              };
                              if (_autoScrollEnabled &&
                                  !readingFlowActions.contains(value)) {
                                _stopAutoScroll();
                              }
                              switch (value) {
                                case 'open-external':
                                  _openExternally();
                                case 'goto-page':
                                  _showGoToPageDialog();
                                case 'previous-page':
                                  _previousPage();
                                case 'next-page':
                                  _nextPage();
                                case 'first-page':
                                  _firstPage();
                                case 'last-page':
                                  _lastPage();
                                case 'autoscroll-toggle':
                                  _toggleAutoScroll();
                                case 'autoscroll-speed':
                                  _cycleAutoScrollSpeed();
                                case 'zoom-in':
                                  _zoomIn();
                                case 'zoom-out':
                                  _zoomOut();
                                case 'fit-width':
                                  _fitWidth();
                                case 'fit-page':
                                  _fitPage();
                                case 'actual-size':
                                  _actualSize();
                                case 'fullscreen':
                                  _toggleFullscreen();
                                case 'color-normal':
                                  _setColorMode(_PdfColorMode.normal);
                                case 'color-night':
                                  _setColorMode(_PdfColorMode.night);
                                case 'color-sepia':
                                  _setColorMode(_PdfColorMode.sepia);
                                case 'select-text':
                                  setState(
                                    () => _textSelectionEnabled =
                                        !_textSelectionEnabled,
                                  );
                                case 'bookmarks':
                                  _showBookmarksList();
                                case 'share':
                                  _sharePdf();
                                case 'keyboard-shortcuts':
                                  _showKeyboardShortcuts();
                              }
                            },
                            itemBuilder: (context) {
                              final showShortcuts = !Platform.isAndroid;
                              final canShare = Platform.isAndroid ||
                                  Platform.isMacOS ||
                                  Platform.isWindows;
                              final total = _totalPages;
                              final hasPages =
                                  _ready && total != null && total > 0;
                              final canGoBack = total != null &&
                                  total > 0 &&
                                  _ready &&
                                  _currentPage > 1;
                              final canGoForward = total != null &&
                                  total > 0 &&
                                  _ready &&
                                  _currentPage < total;

                              // ── helpers ────────────────────────────────────────
                              final cs = Theme.of(context).colorScheme;

                              PopupMenuItem<String> item({
                                required String value,
                                required IconData icon,
                                required String label,
                                String? shortcut,
                                bool enabled = true,
                                Color? iconColor,
                                bool active = false,
                              }) {
                                return PopupMenuItem<String>(
                                  value: value,
                                  enabled: enabled,
                                  padding: EdgeInsets.zero,
                                  height: 36,
                                  child: _MenuRow(
                                    icon: icon,
                                    label: label,
                                    shortcut: shortcut,
                                    enabled: enabled,
                                    iconColor: iconColor,
                                    active: active,
                                    activeColor: iconColor ?? cs.primary,
                                  ),
                                );
                              }

                              PopupMenuItem<String> sectionHeader(
                                  String title) {
                                return PopupMenuItem<String>(
                                  enabled: false,
                                  height: 22,
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 6, 16, 0),
                                  child: Text(
                                    title.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.1,
                                      color: cs.onSurface.withOpacity(0.42),
                                    ),
                                  ),
                                );
                              }

                              // Two side-by-side tappable cells in one row
                              PopupMenuItem<String> pairedItem({
                                required IconData icon1,
                                required String label1,
                                required String value1,
                                bool enabled1 = true,
                                required IconData icon2,
                                required String label2,
                                required String value2,
                                bool enabled2 = true,
                                Color? iconColor,
                              }) {
                                return PopupMenuItem<String>(
                                  enabled: false,
                                  padding: EdgeInsets.zero,
                                  height: 44,
                                  child: _PairedMenuRow(
                                    icon1: icon1,
                                    label1: label1,
                                    value1: value1,
                                    enabled1: enabled1,
                                    icon2: icon2,
                                    label2: label2,
                                    value2: value2,
                                    enabled2: enabled2,
                                    iconColor: iconColor ?? cs.primary,
                                  ),
                                );
                              }

                              // Multiple side-by-side tappable cells in a single row
                              PopupMenuItem<String> multiItem({
                                required List<_MenuActionItem> items,
                                Color? iconColor,
                                double height = 54,
                              }) {
                                return PopupMenuItem<String>(
                                  enabled: false,
                                  padding: EdgeInsets.zero,
                                  height: height,
                                  child: _MultiMenuRow(
                                    items: items,
                                    iconColor: iconColor ?? cs.primary,
                                  ),
                                );
                              }

                              PopupMenuDivider divider() =>
                                  const PopupMenuDivider(height: 1);

                              // ── items ───────────────────────────────────────────
                              return [
                                // ── File ───────────────────────────────────────
                                sectionHeader('File'),
                                item(
                                  value: 'open-external',
                                  icon: Icons.open_in_new_rounded,
                                  label: 'Open in another app',
                                  iconColor: const Color(0xFF6366F1),
                                ),
                                if (canShare)
                                  item(
                                    value: 'share',
                                    icon: Icons.share_rounded,
                                    label: 'Share',
                                    iconColor: const Color(0xFF0EA5E9),
                                  ),
                                divider(),

                                // ── Navigation ─────────────────────────────────
                                sectionHeader('Navigation'),
                                item(
                                  value: 'goto-page',
                                  icon: Icons.tag_rounded,
                                  label: 'Go to page…',
                                  shortcut: total == null
                                      ? null
                                      : '$_currentPage / $total',
                                  enabled: hasPages,
                                  iconColor: const Color(0xFF8B5CF6),
                                ),
                                multiItem(
                                  iconColor: const Color(0xFF8B5CF6),
                                  items: [
                                    _MenuActionItem(
                                      icon: Icons.first_page_rounded,
                                      label: 'First',
                                      value: 'first-page',
                                      enabled: canGoBack,
                                      tooltip: 'First page',
                                    ),
                                    _MenuActionItem(
                                      icon: Icons.arrow_back_ios_new_rounded,
                                      label: 'Previous',
                                      value: 'previous-page',
                                      enabled: canGoBack,
                                      tooltip: 'Previous page',
                                    ),
                                    _MenuActionItem(
                                      icon: Icons.arrow_forward_ios_rounded,
                                      label: 'Next',
                                      value: 'next-page',
                                      enabled: canGoForward,
                                      tooltip: 'Next page',
                                    ),
                                    _MenuActionItem(
                                      icon: Icons.last_page_rounded,
                                      label: 'Last',
                                      value: 'last-page',
                                      enabled: canGoForward,
                                      tooltip: 'Last page',
                                    ),
                                  ],
                                ),
                                divider(),

                                // ── Auto-scroll ────────────────────────────────
                                sectionHeader('Auto-scroll'),
                                item(
                                  value: 'autoscroll-toggle',
                                  icon: _autoScrollEnabled
                                      ? Icons.stop_rounded
                                      : Icons.play_arrow_rounded,
                                  label: _autoScrollEnabled
                                      ? 'Stop auto-scroll'
                                      : 'Start auto-scroll',
                                  shortcut: _autoScrollPaused ? 'PAUSED' : null,
                                  enabled: hasPages,
                                  iconColor: const Color(0xFF10B981),
                                  active: _autoScrollEnabled,
                                ),
                                item(
                                  value: 'autoscroll-speed',
                                  icon: Icons.speed_rounded,
                                  label: 'Auto-scroll speed',
                                  shortcut: _autoScrollSpeedLabel,
                                  enabled: hasPages,
                                  iconColor: const Color(0xFF10B981),
                                ),
                                divider(),

                                // ── Zoom ───────────────────────────────────────
                                sectionHeader('Zoom'),
                                pairedItem(
                                  icon1: Icons.zoom_in_rounded,
                                  label1: 'Zoom in',
                                  value1: 'zoom-in',
                                  enabled1: _ready,
                                  icon2: Icons.zoom_out_rounded,
                                  label2: 'Zoom out',
                                  value2: 'zoom-out',
                                  enabled2: _ready,
                                  iconColor: const Color(0xFF10B981),
                                ),
                                multiItem(
                                  iconColor: const Color(0xFF10B981),
                                  items: [
                                    _MenuActionItem(
                                      icon: Icons.width_full_rounded,
                                      label: 'Fit width',
                                      value: 'fit-width',
                                      tooltip: 'Fit width',
                                    ),
                                    _MenuActionItem(
                                      icon: Icons.fit_screen_rounded,
                                      label: 'Fit page',
                                      value: 'fit-page',
                                      tooltip: 'Fit page',
                                    ),
                                    _MenuActionItem(
                                      icon: Icons.crop_free_rounded,
                                      label: 'Actual size',
                                      value: 'actual-size',
                                      tooltip: 'Actual size (100%)',
                                    ),
                                  ],
                                ),
                                divider(),

                                // ── Color mode ─────────────────────────────────
                                sectionHeader('Color mode'),
                                multiItem(
                                  iconColor: const Color(0xFFF59E0B),
                                  items: [
                                    for (final mode in _PdfColorMode.values)
                                      _MenuActionItem(
                                        icon: mode.icon,
                                        label: mode.label,
                                        value: 'color-${mode.name}',
                                        active: _colorMode == mode,
                                        tooltip: mode.tooltip,
                                      ),
                                  ],
                                ),
                                divider(),

                                // ── Tools ──────────────────────────────────────
                                sectionHeader('Tools'),
                                item(
                                  value: 'fullscreen',
                                  icon: _isFullscreen
                                      ? Icons.fullscreen_exit_rounded
                                      : Icons.fullscreen_rounded,
                                  label: _isFullscreen
                                      ? 'Exit fullscreen'
                                      : 'Fullscreen',
                                  shortcut: showShortcuts ? 'F11' : null,
                                  iconColor: const Color(0xFF6366F1),
                                  active: _isFullscreen,
                                ),
                                item(
                                  value: 'select-text',
                                  icon: Icons.text_fields_rounded,
                                  label: 'Select text',
                                  iconColor: const Color(0xFF0EA5E9),
                                  active: _textSelectionEnabled,
                                ),
                                item(
                                  value: 'bookmarks',
                                  icon: Icons.bookmarks_rounded,
                                  label:
                                      'Bookmarks (${_bookmarkedPages.length})',
                                  iconColor: const Color(0xFFEF4444),
                                  active: _bookmarkedPages.isNotEmpty,
                                ),
                                if (showShortcuts) ...[
                                  divider(),
                                  item(
                                    value: 'keyboard-shortcuts',
                                    icon: Icons.keyboard_rounded,
                                    label: 'Keyboard shortcuts',
                                    iconColor: const Color(0xFF64748B),
                                  ),
                                ],
                              ];
                            },
                          ),
                        ],
                      ),
            body: _buildBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return _buildLoading();

    if (_error != null) {
      return _buildErrorState(
        message: _error!,
        onRetry: _load,
      );
    }

    final bytes = _bytes;
    if (bytes == null) {
      return _buildErrorState(
        message: 'The PDF could not be loaded.',
        onRetry: _load,
      );
    }

    final viewer = LayoutBuilder(
      builder: (context, constraints) {
        // On desktop platforms (like Linux), the window may have a 0x0 or
        // very small size during initial frame creation before the window
        // manager allocates geometry. In pdfrx, if viewSize <= margin * 2,
        // _calcAlternativeFitScale() computes a negative scale, triggering
        // assertion `minScale > 0` in InteractiveViewer.
        if (constraints.maxWidth <= 28 || constraints.maxHeight <= 28) {
          return const SizedBox.shrink();
        }

        final params = PdfViewerParams(
          margin: 14,
          // Night mode inverts the rendered viewer, so the underlying page and
          // background colours stay light here.
          backgroundColor: const Color(0xFFE8EBEF),
          pageDropShadow: BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 10,
            spreadRadius: 1,
            offset: const Offset(0, 3),
          ),
          maxImageBytesCachedOnMemory: 100 * 1024 * 1024,
          verticalCacheExtent: 1,
          scrollByMouseWheel: 0.25,
          enableKeyboardNavigation: false,
          enableTextSelection: _textSelectionEnabled,
          pagePaintCallbacks: _pagePaintCallbacks,
          matchTextColor: _matchHighlightColor,
          activeMatchTextColor: _activeMatchHighlightColor,
          onViewerReady: _handleViewerReady,
          onDocumentChanged: _handleDocumentChanged,
          onPageChanged: _handlePageChanged,
          onInteractionStart: (_) {
            // Touching the page while auto-scrolling gives control back to
            // the reader immediately.
            if (_autoScrollEnabled) _stopAutoScroll();
          },
          loadingBannerBuilder: (context, bytesDownloaded, totalBytes) =>
              const _ViewerLoadingBanner(),
          errorBannerBuilder: (context, error, stackTrace, documentRef) {
            return _buildErrorState(
              message:
                  'The file may be damaged, password protected, or not a valid PDF.',
              detail: error.toString(),
              onRetry: _retryViewer,
            );
          },
        );

        // Local files use PdfViewer.file so PDFium reads the file directly.
        // The byte path (PdfViewer.data) intermittently fails to paint the
        // page for single-page documents that fit entirely in the viewport.
        final localPath = widget.filePath;
        if (localPath != null) {
          return PdfViewer.file(
            localPath,
            key: ValueKey<String>(_sourceName),
            controller: _controller,
            passwordProvider: _askForPassword,
            params: params,
          );
        }
        return PdfViewer.data(
          bytes,
          key: ValueKey<String>(_sourceName),
          sourceName: _sourceName,
          controller: _controller,
          passwordProvider: _askForPassword,
          params: params,
        );
      },
    );

    final colorFilter = _activeColorFilter;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _handleDocumentPointerDown,
            onPointerMove: _handleDocumentPointerMove,
            onPointerUp: _handleDocumentPointerUp,
            onPointerCancel: _handleDocumentPointerCancel,
            child: colorFilter == null
                ? viewer
                : ColorFiltered(
                    colorFilter: colorFilter,
                    child: viewer,
                  ),
          ),
        ),
        // The old bottom slider/page bar is replaced by this right-edge page
        // scrubber. It is deliberately outside the colour-filtered layer so
        // its colours stay accurate.
        if (_ready)
          _PageScrollBar(
            controller: _controller,
            colorMode: _colorMode,
            onUserInteraction: () => _stopAutoScroll(),
          ),
        _buildAutoScrollControls(),
        if (_isFullscreen)
          Positioned(
            top: 10 + MediaQuery.viewPaddingOf(context).top,
            left: 10,
            child: _FullscreenExitButton(
              colorMode: _colorMode,
              onPressed: _exitFullscreen,
            ),
          ),
      ],
    );
  }

  Widget _buildAutoScrollControls() {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 18 + bottomInset,
      child: IgnorePointer(
        ignoring: !_autoScrollEnabled,
        child: AnimatedSlide(
          offset: _autoScrollEnabled ? Offset.zero : const Offset(0, 0.65),
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: _autoScrollEnabled ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: Center(
              child: _AutoScrollPill(
                speedLabel: _autoScrollSpeedLabel,
                colorMode: _colorMode,
                paused: _autoScrollPaused,
                onTogglePause: _toggleAutoScrollPause,
                onSpeed: _cycleAutoScrollSpeed,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    final progress = _downloadProgress;
    return LoadingWidget(
      progress: progress ?? 0,
      loadingText: progress == null ? 'Opening PDF...' : 'Downloading PDF...',
    );
  }

  PreferredSizeWidget _buildSearchAppBar() {
    final hasQuery = _searchController.text.trim().isNotEmpty;
    final matches = _searcher.matches.length;
    final current = _searcher.currentIndex;
    final searching =
        hasQuery && (_searchPending || (_searcher.isSearching && matches == 0));
    final status = !hasQuery
        ? ''
        : matches == 0
            ? (searching ? 'Searching…' : 'No matches')
            : '${(current ?? 0) + 1} / $matches';
    final canNavigate = hasQuery && matches > 0;
    final showStatus = hasQuery && MediaQuery.sizeOf(context).width >= 360;

    return CustomAppBar(
      title: 'Search',
      centerTitle: false,
      showNotification: false,
      leading: IconButton(
        tooltip: 'Close search',
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: _closeSearch,
      ),
      titleWidget: _buildSearchField(),
      actions: [
        if (showStatus)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Center(
              child: searching
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      status,
                      style: TextStyle(
                        fontSize: 12,
                        color: _colorMode.subtitle,
                      ),
                    ),
            ),
          )
        else if (searching)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        IconButton(
          tooltip: 'Previous match',
          visualDensity: VisualDensity.compact,
          onPressed: canNavigate ? _goToPrevMatch : null,
          icon: const Icon(Icons.keyboard_arrow_up_rounded),
        ),
        IconButton(
          tooltip: 'Next match',
          visualDensity: VisualDensity.compact,
          onPressed: canNavigate ? _goToNextMatch : null,
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
        ),
      ],
    );
  }

  Widget _buildSearchField() {
    final foreground = _colorMode.foreground;

    return SizedBox(
      height: 38,
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        onChanged: _onSearchChanged,
        onSubmitted: (_) {
          if (_searcher.matches.isNotEmpty) _goToNextMatch();
        },
        textInputAction: TextInputAction.search,
        style: TextStyle(color: foreground, fontSize: 14),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search in document',
          hintStyle: TextStyle(
            color: foreground.withOpacity(0.45),
            fontSize: 14,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 18,
            color: foreground.withOpacity(0.65),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 34,
            minHeight: 34,
          ),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  icon: Icon(
                    Icons.cancel_rounded,
                    size: 17,
                    color: foreground.withOpacity(0.55),
                  ),
                  onPressed: () {
                    _searchController.clear();
                    _onSearchChanged('');
                    _searchFocusNode.requestFocus();
                  },
                ),
          suffixIconConstraints: const BoxConstraints(
            minWidth: 34,
            minHeight: 34,
          ),
          filled: true,
          fillColor: _colorMode.fieldFill,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 9,
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState({
    required String message,
    String? detail,
    required VoidCallback onRetry,
  }) {
    final trimmedDetail = detail?.trim();

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.picture_as_pdf_outlined,
                      size: 40,
                      color: Colors.red.shade400,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Unable to open this PDF',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  if (trimmedDetail != null && trimmedDetail.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        trimmedDetail,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _openExternally,
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: const Text('Open externally'),
                      ),
                      FilledButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showKeyboardShortcuts() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Keyboard shortcuts'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ShortcutRow(keys: '← / →', action: 'Previous / next page'),
            _ShortcutRow(
              keys: 'Page Up / Page Down',
              action: 'Previous / next page',
            ),
            _ShortcutRow(keys: 'Home / End', action: 'First / last page'),
            _ShortcutRow(keys: '↑ / ↓', action: 'Scroll'),
            _ShortcutRow(keys: 'Ctrl + / Ctrl −', action: 'Zoom in / out'),
            _ShortcutRow(
              keys: 'Ctrl+0 / Ctrl+1',
              action: 'Fit page / fit width',
            ),
            _ShortcutRow(keys: 'Ctrl+2', action: 'Actual size'),
            _ShortcutRow(keys: 'Ctrl+F', action: 'Search in document'),
            _ShortcutRow(keys: 'F11', action: 'Toggle fullscreen'),
            _ShortcutRow(
              keys: 'Esc',
              action: 'Close search / exit fullscreen',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

/// A slim, draggable page scrubber pinned to the right edge of the viewer.
///
/// The thumb shows the current page number and total page count. Dragging it
/// scrolls the document continuously; tapping or dragging the rail jumps
/// straight to that position.
class _PageScrollBar extends StatefulWidget {
  const _PageScrollBar({
    required this.controller,
    required this.colorMode,
    this.onUserInteraction,
  });

  final PdfViewerController controller;
  final _PdfColorMode colorMode;

  /// Called when the reader touches the scrubber, so auto-scroll can stop.
  final VoidCallback? onUserInteraction;

  @override
  State<_PageScrollBar> createState() => _PageScrollBarState();
}

class _PageScrollBarState extends State<_PageScrollBar> {
  static const double _barWidth = 36;
  static const double _thumbHeight = 58;
  static const double _edgeInset = 4;
  static const double _verticalInset = 10;

  bool _dragging = false;
  double? _dragThumbTop;
  int _lastHapticPage = 0;

  @override
  Widget build(BuildContext context) {
    if (!widget.controller.isReady) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        if (!controller.isReady) return const SizedBox.shrink();

        final documentSize = controller.documentSize;
        final viewRect = controller.visibleRect;
        final maxTop = documentSize.height - viewRect.height;
        final total = controller.pageCount;
        if (maxTop <= 1 || total < 2) return const SizedBox.shrink();

        final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

        return Positioned(
          top: _verticalInset,
          bottom: _verticalInset + bottomInset,
          right: _edgeInset,
          width: _barWidth,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final trackHeight = constraints.maxHeight;
              final travel = math.max(0.0, trackHeight - _thumbHeight);
              final naturalTop =
                  (viewRect.top / maxTop).clamp(0.0, 1.0) * travel;
              final thumbTop = (_dragThumbTop ?? naturalTop).clamp(0.0, travel);
              final page = (controller.pageNumber ?? 1).clamp(1, total);

              return Semantics(
                label: 'Page scroll bar',
                value: 'Page $page of $total',
                hint: 'Swipe up or down to move through the document',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) {
                    widget.onUserInteraction?.call();
                    final y = details.localPosition.dy;
                    final onThumb =
                        y >= thumbTop && y <= thumbTop + _thumbHeight;
                    if (onThumb) return;
                    _applyFraction(
                      _fractionForPosition(y, travel),
                      duration: const Duration(milliseconds: 220),
                    );
                  },
                  onVerticalDragStart: (details) {
                    widget.onUserInteraction?.call();
                    final y = details.localPosition.dy;
                    final onThumb =
                        y >= thumbTop && y <= thumbTop + _thumbHeight;
                    final startTop = onThumb
                        ? thumbTop
                        : (y - _thumbHeight / 2).clamp(0.0, travel);
                    setState(() {
                      _dragging = true;
                      _dragThumbTop = startTop;
                    });
                    if (!onThumb) {
                      _applyFraction(
                        travel <= 0 ? 0 : startTop / travel,
                      );
                    }
                  },
                  onVerticalDragUpdate: (details) {
                    final next =
                        ((_dragThumbTop ?? thumbTop) + details.delta.dy)
                            .clamp(0.0, travel);
                    setState(() => _dragThumbTop = next);
                    _applyFraction(travel <= 0 ? 0 : next / travel);
                  },
                  onVerticalDragEnd: (_) => _endDrag(),
                  onVerticalDragCancel: _endDrag,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOut,
                        top: 0,
                        bottom: 0,
                        left: (_barWidth - (_dragging ? 6 : 4)) / 2,
                        width: _dragging ? 6 : 4,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: widget.colorMode.track,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      Positioned(
                        top: thumbTop,
                        left: 0,
                        right: 0,
                        height: _thumbHeight,
                        child: AnimatedScale(
                          scale: _dragging ? 1.06 : 1.0,
                          duration: const Duration(milliseconds: 150),
                          curve: Curves.easeOut,
                          child: _buildThumb(page, total),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildThumb(int page, int total) {
    final primary = Theme.of(context).colorScheme.primary;
    final gradientStart = switch (widget.colorMode) {
      _PdfColorMode.normal => primary,
      _PdfColorMode.night => const Color(0xFF5B8DEF),
      _PdfColorMode.sepia => const Color(0xFFB07A3F),
    };
    final gradientEnd = switch (widget.colorMode) {
      _PdfColorMode.normal => Color.lerp(primary, Colors.black, 0.35)!,
      _PdfColorMode.night => const Color(0xFF2D5BD1),
      _PdfColorMode.sepia => const Color(0xFF7A4F24),
    };
    final pageFontSize = page >= 1000
        ? 10.5
        : page >= 100
            ? 12.0
            : 13.5;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [gradientStart, gradientEnd],
        ),
        borderRadius: BorderRadius.circular(_barWidth / 2),
        border: Border.all(
          color: widget.colorMode.thumbBorder,
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: gradientStart.withOpacity(_dragging ? 0.5 : 0.3),
            blurRadius: _dragging ? 18 : 10,
          ),
          BoxShadow(
            color: Colors.black.withOpacity(
              widget.colorMode.isDark ? 0.55 : 0.28,
            ),
            blurRadius: _dragging ? 13 : 7,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$page',
            maxLines: 1,
            style: TextStyle(
              color: Colors.white,
              fontSize: pageFontSize,
              fontWeight: FontWeight.w800,
              height: 1.0,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '/$total',
            maxLines: 1,
            style: TextStyle(
              color: Colors.white.withOpacity(0.78),
              fontSize: 8,
              fontWeight: FontWeight.w600,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  double _fractionForPosition(double y, double travel) {
    if (travel <= 0) return 0;
    return ((y - _thumbHeight / 2) / travel).clamp(0.0, 1.0);
  }

  void _applyFraction(
    double fraction, {
    Duration duration = Duration.zero,
  }) {
    final controller = widget.controller;
    if (!controller.isReady) return;

    final viewRect = controller.visibleRect;
    final documentSize = controller.documentSize;
    final maxTop = documentSize.height - viewRect.height;
    if (maxTop <= 0) return;

    final targetTop = fraction.clamp(0.0, 1.0) * maxTop;
    final targetCenter =
        Offset(viewRect.center.dx, targetTop + viewRect.height / 2);
    final matrix =
        controller.calcMatrixFor(targetCenter, zoom: controller.currentZoom);

    if (duration == Duration.zero) {
      controller.value = matrix;
    } else {
      controller.goTo(matrix, duration: duration);
    }
    _maybeHaptic(targetCenter.dy);
  }

  void _maybeHaptic(double documentY) {
    final layouts = widget.controller.layout.pageLayouts;
    var page = layouts.length;
    for (var i = 0; i < layouts.length; i++) {
      if (documentY < layouts[i].bottom) {
        page = i + 1;
        break;
      }
    }
    if (page == _lastHapticPage) return;
    _lastHapticPage = page;
    HapticFeedback.selectionClick();
  }

  void _endDrag() {
    if (!mounted) return;
    setState(() {
      _dragging = false;
      _dragThumbTop = null;
    });
  }
}

/// Floating control shown while an auto-scroll session is active.
class _AutoScrollPill extends StatelessWidget {
  const _AutoScrollPill({
    required this.speedLabel,
    required this.colorMode,
    required this.paused,
    required this.onTogglePause,
    required this.onSpeed,
  });

  final String speedLabel;
  final _PdfColorMode colorMode;
  final bool paused;
  final VoidCallback onTogglePause;
  final VoidCallback onSpeed;

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF10B981);
    const greenDark = Color(0xFF059669);
    final foreground = colorMode.foreground;
    final subtitle = colorMode.subtitle;
    final surface = colorMode.surface;
    final border = colorMode.border;
    final buttonColors = paused
        ? const [Color(0xFFF59E0B), Color(0xFFD97706)]
        : const [green, greenDark];

    return Semantics(
      label: 'Auto-scroll controls',
      child: Material(
        elevation: 12,
        shadowColor: Colors.black.withOpacity(0.28),
        color: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
          side: BorderSide(color: border),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(5, 5, 9, 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                button: true,
                label: paused ? 'Resume auto-scroll' : 'Pause auto-scroll',
                child: Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  child: Ink(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: buttonColors,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onTogglePause,
                      child: SizedBox(
                        width: 38,
                        height: 38,
                        child: Icon(
                          paused
                              ? Icons.play_arrow_rounded
                              : Icons.pause_rounded,
                          size: 21,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: paused ? const Color(0xFFF59E0B) : green,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Auto-scroll',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: foreground,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    paused ? 'Paused' : 'Running',
                    style: TextStyle(fontSize: 9.5, color: subtitle),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Tooltip(
                message: 'Change auto-scroll speed',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onSpeed,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: green.withOpacity(
                          colorMode.isDark ? 0.18 : 0.12,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.speed_rounded,
                            size: 14,
                            color: green,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            speedLabel,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: green,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Floating control that brings the reader back out of fullscreen.
class _FullscreenExitButton extends StatelessWidget {
  const _FullscreenExitButton({
    required this.colorMode,
    required this.onPressed,
  });

  final _PdfColorMode colorMode;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final surface = colorMode.surface;
    final foreground = colorMode.foreground;

    return Semantics(
      button: true,
      label: 'Exit fullscreen',
      child: Tooltip(
        message: 'Exit fullscreen (Esc)',
        child: Material(
          elevation: 6,
          shadowColor: Colors.black.withOpacity(0.28),
          color: surface,
          shape: CircleBorder(
            side: BorderSide(color: colorMode.border),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(
                Icons.fullscreen_exit_rounded,
                size: 22,
                color: foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ViewerLoadingBanner extends StatelessWidget {
  const _ViewerLoadingBanner();

  @override
  Widget build(BuildContext context) {
    return const LoadingWidget(
      loadingText: 'Preparing document...',
    );
  }
}

class _MenuActionItem {
  final IconData icon;
  final String label;
  final String value;
  final bool enabled;
  final bool active;
  final String? tooltip;

  const _MenuActionItem({
    required this.icon,
    required this.label,
    required this.value,
    this.enabled = true,
    this.active = false,
    this.tooltip,
  });
}

// Displays 3 or 4 equal-width action cells in a single PopupMenuItem row.
class _MultiMenuRow extends StatelessWidget {
  const _MultiMenuRow({
    required this.items,
    required this.iconColor,
  });

  final List<_MenuActionItem> items;
  final Color iconColor;

  Widget _buildCell(BuildContext context, _MenuActionItem item) {
    final effectiveColor = item.enabled ? iconColor : Colors.grey.shade400;
    final labelColor = item.enabled
        ? Theme.of(context).colorScheme.onSurface
        : Colors.grey.shade400;
    final active = item.enabled && item.active;

    Widget content = InkWell(
      onTap: item.enabled ? () => Navigator.pop(context, item.value) : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: effectiveColor.withOpacity(active ? 0.20 : 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: active
                        ? Border.all(
                            color: effectiveColor.withOpacity(0.55),
                            width: 1.2,
                          )
                        : null,
                  ),
                  child: Icon(item.icon, size: 15, color: effectiveColor),
                ),
                if (active)
                  Positioned(
                    top: -3,
                    right: -3,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: effectiveColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.surface,
                          width: 1,
                        ),
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 8,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: labelColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );

    if (item.tooltip != null) {
      content = Tooltip(
        message: item.tooltip!,
        child: content,
      );
    }

    return Expanded(child: content);
  }

  @override
  Widget build(BuildContext context) {
    final dividerColor = Theme.of(context).dividerColor.withOpacity(0.35);

    final children = <Widget>[];
    for (int i = 0; i < items.length; i++) {
      if (i > 0) {
        children.add(
          Container(
            width: 1,
            height: 28,
            color: dividerColor,
          ),
        );
      }
      children.add(_buildCell(context, items[i]));
    }

    // The containing PopupMenuItem is disabled so that its own InkWell does
    // not swallow taps meant for the individual cells. Undo the faded icon
    // theme that the disabled state adds; each cell already chooses its own
    // enabled/disabled colour.
    return IconTheme.merge(
      data: const IconThemeData(opacity: 1),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: children,
        ),
      ),
    );
  }
}

// Two equal-width tappable cells side by side inside one PopupMenuItem.
// Because PopupMenuItem only carries one value, each cell calls
// Navigator.pop(context, value) directly via InkWell.
class _PairedMenuRow extends StatelessWidget {
  const _PairedMenuRow({
    required this.icon1,
    required this.label1,
    required this.value1,
    this.enabled1 = true,
    required this.icon2,
    required this.label2,
    required this.value2,
    this.enabled2 = true,
    required this.iconColor,
  });

  final IconData icon1;
  final String label1;
  final String value1;
  final bool enabled1;
  final IconData icon2;
  final String label2;
  final String value2;
  final bool enabled2;
  final Color iconColor;

  Widget _cell(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required bool enabled,
  }) {
    final effectiveColor = enabled ? iconColor : Colors.grey.shade400;
    final labelColor = enabled
        ? Theme.of(context).colorScheme.onSurface
        : Colors.grey.shade400;
    return Expanded(
      child: InkWell(
        onTap: enabled ? () => Navigator.pop(context, value) : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: effectiveColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 15, color: effectiveColor),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 12.5, color: labelColor),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconTheme.merge(
      data: const IconThemeData(opacity: 1),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: [
            _cell(
              context,
              icon: icon1,
              label: label1,
              value: value1,
              enabled: enabled1,
            ),
            Container(
              width: 1,
              height: 28,
              color: Theme.of(context).dividerColor.withOpacity(0.5),
            ),
            _cell(
              context,
              icon: icon2,
              label: label2,
              value: value2,
              enabled: enabled2,
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    this.shortcut,
    this.enabled = true,
    this.iconColor,
    this.active = false,
    this.activeColor,
  });

  final IconData icon;
  final String label;
  final String? shortcut;
  final bool enabled;
  final Color? iconColor;
  final bool active;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final effectiveIconColor = enabled
        ? (iconColor ?? Theme.of(context).colorScheme.primary)
        : Colors.grey.shade400;
    final labelColor = enabled
        ? Theme.of(context).colorScheme.onSurface
        : Colors.grey.shade400;
    final bgColor = effectiveIconColor.withOpacity(0.12);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          // Rounded icon badge
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: active ? effectiveIconColor.withOpacity(0.18) : bgColor,
              borderRadius: BorderRadius.circular(10),
              border: active
                  ? Border.all(
                      color: effectiveIconColor.withOpacity(0.5), width: 1.5)
                  : null,
            ),
            child: Icon(icon, size: 18, color: effectiveIconColor),
          ),
          const SizedBox(width: 12),
          // Label
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: labelColor,
              ),
            ),
          ),
          // Shortcut badge
          if (shortcut != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                shortcut!,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ),
          ],
          // Active checkmark
          if (active && shortcut == null) ...[
            const SizedBox(width: 6),
            Icon(Icons.check_rounded,
                size: 16, color: activeColor ?? effectiveIconColor),
          ],
        ],
      ),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.keys, required this.action});

  final String keys;
  final String action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(
              keys,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(action)),
        ],
      ),
    );
  }
}

class _PdfViewerException implements Exception {
  const _PdfViewerException(this.message);

  final String message;
}
