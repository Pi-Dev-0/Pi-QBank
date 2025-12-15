import 'package:flutter/material.dart';
import 'package:pi_qbank/widgets/custom_app_bar.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:pi_qbank/widgets/loading_widget.dart';
import 'package:pi_qbank/constants/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class EducationalLinksPage extends StatefulWidget {
  const EducationalLinksPage({super.key});

  @override
  State<EducationalLinksPage> createState() => _EducationalLinksPageState();
}

class _EducationalLinksPageState extends State<EducationalLinksPage> {
  static const String kAppScriptUrl =
      'https://script.google.com/macros/s/AKfycbzMbcCYnPBv4hhpdAkAmPRbMoXraZevTZxSB-AuC7FxN_2KGJgJauycgFEWEwgPRIf7hQ/exec';

  String _getFaviconUrl(String url) {
    final uri = Uri.parse(url);
    return 'https://www.google.com/s2/favicons?sz=64&domain=${uri.host}';
  }

  List<Map<String, dynamic>> educationalLinks = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    _fetchEducationalLinks();
  }

  Future<void> _fetchEducationalLinks() async {
    try {
      final response = await http.get(Uri.parse(kAppScriptUrl));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);

        setState(() {
          educationalLinks =
              data.where((item) => item['Type'] == 'Edu').map((item) {
            return {
              'title': item['Name'],
              'url': item['Link'],
              'favicon': _getFaviconUrl(item['Link'])
            };
          }).toList();
          _isLoading = false;
        });
      } else {
        throw Exception('Failed to load educational links');
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Set<String> _favoriteEducationalLinks = {};
  late SharedPreferences _prefs;

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
      body: _isLoading
          ? const LoadingWidget(loadingText: 'Loading Links...')
          : _errorMessage != null
              ? Center(child: Text('Error: $_errorMessage'))
              : ListView.builder(
                  padding: const EdgeInsets.all(8.0),
                  itemCount: displayedLinks.length,
                  itemBuilder: (context, index) {
                    final link = displayedLinks[index];
                    final isFavorite =
                        _favoriteEducationalLinks.contains(link['url']!);
                    return Card(
                      color: AppColors
                          .white, // Explicitly set card background to white
                      margin: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 12),
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
                          padding: const EdgeInsets.symmetric(
                              vertical: 14, horizontal: 16),
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
                                    return Icon(Icons.link,
                                        color: AppColors.deepPurple);
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
                                  isFavorite
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  color: isFavorite
                                      ? AppColors.redError
                                      : AppColors.lightGrey,
                                ),
                                onPressed: () {
                                  setState(() {
                                    if (isFavorite) {
                                      _favoriteEducationalLinks
                                          .remove(link['url']!);
                                    } else {
                                      _favoriteEducationalLinks
                                          .add(link['url']!);
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
