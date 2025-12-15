import 'package:flutter/material.dart';
import '../widgets/app_drawer.dart';
import '../widgets/custom_app_bar.dart';

class ClassPage extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> subjects;

  // Color palette for cards
  final List<Color> _cardColors = const [
    Colors.purple,
    Colors.orange,
    Colors.blue,
    Colors.red,
    Colors.teal,
    Colors.pink,
    Colors.indigo,
    Colors.cyan,
    Colors.amber,
    Colors.deepOrange,
  ];

  const ClassPage({
    super.key,
    required this.title,
    required this.subjects,
  });

  String _getRouteName(String className, String subjectName) {
    // Convert class name (e.g., "Class 1" to "class1")
    String classRoute = className.toLowerCase().replaceAll(' ', '');

    // Convert subject name to route name
    String subjectRoute = '';
    switch (subjectName) {
      // Primary Classes (1-5)
      case 'আমার বাংলা বই':
        subjectRoute = '_bangla';
        break;
      case 'English For Today':
        subjectRoute = '_english';
        break;
      case 'প্রাথমিক গণিত':
        subjectRoute = '_math';
        break;
      case 'প্রাথমিক বিজ্ঞান':
        subjectRoute = '_science';
        break;
      case 'বাংলাদেশ ও বিশ্বপরিচয়':
        subjectRoute = '_social_science';
        break;
      case 'ইসলাম ও নৈতিক শিক্ষা':
        subjectRoute = '_religion';
        break;

      // Secondary Classes (6-8)
      case 'বাংলা':
        subjectRoute = '_bangla';
        break;
      case 'English':
        subjectRoute = '_english';
        break;
      case 'গণিত':
        subjectRoute = '_math';
        break;
      case 'বিজ্ঞান অনুসন্ধানী পাঠ':
        subjectRoute = '_science_inquiry';
        break;
      case 'বিজ্ঞান অনুশীলন':
        subjectRoute = '_science_practice';
        break;
      case 'ইতিহাস ও সামাজিক বিজ্ঞান':
        subjectRoute = '_social_science';
        break;
      case 'ডিজিটাল প্রযুক্তি':
        subjectRoute = '_digital_tech';
        break;
      case 'স্বাস্থ্য সুরক্ষা':
        subjectRoute = '_health';
        break;
      case 'জীবন ও জীবিকা':
        subjectRoute = '_life_career';
        break;
      case 'শিল্প ও সংস্কৃতি':
        subjectRoute = '_arts_culture';
        break;
      case 'ইসলাম শিক্ষা':
        subjectRoute = '_islam';
        break;
      case 'হিন্দুধর্ম শিক্ষা':
        subjectRoute = '_hindu';
        break;
      case 'খ্রিস্ট্রধর্ম শিক্ষা':
        subjectRoute = '_christian';
        break;
      case 'বৌদ্ধধর্ম শিক্ষা':
        subjectRoute = '_buddhist';
        break;
    }

    return '/$classRoute$subjectRoute';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(title: title),
      drawer: const AppDrawer(),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.blue.shade50,
              Colors.purple.shade50,
            ],
          ),
        ),
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: subjects.length,
          itemBuilder: (context, index) {
            final subject = subjects[index];
            final color = _cardColors[index % _cardColors.length];

            return Theme(
              data: Theme.of(context).copyWith(
                primaryColor: color,
                colorScheme: ColorScheme.fromSeed(
                  seedColor: color,
                  primary: color,
                ),
              ),
              child: Container(
                margin: const EdgeInsets.only(bottom: 16),
                child: Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        subject['icon'],
                        size: 24,
                        color: color,
                      ),
                    ),
                    title: Text(
                      subject['name'] ?? '',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: color,
                      ),
                    ),
                    onTap: () {
                      String route = _getRouteName(title, subject['name']);
                      Navigator.pushNamed(context, route);
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
