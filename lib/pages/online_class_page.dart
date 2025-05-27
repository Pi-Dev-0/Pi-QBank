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
  String? selectedClass;
  String? selectedSubject;
  String? selectedChapter;
  List<Video> videos = [];
  List<Video> filteredVideos = [];
  bool isLoading = false;
  String? errorMessage;

  final YoutubeApiService _apiService = YoutubeApiService();

  // Dynamic lists for dropdowns
  List<String> availableClasses = [];
  List<String> availableSubjects = [];
  List<String> availableChapters = [];

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
        errorMessage = 'Failed to load videos: ${e.toString()}';
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

    // Populate subjects based on selected class
    if (selectedClass != null) {
      availableSubjects = videos
          .where((video) => video.className == selectedClass!)
          .map((video) => video.subjectName)
          .toSet()
          .toList()
        ..sort();
    } else {
      availableSubjects = [];
    }

    // Populate chapters based on selected class and subject
    if (selectedClass != null && selectedSubject != null) {
      availableChapters = videos
          .where((video) =>
              video.className == selectedClass! &&
              video.subjectName == selectedSubject!)
          .map((video) => video.chapterName)
          .toSet()
          .toList()
        ..sort();
    } else {
      availableChapters = [];
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
        return classMatch && subjectMatch && chapterMatch;
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
            Row(
              children: [
                Expanded(
                  child: _buildDropdown(
                    labelText: 'Class',
                    value: selectedClass,
                    items: availableClasses,
                    onChanged: (String? newValue) {
                      setState(() {
                        selectedClass = newValue;
                        selectedSubject = null; // Reset subject
                        selectedChapter = null; // Reset chapter
                        _populateDropdowns(); // Repopulate subjects and chapters
                        _applyFilters();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8.0),
                Expanded(
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
                  ),
                ),
                const SizedBox(width: 8.0),
                Expanded(
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
  }) {
    return InkWell(
      onTap: () {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width - 32,
                  maxHeight: MediaQuery.of(context).size.height * 0.7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor.withOpacity(0.1),
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
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).primaryColor,
                              ),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            child: IconButton(
                              icon: Icon(
                                Icons.close_rounded,
                                color: Theme.of(context).primaryColor,
                              ),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final isSelected = items[index] == value;
                          return ListTile(
                            title: Text(
                              items[index],
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isSelected
                                    ? Theme.of(context).primaryColor
                                    : null,
                              ),
                            ),
                            leading: Icon(
                              isSelected
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_off_rounded,
                              color: isSelected
                                  ? Theme.of(context).primaryColor
                                  : Colors.grey,
                            ),
                            selected: isSelected,
                            selectedColor: Theme.of(context).primaryColor,
                            onTap: () {
                              onChanged(items[index]);
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
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
                    color: value?.isNotEmpty == true
                        ? Colors.black
                        : Colors.grey[500],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 20),
          ],
        ),
      ),
    );
  }
}
