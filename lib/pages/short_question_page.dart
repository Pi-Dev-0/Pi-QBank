import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../widgets/custom_app_bar.dart';

class ShortQuestionPage extends StatefulWidget {
  final int numberOfQuestions;
  final int testTimeInMinutes;
  final XFile? selectedImage;
  final String aiResponse;
  final String language;

  const ShortQuestionPage({
    Key? key,
    required this.numberOfQuestions,
    required this.testTimeInMinutes,
    this.selectedImage,
    required this.aiResponse,
    required this.language,
  }) : super(key: key);

  @override
  State<ShortQuestionPage> createState() => _ShortQuestionPageState();
}

class _ShortQuestionPageState extends State<ShortQuestionPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Short Questions (${widget.language})',
      ),
      body: const Center(
        child: Text('Short Question Implementation'),
      ),
    );
  }
}
