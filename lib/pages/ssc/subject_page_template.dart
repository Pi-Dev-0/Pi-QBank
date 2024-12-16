import 'package:flutter/material.dart';
import '../../widgets/notification_icon.dart';

class SSCSubjectPage extends StatefulWidget {
  final String subjectName;
  final String subjectCode;
  final Color primaryColor;
  final Color secondaryColor;

  const SSCSubjectPage({
    super.key,
    required this.subjectName,
    required this.subjectCode,
    required this.primaryColor,
    required this.secondaryColor,
  });

  @override
  State<SSCSubjectPage> createState() => _SSCSubjectPageState();
}

class _SSCSubjectPageState extends State<SSCSubjectPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('SSC ${widget.subjectName}'),
        backgroundColor: widget.primaryColor,
        actions: const [NotificationIcon()],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              widget.primaryColor,
              widget.secondaryColor,
            ],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            _buildChapterSection(),
            const SizedBox(height: 20),
            _buildResourceSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildChapterSection() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Chapters',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            // Add chapter list here
          ],
        ),
      ),
    );
  }

  Widget _buildResourceSection() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Resources',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            // Add resource list here
          ],
        ),
      ),
    );
  }
}
