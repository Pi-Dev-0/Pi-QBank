import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class AdsterraService {
  static const String _adUrl =
      'https://www.profitableratecpm.com/anpzahxh0?key=c1bc8b96c1d495394e6f6f52d9722d62';
  static WebViewController? _controller;

  static Widget showAd() {
    try {
      _controller ??= WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0x00000000))
        ..enableZoom(false)
        ..loadRequest(Uri.parse(_adUrl));

      return Opacity(
        opacity: 0.01,
        child: SizedBox(
          height: 1,
          width: 1,
          child: WebViewWidget(controller: _controller!),
        ),
      );
    } catch (e) {
      debugPrint('AdsterraService initialization error: $e');
      return const SizedBox.shrink();
    }
  }

  static Future<bool> showAdDialog(BuildContext context) async {
    try {
      bool isLoading = true;
      int countdown = 5;
      bool canDownload = false;

      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.white)
        ..setUserAgent('Mozilla/5.0')
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (_) => debugPrint('Loading ad...'),
            onPageFinished: (_) => isLoading = false,
          ),
        )
        ..loadRequest(Uri.parse(_adUrl));

      return await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            useSafeArea: false, // Make it truly fullscreen
            builder: (BuildContext dialogContext) {
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
                                  Theme.of(context)
                                      .primaryColor
                                      .withOpacity(0.8),
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
                                margin: const EdgeInsets.only(top: 26.0),
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
                                WebViewWidget(controller: controller),
                                StatefulBuilder(
                                  builder: (context, setState) {
                                    controller.setNavigationDelegate(
                                      NavigationDelegate(
                                        onPageFinished: (_) {
                                          setState(() => isLoading = false);
                                        },
                                      ),
                                    );

                                    if (isLoading) {
                                      return Container(
                                        color: Colors.white,
                                        child: Center(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const CircularProgressIndicator(),
                                              const SizedBox(height: 20),
                                              Text(
                                                'Loading Advertisement...',
                                                style: TextStyle(
                                                  color: Theme.of(context)
                                                      .primaryColor,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }
                                    return const SizedBox.shrink();
                                  },
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
                            child: StatefulBuilder(
                              builder: (context, setState) {
                                if (!canDownload) {
                                  Future.delayed(const Duration(seconds: 1),
                                      () {
                                    if (countdown > 0) {
                                      setState(() => countdown--);
                                    } else {
                                      setState(() => canDownload = true);
                                    }
                                  });
                                }

                                return ElevatedButton(
                                  onPressed: canDownload
                                      ? () =>
                                          Navigator.of(dialogContext).pop(true)
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: canDownload
                                        ? Colors.green
                                        : Colors.grey,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: canDownload ? 8 : 0,
                                  ),
                                  child: Text(
                                    canDownload
                                        ? 'Continue to Download'
                                        : 'Wait $countdown seconds...',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ) ??
          false;
    } catch (e) {
      debugPrint('AdsterraService dialog error: $e');
      return true;
    }
  }
}
