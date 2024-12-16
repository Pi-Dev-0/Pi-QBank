import 'package:flutter/material.dart';
import '../../../widgets/notification_icon.dart';

class HSCProductionManagement extends StatefulWidget {
  const HSCProductionManagement({super.key});

  @override
  State<HSCProductionManagement> createState() => _HSCProductionManagementState();
}

class _HSCProductionManagementState extends State<HSCProductionManagement> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HSC উৎপাদন ব্যবস্থাপনা ও বিপণন'),
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
      'উৎপাদন ব্যবস্থাপনা',
      'উৎপাদন পদ্ধতি',
      'উৎপাদন পরিকল্পনা',
      'উৎপাদন নিয়ন্ত্রণ',
      'মান নিয়ন্ত্রণ',
      'উৎপাদনশীলতা',
      'কার্য ব্যবস্থাপনা',
      'ক্রয় ব্যবস্থাপনা',
      'মজুদ নিয়ন্ত্রণ',
      'বিপণন',
      'বিপণন মিশ্রণ',
      'বিপণন পরিবেশ',
      'বাজার বিভক্তিকরণ',
      'পণ্য জীবনচক্র',
      'বিপণন গবেষণা',
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
