import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'dart:io';
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
  late PdfViewerController _pdfViewerController;
  final TextEditingController _pageController = TextEditingController();
  bool _isLoading = true;
  int? _totalPages;

  @override
  void initState() {
    super.initState();
    _pdfViewerController = PdfViewerController();
  }

  @override
  void dispose() {
    _pdfViewerController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _handlePageNavigation(String value) {
    if (_totalPages == null) return;
    final page = int.tryParse(value);
    if (page == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid number'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else if (page <= 0 || page > _totalPages!) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please enter a number between 1 and $_totalPages'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      _pdfViewerController.jumpToPage(page);
    }
  }

  void _showPageDialog() {
    if (_totalPages == null) return;
    _pageController.text = '';

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
              'Current Page: ${_pdfViewerController.pageNumber} of $_totalPages',
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
                _handlePageNavigation(value);
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
                  _handlePageNavigation(_pageController.text);
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
  Widget build(BuildContext context) => Scaffold(
        appBar: CustomAppBar(
          title: widget.title,
          actions: [
            IconButton(
              icon: const Icon(Icons.pageview),
              iconSize: 28, // Increased icon size
              onPressed: _showPageDialog,
            ),
          ],
        ),
        body: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              margin: const EdgeInsets.all(8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SfPdfViewer.file(
                  File(widget.filePath),
                  controller: _pdfViewerController,
                  canShowScrollHead: true,
                  enableDoubleTapZooming: true,
                  enableTextSelection: true,
                  onDocumentLoaded: (PdfDocumentLoadedDetails details) {
                    setState(() {
                      _isLoading = false;
                      _totalPages = details.document.pages.count;
                    });
                  },
                  onDocumentLoadFailed: (PdfDocumentLoadFailedDetails details) {
                    setState(() {
                      _isLoading = false;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: ${details.error}')),
                    );
                  },
                ),
              ),
            ),
            if (_isLoading)
              Container(
                color: Colors.white.withOpacity(0.8),
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
      );
}
