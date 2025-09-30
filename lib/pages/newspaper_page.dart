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
    {'name': 'The Daily Campus', 'url': 'https://www.thedailycampus.com/'},
    {'name': 'Bangla Tribune', 'url': 'https://www.banglatribune.com/'},
    {'name': 'Kaler Kantho', 'url': 'https://www.kalerkantho.com/'},
    {'name': 'New Age', 'url': 'https://www.newagebd.net/'},
    {'name': 'The Independent', 'url': 'https://www.theindependentbd.com/'},
    {'name': 'The Financial Express', 'url': 'https://thefinancialexpress.com.bd/'},
    {'name': 'The Business Standard', 'url': 'https://www.tbsnews.net/'},
    {'name': 'Daily Sun', 'url': 'https://www.daily-sun.com/'},
    {'name': 'Daily Observer', 'url': 'https://www.observerbd.com/'},
    {'name': 'The Asian Age', 'url': 'https://dailyasianage.com/'},
    {'name': 'The New Nation', 'url': 'http://thedailynewnation.com/'},
    {'name': 'The Bangladesh Today', 'url': 'https://www.thebangladeshtoday.com/'},
    {'name': 'The Daily Inqilab', 'url': 'https://www.dailyinqilab.com/'},
    {'name': 'The Daily Naya Diganta', 'url': 'https://www.dailynayadiganta.com/'},
    {'name': 'The Daily Janakantha', 'url': 'https://www.dailyjanakantha.com/'},
    {'name': 'The Daily Ittefaq', 'url': 'https://www.ittefaq.com.bd/'},
    {'name': 'The Daily Jugantor', 'url': 'https://www.jugantor.com/'},
    {'name': 'The Daily Khabar', 'url': 'https://www.dailykhabar.com/'},
    {'name': 'The Daily Manab Zamin', 'url': 'https://mzamin.com/'},
    {'name': 'The Daily Sangram', 'url': 'https://www.dailysangram.com/'},
    {'name': 'The Daily Azadi', 'url': 'https://www.dailyazadi.net/'},
    {'name': 'The Daily Purbokone', 'url': 'https://www.purbokone.net/'},
    {'name': 'The Daily Sylheter Dak', 'url': 'https://sylheterdak.com/'},
    {'name': 'The Daily Sunamganjer Khobor', 'url': 'https://sunamganjerkhobor.com/'},
    {'name': 'The Daily Comilla', 'url': 'https://www.dailycomilla.com/'},
    {'name': 'The Daily Rajshahi', 'url': 'https://www.dailyrajshahi.com/'},
    {'name': 'The Daily Barisal', 'url': 'https://www.dailybarisal.com/'},
    {'name': 'The Daily Bogura', 'url': 'https://www.dailybogura.com/'},
    {'name': 'The Daily Dinajpur', 'url': 'https://www.dailydinajpur.com/'},
    {'name': 'The Daily Rangpur', 'url': 'https://www.dailyrangpur.com/'},
    {'name': 'The Daily Khulna', 'url': 'https://www.dailykhulna.com/'},
    {'name': 'The Daily Jessore', 'url': 'https://www.dailyjessore.com/'},
    {'name': 'The Daily Pabna', 'url': 'https://www.dailypabna.com/'},
    {'name': 'The Daily Mymensingh', 'url': 'https://www.dailymymensingh.com/'},
    {'name': 'The Daily Tangail', 'url': 'https://www.dailytangail.com/'},
    {'name': 'The Daily Narayanganj', 'url': 'https://www.dailynarayanganj.com/'},
    {'name': 'The Daily Gazipur', 'url': 'https://www.dailygazipur.com/'},
    {'name': 'The Daily Narsingdi', 'url': 'https://www.dailynarsingdi.com/'},
    {'name': 'The Daily Munshiganj', 'url': 'https://www.dailymunshiganj.com/'},
    {'name': 'The Daily Chandpur', 'url': 'https://www.dailychandpur.com/'},
    {'name': 'The Daily Noakhali', 'url': 'https://www.dailynoakhali.com/'},
    {'name': 'The Daily Cox\'s Bazar', 'url': 'https://www.dailycoxsbazar.com/'},
    {'name': 'The Daily Feni', 'url': 'https://www.dailyfeni.com/'},
    {'name': 'The Daily Lakshmipur', 'url': 'https://www.dailylakshmipur.com/'},
    {'name': 'The Daily Bhola', 'url': 'https://www.dailybhola.com/'},
    {'name': 'The Daily Patuakhali', 'url': 'https://www.dailypatuakhali.com/'},
    {'name': 'The Daily Barisal', 'url': 'https://www.dailybarisal.com/'},
    {'name': 'The Daily Jhalokati', 'url': 'https://www.dailyjhalokati.com/'},
    {'name': 'The Daily Pirojpur', 'url': 'https://www.dailypirojpur.com/'},
    {'name': 'The Daily Barguna', 'url': 'https://www.dailybarguna.com/'},
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
