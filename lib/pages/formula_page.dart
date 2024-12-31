import 'package:flutter/material.dart';
import 'package:flutter_tex/flutter_tex.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/app_drawer.dart';
import '../services/formula_service.dart';
import 'package:provider/provider.dart';
import '../services/connectivity_service.dart';

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

  final List<String> _subjects = [
    'Mathematics',
    'Physics',
    'Chemistry',
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
        setState(() {
          _error = 'No internet connection. Please check your network.';
          _isLoading = false;
        });
        return;
      }

      final formulas = await formulaService.getFormulas(
        subject: _selectedSubject,
      );

      setState(() {
        _formulas = formulas;
        _isLoading = false;
      });
    } catch (e) {
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

      setState(() {
        _formulas = formulas;
        _isLoading = false;
      });
    } catch (e) {
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
            child: RefreshIndicator(
              onRefresh: _refreshFormulas,
              child: _buildFormulaList(),
            ),
          ),
        ],
      ),
    );
  }
}
