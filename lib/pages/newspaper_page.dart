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

  @override
  void initState() {
    super.initState();
    _selectedChannelUrl = newsChannels.first['url'];
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            // Update loading bar.
          },
          onPageStarted: (String url) {},
          onPageFinished: (String url) {
            // Inject JavaScript to hide elements after the page has loaded
            _controller.runJavaScript(
              """
              var style = document.createElement('style');
              style.innerHTML = `
                .mb-6.flex.flex-col.items-center.justify-center.gap-4, .shadow-anchorAdShadow, flex .justify-center {
                  display: none !important;
                }
              `;
              document.head.appendChild(style);
              """
            );
          },
          onWebResourceError: (WebResourceError error) {},
          onNavigationRequest: (NavigationRequest request) {
            if (request.url.startsWith('https://www.youtube.com/')) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(_selectedChannelUrl!));
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'News Paper',
        actions: [
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: newsChannels.asMap().entries.map((entry) {
                  final index = entry.key;
                  final channel = entry.value;
                  final isSelected = _selectedChannelUrl == channel['url'];
                  final List<Color> buttonColors = [
                    Colors.blue,
                    Colors.green,
                    Colors.orange,
                    Colors.purple,
                    Colors.red,
                  ];
                  final Color buttonColor = buttonColors[index % buttonColors.length];

                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _selectedChannelUrl = channel['url'];
                        });
                        _controller.loadRequest(Uri.parse(channel['url']!));
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isSelected ? buttonColor : buttonColor.withOpacity(0.7),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20.0),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        elevation: isSelected ? 5 : 2,
                      ),
                      child: Text(
                        channel['name']!,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          Expanded(
            child: WebViewWidget(controller: _controller),
          ),
        ],
      ),
    );
  }
}
