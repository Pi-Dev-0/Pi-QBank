import 'package:flutter/material.dart';
import 'package:pi_qbank/pages/newspaper_page.dart';
import 'package:pi_qbank/widgets/custom_app_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pi_qbank/constants/app_colors.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:pi_qbank/widgets/loading_widget.dart';

class NewspaperListPage extends StatefulWidget {
  const NewspaperListPage({super.key});

  @override
  State<NewspaperListPage> createState() => _NewspaperListPageState();
}

class _NewspaperListPageState extends State<NewspaperListPage> {
  static const String kAppScriptUrl =
      'https://script.google.com/macros/s/AKfycbzMbcCYnPBv4hhpdAkAmPRbMoXraZevTZxSB-AuC7FxN_2KGJgJauycgFEWEwgPRIf7hQ/exec';

  String _getFaviconUrl(String url) {
    final uri = Uri.parse(url);
    return 'https://www.google.com/s2/favicons?sz=64&domain=${uri.host}';
  }

  List<Map<String, dynamic>> newsChannels = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    _fetchNewsChannels();
  }

  Future<void> _fetchNewsChannels() async {
    try {
      final response = await http.get(Uri.parse(kAppScriptUrl));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);

        setState(() {
          newsChannels =
              data.where((item) => item['Type'] == 'News').map((item) {
            String hiddenElementsStr = item['hiddenElements']?.toString() ?? '';
            List<String> hiddenElements = hiddenElementsStr.isNotEmpty
                ? hiddenElementsStr.split(',').map((e) => e.trim()).toList()
                : [];

            return {
              'name': item['Name'],
              'url': item['Link'],
              'hiddenElements': hiddenElements,
              'favicon': _getFaviconUrl(item['Link'])
            };
          }).toList();
          _isLoading = false;
        });
      } else {
        throw Exception('Failed to load news channels');
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
      // Fallback to empty or handled in UI
    }
  }

  Set<String> _favoriteNewspapers = {};
  late SharedPreferences _prefs;

  Future<void> _loadFavorites() async {
    _prefs = await SharedPreferences.getInstance();
    setState(() {
      _favoriteNewspapers =
          _prefs.getStringList('favoriteNewspapers')?.toSet() ?? {};
    });
  }

  Future<void> _saveFavorites() async {
    await _prefs.setStringList(
        'favoriteNewspapers', _favoriteNewspapers.toList());
  }

  @override
  Widget build(BuildContext context) {
    // Separate favorite and non-favorite channels
    final List<Map<String, dynamic>> favoriteChannels = [];
    final List<Map<String, dynamic>> nonFavoriteChannels = [];

    for (var channel in newsChannels) {
      if (_favoriteNewspapers.contains(channel['url']!)) {
        favoriteChannels.add(channel);
      } else {
        nonFavoriteChannels.add(channel);
      }
    }

    // Combine them with favorites at the top
    final List<Map<String, dynamic>> displayedChannels = [
      ...favoriteChannels,
      ...nonFavoriteChannels,
    ];

    return Scaffold(
      backgroundColor: AppColors.lightBlueGrey, // Softer background color
      appBar: CustomAppBar(title: 'Select News Provider'),
      body: _isLoading
          ? const LoadingWidget(loadingText: 'Loading Newspapers...')
          : _errorMessage != null
              ? Center(child: Text('Error: $_errorMessage'))
              : ListView.builder(
                  padding: const EdgeInsets.all(8.0),
                  itemCount: displayedChannels.length,
                  itemBuilder: (context, index) {
                    final channel = displayedChannels[index];
                    final isFavorite =
                        _favoriteNewspapers.contains(channel['url']!);
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
                              builder: (context) => NewspaperPage(
                                name: channel['name']!,
                                url: channel['url']!,
                                hiddenElements:
                                    (channel['hiddenElements'] as List<dynamic>)
                                        .cast<String>(),
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
                                  channel['favicon']!,
                                  width: 32,
                                  height: 32,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Icon(Icons.newspaper,
                                        color: AppColors.redError);
                                  },
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  channel['name']!,
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
                                      _favoriteNewspapers
                                          .remove(channel['url']!);
                                    } else {
                                      _favoriteNewspapers.add(channel['url']!);
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
