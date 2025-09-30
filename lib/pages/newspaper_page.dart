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
                  // Corrected and improved selectors. Note that some class names might be dynamic
                  // and may need to be adjusted after inspecting the websites.
                  const css = `
                    .gap-4, .shadow-anchorAdShadow, div.flex.justify-center, .adsBox, .bvT29, .TjeAm, ._0avoF._0U6Mc,
                    .adsBox.U15rh, .special-ads.adsBox, .KjUap, .ad-bottom-container.gHtZA.sGTMR,
                    .container-section.py-3.flex.items-center.justify-center,
                    .flex.items-center.justify-center.w-full,
                    .flex.items-center.justify-center.w-full.mb-7,
                    .flex.items-center.justify-center.w-full.mb-1,
                    .news-details div>div,
                    ._5NJPB, .print-adslot.adsBox._4Pk8L._0Zwdj, .web-interstitial-ad, .special_ads_for_story_0, ._0Zwdj .dfp-ad-unit, .adunitContainer {
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