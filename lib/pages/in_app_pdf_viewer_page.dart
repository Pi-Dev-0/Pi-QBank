import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/custom_app_bar.dart';

/// An in-app PDF viewer for Android and Linux.
///
/// `flutter_pdfview` remains the iOS reader, while Android and Linux use this
/// PDFium-based viewer through `pdfrx`. It provides continuous scrolling,
/// pinch/scroll zoom, page navigation, full-text search, bookmarks and lazy
/// page rendering for long textbooks.
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

class _InAppPdfViewerPageState extends State<InAppPdfViewerPage> {
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

  final PdfViewerController _controller = PdfViewerController();
  final GlobalKey _viewerKey = GlobalKey();
  late final PdfTextSearcher _searcher;
  late final List<PdfViewerPagePaintCallback> _pagePaintCallbacks;
  late final VoidCallback _removeSearchListener;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  Uint8List? _bytes;
  bool _loading = true;
  double? _downloadProgress;
  String? _error;

  int? _totalPages;
  int _currentPage = 1;
  int _sliderPage = 1;
  bool _isScrubbing = false;
  bool _ready = false;
  bool _textSelectionEnabled = false;
  bool _askingPassword = false;
  bool _nightMode = false;
  bool _searchVisible = false;
  bool _searchPending = false;
  String _lastQuery = '';
  String? _initialPassword;

  final Set<int> _bookmarkedPages = <int>{};
  SharedPreferences? _prefs;

  // Changing this gives pdfrx a fresh source name, which forces it to retry a
  // document that previously failed to parse.
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _initialPassword = widget.password;
    _searcher = PdfTextSearcher(_controller);
    _pagePaintCallbacks = [_searcher.pageTextMatchPaintCallback];
    _removeSearchListener = _searcher.addListener(_handleSearchChanged);
    _loadBookmarks();
    _load(initial: true);
  }

  @override
  void dispose() {
    _removeSearchListener();
    _searcher.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  String get _sourceName {
    final base = widget.filePath ?? widget.pdfUrl ?? widget.title;
    return '$base#viewer=$_loadGeneration';
  }

  String get _bookmarkKey =>
      'bookmarks_${(widget.filePath ?? widget.pdfUrl ?? widget.title).hashCode}';

  Future<void> _load({bool initial = false}) async {
    _resetSearch();

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
        _sliderPage = 1;
        _isScrubbing = false;
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
      });
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
      backgroundColor: _nightMode ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        final foreground = _nightMode ? Colors.white : Colors.black87;

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
    final total = document.pages.length;
    if (total == 0) {
      setState(() {
        _ready = true;
        _totalPages = 0;
        _currentPage = 1;
        _sliderPage = 1;
        _isScrubbing = false;
      });
      return;
    }
    final page = (controller.pageNumber ?? 1).clamp(1, total);
    setState(() {
      _ready = true;
      _totalPages = total;
      _currentPage = page;
      _sliderPage = page;
      _isScrubbing = false;
    });

    // The previous Android reader opened documents at "fit width", which is
    // far more readable on phones than fit-page for typical textbook pages.
    if (Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_ready) return;
        final pages = _totalPages;
        if (pages == null || pages < 1) return;
        final target = page.clamp(1, pages);
        _controller.goTo(
          _controller.calcMatrixFitWidthForPage(pageNumber: target),
          duration: Duration.zero,
        );
      });
    }
  }

  void _handleDocumentChanged(PdfDocument? document) {
    if (!mounted) return;
    final pages = document?.pages.length;
    if (pages == null) {
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
    if (pages == _totalPages) return;

    setState(() {
      _totalPages = pages;
      if (pages > 0) {
        _currentPage = _currentPage.clamp(1, pages);
        _sliderPage = _sliderPage.clamp(1, pages);
      } else {
        _currentPage = 1;
        _sliderPage = 1;
      }
    });
  }

  void _handlePageChanged(int? pageNumber) {
    if (!mounted || pageNumber == null) return;
    final total = _totalPages;
    if (total != null && total < 1) return;
    final page = total == null ? pageNumber : pageNumber.clamp(1, total);
    if (page == _currentPage && (!_isScrubbing || page == _sliderPage)) return;

    setState(() {
      _currentPage = page;
      if (!_isScrubbing) _sliderPage = page;
    });
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

  Future<void> _finishScrubbing(double value) async {
    final target = value.round();
    try {
      await _goToPage(target);
    } finally {
      if (mounted) setState(() => _isScrubbing = false);
    }
  }

  Future<void> _zoomIn() async {
    if (!_ready) return;
    await _controller.zoomUp();
  }

  Future<void> _zoomOut() async {
    if (!_ready) return;
    await _controller.zoomDown();
  }

  Future<void> _fitWidth() async {
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
    if (!_ready) return;
    final matrix = _controller.value.clone()..translate(dx, dy);
    await _controller.goTo(
      _controller.makeMatrixInSafeRange(matrix),
      duration: const Duration(milliseconds: 110),
    );
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
    setState(() => _searchVisible = true);
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
    await _searcher.goToNextMatch();
    if (mounted) setState(() {});
  }

  Future<void> _goToPrevMatch() async {
    if (!_ready || _searcher.matches.isEmpty) return;
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
    if (_searchVisible) _closeSearch();
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
    setState(() {
      _loadGeneration++;
      _ready = false;
      _totalPages = null;
      _currentPage = 1;
      _sliderPage = 1;
      _isScrubbing = false;
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
          canPop: !_searchVisible,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && _searchVisible) _closeSearch();
          },
          child: Scaffold(
            backgroundColor:
                _nightMode ? const Color(0xFF121212) : const Color(0xFFE8EBEF),
            appBar: CustomAppBar(
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
                  onPressed:
                      _ready && (_totalPages ?? 0) > 0 ? _toggleBookmark : null,
                ),
                PopupMenuButton<String>(
                  tooltip: 'View options',
                  icon: const Icon(Icons.more_vert_rounded),
                  onSelected: (value) {
                    switch (value) {
                      case 'open-external':
                        _openExternally();
                      case 'fit-width':
                        _fitWidth();
                      case 'fit-page':
                        _fitPage();
                      case 'actual-size':
                        _actualSize();
                      case 'night-mode':
                        setState(() => _nightMode = !_nightMode);
                      case 'select-text':
                        setState(
                          () => _textSelectionEnabled = !_textSelectionEnabled,
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
                    final showShortcuts =
                        !Platform.isAndroid && !Platform.isIOS;
                    final canShare = Platform.isAndroid ||
                        Platform.isIOS ||
                        Platform.isMacOS ||
                        Platform.isWindows;

                    return [
                      const PopupMenuItem(
                        value: 'open-external',
                        child: _MenuRow(
                          icon: Icons.open_in_new_rounded,
                          label: 'Open in another app',
                        ),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'fit-width',
                        child: _MenuRow(
                          icon: Icons.width_full_rounded,
                          label: 'Fit width',
                          shortcut: showShortcuts ? 'Ctrl+1' : null,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'fit-page',
                        child: _MenuRow(
                          icon: Icons.fit_screen_rounded,
                          label: 'Fit page',
                          shortcut: showShortcuts ? 'Ctrl+0' : null,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'actual-size',
                        child: _MenuRow(
                          icon: Icons.crop_free_rounded,
                          label: 'Actual size',
                          shortcut: showShortcuts ? 'Ctrl+2' : null,
                        ),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'night-mode',
                        child: _MenuRow(
                          icon: _nightMode
                              ? Icons.light_mode_rounded
                              : Icons.dark_mode_rounded,
                          label: _nightMode ? 'Light mode' : 'Night mode',
                        ),
                      ),
                      PopupMenuItem(
                        value: 'select-text',
                        child: _MenuRow(
                          icon: _textSelectionEnabled
                              ? Icons.check_box_rounded
                              : Icons.check_box_outline_blank_rounded,
                          label: 'Select text',
                        ),
                      ),
                      PopupMenuItem(
                        value: 'bookmarks',
                        child: _MenuRow(
                          icon: Icons.bookmarks_rounded,
                          label: 'Bookmarks (${_bookmarkedPages.length})',
                        ),
                      ),
                      if (canShare)
                        const PopupMenuItem(
                          value: 'share',
                          child: _MenuRow(
                            icon: Icons.share_rounded,
                            label: 'Share',
                          ),
                        ),
                      if (showShortcuts) ...[
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: 'keyboard-shortcuts',
                          child: _MenuRow(
                            icon: Icons.keyboard_rounded,
                            label: 'Keyboard shortcuts',
                          ),
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

    final viewer = PdfViewer.data(
      bytes,
      key: _viewerKey,
      sourceName: _sourceName,
      controller: _controller,
      passwordProvider: _askForPassword,
      params: PdfViewerParams(
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
        matchTextColor: Colors.yellow.withOpacity(0.55),
        activeMatchTextColor: Colors.orange.withOpacity(0.65),
        onViewerReady: _handleViewerReady,
        onDocumentChanged: _handleDocumentChanged,
        onPageChanged: _handlePageChanged,
        loadingBannerBuilder: (context, bytesDownloaded, totalBytes) =>
            const _ViewerLoadingBanner(),
        errorBannerBuilder: (context, error, stackTrace, documentRef) =>
            _buildErrorState(
          message:
              'The file may be damaged, password protected, or not a valid PDF.',
          detail: error.toString(),
          onRetry: _retryViewer,
        ),
      ),
    );

    return Column(
      children: [
        _searchVisible ? _buildSearchBar() : const SizedBox.shrink(),
        Expanded(
          child: _nightMode
              ? ColorFiltered(
                  colorFilter: _nightModeFilter,
                  child: viewer,
                )
              : viewer,
        ),
        _buildBottomBar(),
      ],
    );
  }

  Widget _buildLoading() {
    final progress = _downloadProgress;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 46,
            height: 46,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 3.5,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            progress == null ? 'Opening PDF...' : 'Downloading PDF...',
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (progress != null) ...[
            const SizedBox(height: 6),
            Text(
              '${(progress * 100).round()}%',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final foreground = _nightMode ? Colors.white : Colors.black87;
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

    final field = TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      onChanged: _onSearchChanged,
      onSubmitted: (_) {
        if (canNavigate) _goToNextMatch();
      },
      textInputAction: TextInputAction.search,
      style: TextStyle(color: foreground, fontSize: 15),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Search in document',
        hintStyle: TextStyle(color: foreground.withOpacity(0.45)),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 20,
          color: foreground.withOpacity(0.65),
        ),
        suffixIcon: _searchController.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear',
                icon: Icon(
                  Icons.cancel_rounded,
                  size: 18,
                  color: foreground.withOpacity(0.55),
                ),
                onPressed: () {
                  _searchController.clear();
                  _onSearchChanged('');
                  _searchFocusNode.requestFocus();
                },
              ),
        filled: true,
        fillColor:
            _nightMode ? const Color(0xFF2A2A2A) : const Color(0xFFF2F4F7),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
      ),
    );

    final navigation = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (searching)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              status,
              style: TextStyle(
                fontSize: 12,
                color: foreground.withOpacity(0.7),
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
        IconButton(
          tooltip: 'Close search',
          visualDensity: VisualDensity.compact,
          onPressed: _closeSearch,
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );

    return Theme(
      data: Theme.of(context).copyWith(
        disabledColor: foreground.withOpacity(0.35),
      ),
      child: Material(
        color: _nightMode ? const Color(0xFF1E1E1E) : Colors.white,
        elevation: 2,
        child: SafeArea(
          top: false,
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: IconTheme(
              data: IconThemeData(color: foreground),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth >= 520) {
                    return Row(
                      children: [
                        Expanded(child: field),
                        const SizedBox(width: 8),
                        navigation,
                      ],
                    );
                  }

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(child: field),
                          IconButton(
                            tooltip: 'Close search',
                            visualDensity: VisualDensity.compact,
                            onPressed: _closeSearch,
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(left: 12),
                              child: searching
                                  ? Row(
                                      children: [
                                        const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Searching…',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: foreground.withOpacity(0.7),
                                          ),
                                        ),
                                      ],
                                    )
                                  : Text(
                                      status,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: foreground.withOpacity(0.7),
                                      ),
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
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final total = _totalPages;
    final displayedPage = _isScrubbing ? _sliderPage : _currentPage;
    final foreground = _nightMode ? Colors.white : Colors.black87;

    return Theme(
      data: Theme.of(context).copyWith(
        disabledColor: foreground.withOpacity(0.35),
      ),
      child: Material(
        color: _nightMode ? const Color(0xFF1E1E1E) : Colors.white,
        elevation: 12,
        shadowColor: Colors.black26,
        child: SafeArea(
          top: false,
          child: IconTheme(
            data: IconThemeData(color: foreground),
            child: DefaultTextStyle.merge(
              style: TextStyle(color: foreground),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (total != null && total > 1)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 14,
                          ),
                          activeTrackColor:
                              Theme.of(context).colorScheme.primary,
                          inactiveTrackColor: Theme.of(context)
                              .colorScheme
                              .primary
                              .withOpacity(0.18),
                          thumbColor: Theme.of(context).colorScheme.primary,
                          overlayColor: Theme.of(context)
                              .colorScheme
                              .primary
                              .withOpacity(0.12),
                        ),
                        child: Slider(
                          value: displayedPage.clamp(1, total).toDouble(),
                          min: 1,
                          max: total.toDouble(),
                          semanticFormatterCallback: (value) =>
                              'Page ${value.round()} of $total',
                          onChangeStart: (value) {
                            setState(() {
                              _isScrubbing = true;
                              _sliderPage = value.round();
                            });
                          },
                          onChanged: (value) {
                            setState(() => _sliderPage = value.round());
                          },
                          onChangeEnd: _finishScrubbing,
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 720;
                        final pageNavigation =
                            _buildPageNavigation(displayedPage);
                        final zoomControls = _buildZoomControls();

                        if (wide) {
                          return Row(
                            children: [
                              Expanded(
                                child: Center(child: pageNavigation),
                              ),
                              zoomControls,
                            ],
                          );
                        }

                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            pageNavigation,
                            const SizedBox(height: 2),
                            zoomControls,
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPageNavigation(int displayedPage) {
    final total = _totalPages;
    final enabled = _ready && total != null && total > 0;
    final canGoBack = _ready && total != null && displayedPage > 1;
    final canGoForward = _ready && total != null && displayedPage < total;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'First page',
          visualDensity: VisualDensity.compact,
          onPressed: canGoBack ? _firstPage : null,
          icon: const Icon(Icons.first_page_rounded),
        ),
        IconButton(
          tooltip: 'Previous page',
          visualDensity: VisualDensity.compact,
          onPressed: canGoBack ? _previousPage : null,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        TextButton(
          onPressed: enabled ? _showGoToPageDialog : null,
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text(
            total == null
                ? 'Opening...'
                : total == 0
                    ? 'No pages'
                    : 'Page ${displayedPage.clamp(1, total)} of $total',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          tooltip: 'Next page',
          visualDensity: VisualDensity.compact,
          onPressed: canGoForward ? _nextPage : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
        IconButton(
          tooltip: 'Last page',
          visualDensity: VisualDensity.compact,
          onPressed: canGoForward ? _lastPage : null,
          icon: const Icon(Icons.last_page_rounded),
        ),
      ],
    );
  }

  Widget _buildZoomControls() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Zoom out',
          visualDensity: VisualDensity.compact,
          onPressed: _ready ? _zoomOut : null,
          icon: const Icon(Icons.remove_rounded),
        ),
        if (_ready)
          ValueListenableBuilder<Matrix4>(
            valueListenable: _controller,
            builder: (context, matrix, child) => _ZoomBadge(
              label: '${(matrix.zoom * 100).round()}%',
              onTap: _actualSize,
            ),
          )
        else
          const _ZoomBadge(label: '100%'),
        IconButton(
          tooltip: 'Zoom in',
          visualDensity: VisualDensity.compact,
          onPressed: _ready ? _zoomIn : null,
          icon: const Icon(Icons.add_rounded),
        ),
        Container(
          width: 1,
          height: 24,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          color: _nightMode ? Colors.white24 : Colors.grey.shade300,
        ),
        IconButton(
          tooltip: 'Fit width',
          visualDensity: VisualDensity.compact,
          onPressed: _ready ? _fitWidth : null,
          icon: const Icon(Icons.width_full_rounded),
        ),
        IconButton(
          tooltip: 'Fit page',
          visualDensity: VisualDensity.compact,
          onPressed: _ready ? _fitPage : null,
          icon: const Icon(Icons.fit_screen_rounded),
        ),
        Container(
          width: 1,
          height: 24,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          color: _nightMode ? Colors.white24 : Colors.grey.shade300,
        ),
        IconButton(
          tooltip: _nightMode ? 'Light mode' : 'Night mode',
          visualDensity: VisualDensity.compact,
          onPressed: () => setState(() => _nightMode = !_nightMode),
          icon: Icon(
            _nightMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
          ),
        ),
      ],
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

class _ZoomBadge extends StatelessWidget {
  const _ZoomBadge({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Actual size',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 56,
          padding: const EdgeInsets.symmetric(vertical: 7),
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
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
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          SizedBox(height: 14),
          Text(
            'Preparing document...',
            style: TextStyle(fontSize: 14, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    this.shortcut,
  });

  final IconData icon;
  final String label;
  final String? shortcut;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Text(label),
        if (shortcut != null) ...[
          const SizedBox(width: 24),
          Text(
            shortcut!,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ],
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
