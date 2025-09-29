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

  @override
  void initState() {
    super.initState();
    _controller = WebViewController();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'News Paper',
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: DropdownButton<String>(
              isExpanded: true,
              hint: const Text('Select a news channel'),
              onChanged: (String? newValue) {
                if (newValue != null) {
                  _controller.loadRequest(Uri.parse(newValue));
                }
              },
              items: newsChannels.map<DropdownMenuItem<String>>((channel) {
                return DropdownMenuItem<String>(
                  value: channel['url'],
                  child: Text(channel['name']!),
                );
              }).toList(),
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