import 'package:flutter/material.dart';
import 'dart:io';
import '../widgets/app_drawer.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/downloaded_paper_card.dart';
import '../services/downloaded_papers_registry.dart';

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

      // Group papers by main category and subject (no extra subgrouping except for books)
      // Books: mainCategory > class > subject > [papers]
      // Others: mainCategory > subject > [papers]
      final nested = <String, Map<String, List<DownloadedPaper>>>{};

      for (var paper in papers) {
        final isBook = paper.category.trim().toLowerCase() == 'books';
        final mainCategory = isBook
            ? 'Books'
            : (paper.category.isEmpty ? 'General' : paper.category);

        if (isBook) {
          // Books: class (subtitle) > subject (title)
          final classOrSub = paper.subtitle.isEmpty ? 'Other' : paper.subtitle;
          final subject = paper.title.isEmpty ? 'Unknown Subject' : paper.title;
          final key = '$classOrSub > $subject';
          nested.putIfAbsent(mainCategory, () => {});
          nested[mainCategory]!.putIfAbsent(key, () => []);
          nested[mainCategory]![key]!.add(paper);
        } else {
          // Others: subject (subtitle)
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'Downloaded Papers'),
      drawer: const AppDrawer(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _downloadedPapers.isEmpty
              ? const Center(child: Text('No downloaded papers found'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _nestedGroupedPapers.length,
                  itemBuilder: (context, mainIndex) {
                    final mainCategory =
                        _nestedGroupedPapers.keys.elementAt(mainIndex);
                    final subjectMap = _nestedGroupedPapers[mainCategory]!;

                    return Theme(
                      data: Theme.of(context).copyWith(
                        dividerColor: Colors.transparent,
                        splashColor: Colors.transparent,
                        highlightColor: Colors.transparent,
                      ),
                      child: ExpansionTile(
                        key: Key(mainCategory),
                        initiallyExpanded: false,
                        tilePadding: EdgeInsets.zero,
                        onExpansionChanged: (expanded) {
                          setState(() {
                            expandedCategory = expanded ? mainCategory : null;
                            if (!expanded) {
                              expandedSubCategories.remove(mainCategory);
                            }
                          });
                        },
                        title: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Theme.of(context).primaryColor,
                                Theme.of(context).primaryColor.withOpacity(0.8),
                              ],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.folder_rounded,
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
                                      mainCategory,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    Text(
                                      '${subjectMap.length} subjects',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.white.withOpacity(0.9),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        children: [
                          const SizedBox(height: 12),
                          ...subjectMap.entries.map((subjectEntry) {
                            final papers = subjectEntry.value;
                            return Theme(
                              data: Theme.of(context).copyWith(
                                dividerColor: Colors.transparent,
                                splashColor: Colors.transparent,
                                highlightColor: Colors.transparent,
                              ),
                              child: ExpansionTile(
                                key: Key('${mainCategory}_${subjectEntry.key}'),
                                initiallyExpanded: false,
                                tilePadding: EdgeInsets.zero,
                                title: Container(
                                  padding: const EdgeInsets.all(12),
                                  margin: const EdgeInsets.only(left: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(10),
                                    border:
                                        Border.all(color: Colors.grey.shade300),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.subject_rounded,
                                        size: 20,
                                        color: Colors.grey.shade700,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          subjectEntry.key,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '${papers.length} file(s)',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(left: 24),
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
                    );
                  },
                ),
    );
  }
}
