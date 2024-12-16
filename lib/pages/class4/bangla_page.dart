import 'package:flutter/material.dart';
import '../../config/app_config.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../widgets/app_drawer.dart';
import '../../widgets/question_paper_card.dart';
import '../../widgets/custom_app_bar.dart';
import '../../widgets/exam_year_selector.dart';
import '../../services/data_cache_service.dart';
import '../../widgets/connectivity_wrapper.dart';

class Class4BanglaPage extends StatefulWidget {
  const Class4BanglaPage({super.key});

  @override
  State<Class4BanglaPage> createState() => _Class4BanglaPageState();
}

class _Class4BanglaPageState extends State<Class4BanglaPage> {
  String _selectedType = 'Half Yearly';
  String _selectedExamYear = '';
  List<Map<String, dynamic>> questionPapers = [];
  bool isLoading = true;
  bool hasError = false;

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
    final String scriptUrl = AppConfig.class4Api;
    const String cacheKey = 'class4_bangla';

    try {
      final papers = await _cacheService.fetchData(
        scriptUrl,
        cacheKey,
        () async {
          final response = await http.get(Uri.parse(scriptUrl));
          
          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            return (data['papers'] as List)
                .where((paper) => 
                    paper['subject'].toString().toLowerCase() == 'bangla')
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
    final filteredPapers = questionPapers.where((paper) {
      final typeMatch = paper['examType'].toString() == _selectedType;
      final yearMatch = _selectedExamYear.isEmpty ||
          paper['examYear'].toString() == _selectedExamYear;
      return typeMatch && yearMatch;
    }).toList()
      ..sort((a, b) => int.parse(b['examYear'].toString())
          .compareTo(int.parse(a['examYear'].toString())));

    return Scaffold(
      appBar: const CustomAppBar(title: 'বাংলা - Class 4'),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          // Exam Type Selection
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: ['Half Yearly', 'Annual'].map((type) {
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

          // Year Selection using ExamYearSelector widget
          ExamYearSelector(
            selectedYear: _selectedExamYear,
            examYears: examYears,
            onYearChanged: (value) =>
                setState(() => _selectedExamYear = value ?? ''),
          ),

          // Question Papers List
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : hasError
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('Failed to load question papers'),
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
                        ? const Center(child: Text('No question papers found'))
                        : ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: filteredPapers.length,
                            itemBuilder: (context, index) {
                              final paper = filteredPapers[index];
                              return QuestionPaperCard(
                                key: ValueKey('${paper['examYear']}_${paper['title']}_$_selectedType'),
                                title: '${paper['title']} ($_selectedType) (${paper['examYear']?.toString() ?? ''})',
                                subtitle: paper['subtitle']?.toString() ?? '',
                                year: '4',
                                examYear: paper['examYear']?.toString() ?? '',
                                downloadUrl: paper['downloadUrl']?.toString() ?? '',
                                category: 'Class 4 Bangla',
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
