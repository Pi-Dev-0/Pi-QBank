import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
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
          onNavigationRequest: (NavigationRequest request) {
            // Allow navigation to any URL within the WebView
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
