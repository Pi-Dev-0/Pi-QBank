import 'package:flutter/material.dart';
import 'package:pi_qbank/widgets/custom_app_bar.dart';
import 'package:pi_qbank/pages/prepare_short_test_page.dart'; // Import the new page

class ToolsPage extends StatelessWidget {
  const ToolsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'Tools'),
      body: GridView.count(
        crossAxisCount: 2,
        padding: const EdgeInsets.all(16.0),
        crossAxisSpacing: 16.0,
        mainAxisSpacing: 16.0,
        children: [
          _buildToolCard(context, Icons.assignment, 'Short Test', () {
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => const PrepareShortTestPage()),
            );
          }),
          _buildToolCard(context, Icons.quiz, 'MCQ Generator', () {
            // Navigate to MCQ Generator page
          }),
          _buildToolCard(
              context, Icons.text_fields, 'Short & Broad Question Generator',
              () {
            // Navigate to Short & Broad Question Generator page
          }),
          _buildToolCard(context, Icons.image_search, 'Image to Text', () {
            // Navigate to Image to Text page
          }),
        ],
      ),
    );
  }

  Widget _buildToolCard(
      BuildContext context, IconData icon, String title, VoidCallback onTap) {
    return Card(
      elevation: 8.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12.0),
        child: Center(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 8.0, vertical: 16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(icon, size: 48.0, color: Theme.of(context).primaryColor),
                const SizedBox(height: 12.0),
                Flexible(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 16.0, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
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
