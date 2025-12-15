import 'package:flutter/material.dart';
import '../config/app_config.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../widgets/app_drawer.dart';
import '../widgets/question_paper_card.dart';
import 'dart:io';
import '../widgets/custom_app_bar.dart';
import '../services/data_cache_service.dart';
import '../widgets/exam_year_selector.dart';
import '../widgets/error_state_widget.dart';

class NursingPage extends StatefulWidget {
  const NursingPage({super.key});

  @override
  State<NursingPage> createState() => _NursingPageState();
}

class _NursingPageState extends State<NursingPage> {
  String _selectedType = 'Diploma';
  int _selectedYear = 1;
  String _selectedExamYear = '';
  List<Map<String, dynamic>> questionPapers = [];
  bool isLoading = true;
  bool hasError = false;
  String errorMessage = '';
  final _cacheService = DataCacheService();

  // Color palette for cards
  final List<Color> _cardColors = const [
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

  List<String> get examYears {
    final currentYear = DateTime.now().year;
    final startYear = 2015; // Your starting year
    return List.generate(
      currentYear - startYear + 1,
      (index) => (currentYear - index).toString(),
    );
  }

  @override
  void initState() {
    super.initState();
    fetchQuestionPapers();
  }

  Future<bool> checkInternetConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    }
  }

  void showNoInternetDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('No Internet Connection'),
          content: const Text(
            'Please check your internet connection and try again.',
            style: TextStyle(fontSize: 16),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Retry'),
              onPressed: () {
                Navigator.of(context).pop();
                fetchQuestionPapers();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> fetchQuestionPapers() async {
    final scriptUrl = AppConfig.nursingApi;
    const String cacheKey = 'nursing_papers';

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
                      'title': paper['title'],
                      'subtitle': paper['subtitle'],
                      'type': paper['type'],
                      'examYear': paper['examyear']?.toString() ??
                          paper['year']?.toString() ??
                          '',
                      'year': paper['year']?.toString() ?? '',
                      'downloadUrl': paper['downloadurl']?.toString() ?? '',
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
      final paperType = paper['type']?.toString().toLowerCase() ?? '';
      final selectedType = _selectedType.toLowerCase();
      final typeMatch = paperType == selectedType;

      final paperYear = paper['year']?.toString() ?? '';
      final yearMatch = paperYear == _selectedYear.toString();

      final examYear =
          paper['examyear']?.toString() ?? paper['examYear']?.toString() ?? '';
      final examYearMatch =
          _selectedExamYear.isEmpty || examYear == _selectedExamYear;

      return typeMatch && yearMatch && examYearMatch;
    }).toList()
      ..sort((a, b) => int.parse(b['examYear'].toString())
          .compareTo(int.parse(a['examYear'].toString())));

    return Scaffold(
      appBar: const CustomAppBar(title: 'Nursing'),
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
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: ['Diploma', 'BSC'].map((type) {
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
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          elevation: 8,
                          shadowColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () => setState(() => _selectedType = type),
                        child: Text(
                          type,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: List.generate(4, (index) {
                  final year = index + 1;
                  final suffix = switch (year) {
                    1 => 'st',
                    2 => 'nd',
                    3 => 'rd',
                    _ => 'th',
                  };
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _selectedYear == year
                              ? Theme.of(context).colorScheme.primary
                              : Colors.white,
                          foregroundColor: _selectedYear == year
                              ? Colors.white
                              : Colors.black87,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          elevation: 8,
                          shadowColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () => setState(() => _selectedYear = year),
                        child: Text(
                          '$year$suffix',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 8),
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
                      ? ErrorStateWidget(
                          onRetry: fetchQuestionPapers,
                        )
                      : filteredPapers.isEmpty
                          ? const Center(
                              child: Text('No question papers found'))
                          : ListView.builder(
                              padding: const EdgeInsets.all(8),
                              itemCount: filteredPapers.length,
                              itemBuilder: (context, index) {
                                final paper = filteredPapers[index];
                                final color =
                                    _cardColors[index % _cardColors.length];

                                return Theme(
                                  data: Theme.of(context).copyWith(
                                    primaryColor: color,
                                    colorScheme: ColorScheme.fromSeed(
                                      seedColor: color,
                                      primary: color,
                                    ),
                                  ),
                                  child: QuestionPaperCard(
                                    key: ValueKey(
                                        '${paper['examYear']}_${paper['title']}'),
                                    title: paper['title']?.toString() ?? '',
                                    subtitle:
                                        paper['subtitle']?.toString() ?? '',
                                    year: paper['examYear']?.toString() ?? '',
                                    examYear:
                                        paper['examYear']?.toString() ?? '',
                                    downloadUrl:
                                        paper['downloadUrl']?.toString() ?? '',
                                    category: 'Nursing',
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
