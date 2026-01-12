import 'package:flutter/material.dart';
import 'package:pi_qbank/pages/exam_paper_builder_page.dart';
import 'package:pi_qbank/widgets/custom_app_bar.dart';
import 'package:pi_qbank/pages/prepare_short_test_page.dart';
import 'package:pi_qbank/widgets/api_key_dialog.dart';
import 'package:pi_qbank/pages/question_generator_page.dart';
import 'package:pi_qbank/pages/mess_manager_page.dart';
import 'package:pi_qbank/pages/newspaper_list_page.dart';
import 'package:pi_qbank/pages/notes_remainder_page.dart';
import 'package:pi_qbank/pages/educational_links_page.dart';
import 'package:pi_qbank/widgets/youtube_player_dialog.dart';
import 'package:pi_qbank/pages/pdf_reader_page.dart';
import '../widgets/app_drawer.dart';
import 'package:pi_qbank/models/tool_item.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key});

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  List<ToolItem> _toolItems = [];

  @override
  void initState() {
    super.initState();
    _initializeToolItems();
  }

  void _initializeToolItems() {
    _toolItems = [
      ToolItem(
        icon: Icons.assignment_outlined,
        title: 'Short Test',
        description: 'Create quick assessments',
        accentColor: Colors.blue,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const PrepareShortTestPage(),
            ),
          );
        },
      ),
      ToolItem(
        icon: Icons.text_fields_outlined,
        title: 'Question Generator',
        description: 'Create short & broad questions',
        accentColor: Colors.purple,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const QuestionGeneratorPage(),
            ),
          );
        },
      ),
      ToolItem(
        icon: Icons.assignment_outlined,
        title: 'Exam Paper Builder',
        description: 'Create custom question papers & tests',
        accentColor: Colors.orange,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const ExamPaperBuilderPage(),
            ),
          );
        },
      ),
      ToolItem(
        icon: Icons.calculate_outlined,
        title: 'মেস ম্যানেজার (Mess Manager)',
        description: 'মেস এর হিসাব নিকাশ ম্যানেজ করুন',
        accentColor: Colors.teal,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const MessManagerPage(),
            ),
          );
        },
      ),
      ToolItem(
        icon: Icons.newspaper_outlined,
        title: 'News Paper',
        description: 'Read popular news channels',
        accentColor: Colors.red,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const NewspaperListPage(),
            ),
          );
        },
      ),
      ToolItem(
        icon: Icons.note_alt_outlined,
        title: 'Notes & Remainder',
        description: 'Manage your notes and set reminders',
        accentColor: Colors.indigo,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const NotesRemainderPage(),
            ),
          );
        },
      ),
      ToolItem(
        icon: Icons.school_outlined,
        title: 'Educational Links',
        description: 'Explore useful Bangladeshi educational web links',
        accentColor: Colors.green,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const EducationalLinksPage(),
            ),
          );
        },
      ),
      ToolItem(
        icon: Icons.picture_as_pdf_outlined,
        title: 'Local PDF',
        description: 'Read device local PDF files',
        accentColor: Colors.red,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const PdfReaderPage(),
            ),
          );
        },
      ),
    ];
    _loadPinnedState().then((_) {
      setState(() {});
    });
  }

  Future<void> _loadPinnedState() async {
    final prefs = await SharedPreferences.getInstance();
    final String? pinnedToolsString = prefs.getString('pinnedTools');

    if (pinnedToolsString != null) {
      final List<dynamic> pinnedToolsJson = jsonDecode(pinnedToolsString);
      for (var pinnedToolJson in pinnedToolsJson) {
        final String title = pinnedToolJson['title'];
        final bool isPinned = pinnedToolJson['isPinned'] ?? false;
        final int index = _toolItems.indexWhere((item) => item.title == title);
        if (index != -1) {
          _toolItems[index].isPinned = isPinned;
        }
      }
    }
    _sortToolItems();
  }

  Future<void> _savePinnedState() async {
    final prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> pinnedToolsJson = _toolItems
        .where((item) => item.isPinned)
        .map((item) => item.toJson())
        .toList();
    await prefs.setString('pinnedTools', jsonEncode(pinnedToolsJson));
  }

  void _togglePin(ToolItem item) {
    setState(() {
      item.isPinned = !item.isPinned;
      _sortToolItems();
      _savePinnedState();
    });
  }

  void _sortToolItems() {
    _toolItems.sort((a, b) {
      if (a.isPinned && !b.isPinned) {
        return -1;
      } else if (!a.isPinned && b.isPinned) {
        return 1;
      } else {
        return 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: CustomAppBar(
        title: 'Tools',
      ),
      drawer: const AppDrawer(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.blue.shade50,
                    Colors.green.shade50,
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.vpn_key,
                        color: Colors.blue.shade600,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Use Your Own API Key',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'To get full access to all features, simply add your own API key. ',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            showApiKeyDialog(context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade600,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Setup API Key'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            const String videoId = 'o8iyrtQyrZM';
                            showYoutubePlayerDialog(context, videoId);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade600,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Get API Key?'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 16.0,
              mainAxisSpacing: 16.0,
              childAspectRatio: 0.9,
              children: _toolItems.map((item) {
                return _buildToolCard(context, item);
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolCard(BuildContext context, ToolItem item) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: item.onTap,
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: item.accentColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(item.icon, size: 24, color: item.accentColor),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: Text(
                        item.title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Flexible(
                      child: Text(
                        item.description,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: item.accentColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Try now',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: item.accentColor,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(Icons.arrow_forward, size: 10, color: item.accentColor),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: () => _togglePin(item),
                  child: Icon(
                    item.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                    color: item.isPinned ? item.accentColor : Colors.grey,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}