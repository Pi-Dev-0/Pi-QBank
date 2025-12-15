import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../widgets/custom_app_bar.dart';
import '../../widgets/loading_widget.dart';

// Data model for the filters fetched from the API
class NoteFilter {
  final String className;
  final String subject;
  final String topic;

  NoteFilter({required this.className, required this.subject, required this.topic});

  factory NoteFilter.fromJson(Map<String, dynamic> json) {
    return NoteFilter(
      className: json['class'] ?? '',
      subject: json['subject'] ?? '',
      topic: json['topic'] ?? '',
    );
  }
}

// The API URL that provides the filter combinations
const String handNotesApiUrl = 'https://script.google.com/macros/s/AKfycbzlX697mRB2DOX4isBhf35BrWidU6eKx63eiJ3VUB-dq0mfCEnfFDsp3yZ2ET8rtcmi/exec';

class HandNotesPage extends StatefulWidget {
  const HandNotesPage({super.key});

  @override
  State<HandNotesPage> createState() => _HandNotesPageState();
}

class _HandNotesPageState extends State<HandNotesPage> {
  String? _selectedClass;
  String? _selectedSubject;
  String? _selectedTopic;

  List<NoteFilter> _allFilters = [];
  List<String> _classes = [];
  List<String> _subjects = [];
  List<String> _topics = [];

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchFilters();
  }

  Future<void> _fetchFilters() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final response = await http.get(Uri.parse(handNotesApiUrl));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        _allFilters = data.map((json) => NoteFilter.fromJson(json)).toList();
        _updateDropdowns();
      } else {
        // Handle error
      }
    } catch (e) {
      // Handle error
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _updateDropdowns() {
    setState(() {
      _classes = _allFilters.map((f) => f.className).toSet().toList()..sort();
      if (_selectedClass != null && _classes.contains(_selectedClass)) {
        _subjects = _allFilters
            .where((f) => f.className == _selectedClass)
            .map((f) => f.subject)
            .toSet()
            .toList()..sort();
      } else {
        _selectedSubject = null;
        _subjects = [];
      }
      if (_selectedSubject != null && _subjects.contains(_selectedSubject)) {
        _topics = _allFilters
            .where((f) => f.className == _selectedClass && f.subject == _selectedSubject)
            .map((f) => f.topic)
            .toSet()
            .toList()..sort();
      } else {
        _selectedTopic = null;
        _topics = [];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'Hand Notes'),
      body: _isLoading
          ? const LoadingWidget(loadingText: 'Loading Filters...')
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                alignment: WrapAlignment.center,
                children: [
                  SizedBox(
                    width: 120,
                    child: _buildDropdown(
                      labelText: 'Class',
                      value: _selectedClass,
                      items: _classes,
                      onChanged: (String? newValue) {
                        setState(() {
                          _selectedClass = newValue;
                          _selectedSubject = null;
                          _selectedTopic = null;
                          _updateDropdowns();
                        });
                      },
                    ),
                  ),
                  SizedBox(
                    width: 120,
                    child: _buildDropdown(
                      labelText: 'Subject',
                      value: _selectedSubject,
                      items: _subjects,
                      enabled: _selectedClass != null,
                      onChanged: (String? newValue) {
                        setState(() {
                          _selectedSubject = newValue;
                          _selectedTopic = null;
                          _updateDropdowns();
                        });
                      },
                    ),
                  ),
                  SizedBox(
                    width: 120,
                    child: _buildDropdown(
                      labelText: 'Topic',
                      value: _selectedTopic,
                      items: _topics,
                      enabled: _selectedSubject != null,
                      onChanged: (String? newValue) {
                        setState(() {
                          _selectedTopic = newValue;
                        });
                      },
                    ),
                  ),
                ],
              ),
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
        borderRadius: BorderRadius.circular(12.0),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: labelText,
            filled: true,
            fillColor: enabled ? Colors.white : Colors.grey.shade100,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.blue, width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            labelStyle: TextStyle(
              color: enabled ? Colors.black54 : Colors.grey,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  value?.isNotEmpty == true ? value! : 'Select',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: enabled
                        ? (value?.isNotEmpty == true
                            ? Colors.black87
                            : Colors.grey.shade600)
                        : Colors.grey.shade500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.arrow_drop_down_rounded, size: 24, color: enabled ? Colors.grey.shade700 : Colors.grey.shade400,),
            ],
          ),
        ),
      ),
    );
  }
}
