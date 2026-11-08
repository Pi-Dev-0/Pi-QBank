import 'package:flutter/material.dart';

import 'in_app_pdf_viewer_page.dart';

/// Opens a local PDF in the in-app PDFium reader.
///
/// Every supported platform now uses the same PDFium-based viewer instead of
/// maintaining a separate platform-specific implementation.
class PDFViewerPage extends StatelessWidget {
  final String filePath;
  final String title;
  final String? password;

  const PDFViewerPage({
    super.key,
    required this.filePath,
    required this.title,
    this.password,
  });

  @override
  Widget build(BuildContext context) {
    return InAppPdfViewerPage(
      filePath: filePath,
      title: title,
      password: password,
    );
  }
}
