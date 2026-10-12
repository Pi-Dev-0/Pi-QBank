import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../widgets/loading_widget.dart';
import '../widgets/custom_app_bar.dart';

class OnlinePDFViewerPage extends StatefulWidget {
  const OnlinePDFViewerPage({
    super.key,
    required this.pdfUrl,
    required this.title,
  });
  final String pdfUrl;
  final String title;

  @override
  State<OnlinePDFViewerPage> createState() => _OnlinePDFViewerPageState();
}

class _OnlinePDFViewerPageState extends State<OnlinePDFViewerPage> {
  WebViewController? _controller;
  bool _isLoading = true;
  bool _hasError = false;

  bool get _isWebViewSupported =>
      !kIsWeb &&
      defaultTargetPlatform != TargetPlatform.linux &&
      WebViewPlatform.instance != null;

  @override
  void initState() {
    super.initState();
    if (_isWebViewSupported) {
      _initializeController();
    } else {
      _isLoading = false;
    }
  }

  void _initializeController() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            // Optional: Update progress bar if we had one specifically for the webview
            // For now, staying in loading state until finished
          },
          onPageStarted: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = true;
                _hasError = false;
              });
            }
          },
          onPageFinished: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
          },
          onWebResourceError: (WebResourceError error) {
            // Filter out some common non-critical errors if needed,
            // but for now, we'll assume resource errors might impact the view.
            // Often Google Viewer might throw, but still render.
            // We'll just show a snackbar instead of blocking the view, unless it's critical.
            debugPrint('WebResourceError: ${error.description}');
          },
          onNavigationRequest: (NavigationRequest request) {
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadHtmlString(_buildPdfHtml());
  }

  String _buildPdfHtml() {
    String finalPdfUrl = widget.pdfUrl;
    final uri = Uri.parse(widget.pdfUrl);

    // Check if it's a Google Drive download link and convert it for the viewer
    if (uri.host == 'drive.google.com' &&
        uri.path == '/uc' &&
        uri.queryParameters.containsKey('export') &&
        uri.queryParameters['export'] == 'download' &&
        uri.queryParameters.containsKey('id')) {
      finalPdfUrl =
          'https://drive.google.com/uc?id=${uri.queryParameters['id']}';
    }

    final encodedPdfUrl = Uri.encodeComponent(finalPdfUrl);
    final googleViewerUrl =
        'https://docs.google.com/gview?embedded=true&url=$encodedPdfUrl';

    // A more polished HTML wrapper
    return '''
      <!DOCTYPE html>
      <html>
      <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <style>
          body, html { 
            margin: 0; 
            padding: 0; 
            width: 100%; 
            height: 100%; 
            overflow: hidden; 
            background-color: #f5f5f5; /* Light grey background */
          }
          iframe { 
            border: none; 
            width: 100%; 
            height: 100%; 
            display: block;
          }
          .loading {
             display: flex;
             justify-content: center;
             align-items: center;
             height: 100%;
             font-family: sans-serif;
             color: #666;
          }
        </style>
      </head>
      <body>
        <iframe 
          src="$googleViewerUrl" 
          allow="autoplay"
          title="PDF Viewer"
        ></iframe>
      </body>
      </html>
    ''';
  }

  Future<void> _openInBrowser() async {
    final uri = Uri.parse(widget.pdfUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _reload() async {
    if (_controller == null) return;
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    // Reloading HTML content
    _controller!.loadHtmlString(_buildPdfHtml());
  }

  @override
  Widget build(BuildContext context) {
    if (!_isWebViewSupported) {
      return Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: CustomAppBar(
          title: widget.title,
          actions: [
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
                          color: Colors.red.shade50,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.picture_as_pdf,
                            size: 48, color: Colors.red.shade700),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        widget.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Embedded PDF viewing is not supported on Linux desktop. You can open and view this PDF directly in your browser or document viewer.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade700,
                            height: 1.4),
                      ),
                      const SizedBox(height: 28),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _openInBrowser,
                            icon: const Icon(Icons.open_in_browser),
                            label: const Text('Open PDF'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade700,
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

    if (_isLoading) {
      return const Scaffold(
        body: LoadingWidget(
          progress: 0.7,
          loadingText: 'Loading Document...',
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: CustomAppBar(
        title: widget.title,
        actions: [
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body: Stack(
        children: [
          if (!_hasError && _controller != null)
            WebViewWidget(controller: _controller!),
          if (_hasError)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline,
                      size: 60, color: Colors.red.shade300),
                  const SizedBox(height: 16),
                  const Text(
                    'Failed to load PDF',
                    style: TextStyle(fontSize: 18, color: Colors.black87),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade600,
                      foregroundColor: Colors.white,
                    ),
                  )
                ],
              ),
            ),
        ],
      ),
    );
  }
}
