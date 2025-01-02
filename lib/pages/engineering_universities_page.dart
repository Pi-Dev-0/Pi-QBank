import 'package:flutter/material.dart';
import '../widgets/app_drawer.dart';
import '../widgets/custom_app_bar.dart';

class EngineeringUniversitiesPage extends StatelessWidget {
  const EngineeringUniversitiesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final universities = [
      {
        'name': 'BUET',
        'fullName': 'Bangladesh University of Engineering and Technology',
        'location': 'Dhaka',
        'established': '1962',
        'route': '/buet',
      },
      {
        'name': 'CUET',
        'fullName': 'Chittagong University of Engineering and Technology',
        'location': 'Chittagong',
        'established': '1968',
        'route': '/cuet',
      },
      {
        'name': 'RUET',
        'fullName': 'Rajshahi University of Engineering and Technology',
        'location': 'Rajshahi',
        'established': '1964',
        'route': '/ruet',
      },
      {
        'name': 'KUET',
        'fullName': 'Khulna University of Engineering and Technology',
        'location': 'Khulna',
        'established': '1967',
        'route': '/kuet',
      },
      {
        'name': 'DUET',
        'fullName': 'Dhaka University of Engineering and Technology',
        'location': 'Gazipur',
        'established': '1980',
        'route': '/duet',
      },
    ];

    return Scaffold(
      appBar: const CustomAppBar(title: 'Engineering Universities'),
      drawer: const AppDrawer(),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: universities.length,
        itemBuilder: (context, index) {
          final university = universities[index];
          return Card(
            elevation: 4,
            margin: const EdgeInsets.only(bottom: 16),
            child: InkWell(
              onTap: () {
                if (university['route'] != null) {
                  Navigator.pushNamed(context, university['route']!);
                }
              },
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
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
                    Text(
                      university['fullName']!,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.location_on, size: 16),
                        const SizedBox(width: 4),
                        Text(university['location']!),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 16),
                        const SizedBox(width: 4),
                        Text('Established: ${university["established"]}'),
                      ],
                    ),
                  ],
                ),
                trailing: const Icon(Icons.arrow_forward_ios),
              ),
            ),
          );
        },
      ),
    );
  }
}
