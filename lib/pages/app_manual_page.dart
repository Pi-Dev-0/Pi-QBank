import 'package:flutter/material.dart';
import '../widgets/app_drawer.dart';
import '../widgets/custom_app_bar.dart';

class AppManualPage extends StatelessWidget {
  const AppManualPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'App Manual'),
      drawer: const AppDrawer(),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: const [
          _ManualSection(
            title: 'Getting Started',
            content: '''
• Connect to the internet for full functionality
• Browse through different sections and classes using the home page
• Select a class to view available subjects
• Choose a subject to access question papers
''',
            gifAsset: 'assets/gifs/giphy.gif',
          ),
          _ManualSection(
            title: 'Filtering Papers',
            content: '''
• Use the buttons or dropdown to filter papers
• Papers will be filtered based on your selection
''',
            gifAsset: 'assets/gifs/filtering.gif',
          ),
          _ManualSection(
            title: 'Downloading Papers',
            content: '''
• Tap on any paper card to download it
• Downloaded papers can be viewed offline when bookmarked
• Papers are automatically saved in local storage
''',
            gifAsset: 'assets/gifs/download.gif',
          ),
          _ManualSection(
            title: 'Bookmarking',
            content: '''
• Use the bookmark icon on paper cards to save papers
• Access bookmarked papers from the drawer menu
• Access bookmarked papers offline
''',
            gifAsset: 'assets/gifs/bookmark.gif',
          ),
          _ManualSection(
            title: 'Offline Mode',
            content: '''
• Enable offline mode from the drawer menu
• Downloaded papers can be accessed without internet
• New downloads require internet connection
''',
            gifAsset: 'assets/gifs/offline.gif',
          ),
          _ManualSection(
            title: 'Additional Features',
            content: '''
• Access guidebooks from the drawer menu
• Share the app with friends
• Connect with us on social media
''',
            gifAsset: 'assets/gifs/extra.gif',
          ),
        ],
      ),
    );
  }
}

class _ManualSection extends StatelessWidget {
  final String title;
  final String content;
  final String? gifAsset;

  const _ManualSection({
    required this.title,
    required this.content,
    this.gifAsset,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16.0),
      elevation: 6.0,
      shadowColor: Colors.black,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Center(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ),
            if (gifAsset != null) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  gifAsset!,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.contain,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              content,
              style: const TextStyle(
                fontSize: 16,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
