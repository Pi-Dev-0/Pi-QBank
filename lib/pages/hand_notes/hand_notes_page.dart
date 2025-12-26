import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../../main.dart'; // Import for MainScreen
import '../pdf_viewer_page.dart';
import '../online_pdf_viewer_page.dart';
import '../../widgets/custom_app_bar.dart'; // Import CustomAppBar
import '../../widgets/loading_widget.dart';
import '../../widgets/delete_confirmation_dialog.dart';

// Data model remains the same
class NoteFilter {
  final String className;
  final String subject;
  final String topic;
  final String title;
  final String url;

  NoteFilter({
    required this.className,
    required this.subject,
    required this.topic,
    required this.title,
    required this.url,
  });

  factory NoteFilter.fromJson(Map<String, dynamic> json) {
    return NoteFilter(
      className: json['class'] ?? '',
      subject: json['subject'] ?? '',
      topic: json['topic'] ?? '',
      title: json['title'] ?? '',
      url: json['url'] ?? '',
    );
  }
}

const String handNotesApiUrl =
    'https://script.google.com/macros/s/AKfycbzlX697mRB2DOX4isBhf35BrWidU6eKx63eiJ3VUB-dq0mfCEnfFDsp3yZ2ET8rtcmi/exec';

class HandNotesPage extends StatefulWidget {
  const HandNotesPage({super.key});

  @override
  State<HandNotesPage> createState() => _HandNotesPageState();
}

class _HandNotesPageState extends State<HandNotesPage>
    with SingleTickerProviderStateMixin {
  // Selection State
  String? _selectedClass;
  String? _selectedSubject;
  String? _selectedTopic;

  // Data State
  List<NoteFilter> _allFilters = [];
  List<String> _classes = [];
  List<String> _subjects = [];
  List<String> _topics = [];

  bool _isLoading = true;
  final Map<String, double> _downloadProgress = {};

  // For Animation
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _fetchFilters();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _fetchFilters() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse(handNotesApiUrl));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        _allFilters = data.map((json) => NoteFilter.fromJson(json)).toList();
        _updateDropdowns();
        _animationController.forward();
      }
    } catch (e) {
      debugPrint("Error fetching notes: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _updateDropdowns() {
    setState(() {
      _classes = _allFilters.map((f) => f.className).toSet().toList()..sort();

      // Update Subjects based on selected Class
      if (_selectedClass != null && _classes.contains(_selectedClass)) {
        _subjects = _allFilters
            .where((f) => f.className == _selectedClass)
            .map((f) => f.subject)
            .toSet()
            .toList()
          ..sort();
      } else {
        _selectedSubject = null; // Reset subject if class changes/invalid
        _subjects = [];
      }

      // Update Topics based on selected Class & Subject
      if (_selectedSubject != null && _subjects.contains(_selectedSubject)) {
        _topics = _allFilters
            .where((f) =>
                f.className == _selectedClass && f.subject == _selectedSubject)
            .map((f) => f.topic)
            .toSet()
            .toList()
          ..sort();
      } else {
        _selectedTopic = null; // Reset topic if subject changes/invalid
        _topics = [];
      }
    });
  }

  // --- File Handling Methods (Kept from original) ---
  Future<bool> _isNoteDownloaded(String title) async {
    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/${title.replaceAll(' ', '_')}.pdf';
    return File(filePath).exists();
  }

  Future<void> _deleteNote(String title) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/${title.replaceAll(' ', '_')}.pdf');
    if (await file.exists()) {
      await file.delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Note deleted!'), backgroundColor: Colors.orange));
        setState(() {}); // Refresh UI
      }
    }
  }

  Future<void> _downloadNote(String url, String title) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/${title.replaceAll(' ', '_')}.pdf');

    try {
      setState(() => _downloadProgress[title] = 0.0);
      final request = http.Request('GET', Uri.parse(url));
      final response = await request.send();

      if (response.statusCode == 200) {
        final contentLength = response.contentLength ?? 0;
        final bytes = <int>[];
        int received = 0;

        response.stream.listen(
          (chunk) {
            bytes.addAll(chunk);
            received += chunk.length;
            if (contentLength > 0) {
              setState(
                  () => _downloadProgress[title] = received / contentLength);
            }
          },
          onDone: () async {
            await file.writeAsBytes(bytes);
            if (mounted) {
              setState(() => _downloadProgress.remove(title));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Downloaded successfully!'),
                  backgroundColor: Colors.green));
            }
          },
          onError: (e) {
            if (mounted) setState(() => _downloadProgress.remove(title));
          },
        );
      }
    } catch (e) {
      if (mounted) setState(() => _downloadProgress.remove(title));
    }
  }

  // --- Navigation Handling ---
  void _handleBack() {
    // Safely navigate back to home
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const MainScreen()),
      (route) => false,
    );
  }

  // --- UI Components ---

  Widget _buildFilterChip(String label, String? value, List<String> options,
      ValueChanged<String?> onChanged) {
    IconData getIcon() {
      switch (label) {
        case 'Class':
          return Icons.school_rounded;
        case 'Subject':
          return Icons.menu_book_rounded;
        case 'Topic':
          return Icons.topic_rounded;
        default:
          return Icons.category_rounded;
      }
    }

    Widget buildItemContent(String text) {
      return Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.indigo.withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(
              getIcon(),
              size: 16,
              color: Colors.indigo.withOpacity(0.8),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.indigo,
              fontSize: 12,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.indigo.withOpacity(0.15)),
            boxShadow: [
              BoxShadow(
                color: Colors.indigo.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: options.contains(value) ? value : null,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded,
                  color: Colors.indigo, size: 20),
              hint: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.indigo.withOpacity(0.05),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      getIcon(),
                      size: 16,
                      color: Colors.indigo.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Select',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              selectedItemBuilder: (BuildContext context) {
                return options.map<Widget>((String item) {
                  return buildItemContent(item);
                }).toList();
              },
              items: options.map((String item) {
                return DropdownMenuItem<String>(
                  value: item,
                  child: Text(
                    item,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black87,
                    ),
                  ),
                );
              }).toList(),
              onChanged: onChanged,
              dropdownColor: Colors.white,
              borderRadius: BorderRadius.circular(12),
              style: const TextStyle(color: Colors.black87),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNoteCard(NoteFilter note, int index) {
    final color = Colors.primaries[index % Colors.primaries.length];

    return FutureBuilder<bool>(
      future: _isNoteDownloaded(note.title),
      builder: (context, snapshot) {
        final isDownloaded = snapshot.data ?? false;
        final progress = _downloadProgress[note.title];

        return Theme(
          data: Theme.of(context).copyWith(
            primaryColor: color,
            colorScheme: ColorScheme.fromSeed(
              seedColor: color,
              primary: color,
            ),
          ),
          child: FadeTransition(
            opacity: _animationController,
            child: Card(
              elevation: 4,
              margin: const EdgeInsets.only(bottom: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (progress != null && progress > 0 && progress < 1)
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 3,
                          backgroundColor: Colors.grey.shade300,
                          valueColor: AlwaysStoppedAnimation(color),
                        ),
                      ),
                    if (progress != null && progress > 0 && progress < 1)
                      Text(
                        '${(progress * 100).toInt()}%',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    if (progress == null || progress == 0 || progress == 1)
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isDownloaded ? Icons.check_circle : Icons.book,
                          size: 24,
                          color: isDownloaded ? Colors.green : color,
                        ),
                      ),
                  ],
                ),
                title: Text(
                  note.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                subtitle: Text(
                  note.subject,
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isDownloaded)
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                          final shouldDelete =
                              await showDeleteConfirmationDialog(
                            context: context,
                            title: 'Delete Note',
                            message:
                                'Are you sure you want to delete this note?',
                            paperTitle: note.title,
                            paperSubtitle: note.subject,
                          );
                          if (shouldDelete == true) {
                            _deleteNote(note.title);
                          }
                        },
                      ),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: isDownloaded
                            ? Colors.green.withOpacity(0.1)
                            : color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isDownloaded
                            ? Icons.download_done
                            : Icons.arrow_forward_ios,
                        size: 16,
                        color: isDownloaded ? Colors.green : color,
                      ),
                    ),
                  ],
                ),
                onTap: () async {
                  if (isDownloaded) {
                    final directory = await getApplicationDocumentsDirectory();
                    final filePath =
                        '${directory.path}/${note.title.replaceAll(' ', '_')}.pdf';
                    if (context.mounted) {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => PDFViewerPage(
                                  filePath: filePath, title: note.title)));
                    }
                  } else {
                    final parentContext = context;
                    final choice = await showDialog<String>(
                      context: parentContext,
                      builder: (context) => Theme(
                        data: Theme.of(context).copyWith(
                          primaryColor: color,
                          colorScheme: ColorScheme.fromSeed(
                            seedColor: color,
                            primary: color,
                          ),
                        ),
                        child: AlertDialog(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          title: Row(
                            children: [
                              Icon(Icons.book, color: color),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  note.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Choose an option to view or download this note.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 15,
                                  color: Colors.black87,
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.visibility),
                                    label: const Text('View Online'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: color,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    onPressed: () {
                                      Navigator.pop(context, 'view');
                                    },
                                  ),
                                  OutlinedButton.icon(
                                    icon: const Icon(Icons.download),
                                    label: const Text('Download'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: color,
                                      side: BorderSide(color: color),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    onPressed: () {
                                      Navigator.pop(context, 'download');
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );

                    if (!context.mounted) return;

                    if (choice == 'view') {
                      if (note.url.startsWith('http')) {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => OnlinePDFViewerPage(
                                    pdfUrl: note.url, title: note.title)));
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('No preview available.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    } else if (choice == 'download') {
                      if (note.url.startsWith('http')) {
                        await _downloadNote(note.url, note.title);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('This note is not downloadable.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  }
                },
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredNotes = _allFilters.where((f) {
      return (_selectedClass == null || f.className == _selectedClass) &&
          (_selectedSubject == null || f.subject == _selectedSubject) &&
          (_selectedTopic == null || f.topic == _selectedTopic);
    }).toList();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA), // Light grey/blue background
        appBar: CustomAppBar(
          title: 'Hand Notes',
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () {
              _handleBack();
            },
          ),
        ),
        body: _isLoading
            ? const Center(
                child: LoadingWidget(loadingText: 'Fetching Notes...'))
            : Column(
                children: [
                  // Filters Section
                  Container(
                    padding: const EdgeInsets.only(
                        left: 16.0, right: 16.0, top: 16.0, bottom: 8.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildFilterChip(
                              'Class', _selectedClass, _classes, (val) {
                            setState(() {
                              _selectedClass = val;
                              _selectedSubject = null;
                              _selectedTopic = null;
                              _updateDropdowns();
                            });
                          }),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildFilterChip(
                              'Subject', _selectedSubject, _subjects, (val) {
                            setState(() {
                              _selectedSubject = val;
                              _selectedTopic = null;
                              _updateDropdowns();
                            });
                          }),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildFilterChip(
                              'Topic', _selectedTopic, _topics, (val) {
                            setState(() {
                              _selectedTopic = val;
                            });
                          }),
                        ),
                      ],
                    ),
                  ),

                  // Content Section
                  Expanded(
                    child: filteredNotes.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.note_alt_outlined,
                                    size: 60, color: Colors.grey[400]),
                                const SizedBox(height: 16),
                                Text("No notes found",
                                    style: TextStyle(
                                        color: Colors.grey[600], fontSize: 16)),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            physics: const BouncingScrollPhysics(),
                            itemCount: filteredNotes.length,
                            itemBuilder: (context, index) =>
                                _buildNoteCard(filteredNotes[index], index),
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}
