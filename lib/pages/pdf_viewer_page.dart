import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'dart:io';
import '../widgets/custom_app_bar.dart';

class PDFViewerPage extends StatelessWidget {
  final String filePath;
  final String title;

  const PDFViewerPage({
    super.key,
    required this.filePath,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final file = File(filePath);

    return Scaffold(
      appBar: CustomAppBar(title: title),
      body: PDFView(
        filePath: file.path,
        enableSwipe: true,
        swipeHorizontal: false,
        autoSpacing: false,
        pageFling: false,
      ),
    );
  }
} 