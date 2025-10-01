import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:pi_qbank/widgets/custom_app_bar.dart';

class NewspaperPage extends StatefulWidget {
  final String name;
  final String url;
  final List<String> hiddenElements;

  const NewspaperPage({
    super.key,
    required this.name,
    required this.url,
    this.hiddenElements = const [],
  });

  @override
  State<NewspaperPage> createState() => _NewspaperPageState();
}

class _NewspaperPageState extends State<NewspaperPage> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            // Update loading bar.
          },
          onPageStarted: (String url) {},
          onPageFinished: (String url) {
            // Inject JavaScript to hide elements.
            // This script runs periodically to hide dynamically loaded content.
            _controller.runJavaScript("""
              (function() {
                  const styleId = 'gemini-hide-elements-style';
                  const css = `
                   ${widget.hiddenElements.join(', ')}
                   {
                       display: none !important;
                   }
                  `;

                  function addStyle() {
                      var styleElement = document.getElementById(styleId);
                      if (!styleElement) {
                          styleElement = document.createElement('style');
                          styleElement.id = styleId;
                          styleElement.innerHTML = css;
                          document.head.appendChild(styleElement);
                      }
                  }

                  // Run initially on page load
                  addStyle();

                  // And retry periodically to catch elements that load later
                  // or to re-apply if the website removes the style tag.
                  setInterval(addStyle, 500);
              })();
              """);
          },
          onWebResourceError: (WebResourceError error) {},
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Prevent popping by default
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) {
          return;
        }
        if (await _controller.canGoBack()) {
          _controller.goBack();
        } else {
          if (!context.mounted) return;
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: CustomAppBar(
          title: widget.name,
        ),
        body: Column(
          children: [
            Expanded(
              child: WebViewWidget(controller: _controller),
            ),
          ],
        ),
      ),
    );
  }
}