import 'package:flutter/material.dart';
import 'dart:io';
import '../pages/pdf_viewer_page.dart';

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

  Future<void> _deletePaper(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Paper'),
        content: const Text('Are you sure you want to delete this paper?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
          onDeleted();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Paper deleted successfully',
                  style: TextStyle(color: Colors.white),
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
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
    return Card(
      elevation: 5,
      shadowColor: Colors.grey[600],
      color: Colors.white,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 0, 16),
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle.isEmpty ? examYear : '$subtitle - $examYear',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (category.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          category,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue[900],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _openPDF(context),
                  icon: const Icon(
                    Icons.visibility,
                    color: Colors.white,
                    size: 20,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    elevation: 6,
                    shadowColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  label: const Text(
                    'View',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _deletePaper(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
