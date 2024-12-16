import 'package:flutter/material.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy Policy'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Privacy Policy for Pi-QBank',
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
              'Information Collection and Use',
              'Pi-QBank is committed to protecting your privacy. This Privacy Policy explains how we collect, use, and safeguard your information when you use our application.',
            ),
            _buildSection(
              'Data Collection',
              'We collect the following information:\n'
              '• User preferences and settings\n'
              '• App usage statistics\n'
              '• Device information for crash reporting',
            ),
            _buildSection(
              'Data Usage',
              'The collected information is used to:\n'
              '• Improve app functionality\n'
              '• Provide personalized content\n'
              '• Fix bugs and improve performance',
            ),
            _buildSection(
              'File Upload Services',
              'We use file.io to temporarily store files you upload:\n'
              '• Files are transmitted to file.io\'s servers\n'
              '• We only accept PDF and image files (jpg, jpeg, png, gif)\n'
              '• Files are automatically deleted from file.io\'s servers after a short period\n'
              '• All file transfers use secure HTTPS connections',
            ),
            _buildSection(
              'Data Storage',
              'Your data is stored on your device and is not shared with any third parties.',
            ),
            _buildSection(
              'Third-Party Services',
              'Our app integrates with the following third-party services:\n'
              '• Firebase Analytics for app usage statistics\n'
              '• We use Google Sheet API to provide question papers\n'
              '• Firebase Crashlytics for crash reporting\n'
              '• File.io (File Hosting Service):\n'
              '  • Purpose: Temporary file storage and transfer\n'
              '  • Data shared: User-uploaded files\n'
              '  • Data retention: Files are temporarily stored\n'
              '  • For more information, visit file.io\'s privacy policy',
            ),
            _buildSection(
              'User Rights',
              'Regarding file uploads, you have the right to:\n'
              '• Know how your uploaded files are processed\n'
              '• Request information about file storage duration\n'
              '• Understand that files are subject to file.io\'s terms\n'
              '• Be informed about our security measures',
            ),
            _buildSection(
              'Security Measures',
              'To protect your uploaded files:\n'
              '• We use secure HTTPS connections\n'
              '• Files are only temporarily stored\n'
              '• We limit file types to PDFs and images\n'
              '• We implement file size restrictions',
            ),
            _buildSection(
              'Children\'s Privacy',
              'Our app is designed for educational purposes and may be used by children. We comply with COPPA (Children\'s Online Privacy Protection Act) and do not knowingly collect personal information from children under 13 without parental consent.',
            ),
            _buildSection(
              'Changes to Privacy Policy',
              'We may update our Privacy Policy from time to time. We will notify you of any changes by posting the new Privacy Policy on this page.',
            ),
            _buildSection(
              'Contact Us',
              'If you have any questions about our Privacy Policy, please contact us at:\n'
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
