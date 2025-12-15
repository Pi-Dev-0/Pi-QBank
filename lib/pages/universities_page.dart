import 'package:flutter/material.dart';
import '../widgets/app_drawer.dart';
import '../widgets/custom_app_bar.dart';

class UniversitiesPage extends StatelessWidget {
  const UniversitiesPage({super.key});

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

    final universities = [
      {
        'name': 'University of Dhaka',
        'location': 'Dhaka',
        'established': '1921',
        'type': 'Public',
        'route': '/dhaka_university',
      },
      {
        'name': 'Rajshahi University',
        'location': 'Rajshahi',
        'established': '1953',
        'type': 'Public',
        'route': '/rajshahi_university',
      },
      {
        'name': 'Chittagong University',
        'location': 'Chittagong',
        'established': '1966',
        'type': 'Public',
        'route': '/chittagong_university',
      },
      {
        'name': 'Jahangirnagar University',
        'location': 'Savar, Dhaka',
        'established': '1970',
        'type': 'Public',
        'route': '/jahangirnagar_university',
      },
      {
        'name': 'Bangladesh Agricultural University',
        'location': 'Mymensingh',
        'established': '1961',
        'type': 'Public',
        'route': '/agricultural_university',
      },
    ];

    return Scaffold(
      appBar: const CustomAppBar(title: 'Universities'),
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
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: universities.length,
          itemBuilder: (context, index) {
            final university = universities[index];
            final color = cardColors[index % cardColors.length];

            return Theme(
              data: Theme.of(context).copyWith(
                primaryColor: color,
                colorScheme: ColorScheme.fromSeed(
                  seedColor: color,
                  primary: color,
                ),
              ),
              child: Card(
                elevation: 4,
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: InkWell(
                  onTap: () {
                    if (university['route'] != null) {
                      Navigator.pushNamed(context, university['route']!);
                    }
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white,
                          color.withOpacity(0.05),
                        ],
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.school,
                          color: color,
                          size: 28,
                        ),
                      ),
                      title: Text(
                        university['name']!,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.location_on,
                                  size: 16, color: Colors.grey.shade600),
                              const SizedBox(width: 4),
                              Text(university['location']!),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.calendar_today,
                                  size: 16, color: Colors.grey.shade600),
                              const SizedBox(width: 4),
                              Text('Established: ${university["established"]}'),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.category,
                                  size: 16, color: Colors.grey.shade600),
                              const SizedBox(width: 4),
                              Text('Type: ${university["type"]}'),
                            ],
                          ),
                        ],
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.arrow_forward_ios,
                            size: 16, color: color),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
