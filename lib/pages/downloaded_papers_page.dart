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

      setState(() {
        _downloadedPapers = papers;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'Downloaded Papers'),
      drawer: const AppDrawer(),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _downloadedPapers.isEmpty
              ? const Center(
                  child: Text(
                    'No downloaded papers found',
                    style: TextStyle(fontSize: 16),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _downloadedPapers.length,
                  itemBuilder: (context, index) {
                    final paper = _downloadedPapers[index];
                    return DownloadedPaperCard(
                      key: ValueKey(paper.filePath),
                      title: paper.title,
                      subtitle: paper.subtitle,
                      examYear: paper.examYear,
                      category: paper.category,
                      filePath: paper.filePath,
                      onDeleted: () async {
                        await DownloadedPapersRegistry()
                            .removeDownloadedPaper(paper.filePath);
                        setState(() {
                          _downloadedPapers.removeAt(index);
                        });
                      },
                    );
                  },
                ),
    );
  }
}
