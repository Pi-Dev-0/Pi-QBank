import 'package:flutter/material.dart';
import '../../config/app_config.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../widgets/year_selector.dart';
import '../../widgets/question_paper_card.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/custom_app_bar.dart';
import '../../widgets/exam_year_selector.dart';
import '../../services/data_cache_service.dart';
import '../../widgets/connectivity_wrapper.dart';

class SevecCollegeMathematicsPage extends StatefulWidget {
  const SevecCollegeMathematicsPage({super.key});

  @override
  State<SevecCollegeMathematicsPage> createState() => _SevecCollegeMathematicsPageState();
}

class _SevecCollegeMathematicsPageState extends State<SevecCollegeMathematicsPage> {
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

  Future<void> fetchQuestionPapers() async {
    if (!mounted) return;

    setState(() {
      isLoading = true;
      hasError = false;
      errorMessage = '';
    });

    final scriptUrl = AppConfig.sevenCollegeMathApi;
    const String cacheKey = 'question_bank';

    try {
      final papers = await _cacheService.fetchData(
        scriptUrl,
        cacheKey,
        () async {
          final response = await http.get(Uri.parse(scriptUrl));

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

  bool matchesExamYear(dynamic paperExamYear, String selectedYear) {
    if (selectedYear.isEmpty || paperExamYear == null) return true;

    String examYearStr = paperExamYear.toString();
    final paperYears = examYearStr
        .split('-')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    return paperYears.contains(selectedYear);
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
      appBar: const CustomAppBar(title: '7 College'),
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
            child: isLoading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text(
                          'Loading Question Papers...',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  )
                : hasError
                    ? Center(
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
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : filteredPapers.isEmpty
                        ? const Center(
                            child: Text(
                              'No question papers found for selected filters',
                              style: TextStyle(fontSize: 16),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: filteredPapers.length,
                            itemBuilder: (context, index) {
                              final paper = filteredPapers[index];
                              final key = ValueKey('${paper['year']}_${paper['examyear']}_${paper['title']}');
                              return KeyedSubtree(
                                key: key,
                                child: QuestionPaperCard(
                                  key: ValueKey('${paper['year']}_${paper['examyear']}_${paper['title']}'),
                                  title: paper['title']?.toString() ?? '',
                                  subtitle: paper['subtitle']?.toString() ?? '',
                                  year: paper['year']?.toString() ?? '',
                                  examYear: paper['examyear']?.toString() ?? '',
                                  downloadUrl: paper['downloadurl']?.toString() ?? '',
                                  category: '7 College',
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
