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

      // Group papers by main category and subcategory
      final nested = <String, Map<String, List<DownloadedPaper>>>{};
      for (var paper in papers) {
        final mainCategory =
            paper.category.isEmpty ? 'General' : paper.category;
        final subCategory = paper.subtitle.isEmpty ? 'Other' : paper.subtitle;

        nested.putIfAbsent(mainCategory, () => {});
        nested[mainCategory]!.putIfAbsent(subCategory, () => []);
        nested[mainCategory]![subCategory]!.add(paper);
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
              ? const Center(
                  child: Text('No downloaded papers found',
                      style: TextStyle(fontSize: 16)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _nestedGroupedPapers.length,
                  itemBuilder: (context, mainIndex) {
                    final mainCategory =
                        _nestedGroupedPapers.keys.elementAt(mainIndex);
                    final subCategories = _nestedGroupedPapers[mainCategory]!;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Theme(
                        data: Theme.of(context)
                            .copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          title: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .primaryColor
                                      .withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(Icons.folder,
                                    color: Theme.of(context).primaryColor),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      mainCategory,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      '${subCategories.length} subjects',
                                      style: TextStyle(
                                          color: Colors.grey.shade600),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          children: subCategories.entries.map((subEntry) {
                            return Theme(
                              data: Theme.of(context)
                                  .copyWith(dividerColor: Colors.transparent),
                              child: ExpansionTile(
                                title: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Icon(Icons.subject,
                                          color: Colors.grey, size: 20),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            subEntry.key,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          Text(
                                            '${subEntry.value.length} papers',
                                            style: TextStyle(
                                                color: Colors.grey.shade600,
                                                fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                children: subEntry.value.map((paper) {
                                  return DownloadedPaperCard(
                                    key: ValueKey(paper.filePath),
                                    title: paper.title,
                                    subtitle: paper.subtitle,
                                    examYear: paper.examYear,
                                    category: paper.category,
                                    filePath: paper.filePath,
                                    onDeleted: () async {
                                      await DownloadedPapersRegistry()
                                          .removeDownloadedPaper(
                                              paper.filePath);
                                      _loadDownloadedPapers();
                                    },
                                  );
                                }).toList(),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
