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
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            children: <Widget>[
              YoutubePlayerDialogContent(videoId: videoId),
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ],
          ),
        ),
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
  late final YoutubePlayerController _controller;
  final ValueNotifier<bool> _showThumbnail = ValueNotifier(true);

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController(
      initialVideoId: widget.videoId,
      flags: const YoutubePlayerFlags(
        autoPlay: false,
        mute: false,
        forceHD: true,
      ),
    )..addListener(_playerListener);
  }

  void _playerListener() {
    if (mounted) {
      final isPlaying = _controller.value.playerState == PlayerState.playing;
      if (isPlaying && _showThumbnail.value) {
        _showThumbnail.value = false;
      } else if (_controller.value.playerState == PlayerState.ended) {
        _showThumbnail.value = true;
      }
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_playerListener);
    _controller.dispose();
    _showThumbnail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: ValueListenableBuilder<bool>(
        valueListenable: _showThumbnail,
        builder: (context, showThumbnail, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              Offstage(
                offstage: showThumbnail,
                child: YoutubePlayer(
                  controller: _controller,
                  showVideoProgressIndicator: true,
                  progressIndicatorColor: Theme.of(context).colorScheme.primary,
                  progressColors: ProgressBarColors(
                    playedColor: Theme.of(context).colorScheme.primary,
                    handleColor: Theme.of(context).colorScheme.primary,
                  ),
                  onReady: () {
                    // Optional: anything to do when player is ready
                  },
                ),
              ),
              if (showThumbnail) ...[
                _buildThumbnail(),
                _buildPlayButton(),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildThumbnail() {
    return Image.network(
      'https://img.youtube.com/vi/${widget.videoId}/hqdefault.jpg',
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.primary),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) => const Center(
        child: Icon(Icons.error_outline, color: Colors.white, size: 40),
      ),
    );
  }

  Widget _buildPlayButton() {
    return GestureDetector(
      onTap: () {
        _controller.play();
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.play_arrow_rounded,
          color: Colors.white,
          size: 50.0,
        ),
      ),
    );
  }
}