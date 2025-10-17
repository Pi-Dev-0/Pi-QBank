import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../widgets/delete_confirmation_dialog.dart';

class Note {
  String title;
  String content;
  Color color;

  Note({required this.title, required this.content, this.color = Colors.white});

  Map<String, dynamic> toJson() => {
        'title': title,
        'content': content,
        'color': color.value,
      };

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      title: json['title'] as String,
      content: json['content'] as String,
      color: json['color'] != null ? Color(json['color'] as int) : Colors.white,
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
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadNotes();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
  }

  List<Note> get _filteredNotes {
    if (_searchQuery.isEmpty) {
      return _notes;
    }
    return _notes
        .where((note) =>
            note.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            note.content.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  Future<void> _loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final notesStringList = prefs.getStringList('notes_list_v2');
    if (notesStringList != null) {
      setState(() {
        _notes.clear();
        for (var noteJson in notesStringList) {
          try {
            _notes.add(Note.fromJson(jsonDecode(noteJson)));
          } catch (e) {
            print('Error decoding note: $e - $noteJson');
          }
        }
      });
    }
  }

  Future<void> _saveNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final notesStringList =
        _notes.map((note) => jsonEncode(note.toJson())).toList();
    await prefs.setStringList('notes_list_v2', notesStringList);
  }

  void _addOrUpdateNote(Note note, [int? index]) {
    setState(() {
      if (index != null) {
        _notes[index] = note;
      } else {
        _notes.insert(0, note);
      }
    });
    _saveNotes();
  }

  void _deleteNote(int index) async {
    final confirmed = await showDeleteConfirmationDialog(
      context: context,
      title: 'Delete Note',
      message: 'Are you sure you want to delete this note?',
      paperTitle: _notes[index].title,
      paperSubtitle: _notes[index].content.length > 100
          ? '${_notes[index].content.substring(0, 100)}...'
          : _notes[index].content,
    );

    if (confirmed == true) {
      setState(() {
        _notes.removeAt(index);
      });
      _saveNotes();
    }
  }

  void _navigateToNotePage([Note? note, int? index]) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NoteEditPage(note: note),
      ),
    );

    if (result != null && result is Note) {
      _addOrUpdateNote(result, index);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search notes...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30.0),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[200],
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),
        ),
      ),
      body: _buildNotesGrid(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToNotePage(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildNotesGrid() {
    if (_filteredNotes.isEmpty) {
      return Center(
        child: Text(
          _searchQuery.isEmpty ? 'No notes yet.' : 'No notes found.',
          style: const TextStyle(fontSize: 18, color: Colors.grey),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Column(children: _buildNoteColumn(0))),
          const SizedBox(width: 8),
          Expanded(child: Column(children: _buildNoteColumn(1))),
        ],
      ),
    );
  }

  List<Widget> _buildNoteColumn(int columnIndex) {
    final List<Widget> columnItems = [];
    for (int i = columnIndex; i < _filteredNotes.length; i += 2) {
      columnItems.add(
        NoteCard(
          note: _filteredNotes[i],
          onTap: () => _navigateToNotePage(_filteredNotes[i], i),
          onDelete: () => _deleteNote(i),
        ),
      );
    }
    return columnItems;
  }
}

class NoteCard extends StatelessWidget {
  final Note note;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const NoteCard({
    super.key,
    required this.note,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: note.color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12.0),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (note.title.isNotEmpty)
                Text(
                  note.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              if (note.title.isNotEmpty && note.content.isNotEmpty)
                const SizedBox(height: 8),
              if (note.content.isNotEmpty)
                Text(
                  note.content,
                  style: const TextStyle(fontSize: 14),
                  maxLines: 10,
                  overflow: TextOverflow.ellipsis,
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.delete, size: 20, color: Colors.brown),
                    onPressed: onDelete,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NoteEditPage extends StatefulWidget {
  final Note? note;

  const NoteEditPage({super.key, this.note});

  @override
  State<NoteEditPage> createState() => _NoteEditPageState();
}

class _NoteEditPageState extends State<NoteEditPage> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  late Color _noteColor;
  final List<Color> _colorPalette = [
    Colors.white,
    Colors.red[100]!,
    Colors.blue[100]!,
    Colors.green[100]!,
    Colors.yellow[100]!,
    Colors.orange[100]!,
    Colors.purple[100]!,
  ];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note?.title ?? '');
    _contentController =
        TextEditingController(text: widget.note?.content ?? '');
    _noteColor = widget.note?.color ?? Colors.white;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _saveAndExit() {
    if (_titleController.text.isEmpty && _contentController.text.isEmpty) {
      Navigator.pop(context);
      return;
    }
    final newNote = Note(
      title: _titleController.text,
      content: _contentController.text,
      color: _noteColor,
    );
    Navigator.pop(context, newNote);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _noteColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _saveAndExit,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.palette),
            onPressed: _showColorPalette,
          ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveAndExit,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration.collapsed(
                hintText: 'Title',
              ),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TextField(
                controller: _contentController,
                decoration: const InputDecoration.collapsed(
                  hintText: 'Note',
                ),
                maxLines: null,
                expands: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showColorPalette() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          height: 100,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: _colorPalette
                .map((color) => GestureDetector(
                      onTap: () {
                        setState(() {
                          _noteColor = color;
                        });
                        Navigator.pop(context);
                      },
                      child: CircleAvatar(
                        backgroundColor: color,
                        radius: 20,
                        child: _noteColor == color
                            ? const Icon(Icons.check, color: Colors.black)
                            : null,
                      ),
                    ))
                .toList(),
          ),
        );
      },
    );
  }
}