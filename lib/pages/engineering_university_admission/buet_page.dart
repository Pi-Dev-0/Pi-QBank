import 'package:flutter/material.dart';
import '../../config/app_config.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../widgets/app_drawer.dart';
import '../../widgets/question_paper_card.dart';
import '../../widgets/custom_app_bar.dart';
import '../../services/data_cache_service.dart';
import '../../widgets/exam_year_selector.dart';

class BUETPage extends StatefulWidget {
  const BUETPage({super.key});

  @override
  State<BUETPage> createState() => _BUETPageState();
}

class _BUETPageState extends State<BUETPage> {
  List<Map<String, dynamic>> questionPapers = [];
  bool isLoading = true;
  bool hasError = false;
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
    final scriptUrl = AppConfig.engineeringUniversityAdmissionApi;
    const String cacheKey = 'buet_papers';

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
            final List<dynamic> data = json.decode(response.body);
            return data
                .where((paper) => paper['Title'] == 'BUET')
                .map((paper) => {
                      'title': paper['Title'],
                      'subtitle': paper['Subtitle'],
                      'examYear': paper['ExamYear']?.toString() ?? '',
                      'downloadUrl': paper['DownloadURL']?.toString() ?? '',
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
    final filteredPapers = questionPapers.where((paper) {
      return _selectedExamYear.isEmpty ||
          paper['examYear'].toString() == _selectedExamYear;
    }).toList()
      ..sort((a, b) => int.parse(b['examYear'].toString())
          .compareTo(int.parse(a['examYear'].toString())));

    return Scaffold(
      appBar: const CustomAppBar(title: 'BUET'),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          // Exam Year Selection
          ExamYearSelector(
            selectedYear: _selectedExamYear,
            examYears: examYears,
            onYearChanged: (value) =>
                setState(() => _selectedExamYear = value ?? ''),
          ),

          // Question Papers List
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
                            const Text('Failed to load question papers'),
                            ElevatedButton(
                              onPressed: fetchQuestionPapers,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : filteredPapers.isEmpty
                        ? const Center(child: Text('No question papers found'))
                        : ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: filteredPapers.length,
                            itemBuilder: (context, index) {
                              final paper = filteredPapers[index];
                              return QuestionPaperCard(
                                key: ValueKey(
                                    '${paper['examYear']}_${paper['title']}'),
                                title: paper['title']?.toString() ?? '',
                                subtitle: paper['subtitle']?.toString() ?? '',
                                year: paper['examYear']?.toString() ?? '',
                                examYear: paper['examYear']?.toString() ?? '',
                                downloadUrl:
                                    paper['downloadUrl']?.toString() ?? '',
                                category: 'Engineering',
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
