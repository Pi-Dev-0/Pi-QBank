import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'dart:io';
import '../pages/pdf_viewer_page.dart';
import '../services/services.dart';
import '../services/downloaded_papers_registry.dart';

class DownloadedFileRegistry {
  static final Map<String, String> _registry = {};

  static void registerFile(String uniqueId, String filePath) {
    _registry[uniqueId] = filePath;
  }

  static String? getFilePath(String uniqueId) {
    return _registry[uniqueId];
  }

  static void removeFile(String uniqueId) {
    _registry.remove(uniqueId);
  }
}

class QuestionPaperCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final String year;
  final String examYear;
  final String downloadUrl;
  final String category;

  const QuestionPaperCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.year,
    required this.examYear,
    required this.downloadUrl,
    required this.category,
  });

  @override
  State<QuestionPaperCard> createState() => _QuestionPaperCardState();
}

class _QuestionPaperCardState extends State<QuestionPaperCard> {
  bool _isDownloading = false;
  double _downloadProgress = 0;
  bool _isFileDownloaded = false;
  String? _downloadedFilePath;
  bool _isBookmarked = false;

  @override
  void initState() {
    super.initState();
    _checkExistingFile();
    _checkBookmarkStatus();
  }

  @override
  void didUpdateWidget(QuestionPaperCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.title != widget.title ||
        oldWidget.subtitle != widget.subtitle ||
        oldWidget.year != widget.year ||
        oldWidget.examYear != widget.examYear) {
      _checkExistingFile();
    }
  }

  Future<void> _checkExistingFile() async {
    if (!mounted) return;

    setState(() {
      _isFileDownloaded = false;
      _downloadedFilePath = null;
    });

    try {
      final filePath = await _findExistingFile();
      if (filePath != null && await _isValidPDF(filePath)) {
        if (!mounted) return;
        setState(() {
          _isFileDownloaded = true;
          _downloadedFilePath = filePath;
        });
        Logger().d(
            'Found valid downloaded file for: ${widget.title} (${widget.examYear})');
      } else {
        Logger()
            .d('No valid file found for: ${widget.title} (${widget.examYear})');
      }
    } catch (e) {
      Logger().e('Error checking existing file: $e');
      if (!mounted) return;
      setState(() {
        _isFileDownloaded = false;
        _downloadedFilePath = null;
      });
    }
  }

  Future<String?> _findExistingFile() async {
    try {
      final baseDir = await _storageDir;
      final uniqueFolder = _getUniqueFolder();
      final paperDir = Directory('$baseDir/$uniqueFolder');

      if (!await paperDir.exists()) {
        Logger().d(
            'Directory does not exist for: ${widget.title} (${widget.examYear})');
        return null;
      }

      final filePath = '${paperDir.path}/paper.pdf';
      final file = File(filePath);

      if (!await file.exists()) {
        Logger().d('File does not exist: $filePath');
        await paperDir.delete(recursive: true);
        return null;
      }

      if (!await _isValidPDF(filePath)) {
        Logger().d('Invalid PDF file: $filePath');
        await paperDir.delete(recursive: true);
        return null;
      }

      Logger().d(
          'Found valid PDF: $filePath for ${widget.title} (${widget.examYear})');
      return filePath;
    } catch (e) {
      Logger().e('Error in _findExistingFile: $e');
      return null;
    }
  }

  String _getUniqueFolder() {
    // Create a unique folder name combining all unique identifiers
    final sanitizedTitle =
        widget.title.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_').toLowerCase();
    final sanitizedSubtitle =
        widget.subtitle.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_').toLowerCase();
    final sanitizedExamYear =
        widget.examYear.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_').toLowerCase();
    final urlHash = widget.downloadUrl.hashCode.abs().toString();

    return 'paper_${widget.year}_${sanitizedExamYear}_${sanitizedTitle}_${sanitizedSubtitle}_$urlHash';
  }

  Future<String> get _storageDir async {
    if (Platform.isAndroid) {
      final List<Directory>? directories =
          await getExternalStorageDirectories();
      if (directories != null && directories.isNotEmpty) {
        final baseDir = directories[0].path;
        final appDir = Directory('$baseDir/Pi-QuestionBank');
        if (!await appDir.exists()) {
          await appDir.create(recursive: true);
        }
        Logger().d('Using external storage directory: ${appDir.path}');
        return appDir.path;
      }
    }
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  Future<bool> _isValidPDF(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return false;

      // Check if file size is too small
      final fileSize = await file.length();
      if (fileSize < 100) {
        await file.delete();
        Logger().d('File too small, deleting: $filePath');
        return false;
      }

      // Read first few bytes to check PDF signature
      final bytes = await file.openRead(0, 4).first;
      final signature = String.fromCharCodes(bytes);

      if (signature != '%PDF') {
        await file.delete();
        Logger().d('Invalid PDF signature, deleting: $filePath');
        return false;
      }

      // Add logging to debug file validation
      Logger().d('Valid PDF found: $filePath');
      return true;
    } catch (e) {
      Logger().e('Error validating PDF: $e');
      try {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
          Logger().d('Deleted invalid file after error: $filePath');
        }
      } catch (deleteError) {
        Logger().e('Error deleting invalid file: $deleteError');
      }
      return false;
    }
  }

  Future<void> _openPDF(String filePath, BuildContext context) async {
    // Capture BuildContext early
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      if (Platform.isAndroid || Platform.isIOS) {
        if (!mounted) {
          return; // Check mounted before using context for navigation
        }
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PDFViewerPage(
              filePath: filePath,
              title: widget.title,
            ),
          ),
        );
      } else {
        final result = await OpenFile.open(filePath);
        if (result.type != ResultType.done) {
          throw Exception('Could not open file: ${result.message}');
        }
      }
    } catch (e) {
      Logger().e('Error opening PDF: $e');
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        // Use captured scaffoldMessenger
        const SnackBar(
          content: Text('Could not open PDF file'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _downloadFile(BuildContext context) async {
    if (_isDownloading) return;

    // First check if file is already downloaded
    if (_isFileDownloaded && _downloadedFilePath != null) {
      _openPDF(_downloadedFilePath!, context);
      return;
    }

    if (!context.mounted) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
    });

    try {
      // Create unique filename including path
      final baseDir = await _storageDir;
      final uniqueFolder = _getUniqueFolder();
      final paperDir = Directory('$baseDir/$uniqueFolder');

      if (!await paperDir.exists()) {
        await paperDir.create(recursive: true);
      }

      final fileName = 'paper.pdf';
      final fullPath = '${paperDir.path}/$fileName';

      // Check if file exists
      final file = File(fullPath);
      if (await file.exists() && await _isValidPDF(fullPath)) {
        setState(() {
          _isFileDownloaded = true;
          _downloadedFilePath = fullPath;
          _isDownloading = false;
        });
        if (!context.mounted) return;
        _openPDF(fullPath, context);
        return;
      }

      // Download the file
      final downloadedFilePath = await DownloadService.downloadPDF(
        url: widget.downloadUrl,
        fileName: fileName,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _downloadProgress = progress;
            });
          }
        },
      );

      if (downloadedFilePath != null && mounted) {
        // Move the downloaded file to the correct location
        final downloadedFile = File(downloadedFilePath);
        await downloadedFile.copy(fullPath);
        await downloadedFile.delete(); // Delete the temporary file

        // Add to downloaded papers registry
        final downloadedPaper = DownloadedPaper(
          title: widget.title,
          subtitle: widget.subtitle,
          examYear: widget.examYear,
          category: widget.category,
          filePath: fullPath,
        );
        await DownloadedPapersRegistry().addDownloadedPaper(downloadedPaper);

        setState(() {
          _isFileDownloaded = true;
          _downloadedFilePath = fullPath;
          _downloadProgress = 1.0;
        });

        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: const Text(
              'Download complete',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: 'View',
              textColor: Colors.white,
              onPressed: () {
                if (_downloadedFilePath != null) {
                  _openPDF(_downloadedFilePath!, context);
                }
              },
            ),
          ),
        );
      }
    } catch (e) {
      Logger().e('Download error: $e');
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  Future<void> _redownloadFile(BuildContext context) async {
    // Capture BuildContext early
    if (!context.mounted) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      // Delete the entire folder if it exists
      if (_downloadedFilePath != null) {
        final file = File(_downloadedFilePath!);
        final folder = file.parent;
        if (await folder.exists()) {
          await folder.delete(recursive: true);
        }
      }

      // Reset state and start new download
      if (!mounted) return;
      setState(() {
        _isFileDownloaded = false;
        _downloadedFilePath = null;
      });

      if (!context.mounted) return;
      _downloadFile(context);
    } catch (e) {
      Logger().e('Error redownloading file: $e');
      if (!context.mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _checkBookmarkStatus() async {
    final isBookmarked = await BookmarkService.isBookmarked(
      widget.downloadUrl,
      widget.subtitle,
      widget.title,
    );
    if (mounted) {
      setState(() => _isBookmarked = isBookmarked);
    }
  }

  Future<void> _toggleBookmark() async {
    final paper = BookmarkedPaper(
      title: widget.title,
      subtitle: widget.subtitle,
      year: widget.year,
      examYear: widget.examYear,
      downloadUrl: widget.downloadUrl,
      category: widget.category,
    );

    await BookmarkService.toggleBookmark(paper);
    await _checkBookmarkStatus();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 6.0,
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
                    widget.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            if (_isDownloading && _downloadProgress > 0)
              Container(
                width: 40,
                height: 40,
                margin: const EdgeInsets.only(right: 8),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: _downloadProgress,
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).primaryColor),
                    ),
                    Text(
                      '${(_downloadProgress * 100).toInt()}%',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isFileDownloaded && _downloadedFilePath != null)
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: () => _redownloadFile(context),
                      tooltip: 'Redownload',
                      color: Colors.grey,
                    ),
                  ElevatedButton.icon(
                    onPressed: _isDownloading
                        ? null
                        : () {
                            if (_isFileDownloaded &&
                                _downloadedFilePath != null) {
                              _openPDF(_downloadedFilePath!, context);
                            } else {
                              _downloadFile(context);
                            }
                          },
                    icon: _isDownloading
                        ? const SizedBox.shrink() // No icon while downloading
                        : Icon(
                            _isFileDownloaded
                                ? Icons.visibility
                                : Icons.download,
                            color: _isFileDownloaded ? Colors.white : null,
                            size: 20,
                          ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isFileDownloaded ? Colors.green : null,
                      foregroundColor: _isFileDownloaded ? Colors.white : null,
                      elevation: 4,
                      shadowColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    label: Text(
                      _isFileDownloaded
                          ? 'View'
                          : (_isDownloading ? 'Downloading' : 'Download'),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            Padding(
              padding: const EdgeInsets.only(right: 0),
              child: IconButton(
                icon: Icon(
                  _isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                  color: _isBookmarked
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: _toggleBookmark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
