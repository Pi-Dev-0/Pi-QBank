import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui'; // Import for ImageFilter
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import '../widgets/custom_app_bar.dart';
import '../pages/pdf_viewer_page.dart';
import '../widgets/delete_confirmation_dialog.dart';

class PdfReaderPage extends StatefulWidget {
  const PdfReaderPage({super.key});

  @override
  State<PdfReaderPage> createState() => _PdfReaderPageState();
}

class _PdfReaderPageState extends State<PdfReaderPage>
    with TickerProviderStateMixin {
  List<FileSystemEntity> pdfFiles = [];
  bool loading = true;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // Colorful gradient colors
  final List<List<Color>> gradientColors = [
    [const Color(0xFF667eea), const Color(0xFF764ba2)],
    [const Color(0xFFf093fb), const Color(0xFFf5576c)],
    [const Color(0xFF4facfe), const Color(0xFF00f2fe)],
    [const Color(0xFF43e97b), const Color(0xFF38f9d7)],
    [const Color(0xFFfa709a), const Color(0xFFfee140)],
    [const Color(0xFFa8edea), const Color(0xFFfed6e3)],
    [const Color(0xFFffecd2), const Color(0xFFfcb69f)],
    [const Color(0xFFd299c2), const Color(0xFFfef9d7)],
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    _fetchPdfFiles();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _fetchPdfFiles() async {
    setState(() {
      loading = true;
    });

    // Request storage permission
    if (Platform.isAndroid) {
      if (!await Permission.manageExternalStorage.request().isGranted) {
        setState(() {
          loading = false;
        });
        return;
      }
    } else {
      if (!await Permission.storage.request().isGranted) {
        setState(() {
          loading = false;
        });
        return;
      }
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

    _animationController.forward();
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
      debugPrint('Error scanning PDFs!');
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = (math.log(bytes) / math.log(1024)).floor();
    return '${(bytes / math.pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  Color _getFileSizeColor(int bytes) {
    final sizeInMB = bytes / (1024 * 1024);
    if (sizeInMB < 1) return Colors.green;
    if (sizeInMB < 10) return Colors.orange;
    return Colors.red;
  }

  Widget _buildLoadingWidget() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.transparent,
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withOpacity(0.2),
                    Colors.blue.withOpacity(0.1),
                    Colors.purple.withOpacity(0.1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: const CircularProgressIndicator(),
            ),
            const SizedBox(height: 24),
            Text(
              'Loading PDF...',
              style: TextStyle(
                color: Colors.blue.shade700, // Changed text color
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Please wait while we prepare your document',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFffecd2), Color(0xFFfcb69f)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withOpacity(0.3),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Icon(
                Icons.picture_as_pdf_rounded,
                size: 80,
                color: Colors.orange[600],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No PDF files found',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try adding some PDF files to your device',
              style: TextStyle(
                fontSize: 16,
                color: Colors.white.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(
        title: 'Local PDF',
        centerTitle: true,
      ),
      body: loading
          ? _buildLoadingWidget()
          : pdfFiles.isEmpty
              ? _buildEmptyState()
              : Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                  ),
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: pdfFiles.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 16),
                      itemBuilder: (context, index) {
                        final file = pdfFiles[index];
                        final colorIndex = index % gradientColors.length;
                        final gradients = gradientColors[colorIndex];

                        return AnimatedContainer(
                          duration: Duration(milliseconds: 300 + (index * 100)),
                          curve: Curves.easeOutBack,
                          child: Card(
                            elevation: 8,
                            shadowColor: gradients[0].withOpacity(0.4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    gradients[0].withOpacity(0.1),
                                    gradients[1].withOpacity(0.05),
                                  ],
                                ),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 16),
                                leading: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: gradients,
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: gradients[0].withOpacity(0.4),
                                        blurRadius: 8,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  padding: const EdgeInsets.all(12),
                                  child: const Icon(
                                    Icons.picture_as_pdf_rounded,
                                    color: Colors.white,
                                    size: 32,
                                  ),
                                ),
                                title: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      file.path.split('/').last,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: Color(0xFF2D3748),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 2,
                                    ),
                                    const SizedBox(height: 8),
                                    FutureBuilder<int>(
                                      future: File(file.path).length(),
                                      builder: (context, snapshot) {
                                        if (snapshot.hasData) {
                                          return Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: _getFileSizeColor(
                                                      snapshot.data!)
                                                  .withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: _getFileSizeColor(
                                                    snapshot.data!),
                                                width: 1,
                                              ),
                                            ),
                                            child: Text(
                                              _formatFileSize(snapshot.data!),
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: _getFileSizeColor(
                                                    snapshot.data!),
                                              ),
                                            ),
                                          );
                                        }
                                        return Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.withOpacity(0.1),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: const Text(
                                            'Calculating...',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.red.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: IconButton(
                                        icon: const Icon(
                                          Icons.delete_forever_rounded,
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
                                            paperTitle:
                                                file.path.split('/').last,
                                          );
                                          if (shouldDelete == true) {
                                            await file.delete();
                                            _fetchPdfFiles();
                                          }
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: gradients,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      padding: const EdgeInsets.all(8),
                                      child: const Icon(
                                        Icons.arrow_forward_ios_rounded,
                                        size: 16,
                                        color: Colors.white,
                                      ),
                                    ),
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
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
    );
  }
}
