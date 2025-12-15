import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../widgets/custom_app_bar.dart';
import '../../widgets/loading_widget.dart';
import '../online_pdf_viewer_page.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../pdf_viewer_page.dart';
import '../../widgets/delete_confirmation_dialog.dart';

// Data model for the filters fetched from the API
class NoteFilter {
  final String className;
  final String subject;
  final String topic;
  final String title;
  final String url;

  NoteFilter({required this.className, required this.subject, required this.topic, required this.title, required this.url});

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
  final Map<String, double> _downloadProgress = {};

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
        // Auto show class selection dialog after loading
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showSelectionDialog('Class', _classes, _selectedClass, (String? newValue) {
            setState(() {
              _selectedClass = newValue;
              _selectedSubject = null;
              _selectedTopic = null;
              _updateDropdowns();
            });
          });
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

  Future<bool> _isNoteDownloaded(String title) async {
    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/${title.replaceAll(' ', '_')}.pdf';
    final file = File(filePath);
    return file.exists();
  }

  Future<void> _deleteNote(String title) async {
    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/${title.replaceAll(' ', '_')}.pdf';
    final file = File(filePath);

    if (await file.exists()) {
      await file.delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Note deleted successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      setState(() {});
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Note not found.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _downloadNote(String url, String title, BuildContext context) async {
    final directory = await getApplicationDocumentsDirectory();
    if (!context.mounted) return;
    final filePath = '${directory.path}/${title.replaceAll(' ', '_')}.pdf';
    final file = File(filePath);

    try {
      setState(() {
        _downloadProgress[title] = 0.0;
      });

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
            setState(() {
              _downloadProgress[title] = received / contentLength;
            });
          },
          onDone: () async {
            await file.writeAsBytes(bytes);
            setState(() {
              _downloadProgress.remove(title);
            });
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Note downloaded successfully!'),
                backgroundColor: Colors.green,
              ),
            );
          },
          onError: (_) {
            setState(() {
              _downloadProgress.remove(title);
            });
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to download the note.'),
                backgroundColor: Colors.red,
              ),
            );
          },
          cancelOnError: true,
        );
      } else {
        setState(() {
          _downloadProgress.remove(title);
        });
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to download the note.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _downloadProgress.remove(title);
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('An error occurred while downloading the note.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showSelectionDialog(String label, List<String> items, String? value, ValueChanged<String?> onChanged) {
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
                'Select $label',
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

  // Color palette for note cards
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

  Widget _buildNoteCard(NoteFilter note, int index) {
    final color = _cardColors[index % _cardColors.length];

    return FutureBuilder<bool>(
      future: _isNoteDownloaded(note.title),
      builder: (context, snapshot) {
        final isDownloaded = snapshot.data ?? false;
        final progress = _downloadProgress[note.title] ?? 0.0;

        return Theme(
          data: Theme.of(context).copyWith(
            primaryColor: color,
            colorScheme: ColorScheme.fromSeed(
              seedColor: color,
              primary: color,
            ),
          ),
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
                  if (progress > 0 && progress < 1)
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
                  if (progress > 0 && progress < 1)
                    Text(
                      '${(progress * 100).toInt()}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  if (progress == 0 || progress == 1)
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isDownloaded
                            ? Icons.check_circle
                            : Icons.picture_as_pdf,
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
              subtitle: Text("Made By: Rashid Sahriar Asif"),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isDownloaded)
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () async {
                        final shouldDelete = await showDeleteConfirmationDialog(
                          context: context,
                          title: 'Delete Note',
                          message:
                              'Are you sure you want to delete this note?',
                          paperTitle: note.title,
                          paperSubtitle: null,
                        );
                        if (shouldDelete == true) {
                          await _deleteNote(note.title);
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
                  if (!context.mounted) return;
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => PDFViewerPage(
                        filePath: filePath,
                        title: note.title,
                      ),
                    ),
                  );
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
                            Icon(
                              Icons.book,
                              color: color,
                            ),
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
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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
                                    side: BorderSide(
                                      color: color,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  onPressed: () async {
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
                        parentContext,
                        MaterialPageRoute(
                          builder: (context) => OnlinePDFViewerPage(
                            pdfUrl: note.url,
                            title: note.title,
                          ),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(parentContext).showSnackBar(
                        const SnackBar(
                          content: Text('No preview available.'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  } else if (choice == 'download') {
                    if (note.url.startsWith('http')) {
                      await _downloadNote(note.url, note.title, context);
                    } else {
                      ScaffoldMessenger.of(parentContext).showSnackBar(
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
        );
      },
    );
  }

  Widget _buildNotesList() {
    final filteredNotes = _allFilters.where((f) {
      return (_selectedClass == null || f.className == _selectedClass) &&
             (_selectedSubject == null || f.subject == _selectedSubject) &&
             (_selectedTopic == null || f.topic == _selectedTopic);
    }).toList();
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filteredNotes.length,
      itemBuilder: (context, index) {
        final note = filteredNotes[index];
        return _buildNoteCard(note, index);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'Hand Notes'),
      body: _isLoading
          ? const LoadingWidget(loadingText: 'Loading Filters...')
          : Column(
              children: [
                Padding(
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
                Expanded(
                  child: _buildNotesList(),
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
