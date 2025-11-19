import 'package:flutter/material.dart';
import '../widgets/custom_app_bar.dart';

class QuestionBankContent extends StatelessWidget {
  const QuestionBankContent({super.key});

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final List<Map<String, dynamic>> educationLevels = [
      {
        'title': 'Secondary Education',
        'items': [
          {
            'name': 'Class 6',
            'icon': Icons.filter_6,
            'route': '/class6',
            'description': 'Questions for Class 6',
            'accentColor': Colors.red
          },
          {
            'name': 'Class 7',
            'icon': Icons.filter_7,
            'route': '/class7',
            'description': 'Questions for Class 7',
            'accentColor': Colors.orange
          },
          {
            'name': 'Class 8',
            'icon': Icons.filter_8,
            'route': '/class8',
            'description': 'Questions for Class 8',
            'accentColor': Colors.yellow
          },
          {
            'name': 'SSC',
            'icon': Icons.school,
            'route': '/ssc',
            'description': 'Questions for SSC exams',
            'accentColor': Colors.green
          },
        ]
      },
      {
        'title': 'Higher Education',
        'items': [
          {
            'name': 'HSC',
            'icon': Icons.school,
            'route': '/hsc',
            'description': 'Questions for HSC exams',
            'accentColor': Colors.blue
          },
          {
            'name': '7 College',
            'icon': Icons.account_balance,
            'route': '/seven_college',
            'description': 'Questions for 7 College admissions',
            'accentColor': Colors.indigo
          },
          {
            'name': 'National University',
            'icon': Icons.account_balance,
            'route': '/national_university',
            'description': 'Questions for National University admissions',
            'accentColor': Colors.purple
          },
          {
            'name': 'Nursing',
            'icon': Icons.medical_services,
            'route': '/nursing',
            'description': 'Questions for Nursing admissions',
            'accentColor': Colors.deepPurple
          }
        ]
      },
      {
        'title': 'Admission',
        'items': [
          {
            'name': 'GST',
            'icon': Icons.assignment,
            'route': '/gst',
            'description': 'Questions for GST admission tests',
            'accentColor': Colors.pink
          },
          {
            'name': '7 College',
            'icon': Icons.account_balance,
            'route': '/seven_college_admission',
            'description': 'Questions for 7 College admission tests',
            'accentColor': Colors.brown
          },
          {
            'name': 'Engineering',
            'icon': Icons.engineering,
            'route': '/engineering_universities',
            'description': 'Questions for Engineering university admission tests',
            'accentColor': Colors.cyan
          },
          {
            'name': 'University',
            'icon': Icons.school_outlined,
            'route': '/universities',
            'description': 'Questions for general university admission tests',
            'accentColor': Colors.lightBlue
          },
          {
            'name': 'Nursing',
            'icon': Icons.medical_services,
            'route': '/nursing_admission',
            'description': 'Questions for Nursing admission tests',
            'accentColor': Colors.lime
          },
          {
            'name': 'Medical',
            'icon': Icons.local_hospital,
            'route': '/medical',
            'description': 'Questions for Medical college admission tests',
            'accentColor': Colors.amber
          },
        ]
      },
    ];

    return Scaffold(
      backgroundColor: Colors.white, // Set background to white
      appBar: const CustomAppBar(
        title: 'Question Bank',
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
                          color: Colors.black, // Ensure text is visible on white background
                        ),
                      ),
                    ),
                  ),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.9,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: section['items'].length,
                    itemBuilder: (context, itemIndex) {
                      final item = section['items'][itemIndex];
                      return _buildQuestionBankItem(
                          context, item, isLandscape, item['accentColor']);
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
  Widget _buildQuestionBankItem(BuildContext context, Map<String, dynamic> item,
      bool isLandscape, Color accentColor) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: () {
            if (item['route'] != null) {
              Navigator.pushNamed(context, item['route']);
            }
          },
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.max,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(item['icon'], size: 24, color: accentColor),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: Text(
                    item['name'],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 4),
                Flexible(
                  child: Text(
                    item['description'],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Explore',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: accentColor,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.arrow_forward, size: 10, color: accentColor),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}