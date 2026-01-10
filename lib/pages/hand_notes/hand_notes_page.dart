import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../main.dart'; // Import for MainScreen
import '../../widgets/custom_app_bar.dart'; // Import CustomAppBar
import '../../widgets/loading_widget.dart';
import '../../widgets/question_paper_card.dart';

// Data model for notes
class NoteFilter {
  final String className;
  final String subject;
  final String topic;
  final String title;
  final String url;
  final String type; // "Hand" or "Digital"
  final String creator;

  NoteFilter({
    required this.className,
    required this.subject,
    required this.topic,
    required this.title,
    required this.url,
    required this.type,
    required this.creator,
  });

  factory NoteFilter.fromJson(Map<String, dynamic> json) {
    return NoteFilter(
      className: json['class'] ?? '',
      subject: json['subject'] ?? '',
      topic: json['topic'] ?? '',
      title: json['title'] ?? '',
      url: json['url'] ?? '',
      type: json['type'] ?? 'Hand',
      creator: json['creator'] ?? '',
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
  String? _selectedType; // "Hand" or "Digital"

  // Data State
  List<NoteFilter> _allFilters = [];
  List<String> _classes = [];
  List<String> _subjects = [];
  List<String> _topics = [];

  bool _isLoading = true;

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
      if (!mounted) return;
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
      // Filter by type first if selected
      final typeFiltered = _selectedType != null
          ? _allFilters.where((f) => f.type == _selectedType).toList()
          : _allFilters;

      _classes = typeFiltered.map((f) => f.className).toSet().toList()..sort();

      // Update Subjects based on selected Class and Type
      if (_selectedClass != null && _classes.contains(_selectedClass)) {
        _subjects = typeFiltered
            .where((f) => f.className == _selectedClass)
            .map((f) => f.subject)
            .toSet()
            .toList()
          ..sort();
      } else {
        _selectedSubject = null; // Reset subject if class changes/invalid
        _subjects = [];
      }

      // Update Topics based on selected Class, Subject & Type
      if (_selectedSubject != null && _subjects.contains(_selectedSubject)) {
        _topics = typeFiltered
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

  // --- Navigation Handling ---
  void _handleBack() {
    // Safely navigate back to home
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const MainScreen()),
      (route) => false,
    );
  }

  // --- UI Components ---

  Widget _buildTypeButton({
    required String label,
    required IconData icon,
    required String type,
    required bool isSelected,
  }) {
    return Material(
      color: isSelected ? Colors.indigo.withOpacity(0.12) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedType = isSelected ? null : type;
            _selectedClass = null;
            _selectedSubject = null;
            _selectedTopic = null;
            _updateDropdowns();
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? Colors.indigo.withOpacity(0.4)
                  : Colors.indigo.withOpacity(0.15),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.indigo.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? Colors.indigo : Colors.grey[600],
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    color: isSelected ? Colors.indigo : Colors.grey[700],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String? value, List<String> options,
      ValueChanged<String?> onChanged,
      {bool enabled = true}) {
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

    return Opacity(
      opacity: enabled ? 1.0 : 0.6,
      child: Column(
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
                value: (enabled && options.contains(value)) ? value : null,
                isExpanded: true,
                menuWidth: 200,
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
                items: options.asMap().entries.map((entry) {
                  final item = entry.value;
                  final isLast = entry.key == options.length - 1;
                  return DropdownMenuItem<String>(
                    value: item,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Container(
                                width: 3,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: Colors.indigo.withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  item,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!isLast)
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: Colors.indigo.withOpacity(0.05),
                          ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: enabled ? onChanged : null,
                dropdownColor: Colors.white,
                borderRadius: BorderRadius.circular(12),
                style: const TextStyle(color: Colors.black87),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoteCard(NoteFilter note, int index) {
    return QuestionPaperCard(
      title: note.title,
      subtitle: '${note.subject} • ${note.topic}',
      year: note.className,
      examYear: note.type,
      downloadUrl: note.url,
      category: 'Notes',
      index: index,
      creator: note.creator,
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredNotes = _allFilters.where((f) {
      return (_selectedType == null || f.type == _selectedType) &&
          (_selectedClass == null || f.className == _selectedClass) &&
          (_selectedSubject == null || f.subject == _selectedSubject) &&
          (_selectedTopic == null || f.topic == _selectedTopic);
    }).toList();

    if (_isLoading) {
      return const Scaffold(
        body: LoadingWidget(loadingText: 'Loading Notes...'),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA), // Light grey/blue background
        appBar: CustomAppBar(
          title: 'Notes',
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () {
              _handleBack();
            },
          ),
        ),
        body: Column(
          children: [
            // Type Filter - Toggle Buttons
            Container(
              padding: const EdgeInsets.only(
                  top: 4.0, left: 16.0, right: 16.0, bottom: 8.0),
              child: Row(
                children: [
                  Expanded(
                    child: _buildTypeButton(
                      label: 'Hand Notes',
                      icon: Icons.edit_note_rounded,
                      type: 'Hand',
                      isSelected: _selectedType == 'Hand',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildTypeButton(
                      label: 'Digital Notes',
                      icon: Icons.laptop_rounded,
                      type: 'Digital',
                      isSelected: _selectedType == 'Digital',
                    ),
                  ),
                ],
              ),
            ),
            // Other Filters
            Container(
              padding: const EdgeInsets.only(left: 16.0, right: 16.0),
              child: Row(
                children: [
                  Expanded(
                    child: _buildFilterChip(
                      'Class',
                      _selectedClass,
                      _classes,
                      (val) {
                        setState(() {
                          _selectedClass = val;
                          _selectedSubject = null;
                          _selectedTopic = null;
                          _updateDropdowns();
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildFilterChip(
                      'Subject',
                      _selectedSubject,
                      _subjects,
                      (val) {
                        setState(() {
                          _selectedSubject = val;
                          _selectedTopic = null;
                          _updateDropdowns();
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildFilterChip(
                      'Topic',
                      _selectedTopic,
                      _topics,
                      (val) {
                        setState(() {
                          _selectedTopic = val;
                        });
                      },
                    ),
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
