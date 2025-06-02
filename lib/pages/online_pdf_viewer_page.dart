import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
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
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            // Update loading bar.
          },
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
          },
          onWebResourceError: (WebResourceError error) {
            setState(() {
              _isLoading = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error loading PDF: ${error.description}')),
            );
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

    // Check if it's a Google Drive download link and convert it
    if (uri.host == 'drive.google.com' && uri.path == '/uc' && uri.queryParameters.containsKey('export') && uri.queryParameters['export'] == 'download' && uri.queryParameters.containsKey('id')) {
      finalPdfUrl = 'https://drive.google.com/uc?id=${uri.queryParameters['id']}';
    }

    final encodedPdfUrl = Uri.encodeComponent(finalPdfUrl);
    final googleViewerUrl = 'https://docs.google.com/gview?embedded=true&url=$encodedPdfUrl';

    return '''
      <!DOCTYPE html>
      <html>
      <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
          body { margin: 0; overflow: hidden; }
          iframe { border: none; width: 100vw; height: 100vh; }
        </style>
      </head>
      <body>
        <iframe src="$googleViewerUrl"></iframe>
      </body>
      </html>
    ''';
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: CustomAppBar(
          title: widget.title,
          actions: const [], // Removed page navigation button
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
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
