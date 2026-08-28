import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Extracts a YouTube video ID from a full URL or returns the string as-is.
String extractYoutubeVideoId(String urlOrId) {
  if (!urlOrId.contains('/') && !urlOrId.contains('.')) return urlOrId;
  final patterns = [
    RegExp(r'youtu\.be/([^?&]+)'),
    RegExp(r'youtube\.com/watch\?v=([^&]+)'),
    RegExp(r'youtube\.com/embed/([^?&]+)'),
    RegExp(r'youtube\.com/shorts/([^?&]+)'),
  ];
  for (final p in patterns) {
    final m = p.firstMatch(urlOrId);
    if (m != null) return m.group(1) ?? urlOrId;
  }
  return urlOrId;
}

/// Builds the host HTML page using youtube-nocookie.com and an explicit <iframe>.
/// Explicit iframe element with feature policy attributes prevents origin 152
/// errors while retaining full YouTube IFrame Player API interactivity.
String _buildYtApiHtml(String videoId) => '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport"
        content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <style>
    * { margin:0; padding:0; box-sizing:border-box; }
    html, body { width:100%; height:100%; background:#000; overflow:hidden; }
    #player { width:100% !important; height:100% !important; border:none; }
  </style>
</head>
<body>
  <iframe id="player"
          src="https://www.youtube-nocookie.com/embed/$videoId?autoplay=1&enablejsapi=1&playsinline=1&rel=0&modestbranding=1&fs=1&origin=https://www.youtube-nocookie.com"
          allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
          allowfullscreen
          style="width:100%; height:100%; border:none;">
  </iframe>

  <script>
    // ── Safe bridge helper ─────────────────────────────────────────────────
    function bridge(msg) {
      try { YTBridge.postMessage(msg); } catch(e) {}
    }

    // ── Load IFrame Player API ──────────────────────────────────────────────
    var tag = document.createElement('script');
    tag.src = 'https://www.youtube-nocookie.com/iframe_api';
    document.head.appendChild(tag);

    // ── Attach player events once API is ready ──────────────────────────────
    var player;
    function onYouTubeIframeAPIReady() {
      bridge('[API_READY] YouTube IFrame API loaded');
      player = new YT.Player('player', {
        host: 'https://www.youtube-nocookie.com',
        events: {
          onReady: function(e) {
            bridge('[PLAYER_READY] Player initialized OK');
            try { e.target.playVideo(); } catch(err) {}
          },
          onStateChange: function(e) {
            var s = {'-1':'UNSTARTED','0':'ENDED','1':'PLAYING','2':'PAUSED',
                     '3':'BUFFERING','5':'CUED'};
            bridge('[STATE] ' + (s[String(e.data)] || e.data));
          },
          onError: function(e) {
            var err = {'2':'INVALID_PARAM','5':'HTML5_ERROR','100':'NOT_FOUND',
                       '101':'EMBED_DISABLED','150':'EMBED_DISABLED_ALT',
                       '152':'ORIGIN_RESTRICTED'};
            bridge('[PLAYER_ERROR] code=' + e.data
                   + ' meaning=' + (err[String(e.data)] || 'UNKNOWN'));
          },
          onPlaybackQualityChange: function(e) {
            bridge('[QUALITY] ' + e.data);
          }
        }
      });
    }

    // ── Timeout guard ──────────────────────────────────────────────────────
    setTimeout(function() {
      if (typeof YT === 'undefined' || typeof YT.Player === 'undefined') {
        bridge('[TIMEOUT] IFrame API script never loaded – network issue?');
      } else if (!player) {
        bridge('[TIMEOUT] player not created after 12 s');
      }
    }, 12000);
  </script>
</body>
</html>
''';

// ---------------------------------------------------------------------------
// Shared controller builder
// ---------------------------------------------------------------------------

WebViewController _buildController({
  required String videoId,
  required void Function(String url) onPageStarted,
  required void Function(String url) onPageFinished,
  required void Function(String msg) onError,
  required void Function(String msg) onYtEvent,
}) {
  final controller = WebViewController();

  // JS → Dart bridge for all YouTube player events
  controller.addJavaScriptChannel(
    'YTBridge',
    onMessageReceived: (JavaScriptMessage msg) {
      final data = msg.message;
      debugPrint('[YTPlayer][JS] $data');
      onYtEvent(data);
    },
  );

  controller
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setBackgroundColor(Colors.black)
    ..setNavigationDelegate(NavigationDelegate(
      onPageStarted: (url) {
        debugPrint('[YTPlayer][Nav] PAGE STARTED  → $url');
        onPageStarted(url);
      },
      onPageFinished: (url) {
        debugPrint('[YTPlayer][Nav] PAGE FINISHED → $url');
        onPageFinished(url);
      },
      onWebResourceError: (WebResourceError err) {
        final msg =
            'WebResourceError [${err.errorCode}]: ${err.description} '
            '| url=${err.url} | main=${err.isForMainFrame}';
        debugPrint('[YTPlayer][ERROR] $msg');
        final isAdError = err.url?.contains('googleads') == true ||
            err.url?.contains('doubleclick') == true;
        if (err.isForMainFrame == true && !isAdError) onError(msg);
      },
      onHttpError: (HttpResponseError err) {
        debugPrint('[YTPlayer][HTTP] ${err.response?.statusCode} '
            '→ ${err.request?.uri}');
      },
      onNavigationRequest: (NavigationRequest req) {
        debugPrint('[YTPlayer][Nav] REQUEST → ${req.url}');
        final url = req.url;
        if (url.startsWith('intent://') ||
            url.startsWith('market://') ||
            url.startsWith('vnd.youtube://') ||
            url.startsWith('youtube://')) {
          debugPrint('[YTPlayer][Nav] BLOCKED deep-link: $url');
          return NavigationDecision.prevent;
        }
        return NavigationDecision.navigate;
      },
      onUrlChange: (UrlChange c) =>
          debugPrint('[YTPlayer][Nav] URL CHANGED → ${c.url}'),
    ))
    ..loadHtmlString(
      _buildYtApiHtml(videoId),
      baseUrl: 'https://www.youtube-nocookie.com',
    );

  if (Platform.isAndroid) {
    debugPrint('[YTPlayer] setMediaPlaybackRequiresUserGesture(false)');
    (controller.platform as AndroidWebViewController)
        .setMediaPlaybackRequiresUserGesture(false);
  }

  return controller;
}

// ---------------------------------------------------------------------------
// Full-page YouTube player (landscape fullscreen, Online Classes screen)
// ---------------------------------------------------------------------------

class VideoPlayerPage extends StatefulWidget {
  final String youtubeUrl;
  final String videoTitle;

  const VideoPlayerPage({
    super.key,
    required this.youtubeUrl,
    required this.videoTitle,
  });

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasAttemptedFallback = false;
  String? _errorMessage;
  late final String _videoId;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _videoId = extractYoutubeVideoId(widget.youtubeUrl);
    debugPrint('╔══════════════════════════════════════╗');
    debugPrint('║  [YTPlayer] VideoPlayerPage init     ║');
    debugPrint('╠══════════════════════════════════════╣');
    debugPrint('║  Raw URL  : ${widget.youtubeUrl}');
    debugPrint('║  Video ID : $_videoId');
    debugPrint('╚══════════════════════════════════════╝');

    _controller = _buildController(
      videoId: _videoId,
      onPageStarted: (_) {},
      onPageFinished: (_) {
        if (mounted) setState(() => _isLoading = false);
      },
      onError: (msg) {
        if (mounted) setState(() => _errorMessage = msg);
      },
      onYtEvent: (msg) {
        if (msg.contains('[PLAYER_ERROR]')) {
          if (!_hasAttemptedFallback) {
            _hasAttemptedFallback = true;
            debugPrint(
                '[YTPlayer] Error detected ($msg), attempting direct embed fallback...');
            _controller.loadRequest(
              Uri.parse(
                'https://www.youtube-nocookie.com/embed/$_videoId?autoplay=1&playsinline=1&rel=0&controls=1',
              ),
            );
          } else if (mounted) {
            setState(() => _errorMessage = msg);
          }
        }
      },
    );
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            SizedBox.expand(child: WebViewWidget(controller: _controller)),
            if (_isLoading) _LoadingIndicator(),
            if (_errorMessage != null)
              _ErrorOverlay(
                message: _errorMessage!,
                videoId: _videoId,
                onRetry: () {
                  setState(() {
                    _errorMessage = null;
                    _isLoading = true;
                    _hasAttemptedFallback = false;
                  });
                  _controller.loadHtmlString(
                    _buildYtApiHtml(_videoId),
                    baseUrl: 'https://www.youtube-nocookie.com',
                  );
                },
              ),
            Positioned(
              top: 8,
              left: 8,
              child: _BackButton(onPressed: () => Navigator.of(context).pop()),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Inline YouTube player (portrait + landscape, Tools page)
// ---------------------------------------------------------------------------

void showYoutubePlayerDialog(BuildContext context, String videoId) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (context) => YoutubePlayerScreen(videoId: videoId),
    ),
  );
}

class YoutubePlayerScreen extends StatefulWidget {
  final String videoId;
  const YoutubePlayerScreen({super.key, required this.videoId});

  @override
  State<YoutubePlayerScreen> createState() => _YoutubePlayerScreenState();
}

class _YoutubePlayerScreenState extends State<YoutubePlayerScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _isFullscreen = false;
  bool _hasAttemptedFallback = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    debugPrint('╔══════════════════════════════════════╗');
    debugPrint('║  [YTPlayer] YoutubePlayerScreen init ║');
    debugPrint('║  Video ID : ${widget.videoId}');
    debugPrint('╚══════════════════════════════════════╝');

    _controller = _buildController(
      videoId: widget.videoId,
      onPageStarted: (_) {},
      onPageFinished: (_) {
        if (mounted) setState(() => _isLoading = false);
      },
      onError: (msg) {
        if (mounted) setState(() => _errorMessage = msg);
      },
      onYtEvent: (msg) {
        if (msg.contains('[PLAYER_ERROR]')) {
          if (!_hasAttemptedFallback) {
            _hasAttemptedFallback = true;
            debugPrint(
                '[YTPlayer] Error detected ($msg), attempting direct embed fallback...');
            _controller.loadRequest(
              Uri.parse(
                'https://www.youtube-nocookie.com/embed/${widget.videoId}?autoplay=1&playsinline=1&rel=0&controls=1',
              ),
            );
          } else if (mounted) {
            setState(() => _errorMessage = msg);
          }
        }
      },
    );
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _toggleFullscreen() {
    setState(() => _isFullscreen = !_isFullscreen);
    if (_isFullscreen) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final showFullscreen = _isFullscreen || isLandscape;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: showFullscreen
          ? null
          : AppBar(
              backgroundColor: const Color(0xFF0D0D0D),
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
              title: const Text(
                'YouTube',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              actions: [
                IconButton(
                  icon: Icon(
                    _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                    color: Colors.white,
                  ),
                  onPressed: _toggleFullscreen,
                ),
              ],
            ),
      body: Stack(
        children: [
          showFullscreen
              ? SizedBox.expand(child: WebViewWidget(controller: _controller))
              : Center(
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: WebViewWidget(controller: _controller),
                  ),
                ),
          if (_isLoading) _LoadingIndicator(),
          if (_errorMessage != null)
            _ErrorOverlay(
              message: _errorMessage!,
              videoId: widget.videoId,
              onRetry: () {
                setState(() {
                  _errorMessage = null;
                  _isLoading = true;
                  _hasAttemptedFallback = false;
                });
                _controller.loadHtmlString(
                  _buildYtApiHtml(widget.videoId),
                  baseUrl: 'https://www.youtube-nocookie.com',
                );
              },
            ),
          if (showFullscreen)
            Positioned(
              top: 8,
              left: 8,
              child: _BackButton(
                onPressed: () {
                  if (_isFullscreen) {
                    _toggleFullscreen();
                  } else {
                    Navigator.of(context).pop();
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared UI helpers
// ---------------------------------------------------------------------------

class _LoadingIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(
          color: Color(0xFFFF0000), strokeWidth: 3),
    );
  }
}

class _ErrorOverlay extends StatelessWidget {
  final String message;
  final String videoId;
  final VoidCallback onRetry;

  const _ErrorOverlay({
    required this.message,
    required this.videoId,
    required this.onRetry,
  });

  Future<void> _openExternal() async {
    final uri = Uri.parse('https://www.youtube.com/watch?v=$videoId');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                color: Color(0xFFFF0000), size: 56),
            const SizedBox(height: 16),
            const Text(
              'Playback Error',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white12,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Retry'),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF0000),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  onPressed: _openExternal,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Open in YouTube'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _BackButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.55),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24, width: 1),
          ),
          child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}
