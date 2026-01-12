import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/loading_widget.dart';

class PDFViewerPage extends StatefulWidget {
  final String filePath;
  final String title;
  final String? password;

  const PDFViewerPage({
    super.key,
    required this.filePath,
    required this.title,
    this.password,
  });

  @override
  State<PDFViewerPage> createState() => _PDFViewerPageState();
}

class _PDFViewerPageState extends State<PDFViewerPage>
    with TickerProviderStateMixin {
  PDFViewController? _pdfViewController;
  final TextEditingController _pageController = TextEditingController();

  bool _isLoading = true;
  bool _nightMode = false;
  // _swipeHorizontal removed, defaulting to false (vertical only)
  bool _pageSnap = true; // Toggle for smooth/continuous scrolling
  bool _isBookmarked = false;

  int? _totalPages;
  int _currentPage = 1;
  String? _currentPassword;

  late AnimationController _dialogController;
  late Animation<double> _dialogScaleAnimation;
  late Animation<double> _dialogOpacityAnimation;

  @override
  void initState() {
    super.initState();
    _dialogController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _dialogScaleAnimation = Tween<double>(
      begin: 0.7,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _dialogController,
      curve: Curves.elasticOut,
    ));
    _dialogOpacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _dialogController,
      curve: Curves.easeOut,
    ));
    _checkBookmarkStatus();

    // Initialize with provided password or null
    _currentPassword = widget.password;
  }

  Future<String?> _showPasswordDialog() async {
    final TextEditingController passwordController = TextEditingController();
    String? password = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Password Required'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This PDF is password protected.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Enter password',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (value) {
                  if (value.isNotEmpty) {
                    Navigator.of(context).pop(value);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (passwordController.text.isNotEmpty) {
                  Navigator.of(context).pop(passwordController.text);
                }
              },
              child: const Text('Open'),
            ),
          ],
        );
      },
    );
    return password;
  }

  @override
  void dispose() {
    _pageController.dispose();
    _dialogController.dispose();
    super.dispose();
  }

  // --- Bookmark Logic ---
  final Set<String> _bookmarkedPages = {};

  Future<void> _checkBookmarkStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'bookmarks_${widget.filePath.hashCode}';
    final List<String> savedBookmarks = prefs.getStringList(key) ?? [];
    if (mounted) {
      setState(() {
        _bookmarkedPages.clear();
        _bookmarkedPages.addAll(savedBookmarks);
        _isBookmarked = _bookmarkedPages.contains(_currentPage.toString());
      });
    }
  }

  Future<void> _toggleBookmark() async {
    final pageString = _currentPage.toString();
    setState(() {
      if (_bookmarkedPages.contains(pageString)) {
        _bookmarkedPages.remove(pageString);
        _isBookmarked = false;
        _showCustomSnackBar(
            'Bookmark removed', Colors.grey.shade700, Icons.bookmark_border);
      } else {
        _bookmarkedPages.add(pageString);
        _isBookmarked = true;
        _showCustomSnackBar(
            'Page $_currentPage bookmarked', Colors.blue, Icons.bookmark);
      }
    });

    final prefs = await SharedPreferences.getInstance();
    final key = 'bookmarks_${widget.filePath.hashCode}';
    await prefs.setStringList(key, _bookmarkedPages.toList());
  }

  void _updateBookmarkIcon() {
    // Synchronous update from local cache
    if (mounted) {
      final isMarked = _bookmarkedPages.contains(_currentPage.toString());
      if (_isBookmarked != isMarked) {
        setState(() => _isBookmarked = isMarked);
      }
    }
  }

  void _showBookmarksList() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'bookmarks_${widget.filePath.hashCode}';
    List<String> bookmarks = prefs.getStringList(key) ?? [];

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: _nightMode ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Bookmarks',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: _nightMode ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 10),
            if (bookmarks.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'No bookmarks yet.',
                  style: TextStyle(
                      color: _nightMode ? Colors.grey : Colors.grey.shade600),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: bookmarks.length,
                  itemBuilder: (context, index) {
                    final page = int.parse(bookmarks[index]);
                    return ListTile(
                      leading: const Icon(Icons.bookmark, color: Colors.blue),
                      title: Text(
                        'Page $page',
                        style: TextStyle(
                            color: _nightMode ? Colors.white : Colors.black87),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _pdfViewController?.setPage(page - 1);
                      },
                      trailing: IconButton(
                        icon:
                            const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () async {
                          bookmarks.removeAt(index);
                          await prefs.setStringList(key, bookmarks);

                          if (!context.mounted) return;
                          Navigator.pop(context);
                          _showBookmarksList(); // Re-open to refresh
                          _updateBookmarkIcon();
                        },
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _handlePageNavigation(String value) {
    if (_totalPages == null) return;
    final page = int.tryParse(value);
    if (page == null) {
      _showCustomSnackBar(
        'Please enter a valid number',
        Colors.red.shade400,
        Icons.error_outline,
      );
    } else if (page <= 0 || page > _totalPages!) {
      _showCustomSnackBar(
        'Please enter a number between 1 and $_totalPages',
        Colors.orange.shade400,
        Icons.warning_amber_rounded,
      );
    } else {
      _pdfViewController?.setPage(page - 1);
      _showCustomSnackBar(
        'Navigated to page $page',
        Colors.green.shade400,
        Icons.check_circle_outline,
      );
    }
  }

  void _showCustomSnackBar(String message, Color color, IconData icon) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars(); // Prevent stacking
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
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

  void _showPageDialog() async {
    if (_totalPages == null || _pdfViewController == null) return;
    _pageController.text = '';

    // ignore: unused_local_variable
    final currentPage = await _pdfViewController!.getCurrentPage();
    if (!mounted) return;

    _dialogController.forward();

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.6), // Darker barrier
      builder: (context) => AnimatedBuilder(
        animation: _dialogController,
        builder: (context, child) => Transform.scale(
          scale: _dialogScaleAnimation.value,
          child: Opacity(
            opacity: _dialogOpacityAnimation.value,
            child: Dialog(
              backgroundColor: Colors.transparent, // Use Container color
              elevation: 0,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxWidth: 400),
                decoration: BoxDecoration(
                  color: _nightMode ? const Color(0xFF1E1E1E) : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // --- Header ---
                    Container(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                      decoration: BoxDecoration(
                        color: _nightMode
                            ? Colors.white.withOpacity(0.05)
                            : Colors.blue.shade50.withOpacity(0.5),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.find_in_page_rounded,
                            size: 48,
                            color: _nightMode
                                ? Colors.blue.shade300
                                : Colors.blue.shade600,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Go to Page',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: _nightMode ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Current: $_currentPage / $_totalPages',
                            style: TextStyle(
                              fontSize: 14,
                              color: _nightMode
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // --- Content ---
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      child: Column(
                        children: [
                          const SizedBox(height: 24),
                          TextField(
                            controller: _pageController,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            autofocus: true,
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: _nightMode ? Colors.white : Colors.black87,
                              letterSpacing: 2,
                            ),
                            decoration: InputDecoration(
                              hintText: '#',
                              hintStyle: TextStyle(
                                color: _nightMode
                                    ? Colors.grey.shade700
                                    : Colors.grey.shade300,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 16,
                                horizontal: 16,
                              ),
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                  color: _nightMode
                                      ? Colors.grey.shade700
                                      : Colors.grey.shade300,
                                  width: 2,
                                ),
                              ),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                  color: _nightMode
                                      ? Colors.blue.shade300
                                      : Colors.blue.shade600,
                                  width: 2,
                                ),
                              ),
                            ),
                            onSubmitted: (value) {
                              Navigator.pop(context);
                              _handlePageNavigation(value);
                            },
                          ),
                          const SizedBox(height: 32),

                          // --- Actions ---
                          Row(
                            children: [
                              Expanded(
                                child: TextButton(
                                  onPressed: () {
                                    _dialogController.reverse();
                                    Navigator.pop(context);
                                  },
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    overlayColor: _nightMode
                                        ? Colors.white10
                                        : Colors.black12,
                                  ),
                                  child: Text(
                                    'Cancel',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: _nightMode
                                          ? Colors.grey.shade400
                                          : Colors.grey.shade600,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    _dialogController.reverse();
                                    Navigator.pop(context);
                                    _handlePageNavigation(_pageController.text);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _nightMode
                                        ? Colors.blue.shade700
                                        : Colors.blue.shade600,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    elevation: 0,
                                    shadowColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: const Text(
                                    'Go',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ).then((_) {
      _dialogController.reset();
    });
  }

  Widget _buildScrollHandler() {
    if (_totalPages == null || _totalPages! <= 1) return const SizedBox();

    return Positioned(
      top: 0,
      bottom: 0,
      right: 4,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalLength = constraints.maxHeight;
          final thumbLength = (_totalPages! > 0)
              ? (totalLength / _totalPages!).clamp(40.0, totalLength * 0.9)
              : 40.0;

          double getThumbPositionFromPage() {
            if (_totalPages! <= 1) return 0.0;
            return ((_currentPage - 1) / (_totalPages! - 1)) *
                (totalLength - thumbLength);
          }

          double thumbPosition = getThumbPositionFromPage();

          return StatefulBuilder(
            builder: (context, setThumbState) {
              return GestureDetector(
                onVerticalDragUpdate: (details) {
                  _handleDrag(details.delta.dy, totalLength, thumbLength,
                      setThumbState);
                },
                child: Container(
                  width: 30,
                  height: totalLength,
                  color: Colors.transparent, // Hit test target
                  child: Stack(
                    children: [
                      Positioned(
                        top: thumbPosition,
                        right: 0,
                        child: Container(
                          width: 24,
                          height: thumbLength,
                          decoration: BoxDecoration(
                              color: (_nightMode
                                      ? Colors.blue.shade200
                                      : Colors.blue.shade600)
                                  .withOpacity(0.6),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                )
                              ]),
                          alignment: Alignment.center,
                          child: Text(
                            '$_currentPage',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _handleDrag(double delta, double totalLength, double thumbLength,
      StateSetter setThumbState) {
    if (_pdfViewController == null || _totalPages! <= 1) return;

    double currentThumbPos =
        ((_currentPage - 1) / (_totalPages! - 1)) * (totalLength - thumbLength);
    double newThumbPos = currentThumbPos + delta;
    newThumbPos = newThumbPos.clamp(0.0, totalLength - thumbLength);

    int newPage =
        ((newThumbPos / (totalLength - thumbLength)) * (_totalPages! - 1))
                .round() +
            1;

    if (newPage != _currentPage) {
      if (mounted) setState(() => _currentPage = newPage);
      _pdfViewController!.setPage(newPage - 1);
    }
    setThumbState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          _nightMode ? const Color(0xFF121212) : Colors.grey.shade100,
      appBar: CustomAppBar(
        title: widget.title,
        actions: [
          IconButton(
            icon: Icon(_isBookmarked ? Icons.bookmark : Icons.bookmark_border),
            onPressed: _toggleBookmark,
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  decoration: BoxDecoration(
                    color: _nightMode ? Colors.black : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _nightMode
                        ? ColorFiltered(
                            colorFilter: const ColorFilter.matrix([
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
                            ]),
                            child: _buildPdfView(),
                          )
                        : _buildPdfView(),
                  ), // End Container
                ), // End Container
              ),
              _buildBottomControls(),
            ],
          ),
          if (_totalPages != null && _totalPages! > 1) _buildScrollHandler(),
          // Show LoadingWidget when loading
          if (_isLoading)
            LoadingWidget(
              loadingText: 'Loading PDF...',
              progress: 0.0, // Can be updated if we track progress
            ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: _nightMode ? const Color(0xFF1E1E1E) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildControlButton(
              icon: Icons.bookmarks_outlined,
              label: 'Bookmarks',
              onTap: _showBookmarksList,
            ),
            _buildControlButton(
              icon: _nightMode ? Icons.light_mode : Icons.dark_mode,
              label: _nightMode ? 'Light' : 'Dark',
              onTap: () {
                setState(() => _nightMode = !_nightMode);
              },
            ),
            _buildControlButton(
              icon: _pageSnap ? Icons.grid_off : Icons.grid_on,
              label: _pageSnap ? 'Smooth' : 'Snap',
              onTap: () {
                setState(() {
                  _pageSnap = !_pageSnap;
                });
                _showCustomSnackBar(
                    _pageSnap
                        ? 'Page Snapping Enabled'
                        : 'Smooth Scrolling Enabled',
                    Colors.blue,
                    Icons.touch_app);
              },
            ),
            _buildControlButton(
              icon: Icons.share,
              label: 'Share',
              onTap: () {
                Share.shareXFiles([XFile(widget.filePath)],
                    text: 'Sharing PDF: ${widget.title}');
              },
            ),
            _buildControlButton(
              icon: Icons.search,
              label: 'Find',
              onTap: _showPageDialog,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPdfView() {
    return PDFView(
      key: Key(
          'pdf_view_${_pageSnap ? 'snap' : 'smooth'}_${_currentPassword ?? 'nopass'}'), // Force recreation when password changes
      filePath: widget.filePath,
      password: _currentPassword,
      defaultPage: _currentPage > 0 ? _currentPage - 1 : 0,
      enableSwipe: true,
      swipeHorizontal: false,
      autoSpacing: _pageSnap, // Auto-spacing only in snap mode
      pageFling: true,
      pageSnap: _pageSnap,
      nightMode: false, // We handle night mode manually
      fitPolicy: FitPolicy.WIDTH,
      onRender: (pages) {
        setState(() {
          _totalPages = pages;
          _isLoading = false;
        });
        _updateBookmarkIcon();
      },
      onError: (error) {
        setState(() => _isLoading = false);

        // Check if it's a password error
        if (error != null &&
            error.toString().toLowerCase().contains('password')) {
          _handlePasswordError();
        }
      },
      onPageError: (page, error) {
        setState(() => _isLoading = false);
      },
      onViewCreated: (controller) {
        _pdfViewController = controller;
      },
      onPageChanged: (page, total) {
        if (page != null) {
          setState(() {
            _currentPage = page + 1;
          });
          _updateBookmarkIcon();
        }
      },
    );
  }

  Future<void> _handlePasswordError() async {
    final password = await _showPasswordDialog();
    if (password != null && password.isNotEmpty) {
      // Show loading state
      setState(() {
        _currentPassword = password;
        _isLoading = true;
      });
    } else {
      // User cancelled - go back
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final color = _nightMode ? Colors.white : Colors.black87;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
