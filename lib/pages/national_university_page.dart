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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 0),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16.0, vertical: 12.0),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.8),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: List.generate(headers.length, (index) {
                      final isSelected =
                          selectedHeader == getFullHeader(headers[index]);
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.grey.shade100,
                              foregroundColor:
                                  isSelected ? Colors.white : Colors.black87,
                              elevation: isSelected ? 4 : 0,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(25),
                                side: BorderSide(
                                  color: isSelected
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.transparent,
                                  width: 1,
                                ),
                              ),
                            ),
                            onPressed: () {
                              setState(() {
                                selectedHeader = getFullHeader(headers[index]);
                              });
                            },
                            child: Text(
                              headers[index],
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: getFilteredItems().length,
                  itemBuilder: (context, index) {
                    final item = getFilteredItems()[index];
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
                        margin: const EdgeInsets.symmetric(vertical: 8.0),
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
                                item['icon'],
                                size: 24,
                                color: color,
                              ),
                            ),
                            title: Text(
                              item['name'],
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
                              if (item['route'] != null) {
                                Navigator.pushNamed(context, item['route']);
                              }
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
