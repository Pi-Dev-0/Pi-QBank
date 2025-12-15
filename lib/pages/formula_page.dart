import 'package:flutter/material.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/app_drawer.dart';
import '../services/formula_service.dart';
import 'package:provider/provider.dart';
import '../services/connectivity_service.dart';
import 'online_pdf_viewer_page.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../pages/pdf_viewer_page.dart';
import '../widgets/delete_confirmation_dialog.dart';
import '../widgets/loading_widget.dart';

class FormulaPage extends StatefulWidget {
  const FormulaPage({super.key});

  @override
  State<FormulaPage> createState() => _FormulaPageState();
}

class _FormulaPageState extends State<FormulaPage> {
  String _selectedSubject = 'Mathematics';
  late Future<FormulaService> _formulaServiceFuture;
  List<Formula> _formulas = [];
  bool _isLoading = true;
  String? _error;
  final Map<String, double> _downloadProgress = {};

  List<String> _subjects = []; // Will be populated from API

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
    _formulaServiceFuture = FormulaService.create();
    _fetchFormulas();
  }

  Future<void> _fetchFormulas() async {
    final connectivityService =
        Provider.of<ConnectivityService>(context, listen: false);

    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final formulaService = await _formulaServiceFuture;
      await connectivityService.initConnectivity();

      if (!connectivityService.isOnline) {
        if (!mounted) return;
        setState(() {
          _error = 'No internet connection. Please check your network.';
          _isLoading = false;
        });
        return;
      }

      final formulas = await formulaService.getFormulas();
      if (!mounted) return;

      // Dynamically get all unique subjects from formulas
      final subjects = formulas.map((f) => f.subject.trim()).toSet().toList();
      subjects.sort();

      setState(() {
        _formulas = formulas;
        _subjects = subjects;
        // If the current selected subject is not in the new list, reset it
        if (!_subjects.contains(_selectedSubject) && _subjects.isNotEmpty) {
          _selectedSubject = _subjects.first;
        }
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load formulas. Please try again later.';
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshFormulas() async {
    final connectivityService =
        Provider.of<ConnectivityService>(context, listen: false);

    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final formulaService = await _formulaServiceFuture;
      await connectivityService.initConnectivity();

      if (!connectivityService.isOnline) {
        if (!mounted) return;
        setState(() {
          _error = 'No internet connection. Please check your network.';
          _isLoading = false;
        });
        return;
      }

      await formulaService.clearCache();
      await _fetchFormulas();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to refresh formulas. Please try again later.';
        _isLoading = false;
      });
    }
  }

  void _onSubjectChanged(String subject) {
    setState(() {
      _selectedSubject = subject;
    });
  }

  // Group formulas by title for the selected subject
  Map<String, List<Formula>> _groupFormulasByTitle() {
    final Map<String, List<Formula>> grouped = {};
    for (var formula
        in _formulas.where((f) => f.subject.trim() == _selectedSubject)) {
      final title = formula.title.trim();
      if (!grouped.containsKey(title)) {
        grouped[title] = [];
      }
      grouped[title]!.add(formula);
    }
    return grouped;
  }

  Future<bool> _isFormulaDownloaded(String title) async {
    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/${title.replaceAll(' ', '_')}.pdf';
    final file = File(filePath);
    return file.exists();
  }

  Future<void> _deleteFormula(String title) async {
    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/${title.replaceAll(' ', '_')}.pdf';
    final file = File(filePath);

    if (await file.exists()) {
      await file.delete();
      if (!mounted) return; // Ensure widget is still mounted
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Formula deleted successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      setState(() {}); // Refresh UI
    } else {
      if (!mounted) return; // Ensure widget is still mounted
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Formula not found.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildFormulaCard(String title, List<Formula> formulas, int index) {
    // Use the first formula for download/view (assuming one per title)
    final formula = formulas.first;
    final subtitle = formula.subtitle ?? '';
    final color = _cardColors[index % _cardColors.length];

    return FutureBuilder<bool>(
      future: _isFormulaDownloaded(title),
      builder: (context, snapshot) {
        final isDownloaded = snapshot.data ?? false;
        final progress = _downloadProgress[title] ?? 0.0;

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
                            : (formula.formula.startsWith('http')
                                ? Icons.picture_as_pdf
                                : Icons.functions),
                        size: 24,
                        color: isDownloaded ? Colors.green : color,
                      ),
                    ),
                ],
              ),
              title: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              subtitle: subtitle.isNotEmpty ? Text(subtitle) : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isDownloaded)
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () async {
                        final shouldDelete = await showDeleteConfirmationDialog(
                          context: context,
                          title: 'Delete Formula',
                          message:
                              'Are you sure you want to delete this formula?',
                          paperTitle: title,
                          paperSubtitle: null,
                        );
                        if (shouldDelete == true) {
                          await _deleteFormula(title);
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
                      '${directory.path}/${title.replaceAll(' ', '_')}.pdf';
                  if (!context.mounted) return;
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => PDFViewerPage(
                        filePath: filePath,
                        title: title,
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
                                title,
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
                              'Choose an option to view or download this formula.',
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
                    if (formula.formula.startsWith('http')) {
                      Navigator.push(
                        parentContext,
                        MaterialPageRoute(
                          builder: (context) => OnlinePDFViewerPage(
                            pdfUrl: formula.formula,
                            title: title,
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
                    if (formula.formula.startsWith('http')) {
                      await _downloadFormula(formula.formula, title, context);
                    } else {
                      ScaffoldMessenger.of(parentContext).showSnackBar(
                        const SnackBar(
                          content: Text('This formula is not downloadable.'),
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

  Widget _buildSubjectSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.8),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _subjects.map((subject) {
            final isSelected = _selectedSubject == subject;
            return Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey.shade100,
                    foregroundColor: isSelected ? Colors.white : Colors.black87,
                    elevation: isSelected ? 4 : 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                      side: BorderSide(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                        width: 1,
                      ),
                    ),
                  ),
                  onPressed: () => _onSubjectChanged(subject),
                  child: Text(
                    subject,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildFormulaList() {
    if (_isLoading) {
      return const Center(
        child: LoadingWidget(loadingText: 'Loading Formulas...'),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.signal_wifi_off,
                size: 60,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Internet Connection',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please connect to the internet to continue.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
              ),
              onPressed: _refreshFormulas,
              child: const Text(
                'Retry',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final groupedFormulas = _groupFormulasByTitle();
    if (groupedFormulas.isEmpty) {
      return const Center(child: Text('No formulas found.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: groupedFormulas.length,
      itemBuilder: (context, index) {
        final title = groupedFormulas.keys.elementAt(index);
        final formulas = groupedFormulas[title]!;
        return _buildFormulaCard(title, formulas, index);
      },
    );
  }

  Future<void> _downloadFormula(
      String url, String title, BuildContext context) async {
    final directory = await getApplicationDocumentsDirectory();
    if (!context.mounted) return; // Ensure widget is still mounted
    final filePath = '${directory.path}/${title.replaceAll(' ', '_')}.pdf';
    final file = File(filePath);

    try {
      setState(() {
        _downloadProgress[title] = 0.0; // Initialize progress
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
              _downloadProgress.remove(title); // Remove progress tracking
            });
            if (!context.mounted) return; // Ensure widget is still mounted
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Formula downloaded successfully!'),
                backgroundColor: Colors.green,
              ),
            );
          },
          onError: (_) {
            setState(() {
              _downloadProgress.remove(title); // Remove progress tracking
            });
            if (!context.mounted) return; // Ensure widget is still mounted
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to download the formula.'),
                backgroundColor: Colors.red,
              ),
            );
          },
          cancelOnError: true,
        );
      } else {
        setState(() {
          _downloadProgress.remove(title); // Remove progress tracking
        });
        if (!context.mounted) return; // Ensure widget is still mounted
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to download the formula.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _downloadProgress.remove(title); // Remove progress tracking
      });
      if (!context.mounted) return; // Ensure widget is still mounted
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('An error occurred while downloading the formula.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Formulas',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshFormulas,
          ),
        ],
      ),
      drawer: const AppDrawer(),
      backgroundColor: Colors.white,
      body: ClipRRect(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(30),
        ),
        child: Container(
          color: Colors.white,
          child: Container(
            color: Colors.white,
            child: Column(
              children: [
                _buildSubjectSelector(),
                Expanded(
                  child: _buildFormulaList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
