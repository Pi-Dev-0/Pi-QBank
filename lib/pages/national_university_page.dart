import 'package:flutter/material.dart';
import '../widgets/app_drawer.dart';
import '../widgets/custom_app_bar.dart';

class NationalUniversityPage extends StatefulWidget {
  const NationalUniversityPage({super.key});

  @override
  State<NationalUniversityPage> createState() => _NationalUniversityPageState();
}

class _NationalUniversityPageState extends State<NationalUniversityPage> {
  String? selectedHeader = '(BSc)';

  final List<String> headers = [
    'BSc',
    'BA/BSS',
    'BBA',
  ];

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> items = [
      {'isHeader': true, 'name': '(BSc)'},
      {
        'name': 'Physics',
        'icon': Icons.science,
        'route': '/national_university/physics'
      },
      {
        'name': 'Chemistry',
        'icon': Icons.science_outlined,
        'route': '/national_university/chemistry'
      },
      {
        'name': 'Bio-Chemistry',
        'icon': Icons.biotech,
        'route': '/nu_biochemistry'
      },
      {
        'name': 'Mathematics',
        'icon': Icons.functions,
        'route': '/national_university/mathematics'
      },
      {
        'name': 'Statistics',
        'icon': Icons.bar_chart,
        'route': '/nu_statistics'
      },
      {'name': 'Botany', 'icon': Icons.local_florist, 'route': '/nu_botany'},
      {'name': 'Zoology', 'icon': Icons.pets, 'route': '/nu_zoology'},
      {
        'name': 'Environment Science',
        'icon': Icons.eco,
        'route': '/nu_environment_science'
      },
      {'isHeader': true, 'name': '(BA/BSS)'},
      {'name': 'Bangla', 'icon': Icons.book, 'route': '/nu_bangla'},
      {'name': 'English', 'icon': Icons.language, 'route': '/nu_english'},
      {'name': 'History', 'icon': Icons.history_edu, 'route': '/nu_history'},
      {
        'name': 'Islamic Studies',
        'icon': Icons.mosque,
        'route': '/nu_islamic_studies'
      },
      {
        'name': 'Political Science',
        'icon': Icons.policy,
        'route': '/nu_political_science'
      },
      {'name': 'Sociology', 'icon': Icons.groups, 'route': '/nu_sociology'},
      {
        'name': 'Economics',
        'icon': Icons.attach_money,
        'route': '/nu_economics'
      },
      {'isHeader': true, 'name': '(BBA)'},
      {
        'name': 'Marketing',
        'icon': Icons.trending_up,
        'route': '/nu_marketing'
      },
      {
        'name': 'Finance',
        'icon': Icons.account_balance,
        'route': '/nu_finance'
      },
      {
        'name': 'Accounting',
        'icon': Icons.account_balance_wallet,
        'route': '/nu_accounting'
      },
      {'name': 'Management', 'icon': Icons.business, 'route': '/nu_management'},
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
      appBar: const CustomAppBar(title: 'National University'),
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
      case 'BSc':
        return '(BSc)';
      case 'BA/BSS':
        return '(BA/BSS)';
      case 'BBA':
        return '(BBA)';
      default:
        return shortName;
    }
  }
}
