import 'package:flutter/material.dart';
import 'dart:io';
import '../pages/pdf_viewer_page.dart';
import '../widgets/delete_confirmation_dialog.dart';

class DownloadedPaperCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String examYear;
  final String category;
  final String filePath;
  final VoidCallback onDeleted;

  const DownloadedPaperCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.examYear,
    required this.category,
    required this.filePath,
    required this.onDeleted,
  });

  Future<void> _openPDF(BuildContext context) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PDFViewerPage(
          filePath: filePath,
          title: title,
        ),
      ),
    );
  }

  void _handleDelete(BuildContext context) async {
    final shouldDelete = await showDeleteConfirmationDialog(
      context: context,
      title: 'Delete Paper',
      message: 'Are you sure you want to delete this paper?',
      paperTitle: title,
      paperSubtitle: subtitle,
    );

    if (shouldDelete == true) {
      try {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
          onDeleted();
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error deleting paper')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => _openPDF(context),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Icon/Leading
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.picture_as_pdf_rounded,
                    color: Colors.blue[700],
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                // Text Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2D3436),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle.isEmpty ? examYear : '$subtitle • $examYear',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (category.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            category.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Colors.blue[400],
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // Actions
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.red[300],
                        size: 22,
                      ),
                      onPressed: () => _handleDelete(context),
                      tooltip: 'Delete',
                      visualDensity: VisualDensity.compact,
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.grey,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
