import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';
import 'package:pi_qbank/widgets/custom_app_bar.dart';
import 'package:pi_qbank/pages/mcq_test_page.dart';
import 'package:pi_qbank/widgets/loading_widget.dart';

class CloudTestsPage extends StatefulWidget {
  const CloudTestsPage({super.key});

  @override
  State<CloudTestsPage> createState() => _CloudTestsPageState();
}

class _CloudTestsPageState extends State<CloudTestsPage> {
  bool _isLoading = true;
  String? _errorMessage;

  final Map<String, _CloudTestGroup> _testGroups = {};
  
  // Available filter options
  final Set<String> _availableClasses = {};
  final Set<String> _availableSubjects = {};
  final Set<String> _availableTopics = {};

  // Currently selected filters
  final Set<String> _selectedClasses = {};
  final Set<String> _selectedSubjects = {};
  final Set<String> _selectedTopics = {};

  final String _googleWebAppUrl = 'https://script.google.com/macros/s/AKfycbwAMFYO2yPtEmxK1Jbhu727bSvFei8I7ZQzUqXm079Gzj4w_tw9xreN3j3bl9mrwtkbTg/exec?action=getTests';

  // Color palette for formula cards
  final List<Color> _cardColors = [
    Colors.purple,
    Colors.orange,
    Colors.blue,
    Colors.red,
    Colors.teal,
    Colors.pink,
    Colors.indigo,
    Colors.cyan,
    Colors.amber,
    Colors.deepOrange,
  ];

  @override
  void initState() {
    super.initState();
    _fetchCloudTests();
  }

  Future<void> _fetchCloudTests() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.get(Uri.parse(_googleWebAppUrl));
      if (response.statusCode == 200 || response.statusCode == 302) {
        String body = response.body;
        final Map<String, dynamic> jsonResponse = json.decode(body);
        if (jsonResponse['status'] == 'success') {
          _parseTests(jsonResponse['data']);
        } else {
          setState(() {
            _errorMessage = 'Failed to load tests: ${jsonResponse['message'] ?? 'Unknown error'}';
          });
        }
      } else {
        setState(() {
          _errorMessage = 'Server error: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Network error: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _parseTests(Map<String, dynamic> data) {
    _testGroups.clear();
    _availableClasses.clear();
    _availableSubjects.clear();
    _availableTopics.clear();

    void processQuestion(Map<String, dynamic> q, String testType) {
      String ts = q['timestamp']?.toString() ?? 'unknown_time';
      String key = '${testType}_$ts';
      String cName = q['className']?.toString() ?? 'N/A';
      String subj = q['subject']?.toString() ?? 'N/A';
      String topic = q['topic']?.toString() ?? 'N/A';
      
      _availableClasses.add(cName);
      _availableSubjects.add(subj);
      _availableTopics.add(topic);

      if (!_testGroups.containsKey(key)) {
        _testGroups[key] = _CloudTestGroup(
          timestamp: ts,
          testType: testType,
          className: cName,
          subject: subj,
          topic: topic,
          language: q['language']?.toString() ?? 'English',
        );
      }
      _testGroups[key]!.questions.add(q);
    }

    if (data['MCQ'] != null) {
      for (var q in data['MCQ']) {
        processQuestion(q as Map<String, dynamic>, 'MCQ');
      }
    }

    if (data['Short Question'] != null) {
      for (var q in data['Short Question']) {
        processQuestion(q as Map<String, dynamic>, 'Short Question');
      }
    }
    
    // Automatically select all by default
    _selectedClasses.addAll(_availableClasses);
    _selectedSubjects.addAll(_availableSubjects);
    _selectedTopics.addAll(_availableTopics);
  }

  void _launchTest(_CloudTestGroup group) {
    if (group.testType == 'MCQ') {
      _startMCQTest(group.questions, group.language);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Taking this type of exam is not supported yet.')),
      );
    }
  }

  void _startMCQTest(List<dynamic> questions, String language) {
    List<Map<String, dynamic>> formattedQuestions = questions.map((q) {
      return {
        "question": q['question'],
        "options": q['options'],
        "correct_answer": q['correct_answer'],
      };
    }).toList();

    final aiResponseJson = json.encode({
      "questions": formattedQuestions
    });
    
    int testTime = formattedQuestions.length; // 1 min per question

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MCQTestPage(
          numberOfQuestions: formattedQuestions.length,
          testTimeInMinutes: testTime,
          aiResponse: aiResponseJson,
          language: language,
        ),
      ),
    );
  }

  void _showCustomExamDialog(List<dynamic> pool) {
    final TextEditingController countController = TextEditingController(text: pool.length.toString());
    
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Generate Custom Exam'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Found ${pool.length} matching MCQ questions from your filters.'),
              const SizedBox(height: 16),
              TextField(
                controller: countController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Number of Questions',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                int count = int.tryParse(countController.text) ?? pool.length;
                if (count <= 0) count = 1;
                if (count > pool.length) count = pool.length;
                
                // Randomly shuffle and pick 'count' questions
                final random = Random();
                List<dynamic> shuffledPool = List.from(pool)..shuffle(random);
                List<dynamic> selectedQuestions = shuffledPool.take(count).toList();
                
                Navigator.pop(context);
                
                // Since this is a mixed pool, we assume English/Bengali is mixed. Pass 'Mixed' as language
                _startMCQTest(selectedQuestions, "Mixed");
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
              child: const Text('Start Exam', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _onGenerateCustomExam() {
    // Pool all MCQ questions that match the active filters
    List<dynamic> matchedQuestions = [];
    for (var group in _testGroups.values) {
      if (group.testType == 'MCQ' &&
          _selectedClasses.contains(group.className) &&
          _selectedSubjects.contains(group.subject) &&
          _selectedTopics.contains(group.topic)) {
        matchedQuestions.addAll(group.questions);
      }
    }

    if (matchedQuestions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No MCQ questions match the current filters.')),
      );
      return;
    }

    _showCustomExamDialog(matchedQuestions);
  }

  Widget _buildMultiSelectDropdown(String label, List<String> available, Set<String> selected, Function(String, bool) onSelected) {
    IconData getIcon() {
      switch (label) {
        case 'Classes': return Icons.school_rounded;
        case 'Subjects': return Icons.menu_book_rounded;
        case 'Topics': return Icons.topic_rounded;
        default: return Icons.category_rounded;
      }
    }

    String displayText = selected.isEmpty 
        ? 'Select' 
        : (selected.length == available.length && available.isNotEmpty ? 'All' : '${selected.length} Selected');

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
        GestureDetector(
          onTap: () {
            showDialog(
              context: context,
              builder: (context) {
                return StatefulBuilder(
                  builder: (context, setDialogState) {
                    return AlertDialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      title: Text('Select $label'),
                      content: SizedBox(
                        width: double.maxFinite,
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: available.length,
                          itemBuilder: (context, index) {
                            String item = available[index];
                            bool isSelected = selected.contains(item);
                            return CheckboxListTile(
                              activeColor: Colors.indigo,
                              title: Text(item),
                              value: isSelected,
                              onChanged: (bool? val) {
                                setDialogState(() {
                                  onSelected(item, val ?? false);
                                });
                                setState(() {}); // Update the main page state too
                              },
                            );
                          },
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () {
                            bool isAllSelected = selected.length == available.length && available.isNotEmpty;
                            setDialogState(() {
                              for (var item in available) {
                                onSelected(item, !isAllSelected);
                              }
                            });
                            setState(() {});
                          },
                          child: Text(
                            (selected.length == available.length && available.isNotEmpty) ? 'Deselect All' : 'Select All', 
                            style: const TextStyle(color: Colors.indigo)
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Done', style: TextStyle(color: Colors.indigo)),
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
          child: Container(
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
            child: Row(
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
                    displayText,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected.isNotEmpty ? FontWeight.bold : FontWeight.normal,
                      color: selected.isNotEmpty ? Colors.black87 : Colors.grey,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.indigo, size: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<String> _getSortedClasses() {
    const classOrder = [
      'One', 'Two', 'Three', 'Four', 'Five', 
      'Six', 'Seven', 'JSC', 'Eight', 'Nine', 'Ten', 
      'SSC', 'HSC', 'Honours', 'Masters', 'Job'
    ];
    final list = _availableClasses.toList();
    list.sort((a, b) {
      int indexA = classOrder.indexOf(a);
      int indexB = classOrder.indexOf(b);
      if (indexA == -1 && indexB == -1) return a.compareTo(b);
      if (indexA == -1) return 1;
      if (indexB == -1) return -1;
      return indexA.compareTo(indexB);
    });
    return list;
  }

  List<String> _getAvailableSubjects() {
    Set<String> subjects = {};
    for (var group in _testGroups.values) {
      if (_selectedClasses.isEmpty || _selectedClasses.contains(group.className)) {
        subjects.add(group.subject);
      }
    }
    final list = subjects.toList();
    list.sort();
    return list;
  }

  List<String> _getAvailableTopics() {
    Set<String> topics = {};
    for (var group in _testGroups.values) {
      bool classMatch = _selectedClasses.isEmpty || _selectedClasses.contains(group.className);
      bool subjectMatch = _selectedSubjects.isEmpty || _selectedSubjects.contains(group.subject);
      if (classMatch && subjectMatch) {
        topics.add(group.topic);
      }
    }
    final list = topics.toList();
    list.sort();
    return list;
  }

  void _cleanupSelections() {
    final validSubjects = _getAvailableSubjects().toSet();
    _selectedSubjects.removeWhere((s) => !validSubjects.contains(s));

    final validTopics = _getAvailableTopics().toSet();
    _selectedTopics.removeWhere((t) => !validTopics.contains(t));
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 16.0, bottom: 24.0),
      color: const Color(0xFFF5F7FA), // Match online_class_page background
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildMultiSelectDropdown('Classes', _getSortedClasses(), _selectedClasses, (item, isSelected) {
                  if (isSelected) {
                    _selectedClasses.add(item);
                  } else {
                    _selectedClasses.remove(item);
                  }
                  _cleanupSelections();
                }),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMultiSelectDropdown('Subjects', _getAvailableSubjects(), _selectedSubjects, (item, isSelected) {
                  if (isSelected) {
                    _selectedSubjects.add(item);
                  } else {
                    _selectedSubjects.remove(item);
                  }
                  _cleanupSelections();
                }),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMultiSelectDropdown('Topics', _getAvailableTopics(), _selectedTopics, (item, isSelected) {
                  if (isSelected) {
                    _selectedTopics.add(item);
                  } else {
                    _selectedTopics.remove(item);
                  }
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: CustomAppBar(
        title: 'Cloud Tests',
      ),
      body: _buildBody(),
      floatingActionButton: _isLoading || _errorMessage != null || _testGroups.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _onGenerateCustomExam,
              icon: const Icon(Icons.shuffle, color: Colors.white),
              label: const Text('Custom Exam', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              backgroundColor: Colors.teal,
            ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const LoadingWidget(loadingText: 'Loading Cloud Tests...');
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchCloudTests,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_testGroups.isEmpty) {
      return const Center(
        child: Text('No cloud tests available.'),
      );
    }

    // Filter grouped tests to show only those that match ALL active filters.
    // An empty selection set means "no filter applied" (show all for that dimension).
    final filteredGroups = _testGroups.values.where((g) {
      final classMatch = _selectedClasses.isEmpty || _selectedClasses.contains(g.className);
      final subjectMatch = _selectedSubjects.isEmpty || _selectedSubjects.contains(g.subject);
      final topicMatch = _selectedTopics.isEmpty || _selectedTopics.contains(g.topic);
      return classMatch && subjectMatch && topicMatch;
    }).toList();

    filteredGroups.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return Column(
      children: [
        Container(
          color: Colors.white,
          child: _buildFilters(),
        ),
        Expanded(
          child: filteredGroups.isEmpty
              ? const Center(child: Text('No tests match the current filters.'))
              : ListView.builder(
                  padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 80), // bottom padding for FAB
                  itemCount: filteredGroups.length,
                  itemBuilder: (context, index) {
                    final group = filteredGroups[index];
                    final color = _cardColors[index % _cardColors.length];
                    
                    return Theme(
                      data: Theme.of(context).copyWith(
                        primaryColor: color,
                        colorScheme: ColorScheme.fromSeed(seedColor: color, primary: color),
                      ),
                      child: Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 4,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _launchTest(group),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Leading icon
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    group.testType == 'MCQ' ? Icons.quiz : Icons.edit_document,
                                    size: 24,
                                    color: color,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Main content
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Top row: title + question count+type badge
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '${group.className} - ${group.subject}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: color.withOpacity(0.12),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              '${group.questions.length} Q • ${group.testType}',
                                              style: TextStyle(
                                                color: color,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Topic: ${group.topic}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      // Bottom row: Language at right
                                      Align(
                                        alignment: Alignment.bottomRight,
                                        child: Text(
                                          group.language,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade500,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _CloudTestGroup {
  final String timestamp;
  final String testType;
  final String className;
  final String subject;
  final String topic;
  final String language;
  final List<dynamic> questions = [];

  _CloudTestGroup({
    required this.timestamp,
    required this.testType,
    required this.className,
    required this.subject,
    required this.topic,
    required this.language,
  });
}
