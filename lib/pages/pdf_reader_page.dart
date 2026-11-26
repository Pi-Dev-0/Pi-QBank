import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../widgets/custom_app_bar.dart';
import '../pages/pdf_viewer_page.dart';
import '../services/local_pdf_favorites_service.dart';
import '../widgets/delete_confirmation_dialog.dart';
import '../widgets/loading_widget.dart';

/// Representation of a local PDF document with cached metadata.
class LocalPdfItem {
  final File file;
  final String path;
  final String fileName;
  final int sizeInBytes;
  final DateTime lastModified;

  LocalPdfItem({
    required this.file,
    required this.path,
    required this.fileName,
    required this.sizeInBytes,
    required this.lastModified,
  });

  /// Name without the trailing .pdf extension for cleaner display.
  String get displayName {
    if (fileName.toLowerCase().endsWith('.pdf')) {
      return fileName.substring(0, fileName.length - 4);
    }
    return fileName;
  }

  /// Extracts the parent folder name for context.
  String get parentFolder {
    final segments = path.split(Platform.pathSeparator);
    if (segments.length >= 2) {
      final folder = segments[segments.length - 2];
      if (folder.isNotEmpty && folder != '0' && folder != 'emulated') {
        return folder;
      }
    }
    return '';
  }
}

/// Available sorting modes.
enum PdfSortOption {
  dateDesc('Newest First', Icons.calendar_today_rounded),
  dateAsc('Oldest First', Icons.history_rounded),
  nameAsc('Name (A-Z)', Icons.sort_by_alpha_rounded),
  nameDesc('Name (Z-A)', Icons.sort_by_alpha_rounded),
  sizeDesc('Largest First', Icons.arrow_downward_rounded),
  sizeAsc('Smallest First', Icons.arrow_upward_rounded);

  final String label;
  final IconData icon;
  const PdfSortOption(this.label, this.icon);
}

class PdfReaderPage extends StatefulWidget {
  const PdfReaderPage({super.key});

  @override
  State<PdfReaderPage> createState() => _PdfReaderPageState();
}

class _PdfReaderPageState extends State<PdfReaderPage>
    with SingleTickerProviderStateMixin {
  List<LocalPdfItem> _allPdfs = [];
  bool _loading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  PdfSortOption _selectedSort = PdfSortOption.dateDesc;
  bool _isSearching = false;
  bool _showFavoritesOnly = false;
  Set<String> _favoritePaths = <String>{};

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    );
    _loadFavorites();
    _fetchPdfFiles();
  }

  Future<void> _loadFavorites() async {
    final favorites = await LocalPdfFavoritesService.getFavorites();
    if (!mounted) return;
    setState(() => _favoritePaths = favorites);
  }

  bool _isFavorite(LocalPdfItem item) => _favoritePaths.contains(item.path);

  Future<void> _toggleFavorite(LocalPdfItem item) async {
    final updated = Set<String>.from(_favoritePaths);
    if (!updated.remove(item.path)) {
      updated.add(item.path);
    }
    setState(() => _favoritePaths = updated);
    await LocalPdfFavoritesService.saveFavorites(updated);
  }

  void _openSearch() {
    setState(() => _isSearching = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isSearching) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  void _closeSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    setState(() {
      _searchQuery = '';
      _isSearching = false;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  /// Scans storage for PDFs and extracts metadata once to ensure zero jank.
  Future<void> _fetchPdfFiles() async {
    setState(() {
      _loading = true;
    });

    if (Platform.isAndroid) {
      if (!await Permission.manageExternalStorage.request().isGranted) {
        if (mounted) {
          setState(() {
            _loading = false;
          });
        }
        return;
      }
    }

    Directory? rootDir;
    if (Platform.isAndroid) {
      rootDir = Directory('/storage/emulated/0');
    } else {
      rootDir = await getApplicationDocumentsDirectory();
    }

    List<LocalPdfItem> foundPdfs = [];
    await _scanForPdfs(rootDir, foundPdfs);

    if (mounted) {
      setState(() {
        _allPdfs = foundPdfs;
        _loading = false;
      });
      _fadeController.forward(from: 0.0);
    }
  }

  Future<void> _scanForPdfs(Directory dir, List<LocalPdfItem> foundPdfs) async {
    try {
      if (dir.path == '/storage/emulated/0/Android') return;

      final entities = dir.listSync(recursive: false, followLinks: false);
      for (var entity in entities) {
        if (entity is File && entity.path.toLowerCase().endsWith('.pdf')) {
          try {
            final stat = await entity.stat();
            final fileSizeInMB = stat.size / (1024 * 1024);

            // Skip files larger than 250MB to prevent OOM
            if (fileSizeInMB <= 250) {
              final fileName = entity.path.split(Platform.pathSeparator).last;
              foundPdfs.add(LocalPdfItem(
                file: entity,
                path: entity.path,
                fileName: fileName,
                sizeInBytes: stat.size,
                lastModified: stat.modified,
              ));
            }
          } catch (_) {
            // Ignore unreadable individual file
          }
        } else if (entity is Directory && !entity.path.contains('/Android')) {
          await _scanForPdfs(entity, foundPdfs);
        }
      }
    } catch (_) {
      debugPrint('Error scanning folder: ${dir.path}');
    }
  }

  /// Allows user to pick any PDF file directly using file picker.
  Future<void> _pickAndOpenPdf() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        final file = File(filePath);
        if (await file.exists()) {
          final fileName = file.path.split(Platform.pathSeparator).last;

          // Open directly
          if (mounted) {
            _openPdf(filePath, fileName);
          }

          // If not in our list, add it
          final exists = _allPdfs.any((item) => item.path == filePath);
          if (!exists) {
            final stat = await file.stat();
            setState(() {
              _allPdfs.insert(
                0,
                LocalPdfItem(
                  file: file,
                  path: filePath,
                  fileName: fileName,
                  sizeInBytes: stat.size,
                  lastModified: stat.modified,
                ),
              );
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick file: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _openPdf(String filePath, String title) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PDFViewerPage(
          filePath: filePath,
          title: title,
        ),
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = (math.log(bytes) / math.log(1024)).floor();
    return '${(bytes / math.pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0 && dt.day == now.day) {
      return 'Today, ${DateFormat.jm().format(dt)}';
    } else if (diff.inDays <= 1 &&
        dt.day == now.subtract(const Duration(days: 1)).day) {
      return 'Yesterday, ${DateFormat.jm().format(dt)}';
    } else if (dt.year == now.year) {
      return DateFormat('MMM d, h:mm a').format(dt);
    } else {
      return DateFormat('MMM d, yyyy').format(dt);
    }
  }

  List<LocalPdfItem> get _filteredAndSortedList {
    final query = _searchQuery.trim().toLowerCase();
    List<LocalPdfItem> list = _allPdfs;

    // Search query filter
    if (query.isNotEmpty) {
      list = list.where((item) {
        return item.fileName.toLowerCase().contains(query) ||
            item.parentFolder.toLowerCase().contains(query);
      }).toList();
    }

    if (_showFavoritesOnly) {
      list = list.where((item) => _favoritePaths.contains(item.path)).toList();
    }

    // Sort order
    final sorted = List<LocalPdfItem>.from(list);
    switch (_selectedSort) {
      case PdfSortOption.dateDesc:
        sorted.sort((a, b) => b.lastModified.compareTo(a.lastModified));
        break;
      case PdfSortOption.dateAsc:
        sorted.sort((a, b) => a.lastModified.compareTo(b.lastModified));
        break;
      case PdfSortOption.nameAsc:
        sorted.sort((a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
        break;
      case PdfSortOption.nameDesc:
        sorted.sort((a, b) =>
            b.displayName.toLowerCase().compareTo(a.displayName.toLowerCase()));
        break;
      case PdfSortOption.sizeDesc:
        sorted.sort((a, b) => b.sizeInBytes.compareTo(a.sizeInBytes));
        break;
      case PdfSortOption.sizeAsc:
        sorted.sort((a, b) => a.sizeInBytes.compareTo(b.sizeInBytes));
        break;
    }

    return sorted;
  }

  int get _totalFilteredBytes {
    return _filteredAndSortedList.fold(
        0, (sum, item) => sum + item.sizeInBytes);
  }

  void _showFileDetails(LocalPdfItem item) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFE53935), Color(0xFFFF5252)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.picture_as_pdf_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.displayName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _formatFileSize(item.sizeInBytes),
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.textTheme.bodySmall?.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(height: 1),
              const SizedBox(height: 16),
              _buildDetailRow(
                icon: Icons.folder_open_rounded,
                label: 'Folder',
                value: item.parentFolder.isNotEmpty
                    ? item.parentFolder
                    : 'Device Storage',
              ),
              const SizedBox(height: 12),
              _buildDetailRow(
                icon: Icons.calendar_today_rounded,
                label: 'Modified',
                value: DateFormat('MMMM d, yyyy • h:mm:ss a')
                    .format(item.lastModified),
              ),
              const SizedBox(height: 12),
              _buildDetailRow(
                icon: Icons.data_usage_rounded,
                label: 'Size',
                value:
                    '${_formatFileSize(item.sizeInBytes)} (${item.sizeInBytes} bytes)',
              ),
              const SizedBox(height: 12),
              _buildDetailRow(
                icon: Icons.link_rounded,
                label: 'Path',
                value: item.path,
                trailing: IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  tooltip: 'Copy path',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: item.path));
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('File path copied to clipboard'),
                        behavior: SnackBarBehavior.floating,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.share_outlined, size: 18),
                      label: const Text('Share'),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _sharePdf(item);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.chrome_reader_mode_outlined,
                          size: 18),
                      label: const Text('Open'),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _openPdf(item.path, item.fileName);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    Widget? trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 10),
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Future<void> _sharePdf(LocalPdfItem item) async {
    try {
      await Share.shareXFiles(
        [XFile(item.path)],
        text: 'Sharing PDF: ${item.fileName}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to share file: $e')),
        );
      }
    }
  }

  Future<void> _deletePdf(LocalPdfItem item) async {
    final shouldDelete = await showDeleteConfirmationDialog(
      context: context,
      title: 'Delete PDF',
      message: 'Are you sure you want to delete this PDF file from storage?',
      paperTitle: item.fileName,
      paperSubtitle: _formatFileSize(item.sizeInBytes),
    );

    if (shouldDelete == true) {
      try {
        if (await item.file.exists()) {
          await item.file.delete();
        }
        final wasFavorite = _favoritePaths.contains(item.path);
        setState(() {
          _allPdfs.removeWhere((p) => p.path == item.path);
          _favoritePaths.remove(item.path);
        });
        if (wasFavorite) {
          await LocalPdfFavoritesService.saveFavorites(_favoritePaths);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Deleted "${item.fileName}"'),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting file: $e'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  PreferredSizeWidget _buildSearchAppBar(bool isDark) {
    return CustomAppBar(
      title: 'Search',
      centerTitle: false,
      showNotification: false,
      leading: IconButton(
        tooltip: 'Close search',
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: _closeSearch,
      ),
      titleWidget: _buildSearchField(isDark),
    );
  }

  Widget _buildSearchField(bool isDark) {
    return SizedBox(
      height: 38,
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        onChanged: (val) => setState(() => _searchQuery = val),
        textInputAction: TextInputAction.search,
        textAlignVertical: TextAlignVertical.center,
        style: TextStyle(
          fontSize: 14,
          color: isDark ? Colors.white : Colors.black87,
        ),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search PDFs by title or folder...',
          hintStyle: TextStyle(
            color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
            fontSize: 14,
          ),
          filled: true,
          fillColor: isDark ? const Color(0xFF1E222B) : Colors.white,
          prefixIcon: Icon(
            Icons.search_rounded,
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            size: 20,
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 40),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  color: Colors.grey.shade500,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                    _searchFocusNode.requestFocus();
                  },
                ),
          suffixIconConstraints: const BoxConstraints(minWidth: 36),
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: isDark ? Colors.white12 : Colors.grey.shade300,
              width: 1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsAndSortHeader(ThemeData theme, bool isDark, int count) {
    final compact = MediaQuery.sizeOf(context).width < 380;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 16, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Total count & storage badge
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: Color(0xFF10B981),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$count ${count == 1 ? 'file' : 'files'}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.grey.shade300 : Colors.grey.shade800,
                ),
              ),
              if (count > 0) ...[
                Text(
                  ' • ${_formatFileSize(_totalFilteredBytes)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                  ),
                ),
              ],
            ],
          ),

          // Favorites filter + sort dropdown
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildFavoritesToggle(isDark),
              const SizedBox(width: 8),
              // Sort dropdown menu button
              PopupMenuButton<PdfSortOption>(
                initialValue: _selectedSort,
                tooltip: 'Sort by',
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                onSelected: (option) {
                  setState(() => _selectedSort = option);
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color:
                        isDark ? const Color(0xFF1E222B) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDark ? Colors.white10 : Colors.grey.shade300,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _selectedSort.icon,
                        size: 14,
                        color: const Color(0xFF6366F1),
                      ),
                      if (!compact) ...[
                        const SizedBox(width: 6),
                        Text(
                          _selectedSort.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Colors.grey.shade300
                                : Colors.grey.shade800,
                          ),
                        ),
                      ],
                      const SizedBox(width: 4),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                    ],
                  ),
                ),
                itemBuilder: (context) {
                  return PdfSortOption.values.map((sort) {
                    final isCurrent = _selectedSort == sort;
                    return PopupMenuItem<PdfSortOption>(
                      value: sort,
                      child: Row(
                        children: [
                          Icon(
                            sort.icon,
                            size: 18,
                            color: isCurrent
                                ? const Color(0xFF6366F1)
                                : Colors.grey,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            sort.label,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isCurrent
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isCurrent ? const Color(0xFF6366F1) : null,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFavoritesToggle(bool isDark) {
    final active = _showFavoritesOnly;
    return Tooltip(
      message: active ? 'Show all files' : 'Show favorites only',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() => _showFavoritesOnly = !_showFavoritesOnly),
          child: Container(
            width: 34,
            height: 30,
            decoration: BoxDecoration(
              color: active
                  ? (isDark ? const Color(0xFF3A2F1B) : const Color(0xFFFEF3C7))
                  : (isDark ? const Color(0xFF1E222B) : Colors.grey.shade100),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active
                    ? const Color(0xFFF59E0B)
                    : (isDark ? Colors.white10 : Colors.grey.shade300),
                width: 1,
              ),
            ),
            child: Icon(
              active ? Icons.star_rounded : Icons.star_border_rounded,
              size: 18,
              color: active
                  ? const Color(0xFFF59E0B)
                  : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF6366F1).withOpacity(0.15),
                    const Color(0xFFEC4899).withOpacity(0.1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: const Color(0xFF6366F1).withOpacity(0.25),
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.folder_zip_outlined,
                size: 72,
                color: Color(0xFF6366F1),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No PDF Files Found',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'We scanned your device storage but couldn\'t find any PDF documents.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: _pickAndOpenPdf,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              icon: const Icon(Icons.file_open_rounded, size: 20),
              label: const Text(
                'Browse & Pick PDF',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _fetchPdfFiles,
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Rescan Storage'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySearchState(bool isDark) {
    final hasQuery = _searchQuery.trim().isNotEmpty;
    final favoritesOnly = _showFavoritesOnly && !hasQuery;
    final title = favoritesOnly ? 'No favorites yet' : 'No matching PDFs';
    final message = favoritesOnly
        ? 'Tap the star on any PDF to add it to your favorites.'
        : 'No documents match "$_searchQuery"';
    final actionLabel = favoritesOnly ? 'Show all files' : 'Clear search';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? Colors.white10 : Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                favoritesOnly
                    ? Icons.star_border_rounded
                    : Icons.search_off_rounded,
                size: 48,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () {
                if (favoritesOnly) {
                  setState(() => _showFavoritesOnly = false);
                  return;
                }
                _searchController.clear();
                setState(() => _searchQuery = '');
                _searchFocusNode.requestFocus();
              },
              icon: Icon(
                favoritesOnly
                    ? Icons.visibility_outlined
                    : Icons.restart_alt_rounded,
                size: 18,
              ),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPdfCard(LocalPdfItem item, ThemeData theme, bool isDark) {
    final isFavorite = _isFavorite(item);
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E222B) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _openPdf(item.path, item.fileName),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                // Modern PDF Document Badge
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 48,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFE53935), Color(0xFFD32F2F)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFE53935).withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.description_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                          SizedBox(height: 2),
                          Text(
                            'PDF',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),

                // Title and Meta Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.displayName,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14.5,
                          height: 1.25,
                          color:
                              isDark ? Colors.white : const Color(0xFF1E293B),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          // Size pill
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white12
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _formatFileSize(item.sizeInBytes),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Colors.grey.shade300
                                    : const Color(0xFF475569),
                              ),
                            ),
                          ),
                          Text(
                            '•',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? Colors.white30
                                  : Colors.grey.shade400,
                            ),
                          ),
                          // Date
                          Text(
                            _formatDate(item.lastModified),
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600,
                            ),
                          ),
                          if (item.parentFolder.isNotEmpty) ...[
                            Text(
                              '•',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Colors.white30
                                    : Colors.grey.shade400,
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.folder_outlined,
                                  size: 11,
                                  color: isDark
                                      ? Colors.grey.shade500
                                      : Colors.grey.shade500,
                                ),
                                const SizedBox(width: 3),
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 80),
                                  child: Text(
                                    item.parentFolder,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark
                                          ? Colors.grey.shade400
                                          : Colors.grey.shade600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Quick Action Buttons
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Favorite button
                    IconButton(
                      icon: Icon(
                        isFavorite
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        size: 22,
                      ),
                      color: isFavorite
                          ? const Color(0xFFF59E0B)
                          : (isDark
                              ? Colors.grey.shade400
                              : const Color(0xFF94A3B8)),
                      tooltip: isFavorite
                          ? 'Remove from favorites'
                          : 'Add to favorites',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _toggleFavorite(item),
                    ),

                    // Context Menu
                    PopupMenuButton<String>(
                      tooltip: 'More actions',
                      icon: Icon(
                        Icons.more_vert_rounded,
                        size: 20,
                        color: isDark
                            ? Colors.grey.shade400
                            : const Color(0xFF94A3B8),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      onSelected: (action) {
                        switch (action) {
                          case 'favorite':
                            _toggleFavorite(item);
                            break;
                          case 'open':
                            _openPdf(item.path, item.fileName);
                            break;
                          case 'share':
                            _sharePdf(item);
                            break;
                          case 'details':
                            _showFileDetails(item);
                            break;
                          case 'delete':
                            _deletePdf(item);
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'favorite',
                          child: Row(
                            children: [
                              Icon(
                                isFavorite
                                    ? Icons.star_rounded
                                    : Icons.star_border_rounded,
                                size: 18,
                                color: const Color(0xFFF59E0B),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                isFavorite
                                    ? 'Remove from favorites'
                                    : 'Add to favorites',
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'open',
                          child: Row(
                            children: [
                              Icon(Icons.chrome_reader_mode_outlined, size: 18),
                              SizedBox(width: 12),
                              Text('Open'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'share',
                          child: Row(
                            children: [
                              Icon(Icons.share_outlined, size: 18),
                              SizedBox(width: 12),
                              Text('Share'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'details',
                          child: Row(
                            children: [
                              Icon(Icons.info_outline_rounded, size: 18),
                              SizedBox(width: 12),
                              Text('Details'),
                            ],
                          ),
                        ),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline_rounded,
                                  size: 18, color: Colors.red),
                              SizedBox(width: 12),
                              Text(
                                'Delete',
                                style: TextStyle(color: Colors.red),
                              ),
                            ],
                          ),
                        ),
                      ],
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: LoadingWidget(loadingText: 'Scanning PDF Documents...'),
      );
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final items = _filteredAndSortedList;

    return PopScope(
      canPop: !_isSearching,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isSearching) {
          _closeSearch();
        }
      },
      child: Scaffold(
        appBar: _isSearching
            ? _buildSearchAppBar(isDark)
            : CustomAppBar(
                title: 'Local PDF',
                centerTitle: true,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.search_rounded),
                    tooltip: 'Search PDFs',
                    onPressed: _openSearch,
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'Rescan storage',
                    onPressed: _fetchPdfFiles,
                  ),
                ],
              ),
        floatingActionButton: _allPdfs.isNotEmpty
            ? FloatingActionButton.extended(
                onPressed: _pickAndOpenPdf,
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                elevation: 4,
                icon: const Icon(Icons.add_rounded),
                label: const Text(
                  'Open File',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              )
            : null,
        body: SafeArea(
          child: _allPdfs.isEmpty
              ? _buildEmptyState(isDark)
              : RefreshIndicator(
                  onRefresh: _fetchPdfFiles,
                  color: const Color(0xFF6366F1),
                  child: Column(
                    children: [
                      _buildStatsAndSortHeader(theme, isDark, items.length),
                      Expanded(
                        child: items.isEmpty
                            ? _buildEmptySearchState(isDark)
                            : FadeTransition(
                                opacity: _fadeAnimation,
                                child: ListView.separated(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 6, 16, 80),
                                  physics: const AlwaysScrollableScrollPhysics(
                                    parent: BouncingScrollPhysics(),
                                  ),
                                  itemCount: items.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (context, index) {
                                    return _buildPdfCard(
                                        items[index], theme, isDark);
                                  },
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
