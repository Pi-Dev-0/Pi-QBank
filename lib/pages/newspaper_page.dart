import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:pi_qbank/widgets/custom_app_bar.dart';

class NewspaperPage extends StatefulWidget {
  final String name;
  final String url;

  const NewspaperPage({super.key, required this.name, required this.url});

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
                   .bg-gray-50, .adsBox, .web-interstitial-ad, .special_ads_for_story_0, .TjeAm, .dfp-ad-unit, .bvT29, #anchor-ad, .print-none, ._5NJPB,
                   .py-3, .flex.items-center.justify-center.w-full, .footer-ad, .ads-container, 
                   .adsbygoogle, 
                    #div-gpt-ad-1703757687357-0, #div-gpt-ad-1701849334941-0, #div-gpt-ad-1702964129290-0, #div-gpt-ad-1753528412147-0
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