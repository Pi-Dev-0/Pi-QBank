import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'dart:io';
import '../pages/pdf_viewer_page.dart';
import '../pages/online_pdf_viewer_page.dart';
import '../services/services.dart';
import '../services/downloaded_papers_registry.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

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
  RewardedInterstitialAd? _rewardedInterstitialAd;
  bool _isAdLoading = false;
  bool _isShowingAd = false;
  final GlobalKey<State> _dialogKey = GlobalKey<State>();

  @override
  void initState() {
    super.initState();
    _checkExistingFile();
    _checkBookmarkStatus();
  }

  @override
  void dispose() {
    _rewardedInterstitialAd?.dispose();
    super.dispose();
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

  void _loadInterstitialAd({bool isRefresh = false}) {
    // Prevent multiple ad loading attempts
    if (_isAdLoading || _isShowingAd) return;

    setState(() {
      _isAdLoading = true;
    });

    // Show loading dialog with countdown
    _showAdLoadingDialog(isRefresh);

    // Load rewarded interstitial ad
    RewardedInterstitialAd.load(
      adUnitId: Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/5354046379' // Android test rewarded interstitial ad ID
          : 'ca-app-pub-3940256099942544/6978759866', // iOS test rewarded interstitial ad ID
      request: const AdRequest(),
      rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
        onAdLoaded: (ad) => _onAdLoaded(ad, isRefresh),
        onAdFailedToLoad: (error) => _onAdLoadFailed(error, isRefresh),
      ),
    );
  }

  void _showAdLoadingDialog(bool isRefresh) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => Center(
        key: _dialogKey,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text('Loading Ad...'),
                const SizedBox(height: 24),
                TweenAnimationBuilder<double>(
                  duration: const Duration(seconds: 5),
                  tween: Tween<double>(begin: 5, end: 0),
                  builder: (context, value, child) {
                    int countdown = value.toInt();
                    return Text(
                      '$countdown',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: _getCountdownColor(countdown + 1),
                      ),
                    );
                  },
                  onEnd: () => _handleCountdownEnd(isRefresh),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onAdLoaded(RewardedInterstitialAd ad, bool isRefresh) {
    _rewardedInterstitialAd = ad;
    _isAdLoading = false;
    Logger().d('Rewarded Interstitial Ad loaded successfully');

    // Dismiss the loading dialog first
    _dismissLoadingDialog();

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) => _handleAdDismissed(ad, isRefresh),
      onAdFailedToShowFullScreenContent: (ad, error) =>
          _handleAdShowError(ad, error, isRefresh),
      onAdShowedFullScreenContent: (ad) {
        Logger().d('Rewarded Interstitial Ad showed full screen content');
        _isShowingAd = true;
      },
    );

    // Attempt to show the ad immediately after loading
    _showInterstitialAd(isRefresh);
  }

  void _showInterstitialAd(bool isRefresh) {
    if (_rewardedInterstitialAd == null) {
      Logger().e('Attempted to show ad, but ad is null');
      _proceedWithDownload(isRefresh);
      return;
    }

    try {
      _rewardedInterstitialAd?.show(
        onUserEarnedReward: (ad, reward) {
          Logger().d('User earned reward: ${reward.amount} ${reward.type}');
          // You can add additional logic here if needed when a reward is earned
        },
      );
    } catch (e) {
      Logger().e('Failed to show rewarded interstitial ad: $e');
      _handleAdShowFailure(isRefresh);
    }
  }

  void _handleAdShowFailure(bool isRefresh) {
    _isAdLoading = false;
    _proceedWithDownload(isRefresh);
  }

  void _handleAdDismissed(RewardedInterstitialAd ad, bool isRefresh) {
    Logger().d('Rewarded Interstitial Ad dismissed, starting download...');
    ad.dispose();
    _rewardedInterstitialAd = null;
    _isShowingAd = false;
    _proceedWithDownload(isRefresh);
  }

  void _handleAdShowError(
      RewardedInterstitialAd ad, AdError error, bool isRefresh) {
    Logger().e('Rewarded Interstitial Ad failed to show: $error');
    ad.dispose();
    _rewardedInterstitialAd = null;
    _isShowingAd = false;
    _proceedWithDownload(isRefresh);
  }

  void _handleCountdownEnd(bool isRefresh) {
    _dismissLoadingDialog();
    _isAdLoading = false;
    _rewardedInterstitialAd?.dispose();
    _rewardedInterstitialAd = null;
    _proceedWithDownload(isRefresh);
  }

  void _proceedWithDownload(bool isRefresh) {
    if (isRefresh) {
      _redownloadFile(context);
    } else {
      _startDownload(context);
    }
  }

  void _dismissLoadingDialog() {
    if (_dialogKey.currentContext != null) {
      Navigator.of(_dialogKey.currentContext!).pop();
    }
  }

  Color _getCountdownColor(int countdown) {
    return const Color.fromARGB(
        255, 92, 92, 92); // Consistent color for all countdown values
  }

  Future<void> _downloadFile(BuildContext context) async {
    if (_isDownloading || _isShowingAd) return;

    if (_isFileDownloaded && _downloadedFilePath != null) {
      _openPDF(_downloadedFilePath!, context);
      return;
    }

    _loadInterstitialAd();
  }

  Future<void> _startDownload(BuildContext context) async {
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
                // Optional: You can add a method to show a dialog or navigate to a page with download options
                if (_downloadedFilePath != null) {
                  // Commented out to prevent auto-opening
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

  void _onAdLoadFailed(AdError error, bool isRefresh) {
    Logger().e('Rewarded Interstitial Ad failed to load: $error');
    _dismissLoadingDialog();
    _isAdLoading = false;
    _rewardedInterstitialAd = null;
    _proceedWithDownload(isRefresh);
  }

  void _deleteDownloadedFile() async {
    if (_downloadedFilePath != null) {
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
        final file = File(_downloadedFilePath!);
        final folder = file.parent;
        
        try {
          if (await folder.exists()) {
            await folder.delete(recursive: true);
          }
          
          // Check if the widget is still mounted before showing SnackBar
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
          // Check if the widget is still mounted before showing SnackBar
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
    return Card(
      elevation: 6.0,
      shadowColor: Colors.grey[600],
      color: Colors.white,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 10, 4),
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
                    children: [
                      if (_isFileDownloaded && _downloadedFilePath != null)
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: () {
                            // Show ad before redownloading
                            _loadInterstitialAd(isRefresh: true);
                          },
                          tooltip: 'Redownload',
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      IconButton(
                        icon: Icon(
                          _isBookmarked
                              ? Icons.bookmark
                              : Icons.bookmark_border,
                          color: _isBookmarked
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: _toggleBookmark,
                      ),
                      if (_isFileDownloaded)
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.red),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            _deleteDownloadedFile();
                          },
                          tooltip: 'Delete File',
                        ),
                    ],
                  ),
              ],
            ),
          ),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _viewOnlinePDF(context),
                    icon: const Icon(
                      Icons.remove_red_eye_outlined,
                      size: 20,
                    ),
                    label: const Text(
                      'View Online',
                      style: TextStyle(fontSize: 14),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 4,
                      shadowColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                        ? const SizedBox.shrink() // No icon while downloading
                        : Icon(
                            _isFileDownloaded
                                ? Icons.visibility
                                : Icons.download,
                            color: _isFileDownloaded ? Colors.white : null,
                            size: 20,
                          ),
                    label: Text(
                      _isFileDownloaded
                          ? 'View Offline'
                          : (_isDownloading ? 'Downloading' : 'Download'),
                      style: const TextStyle(fontSize: 14),
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
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
