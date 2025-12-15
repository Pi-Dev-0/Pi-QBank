import 'package:flutter/material.dart';
import '../widgets/app_drawer.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/group_selector.dart';

class HSCPage extends StatefulWidget {
  const HSCPage({super.key});

  @override
  State<HSCPage> createState() => _HSCPageState();
}

class _HSCPageState extends State<HSCPage> {
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
      {'name': 'বাংলা ১ম পত্র', 'icon': Icons.book, 'route': '/hsc_bangla_1st'},
      {
        'name': 'বাংলা ২য় পত্র',
        'icon': Icons.book,
        'route': '/hsc_bangla_2nd'
      },
      {
        'name': 'English 1st Paper',
        'icon': Icons.language,
        'route': '/hsc_english_1st'
      },
      {
        'name': 'English 2nd Paper',
        'icon': Icons.language_outlined,
        'route': '/hsc_english_2nd'
      },
      {'name': 'ICT', 'icon': Icons.computer, 'route': '/hsc_ict'},
    ];

    switch (group) {
      case 'Science':
        return [
          ...commonSubjects,
          {
            'name': 'পদার্থবিজ্ঞান ১ম পত্র',
            'icon': Icons.precision_manufacturing,
            'route': '/hsc_physics_1st'
          },
          {
            'name': 'পদার্থবিজ্ঞান ২য় পত্র',
            'icon': Icons.precision_manufacturing_outlined,
            'route': '/hsc_physics_2nd'
          },
          {
            'name': 'রসায়ন ১ম পত্র',
            'icon': Icons.science,
            'route': '/hsc_chemistry_1st'
          },
          {
            'name': 'রসায়ন ২য় পত্র',
            'icon': Icons.science_outlined,
            'route': '/hsc_chemistry_2nd'
          },
          {
            'name': 'জীববিজ্ঞান ১ম পত্র',
            'icon': Icons.biotech,
            'route': '/hsc_biology_1st'
          },
          {
            'name': 'জীববিজ্ঞান ২য় পত্র',
            'icon': Icons.biotech_outlined,
            'route': '/hsc_biology_2nd'
          },
          {
            'name': 'উচ্চতর গণিত ১ম পত্র',
            'icon': Icons.functions,
            'route': '/hsc_math_1st'
          },
          {
            'name': 'উচ্চতর গণিত ২য় পত্র',
            'icon': Icons.calculate,
            'route': '/hsc_math_2nd'
          },
        ];
      case 'Humanities':
        return [
          ...commonSubjects,
          {
            'name': 'ইতিহাস ১ম পত্র',
            'icon': Icons.history_edu,
            'route': '/hsc_history_1st'
          },
          {
            'name': 'ইতিহাস ২য় পত্র',
            'icon': Icons.history_edu_outlined,
            'route': '/hsc_history_2nd'
          },
          {
            'name': 'ভূগোল ১ম পত্র',
            'icon': Icons.public,
            'route': '/hsc_geography_1st'
          },
          {
            'name': 'ভূগোল ২য় পত্র',
            'icon': Icons.public_outlined,
            'route': '/hsc_geography_2nd'
          },
          {
            'name': 'অর্থনীতি ১ম পত্র',
            'icon': Icons.attach_money,
            'route': '/hsc_economics_1st'
          },
          {
            'name': 'অর্থনীতি ২য় পত্র',
            'icon': Icons.attach_money,
            'route': '/hsc_economics_2nd'
          },
        ];
      case 'Business':
        return [
          ...commonSubjects,
          {
            'name': 'ব্যবসায় শিক্ষা ১ম পত্র',
            'icon': Icons.business,
            'route': '/hsc_business_org_1st'
          },
          {
            'name': 'ব্যবসায় শিক্ষা ২য় পত্র',
            'icon': Icons.business_outlined,
            'route': '/hsc_business_org_2nd'
          },
          {
            'name': 'হিসাববিজ্ঞান ১ম পত্র',
            'icon': Icons.account_balance_wallet,
            'route': '/hsc_accounting_1st'
          },
          {
            'name': 'হিসাববিজ্ঞান ২য় পত্র',
            'icon': Icons.account_balance_wallet_outlined,
            'route': '/hsc_accounting_2nd'
          },
          {
            'name': 'অর্থনীতি ১ম পত্র',
            'icon': Icons.attach_money,
            'route': '/hsc_economics_1st'
          },
          {
            'name': 'অর্থনীতি ২য় পত্র',
            'icon': Icons.attach_money,
            'route': '/hsc_economics_2nd'
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
      appBar: const CustomAppBar(title: 'Higher Secondary Certificate (HSC)'),
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
