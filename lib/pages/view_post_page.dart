import 'dart:io';
// Added for URL decoding
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
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
          onProgress: (int progress) {},
          onPageStarted: (String url) {},
          onPageFinished: (String url) {},
          onWebResourceError: (WebResourceError error) {},
          onNavigationRequest: (NavigationRequest request) async {
            if ((request.url.contains('drive.google.com') ||
                    request.url.contains('drive.usercontent.google.com')) &&
                (request.url.contains('export=download') ||
                    request.url.contains('/download')) &&
                request.url.contains('id=')) {
              // This is likely a Google Drive download link for a PDF
              await _downloadFile(request.url);
              return NavigationDecision
                  .prevent; // Prevent WebView from navigating
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
      ..loadHtmlString(
          _wrapContentWithHtml(widget.content)); // Load wrapped HTML content
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

      // Hardcode the public downloads directory path on Android as requested
      final String downloadsPath = '/storage/emulated/0/Download';
      final directory = Directory(downloadsPath);
      // Extract a more user-friendly filename if possible, otherwise use a generic one
      String determinedFileName =
          'downloaded_file'; // Default filename without extension
      String determinedFileExtension = 'pdf'; // Default extension

      try {
        final uri = Uri.parse(url);

        // 1. Try to get filename from content-disposition header
        final headResponse = await http.head(uri);
        final contentDisposition = headResponse.headers['content-disposition'];

        if (contentDisposition != null) {
          // Regex to capture filename from both filename* and filename attributes
          final filenameRegex =
              RegExp(r'filename\*?=(?:UTF-8' '|")?([^;"\n]+)');
          final match = filenameRegex.firstMatch(contentDisposition);

          if (match != null && match.group(1) != null) {
            String extracted = Uri.decodeComponent(match.group(1)!);
            // Remove quotes if present
            if (extracted.startsWith('"') && extracted.endsWith('"')) {
              extracted = extracted.substring(1, extracted.length - 1);
            }
            determinedFileName = extracted;
          }
        }

        // 2. Fallback: try to get filename from URL path if not found or still generic
        if (determinedFileName == 'downloaded_file') {
          final pathSegments = uri.pathSegments;
          if (pathSegments.isNotEmpty) {
            String lastSegment = pathSegments.last;
            // Remove query parameters from the last segment if present
            if (lastSegment.contains('?')) {
              lastSegment = lastSegment.substring(0, lastSegment.indexOf('?'));
            }
            if (lastSegment.isNotEmpty) {
              determinedFileName = lastSegment;
            }
          }
        }

        // 3. Extract extension from the determined filename
        if (determinedFileName.contains('.')) {
          determinedFileExtension = determinedFileName.split('.').last;
          determinedFileName = determinedFileName.substring(
              0, determinedFileName.lastIndexOf('.'));
        } else {
          // If no extension in filename, try to infer from URL or default
          // This part can be expanded for more file types
          if (uri.path.contains('.pdf')) {
            determinedFileExtension = 'pdf';
          } else if (uri.path.contains('.doc')) {
            determinedFileExtension = 'doc';
          } else if (uri.path.contains('.docx')) {
            determinedFileExtension = 'docx';
          } else if (uri.path.contains('.xls')) {
            determinedFileExtension = 'xls';
          } else if (uri.path.contains('.xlsx')) {
            determinedFileExtension = 'xlsx';
          } else if (uri.path.contains('.ppt')) {
            determinedFileExtension = 'ppt';
          } else if (uri.path.contains('.pptx')) {
            determinedFileExtension = 'pptx';
          } else if (uri.path.contains('.zip')) {
            determinedFileExtension = 'zip';
          } else if (uri.path.contains('.rar')) {
            determinedFileExtension = 'rar';
          } else if (uri.path.contains('.txt')) {
            determinedFileExtension = 'txt';
          } else if (uri.path.contains('.jpg') || uri.path.contains('.jpeg')) {
            determinedFileExtension = 'jpg';
          } else if (uri.path.contains('.png')) {
            determinedFileExtension = 'png';
          } else if (uri.path.contains('.gif')) {
            determinedFileExtension = 'gif';
          }
          // Add more common file types as needed
        }

        // 4. Final fallback: if filename is still generic, use ID if available
        if (determinedFileName == 'downloaded_file' &&
            uri.queryParameters['id'] != null) {
          determinedFileName = uri.queryParameters['id']!;
        }
      } catch (e) {
        // Fallback to generic name if any error occurs during filename determination
        determinedFileName = 'downloaded_file';
        determinedFileExtension = 'pdf';
      }

      final fullFileName = '$determinedFileName.$determinedFileExtension';
      final filePath = '${directory.path}/$fullFileName';

      // Download the file
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);

        scaffoldMessenger.hideCurrentSnackBar(); // Hide downloading snackbar
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
                'Downloaded "$determinedFileName.$determinedFileExtension" to: ${directory.path}'),
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
