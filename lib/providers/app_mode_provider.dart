import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppModeProvider extends ChangeNotifier {
  bool _isOfflineMode = false;
  static const String _offlineModeKey = 'offline_mode';

  bool get isOfflineMode => _isOfflineMode;

  AppModeProvider() {
    _loadOfflineMode();
  }

  Future<void> _loadOfflineMode() async {
    final prefs = await SharedPreferences.getInstance();
    _isOfflineMode = prefs.getBool(_offlineModeKey) ?? false;
    notifyListeners();
  }

  Future<void> toggleOfflineMode() async {
    _isOfflineMode = !_isOfflineMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_offlineModeKey, _isOfflineMode);
    notifyListeners();
  }

  Future<void> setOnlineMode() async {
    if (_isOfflineMode) {
      _isOfflineMode = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_offlineModeKey, false);
      notifyListeners();
    }
  }
} 