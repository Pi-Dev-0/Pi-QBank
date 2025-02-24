import 'package:flutter/material.dart';
import '../config/app_config.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../widgets/app_drawer.dart';
import '../widgets/question_paper_card.dart';
import '../widgets/custom_app_bar.dart';
import '../services/data_cache_service.dart';
import '../widgets/exam_year_selector.dart';
import '../widgets/group_selector.dart';
import '../widgets/error_state_widget.dart';

class SevenCollegeAdmissionPage extends StatefulWidget {
  const SevenCollegeAdmissionPage({super.key});

  @override
  State<SevenCollegeAdmissionPage> createState() =>
      _SevenCollegeAdmissionPageState();
}

class _SevenCollegeAdmissionPageState extends State<SevenCollegeAdmissionPage> {
  List<Map<String, dynamic>> questionPapers = [];
  bool isLoading = true;
  bool hasError = false;
  String _selectedExamYear = '';
  String _selectedGroup = 'Science';
  final _cacheService = DataCacheService();

  final List<String> examYears = List.generate(
    DateTime.now().year - 2015 + 1,
    (index) => (DateTime.now().year - index).toString(),
  );

  final List<String> groups = ['Science', 'Arts', 'Commerce'];

  @override
  void initState() {
    super.initState();
    fetchQuestionPapers();
  }

  Future<void> fetchQuestionPapers() async {
    final scriptUrl = AppConfig.sevenCollegeAdmissionApi;
    const String cacheKey = 'seven_college_admission_papers';

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
                      'group': paper['Group'] ?? '',
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
      final yearMatch = _selectedExamYear.isEmpty ||
          paper['examYear'].toString() == _selectedExamYear;
      final groupMatch =
          _selectedGroup.isEmpty || paper['group'].toString() == _selectedGroup;
      return yearMatch && groupMatch;
    }).toList();

    return Scaffold(
      appBar: const CustomAppBar(title: '7 College Admission'),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          // Group Selection
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
            child: GroupSelector(
              selectedGroup: _selectedGroup,
              groups: groups,
              onGroupChanged: (value) =>
                  setState(() => _selectedGroup = value ?? ''),
            ),
          ),

          // Exam Year Selection
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 0.0),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8.0),
              child: ExamYearSelector(
                selectedYear: _selectedExamYear,
                examYears: examYears,
                onYearChanged: (value) =>
                    setState(() => _selectedExamYear = value ?? ''),
              ),
            ),
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
                                  '${paper['examYear']}_${paper['title']}_$_selectedGroup');
                              return KeyedSubtree(
                                key: key,
                                child: QuestionPaperCard(
                                  key: ValueKey(
                                      '${paper['examYear']}_${paper['title']}_$_selectedGroup'),
                                  title: paper['title']?.toString() ?? '',
                                  subtitle: paper['subtitle']?.toString() ?? '',
                                  year: paper['examYear']?.toString() ?? '',
                                  examYear: paper['examYear']?.toString() ?? '',
                                  downloadUrl:
                                      paper['downloadUrl']?.toString() ?? '',
                                  category: 'Seven College',
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
