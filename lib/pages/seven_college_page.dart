import 'package:flutter/material.dart';
import '../widgets/app_drawer.dart';
import '../widgets/custom_app_bar.dart';

class SevenCollegePage extends StatefulWidget {
  const SevenCollegePage({super.key});

  @override
  State<SevenCollegePage> createState() => _SevenCollegePageState();
}

class _SevenCollegePageState extends State<SevenCollegePage> {
  String? selectedHeader = '(Science)';

  final List<String> headers = [
    'Science',
    'Arts',
    'Business',
  ];

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> items = [
      {'isHeader': true, 'name': '(Science)'},
      {
        'name': 'Mathematics',
        'icon': Icons.functions,
        'route': '/seven_college_mathematics'
      },
      {'name': 'Physics', 'icon': Icons.science, 'route': '/sc_physics'},
      {
        'name': 'Chemistry',
        'icon': Icons.science_outlined,
        'route': '/sc_chemistry'
      },
      {
        'name': 'Statistics',
        'icon': Icons.bar_chart,
        'route': '/sc_statistics'
      },
      {'name': 'Biology', 'icon': Icons.biotech, 'route': '/sc_biology'},
      {
        'name': 'Computer Science',
        'icon': Icons.computer,
        'route': '/sc_computer_science'
      },
      {'isHeader': true, 'name': '(Arts)'},
      {'name': 'Bangla', 'icon': Icons.book, 'route': '/sc_bangla'},
      {'name': 'English', 'icon': Icons.language, 'route': '/sc_english'},
      {'name': 'History', 'icon': Icons.history_edu, 'route': '/sc_history'},
      {
        'name': 'Islamic Studies',
        'icon': Icons.mosque,
        'route': '/sc_islamic_studies'
      },
      {
        'name': 'Philosophy',
        'icon': Icons.psychology,
        'route': '/sc_philosophy'
      },
      {
        'name': 'Political Science',
        'icon': Icons.policy,
        'route': '/sc_political_science'
      },
      {'name': 'Sociology', 'icon': Icons.groups, 'route': '/sc_sociology'},
      {'isHeader': true, 'name': '(Business)'},
      {
        'name': 'Economics',
        'icon': Icons.attach_money,
        'route': '/sc_economics'
      },
      {
        'name': 'Accounting',
        'icon': Icons.account_balance_wallet,
        'route': '/sc_accounting'
      },
      {'name': 'Management', 'icon': Icons.business, 'route': '/sc_management'},
      {
        'name': 'Finance',
        'icon': Icons.account_balance,
        'route': '/sc_finance'
      },
      {
        'name': 'Marketing',
        'icon': Icons.trending_up,
        'route': '/sc_marketing'
      },
      {'name': 'Banking', 'icon': Icons.account_balance, 'route': '/sc_banking'}
    ];

    List<Map<String, dynamic>> getFilteredItems() {
      if (selectedHeader == null) return [];
      return items.where((item) {
        int headerIndex = items.indexWhere((element) =>
            element['isHeader'] == true && element['name'] == selectedHeader);
        int nextHeaderIndex = items.indexWhere(
            (element) => element['isHeader'] == true, headerIndex + 1);
        if (nextHeaderIndex == -1) nextHeaderIndex = items.length;

        int itemIndex = items.indexOf(item);
        return itemIndex > headerIndex &&
            itemIndex < nextHeaderIndex &&
            item['isHeader'] != true;
      }).toList();
    }

    return Scaffold(
      appBar: const CustomAppBar(title: 'Seven College'),
      drawer: const AppDrawer(),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: List.generate(headers.length, (index) {
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              selectedHeader == getFullHeader(headers[index])
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.white,
                          foregroundColor:
                              selectedHeader == getFullHeader(headers[index])
                                  ? Colors.white
                                  : Colors.black87,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          elevation: 8,
                          shadowColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () {
                          setState(() {
                            selectedHeader = getFullHeader(headers[index]);
                          });
                        },
                        child: Text(
                          headers[index],
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: getFilteredItems().length,
                itemBuilder: (context, index) {
                  final item = getFilteredItems()[index];
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Card(
                      elevation: 5,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          if (item['route'] != null) {
                            Navigator.pushNamed(context, item['route']);
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20.0,
                            vertical: 16.0,
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .primaryColor
                                      .withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  item['icon'],
                                  size: 28,
                                  color: Theme.of(context).primaryColor,
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: Text(
                                  item['name'],
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward_ios,
                                size: 16,
                                color: Colors.grey[600],
                              ),
                            ],
                          ),
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

  String getFullHeader(String shortName) {
    switch (shortName) {
      case 'Science':
        return '(Science)';
      case 'Arts':
        return '(Arts)';
      case 'Business':
        return '(Business)';
      default:
        return shortName;
    }
  }
}
