import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/connectivity_service.dart';
import '../providers/app_mode_provider.dart';

class ConnectionStatusBar extends StatelessWidget {
  const ConnectionStatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<ConnectivityService, AppModeProvider>(
      builder: (context, connectivity, appMode, child) {
        final isOnline = connectivity.isOnline;
        final isOfflineMode = appMode.isOfflineMode;

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
          color: isOfflineMode
              ? Colors.orange
              : isOnline
                  ? Colors.green
                  : Colors.red,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isOfflineMode
                    ? 'Offline Mode'
                    : isOnline
                        ? 'Online'
                        : 'No Internet Connection',
                style: const TextStyle(color: Colors.white),
              ),
              Switch(
                value: isOfflineMode,
                onChanged: (value) => appMode.toggleOfflineMode(),
                activeColor: Colors.white,
              ),
            ],
          ),
        );
      },
    );
  }
} 