import 'package:flutter/material.dart';
import '../widgets/app_drawer.dart';
import '../widgets/custom_app_bar.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final List<Map<String, dynamic>> educationLevels = [
      {
        'title': 'Primary Education',
        'items': [
          {'name': 'Class 1', 'icon': Icons.filter_1, 'route': '/class1'},
          {'name': 'Class 2', 'icon': Icons.filter_2, 'route': '/class2'},
          {'name': 'Class 3', 'icon': Icons.filter_3, 'route': '/class3'},
          {'name': 'Class 4', 'icon': Icons.filter_4, 'route': '/class4'},
          {'name': 'Class 5', 'icon': Icons.filter_5, 'route': '/class5'},
        ]
      },
      {
        'title': 'Secondary Education',
        'items': [
          {'name': 'Class 6', 'icon': Icons.filter_6, 'route': '/class6'},
          {'name': 'Class 7', 'icon': Icons.filter_7, 'route': '/class7'},
          {'name': 'Class 8', 'icon': Icons.filter_8, 'route': '/class8'},
          {'name': 'SSC', 'icon': Icons.school, 'route': '/ssc'},
        ]
      },
      {
        'title': 'Higher Education',
        'items': [
          {'name': 'HSC', 'icon': Icons.school, 'route': '/hsc'},
          {
            'name': '7 College',
            'icon': Icons.account_balance,
            'route': '/seven_college',
          },
          {
            'name': 'National University',
            'icon': Icons.account_balance,
            'route': '/national_university',
          },
          {
            'name': 'Nursing',
            'icon': Icons.medical_services,
            'route': '/nursing',
          }
        ]
      },
      {
        'title': 'Admission',
        'items': [
          {'name': 'GST', 'icon': Icons.assignment, 'route': '/gst'},
          {
            'name': '7 College',
            'icon': Icons.account_balance,
            'route': '/seven_college_admission'
          },
          {
            'name': 'Engineering',
            'icon': Icons.engineering,
            'route': '/engineering_universities'
          },
          {
            'name': 'University',
            'icon': Icons.school_outlined,
            'route': '/universities'
          },
          {
            'name': 'Nursing',
            'icon': Icons.medical_services,
            'route': '/nursing_admission'
          },
          {
            'name': 'Medical',
            'icon': Icons.local_hospital,
            'route': '/medical'
          },
        ]
      },
    ];

    return Scaffold(
      appBar: const CustomAppBar(title: 'Pi-Mathematics'),
      drawer: const AppDrawer(),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Education Levels
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: educationLevels.length,
            itemBuilder: (context, sectionIndex) {
              final section = educationLevels[sectionIndex];
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Center(
                      child: Text(
                        section['title'],
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: isLandscape ? 3 : 2,
                      childAspectRatio: isLandscape ? 2 : 1.5,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: section['items'].length,
                    itemBuilder: (context, itemIndex) {
                      final item = section['items'][itemIndex];
                      return Card(
                        elevation: 4,
                        child: InkWell(
                          onTap: () {
                            if (item['route'] != null) {
                              Navigator.pushNamed(context, item['route']);
                            }
                          },
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                item['icon'],
                                size: isLandscape ? 28 : 32,
                                color: Theme.of(context).primaryColor,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                item['name'],
                                style: TextStyle(
                                  fontSize: isLandscape ? 14 : 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),

          // Books Section
          const SizedBox(height: 24),
          const Divider(
            thickness: 1,
            color: Colors.grey,
          ),
          const SizedBox(height: 24),
          Card(
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            child: InkWell(
              onTap: () {
                Navigator.pushNamed(context, '/books');
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.menu_book,
                      size: 40,
                      color: Theme.of(context).primaryColor,
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Books',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // --- Add PDF Reader Button Below ---
          const SizedBox(height: 24),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.blue,
                  Colors.purple,
                  Colors.pinkAccent,
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                foregroundColor: Colors.white,
                elevation: 0,
              ),
              icon: const Icon(Icons.picture_as_pdf, size: 28),
              label: const Text(
                'Local PDF',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                Navigator.pushNamed(context, '/pdf_reader');
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
