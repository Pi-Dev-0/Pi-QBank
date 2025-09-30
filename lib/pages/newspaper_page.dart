import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:pi_qbank/widgets/custom_app_bar.dart';

class NewspaperPage extends StatefulWidget {
  const NewspaperPage({super.key});

  @override
  State<NewspaperPage> createState() => _NewspaperPageState();
}

class _NewspaperPageState extends State<NewspaperPage> {
  late final WebViewController _controller;
  final List<Map<String, String>> newsChannels = [
    {'name': 'Daily Amardesh', 'url': 'https://www.dailyamardesh.com/'},
    {'name': 'Prothom Alo', 'url': 'https://www.prothomalo.com/'},
    {'name': 'Dhaka Post', 'url': 'https://www.dhakapost.com/'},
    {'name': 'The Daily Star', 'url': 'https://www.thedailystar.net/'},
  ];

  String? _selectedChannelUrl;
  String? _selectedChannelName;

  @override
  void initState() {
    super.initState();
    _selectedChannelUrl = newsChannels.first['url'];
    _selectedChannelName = newsChannels.first['name'];
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
      ..loadRequest(Uri.parse(_selectedChannelUrl!));
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
          title: _selectedChannelName ?? 'News Paper',
          actions: [
            IconButton(
              icon: const Icon(Icons.newspaper),
              onPressed: () => _showNewsChannelPicker(context),
            ),
          ],
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

  void _showNewsChannelPicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          elevation: 8,
          title: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Text(
                'Select News Provider',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ),
          ),
          content: SingleChildScrollView(
            child: ListBody(
              children: newsChannels.map((channel) {
                final isSelected = _selectedChannelUrl == channel['url'];
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedChannelUrl = channel['url'];
                      _selectedChannelName = channel['name'];
                    });
                    _controller.loadRequest(Uri.parse(channel['url']!));
                    Navigator.of(context).pop();
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 14),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.blue.shade100 : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? Colors.blue : Colors.grey.shade300,
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      channel['name']!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? Colors.blue.shade900 : Colors.black87,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Close'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }
}
