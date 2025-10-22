import 'package:flutter/material.dart';
import 'package:pi_qbank/widgets/custom_app_bar.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:pi_qbank/widgets/loading_widget.dart';
import 'package:http/http.dart' as http;

class EducationalLinksPage extends StatefulWidget {
  const EducationalLinksPage({super.key});

  @override
  State<EducationalLinksPage> createState() => _EducationalLinksPageState();
}

class _EducationalLinksPageState extends State<EducationalLinksPage> {
  final List<Map<String, String>> educationalLinks = [
    {'title': 'Education Board Results', 'url': 'http://www.educationboardresults.gov.bd/'},
    {'title': 'Directorate of Primary Education', 'url': 'http://www.dpe.gov.bd/'},
    {'title': 'Ministry of Education', 'url': 'https://moedu.gov.bd/'},
    {'title': 'University Grants Commission', 'url': 'http://www.ugc.gov.bd/'},
    {'title': 'National University', 'url': 'http://www.nu.ac.bd/'},
    {'title': 'Bangladesh Open University', 'url': 'http://www.bou.ac.bd/'},
    {'title': 'Dhaka University', 'url': 'http://www.du.ac.bd/'},
    {'title': 'Bangladesh Technical Education Board', 'url': 'http://www.bteb.gov.bd/'},
    {'title': 'NTRCA', 'url': 'http://www.ntrca.gov.bd/'},
    {'title': 'Teachers Portal', 'url': 'http://www.teachers.gov.bd/'},
  ];

  final Map<String, String?> _faviconUrls = {};

  @override
  void initState() {
    super.initState();
    _fetchFavicons();
  }

  Future<void> _fetchFavicons() async {
    for (var link in educationalLinks) {
      final url = link['url']!;
      try {
        final uri = Uri.parse(url);
        final faviconUrl = Uri.parse(
            '${uri.scheme}://${uri.host}/favicon.ico'); // Common favicon path
        final response = await http.head(faviconUrl);

        if (response.statusCode == 200) {
          setState(() {
            _faviconUrls[url] = faviconUrl.toString();
          });
        }
      } catch (e) {
        // Handle error or simply ignore if favicon not found
        // print('Error fetching favicon for $url: $e');
      }
    }
  }

  void _launchURLInWebView(BuildContext context, String title, String url) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _WebViewScreen(title: title, url: url),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Educational Links',
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(8.0),
        itemCount: educationalLinks.length,
        itemBuilder: (context, index) {
          final link = educationalLinks[index];
          final faviconUrl = _faviconUrls[link['url']!];
          return _buildLinkListItem(context, link['title']!, link['url']!, faviconUrl);
        },
      ),
    );
  }

  Widget _buildLinkListItem(BuildContext context, String title, String url, String? faviconUrl) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        leading: faviconUrl != null
            ? Image.network(
                faviconUrl,
                width: 24,
                height: 24,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.link,
                  color: Theme.of(context).primaryColor,
                ),
              )
            : Icon(
                Icons.link,
                color: Theme.of(context).primaryColor,
              ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(url),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16.0),
        onTap: () => _launchURLInWebView(context, title, url),
      ),
    );
  }
}

class _WebViewScreen extends StatefulWidget {
  final String title;
  final String url;

  const _WebViewScreen({super.key, required this.title, required this.url});

  @override
  State<_WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<_WebViewScreen> {
  late final WebViewController controller;
  double _progress = 0.0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            setState(() {
              _progress = progress / 100;
            });
          },
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
          },
          onWebResourceError: (WebResourceError error) {
            // Handle error
          },
          onNavigationRequest: (NavigationRequest request) {
            return NavigationDecision.navigate;
          },
        ),
      )
      ..setUserAgent("Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/107.0.0.0 Mobile Safari/537.36")
      ..loadRequest(
        Uri.parse(widget.url),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: widget.title,
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: controller),
          if (_isLoading)
            LoadingWidget(progress: _progress, loadingText: 'Loading ${widget.title}...'),
        ],
      ),
    );
  }
}