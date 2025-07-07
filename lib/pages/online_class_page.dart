import 'package:flutter/material.dart';
import '../services/youtube_api_service.dart'; // Import the API service
import '../models/video_models.dart'; // Import the new video models
import '../widgets/custom_app_bar.dart'; // Import the custom app bar
import '../widgets/app_drawer.dart'; // Import the app drawer
import 'video_player_page.dart'; // Import the new video player page

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(
        title: 'Online Class',
      ),
      drawer: const AppDrawer(),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Wrap(
              spacing: 8.0, // Horizontal spacing between dropdowns
              runSpacing: 8.0, // Vertical spacing if they wrap
              alignment: WrapAlignment.center,
              children: [
                SizedBox(
                  width: 110, // Adjust width as needed
                  child: _buildDropdown(
                    labelText: 'Class',
                    value: selectedClass,
                    items: availableClasses,
                    onChanged: (String? newValue) {
                      setState(() {
                        selectedClass = newValue;
                        selectedSubject = null; // Reset subject
                        selectedChapter = null; // Reset chapter
                        _showAdvancedFields =
                            (newValue == "Honours" || newValue == "Masters");
                        if (!_showAdvancedFields) {
                          // Reset Honours/Masters specific fields if class is changed
                          _selectedDepartment = null;
                          _selectedYear = null;
                        }
                        _populateDropdowns(); // Repopulate all relevant dropdowns
                        _applyFilters();
                      });
                    },
                    enabled: true,
                  ),
                ),
                if (_showAdvancedFields)
                  SizedBox(
                    width: 110, // Adjust width as needed
                    child: _buildDropdown(
                      labelText: 'Department',
                      value: _selectedDepartment,
                      items: availableDepartments, // Use dynamic list
                      onChanged: (String? newValue) {
                        setState(() {
                          _selectedDepartment = newValue;
                          _selectedYear =
                              null; // Reset year when department changes
                          _populateDropdowns(); // Repopulate years
                          _applyFilters();
                        });
                      },
                      enabled: selectedClass != null,
                    ),
                  ),
                if (_showAdvancedFields)
                  SizedBox(
                    width: 110, // Adjust width as needed
                    child: _buildDropdown(
                      labelText: 'Year',
                      value: _selectedYear,
                      items: availableYears, // Use dynamic list
                      onChanged: (String? newValue) {
                        setState(() {
                          _selectedYear = newValue;
                          _populateDropdowns(); // Repopulate subjects and chapters based on new year
                          _applyFilters();
                        });
                      },
                      enabled:
                          selectedClass != null && _selectedDepartment != null,
                    ),
                  ),
                SizedBox(
                  width: 110, // Adjust width as needed
                  child: _buildDropdown(
                    labelText: 'Subject',
                    value: selectedSubject,
                    items: availableSubjects,
                    onChanged: (String? newValue) {
                      setState(() {
                        selectedSubject = newValue;
                        selectedChapter = null; // Reset chapter
                        _populateDropdowns(); // Repopulate chapters
                        _applyFilters();
                      });
                    },
                    enabled: _showAdvancedFields
                        ? (selectedClass != null &&
                            _selectedDepartment != null &&
                            _selectedYear != null)
                        : (selectedClass != null),
                  ),
                ),
                SizedBox(
                  width: 110, // Adjust width as needed
                  child: _buildDropdown(
                    labelText: 'Chapter',
                    value: selectedChapter,
                    items: availableChapters,
                    onChanged: (String? newValue) {
                      setState(() {
                        selectedChapter = newValue;
                        _applyFilters();
                      });
                    },
                    enabled: _showAdvancedFields
                        ? (selectedClass != null &&
                            _selectedDepartment != null &&
                            _selectedYear != null &&
                            selectedSubject != null)
                        : (selectedClass != null && selectedSubject != null),
                  ),
                ),
              ],
            ),
            isLoading
                ? const Expanded(
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  )
                : errorMessage != null
                    ? Center(
                        child: Text(
                          errorMessage!,
                          style:
                              const TextStyle(color: Colors.red, fontSize: 16),
                          textAlign: TextAlign.center,
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
                                          fontSize: 16,
                                          color: Colors.grey[600]),
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
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                    clipBehavior: Clip.antiAlias,
                                    child: InkWell(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                VideoPlayerPage(
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
                                                left: 8.0,
                                                right: 8.0,
                                                top: 4.0),
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
    );
  }

  Widget _buildDropdown({
    required String labelText,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    bool enabled = true,
  }) {
    return AbsorbPointer(
      absorbing: !enabled,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.5,
        child: InkWell(
          onTap: enabled
              ? () {
                  showDialog(
                    context: context,
                    barrierDismissible: true,
                    builder: (BuildContext dialogContext) {
                      final double dialogWidth =
                          MediaQuery.of(context).size.width * 0.7;
                      final double dialogMaxHeight =
                          MediaQuery.of(context).size.height * 0.6;
                      return AlertDialog(
                        backgroundColor: Colors.white,
                        elevation: 8,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        titlePadding: EdgeInsets.zero,
                        contentPadding: EdgeInsets.zero,
                        title: Container(
                          width: dialogWidth,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(20),
                              topRight: Radius.circular(20),
                            ),
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Center(
                                child: Text(
                                  'Select $labelText',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue,
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 0,
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    color: Colors.blue,
                                  ),
                                  onPressed: () => Navigator.pop(dialogContext),
                                ),
                              ),
                            ],
                          ),
                        ),
                        content: SizedBox(
                          width: dialogWidth,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: dialogMaxHeight,
                            ),
                            child: SingleChildScrollView(
                              child: ListBody(
                                children: items.map((item) {
                                  final isSelected = item == value;
                                  return GestureDetector(
                                    onTap: () {
                                      onChanged(item);
                                      Navigator.of(dialogContext).maybePop();
                                    },
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(
                                          vertical: 6, horizontal: 8),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 10, horizontal: 14),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? Colors.blue.shade100
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isSelected
                                              ? Colors.blue
                                              : Colors.grey.shade300,
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Center(
                                              child: Text(
                                                item,
                                                style: TextStyle(
                                                  fontWeight: isSelected
                                                      ? FontWeight.bold
                                                      : FontWeight.normal,
                                                  color: isSelected
                                                      ? Colors.blue.shade900
                                                      : Colors.black87,
                                                  fontSize: 15,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                                textAlign: TextAlign.center,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                }
              : null,
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: labelText,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Center(
                    child: Text(
                      value?.isNotEmpty == true ? value! : 'Select',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: enabled
                            ? (value?.isNotEmpty == true
                                ? Colors.black
                                : Colors.grey[500])
                            : Colors.grey[400],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const Icon(Icons.arrow_drop_down, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
