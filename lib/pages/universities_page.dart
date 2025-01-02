import 'package:flutter/material.dart';
import '../widgets/app_drawer.dart';
import '../widgets/custom_app_bar.dart';

class UniversitiesPage extends StatelessWidget {
  const UniversitiesPage({super.key});

  @override
  Widget build(BuildContext context) {
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
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.school, size: 16),
                        const SizedBox(width: 4),
                        Text('Type: ${university["type"]}'),
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
