import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../services/connectivity_service.dart';
import '../widgets/app_drawer.dart';
import '../widgets/question_paper_card.dart';
import '../widgets/custom_app_bar.dart';
import '../config/app_config.dart';

class GuideBookPage extends StatefulWidget {
  const GuideBookPage({super.key});

  @override
  State<GuideBookPage> createState() => _GuideBookPageState();
}

class _GuideBookPageState extends State<GuideBookPage> {
  String? selectedClass;
  List<Map<String, dynamic>> guides = [];
  bool isLoading = false;
  final Map<String, List<Map<String, dynamic>>> classGuides = {};

  // Color palette for guide cards
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

  @override
  void initState() {
    super.initState();
    fetchData();
  }

  Future<void> fetchData() async {
    // Early exit if not mounted
    if (!mounted) return;

    try {
      final connectivityService =
          Provider.of<ConnectivityService>(context, listen: false);
      await connectivityService.initConnectivity();

      // Check mounted again after async operation
      if (!mounted) return;

      setState(() {
        isLoading = true;
      });

      final url = AppConfig.guideBookApi;
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer ${AppConfig.apiKey}',
        },
      );

      // Check mounted before processing response
      if (!mounted) return;

      if (response.statusCode == 200) {
        List<dynamic> data = jsonDecode(response.body);

        // Skip the header row [0] which contains ["CLASS", "SUBJECT", "URL"]
        if (data.length > 1) {
          if (!mounted) return;
          setState(() {
            classGuides.clear();
            // Start from index 1 to skip header row
            for (var i = 1; i < data.length; i++) {
              var item = data[i];
              String className = item[0]; // "Class1", "SSC", "HSC", etc.
              String subjectName = item[1]; // "Bangla", "English 2nd", etc.
              String downloadUrl = item[2]; // URL or "#"

              if (!classGuides.containsKey(className)) {
                classGuides[className] = [];
              }

              classGuides[className]!.add({
                'title': subjectName,
                'downloadUrl': downloadUrl,
              });
            }
          });

          // Show dialog after data is loaded
          if (mounted && selectedClass == null) {
            _showClassSelectionDialog();
          }
        }
      } else {
        throw Exception('Failed to load guide books: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error loading guide books: $e');

      // Check mounted before showing any dialogs
      if (!mounted) return;

      final connectivityService =
          Provider.of<ConnectivityService>(context, listen: false);

      if (!connectivityService.isOnline) {
        // Show dialog with only close button
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
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  void _showClassSelectionDialog() {
    if (mounted && classGuides.isNotEmpty) {
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
              children: classGuides.keys.map((className) {
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      selectedClass = className;
                      guides = classGuides[className] ?? [];
                    });
                    Navigator.pop(context);
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 14),
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
  }

  @override
  Widget build(BuildContext context) {
    final connectivityService =
        Provider.of<ConnectivityService>(context, listen: false);

    return Scaffold(
      appBar: const CustomAppBar(title: 'Guides'),
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
        child: connectivityService.isOnline
            ? Padding(
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
                      child: isLoading
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const CircularProgressIndicator(),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Loading Guide Books...',
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
                              child: guides.isEmpty
                                  ? Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.menu_book_rounded,
                                            size: 64,
                                            color: Colors.grey.shade400,
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            'No guides available',
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
                                      itemCount: guides.length,
                                      padding:
                                          const EdgeInsets.only(bottom: 20),
                                      itemBuilder: (context, index) {
                                        final guide = guides[index];
                                        final key =
                                            ValueKey('${guide['title']}');
                                        final color = _cardColors[
                                            index % _cardColors.length];

                                        return Theme(
                                          data: Theme.of(context).copyWith(
                                            primaryColor: color,
                                            colorScheme: ColorScheme.fromSeed(
                                              seedColor: color,
                                              primary: color,
                                            ),
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 8.0),
                                            child: KeyedSubtree(
                                              key: key,
                                              child: QuestionPaperCard(
                                                key: key,
                                                title: guide['title'],
                                                subtitle: selectedClass ?? '',
                                                year: '',
                                                examYear: '',
                                                downloadUrl:
                                                    guide['downloadUrl'] ?? '',
                                                category: 'Guide Books',
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
              )
            : Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
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
                        onPressed: fetchData,
                        style: ElevatedButton.styleFrom(
                          alignment: Alignment.center,
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
