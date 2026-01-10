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
  final int? index;
  final String? creator;

  const QuestionPaperCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.year,
    required this.examYear,
    required this.downloadUrl,
    required this.category,
    this.index,
    this.creator,
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
                color: Theme.of(context).primaryColor.withOpacity(0.1),
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
            icon: const Icon(
              Icons.cloud_download_outlined,
              size: 18,
              color: Colors.white,
            ),
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

  Color _getAccentColor() {
    final colors = [
      const Color(0xFF6C5CE7), // Indigo
      const Color(0xFF00B894), // Teal
      const Color(0xFFFDCB6E), // Amber
      const Color(0xFFE84393), // Rose
      const Color(0xFF0984E3), // Blue
      const Color(0xFF6D214F), // Plum
      const Color(0xFF00CEC9), // Cyan
      const Color(0xFF6AB04C), // Green
    ];
    final colorIndex = widget.index != null
        ? widget.index! % colors.length
        : widget.title.hashCode.abs() % colors.length;
    return colors[colorIndex];
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = _getAccentColor();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.08),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Section
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.06),
                border: Border(
                  bottom: BorderSide(color: accentColor.withOpacity(0.1)),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2D3436),
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: accentColor.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  widget.subtitle,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: accentColor,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            if (widget.examYear.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Text(
                                widget.examYear,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (widget.creator != null &&
                            widget.creator!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                Icons.person_outline_rounded,
                                size: 14,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  widget.creator!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  _buildHeaderActions(accentColor),
                ],
              ),
            ),
            // Progress Bar (if downloading)
            if (_isDownloading)
              LinearProgressIndicator(
                value: _downloadProgress,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                minHeight: 3,
              ),
            // Actions Section
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: _buildActionButton(
                      label: 'View Online',
                      icon: Icons.public_rounded,
                      onPressed: () => _viewOnlinePDF(context),
                      color: Colors.grey[100]!,
                      textColor: const Color(0xFF2D3436),
                      isPrimary: false,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildActionButton(
                      label: _isFileDownloaded
                          ? 'View Offline'
                          : (_isDownloading ? 'Downloading...' : 'Download'),
                      icon: _isFileDownloaded
                          ? Icons.visibility_rounded
                          : Icons.file_download_rounded,
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
                      color: _isFileDownloaded
                          ? Colors.green[50]!
                          : accentColor.withOpacity(0.12),
                      textColor:
                          _isFileDownloaded ? Colors.green[700]! : accentColor,
                      isPrimary: true,
                    ),
                  ),
                ],
              ),
            ),
            // Hidden Ad Trigger
            SizedBox(
              height: 1,
              child: AdsterraService.showAd(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderActions(Color accentColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_isFileDownloaded && _downloadedFilePath != null)
          _buildTinyIconButton(
            icon: Icons.refresh_rounded,
            onPressed: () => _redownloadFile(context),
            color: accentColor.withOpacity(0.8),
            tooltip: 'Redownload',
          ),
        _buildTinyIconButton(
          icon: _isBookmarked
              ? Icons.bookmark_rounded
              : Icons.bookmark_outline_rounded,
          onPressed: _toggleBookmark,
          color: _isBookmarked ? accentColor : Colors.grey[400]!,
          tooltip: 'Bookmark',
        ),
        if (_isFileDownloaded)
          _buildTinyIconButton(
            icon: Icons.delete_outline_rounded,
            onPressed: _deleteDownloadedFile,
            color: Colors.red[300]!,
            tooltip: 'Delete',
          ),
      ],
    );
  }

  Widget _buildTinyIconButton({
    required IconData icon,
    required VoidCallback onPressed,
    required Color color,
    required String tooltip,
  }) {
    return IconButton(
      icon: Icon(icon, color: color, size: 22),
      onPressed: onPressed,
      tooltip: tooltip,
      splashRadius: 20,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    required Color color,
    required Color textColor,
    required bool isPrimary,
  }) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: textColor),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
