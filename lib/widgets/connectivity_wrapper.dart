import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_mode_provider.dart';
import '../services/connectivity_service.dart';

class ConnectivityWrapper extends StatefulWidget {
  final Widget child;

  const ConnectivityWrapper({
    super.key,
    required this.child,
  });

  static void showOnRetry(BuildContext context) {
    final connectivityService =
        Provider.of<ConnectivityService>(context, listen: false);
    final appMode = Provider.of<AppModeProvider>(context, listen: false);

    if (!connectivityService.isOnline && !appMode.isOfflineMode) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha:0.1),
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
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(120, 40),
                ),
                child: const Text('Close'),
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  await connectivityService.initConnectivity();
                },
              ),
            ],
          );
        },
      );
    }
  }

  @override
  State<ConnectivityWrapper> createState() => _ConnectivityWrapperState();
}

class _ConnectivityWrapperState extends State<ConnectivityWrapper> {
  bool _isDialogShowing = false;
  DateTime? _lastOnlineSwitch;
  bool _hasShownDialog = false;
  final navigatorKey = GlobalKey<NavigatorState>();

  void _showNoInternetDialog(BuildContext context) {
    if (!mounted ||
        _isDialogShowing ||
        _hasShownDialog ||
        Provider.of<AppModeProvider>(context, listen: false).isOfflineMode) {
      return;
    }

    _isDialogShowing = true;
    _hasShownDialog = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha:0.1),
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
            'This app works best with an active internet connection. \nPlease connect to the Internet.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actionsPadding: const EdgeInsets.symmetric(vertical: 16),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                minimumSize: const Size(120, 40),
              ),
              child: const Text('Close'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                if (mounted) {
                  setState(() {
                    _isDialogShowing = false;
                  });
                }
              },
            ),
          ],
        );
      },
    ).then((_) {
      if (mounted) {
        setState(() {
          _isDialogShowing = false;
        });
      }
    });
  }

  void _closeNoInternetDialog(BuildContext context) {
    if (_isDialogShowing) {
      Navigator.of(context).pop();
      if (mounted) {
        setState(() {
          _isDialogShowing = false;
        });
      }
    }
  }

  void _showOnlineModeSnackBar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Internet connection restored. Switched to online mode.',
          style: TextStyle(color: Colors.white),
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      onGenerateRoute: (settings) => MaterialPageRoute(
        builder: (context) => Consumer2<ConnectivityService, AppModeProvider>(
          builder: (context, connectivity, appMode, _) {
            // Reset the flag when internet is restored
            if (connectivity.isOnline) {
              _hasShownDialog = false;
              if (_isDialogShowing) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _closeNoInternetDialog(context);
                });
              }

              if (appMode.isOfflineMode) {
                final now = DateTime.now();
                if (_lastOnlineSwitch == null ||
                    now.difference(_lastOnlineSwitch!) >
                        const Duration(seconds: 5)) {
                  _lastOnlineSwitch = now;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      appMode.setOnlineMode();
                      _showOnlineModeSnackBar(context);
                    }
                  });
                }
              }
            }

            // Show dialog only if we're not in offline mode and there's no internet
            if (!appMode.isOfflineMode &&
                !connectivity.isOnline &&
                !_isDialogShowing &&
                !_hasShownDialog) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _showNoInternetDialog(context);
              });
            }

            return widget.child;
          },
        ),
      ),
    );
  }
}
