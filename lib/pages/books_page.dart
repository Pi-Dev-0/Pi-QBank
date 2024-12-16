import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../widgets/app_drawer.dart';
import '../widgets/question_paper_card.dart';
import '../widgets/custom_app_bar.dart';
import '../config/app_config.dart';
import '../services/connectivity_service.dart';
import '../widgets/connectivity_wrapper.dart';
import 'dart:io';

class BooksPage extends StatefulWidget {
  const BooksPage({super.key});

  @override
  State<BooksPage> createState() => _BooksPageState();
}

class _BooksPageState extends State<BooksPage> {
  String? selectedClass;
  List<Map<String, dynamic>> subjects = [];
  bool _isLoading = true;
  bool _showConnectivityWrapper = false;

  Map<String, List<Map<String, dynamic>>> classSubjects = {};

  Future<bool> _checkIfFileExists(String title, String classItem) async {
    // Sanitize title and class for file naming
    final sanitizedTitle =
        title.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_').toLowerCase();
    final sanitizedClass =
        classItem.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_').toLowerCase();

    if (Platform.isAndroid) {
      final baseDir = '/storage/emulated/0/Download/Pi-QBank';

      // Try multiple possible file naming patterns
      final filePatterns = [
        '$baseDir/paper_1_2024_${sanitizedTitle}_$sanitizedClass.pdf',
        '$baseDir/${sanitizedClass}_$sanitizedTitle.pdf',
        '$baseDir/${sanitizedTitle}_$sanitizedClass.pdf',
        '$baseDir/paper_1_2024_${sanitizedTitle}_${sanitizedClass}_${title.hashCode}.pdf',
      ];

      for (var filePath in filePatterns) {
        if (await File(filePath).exists()) {
          return true;
        }
      }
    }
    return false;
  }

  void _showClassSelectionDialog() async {
    if (!mounted || classSubjects.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        elevation: 8,
        title: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Center(
            child: Text(
              'Select Class',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
          ),
        ),
        content: SingleChildScrollView(
          child: ListBody(
            children: classSubjects.keys.map((className) {
              return GestureDetector(
                onTap: () async {
                  final navigator = Navigator.of(context);
                  setState(() {
                    selectedClass = className;
                  });
                  subjects = await Future.wait(
                      classSubjects[className]!.map((book) async {
                    return {
                      'title': book['title'],
                      'downloadUrl': book['downloadUrl'],
                      'subtitle': className,
                      'year': '',
                      'examYear': '2024',
                      'isDownloaded':
                          await _checkIfFileExists(book['title'], className),
                    };
                  }).toList());
                  setState(() {});
                  navigator.pop();
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  padding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                  decoration: BoxDecoration(
                    color: selectedClass == className
                        ? Colors.blue.shade100
                        : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selectedClass == className
                          ? Colors.blue
                          : Colors.grey.shade300,
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    className,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: selectedClass == className
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: selectedClass == className
                          ? Colors.blue.shade900
                          : Colors.black87,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _retryFetchBooksData() async {
    final connectivityService =
        Provider.of<ConnectivityService>(context, listen: false);
    await connectivityService.initConnectivity();

    debugPrint('Retry - Connectivity status: ${connectivityService.isOnline}');

    if (!mounted) return;

    if (connectivityService.isOnline) {
      setState(() {
        _showConnectivityWrapper = false;
        _isLoading = true;
      });
      _fetchBooksData();
    } else {
      // Show dialog with only close button
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.signal_wifi_off,
                size: 40,
                color: Colors.red,
              ),
            ),
            title: const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'No Internet Connection',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20),
              ),
            ),
            content: const Text(
              'Please connect to the internet to continue.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            actionsAlignment: MainAxisAlignment.center,
            actionsPadding: const EdgeInsets.symmetric(vertical: 16),
            actions: [
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.blue,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 26, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
                child: const Text(
                  'Close',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
              ),
            ],
          );
        },
      );

      debugPrint('Showing offline dialog');
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchBooksData();
  }

  Future<void> _fetchBooksData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final url = AppConfig.booksApi;
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer ${AppConfig.apiKey}',
        },
      );

      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body);

        setState(() {
          classSubjects.clear(); // Clear previous data

          // Start from index 1 to skip header row
          for (var i = 1; i < data.length; i++) {
            var item = data[i];
            String className = item[0]; // "Class1", "SSC", "HSC", etc.
            String subjectName = item[1]; // "Bangla", "English 2nd", etc.
            String downloadUrl = item[2]; // URL or "#"

            if (!classSubjects.containsKey(className)) {
              classSubjects[className] = [];
            }

            classSubjects[className]!.add({
              'class': className,
              'title': subjectName,
              'downloadUrl': downloadUrl,
            });
          }

          _isLoading = false;
        });

        // Show class selection dialog after data is loaded
        if (mounted && selectedClass == null) {
          _showClassSelectionDialog();
        }
      } else {
        setState(() {
          _showConnectivityWrapper = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _showConnectivityWrapper = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'Books'),
      drawer: const AppDrawer(),
      body: _showConnectivityWrapper
          ? ConnectivityWrapper(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.signal_wifi_off,
                        size: 48, color: Colors.red),
                    const SizedBox(height: 8),
                    const Text('No Internet Connection',
                        style: TextStyle(fontSize: 18, color: Colors.red)),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                      onPressed: _retryFetchBooksData,
                      style: ElevatedButton.styleFrom(
                        alignment: Alignment.center,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Container(
                    width: MediaQuery.of(context).size.width * 0.7,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.3),
                          spreadRadius: 2,
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          spreadRadius: 0,
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: InkWell(
                      onTap: _showClassSelectionDialog,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            const Text(
                              'Select Class:',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.black54,
                              ),
                            ),
                            Expanded(
                              child: Center(
                                child: Text(
                                  selectedClass ?? 'Choose',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _isLoading
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const CircularProgressIndicator(),
                                const SizedBox(height: 16),
                                Text(
                                  'Loading Books...',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight:
                                  MediaQuery.of(context).size.height * 0.7,
                            ),
                            child: subjects.isEmpty
                                ? Center(
                                    child: Text(
                                      'No books available for ${selectedClass ?? 'this class'}',
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 16,
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    shrinkWrap: true,
                                    itemCount: subjects.length,
                                    itemBuilder: (context, index) {
                                      final book = subjects[index];
                                      final key = ValueKey('${book['title']}');
                                      return KeyedSubtree(
                                        key: key,
                                        child: QuestionPaperCard(
                                          key: key,
                                          title: book['title'],
                                          subtitle: book['subtitle'] ?? '',
                                          year: book['year'] ?? '',
                                          examYear: book['examYear'] ?? '',
                                          downloadUrl:
                                              book['downloadUrl'] ?? '',
                                          category: 'Books',
                                        ),
                                      );
                                    },
                                  ),
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
