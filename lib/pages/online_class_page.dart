import 'package:flutter/material.dart';
import '../main.dart'; // Import for MainScreen
import '../services/youtube_api_service.dart'; // Import the API service
import '../models/video_models.dart'; // Import the new video models
import '../widgets/custom_app_bar.dart'; // Import the custom app bar
import '../widgets/app_drawer.dart'; // Import the app drawer
import 'video_player_page.dart'; // Import the new video player page
import '../widgets/loading_widget.dart'; // Import the LoadingWidget
import '../widgets/error_state_widget.dart'; // Import ErrorStateWidget

class OnlineClassPage extends StatefulWidget {
  const OnlineClassPage({super.key});

  @override
  State<OnlineClassPage> createState() => _OnlineClassPageState();
}

class _OnlineClassPageState extends State<OnlineClassPage> {
  // --- Selected Values ---
  String? selectedClass;
  String? selectedSubject;
  String? selectedChapter;
  String? _selectedDepartment;
  String? _selectedYear;

  List<Video> videos = [];
  List<Video> filteredVideos = [];
  bool isLoading = false;
  String? errorMessage;
  bool _showAdvancedFields = false;

  final YoutubeApiService _apiService = YoutubeApiService();

  // Dynamic lists for dropdowns
  List<String> availableClasses = [];
  List<String> availableSubjects = [];
  List<String> availableChapters = [];
  List<String> availableDepartments = []; // New dynamic list
  List<String> availableYears = []; // New dynamic list

  @override
  void initState() {
    super.initState();
    selectedClass = null;
    selectedSubject = null;
    selectedChapter = null;
    _fetchVideos();
  }

  void _fetchVideos() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
      videos = [];
      filteredVideos = [];
      availableClasses = [];
      availableSubjects = [];
      availableChapters = [];
    });

    try {
      final fetchedVideos =
          await _apiService.fetchVideos(); // Fetch all videos initially
      setState(() {
        videos = fetchedVideos;
        _populateDropdowns(); // Populate dropdowns based on all fetched videos
        _applyFilters();
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Failed to Load Video. Turn on internet connection';
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  void _populateDropdowns() {
    // Populate classes
    availableClasses = videos.map((video) => video.className).toSet().toList()
      ..sort();

    // Populate subjects based on selected class, department, and year (conditionally)
    if (selectedClass != null) {
      availableSubjects = videos
          .where((video) {
            bool classMatch = video.className == selectedClass!;
            bool departmentMatch = true;
            bool yearMatch = true;

            if (_showAdvancedFields) {
              if (_selectedDepartment != null) {
                departmentMatch = video.department == _selectedDepartment!;
              }
              if (_selectedYear != null) {
                yearMatch = video.year == _selectedYear!;
              }
            }
            return classMatch && departmentMatch && yearMatch;
          })
          .map((video) => video.subjectName)
          .toSet()
          .toList()
        ..sort();
    } else {
      availableSubjects = [];
    }

    // Populate chapters based on selected class, subject, department, and year (conditionally)
    if (selectedClass != null && selectedSubject != null) {
      availableChapters = videos
          .where((video) {
            bool classMatch = video.className == selectedClass!;
            bool subjectMatch = video.subjectName == selectedSubject!;
            bool departmentMatch = true;
            bool yearMatch = true;

            if (_showAdvancedFields) {
              if (_selectedDepartment != null) {
                departmentMatch = video.department == _selectedDepartment!;
              }
              if (_selectedYear != null) {
                yearMatch = video.year == _selectedYear!;
              }
            }
            return classMatch && subjectMatch && departmentMatch && yearMatch;
          })
          .map((video) => video.chapterName)
          .toSet()
          .toList()
        ..sort();
    } else {
      availableChapters = [];
    }

    // Populate departments based on selected class (Honours/Masters)
    if (selectedClass != null &&
        (selectedClass == "Honours" || selectedClass == "Masters")) {
      availableDepartments = videos
          .where((video) => video.className == selectedClass!)
          .map((video) => video.department)
          .where((department) => department != null && department.isNotEmpty)
          .toSet()
          .cast<String>()
          .toList()
        ..sort();
    } else {
      availableDepartments = [];
    }

    // Populate years based on selected class and department
    if (selectedClass != null &&
        (selectedClass == "Honours" || selectedClass == "Masters") &&
        _selectedDepartment != null) {
      availableYears = videos
          .where((video) =>
              video.className == selectedClass! &&
              video.department == _selectedDepartment!)
          .map((video) => video.year)
          .where((year) => year != null && year.isNotEmpty)
          .toSet()
          .cast<String>()
          .toList()
        ..sort();
    } else {
      availableYears = [];
    }
  }

  void _applyFilters() {
    setState(() {
      filteredVideos = videos.where((video) {
        final classMatch =
            selectedClass == null || video.className == selectedClass!;
        final subjectMatch =
            selectedSubject == null || video.subjectName == selectedSubject!;
        final chapterMatch =
            selectedChapter == null || video.chapterName == selectedChapter!;

        // Advanced fields filtering for Honours/Masters
        final departmentMatch = (_selectedDepartment == null ||
            video.department == _selectedDepartment!);
        final yearMatch =
            (_selectedYear == null || video.year == _selectedYear!);

        if (_showAdvancedFields) {
          return classMatch &&
              subjectMatch &&
              chapterMatch &&
              departmentMatch &&
              yearMatch;
        } else {
          return classMatch && subjectMatch && chapterMatch;
        }
      }).toList();
    });
  }

  void _handleBack() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const MainScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: LoadingWidget(loadingText: 'Loading Videos...'),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA), // Light grey/blue background
        appBar: const CustomAppBar(
          title: 'Online Class',
        ),
        drawer: const AppDrawer(),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Column(
                  children: [
                    if (!_showAdvancedFields)
                      Row(
                        children: [
                          Expanded(
                            child: _buildFilterChip(
                              'Class',
                              selectedClass,
                              availableClasses,
                              (String? newValue) {
                                setState(() {
                                  selectedClass = newValue;
                                  selectedSubject = null;
                                  selectedChapter = null;
                                  _showAdvancedFields =
                                      (newValue == "Honours" ||
                                          newValue == "Masters");
                                  _populateDropdowns();
                                  _applyFilters();
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildFilterChip(
                              'Subject',
                              selectedSubject,
                              availableSubjects,
                              (String? newValue) {
                                setState(() {
                                  selectedSubject = newValue;
                                  selectedChapter = null;
                                  _populateDropdowns();
                                  _applyFilters();
                                });
                              },
                              enabled: selectedClass != null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildFilterChip(
                              'Chapter',
                              selectedChapter,
                              availableChapters,
                              (String? newValue) {
                                setState(() {
                                  selectedChapter = newValue;
                                  _applyFilters();
                                });
                              },
                              enabled: selectedClass != null &&
                                  selectedSubject != null,
                            ),
                          ),
                        ],
                      )
                    else ...[
                      Row(
                        children: [
                          Expanded(
                            child: _buildFilterChip(
                              'Class',
                              selectedClass,
                              availableClasses,
                              (String? newValue) {
                                setState(() {
                                  selectedClass = newValue;
                                  selectedSubject = null;
                                  selectedChapter = null;
                                  _showAdvancedFields =
                                      (newValue == "Honours" ||
                                          newValue == "Masters");
                                  if (!_showAdvancedFields) {
                                    _selectedDepartment = null;
                                    _selectedYear = null;
                                  }
                                  _populateDropdowns();
                                  _applyFilters();
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildFilterChip(
                              'Department',
                              _selectedDepartment,
                              availableDepartments,
                              (String? newValue) {
                                setState(() {
                                  _selectedDepartment = newValue;
                                  _selectedYear = null;
                                  _populateDropdowns();
                                  _applyFilters();
                                });
                              },
                              enabled: selectedClass != null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildFilterChip(
                              'Year',
                              _selectedYear,
                              availableYears,
                              (String? newValue) {
                                setState(() {
                                  _selectedYear = newValue;
                                  _populateDropdowns();
                                  _applyFilters();
                                });
                              },
                              enabled: selectedClass != null &&
                                  _selectedDepartment != null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildFilterChip(
                              'Subject',
                              selectedSubject,
                              availableSubjects,
                              (String? newValue) {
                                setState(() {
                                  selectedSubject = newValue;
                                  selectedChapter = null;
                                  _populateDropdowns();
                                  _applyFilters();
                                });
                              },
                              enabled: selectedClass != null &&
                                  _selectedDepartment != null &&
                                  _selectedYear != null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildFilterChip(
                              'Chapter',
                              selectedChapter,
                              availableChapters,
                              (String? newValue) {
                                setState(() {
                                  selectedChapter = newValue;
                                  _applyFilters();
                                });
                              },
                              enabled: selectedClass != null &&
                                  _selectedDepartment != null &&
                                  _selectedYear != null &&
                                  selectedSubject != null,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              errorMessage != null
                  ? Expanded(
                      child: ErrorStateWidget(
                        errorMessage: errorMessage,
                        onRetry: _fetchVideos,
                      ),
                    )
                  : Expanded(
                      child: filteredVideos.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.ondemand_video_outlined,
                                      size: 60, color: Colors.grey[400]),
                                  const SizedBox(height: 10),
                                  Text(
                                    'No videos found for the selected criteria.',
                                    style: TextStyle(
                                        fontSize: 16, color: Colors.grey[600]),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            )
                          : GridView.builder(
                              padding: const EdgeInsets.all(8.0),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 10.0,
                                mainAxisSpacing: 10.0,
                                childAspectRatio: 16 / 14,
                              ),
                              itemCount: filteredVideos.length,
                              itemBuilder: (context, index) {
                                final video = filteredVideos[index];
                                return Card(
                                  elevation: 4,
                                  margin: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => VideoPlayerPage(
                                            youtubeUrl: video.youtubeUrl,
                                            videoTitle: video.title,
                                          ),
                                        ),
                                      );
                                    },
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              FadeInImage.assetNetwork(
                                                placeholder:
                                                    'assets/gifs/giphy.gif',
                                                image: video.thumbnailUrl,
                                                fit: BoxFit.cover,
                                                width: double.infinity,
                                                imageErrorBuilder: (context,
                                                    error, stackTrace) {
                                                  return Image.asset(
                                                    'assets/gifs/giphy.gif',
                                                    fit: BoxFit.cover,
                                                    width: double.infinity,
                                                  );
                                                },
                                              ),
                                              Icon(
                                                Icons.play_circle_fill,
                                                color: Colors.white
                                                    .withOpacity(0.8),
                                                size: 50,
                                              ),
                                            ],
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              left: 8.0, right: 8.0, top: 4.0),
                                          child: Text(
                                            video.title,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8.0, vertical: 4.0),
                                          child: Text(
                                            '${video.className} | ${video.subjectName} | ${video.chapterName}',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[600]),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String? value, List<String> options,
      ValueChanged<String?> onChanged,
      {bool enabled = true}) {
    IconData getIcon() {
      switch (label) {
        case 'Class':
          return Icons.school_rounded;
        case 'Department':
          return Icons.business_rounded;
        case 'Year':
          return Icons.calendar_today_rounded;
        case 'Subject':
          return Icons.menu_book_rounded;
        case 'Chapter':
          return Icons.topic_rounded;
        default:
          return Icons.category_rounded;
      }
    }

    Widget buildItemContent(String text) {
      return Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.indigo.withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(
              getIcon(),
              size: 16,
              color: Colors.indigo.withOpacity(0.8),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    return Opacity(
      opacity: enabled ? 1.0 : 0.6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.indigo,
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.indigo.withOpacity(0.15)),
              boxShadow: [
                BoxShadow(
                  color: Colors.indigo.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: (enabled && options.contains(value)) ? value : null,
                isExpanded: true,
                menuWidth: 200,
                icon: const Icon(Icons.keyboard_arrow_down_rounded,
                    color: Colors.indigo, size: 20),
                hint: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.indigo.withOpacity(0.05),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        getIcon(),
                        size: 16,
                        color: Colors.indigo.withOpacity(0.8),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Select',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                selectedItemBuilder: (BuildContext context) {
                  return options.map<Widget>((String item) {
                    return buildItemContent(item);
                  }).toList();
                },
                items: options.asMap().entries.map((entry) {
                  final item = entry.value;
                  final isLast = entry.key == options.length - 1;
                  return DropdownMenuItem<String>(
                    value: item,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Container(
                                width: 3,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: Colors.indigo.withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  item,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!isLast)
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: Colors.indigo.withOpacity(0.05),
                          ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: enabled ? onChanged : null,
                dropdownColor: Colors.white,
                borderRadius: BorderRadius.circular(12),
                style: const TextStyle(color: Colors.black87),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
