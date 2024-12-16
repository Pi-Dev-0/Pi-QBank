import 'package:flutter/material.dart';
import '../widgets/app_drawer.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/group_selector.dart';

class SSCPage extends StatefulWidget {
  const SSCPage({super.key});

  @override
  State<SSCPage> createState() => _SSCPageState();
}

class _SSCPageState extends State<SSCPage> {
  String selectedGroup = 'Science';
  final List<String> groups = ['Science', 'Humanities', 'Business'];

  List<Map<String, dynamic>> getSubjectsForGroup(String group) {
    final List<Map<String, dynamic>> commonSubjects = [
      {'name': 'বাংলা ১ম পত্র', 'icon': Icons.book, 'route': '/ssc_bangla_1st'},
      {'name': 'বাংলা ২য় পত্র', 'icon': Icons.book, 'route': '/ssc_bangla_2nd'},
      {'name': 'English 1st Paper', 'icon': Icons.language, 'route': '/ssc_english_1st'},
      {'name': 'English 2nd Paper', 'icon': Icons.language, 'route': '/ssc_english_2nd'},
      {'name': 'গণিত', 'icon': Icons.functions, 'route': '/ssc_math'},
      {'name': 'ধর্ম ও নৈতিক শিক্ষা', 'icon': Icons.mosque, 'route': '/ssc_religion'},
      {'name': 'তথ্য ও যোগাযোগ প্রযুক্তি', 'icon': Icons.computer, 'route': '/ssc_ict'},
    ];

    switch (group) {
      case 'Science':
        return [
          ...commonSubjects,
          {'name': 'উচ্চতর গণিত', 'icon': Icons.calculate, 'route': '/ssc_higher_math'},
          {'name': 'পদার্থবিজ্ঞান', 'icon': Icons.precision_manufacturing, 'route': '/ssc_physics'},
          {'name': 'রসায়ন', 'icon': Icons.science_outlined, 'route': '/ssc_chemistry'},
          {'name': 'জীববিজ্ঞান', 'icon': Icons.biotech, 'route': '/ssc_biology'},
          {'name': 'বাংলাদেশ ও বিশ্ব পরিচয়', 'icon': Icons.public, 'route': '/ssc_bgst'},
        ];
      case 'Humanities':
        return [
          ...commonSubjects,
          {'name': 'ভূগোল', 'icon': Icons.public, 'route': '/ssc_geography'},
          {'name': 'ইতিহাস', 'icon': Icons.history_edu, 'route': '/ssc_history'},
          {'name': 'পৌরনীতি', 'icon': Icons.policy, 'route': '/ssc_civics'},
        ];
      case 'Business':
        return [
          ...commonSubjects,
          {'name': 'অর্থনীতি', 'icon': Icons.attach_money, 'route': '/ssc_economics'},
          {'name': 'ব্যবসায় উদ্যোগ', 'icon': Icons.business, 'route': '/ssc_business'},
          {'name': 'হিসাববিজ্ঞান', 'icon': Icons.account_balance_wallet, 'route': '/ssc_accounting'},
          {'name': 'ফিন্যান্স ও ব্যাংকিং', 'icon': Icons.account_balance, 'route': '/ssc_finance'},
        ];
      default:
        return commonSubjects;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final subjects = getSubjectsForGroup(selectedGroup);

    return Scaffold(
      appBar: const CustomAppBar(title: 'Secondary School Certificate (SSC)'),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          GroupSelector(
            selectedGroup: selectedGroup,
            groups: groups,
            onGroupChanged: (group) {
              if (group != null) {
                setState(() {
                  selectedGroup = group;
                });
              }
            },
          ),
          Expanded(
            child: Padding(
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
          ),
        ],
      ),
    );
  }
}
