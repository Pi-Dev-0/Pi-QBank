import 'package:flutter/material.dart';
import 'dart:io';
import '../widgets/app_drawer.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/downloaded_paper_card.dart';
import '../services/downloaded_papers_registry.dart';
import '../widgets/loading_widget.dart';

class DownloadedPapersPage extends StatefulWidget {
  const DownloadedPapersPage({super.key});

  @override
  State<DownloadedPapersPage> createState() => _DownloadedPapersPageState();
}

class _DownloadedPapersPageState extends State<DownloadedPapersPage> {
  List<DownloadedPaper> _downloadedPapers = [];
  bool _isLoading = true;
  Map<String, Map<String, List<DownloadedPaper>>> _nestedGroupedPapers = {};
  String? expandedCategory;
  Map<String, String?> expandedSubCategories = {};

  @override
  void initState() {
    super.initState();
    _loadDownloadedPapers();
  }

  Future<void> _loadDownloadedPapers() async {
    try {
      final papers = await DownloadedPapersRegistry().getDownloadedPapers();

      // Filter out papers whose files no longer exist
      papers.removeWhere((paper) {
        final file = File(paper.filePath);
        final exists = file.existsSync();
        if (!exists) {
          DownloadedPapersRegistry().removeDownloadedPaper(paper.filePath);
        }
        return !exists;
      });

      // Group papers by main category and subject
      final nested = <String, Map<String, List<DownloadedPaper>>>{};

      for (var paper in papers) {
        final isBook = paper.category.trim().toLowerCase() == 'books';
        final mainCategory = isBook
            ? 'Books'
            : (paper.category.isEmpty ? 'General' : paper.category);

        if (isBook) {
          final classOrSub = paper.subtitle.isEmpty ? 'Other' : paper.subtitle;
          final subject = paper.title.isEmpty ? 'Unknown Subject' : paper.title;
          final key = '$classOrSub > $subject';
          nested.putIfAbsent(mainCategory, () => {});
          nested[mainCategory]!.putIfAbsent(key, () => []);
          nested[mainCategory]![key]!.add(paper);
        } else {
          final subject =
              paper.subtitle.isEmpty ? 'Unknown Subject' : paper.subtitle;
          nested.putIfAbsent(mainCategory, () => {});
          nested[mainCategory]!.putIfAbsent(subject, () => []);
          nested[mainCategory]![subject]!.add(paper);
        }
      }

      if (mounted) {
        setState(() {
          _downloadedPapers = papers;
          _nestedGroupedPapers = nested;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.cloud_download_rounded,
              size: 80,
              color: Colors.blue[300],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'No Downloads Yet',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2D3436),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Papers you download will appear here for offline access.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: const CustomAppBar(title: 'Downloaded Papers'),
      drawer: const AppDrawer(),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        child: _isLoading
            ? const LoadingWidget(loadingText: 'Loading Downloads...')
            : _downloadedPapers.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 20),
                    itemCount: _nestedGroupedPapers.length,
                    itemBuilder: (context, mainIndex) {
                      final mainCategory =
                          _nestedGroupedPapers.keys.elementAt(mainIndex);
                      final subjectMap = _nestedGroupedPapers[mainCategory]!;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Theme(
                          data: Theme.of(context).copyWith(
                            dividerColor: Colors.transparent,
                          ),
                          child: ExpansionTile(
                            key: Key(mainCategory),
                            tilePadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            iconColor: Theme.of(context).primaryColor,
                            collapsedIconColor: Colors.grey[400],
                            title: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .primaryColor
                                        .withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    Icons.folder_copy_rounded,
                                    color: Theme.of(context).primaryColor,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        mainCategory,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF2D3436),
                                        ),
                                      ),
                                      Text(
                                        '${subjectMap.length} subjects',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            children: [
                              ...subjectMap.entries.map((subjectEntry) {
                                final papers = subjectEntry.value;
                                return Container(
                                  margin:
                                      const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F3F5),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: ExpansionTile(
                                    key: Key(
                                        '${mainCategory}_${subjectEntry.key}'),
                                    tilePadding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 4),
                                    title: Row(
                                      children: [
                                        Icon(
                                          Icons.label_important_rounded,
                                          size: 20,
                                          color: Colors.grey[700],
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            subjectEntry.key,
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF2D3436),
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            '${papers.length}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Theme.of(context)
                                                  .primaryColor,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(
                                            bottom: 8, left: 8, right: 8),
                                        child: Column(
                                          children: papers.map((paper) {
                                            return DownloadedPaperCard(
                                              key: ValueKey(paper.filePath),
                                              title: paper.title,
                                              subtitle: paper.subtitle,
                                              examYear: paper.examYear,
                                              category: paper.category,
                                              filePath: paper.filePath,
                                              onDeleted: () {
                                                DownloadedPapersRegistry()
                                                    .removeDownloadedPaper(
                                                        paper.filePath);
                                                _loadDownloadedPapers();
                                              },
                                            );
                                          }).toList(),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
