import 'package:flutter/material.dart';
import '../config/app_config.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../widgets/app_drawer.dart';
import '../widgets/question_paper_card.dart';
import '../widgets/custom_app_bar.dart';
import '../services/data_cache_service.dart';
import '../widgets/loading_widget.dart';
import '../widgets/exam_year_selector.dart';
import '../widgets/error_state_widget.dart';

class MedicalPage extends StatefulWidget {
  const MedicalPage({super.key});

  @override
  State<MedicalPage> createState() => _MedicalPageState();
}

class _MedicalPageState extends State<MedicalPage> {
  List<Map<String, dynamic>> questionPapers = [];
  bool isLoading = true;
  bool hasError = false;
  String _selectedExamYear = '';
  final List<String> examYears = List.generate(
    DateTime.now().year - 2015 + 1,
    (index) => (DateTime.now().year - index).toString(),
  );
  final _cacheService = DataCacheService();

  @override
  void initState() {
    super.initState();
    fetchQuestionPapers();
  }

  Future<void> fetchQuestionPapers() async {
    final scriptUrl = AppConfig.medicalApi;
    const String cacheKey = 'medical_papers';

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
                .map((paper) => {
                      'title': paper['Title'] ?? '',
                      'subtitle': paper['Subtitle'] ?? '',
                      'examYear': paper['ExamYear'] ?? '',
                      'downloadUrl': paper['DownloadURL'] ?? '#',
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

    if (isLoading) {
      return const Scaffold(
        body: LoadingWidget(loadingText: 'Loading Papers...'),
      );
    }

    return Scaffold(
      appBar: const CustomAppBar(title: 'Medical Admission'),
      drawer: const AppDrawer(),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.blue.shade50,
              Colors.purple.shade50,
            ],
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: ExamYearSelector(
                selectedYear: _selectedExamYear,
                examYears: examYears,
                onYearChanged: (value) =>
                    setState(() => _selectedExamYear = value ?? ''),
              ),
            ),

            // Question Papers List
            Expanded(
              child: hasError
                  ? ErrorStateWidget(
                      onRetry: fetchQuestionPapers,
                    )
                  : filteredPapers.isEmpty
                      ? const Center(child: Text('No question papers found'))
                      : ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: filteredPapers.length,
                          itemBuilder: (context, index) {
                            final paper = filteredPapers[index];
                            final key = ValueKey(
                                '${paper['examYear']}_${paper['title']}');
                            return KeyedSubtree(
                              key: key,
                              child: QuestionPaperCard(
                                key: ValueKey(
                                    '${paper['examYear']}_${paper['title']}'),
                                title: paper['title']?.toString() ?? '',
                                subtitle: paper['subtitle']?.toString() ?? '',
                                year: paper['examYear']?.toString() ?? '',
                                examYear: paper['examYear']?.toString() ?? '',
                                downloadUrl:
                                    paper['downloadUrl']?.toString() ?? '',
                                category: 'Medical',
                                index: index,
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
