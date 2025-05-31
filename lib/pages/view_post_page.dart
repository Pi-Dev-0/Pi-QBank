import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import '../widgets/custom_app_bar.dart';

class ViewPostPage extends StatefulWidget {
  final String title;
  final String content;

  const ViewPostPage({
    super.key,
    required this.title,
    required this.content,
  });

  @override
  State<ViewPostPage> createState() => _ViewPostPageState();
}

class _ViewPostPageState extends State<ViewPostPage> {
  late final WebViewController _controller;

  String _wrapContentWithHtml(String content) {
    return '''
      <!DOCTYPE html>
      <html>
      <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
          body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
            margin: 16px;
            line-height: 1.6;
            color: #333;
            background-color: #f9f9f9;
          }
          h1, h2, h3, h4, h5, h6 {
            color: #222;
            margin-top: 1em;
            margin-bottom: 0.5em;
          }
          p {
            margin-bottom: 1em;
          }
          img {
            max-width: 100%;
            height: auto;
            display: block;
            margin: 1em auto;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
          }
          a {
            color: #007bff;
            text-decoration: none;
          }
          a:hover {
            text-decoration: underline;
          }
          pre {
            background-color: #eee;
            padding: 1em;
            overflow-x: auto;
            border-radius: 4px;
          }
          blockquote {
            border-left: 4px solid #ccc;
            padding-left: 1em;
            margin-left: 0;
            color: #666;
          }
          table {
            width: 100%;
            border-collapse: collapse;
            margin-bottom: 1em;
          }
          th, td {
            border: 1px solid #ddd;
            padding: 8px;
            text-align: left;
          }
          th {
            background-color: #f2f2f2;
          }
          .separator {
            border-bottom: 1px solid #eee;
            margin: 1em 0;
          }
          .button {
            display: inline-block;
            padding: 10px 20px;
            background-color: #007bff;
            color: white;
            text-align: center;
            border-radius: 5px;
            text-decoration: none;
            margin-top: 10px;
          }
          .button:hover {
            background-color: #0056b3;
          }
          /* Removed problematic custom styles */
          .chapter, .chaplist, .chaplist h2, .chaplist h3, .chaplist ul, .chaplist ul li, .chaplist ul li span,
          .bie-slide, .bie-slide2, .bie-slide span.circle, .bie-slide2 span.circle2,
          .bie-slide span.title-hover, .bie-slide2 span.title-hover2,
          .bie-slide span.title, .bie-slide2 span.title2,
          .dlBox, .dlBox .fT, .dlBox .fN, .dlBox .fS,
          span i.icon.dl::after {
            /* Reset or minimal styling to avoid conflicts */
            all: unset; /* This will remove all inherited styles */
            display: block; /* Ensure block-level for layout */
            box-sizing: border-box; /* Standard box model */
          }
          /* Re-apply basic link styling for elements that were custom buttons */
          .dlBox a, .bie-slide2 a {
            display: inline-block;
            padding: 10px 20px;
            background-color: #007bff;
            color: white;
            text-align: center;
            border-radius: 5px;
            text-decoration: none;
            margin-top: 10px;
          }
          .dlBox a:hover, .bie-slide2 a:hover {
            background-color: #0056b3;
          }
        </style>
      </head>
      <body>
        $content
      </body>
      </html>
    ''';
  }

  @override
  void initState() {
    super.initState();

    // Initialize WebViewController without platform-specific parameters
    final WebViewController controller = WebViewController();

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            debugPrint('WebView is loading (progress: $progress%)');
          },
          onPageStarted: (String url) {
            debugPrint('Page started loading: $url');
          },
          onPageFinished: (String url) {
            debugPrint('Page finished loading: $url');
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('''
Page resource error:
  code: ${error.errorCode}
  description: ${error.description}
  errorType: ${error.errorType}
  isForMainFrame: ${error.isForMainFrame}
          ''');
          },
          onNavigationRequest: (NavigationRequest request) async {
            if ((request.url.contains('drive.google.com') || request.url.contains('drive.usercontent.google.com')) &&
                (request.url.contains('export=download') || request.url.contains('/download')) &&
                request.url.contains('id=')) {
              // This is likely a Google Drive download link for a PDF
              debugPrint('Intercepted Google Drive download link: ${request.url}');
              await _downloadFile(request.url);
              return NavigationDecision.prevent; // Prevent WebView from navigating
            }
            // Allow navigation to any other URL within the WebView
            return NavigationDecision.navigate;
          },
        ),
      )
      ..addJavaScriptChannel(
        'Toaster',
        onMessageReceived: (JavaScriptMessage message) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message.message)),
          );
        },
      )
      ..loadHtmlString(_wrapContentWithHtml(widget.content)); // Load wrapped HTML content

    // Removed platform-specific debugging/text zoom as it requires platform imports
    // if (controller.platform is AndroidWebViewController) {
    //   AndroidWebViewController.enableDebugging(true);
    //   (controller.platform as AndroidWebViewController)
    //       .setTextZoom(100); // Set text zoom to 100%
    // }

    _controller = controller;
  }

  Future<void> _downloadFile(String url) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    SnackBar? downloadingSnackBar;

    try {
      // Show "Starting download..." snackbar
      downloadingSnackBar = SnackBar(
        content: Row(
          children: const [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(width: 16),
            Text('Downloading file...'),
          ],
        ),
        duration: const Duration(days: 365), // Make it persistent
        backgroundColor: Colors.blueAccent,
      );
      scaffoldMessenger.showSnackBar(downloadingSnackBar);

      // Request storage permission
      var status = await Permission.storage.request();
      if (!status.isGranted) {
        scaffoldMessenger.hideCurrentSnackBar();
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Storage permission denied. Cannot download file.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Get the application documents directory
      final directory = await getApplicationDocumentsDirectory();
      // Extract a more user-friendly filename if possible, otherwise use a generic one
      String fileName = 'downloaded_file.pdf';
      try {
        final uri = Uri.parse(url);
        final id = uri.queryParameters['id'];
        if (id != null) {
          fileName = '$id.pdf';
        }
      } catch (e) {
        debugPrint('Error parsing URL !');
      }
      final filePath = '${directory.path}/$fileName';

      // Download the file
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);

        scaffoldMessenger.hideCurrentSnackBar(); // Hide downloading snackbar
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('Downloaded "$fileName" to: ${directory.path}'),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: 'Open',
              onPressed: () async {
                await OpenFile.open(filePath);
              },
            ),
          ),
        );
      } else {
        scaffoldMessenger.hideCurrentSnackBar(); // Hide downloading snackbar
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('Failed to download file.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      scaffoldMessenger.hideCurrentSnackBar(); // Hide any active snackbar
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Error during download! Consider turning on Internet'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: widget.title,
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
