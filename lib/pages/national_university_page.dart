import 'package:flutter/material.dart';
import '../widgets/app_drawer.dart';
import '../widgets/custom_app_bar.dart';

class NationalUniversityPage extends StatelessWidget {
  const NationalUniversityPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    
    final List<Map<String, dynamic>> subjects = [
      {
        'name': 'Mathematics',
        'icon': Icons.functions,
        'route': '/nu_mathematics'
      },
      {
        'name': 'Physics',
        'icon': Icons.science,
        'route': '/nu_physics'
      },
      {
        'name': 'Chemistry',
        'icon': Icons.science_outlined,
        'route': '/nu_chemistry'
      },
      {
        'name': 'Statistics',
        'icon': Icons.bar_chart,
        'route': '/nu_statistics'
      },
      {
        'name': 'Economics',
        'icon': Icons.attach_money,
        'route': '/nu_economics'
      },
      {
        'name': 'Accounting',
        'icon': Icons.account_balance_wallet,
        'route': '/nu_accounting'
      },
      {
        'name': 'Management',
        'icon': Icons.business,
        'route': '/nu_management'
      },
      {
        'name': 'English',
        'icon': Icons.language,
        'route': '/nu_english'
      },
      {
        'name': 'Bangla',
        'icon': Icons.book,
        'route': '/nu_bangla'
      },
      {
        'name': 'History',
        'icon': Icons.history_edu,
        'route': '/nu_history'
      },
      {
        'name': 'Islamic Studies',
        'icon': Icons.mosque,
        'route': '/nu_islamic_studies'
      },
    ];

    return Scaffold(
      appBar: const CustomAppBar(title: 'National University'),
      drawer: const AppDrawer(),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: isLandscape ? 3 : 2,
            childAspectRatio: isLandscape ? 2 : 1.5,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: subjects.length,
          itemBuilder: (context, index) {
            final subject = subjects[index];
            return Card(
              elevation: 4,
              child: InkWell(
                onTap: () {
                  if (subject['route'] != null) {
                    Navigator.pushNamed(context, subject['route']);
                  }
                },
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      subject['icon'],
                      size: isLandscape ? 28 : 32,
                      color: Theme.of(context).primaryColor,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subject['name'],
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
      ),
    );
  }
} 