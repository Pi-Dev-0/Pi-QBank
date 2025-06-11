import 'package:flutter/material.dart';
import 'package:pi_qbank/widgets/custom_app_bar.dart';
import 'package:pi_qbank/pages/prepare_short_test_page.dart';
import 'package:pi_qbank/widgets/api_key_dialog.dart';
import 'package:pi_qbank/pages/mcq_generator_page.dart'; // Import MCQGeneratorPage
import '../widgets/app_drawer.dart'; // Import AppDrawer

class ToolsPage extends StatelessWidget {
  const ToolsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: CustomAppBar(
        title: 'Tools',
      ),
      drawer: const AppDrawer(), // Add AppDrawer to ToolsPage Scaffold
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // API Key information section moved to top
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.blue.shade50,
                    Colors.green.shade50,
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.vpn_key,
                        color: Colors.blue.shade600,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Use Your Own API Key',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'To get full access to all features, simply add your own API key. '
                    'This gives you complete control over your usage and costs.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      showApiKeyDialog(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Setup API Key'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Tools grid
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 16.0,
              mainAxisSpacing: 16.0,
              childAspectRatio: 0.9,
              children: [
                _buildToolCard(
                  context,
                  Icons.assignment_outlined,
                  'Short Test',
                  'Create quick assessments',
                  Colors.blue,
                  () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const PrepareShortTestPage(),
                      ),
                    );
                  },
                ),
                _buildToolCard(
                  context,
                  Icons.quiz_outlined,
                  'MCQ Generator',
                  'Generate multiple choice questions',
                  Colors.green,
                  () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const MCQGeneratorPage(),
                      ),
                    );
                  },
                ),
                _buildToolCard(
                  context,
                  Icons.text_fields_outlined,
                  'Question Generator',
                  'Create short & broad questions',
                  Colors.purple,
                  () {
                    // Navigate to Short & Broad Question Generator page
                  },
                ),
                _buildToolCard(
                  context,
                  Icons.assignment_outlined,
                  'Exam Paper Builder',
                  'Create custom question papers & tests',
                  Colors.orange,
                  () {
                    // Navigate to Exam Paper Builder page
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolCard(
    BuildContext context,
    IconData icon,
    String title,
    String description,
    Color accentColor,
    VoidCallback onTap,
  ) {
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
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(16), // Reduced padding
            constraints:
                const BoxConstraints(maxHeight: 180), // Added max height
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min, // Changed to min
              children: [
                // Icon container
                Container(
                  padding: const EdgeInsets.all(12), // Reduced padding
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12), // Reduced radius
                  ),
                  child:
                      Icon(icon, size: 24, color: accentColor), // Reduced size
                ),

                const SizedBox(height: 12), // Reduced spacing

                // Title
                Flexible(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14, // Reduced font size
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                const SizedBox(height: 4), // Reduced spacing

                // Description
                Flexible(
                  child: Text(
                    description,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11, // Reduced font size
                      color: Colors.grey.shade600,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                const SizedBox(height: 8), // Reduced spacing

                // Action indicator
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4), // Reduced padding
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Try now',
                        style: TextStyle(
                          fontSize: 10, // Reduced font size
                          fontWeight: FontWeight.w600,
                          color: accentColor,
                        ),
                      ),
                      const SizedBox(width: 2), // Reduced spacing
                      Icon(Icons.arrow_forward,
                          size: 10, color: accentColor), // Reduced size
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
