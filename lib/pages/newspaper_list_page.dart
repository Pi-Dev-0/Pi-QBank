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

  final List<Map<String, dynamic>> newsChannels = const [
    {'name': 'Google News', 'url': 'https://news.google.com/home?hl=bn&gl=BD&ceid=BD:bn', 'hiddenElements':['.YtXOzd.Au3bp.kbeFSb.lMgtcc']},
    {'name': 'Daily Amardesh', 'url': 'https://www.dailyamardesh.com/', 'hiddenElements': ['.bg-gray-50',]},
    {'name': 'Prothom Alo', 'url': 'https://www.prothomalo.com/', 'hiddenElements': ['.adsBox', '.web-interstitial-ad', '#anchor-ad', 'TjeAm', '.bvT29', '.dfp-ad-unit', '.TjeAm', '._5NJPB', '.comment-wrapper', '#footer',]},
    {'name': 'Dhaka Post', 'url': 'https://www.dhakapost.com/', 'hiddenElements': []},
    {'name': 'The Daily Star', 'url': 'https://www.thedailystar.net/', 'hiddenElements': []},
    {'name': 'The Daily Campus', 'url': 'https://www.thedailycampus.com/', 'hiddenElements': []},
    {'name': 'Bangla Tribune', 'url': 'https://www.banglatribune.com/', 'hiddenElements': []},
    {'name': 'Kaler Kantho', 'url': 'https://www.kalerkantho.com/', 'hiddenElements': []},
    {'name': 'BD GOVT. JOB', 'url': 'https://bdgovtjob.net/', 'hiddenElements': []},
    {'name': 'New Age', 'url': 'https://www.newagebd.net/', 'hiddenElements': []},
    {'name': 'The Independent', 'url': 'https://www.theindependentbd.com/', 'hiddenElements': []},
    {'name': 'The Financial Express', 'url': 'https://thefinancialexpress.com.bd/', 'hiddenElements': []},
    {'name': 'The Business Standard', 'url': 'https://www.tbsnews.net/', 'hiddenElements': []},
    {'name': 'Daily Sun', 'url': 'https://www.daily-sun.com/', 'hiddenElements': []},
    {'name': 'Daily Observer', 'url': 'https://www.observerbd.com/', 'hiddenElements': []},
    {'name': 'The Asian Age', 'url': 'https://dailyasianage.com/', 'hiddenElements': []},
    {'name': 'The New Nation', 'url': 'http://thedailynewnation.com/', 'hiddenElements': []},
    {'name': 'The Bangladesh Today', 'url': 'https://www.thebangladeshtoday.com/', 'hiddenElements': []},
    {'name': 'The Daily Inqilab', 'url': 'https://www.dailyinqilab.com/', 'hiddenElements': []},
    {'name': 'The Daily Naya Diganta', 'url': 'https://www.dailynayadiganta.com/', 'hiddenElements': []},
    {'name': 'The Daily Janakantha', 'url': 'https://www.dailyjanakantha.com/', 'hiddenElements': []},
    {'name': 'The Daily Ittefaq', 'url': 'https://www.ittefaq.com.bd/', 'hiddenElements': []},
    {'name': 'The Daily Jugantor', 'url': 'https://www.jugantor.com/', 'hiddenElements': []},
    {'name': 'The Daily Khabar', 'url': 'https://www.dailykhabar.com/', 'hiddenElements': []},
    {'name': 'The Daily Manab Zamin', 'url': 'https://mzamin.com/', 'hiddenElements': []},
    {'name': 'The Daily Sangram', 'url': 'https://www.dailysangram.com/', 'hiddenElements': []},
    {'name': 'The Daily Azadi', 'url': 'https://www.dailyazadi.net/', 'hiddenElements': []},
    {'name': 'The Daily Purbokone', 'url': 'https://www.purbokone.net/', 'hiddenElements': []},
    {'name': 'The Daily Sylheter Dak', 'url': 'https://sylheterdak.com/', 'hiddenElements': []},
    {'name': 'The Daily Sunamganjer Khobor', 'url': 'https://sunamganjerkhobor.com/', 'hiddenElements': []},
    {'name': 'The Daily Comilla', 'url': 'https://www.dailycomilla.com/', 'hiddenElements': []},
    {'name': 'The Daily Rajshahi', 'url': 'https://www.dailyrajshahi.com/', 'hiddenElements': []},
    {'name': 'The Daily Barisal', 'url': 'https://www.dailybarisal.com/', 'hiddenElements': []},
    {'name': 'The Daily Bogura', 'url': 'https://www.dailybogura.com/', 'hiddenElements': []},
    {'name': 'The Daily Dinajpur', 'url': 'https://www.dailydinajpur.com/', 'hiddenElements': []},
    {'name': 'The Daily Rangpur', 'url': 'https://www.dailyrangpur.com/', 'hiddenElements': []},
    {'name': 'The Daily Khulna', 'url': 'https://www.dailykhulna.com/', 'hiddenElements': []},
    {'name': 'The Daily Jessore', 'url': 'https://www.dailyjessore.com/', 'hiddenElements': []},
    {'name': 'The Daily Pabna', 'url': 'https://www.dailypabna.com/', 'hiddenElements': []},
    {'name': 'The Daily Mymensingh', 'url': 'https://www.dailymymensingh.com/', 'hiddenElements': []},
    {'name': 'The Daily Tangail', 'url': 'https://www.dailytangail.com/', 'hiddenElements': []},
    {'name': 'The Daily Narayanganj', 'url': 'https://www.dailynarayanganj.com/', 'hiddenElements': []},
    {'name': 'The Daily Gazipur', 'url': 'https://www.dailygazipur.com/', 'hiddenElements': []},
    {'name': 'The Daily Narsingdi', 'url': 'https://www.dailynarsingdi.com/', 'hiddenElements': []},
    {'name': 'The Daily Munshiganj', 'url': 'https://www.dailymunshiganj.com/', 'hiddenElements': []},
    {'name': 'The Daily Chandpur', 'url': 'https://www.dailychandpur.com/', 'hiddenElements': []},
    {'name': 'The Daily Noakhali', 'url': 'https://www.dailynoakhali.com/', 'hiddenElements': []},
    {'name': 'The Daily Cox\'s Bazar', 'url': 'https://www.dailycoxsbazar.com/', 'hiddenElements': []},
    {'name': 'The Daily Feni', 'url': 'https://www.dailyfeni.com/', 'hiddenElements': []},
    {'name': 'The Daily Lakshmipur', 'url': 'https://www.dailylakshmipur.com/', 'hiddenElements': []},
    {'name': 'The Daily Bhola', 'url': 'https://www.dailybhola.com/', 'hiddenElements': []},
    {'name': 'The Daily Patuakhali', 'url': 'https://www.dailypatuakhali.com/', 'hiddenElements': []},
    {'name': 'The Daily Barisal', 'url': 'https://www.dailybarisal.com/', 'hiddenElements': []},
    {'name': 'The Daily Jhalokati', 'url': 'https://www.dailyjhalokati.com/', 'hiddenElements': []},
    {'name': 'The Daily Pirojpur', 'url': 'https://www.dailypirojpur.com/', 'hiddenElements': []},
    {'name': 'The Daily Barguna', 'url': 'https://www.dailybarguna.com/', 'hiddenElements': []},
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
      _favoriteNewspapers = _prefs.getStringList('favoriteNewspapers')?.toSet() ?? {};
    });
  }

  Future<void> _saveFavorites() async {
    await _prefs.setStringList('favoriteNewspapers', _favoriteNewspapers.toList());
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
                      hiddenElements: (channel['hiddenElements'] as List<dynamic>).cast<String>(),
                    ),
                  ),
                );
              },
              splashColor: AppColors.deepPurple.withValues(alpha:0.1),
              highlightColor: AppColors.deepPurple.withValues(alpha:0.05),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                child: Row(
                  children: [
                    Icon(Icons.article, color: AppColors.deepPurple),
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
                        color: isFavorite ? AppColors.redError : AppColors.lightGrey,
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
