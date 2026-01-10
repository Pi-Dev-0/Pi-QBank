import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:pi_qbank/config/app_config.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:pi_qbank/widgets/loading_widget.dart';
import 'package:crypto/crypto.dart';
import 'package:intl/intl.dart';

class AdsterraService {
  static List<String> _adUrls = [];
  static int _currentIndex = 0;

  static String _generateToken() {
    final now = DateTime.now().toUtc();
    final timeStr = DateFormat('yyyyMMddHHmm').format(now);
    final secret = AppConfig.adSecret;
    final bytes = utf8.encode(secret + timeStr);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  static Future<void> _fetchAdUrls() async {
    if (_adUrls.isNotEmpty) return;

    try {
      if (AppConfig.adApi.isEmpty) {
        return;
      }

      final token = _generateToken();
      final baseUri = Uri.parse(AppConfig.adApi);

      // Preserve existing query parameters if any, and add token
      final queryParams = Map<String, dynamic>.from(baseUri.queryParameters);
      queryParams['token'] = token;

      final uri = baseUri.replace(queryParameters: queryParams);

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map && data['urls'] != null && data['urls'] is List) {
          _adUrls = List<String>.from(data['urls']);
        } else if (data is List) {
          _adUrls = List<String>.from(data);
        }
      }
    } catch (e) {
      //Use debugprint to view output
    }
  }

  static String? get _adUrl {
    if (_adUrls.isEmpty) return null;
    return _adUrls[_currentIndex % _adUrls.length];
  }

  static void _nextUrl() {
    if (_adUrls.length > 1) {
      _currentIndex = (_currentIndex + 1) % _adUrls.length;
    }
  }

  static Widget showAd() {
    return const _GlobalAdWidget();
  }

  static Future<bool> showAdDialog(BuildContext context) async {
    try {
      await _fetchAdUrls();

      // Fix for use_build_context_synchronously
      if (!context.mounted) return false;

      // If no ad URLs are available, just return true to allow the action
      if (_adUrls.isEmpty) {
        
        return true;
      }

      return await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            useSafeArea: false,
            builder: (BuildContext dialogContext) {
              return const _AdDialogContent();
            },
          ) ??
          false;
    } catch (e) {
      //debugprint to view output
      return true;
    }
  }
}

class _AdDialogContent extends StatefulWidget {
  const _AdDialogContent();

  @override
  State<_AdDialogContent> createState() => _AdDialogContentState();
}

class _AdDialogContentState extends State<_AdDialogContent> {
  late final WebViewController _controller;
  bool _isLoading = true;
  int _countdown = 5;
  bool _canDownload = false;
  int _retryCount = 0;

  @override
  void initState() {
    super.initState();
    _initController();
    _startCountdown();
  }

  void _initController() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setUserAgent('Mozilla/5.0');
    _loadAd();
  }

  void _loadAd() {
    final currentUrl = AdsterraService._adUrl;
    if (currentUrl == null) {
      if (mounted) Navigator.of(context).pop(true);
      return;
    }

    _controller.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) {
            setState(() => _isLoading = false);
          }
        },
        onWebResourceError: (error) {

          if (_retryCount < AdsterraService._adUrls.length) {
            _retryCount++;
            AdsterraService._nextUrl();
            _loadAd();
          } else {
            // If all retries fail, allow the user to continue anyway
            if (mounted) {
              setState(() {
                _isLoading = false;
                _canDownload = true;
              });
            }
          }
        },
      ),
    );
    _controller.loadRequest(Uri.parse(currentUrl));
  }

  void _startCountdown() {
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      if (_countdown > 0) {
        setState(() => _countdown--);
        _startCountdown();
      } else {
        setState(() => _canDownload = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Material(
        child: Stack(
          children: [
            Column(
              children: [
                Container(
                  height: 60,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Theme.of(context).primaryColor,
                        Theme.of(context).primaryColor.withOpacity(0.8),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12.0),
                      child: const Text(
                        'Advertisement',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      WebViewWidget(controller: _controller),
                      if (_isLoading)
                        const LoadingWidget(
                          loadingText: 'Loading Advertisement...',
                        ),
                    ],
                  ),
                ),
              ],
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0),
                      Colors.black.withOpacity(0.7),
                    ],
                  ),
                ),
                padding: const EdgeInsets.all(16),
                child: SafeArea(
                  child: ElevatedButton(
                    onPressed: _canDownload
                        ? () => Navigator.of(context).pop(true)
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _canDownload ? Colors.green : Colors.grey,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: _canDownload ? 8 : 0,
                    ),
                    child: Text(
                      _canDownload
                          ? 'Continue to Download'
                          : 'Wait $_countdown seconds...',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlobalAdWidget extends StatefulWidget {
  const _GlobalAdWidget();

  @override
  State<_GlobalAdWidget> createState() => _GlobalAdWidgetState();
}

class _GlobalAdWidgetState extends State<_GlobalAdWidget> {
  WebViewController? _controller;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  int _retryCount = 0;

  Future<void> _initController() async {
    await AdsterraService._fetchAdUrls();
    final url = AdsterraService._adUrl;
    if (url == null) return;

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..enableZoom(false)
      ..setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (error) {
            //debugprint to view output
            if (_retryCount < AdsterraService._adUrls.length) {
              _retryCount++;
              AdsterraService._nextUrl();
              final nextUrl = AdsterraService._adUrl;
              if (nextUrl != null) {
                _controller?.loadRequest(Uri.parse(nextUrl));
              }
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(url));

    if (mounted) {
      setState(() {
        _controller = controller;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null) return const SizedBox.shrink();

    return Opacity(
      opacity: 0.01,
      child: IgnorableSizedBox(
        height: 1,
        width: 1,
        child: WebViewWidget(controller: _controller!),
      ),
    );
  }
}

class IgnorableSizedBox extends StatelessWidget {
  final double width;
  final double height;
  final Widget child;

  const IgnorableSizedBox({
    super.key,
    required this.width,
    required this.height,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: width,
        height: height,
        child: child,
      ),
    );
  }
}
