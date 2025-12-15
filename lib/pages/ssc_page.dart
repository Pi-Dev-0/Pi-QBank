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

  List<Map<String, dynamic>> getSubjectsForGroup(String group) {
    final List<Map<String, dynamic>> commonSubjects = [
      {'name': 'বাংলা ১ম পত্র', 'icon': Icons.book, 'route': '/ssc_bangla_1st'},
      {
        'name': 'বাংলা ২য় পত্র',
        'icon': Icons.book,
        'route': '/ssc_bangla_2nd'
      },
      {
        'name': 'English 1st Paper',
        'icon': Icons.language,
        'route': '/ssc_english_1st'
      },
      {
        'name': 'English 2nd Paper',
        'icon': Icons.language,
        'route': '/ssc_english_2nd'
      },
      {'name': 'গণিত', 'icon': Icons.functions, 'route': '/ssc_math'},
      {
        'name': 'ধর্ম ও নৈতিক শিক্ষা',
        'icon': Icons.mosque,
        'route': '/ssc_religion'
      },
      {
        'name': 'তথ্য ও যোগাযোগ প্রযুক্তি',
        'icon': Icons.computer,
        'route': '/ssc_ict'
      },
    ];

    switch (group) {
      case 'Science':
        return [
          ...commonSubjects,
          {
            'name': 'উচ্চতর গণিত',
            'icon': Icons.calculate,
            'route': '/ssc_higher_math'
          },
          {
            'name': 'পদার্থবিজ্ঞান',
            'icon': Icons.precision_manufacturing,
            'route': '/ssc_physics'
          },
          {
            'name': 'রসায়ন',
            'icon': Icons.science_outlined,
            'route': '/ssc_chemistry'
          },
          {
            'name': 'জীববিজ্ঞান',
            'icon': Icons.biotech,
            'route': '/ssc_biology'
          },
          {
            'name': 'বাংলাদেশ ও বিশ্ব পরিচয়',
            'icon': Icons.public,
            'route': '/ssc_bgst'
          },
        ];
      case 'Humanities':
        return [
          ...commonSubjects,
          {'name': 'ভূগোল', 'icon': Icons.public, 'route': '/ssc_geography'},
          {
            'name': 'ইতিহাস',
            'icon': Icons.history_edu,
            'route': '/ssc_history'
          },
          {'name': 'পৌরনীতি', 'icon': Icons.policy, 'route': '/ssc_civics'},
        ];
      case 'Business':
        return [
          ...commonSubjects,
          {
            'name': 'অর্থনীতি',
            'icon': Icons.attach_money,
            'route': '/ssc_economics'
          },
          {
            'name': 'ব্যবসায় উদ্যোগ',
            'icon': Icons.business,
            'route': '/ssc_business'
          },
          {
            'name': 'হিসাববিজ্ঞান',
            'icon': Icons.account_balance_wallet,
            'route': '/ssc_accounting'
          },
          {
            'name': 'ফিন্যান্স ও ব্যাংকিং',
            'icon': Icons.account_balance,
            'route': '/ssc_finance'
          },
        ];
      default:
        return commonSubjects;
    }
  }

  @override
  Widget build(BuildContext context) {
    final subjects = getSubjectsForGroup(selectedGroup);

    return Scaffold(
      appBar: const CustomAppBar(title: 'Secondary School Certificate (SSC)'),
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
        child: Column(
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
                            Navigator.pushNamed(context, subject['route']);
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
