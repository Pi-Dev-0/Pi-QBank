import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
// import '../widgets/app_drawer.dart';
import '../widgets/question_paper_card.dart';
import '../widgets/custom_app_bar.dart';
import '../config/app_config.dart';
import '../services/connectivity_service.dart';
import '../widgets/error_state_widget.dart';
import '../widgets/loading_widget.dart';
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

  // Color palette for book cards
  final List<Color> _cardColors = [
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

  // Hardcoded encryption key for Books API
  static const String _encryptionKey =
      "BOOKS_SECRET_KEY"; // New hardcoded key for this page

  // XOR encryption/decryption logic with Base64 encoding
  String _xorEncryptDecrypt(String inputBase64, String key) {
    try {
      // Decode Base64 string to bytes
      final encryptedBytes = base64.decode(inputBase64);
      final keyBytes = utf8.encode(key);
      final decryptedBytes = <int>[];

      for (int i = 0; i < encryptedBytes.length; i++) {
        decryptedBytes.add(encryptedBytes[i] ^ keyBytes[i % keyBytes.length]);
      }
      // Decode bytes to UTF-8 string
      return utf8.decode(decryptedBytes);
    } catch (e) {
      rethrow;
    }
  }

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
      barrierDismissible: true,
      builder: (BuildContext dialogContext) => AlertDialog(
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
                onTap: () {
                  Navigator.of(dialogContext).maybePop();
                  if (!mounted) return;
                  _updateSelectedClass(className);
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

  // Separate method to handle class selection and state updates
  void _updateSelectedClass(String className) async {
    if (!mounted) return;

    try {
      final newSubjects =
          await Future.wait(classSubjects[className]!.map((book) async {
        return {
          'title': book['title'],
          'downloadUrl': book['downloadUrl'],
          'subtitle': className,
          'year': '',
          'examYear': '2024',
          'isDownloaded': await _checkIfFileExists(book['title'], className),
        };
      }).toList());

      if (!mounted) return;
      setState(() {
        selectedClass = className;
        subjects = newSubjects;
      });
    } catch (e) {
      // Error updating selected class
    }
  }

  void _retryFetchBooksData() async {
    final connectivityService =
        Provider.of<ConnectivityService>(context, listen: false);
    await connectivityService.initConnectivity();

    if (!mounted) return;

    if (connectivityService.isOnline) {
      setState(() {
        _showConnectivityWrapper = false;
        _isLoading = true;
      });
      _fetchBooksData();
    } else {
      // Showing offline dialog
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
        // Decrypt the response body (which is Base64 encoded)
        final decryptedBody = _xorEncryptDecrypt(response.body, _encryptionKey);
        List<dynamic> data = json.decode(decryptedBody);

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
    if (_isLoading) {
      return const Scaffold(
        body: LoadingWidget(loadingText: 'Loading Books...'),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: const CustomAppBar(title: 'Books'),
        // drawer: const AppDrawer(), // Removed to show back button
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
          child: _showConnectivityWrapper
              ? ErrorStateWidget(
                  onRetry: _retryFetchBooksData,
                )
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Container(
                        width: MediaQuery.of(context).size.width * 0.8,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.white, Colors.blue.shade50],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(15),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blue.withOpacity(0.1),
                              spreadRadius: 2,
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                          border: Border.all(
                            color: Colors.blue.withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                        child: InkWell(
                          onTap: _showClassSelectionDialog,
                          borderRadius: BorderRadius.circular(15),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.school_rounded,
                                  color: Colors.blue,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Selected Class',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    Text(
                                      selectedClass ?? 'Tap to choose',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.keyboard_arrow_down_rounded,
                                  color: Colors.blue),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Expanded(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: MediaQuery.of(context).size.height * 0.7,
                          ),
                          child: subjects.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.library_books_outlined,
                                        size: 64,
                                        color: Colors.grey.shade400,
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        'No books available',
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 18,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      if (selectedClass != null)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 8),
                                          child: Text(
                                            'for $selectedClass',
                                            style: TextStyle(
                                              color: Colors.grey[500],
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: subjects.length,
                                  padding: const EdgeInsets.only(bottom: 20),
                                  itemBuilder: (context, index) {
                                    final book = subjects[index];
                                    final key = ValueKey('${book['title']}');
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
                                      child: Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 8.0),
                                        child: KeyedSubtree(
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
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
