import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../widgets/year_selector.dart';
import '../../../widgets/question_paper_card.dart';
import '../../../widgets/app_drawer.dart';
import '../../../widgets/custom_app_bar.dart';
import '../../../widgets/exam_year_selector.dart';
import '../../../services/data_cache_service.dart';
import '../../../widgets/connectivity_wrapper.dart';

abstract class NuQuestionPage extends StatefulWidget {
  final String title;
  final String apiUrl;

  const NuQuestionPage({
    super.key,
    required this.title,
    required this.apiUrl,
  });
}

abstract class NuQuestionPageState<T extends NuQuestionPage> extends State<T> {
  List<Map<String, dynamic>> questionPapers = [];
  bool isLoading = true;
  bool hasError = false;
  String errorMessage = '';
  int _selectedYear = 1;
  String _selectedExamYear = '';
  final _cacheService = DataCacheService();

  final List<String> examYears = List.generate(
    DateTime.now().year - 2015 + 1,
    (index) => (DateTime.now().year - index).toString(),
  );

  @override
  void initState() {
    super.initState();
    fetchQuestionPapers();
  }

  // Common methods
  Future<void> fetchQuestionPapers() async {
    if (!mounted) return;

    setState(() {
      isLoading = true;
      hasError = false;
      errorMessage = '';
    });

    try {
      final papers = await _cacheService.fetchData(
        widget.apiUrl,
        'question_bank_${widget.title.toLowerCase()}',
        () async {
          final response = await http.get(Uri.parse(widget.apiUrl));
          if (response.statusCode == 200) {
            final List<dynamic> data = json.decode(response.body);
            return data.map((item) => Map<String, dynamic>.from(item)).toList();
          }
          throw Exception('Failed to load data');
        },
      );

      if (!mounted) return;
      setState(() {
        questionPapers = papers
            .where((paper) =>
                paper['title']?.toString().isNotEmpty == true &&
                paper['year']?.toString().isNotEmpty == true)
            .toList();
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        hasError = true;
        errorMessage = 'Failed to load data. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredPapers = questionPapers.where((paper) {
      final yearMatch = paper['year']?.toString() == _selectedYear.toString();
      final examYearMatch = _selectedExamYear.isEmpty ||
          paper['examyear']?.toString() == _selectedExamYear;
      return yearMatch && examYearMatch;
    }).toList()
      ..sort((a, b) => int.parse(b['examyear'].toString())
          .compareTo(int.parse(a['examyear'].toString())));

    return Scaffold(
      appBar: CustomAppBar(title: widget.title),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          YearSelector(
            selectedYear: _selectedYear,
            onYearSelected: (year) => setState(() => _selectedYear = year),
          ),
          ExamYearSelector(
            selectedYear: _selectedExamYear,
            examYears: examYears,
            onYearChanged: (value) =>
                setState(() => _selectedExamYear = value ?? ''),
          ),
          Expanded(
            child: _buildContent(filteredPapers),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(List<Map<String, dynamic>> filteredPapers) {
    if (isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Loading Question Papers...',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    if (hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              errorMessage,
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                ConnectivityWrapper.showOnRetry(context);
                fetchQuestionPapers();
              },
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 3,
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor:
                    Colors.white, // Add this line to ensure text is visible
              ),
              child: const Text(
                'Retry',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (filteredPapers.isEmpty) {
      return const Center(
        child: Text(
          'No question papers found for selected filters',
          style: TextStyle(fontSize: 16),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: filteredPapers.length,
      itemBuilder: (context, index) {
        final paper = filteredPapers[index];
        return QuestionPaperCard(
          key: ValueKey(
              '${paper['year']}_${paper['examyear']}_${paper['title']}'),
          title: paper['title']?.toString() ?? '',
          subtitle: paper['subtitle']?.toString() ?? '',
          year: paper['year']?.toString() ?? '',
          examYear: paper['examyear']?.toString() ?? '',
          downloadUrl: paper['downloadurl']?.toString() ?? '',
          category: widget.title,
        );
      },
    );
  }
}
