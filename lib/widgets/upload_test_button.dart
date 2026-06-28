import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:developer' as dev;

class UploadTestButton extends StatefulWidget {
  final List<dynamic> questions;
  final String testType;
  final String language;

  const UploadTestButton({
    super.key,
    required this.questions,
    required this.testType,
    required this.language,
  });

  @override
  State<UploadTestButton> createState() => _UploadTestButtonState();
}

class _UploadTestButtonState extends State<UploadTestButton> {
  bool _isUploading = false;
  final String _googleWebAppUrl = 'https://script.google.com/macros/s/AKfycbwAMFYO2yPtEmxK1Jbhu727bSvFei8I7ZQzUqXm079Gzj4w_tw9xreN3j3bl9mrwtkbTg/exec';

  void _showCategorizationDialog() {
    String selectedClass = 'SSC';
    String selectedSubject = 'Bangla';
    final TextEditingController topicController = TextEditingController();

    final List<String> classList = ['One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'JSC', 'SSC', 'HSC', 'Job'];
    final List<String> subjectList = ['Bangla', 'English', 'Math', 'ICT', 'Physics', 'Chemistry', 'Biology', 'General Knowledge'];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('Categorize Questions', style: TextStyle(fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: selectedClass,
                      decoration: const InputDecoration(labelText: 'Select Class'),
                      items: classList.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: (val) => setModalState(() => selectedClass = val!),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: selectedSubject,
                      decoration: const InputDecoration(labelText: 'Select Subject'),
                      items: subjectList.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                      onChanged: (val) => setModalState(() => selectedSubject = val!),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: topicController,
                      decoration: const InputDecoration(
                        labelText: 'Enter Topic',
                        hintText: 'e.g., Pronoun, Algebra, Kinetic Theory',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Back'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade600, foregroundColor: Colors.white),
                  onPressed: () {
                    final String topic = topicController.text.trim();
                    if (topic.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter a topic name')),
                      );
                      return;
                    }
                    Navigator.pop(context);
                    _uploadData(selectedClass, selectedSubject, topic);
                  },
                  child: const Text('Submit & Upload'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _uploadData(String className, String subject, String topic) async {
    setState(() => _isUploading = true);

    final requestUrl = Uri.parse(_googleWebAppUrl);
    final requestBody = json.encode({
      "class": className,
      "subject": subject,
      "topic": topic,
      "test_type": widget.testType,
      "language": widget.language,
      "questions": widget.questions,
    });

    dev.log('--- UPLOAD DEBUG START ---', name: 'UploadData');
    dev.log('Request URL: $requestUrl', name: 'UploadData');
    dev.log('Request Body: $requestBody', name: 'UploadData');

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Uploading questions to Cloud Sheet...'), duration: Duration(seconds: 2)),
    );

    try {
      final response = await http.post(
        requestUrl,
        headers: {"Content-Type": "application/json"},
        body: requestBody,
      );

      dev.log('Response Status Code: ${response.statusCode}', name: 'UploadData');
      dev.log('Response Headers: ${response.headers}', name: 'UploadData');
      dev.log('Response Body: ${response.body}', name: 'UploadData');
      dev.log('--- UPLOAD DEBUG END ---', name: 'UploadData');

      if (response.statusCode == 200 || response.statusCode == 302) {
        _showSuccessHUD('Data securely uploaded to Google Sheets!');
      } else {
        _showError('Upload error [${response.statusCode}]. Check terminal!');
      }
    } catch (e, stackTrace) {
      dev.log(
        'Exception during upload!',
        name: 'UploadData',
        error: e,
        stackTrace: stackTrace,
      );
      dev.log('--- UPLOAD DEBUG END (with error) ---', name: 'UploadData');
      _showError('Upload exception: ${e.runtimeType} — $e\n(Stack trace logged to console)');
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showSuccessHUD(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isUploading) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          color: Colors.teal.shade50,
        ),
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: const Center(
          child: CircularProgressIndicator(color: Colors.teal),
        ),
      );
    }
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        gradient: LinearGradient(
          colors: [Colors.teal.shade500, Colors.teal.shade700],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.teal.withOpacity(0.4),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: _showCategorizationDialog,
        icon: const Icon(Icons.cloud_upload_outlined, color: Colors.white),
        label: const Text(
          'Upload Test to Google Sheet',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          minimumSize: const Size(double.infinity, 55),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }
}
