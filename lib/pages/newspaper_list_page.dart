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

  final List<Map<String, String>> newsChannels = const [
    {'name': 'Daily Amardesh', 'url': 'https://www.dailyamardesh.com/'},
    {'name': 'Prothom Alo', 'url': 'https://www.prothomalo.com/'},
    {'name': 'Dhaka Post', 'url': 'https://www.dhakapost.com/'},
    {'name': 'The Daily Star', 'url': 'https://www.thedailystar.net/'},
    {'name': 'The Daily Campus', 'url': 'https://www.thedailycampus.com/'},
    {'name': 'Bangla Tribune', 'url': 'https://www.banglatribune.com/'},
    {'name': 'Kaler Kantho', 'url': 'https://www.kalerkantho.com/'},
    {'name': 'BD GOVT. JOB', 'url': 'https://bdgovtjob.net/'},
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
    final List<Map<String, String>> favoriteChannels = [];
    final List<Map<String, String>> nonFavoriteChannels = [];

    for (var channel in newsChannels) {
      if (_favoriteNewspapers.contains(channel['url']!)) {
        favoriteChannels.add(channel);
      } else {
        nonFavoriteChannels.add(channel);
      }
    }

    // Combine them with favorites at the top
    final List<Map<String, String>> displayedChannels = [
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
                    ),
                  ),
                );
              },
              splashColor: AppColors.deepPurple.withOpacity(0.1),
              highlightColor: AppColors.deepPurple.withOpacity(0.05),
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
