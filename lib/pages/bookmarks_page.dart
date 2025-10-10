import 'package:flutter/material.dart';
import '../services/bookmark_service.dart';
import '../widgets/question_paper_card.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/app_drawer.dart';

class BookmarksPage extends StatefulWidget {
  const BookmarksPage({super.key});

  @override
  State<BookmarksPage> createState() => _BookmarksPageState();
}

class _BookmarksPageState extends State<BookmarksPage> {
  List<BookmarkedPaper> _bookmarks = [];
  bool _isLoading = true;
  Map<String, List<BookmarkedPaper>> _groupedBookmarks = {};

  @override
  void initState() {
    super.initState();
    _loadBookmarks();
  }

  Future<void> _loadBookmarks() async {
    setState(() => _isLoading = true);
    final bookmarks = await BookmarkService.getBookmarks();
    
    if (mounted) {
      // Group bookmarks by category
      final grouped = <String, List<BookmarkedPaper>>{};
      for (var bookmark in bookmarks) {
        if (!grouped.containsKey(bookmark.category)) {
          grouped[bookmark.category] = [];
        }
        grouped[bookmark.category]!.add(bookmark);
      }

      setState(() {
        _bookmarks = bookmarks;
        _groupedBookmarks = grouped;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'Bookmarks'),
      drawer: const AppDrawer(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _bookmarks.isEmpty
              ? const Center(
                  child: Text(
                    'No bookmarks yet',
                    style: TextStyle(fontSize: 16),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _groupedBookmarks.length,
                  itemBuilder: (context, index) {
                    final category = _groupedBookmarks.keys.elementAt(index);
                    final categoryBookmarks = _groupedBookmarks[category]!;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Category Header
                        Container(
                          margin: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Theme.of(context).primaryColor.withOpacity(0.6),
                                Theme.of(context).primaryColor,
                              ],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.8),
                                spreadRadius: 1,
                                blurRadius: 5,
                                offset: const Offset(1, 1),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              category.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        ),
                        // Category Items
                        ListView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          shrinkWrap: true,
                          itemCount: categoryBookmarks.length,
                          itemBuilder: (context, bookmarkIndex) {
                            final bookmark = categoryBookmarks[bookmarkIndex];
                            return QuestionPaperCard(
                              key: ValueKey(bookmark.downloadUrl),
                              title: bookmark.title,
                              subtitle: bookmark.subtitle,
                              year: bookmark.year,
                              examYear: bookmark.examYear,
                              downloadUrl: bookmark.downloadUrl,
                              category: bookmark.category,
                            );
                          },
                        ),
                        // Add space between categories
                        const SizedBox(height: 16),
                      ],
                    );
                  },
                ),
    );
  }
} 