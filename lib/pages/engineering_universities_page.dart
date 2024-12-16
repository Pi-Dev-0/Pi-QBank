import 'package:flutter/material.dart';
import '../widgets/app_drawer.dart';
import '../widgets/custom_app_bar.dart';

class EngineeringUniversitiesPage extends StatelessWidget {
  const EngineeringUniversitiesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final universities = [
      {
        'name': 'Bangladesh University of Engineering and Technology (BUET)',
        'location': 'Dhaka',
        'established': '1962',
        'type': 'Public',
      },
      {
        'name': 'Khulna University of Engineering & Technology (KUET)',
        'location': 'Khulna',
        'established': '1967',
        'type': 'Public',
      },
      {
        'name': 'Rajshahi University of Engineering & Technology (RUET)',
        'location': 'Rajshahi',
        'established': '1964',
        'type': 'Public',
      },
      {
        'name': 'Chittagong University of Engineering & Technology (CUET)',
        'location': 'Chittagong',
        'established': '1968',
        'type': 'Public',
      },
      {
        'name': 'Dhaka University of Engineering & Technology (DUET)',
        'location': 'Gazipur',
        'established': '1980',
        'type': 'Public',
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
            ),
          );
        },
      ),
    );
  }
} 