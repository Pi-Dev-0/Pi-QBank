import 'package:flutter/material.dart';
import 'package:pi_qbank/widgets/custom_app_bar.dart';
import 'package:intl/intl.dart'; // For date formatting
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert'; // For JSON encoding/decoding

class Note {
  String text;
  DateTime? reminder;

  Note(this.text, {this.reminder});

  Map<String, dynamic> toJson() => {
        'text': text,
        'reminder': reminder?.toIso8601String(),
      };

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      json['text'] as String,
      reminder: json['reminder'] != null ? DateTime.parse(json['reminder'] as String) : null,
    );
  }
}

class NotesRemainderPage extends StatefulWidget {
  const NotesRemainderPage({super.key});

  @override
  State<NotesRemainderPage> createState() => _NotesRemainderPageState();
}

class _NotesRemainderPageState extends State<NotesRemainderPage> {
  final List<Note> _notes = [];
  final TextEditingController _noteController = TextEditingController();
  int? _editingIndex;
  DateTime? _selectedReminderDateTime;

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final notesStringList = prefs.getStringList('notes_list');
    if (notesStringList != null) {
      setState(() {
        _notes.clear(); // Clear existing notes before loading
        for (var noteJson in notesStringList) {
          try {
            _notes.add(Note.fromJson(jsonDecode(noteJson)));
          } catch (e) {
            // Handle parsing errors, e.g., if old data is not in JSON format
            // For now, we'll just print the error and skip the malformed note.
            // In a real app, you might want to log this or migrate data.
            print('Error decoding note: $e - $noteJson');
          }
        }
      });
    }
  }

  Future<void> _saveNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final notesStringList = _notes.map((note) => jsonEncode(note.toJson())).toList();
    await prefs.setStringList('notes_list', notesStringList);
  }

  void _addNote() {
    if (_noteController.text.isNotEmpty) {
      setState(() {
        if (_editingIndex != null) {
          _notes[_editingIndex!].text = _noteController.text;
          _notes[_editingIndex!].reminder = _selectedReminderDateTime;
          _editingIndex = null;
        } else {
          _notes.add(Note(_noteController.text, reminder: _selectedReminderDateTime));
        }
        _noteController.clear();
        _selectedReminderDateTime = null;
      });
      _saveNotes();
    }
  }

  void _editNote(int index) {
    setState(() {
      _noteController.text = _notes[index].text;
      _selectedReminderDateTime = _notes[index].reminder;
      _editingIndex = index;
    });
  }

  void _deleteNote(int index) {
    setState(() {
      _notes.removeAt(index);
    });
    _saveNotes();
  }

  Future<void> _selectReminderDateTime(BuildContext context) async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedReminderDateTime ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2101),
    );
    if (pickedDate != null) {
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_selectedReminderDateTime ?? DateTime.now()),
      );
      if (pickedTime != null) {
        setState(() {
          _selectedReminderDateTime = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            pickedTime.hour,
            pickedTime.minute,
          );
        });
      }
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Notes & Remainder',
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _noteController,
              style: TextStyle(color: Colors.black87),
              decoration: InputDecoration(
                labelText: _editingIndex == null ? 'New Note' : 'Edit Note',
                labelStyle: TextStyle(color: Colors.grey[700]),
                filled: true,
                fillColor: Colors.grey[200],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                  borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2.0),
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _editingIndex == null ? Icons.add : Icons.check,
                    color: Theme.of(context).primaryColor,
                  ),
                  onPressed: _addNote,
                ),
              ),
            ),
            SizedBox(height: 8.0),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedReminderDateTime == null
                        ? 'No reminder set'
                        : 'Reminder: ${DateFormat('yyyy-MM-dd – hh:mm a').format(_selectedReminderDateTime!)}',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.calendar_today, color: Theme.of(context).primaryColor),
                  onPressed: () => _selectReminderDateTime(context),
                ),
                if (_selectedReminderDateTime != null)
                  IconButton(
                    icon: Icon(Icons.clear, color: Colors.redAccent),
                    onPressed: () {
                      setState(() {
                        _selectedReminderDateTime = null;
                      });
                    },
                  ),
              ],
            ),
            SizedBox(height: 16.0),
            Expanded(
              child: ListView.builder(
                itemCount: _notes.length,
                itemBuilder: (context, index) {
                  final note = _notes[index];
                  return Card(
                    elevation: 4.0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                    margin: EdgeInsets.symmetric(vertical: 8.0),
                    child: ListTile(
                      title: Text(
                        note.text,
                        style: TextStyle(fontSize: 16.0, color: Colors.black87),
                      ),
                      subtitle: note.reminder != null
                          ? Text(
                              'Reminder: ${DateFormat('yyyy-MM-dd – hh:mm a').format(note.reminder!)}',
                              style: TextStyle(fontSize: 12.0, color: Colors.grey[600]),
                            )
                          : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(Icons.edit, color: Colors.blueAccent),
                            onPressed: () => _editNote(index),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete, color: Colors.redAccent),
                            onPressed: () => _deleteNote(index),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
