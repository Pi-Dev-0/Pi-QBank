
import 'package:flutter/material.dart';
import 'package:pi_qbank/widgets/custom_app_bar.dart';

class EducationalLinksPage extends StatelessWidget {
  const EducationalLinksPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Educational Links',
      ),
      body: ListView(
        children: const [
          ListTile(
            title: Text('Education Board Results'),
            subtitle: Text('http://www.educationboardresults.gov.bd/'),
          ),
          ListTile(
            title: Text('Directorate of Primary Education'),
            subtitle: Text('http://www.dpe.gov.bd/'),
          ),
          ListTile(
            title: Text('Ministry of Education'),
            subtitle: Text('https://moedu.gov.bd/'),
          ),
          ListTile(
            title: Text('University Grants Commission'),
            subtitle: Text('http://www.ugc.gov.bd/'),
          ),
        ],
      ),
    );
  }
}
