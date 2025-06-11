import 'package:flutter/material.dart';
import 'package:pi_qbank/widgets/custom_app_bar.dart';

class ExamPaperBuilderPage extends StatelessWidget {
  const ExamPaperBuilderPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Exam Paper Builder',
      ),
      body: Center(
        child: Text('Exam Paper Builder Page Content'),
      ),
    );
  }
}
