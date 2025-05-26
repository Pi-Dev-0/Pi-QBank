import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:math' as math;
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import '../widgets/custom_app_bar.dart';
import '../pages/pdf_viewer_page.dart';
import '../widgets/delete_confirmation_dialog.dart'; // Add this import

class PdfReaderPage extends StatefulWidget {
  const PdfReaderPage({super.key});

  @override
  State<PdfReaderPage> createState() => _PdfReaderPageState();
}

class _PdfReaderPageState extends State<PdfReaderPage> {
  List<FileSystemEntity> pdfFiles = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _fetchPdfFiles();
  }

  Future<void> _fetchPdfFiles() async {
    setState(() {
      loading = true;
    });

    // Request storage permission
    if (!await Permission.storage.request().isGranted) {
      setState(() {
        loading = false;
      });
      return;
    }

    Directory? rootDir;
    if (Platform.isAndroid) {
      rootDir = Directory('/storage/emulated/0');
    } else {
      rootDir = await getApplicationDocumentsDirectory();
    }

    List<FileSystemEntity> foundPdfs = [];
    await _scanForPdfs(rootDir, foundPdfs);

    setState(() {
      pdfFiles = foundPdfs;
      loading = false;
    });
  }

  Future<void> _scanForPdfs(
      Directory dir, List<FileSystemEntity> foundPdfs) async {
    try {
      if (dir.path == '/storage/emulated/0/Android') return;

      final entities = dir.listSync(recursive: false, followLinks: false);
      for (var entity in entities) {
        if (entity is File && entity.path.toLowerCase().endsWith('.pdf')) {
          // Check file size before adding
          final fileSize = await entity.length();
          final fileSizeInMB = fileSize / (1024 * 1024);

          // Skip files larger than 100MB to prevent OOM
          if (fileSizeInMB <= 250) {
            foundPdfs.add(entity);
          }
        } else if (entity is Directory && !entity.path.contains('/Android')) {
          await _scanForPdfs(entity, foundPdfs);
        }
      }
    } catch (e) {
      debugPrint('Error scanning PDFs: $e');
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = (math.log(bytes) / math.log(1024)).floor();
    return '${(bytes / math.pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(
        title: 'Local PDF',
        centerTitle: true,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : pdfFiles.isEmpty
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.picture_as_pdf,
                        size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    const Text(
                      'No PDF files found.',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: pdfFiles.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final file = pdfFiles[index];
                    return Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        leading: Container(
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.all(8),
                          child: Icon(Icons.picture_as_pdf,
                              color: Theme.of(context).primaryColor, size: 32),
                        ),
                        title: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              file.path.split('/').last,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            FutureBuilder<int>(
                              future: File(file.path).length(),
                              builder: (context, snapshot) {
                                return Text(
                                  snapshot.hasData
                                      ? _formatFileSize(snapshot.data!)
                                      : 'Calculating...',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.delete_forever,
                                color: Colors.red,
                                size: 24,
                              ),
                              onPressed: () async {
                                final shouldDelete =
                                    await showDeleteConfirmationDialog(
                                  context: context,
                                  title: 'Delete PDF',
                                  message:
                                      'Are you sure you want to delete this PDF file?',
                                  paperTitle: file.path.split('/').last,
                                );
                                if (shouldDelete == true) {
                                  await file.delete();
                                  _fetchPdfFiles();
                                }
                              },
                            ),
                            Icon(Icons.arrow_forward_ios,
                                size: 18, color: Colors.grey[600]),
                          ],
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PDFViewerPage(
                                filePath: file.path,
                                title: file.path.split('/').last,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
    );
  }
}
