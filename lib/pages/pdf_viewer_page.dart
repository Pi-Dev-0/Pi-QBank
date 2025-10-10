import 'package:flutter/material.dart';
import '../widgets/loading_widget.dart';
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

class _PDFViewerPageState extends State<PDFViewerPage>
    with TickerProviderStateMixin {
  PDFViewController? _pdfViewController;
  final TextEditingController _pageController = TextEditingController();
  bool _isLoading = true;
  int? _totalPages;
  int _currentPage = 1;
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
  }

  @override
  void dispose() {
    _pageController.dispose();
    _dialogController.dispose();
    super.dispose();
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
      ),
    );
  }

  void _showPageDialog() async {
    if (_totalPages == null || _pdfViewController == null) return;
    _pageController.text = '';

    final currentPage = await _pdfViewController!.getCurrentPage();
    if (!mounted) return;

    _dialogController.forward();

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha:0.5),
      builder: (context) => AnimatedBuilder(
        animation: _dialogController,
        builder: (context, child) => Transform.scale(
          scale: _dialogScaleAnimation.value,
          child: Opacity(
            opacity: _dialogOpacityAnimation.value,
            child: AlertDialog(
              elevation: 20,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              backgroundColor: Colors.white,
              title: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.blue.shade400,
                      Colors.purple.shade400,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.auto_stories,
                      color: Colors.white,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Navigate to Page',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
              content: Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.blue.shade50,
                            Colors.purple.shade50,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.blue.shade200,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.bookmark,
                            color: Colors.blue.shade600,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Current: ${currentPage! + 1} of $_totalPages',
                            style: TextStyle(
                              color: Colors.blue.shade700,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue.shade100,
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _pageController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Enter page (1-$_totalPages)',
                          hintStyle: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 14,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          prefixIcon: Container(
                            margin: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.blue.shade400,
                                  Colors.purple.shade400,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.article,
                              color: Colors.white,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                        ),
                        onSubmitted: (value) {
                          Navigator.pop(context);
                          _handlePageNavigation(value);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(
                        child: Container(
                          height: 45,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.grey.shade300,
                              width: 1,
                            ),
                          ),
                          child: TextButton(
                            onPressed: () {
                              _dialogController.reverse();
                              Navigator.pop(context);
                            },
                            style: TextButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              'CANCEL',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          height: 45,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.blue.shade400,
                                Colors.purple.shade400,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.blue.shade200,
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: () {
                              _dialogController.reverse();
                              Navigator.pop(context);
                              _handlePageNavigation(_pageController.text);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.rocket_launch,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'GO',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).then((_) {
      _dialogController.reset();
    });
  }

  Widget _buildScrollHandler() {
  if (_totalPages == null) return const SizedBox();

  return Positioned(
    right: 8,
    top: 0,
    bottom: 0,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final totalHeight = constraints.maxHeight;
        final thumbHeight = (_totalPages! > 0)
            ? (totalHeight / _totalPages!).clamp(30.0, totalHeight * 0.9)
            : 30.0;

        double getThumbPositionFromPage() {
          return ((_currentPage - 1) / (_totalPages! - 1)) *
              (totalHeight - thumbHeight);
        }

        double thumbPosition = getThumbPositionFromPage();

        return StatefulBuilder(
          builder: (context, setThumbState) {
            return GestureDetector(
              onVerticalDragUpdate: (details) {
                if (_pdfViewController == null || _totalPages! <= 1) return;

                // Update thumb position
                thumbPosition += details.delta.dy;
                thumbPosition = thumbPosition.clamp(0.0, totalHeight - thumbHeight);

                // Convert to page number
                int newPage = ((thumbPosition / (totalHeight - thumbHeight)) *
                            (_totalPages! - 1))
                        .round() +
                    1;

                if (newPage != _currentPage) {
                  setState(() => _currentPage = newPage);
                  _pdfViewController!.setPage(newPage - 1);
                }

                // Update local thumb state
                setThumbState(() {});
              },
              child: SizedBox(
                width: 40,
                child: Stack(
                  children: [
                    Positioned(
                      top: thumbPosition,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: thumbHeight,
                        decoration: BoxDecoration(
                          color: (_totalPages! <= 1
                                  ? Colors.blue.shade700
                                  : () {
                                      final List<Color> gradientColors = [
                                        Colors.red.shade700,
                                        Colors.orange.shade700,
                                        Colors.yellow.shade700,
                                        Colors.green.shade700,
                                        Colors.blue.shade700,
                                        Colors.purple.shade700,
                                      ];
                                      final int colorCount = gradientColors.length;
                                      final double progress = (_currentPage - 1) / (_totalPages! - 1);
                                      final double clampedProgress = progress.clamp(0.0, 1.0);
                                      final int segmentIndex = (clampedProgress * (colorCount - 1)).floor();
                                      final double segmentProgress = (clampedProgress * (colorCount - 1)) - segmentIndex;
                                      final Color startColor = gradientColors[segmentIndex];
                                      final Color endColor = gradientColors[(segmentIndex + 1).clamp(0, colorCount - 1)];
                                      return Color.lerp(startColor, endColor, segmentProgress)!;
                                    }())
                              .withValues(alpha:0.6), // Semi-transparent color
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(15),
                            bottomLeft: Radius.circular(15),
                          ),
                          border: Border.all(
                            color: (_totalPages! <= 1
                                    ? Colors.blue.shade700
                                    : () {
                                        final List<Color> gradientColors = [
                                          Colors.red.shade700,
                                          Colors.orange.shade700,
                                          Colors.yellow.shade700,
                                          Colors.green.shade700,
                                          Colors.blue.shade700,
                                          Colors.purple.shade700,
                                        ];
                                        final int colorCount = gradientColors.length;
                                        final double progress = (_currentPage - 1) / (_totalPages! - 1);
                                        final double clampedProgress = progress.clamp(0.0, 1.0);
                                        final int segmentIndex = (clampedProgress * (colorCount - 1)).floor();
                                        final double segmentProgress = (clampedProgress * (colorCount - 1)) - segmentIndex;
                                        final Color startColor = gradientColors[segmentIndex];
                                        final Color endColor = gradientColors[(segmentIndex + 1).clamp(0, colorCount - 1)];
                                        return Color.lerp(startColor, endColor, segmentProgress)!;
                                      }())
                                  .withValues(alpha:0.8), // Subtle border
                            width: 0.4,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (_totalPages! <= 1
                                      ? Colors.blue.shade700
                                      : () {
                                          final List<Color> gradientColors = [
                                            Colors.red.shade700,
                                            Colors.orange.shade700,
                                            Colors.yellow.shade700,
                                            Colors.green.shade700,
                                            Colors.blue.shade700,
                                            Colors.purple.shade700,
                                          ];
                                          final int colorCount = gradientColors.length;
                                          final double progress = (_currentPage - 1) / (_totalPages! - 1);
                                          final double clampedProgress = progress.clamp(0.0, 1.0);
                                          final int segmentIndex = (clampedProgress * (colorCount - 1)).floor();
                                          final double segmentProgress = (clampedProgress * (colorCount - 1)) - segmentIndex;
                                          final Color startColor = gradientColors[segmentIndex];
                                          final Color endColor = gradientColors[(segmentIndex + 1).clamp(0, colorCount - 1)];
                                          return Color.lerp(startColor, endColor, segmentProgress)!;
                                        }())
                                  .withValues(alpha:0.4), // Shadow with dynamic color
                              blurRadius: 10, // Increased blur for softer shadow
                              offset: const Offset(0, 4), // Adjusted offset
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '$_currentPage',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
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


  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: CustomAppBar(
          title: widget.title,
          actions: [
            IconButton(
              icon: const Icon(Icons.search),
              iconSize: 24,
              onPressed: _showPageDialog,
            ),
          ],
        ),
        body: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.grey.shade50,
                    Colors.blue.shade50,
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              margin: const EdgeInsets.all(8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: PDFView(
                  filePath: widget.filePath,
                  enableSwipe: true,
                  swipeHorizontal: false,
                  autoSpacing: false,
                  pageFling: true,
                  pageSnap: true,
                  defaultPage: 0,
                  fitPolicy: FitPolicy.WIDTH,
                  preventLinkNavigation: false,
                  onRender: (pages) {
                    setState(() {
                      _totalPages = pages;
                      _isLoading = false;
                    });
                  },
                  onError: (error) {
                    setState(() {
                      _isLoading = false;
                    });
                    _showCustomSnackBar(
                      'Error loading PDF: $error',
                      Colors.red.shade400,
                      Icons.error,
                    );
                  },
                  onPageError: (page, error) {
                    setState(() {
                      _isLoading = false;
                    });
                    _showCustomSnackBar(
                      'Page Error: $error',
                      Colors.orange.shade400,
                      Icons.warning,
                    );
                  },
                  onViewCreated: (PDFViewController pdfViewController) {
                    _pdfViewController = pdfViewController;
                  },
                  onPageChanged: (int? page, int? total) {
                    if (page != null) {
                      setState(() {
                        _currentPage = page + 1;
                      });
                    }
                  },
                ),
              ),
            ),
            _buildScrollHandler(),
            if (_isLoading)
              const LoadingWidget(loadingText: 'Loading PDF...',),
          ],
        ),
      );
}
