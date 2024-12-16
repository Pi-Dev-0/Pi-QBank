import 'package:flutter/material.dart';

class TermsOfServicePage extends StatelessWidget {
  const TermsOfServicePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Terms of Service'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Terms of Service for Pi-QBank',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Last updated: ${DateTime.now().toString().split(' ')[0]}',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 24),
            _buildSection(
              'Acceptance of Terms',
              'By accessing or using Pi-QBank, you agree to be bound by these Terms of Service.',
            ),
            _buildSection(
              'Use License',
              'Permission is granted to temporarily download one copy of Pi-QBank for personal, non-commercial use only.',
            ),
            _buildSection(
              'User Content',
              'Users are responsible for the content they create and share through the app.',
            ),
            _buildSection(
              'Content Sources',
              'The question papers, books, and guides provided through the app are collected from various social media platforms and online blogs available on the internet. All content is curated for educational purposes.',
            ),
            _buildSection(
              'Intellectual Property and Restrictions',
              '• Users are strictly prohibited from extracting, decompiling, or reverse engineering the app\'s source code\n'
              '• It is not permitted to decode the app or its APIs to collect, share, or modify the app\'s question papers, books, or guides data\n'
              '• All content within the app is protected and any unauthorized extraction or modification is prohibited\n'
              '• The app and its contents are for personal educational use only',
            ),
            _buildSection(
              'Intellectual Property',
              'The app and its original content are and will remain the exclusive property of Pi Mathematics.',
            ),
            _buildSection(
              'Disclaimer',
              'Your use of Pi-QBank is at your sole risk. The service is provided on an "AS IS" and "AS AVAILABLE" basis.',
            ),
            _buildSection(
              'Limitation of Liability',
              'Pi Mathematics shall not be liable for any indirect, incidental, special, consequential, or punitive damages.',
            ),
            _buildSection(
              'Changes to Terms',
              'We reserve the right to modify or replace these Terms at any time.',
            ),
            _buildSection(
              'Contact',
              'If you have any questions about these Terms, please contact us at:\n'
              'Email: pimathematics1@gmail.com',
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: const TextStyle(
              fontSize: 16,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
