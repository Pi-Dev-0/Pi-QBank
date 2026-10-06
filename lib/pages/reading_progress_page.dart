import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:pi_qbank/services/reading_progress_service.dart';
import 'package:pi_qbank/widgets/custom_app_bar.dart';
import 'package:pi_qbank/widgets/delete_confirmation_dialog.dart';

class ReadingProgressPage extends StatefulWidget {
  const ReadingProgressPage({super.key});

  @override
  State<ReadingProgressPage> createState() => _ReadingProgressPageState();
}

class _ReadingProgressPageState extends State<ReadingProgressPage>
    with WidgetsBindingObserver {
  late Future<List<ReadingProgress>> _booksFuture;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _booksFuture = ReadingProgressService.getAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshBooks();
  }

  void _refreshBooks() {
    if (!mounted) return;
    setState(() {
      _booksFuture = ReadingProgressService.getAll();
    });
  }

  Future<void> _addBook() async {
    final draft = await showDialog<_PhysicalBookDraft>(
      context: context,
      builder: (_) => const _AddPhysicalBookDialog(),
    );
    if (draft == null) return;
    await ReadingProgressService.add(
      title: draft.title,
      startPage: draft.startPage,
      totalPages: draft.totalPages,
    );
    _refreshBooks();
  }

  Future<void> _editBook(ReadingProgress book) async {
    final draft = await showDialog<_PhysicalBookDraft>(
      context: context,
      builder: (_) => _EditPhysicalBookDialog(book: book),
    );
    if (draft == null) return;
    await ReadingProgressService.edit(
      id: book.id,
      title: draft.title,
      startPage: draft.startPage,
      totalPages: draft.totalPages,
    );
    _refreshBooks();
  }

  Future<void> _updatePage(ReadingProgress book) async {
    final page = await showDialog<int>(
      context: context,
      builder: (_) => _UpdateBookPageDialog(book: book),
    );
    if (page == null) return;
    await ReadingProgressService.updatePage(book.id, page);
    _refreshBooks();
  }

  Future<void> _pickThumbnail(ReadingProgress book) async {
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 86,
        maxWidth: 1200,
      );
      if (image == null) return;
      await ReadingProgressService.updateThumbnail(book.id, image.path);
      _refreshBooks();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Book cover updated.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save the book thumbnail: $error')),
      );
    }
  }

  Future<void> _removeBook(ReadingProgress book) async {
    final confirmed = await showDeleteConfirmationDialog(
      context: context,
      title: 'Remove Book',
      message: 'This will remove the book and its saved reading progress.',
      paperTitle: book.title,
    );
    if (confirmed != true) return;
    await ReadingProgressService.remove(book.id);
    _refreshBooks();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F5FB),
      appBar: const CustomAppBar(title: 'Reading Progress'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addBook,
        icon: const Icon(Icons.add),
        label: const Text('Add book'),
        backgroundColor: const Color(0xFF673AB7),
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<List<ReadingProgress>>(
        future: _booksFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final books = snapshot.data ?? const <ReadingProgress>[];
          if (books.isEmpty) return _buildEmptyState();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              _buildHeader(books.length),
              const SizedBox(height: 22),
              ...books.map(_buildBookCard),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(int bookCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF673AB7), Color(0xFF3F51B5)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF673AB7).withOpacity(0.24),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.17),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.auto_stories_rounded,
                color: Colors.white, size: 23),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your reading shelf',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$bookCount ${bookCount == 1 ? 'book' : 'books'} in progress · synced with your home widget',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.86),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFEDE7F6), Color(0xFFE8EAF6)],
                ),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(Icons.menu_book_rounded,
                  size: 56, color: Color(0xFF673AB7)),
            ),
            const SizedBox(height: 16),
            const Text(
              'No books added yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add a physical book to save the page where you stopped.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _addBook,
              icon: const Icon(Icons.add),
              label: const Text('Add book'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookCard(ReadingProgress book) {
    final progress = book.progress;
    final progressColor = progress == null
        ? const Color(0xFF673AB7)
        : HSVColor.fromAHSV(
            1,
            8 + (progress * 112),
            0.72,
            0.82,
          ).toColor();
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 1.5,
      shadowColor: const Color(0xFF34305A).withOpacity(0.08),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFE9E6F1)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Tooltip(
              message: 'Change cover image',
              child: Semantics(
                button: true,
                label: 'Change cover image for ${book.title}',
                child: InkWell(
                  onTap: () => _pickThumbnail(book),
                  borderRadius: BorderRadius.circular(14),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: SizedBox(
                          width: 82,
                          height: 112,
                          child: _buildThumbnail(book),
                        ),
                      ),
                      Positioned(
                        right: 5,
                        bottom: 5,
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: const Color(0xE6000000),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white70),
                          ),
                          child: const Icon(Icons.edit_rounded,
                              color: Colors.white, size: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          book.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF29243B),
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => _editBook(book),
                        borderRadius: BorderRadius.circular(20),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.edit_note_rounded,
                              size: 21, color: Color(0xFF89849A)),
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () => _removeBook(book),
                        borderRadius: BorderRadius.circular(20),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.delete_outline_rounded,
                              size: 19, color: Color(0xFF89849A)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0EBFA),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      book.startPage > 1
                          ? (book.totalPages == null
                              ? 'Page ${book.currentPage} (Starts at ${book.startPage})'
                              : 'Page ${book.currentPage} · Range ${book.startPage}–${book.totalPages}')
                          : (book.totalPages == null
                              ? 'Page ${book.currentPage}'
                              : 'Page ${book.currentPage} / ${book.totalPages}'),
                      style: const TextStyle(
                        color: Color(0xFF5E35B1),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (progress != null) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        backgroundColor: const Color(0xFFEDEAF3),
                        valueColor:
                            AlwaysStoppedAnimation<Color>(progressColor),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      book.startPage > 1 && book.totalPages != null
                          ? '${(progress * 100).round()}% complete (${book.currentPage - book.startPage}/${book.totalPages! - book.startPage} pages read)'
                          : '${(progress * 100).round()}% complete',
                      style: const TextStyle(
                        color: Color(0xFF7D788D),
                        fontSize: 11,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _updatePage(book),
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Update page'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF5E35B1),
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail(ReadingProgress book) {
    final path = book.thumbnailPath;
    if (path != null) {
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _thumbnailPlaceholder(book),
      );
    }
    return _thumbnailPlaceholder(book);
  }

  Widget _thumbnailPlaceholder(ReadingProgress book) {
    final colors = _coverColors(book.id);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: const Center(
        child: Icon(Icons.menu_book_rounded, color: Colors.white, size: 34),
      ),
    );
  }

  List<Color> _coverColors(String id) {
    const palettes = [
      [Color(0xFF7E57C2), Color(0xFF5C6BC0)],
      [Color(0xFF26A69A), Color(0xFF42A5F5)],
      [Color(0xFFEC6F91), Color(0xFFEE9B55)],
      [Color(0xFF5C6BC0), Color(0xFF26A69A)],
    ];
    return palettes[id.hashCode.abs() % palettes.length];
  }
}

class _PhysicalBookDraft {
  final String title;
  final int startPage;
  final int? totalPages;

  const _PhysicalBookDraft({
    required this.title,
    this.startPage = 1,
    this.totalPages,
  });
}

class _AddPhysicalBookDialog extends StatefulWidget {
  const _AddPhysicalBookDialog();

  @override
  State<_AddPhysicalBookDialog> createState() => _AddPhysicalBookDialogState();
}

class _AddPhysicalBookDialogState extends State<_AddPhysicalBookDialog> {
  final _titleController = TextEditingController();
  final _startPageController = TextEditingController(text: '1');
  final _totalPagesController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _titleController.dispose();
    _startPageController.dispose();
    _totalPagesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add a physical book'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _titleController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Book name',
                  hintText: 'e.g. Higher Math Part 2',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a book name'
                    : null,
              ),
              const SizedBox(height: 16),
              const Text(
                'Page range',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF5E35B1),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _startPageController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Start page',
                        hintText: '1',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) return null;
                        final start = int.tryParse(value.trim());
                        return start == null || start < 1 ? 'Enter >= 1' : null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _totalPagesController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'End page',
                        hintText: 'Optional',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) return null;
                        final end = int.tryParse(value.trim());
                        if (end == null || end < 1) {
                          return 'Enter valid page';
                        }
                        final start =
                            int.tryParse(_startPageController.text.trim()) ?? 1;
                        if (end < start) {
                          return 'End >= start';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Tip: If reading a specific part, volume, or chapter, enter its starting page (e.g. 150 to 350).',
                style: TextStyle(fontSize: 11, color: Color(0xFF7D788D)),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            final start = int.tryParse(_startPageController.text.trim()) ?? 1;
            Navigator.pop(
              context,
              _PhysicalBookDraft(
                title: _titleController.text.trim(),
                startPage: start < 1 ? 1 : start,
                totalPages: int.tryParse(_totalPagesController.text.trim()),
              ),
            );
          },
          child: const Text('Add book'),
        ),
      ],
    );
  }
}

class _EditPhysicalBookDialog extends StatefulWidget {
  final ReadingProgress book;

  const _EditPhysicalBookDialog({required this.book});

  @override
  State<_EditPhysicalBookDialog> createState() =>
      _EditPhysicalBookDialogState();
}

class _EditPhysicalBookDialogState extends State<_EditPhysicalBookDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _startPageController;
  late final TextEditingController _totalPagesController;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.book.title);
    _startPageController =
        TextEditingController(text: '${widget.book.startPage}');
    _totalPagesController = TextEditingController(
      text: widget.book.totalPages == null ? '' : '${widget.book.totalPages}',
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _startPageController.dispose();
    _totalPagesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit book & page range'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _titleController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Book name'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a book name'
                    : null,
              ),
              const SizedBox(height: 16),
              const Text(
                'Page range',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF5E35B1),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _startPageController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Start page',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter start page';
                        }
                        final start = int.tryParse(value.trim());
                        return start == null || start < 1 ? 'Enter >= 1' : null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _totalPagesController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'End page',
                        hintText: 'Optional',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) return null;
                        final end = int.tryParse(value.trim());
                        if (end == null || end < 1) {
                          return 'Enter valid page';
                        }
                        final start =
                            int.tryParse(_startPageController.text.trim()) ?? 1;
                        if (end < start) {
                          return 'End >= start';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Current progress: page ${widget.book.currentPage}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF7D788D)),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            final start = int.tryParse(_startPageController.text.trim()) ?? 1;
            Navigator.pop(
              context,
              _PhysicalBookDraft(
                title: _titleController.text.trim(),
                startPage: start < 1 ? 1 : start,
                totalPages: int.tryParse(_totalPagesController.text.trim()),
              ),
            );
          },
          child: const Text('Save changes'),
        ),
      ],
    );
  }
}

class _UpdateBookPageDialog extends StatefulWidget {
  final ReadingProgress book;

  const _UpdateBookPageDialog({required this.book});

  @override
  State<_UpdateBookPageDialog> createState() => _UpdateBookPageDialogState();
}

class _UpdateBookPageDialogState extends State<_UpdateBookPageDialog> {
  late final TextEditingController _pageController;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _pageController = TextEditingController(text: '${widget.book.currentPage}');
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, int.parse(_pageController.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final helper = book.startPage > 1 && book.totalPages != null
        ? 'Range: ${book.startPage} – ${book.totalPages}'
        : (book.startPage > 1
            ? 'Starts at page ${book.startPage}'
            : (book.totalPages == null
                ? null
                : 'Total: ${book.totalPages} pages'));

    return AlertDialog(
      title: const Text('Update reading progress'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _pageController,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Current page',
            helperText: helper,
          ),
          validator: (value) {
            final parsed = int.tryParse(value?.trim() ?? '');
            if (parsed == null || parsed < book.startPage) {
              return 'Enter a page number >= ${book.startPage}';
            }
            if (book.totalPages != null && parsed > book.totalPages!) {
              return 'Page cannot exceed ${book.totalPages}';
            }
            return null;
          },
          onFieldSubmitted: (_) => _save(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save page')),
      ],
    );
  }
}
