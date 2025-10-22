import 'package:flutter/material.dart';
import 'package:pi_qbank/widgets/custom_app_bar.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:pi_qbank/widgets/loading_widget.dart';
import 'package:pi_qbank/constants/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EducationalLinksPage extends StatefulWidget {
  const EducationalLinksPage({super.key});

  @override
  State<EducationalLinksPage> createState() => _EducationalLinksPageState();
}

class _EducationalLinksPageState extends State<EducationalLinksPage> {
  String _getFaviconUrl(String url) {
    final uri = Uri.parse(url);
    return 'https://www.google.com/s2/favicons?sz=64&domain=${uri.host}';
  }

  late final List<Map<String, dynamic>> educationalLinks = [
    {
      'title': '7 College',
      "url": 'https://student.7college.du.ac.bd/',
      'favicon': _getFaviconUrl('https://student.7college.du.ac.bd/')
    },
    {
      'title': 'Education Board Results',
      'url': 'http://www.educationboardresults.gov.bd/',
      'favicon': _getFaviconUrl('http://www.educationboardresults.gov.bd/')
    },
    {
      'title': 'Directorate of Primary Education',
      'url': 'http://www.dpe.gov.bd/',
      'favicon': _getFaviconUrl('http://www.dpe.gov.bd/')
    },
    {
      'title': 'University Grants Commission',
      'url': 'http://www.ugc.gov.bd/',
      'favicon': _getFaviconUrl('http://www.ugc.gov.bd/')
    },
    {
      'title': 'National University',
      'url': 'http://www.nu.ac.bd/',
      'favicon': _getFaviconUrl('http://www.nu.ac.bd/')
    },
    {
      'title': 'Bangladesh Open University',
      'url': 'http://www.bou.ac.bd/',
      'favicon': _getFaviconUrl('http://www.bou.ac.bd/')
    },
    {
      'title': 'Dhaka University',
      'url': 'http://www.du.ac.bd/',
      'favicon': _getFaviconUrl('http://www.du.ac.bd/')
    },
    {
      'title': 'Bangladesh Technical Education Board',
      'url': 'http://www.bteb.gov.bd/',
      'favicon': _getFaviconUrl('http://www.bteb.gov.bd/')
    },
    {
      'title': 'NTRCA',
      'url': 'http://www.ntrca.gov.bd/',
      'favicon': _getFaviconUrl('http://www.ntrca.gov.bd/')
    },
    {
      'title': 'Teachers Portal',
      'url': 'http://www.teachers.gov.bd/',
      'favicon': _getFaviconUrl('http://www.teachers.gov.bd/')
    },
  ];

  Set<String> _favoriteEducationalLinks = {};
  late SharedPreferences _prefs;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    _prefs = await SharedPreferences.getInstance();
    setState(() {
      _favoriteEducationalLinks =
          _prefs.getStringList('favoriteEducationalLinks')?.toSet() ?? {};
    });
  }

  Future<void> _saveFavorites() async {
    await _prefs.setStringList(
        'favoriteEducationalLinks', _favoriteEducationalLinks.toList());
  }

  @override
  Widget build(BuildContext context) {
    // Separate favorite and non-favorite channels
    final List<Map<String, dynamic>> favoriteLinks = [];
    final List<Map<String, dynamic>> nonFavoriteLinks = [];

    for (var link in educationalLinks) {
      if (_favoriteEducationalLinks.contains(link['url']!)) {
        favoriteLinks.add(link);
      } else {
        nonFavoriteLinks.add(link);
      }
    }

    // Combine them with favorites at the top
    final List<Map<String, dynamic>> displayedLinks = [
      ...favoriteLinks,
      ...nonFavoriteLinks,
    ];

    return Scaffold(
      backgroundColor: AppColors.lightBlueGrey, // Softer background color
      appBar: CustomAppBar(title: 'Educational Links'),
      body: ListView.builder(
        padding: const EdgeInsets.all(8.0),
        itemCount: displayedLinks.length,
        itemBuilder: (context, index) {
          final link = displayedLinks[index];
          final isFavorite = _favoriteEducationalLinks.contains(link['url']!);
          return Card(
            color: AppColors.white, // Explicitly set card background to white
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => _WebViewScreen(
                      title: link['title']!,
                      url: link['url']!,
                    ),
                  ),
                );
              },
              splashColor: AppColors.deepPurple.withOpacity(0.1),
              highlightColor: AppColors.deepPurple.withOpacity(0.05),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8.0),
                      child: Image.network(
                        link['favicon']!,
                        width: 32,
                        height: 32,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(Icons.link, color: AppColors.deepPurple);
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        link['title']!,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppColors.darkGrey,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        isFavorite ? Icons.favorite : Icons.favorite_border,
                        color: isFavorite
                            ? AppColors.redError
                            : AppColors.lightGrey,
                      ),
                      onPressed: () {
                        setState(() {
                          if (isFavorite) {
                            _favoriteEducationalLinks.remove(link['url']!);
                          } else {
                            _favoriteEducationalLinks.add(link['url']!);
                          }
                          _saveFavorites();
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WebViewScreen extends StatefulWidget {
  final String title;
  final String url;

  const _WebViewScreen({required this.title, required this.url});

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
      ..setUserAgent(
          "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/107.0.0.0 Mobile Safari/537.36")
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
            LoadingWidget(
                progress: _progress, loadingText: 'Loading ${widget.title}...'),
        ],
      ),
    );
  }
}
