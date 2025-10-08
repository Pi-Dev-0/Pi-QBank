import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'dart:io';
import '../pages/pdf_viewer_page.dart';
import '../pages/online_pdf_viewer_page.dart';
import '../services/services.dart';
import '../services/downloaded_papers_registry.dart';
import '../services/adsterra_service.dart';
import '../widgets/delete_confirmation_dialog.dart';

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
      }
    } catch (e) {
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
        return null;
      }

      final filePath = '${paperDir.path}/paper.pdf';
      final file = File(filePath);

      if (!await file.exists()) {
        await paperDir.delete(recursive: true);
        return null;
      }

      if (!await _isValidPDF(filePath)) {
        await paperDir.delete(recursive: true);
        return null;
      }
      return filePath;
    } catch (e) {
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
        return appDir.path;
      }
    }
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  Future<bool> _isValidPDF(String filePath) async {
    try {
      final file = File(filePath);
      final fileExists = await file.exists();
      if (!fileExists) return false;

      // Check if file size is too small
      final fileSize = await file.length();
      if (fileSize < 100) {
        await file.delete();
        return false;
      }

      // Read first few bytes to check PDF signature
      final bytes = await file.openRead(0, 4).first;
      final signature = String.fromCharCodes(bytes);

      if (signature != '%PDF') {
        await file.delete();
        return false;
      }

      return true;
    } catch (e) {
      try {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (deleteError) {
        // Error deleting invalid file, silently ignore
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

    if (_isFileDownloaded && _downloadedFilePath != null) {
      _openPDF(_downloadedFilePath!, context);
      return;
    }

    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      // Show ad dialog and capture result before async gap
      final shouldDownload = await AdsterraService.showAdDialog(context);

      // Check mounted after async operation
      if (!mounted) return;

      // Use captured context through scaffoldMessenger
      if (shouldDownload) {
        await _startDownload(scaffoldMessenger);
      }
    } catch (e) {
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _startDownload(ScaffoldMessengerState messenger) async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
    });

    try {
      final baseDir = await _storageDir;
      final uniqueFolder = _getUniqueFolder();
      final paperDir = Directory('$baseDir/$uniqueFolder');

      if (!await paperDir.exists()) {
        await paperDir.create(recursive: true);
      }

      final fileName = 'paper.pdf';
      final fullPath = '${paperDir.path}/$fileName';

      final file = File(fullPath);
      if (await file.exists() && await _isValidPDF(fullPath)) {
        setState(() {
          _isFileDownloaded = true;
          _downloadedFilePath = fullPath;
          _isDownloading = false;
        });
        return;
      }

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
        final downloadedFile = File(downloadedFilePath);
        await downloadedFile.copy(fullPath);
        await downloadedFile.delete();

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

        messenger.showSnackBar(
          SnackBar(
            content: const Text('Download complete',
                style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: 'View',
              textColor: Colors.white,
              onPressed: () {
                if (_downloadedFilePath != null && mounted) {
                  _openPDF(_downloadedFilePath!, context);
                }
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  Future<void> _redownloadFile(BuildContext context) async {
    // Show confirmation dialog first
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.cloud_download_outlined,
                color: Theme.of(context).primaryColor,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Redownload Paper',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Do you want to redownload this paper?',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              widget.subtitle,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: Colors.grey[800],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.cloud_download_outlined, size: 18),
            label: const Text(
              'Redownload',
              style: TextStyle(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );

    if (confirmed != true) return;

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

  void _deleteDownloadedFile() async {
    if (_downloadedFilePath != null) {
      final shouldDelete = await showDeleteConfirmationDialog(
        context: context,
        title: 'Delete Paper',
        message: 'Are you sure you want to delete this paper?',
        paperTitle: widget.title,
        paperSubtitle: widget.subtitle,
      );

      if (shouldDelete == true) {
        final file = File(_downloadedFilePath!);
        final folder = file.parent;

        try {
          if (await folder.exists()) {
            await folder.delete(recursive: true);
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${widget.title} deleted'),
                backgroundColor: Colors.red,
              ),
            );
          }

          setState(() {
            _isFileDownloaded = false;
            _downloadedFilePath = null;
          });
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to delete ${widget.title}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    }
  }

  void _viewOnlinePDF(BuildContext context) {
    if (widget.downloadUrl.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OnlinePDFViewerPage(
            pdfUrl: widget.downloadUrl,
            title: widget.title,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PDF URL is not available'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Card(
          elevation: 8.0,
          shadowColor: Colors.black.withValues(alpha:0.8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
            side: BorderSide(
              color: Colors.grey.withValues(alpha:0.1),
              width: 0.2,
            ),
          ),
          margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha:0.1),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12.0),
                    topRight: Radius.circular(12.0),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(24, 12, 10, 6),
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
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 0),
                            decoration: BoxDecoration(
                              color: Colors.lightBlue.withValues(alpha:0.15),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              widget.subtitle,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.blue,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_isDownloading && _downloadProgress > 0)
                      Container(
                        width: 45,
                        height: 45,
                        margin: const EdgeInsets.only(right: 8),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CircularProgressIndicator(
                              value: _downloadProgress,
                              strokeWidth: 3,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Theme.of(context).primaryColor,
                              ),
                              backgroundColor: Colors.grey[200],
                            ),
                            Text(
                              '${(_downloadProgress * 100).toInt()}%',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      OverflowBar(
                        spacing: 0,
                        overflowAlignment: OverflowBarAlignment.end,
                        children: [
                          if (_isFileDownloaded && _downloadedFilePath != null)
                            IconButton(
                              icon: const Icon(Icons.cloud_download_outlined),
                              onPressed: () => _redownloadFile(context),
                              tooltip: 'Redownload',
                              color: Theme.of(context).primaryColor,
                              style: IconButton.styleFrom(
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                                highlightColor: Theme.of(context)
                                    .primaryColor
                                    .withValues(alpha:0.2),
                              ),
                            ),
                          IconButton(
                            icon: Icon(
                              _isBookmarked
                                  ? Icons.bookmark_rounded
                                  : Icons.bookmark_outline_rounded,
                              color: _isBookmarked
                                  ? Theme.of(context).primaryColor
                                  : Colors.grey[600],
                            ),
                            onPressed: _toggleBookmark,
                            style: IconButton.styleFrom(
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              highlightColor: Theme.of(context)
                                  .primaryColor
                                  .withValues(alpha:0.2),
                            ),
                          ),
                          if (_isFileDownloaded)
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                color: Colors.redAccent,
                              ),
                              onPressed: _deleteDownloadedFile,
                              tooltip: 'Delete File',
                              style: IconButton.styleFrom(
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                                highlightColor: Colors.red.withValues(alpha:0.2),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _viewOnlinePDF(context),
                        icon:
                            const Icon(Icons.remove_red_eye_outlined, size: 20),
                        label: const Text('View Online',
                            style: TextStyle(fontSize: 14, letterSpacing: 0.5)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                          elevation: 6,
                          shadowColor:
                              Theme.of(context).primaryColor.withValues(alpha:0.5),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: Colors.blue.shade800,
                                width: 1,
                              )),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton.icon(
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
                            ? const SizedBox.shrink()
                            : Icon(
                                _isFileDownloaded
                                    ? Icons.visibility_rounded
                                    : Icons.download_rounded,
                                size: 20,
                              ),
                        label: Text(
                          _isFileDownloaded
                              ? 'View Offline'
                              : (_isDownloading ? 'Downloading' : 'Download'),
                          style:
                              const TextStyle(fontSize: 14, letterSpacing: 0.5),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isFileDownloaded
                              ? Colors.green
                              : Colors.grey[200],
                          foregroundColor: _isFileDownloaded
                              ? Colors.white
                              : Colors.grey[800],
                          elevation: 6,
                          shadowColor:
                              (_isFileDownloaded ? Colors.green : Colors.grey)
                                  .withValues(alpha:0.5),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: _isFileDownloaded
                                    ? Colors.green.shade600
                                    : Colors.grey.shade400,
                                width: 1,
                              )),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          child: SizedBox(
            height: 1,
            width: 1,
            child: AdsterraService.showAd(),
          ),
        ),
      ],
    );
  }
}
