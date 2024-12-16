import 'package:flutter/material.dart';
import '../../../widgets/notification_icon.dart';

class SSCBanglaLiterature extends StatefulWidget {
  const SSCBanglaLiterature({super.key});

  @override
  State<SSCBanglaLiterature> createState() => _SSCBanglaLiteratureState();
}

class _SSCBanglaLiteratureState extends State<SSCBanglaLiterature> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SSC বাংলা সাহিত্য'),
        actions: const [NotificationIcon()],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.deepPurple, Colors.deepPurpleAccent],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            _buildChapterSection(),
            const SizedBox(height: 20),
            _buildResourceSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildChapterSection() {
    final chapters = [
      'গদ্য',
      'পদ্য',
      'নাটক',
      'উপন্যাস',
      'ছোট গল্প',
      'প্রবন্ধ',
      'রচনা',
      'পত্র লেখন',
      'সারাংশ',
      'ভাবসম্প্রসারণ',
      'অনুচ্ছেদ রচনা',
      'প্রতিবেদন লেখন',
    ];

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'অধ্যায়সমূহ',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: chapters.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(chapters[index]),
                  trailing: const Icon(Icons.arrow_forward),
                  onTap: () {
                    // Navigate to chapter detail page
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResourceSection() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'রিসোর্সসমূহ',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _buildResourceButton(
                  icon: Icons.quiz,
                  label: 'কুইজ',
                  onTap: () {
                    // Navigate to quiz page
                  },
                ),
                _buildResourceButton(
                  icon: Icons.book,
                  label: 'নোটস',
                  onTap: () {
                    // Navigate to notes page
                  },
                ),
                _buildResourceButton(
                  icon: Icons.video_library,
                  label: 'ভিডিও',
                  onTap: () {
                    // Navigate to video page
                  },
                ),
                _buildResourceButton(
                  icon: Icons.edit,
                  label: 'লেখার অনুশীলন',
                  onTap: () {
                    // Navigate to writing practice page
                  },
                ),
                _buildResourceButton(
                  icon: Icons.library_books,
                  label: 'সাহিত্য সমালোচনা',
                  onTap: () {
                    // Navigate to literary criticism page
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResourceButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    );
  }
}
