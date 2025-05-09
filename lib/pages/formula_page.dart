import 'package:flutter/material.dart';
import 'package:flutter_tex/flutter_tex.dart';
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

  final List<String> _subjects = [
    'Mathematics',
    'Physics',
    'Chemistry',
  ];

  final List<Map<String, String>> _mathCategories = [
    {'title': 'পাটিগণিত (Arithmetic)', 'key': 'Arithmetic'},
    {'title': 'বীজগণিত (Algebra)', 'key': 'Algebra'},
    {'title': 'সূচক (Index)', 'key': 'Index'},
    {'title': 'লগারিদম (Logarithm)', 'key': 'Logarithm'},
    {'title': 'ধারা (Series)', 'key': 'Series'},
    {'title': 'ত্রিকোণমিতি (Trigonometry)', 'key': 'Trigonometry'},
    {'title': 'পরিমিতি (Measurement)', 'key': 'Measurement'},
    {'title': 'জ্যামিতি (Geometry)', 'key': 'Geometry'},
    {'title': 'পরিসংখ্যান (Statistics)', 'key': 'Statistics'},
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
        if (!mounted) return; // Ensure widget is still mounted
        setState(() {
          _error = 'No internet connection. Please check your network.';
          _isLoading = false;
        });
        return;
      }

      if (_selectedSubject == 'Mathematics') {
        final formulas =
            await formulaService.getFormulas(subject: _selectedSubject);
        if (!mounted) return; // Ensure widget is still mounted
        setState(() {
          _formulas = formulas.where((formula) {
            return _mathCategories
                .any((category) => category['key'] == formula.title);
          }).toList();
          _isLoading = false;
        });
      } else {
        final formulas =
            await formulaService.getFormulas(subject: _selectedSubject);
        if (!mounted) return; // Ensure widget is still mounted
        setState(() {
          _formulas = formulas;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return; // Ensure widget is still mounted
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
        if (!mounted) return; // Ensure widget is still mounted
        setState(() {
          _error = 'No internet connection. Please check your network.';
          _isLoading = false;
        });
        return;
      }

      await formulaService.clearCache();
      final formulas = await formulaService.getFormulas(
        subject: _selectedSubject,
      );
      if (!mounted) return; // Ensure widget is still mounted
      setState(() {
        _formulas = formulas;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return; // Ensure widget is still mounted
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
    _fetchFormulas();
  }

  Map<String, List<Formula>> _groupFormulas() {
    final Map<String, List<Formula>> grouped = {};
    for (var formula in _formulas) {
      if (!grouped.containsKey(formula.title)) {
        grouped[formula.title] = [];
      }
      grouped[formula.title]!.add(formula);
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

  Widget _buildFormulaCard(Map<String, String> category) {
    final title = category['title']!;
    final key = category['key']!;
    final formula = _formulas.firstWhere(
      (f) => f.title == key,
      orElse: () => Formula(
        id: '',
        title: key,
        formula: '',
        subject: _selectedSubject,
      ),
    );

    return FutureBuilder<bool>(
      future: _isFormulaDownloaded(title),
      builder: (context, snapshot) {
        final isDownloaded = snapshot.data ?? false;
        final progress = _downloadProgress[title] ?? 0.0;

        return Card(
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
                      valueColor: AlwaysStoppedAnimation(
                        Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                if (progress > 0 && progress < 1)
                  Text(
                    '${(progress * 100).toInt()}%',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                if (progress == 0 || progress == 1)
                  Icon(
                    isDownloaded
                        ? Icons.check_circle
                        : (formula.formula.startsWith('http')
                            ? Icons.picture_as_pdf
                            : Icons.functions),
                    size: 32,
                    color: isDownloaded
                        ? Colors.green
                        : Theme.of(context).colorScheme.primary,
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
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isDownloaded)
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          title: Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded,
                                  color: Colors.red, size: 32),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Delete Formula',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 20,
                                    color: Colors.red,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: 8),
                              Text(
                                'Are you sure you want to delete this formula?',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[900],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 18),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.info_outline,
                                        color: Colors.red, size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'This will remove the downloaded PDF from your device.',
                                        style: TextStyle(
                                          color: Colors.red[700],
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          actionsPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.grey[700],
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 18, vertical: 10),
                                textStyle: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 22, vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                elevation: 2,
                              ),
                              icon: const Icon(Icons.delete_forever),
                              label: const Text('Delete'),
                              onPressed: () async {
                                Navigator.pop(context);
                                await _deleteFormula(title);
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                Icon(
                  isDownloaded ? Icons.download_done : Icons.arrow_forward_ios,
                  size: 16,
                  color: isDownloaded ? Colors.green : Colors.grey,
                ),
              ],
            ),
            onTap: () async {
              if (isDownloaded) {
                final directory = await getApplicationDocumentsDirectory();
                final filePath =
                    '${directory.path}/${title.replaceAll(' ', '_')}.pdf';
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PDFViewerPage(
                      filePath: filePath,
                      title: title,
                    ),
                  ),
                );
              } else {
                // Show popup with options
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    title: Row(
                      children: [
                        Icon(
                          Icons.book,
                          color: Theme.of(context).colorScheme.primary,
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
                                backgroundColor:
                                    Theme.of(context).colorScheme.primary,
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
                                Navigator.pop(context);
                                if (formula.formula.startsWith('http')) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => OnlinePDFViewerPage(
                                        pdfUrl: formula.formula,
                                        title: title,
                                      ),
                                    ),
                                  );
                                } else {
                                  _showLatexDialog(formula.formula, title);
                                }
                              },
                            ),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.download),
                              label: const Text('Download'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor:
                                    Theme.of(context).colorScheme.primary,
                                side: BorderSide(
                                  color: Theme.of(context).colorScheme.primary,
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
                                Navigator.pop(context);
                                if (formula.formula.startsWith('http')) {
                                  await _downloadFormula(
                                      formula.formula, title);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          'This formula is not downloadable.'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }
            },
          ),
        );
      },
    );
  }

  Widget _buildSubjectSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      decoration: const BoxDecoration(
        color: Colors.white,
      ),
      child: Row(
        children: _subjects.map((subject) {
          final isSelected = _selectedSubject == subject;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.white,
                    foregroundColor: isSelected ? Colors.white : Colors.black,
                    elevation: isSelected ? 8 : 2,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey.shade300,
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
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildFormulaList() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Loading Formulas...',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
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

    if (_selectedSubject == 'Mathematics') {
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _mathCategories.length,
        itemBuilder: (context, index) {
          final category = _mathCategories[index];
          return _buildFormulaCard(category);
        },
      );
    }

    final groupedFormulas = _groupFormulas();
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = screenWidth * 0.92;

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: groupedFormulas.length,
      itemBuilder: (context, index) {
        final title = groupedFormulas.keys.elementAt(index);
        final formulas = groupedFormulas[title]!;
        return Container(
          margin: const EdgeInsets.only(bottom: 20),
          child: Material(
            elevation: 6,
            shadowColor: Colors.grey,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: cardWidth,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.grey.shade100,
                  width: 1,
                ),
              ),
              child: Theme(
                data: Theme.of(context).copyWith(
                  dividerColor: Colors.transparent,
                ),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.functions,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                  children: formulas.map((formula) {
                    return Container(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (formula.subtitle != null &&
                              formula.subtitle!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                formula.subtitle!,
                                style: TextStyle(
                                  fontSize: 16,
                                  color:
                                      Theme.of(context).colorScheme.secondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          if (formula.description != null &&
                              formula.description!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                formula.description!,
                                style: const TextStyle(
                                  fontSize: 15,
                                  color: Colors.black87,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.grey.shade200,
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.grey.withOpacity(0.05),
                                  spreadRadius: 1,
                                  blurRadius: 5,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(16),
                            child: TeXView(
                              child: TeXViewDocument(
                                _wrapLatex(formula.formula),
                                style: TeXViewStyle.fromCSS(
                                  'padding: 0; color: #2D3748; font-size: 1.1em;',
                                ),
                              ),
                              style: const TeXViewStyle(
                                margin: TeXViewMargin.all(0),
                                padding: TeXViewPadding.all(0),
                                backgroundColor: Colors.transparent,
                              ),
                              renderingEngine:
                                  const TeXViewRenderingEngine.katex(),
                              loadingWidgetBuilder: (context) => const Center(
                                child: SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _downloadFormula(String url, String title) async {
    final directory = await getApplicationDocumentsDirectory();
    if (!mounted) return; // Ensure widget is still mounted
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
            if (!mounted) return; // Ensure widget is still mounted
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
            if (!mounted) return; // Ensure widget is still mounted
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
        if (!mounted) return; // Ensure widget is still mounted
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
      if (!mounted) return; // Ensure widget is still mounted
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('An error occurred while downloading the formula.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showLatexDialog(String latex, String title) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: TeXView(
            child: TeXViewDocument(
              latex,
              style: TeXViewStyle.fromCSS(
                'padding: 0; color: #2D3748; font-size: 1.1em;',
              ),
            ),
            style: const TeXViewStyle(
              margin: TeXViewMargin.all(0),
              padding: TeXViewPadding.all(0),
              backgroundColor: Colors.transparent,
            ),
            renderingEngine: const TeXViewRenderingEngine.katex(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _wrapLatex(String formula) {
    if (!formula.contains(r'\[') && !formula.contains(r'\(')) {
      formula = r'\[' + formula + r'\]';
    }
    return formula;
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
      backgroundColor: Colors.grey.shade50,
      body: Column(
        children: [
          _buildSubjectSelector(),
          Expanded(
            child: _buildFormulaList(),
          ),
        ],
      ),
    );
  }
}
