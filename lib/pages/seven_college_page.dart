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
    // Color palette for cards
    final List<Color> cardColors = const [
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
                    final color = cardColors[index % cardColors.length];

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
