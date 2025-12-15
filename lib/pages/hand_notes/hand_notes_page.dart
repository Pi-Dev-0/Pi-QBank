import 'package:flutter/material.dart';
import '../../widgets/custom_app_bar.dart';
import '../../widgets/question_paper_card.dart'; // Import QuestionPaperCard

// Define a structure for the notes data
class NoteItem {
  final String title;
  final String subtitle;
  final String year;
  final String examYear;
  final String downloadUrl;
  final String category;

  NoteItem({
    required this.title,
    required this.subtitle,
    required this.year,
    required this.examYear,
    required this.downloadUrl,
    required this.category,
  });

  factory NoteItem.fromJson(Map<String, dynamic> json) {
    return NoteItem(
      title: json['title'] ?? '',
      subtitle: json['subtitle'] ?? '',
      year: json['year'] ?? '',
      examYear: json['examYear'] ?? '',
      downloadUrl: json['downloadUrl'] ?? '',
      category: json['category'] ?? 'Hand Notes',
    );
  }
}

// Placeholder data for selectors
const List<String> classes = [
  'Class 6',
  'Class 7',
  'Class 8',
  'Class 9',
  'Class 10',
  'HSC',
  'Admission'
];
const Map<String, List<String>> subjectsByClass = {
  'Class 6': ['Math', 'Science', 'Bangla'],
  'HSC': ['Physics', 'Chemistry', 'Biology'],
  'Admission': ['Physics', 'Chemistry', 'Math', 'Biology', 'English', 'General Knowledge']
  // Add more mappings as needed
};

// Placeholder API URL - To be replaced with actual Apps Script URL later
const String handNotesApiUrl = 'YOUR_GOOGLE_APPS_SCRIPT_API_URL';

class HandNotesPage extends StatefulWidget {
  const HandNotesPage({super.key});

  @override
  State<HandNotesPage> createState() => _HandNotesPageState();
}

class _HandNotesPageState extends State<HandNotesPage> {
  String? _selectedClass;
  String? _selectedSubject;
  String? _selectedTopic;

  List<String> get _availableSubjects =>
      subjectsByClass[_selectedClass] ?? [];

  // Placeholder function for fetching topics based on selected subject
  Future<List<String>> _fetchTopics(String? className, String? subjectName) async {
    if (className == null || subjectName == null) return [];
    // Dummy topics for now
    await Future.delayed(const Duration(milliseconds: 300));
    return List.generate(5, (index) => 'Topic ${index + 1}: Subtopic $index');
  }

  // Placeholder list of notes fetched from API
  Future<List<NoteItem>> _notesFuture = Future.value([]);

  @override
  void initState() {
    super.initState();
    // Initialize with first class, setting it explicitly helps in dropdown initialization
    _selectedClass = classes.first;
    // We intentionally don't call _updateNotes() here to wait for user selection of subject/topic.
  }
  
  void _updateNotes() {
    if (_selectedClass == null || _selectedSubject == null || _selectedTopic == null) {
      setState(() {
        _notesFuture = Future.value([]);
      });
      return;
    }
    
    setState(() {
      _notesFuture = _fetchNotesFromApi(
        _selectedClass!,
        _selectedSubject!,
        _selectedTopic!,
      );
    });
  }

  // Dummy function mimicking the API call
  Future<List<NoteItem>> _fetchNotesFromApi(
      String className, String subjectName, String topicName) async {
    // In a real scenario, this would call your Apps Script API
    // e.g., using a service class and HTTP package.
    
    if (handNotesApiUrl == 'YOUR_GOOGLE_APPS_SCRIPT_API_URL') {
      // Return dummy data if API URL is not set
      await Future.delayed(const Duration(seconds: 1));
      return [
        NoteItem(
          title: '$className $subjectName Note',
          subtitle: topicName,
          year: '2024',
          examYear: 'N/A',
          downloadUrl: 'https://example.com/note_1.pdf', // Placeholder URL
          category: 'Hand Notes',
        ),
        NoteItem(
          title: 'Summary: $topicName',
          subtitle: '$className $subjectName',
          year: '2024',
          examYear: 'N/A',
          downloadUrl: 'https://example.com/note_2.pdf', // Placeholder URL
          category: 'Hand Notes',
        ),
      ];
    }
    
    // API logic goes here
    // Example:
    // final response = await http.get(Uri.parse('$HAND_NOTES_API_URL?class=$className&subject=$subjectName&topic=$topicName'));
    // return (json.decode(response.body) as List).map((e) => NoteItem.fromJson(e)).toList();
    
    return [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'Hand Notes'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              alignment: WrapAlignment.center,
              children: [
                SizedBox(
                  width: 110,
                  child: _buildDropdown(
                    labelText: 'Class',
                    value: _selectedClass,
                    items: classes,
                    onChanged: (String? newValue) {
                      setState(() {
                        _selectedClass = newValue;
                        _selectedSubject = null; // Reset subject on class change
                        _selectedTopic = null; // Reset topic on class change
                        _notesFuture = Future.value([]);
                      });
                    },
                  ),
                ),
                SizedBox(
                  width: 110,
                  child: _buildDropdown(
                    labelText: 'Subject',
                    value: _selectedSubject,
                    items: _availableSubjects,
                    enabled: _selectedClass != null,
                    onChanged: (String? newValue) {
                      setState(() {
                        _selectedSubject = newValue;
                        _selectedTopic = null; // Reset topic on subject change
                        _notesFuture = Future.value([]);
                      });
                    },
                  ),
                ),
                SizedBox(
                  width: 110,
                  child: FutureBuilder<List<String>>(
                    future: _selectedSubject != null
                        ? _fetchTopics(_selectedClass, _selectedSubject)
                        : Future.value([]),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          _selectedSubject != null) {
                        return _buildDropdown(
                          labelText: 'Topic',
                          value: 'Loading...',
                          items: [],
                          onChanged: (_) {},
                          enabled: false,
                        );
                      }

                      List<String> topics = snapshot.data ?? [];

                      if (topics.isNotEmpty &&
                          _selectedTopic == null &&
                          _selectedSubject != null) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            setState(() {
                              _selectedTopic = topics.first;
                              _updateNotes();
                            });
                          }
                        });
                      }

                      return _buildDropdown(
                        labelText: 'Topic',
                        value: _selectedTopic,
                        items: topics,
                        enabled: _selectedSubject != null && topics.isNotEmpty,
                        onChanged: (String? newValue) {
                          setState(() {
                            _selectedTopic = newValue;
                            _updateNotes();
                          });
                        },
                      );
                    },
                  ),
                ),

              ],
            ),
          ),
          
          // Notes List Display
          Expanded(
            child: FutureBuilder<List<NoteItem>>(
              future: _notesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  return Center(child: Text('Error loading notes: ${snapshot.error}')); // More descriptive error
                } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('No hand notes found for the selection.'));
                }

                final notes = snapshot.data!;
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: notes.length,
                  itemBuilder: (context, index) {
                    final note = notes[index];
                    return QuestionPaperCard(
                      title: note.title,
                      subtitle: note.subtitle,
                      year: note.year,
                      examYear: note.examYear,
                      downloadUrl: note.downloadUrl,
                      category: note.category,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDropdown({
    required String labelText,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    bool enabled = true,
  }) {
    return AbsorbPointer(
      absorbing: !enabled,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.5,
        child: InkWell(
          onTap: enabled
              ? () {
                  showDialog(
                    context: context,
                    barrierDismissible: true,
                    builder: (BuildContext dialogContext) {
                      return AlertDialog(
                        backgroundColor: Colors.white,
                        elevation: 8,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        title: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              'Select $labelText',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                          ),
                        ),
                        content: SingleChildScrollView(
                          child: ListBody(
                            children: items.map((item) {
                              final isSelected = item == value;
                              return GestureDetector(
                                onTap: () {
                                  onChanged(item);
                                  Navigator.of(dialogContext).maybePop();
                                },
                                child: Container(
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 6),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 10, horizontal: 14),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Colors.blue.shade100
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isSelected
                                          ? Colors.blue
                                          : Colors.grey.shade300,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Text(
                                    item,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: isSelected
                                          ? Colors.blue.shade900
                                          : Colors.black87,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      );
                    },
                  );
                }
              : null,
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: labelText,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Center(
                    child: Text(
                      value?.isNotEmpty == true ? value! : 'Select',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: enabled
                            ? (value?.isNotEmpty == true
                                ? Colors.black
                                : Colors.grey[500])
                            : Colors.grey[400],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const Icon(Icons.arrow_drop_down, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
