import 'package:flutter/material.dart';
import 'package:pi_qbank/pages/newspaper_page.dart';
import 'package:pi_qbank/widgets/custom_app_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pi_qbank/constants/app_colors.dart';

class NewspaperListPage extends StatefulWidget {
  const NewspaperListPage({super.key});

  @override
  State<NewspaperListPage> createState() => _NewspaperListPageState();
}

class _NewspaperListPageState extends State<NewspaperListPage> {
  String _getFaviconUrl(String url) {
    final uri = Uri.parse(url);
    return 'https://www.google.com/s2/favicons?sz=64&domain=${uri.host}';
  }

  late final List<Map<String, dynamic>> newsChannels = [
    {
      'name': 'Google News',
      'url': 'https://news.google.com/home?hl=bn&gl=BD&ceid=BD:bn',
      'hiddenElements': [''],
      'favicon': _getFaviconUrl('https://news.google.com/')
    },
    {
      'name': 'Daily Amardesh',
      'url': 'https://www.dailyamardesh.com/',
      'hiddenElements': [
        '.bg-gray-50',
      ],
      'favicon': _getFaviconUrl('https://www.dailyamardesh.com/')
    },
    {
      'name': 'Prothom Alo',
      'url': 'https://www.prothomalo.com/',
      'hiddenElements': [
        '.adsBox',
        '.web-interstitial-ad',
        '#anchor-ad',
        'TjeAm',
        '.bvT29',
        '.dfp-ad-unit',
        '.TjeAm',
        '._5NJPB',
        '.comment-wrapper',
        '#footer',
      ],
      'favicon': _getFaviconUrl('https://www.prothomalo.com/')
    },
    {
      'name': 'Dhaka Post',
      'url': 'https://www.dhakapost.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.dhakapost.com/')
    },
    {
      'name': 'The Daily Star',
      'url': 'https://www.thedailystar.net/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.thedailystar.net/')
    },
    {
      'name': 'The Daily Campus',
      'url': 'https://www.thedailycampus.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.thedailycampus.com/')
    },
    {
      'name': 'Bangla Tribune',
      'url': 'https://www.banglatribune.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.banglatribune.com/')
    },
    {
      'name': 'Kaler Kantho',
      'url': 'https://www.kalerkantho.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.kalerkantho.com/')
    },
    {
      'name': 'BD GOVT. JOB',
      'url': 'https://bdgovtjob.net/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://bdgovtjob.net/')
    },
    {
      'name': 'New Age',
      'url': 'https://www.newagebd.net/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.newagebd.net/')
    },
    {
      'name': 'The Independent',
      'url': 'https://www.theindependentbd.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.theindependentbd.com/')
    },
    {
      'name': 'The Financial Express',
      'url': 'https://thefinancialexpress.com.bd/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://thefinancialexpress.com.bd/')
    },
    {
      'name': 'The Business Standard',
      'url': 'https://www.tbsnews.net/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.tbsnews.net/')
    },
    {
      'name': 'Daily Sun',
      'url': 'https://www.daily-sun.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.daily-sun.com/')
    },
    {
      'name': 'Daily Observer',
      'url': 'https://www.observerbd.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.observerbd.com/')
    },
    {
      'name': 'The Asian Age',
      'url': 'https://dailyasianage.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://dailyasianage.com/')
    },
    {
      'name': 'The New Nation',
      'url': 'http://thedailynewnation.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('http://thedailynewnation.com/')
    },
    {
      'name': 'The Bangladesh Today',
      'url': 'https://www.thebangladeshtoday.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.thebangladeshtoday.com/')
    },
    {
      'name': 'The Daily Inqilab',
      'url': 'https://www.dailyinqilab.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.dailyinqilab.com/')
    },
    {
      'name': 'The Daily Naya Diganta',
      'url': 'https://www.dailynayadiganta.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.dailynayadiganta.com/')
    },
    {
      'name': 'The Daily Janakantha',
      'url': 'https://www.dailyjanakantha.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.dailyjanakantha.com/')
    },
    {
      'name': 'The Daily Ittefaq',
      'url': 'https://www.ittefaq.com.bd/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.ittefaq.com.bd/')
    },
    {
      'name': 'The Daily Jugantor',
      'url': 'https://www.jugantor.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.jugantor.com/')
    },
    {
      'name': 'The Daily Khabar',
      'url': 'https://www.dailykhabar.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.dailykhabar.com/')
    },
    {
      'name': 'The Daily Manab Zamin',
      'url': 'https://mzamin.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://mzamin.com/')
    },
    {
      'name': 'The Daily Sangram',
      'url': 'https://www.dailysangram.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.dailysangram.com/')
    },
    {
      'name': 'The Daily Azadi',
      'url': 'https://www.dailyazadi.net/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.dailyazadi.net/')
    },
    {
      'name': 'The Daily Purbokone',
      'url': 'https://www.purbokone.net/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.purbokone.net/')
    },
    {
      'name': 'The Daily Sylheter Dak',
      'url': 'https://sylheterdak.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://sylheterdak.com/')
    },
    {
      'name': 'The Daily Sunamganjer Khobor',
      'url': 'https://sunamganjerkhobor.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://sunamganjerkhobor.com/')
    },
    {
      'name': 'The Daily Comilla',
      'url': 'https://www.dailycomilla.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.dailycomilla.com/')
    },
    {
      'name': 'The Daily Rajshahi',
      'url': 'https://www.dailyrajshahi.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.dailyrajshahi.com/')
    },
    {
      'name': 'The Daily Barisal',
      'url': 'https://www.dailybarisal.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.dailybarisal.com/')
    },
    {
      'name': 'The Daily Bogura',
      'url': 'https://www.dailybogura.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.dailybogura.com/')
    },
    {
      'name': 'The Daily Dinajpur',
      'url': 'https://www.dailydinajpur.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.dailydinajpur.com/')
    },
    {
      'name': 'The Daily Rangpur',
      'url': 'https://www.dailyrangpur.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.dailyrangpur.com/')
    },
    {
      'name': 'The Daily Khulna',
      'url': 'https://www.dailykhulna.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.dailykhulna.com/')
    },
    {
      'name': 'The Daily Jessore',
      'url': 'https://www.dailyjessore.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.dailyjessore.com/')
    },
    {
      'name': 'The Daily Pabna',
      'url': 'https://www.dailypabna.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.dailypabna.com/')
    },
    {
      'name': 'The Daily Mymensingh',
      'url': 'https://www.dailymymensingh.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.dailymymensingh.com/')
    },
    {
      'name': 'The Daily Tangail',
      'url': 'https://www.dailytangail.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.dailytangail.com/')
    },
    {
      'name': 'The Daily Narayanganj',
      'url': 'https://www.dailynarayanganj.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.dailynarayanganj.com/')
    },
    {
      'name': 'The Daily Gazipur',
      'url': 'https://www.dailygazipur.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.dailygazipur.com/')
    },
    {
      'name': 'The Daily Narsingdi',
      'url': 'https://www.dailynarsingdi.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.dailynarsingdi.com/')
    },
    {
      'name': 'The Daily Munshiganj',
      'url': 'https://www.dailymunshiganj.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.dailymunshiganj.com/')
    },
    {
      'name': 'The Daily Chandpur',
      'url': 'https://www.dailychandpur.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.dailychandpur.com/')
    },
    {
      'name': 'The Daily Noakhali',
      'url': 'https://www.dailynoakhali.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.dailynoakhali.com/')
    },
    {
      'name': 'The Daily Cox\'s Bazar',
      'url': 'https://www.dailycoxsbazar.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.dailycoxsbazar.com/')
    },
    {
      'name': 'The Daily Feni',
      'url': 'https://www.dailyfeni.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.dailyfeni.com/')
    },
    {
      'name': 'The Daily Lakshmipur',
      'url': 'https://www.dailylakshmipur.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.dailylakshmipur.com/')
    },
    {
      'name': 'The Daily Bhola',
      'url': 'https://www.dailybhola.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.dailybhola.com/')
    },
    {
      'name': 'The Daily Patuakhali',
      'url': 'https://www.dailypatuakhali.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.dailypatuakhali.com/')
    },
    {
      'name': 'The Daily Barisal',
      'url': 'https://www.dailybarisal.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.dailybarisal.com/')
    },
    {
      'name': 'The Daily Jhalokati',
      'url': 'https://www.dailyjhalokati.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.dailyjhalokati.com/')
    },
    {
      'name': 'The Daily Pirojpur',
      'url': 'https://www.dailypirojpur.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.dailypirojpur.com/')
    },
    {
      'name': 'The Daily Barguna',
      'url': 'https://www.dailybarguna.com/',
      'hiddenElements': [],
      'favicon': _getFaviconUrl('https://www.dailybarguna.com/')
    },
  ];

  Set<String> _favoriteNewspapers = {};
  late SharedPreferences _prefs;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

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
      body: ListView.builder(
        padding: const EdgeInsets.all(8.0),
        itemCount: displayedChannels.length,
        itemBuilder: (context, index) {
          final channel = displayedChannels[index];
          final isFavorite = _favoriteNewspapers.contains(channel['url']!);
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
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
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
                        isFavorite ? Icons.favorite : Icons.favorite_border,
                        color: isFavorite
                            ? AppColors.redError
                            : AppColors.lightGrey,
                      ),
                      onPressed: () {
                        setState(() {
                          if (isFavorite) {
                            _favoriteNewspapers.remove(channel['url']!);
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
