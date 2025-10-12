import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

void showYoutubePlayerDialog(BuildContext context, String videoId) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: YoutubePlayerDialogContent(videoId: videoId),
      );
    },
  );
}

class YoutubePlayerDialogContent extends StatefulWidget {
  final String videoId;

  const YoutubePlayerDialogContent({super.key, required this.videoId});

  @override
  State<YoutubePlayerDialogContent> createState() =>
      _YoutubePlayerDialogContentState();
}

class _YoutubePlayerDialogContentState
    extends State<YoutubePlayerDialogContent> {
  late YoutubePlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController(
      initialVideoId: widget.videoId,
      flags: const YoutubePlayerFlags(
        autoPlay: false,
        mute: false,
      ),
    );
  }

  bool _isPlaying = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _isPlaying
              ? YoutubePlayer(
                  controller: _controller,
                  showVideoProgressIndicator: true,
                  progressIndicatorColor: Colors.blueAccent,
                  onReady: () {
                    // _controller.addListener(listener);
                  },
                )
              : GestureDetector(
                  onTap: () {
                    setState(() {
                      _isPlaying = true;
                      _controller.play(); // Start playing when thumbnail is tapped
                    });
                  },
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.network(
                          'https://img.youtube.com/vi/${widget.videoId}/hqdefault.jpg', // Direct thumbnail URL
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: 200, // Adjust height as needed
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                            color: Colors.grey,
                            height: 200,
                            child: const Center(
                              child: Icon(Icons.broken_image,
                                  color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.play_circle_filled,
                        color: Colors.white,
                        size: 60.0,
                      ),
                    ],
                  ),
                ),
        ],
      ),
    );
  }
}
