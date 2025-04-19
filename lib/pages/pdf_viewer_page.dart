import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import '../widgets/custom_app_bar.dart';

class PDFViewerPage extends StatefulWidget {
  final String filePath;
  final String title;

  const PDFViewerPage({
    super.key,
    required this.filePath,
    required this.title,
  });

  @override
  State<PDFViewerPage> createState() => _PDFViewerPageState();
}

class _PDFViewerPageState extends State<PDFViewerPage> {
  bool _isLoading = true;
  final TextEditingController _pageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  int? _totalPages;
  int? _currentPage;
  PDFViewController? _pdfViewController;
  double _handlePosition = 0.0; // Changed from 16.0 to 0.0
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateHandlePosition);
  }

  void _updateHandlePosition() {
    if (!mounted) return;
    setState(() {
      if (_scrollController.hasClients) {
        final scrollProgress = _scrollController.offset /
            _scrollController.position.maxScrollExtent;
        final availableHeight = MediaQuery.of(context).size.height - 100;
        _handlePosition =
            scrollProgress * availableHeight; // Removed 16.0 offset
      }
    });
  }

  void _updateHandlePositionFromPage(int page) {
    if (!mounted || _totalPages == null) return;
    setState(() {
      final maxHeight =
          MediaQuery.of(context).size.height - kToolbarHeight - 80;
      if (page == _totalPages! - 1) {
        _handlePosition = maxHeight;
      } else {
        final progress = page / (_totalPages! - 1);
        _handlePosition = progress * maxHeight;
      }
    });
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!mounted || _totalPages == null) return;
    setState(() {
      _handlePosition += details.delta.dy;

      final maxHeight =
          MediaQuery.of(context).size.height - kToolbarHeight - 80;
      _handlePosition = _handlePosition.clamp(0.0, maxHeight);

      final progress = _handlePosition / maxHeight;
      final targetPage = (progress * (_totalPages! - 1)).round();

      if (targetPage >= 0 && targetPage < (_totalPages ?? 1)) {
        _pdfViewController?.setPage(targetPage);
      }
    });
  }

  void _showPageDialog() {
    if (_totalPages == null) return;
    _pageController.text = ''; // Reset the text field

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.pages, color: Colors.blue),
            const SizedBox(width: 10),
            const Text('Go to Page'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Current Page: ${_currentPage ?? 1} of $_totalPages',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _pageController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18),
              decoration: InputDecoration(
                hintText: 'Page number (1-$_totalPages)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
                prefixIcon: const Icon(Icons.article),
              ),
              onSubmitted: (value) {
                Navigator.pop(context);
                final page = int.tryParse(value);
                if (page == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a valid number'),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                } else if (page <= 0 || page > (_totalPages ?? 0)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Please enter a number between 1 and $_totalPages'),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                } else {
                  _pdfViewController?.setPage(page - 1);
                }
              },
            ),
          ],
        ),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'CANCEL',
                  style: TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  final page = int.tryParse(_pageController.text);
                  if (page == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please enter a valid number'),
                        backgroundColor: Colors.red,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  } else if (page <= 0 || page > (_totalPages ?? 0)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            'Please enter a number between 1 and $_totalPages'),
                        backgroundColor: Colors.red,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  } else {
                    _pdfViewController?.setPage(page - 1);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'GO',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateHandlePosition);
    _pageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
        data: Theme.of(context).copyWith(
          primaryColor: Colors.blue.shade700,
          colorScheme: ColorScheme.fromSwatch().copyWith(
            secondary: Colors.blue.shade500,
          ),
        ),
        child: Scaffold(
          appBar: CustomAppBar(
            title: widget.title,
            actions: [
              IconButton(
                icon: const Icon(Icons.pageview),
                onPressed: _showPageDialog,
              ),
            ],
          ),
          body: Stack(
            children: [
              SizedBox(
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height - kToolbarHeight,
                child: PDFView(
                  filePath: widget.filePath,
                  enableSwipe: true,
                  swipeHorizontal: false,
                  autoSpacing: false,
                  pageFling: false,
                  defaultPage: 0,
                  fitPolicy: FitPolicy.WIDTH,
                  pageSnap: false,
                  onRender: (pages) {
                    setState(() {
                      _totalPages = pages;
                      _isLoading = false;
                    });
                  },
                  onError: (error) {
                    setState(() => _isLoading = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $error')),
                    );
                  },
                  onPageChanged: (page, total) {
                    setState(() {
                      _currentPage = page! + 1;
                      if (!_isDragging) {
                        _updateHandlePositionFromPage(page);
                      }
                    });
                  },
                  onViewCreated: (controller) {
                    _pdfViewController = controller;
                  },
                ),
              ),
              Positioned(
                right: 0,
                top: _handlePosition.clamp(
                  0.0,
                  MediaQuery.of(context).size.height - kToolbarHeight - 80,
                ),
                child: GestureDetector(
                  onVerticalDragStart: (_) => _isDragging = true,
                  onVerticalDragEnd: (_) => _isDragging = false,
                  onVerticalDragUpdate: _handleDragUpdate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade700.withOpacity(0.9),
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(12),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      'Page ${_currentPage ?? 1}/$_totalPages',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              if (_isLoading)
                SizedBox(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          'Loading PDF...',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
}
