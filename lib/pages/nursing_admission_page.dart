import 'package:flutter/material.dart';
import '../config/app_config.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../widgets/app_drawer.dart';
import '../widgets/question_paper_card.dart';
import 'dart:io';
import '../widgets/custom_app_bar.dart';
import '../services/data_cache_service.dart';
import '../widgets/connectivity_wrapper.dart';

class NursingAdmissionPage extends StatefulWidget {
  const NursingAdmissionPage({super.key});

  @override
  State<NursingAdmissionPage> createState() => _NursingAdmissionPageState();
}

class YearDropdown extends StatelessWidget {
  final String selectedYear;
  final List<String> examYears;
  final Function(String?) onYearChanged;

  const YearDropdown({
    super.key,
    required this.selectedYear,
    required this.examYears,
    required this.onYearChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: DropdownButtonFormField<String>(
        value: selectedYear.isEmpty ? null : selectedYear,
        hint: const Text('Select Year'),
        items: [
          const DropdownMenuItem<String>(
            value: '',
            child: Text('All Years'),
          ),
          ...examYears.map((year) => DropdownMenuItem<String>(
                value: year,
                child: Text(year),
              )),
        ],
        onChanged: onYearChanged,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),
    );
  }
}

class _NursingAdmissionPageState extends State<NursingAdmissionPage> {
  String _selectedType = 'Diploma';
  String _selectedExamYear = '';
  List<Map<String, dynamic>> questionPapers = [];
  bool isLoading = true;
  bool hasError = false;
  String errorMessage = '';
  final _cacheService = DataCacheService();

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
    final scriptUrl = AppConfig.nursingAdmissionApi;
    const String cacheKey = 'nursing_admission';

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
      // Case-insensitive type matching
      final paperType = paper['type']?.toString().toLowerCase() ?? '';
      final selectedType = _selectedType.toLowerCase();
      final typeMatch = paperType == selectedType;
      
      // Match examyear
      final examYearMatch = _selectedExamYear.isEmpty || 
                           paper['examYear']?.toString() == _selectedExamYear;
      
      return typeMatch && examYearMatch;
    }).toList()
      ..sort((a, b) => int.parse(b['examYear'].toString())
          .compareTo(int.parse(a['examYear'].toString())));

    return Scaffold(
      appBar: const CustomAppBar(title: 'Nursing Admission'),
      drawer: const AppDrawer(),
      body: Column(
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
          Container(
            width: MediaQuery.of(context).size.width * 0.6,
            height: 35,
            margin: const EdgeInsets.only(left: 8, right: 8, bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                  spreadRadius: 0,
                ),
                BoxShadow(
                  color: Colors.grey.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                  spreadRadius: 2,
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                  spreadRadius: -1,
                ),
              ],
            ),
            child: InkWell(
              onTap: () {
                showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      title: const Center(
                        child: Text('Select Year'),
                      ),
                      content: SizedBox(
                        width: double.minPositive,
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: examYears.length + 1,
                          itemBuilder: (BuildContext context, int index) {
                            if (index == 0) {
                              return ListTile(
                                title: const Center(
                                  child: Text(
                                    'All Years',
                                    style: TextStyle(fontSize: 16),
                                  ),
                                ),
                                onTap: () {
                                  setState(() => _selectedExamYear = '');
                                  Navigator.pop(context);
                                },
                              );
                            }
                            final year = examYears[index - 1];
                            return ListTile(
                              title: Center(
                                child: Text(
                                  year,
                                  style: const TextStyle(fontSize: 16),
                                ),
                              ),
                              onTap: () {
                                setState(() => _selectedExamYear = year);
                                Navigator.pop(context);
                              },
                            );
                          },
                        ),
                      ),
                    );
                  },
                );
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Year: ',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Expanded(
                    child: Text(
                      _selectedExamYear.isEmpty
                          ? 'All Years'
                          : _selectedExamYear,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, size: 20),
                ],
              ),
            ),
          ),
          Expanded(
            child: isLoading
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
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
                              'No question papers found',
                              style: TextStyle(fontSize: 16),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: filteredPapers.length,
                            itemBuilder: (context, index) {
                              final paper = filteredPapers[index];
                              final key = ValueKey('${paper['type']}_${paper['examYear']}_${paper['title']}');
                              return KeyedSubtree(
                                key: key,
                                child: QuestionPaperCard(
                                  key: ValueKey('${paper['type']}_${paper['examYear']}_${paper['title']}'),
                                  title: paper['title']?.toString() ?? '',
                                  subtitle: paper['subtitle']?.toString() ?? '',
                                  year: '',
                                  examYear: paper['examYear']?.toString() ?? '',
                                  downloadUrl: paper['downloadUrl']?.toString() ?? '',
                                  category: 'Nursing Admission',
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
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
}
