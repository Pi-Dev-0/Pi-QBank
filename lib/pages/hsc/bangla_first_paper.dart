import 'package:flutter/material.dart';
import '../../config/app_config.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../widgets/app_drawer.dart';
import '../../widgets/custom_app_bar.dart';
import '../../widgets/exam_year_selector.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/question_paper_card.dart';
import '../../services/data_cache_service.dart';

class HSCBanglaFirstPaper extends StatefulWidget {
  const HSCBanglaFirstPaper({super.key});

  @override
  State<HSCBanglaFirstPaper> createState() => _HSCBanglaFirstPaperState();
}

class _HSCBanglaFirstPaperState extends State<HSCBanglaFirstPaper> {
  String _selectedType = 'Board';
  String _selectedExamYear = '';
  List<Map<String, dynamic>> questionPapers = [];
  bool isLoading = true;
  bool hasError = false;
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
    final String scriptUrl = AppConfig.hscApi;
    const String cacheKey = 'hsc_bangla_first';

    try {
      if (mounted) {
        setState(() {
          isLoading = true;
          hasError = false;
        });
      }

      final papers = await _cacheService.fetchData(
        scriptUrl,
        cacheKey,
        () async {
          final response = await http.get(Uri.parse(scriptUrl));

          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            return (data['papers'] as List)
                .where((paper) => paper['subject'].toString() == 'Bangla1')
                .map((paper) => {
                      'title': paper['title'],
                      'subtitle': paper['subtitle'],
                      'examType': paper['examType'],
                      'examYear': paper['examYear'].toString(),
                      'downloadUrl': paper['downloadUrl'],
                    })
                .toList();
          }
          throw Exception('Failed to load papers');
        },
      );

      if (mounted) {
        setState(() {
          questionPapers = papers;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          hasError = true;
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: LoadingWidget(loadingText: 'Loading question papers...'),
      );
    }

    final filteredPapers = questionPapers.where((paper) {
      final typeMatch = paper['examType'].toString() == _selectedType;
      final yearMatch = _selectedExamYear.isEmpty ||
          paper['examYear'].toString() == _selectedExamYear;
      return typeMatch && yearMatch;
    }).toList()
      ..sort((a, b) => int.parse(b['examYear'].toString())
          .compareTo(int.parse(a['examYear'].toString())));

    return Scaffold(
      appBar: const CustomAppBar(title: 'বাংলা ১ম পত্র - HSC'),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          // Exam Type Selection
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: ['Board', 'Test'].map((type) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _selectedType == type
                            ? Theme.of(context).colorScheme.primary
                            : Colors.white,
                        foregroundColor: _selectedType == type
                            ? Colors.white
                            : Colors.black87,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () => setState(() => _selectedType = type),
                      child: Text(
                        type,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // Year Selection
          ExamYearSelector(
            selectedYear: _selectedExamYear,
            examYears: examYears,
            onYearChanged: (value) =>
                setState(() => _selectedExamYear = value ?? ''),
          ),

          // Question Papers List
          Expanded(
            child: hasError
                ? const Center(
                    child: Text('Failed to load question papers'),
                  )
                : filteredPapers.isEmpty
                    ? const Center(
                        child: Text('No question papers found'),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8.0, vertical: 2.0),
                        itemCount: filteredPapers.length,
                        itemBuilder: (context, index) {
                          final paper = filteredPapers[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2.0),
                            child: QuestionPaperCard(
                              key: ValueKey(
                                  '${paper['examYear']}_${paper['title']}_$_selectedType'),
                              title: paper['title'],
                              subtitle:
                                  '${paper['subtitle']} • ${paper['examYear']}',
                              year: 'HSC',
                              examYear: paper['examYear']?.toString() ?? '',
                              downloadUrl:
                                  paper['downloadUrl']?.toString() ?? '',
                              category: 'HSC Bangla 1st Paper',
                              index: index,
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
