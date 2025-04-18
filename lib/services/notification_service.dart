import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';

class AppNotification {
  final String id;
  final String title;
  final String subtitle;
  final String description;
  final DateTime timestamp;
  bool seen;

  AppNotification({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.timestamp,
    this.seen = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'description': description,
        'timestamp': timestamp.toIso8601String(),
        'seen': seen,
      };

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'],
        title: json['title'],
        subtitle: json['subtitle'],
        description: json['description'],
        timestamp: DateTime.parse(json['timestamp']),
        seen: json['seen'] ?? false,
      );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppNotification &&
        title.trim() == other.title.trim() &&
        subtitle.trim() == other.subtitle.trim() &&
        description.trim() == other.description.trim();
  }

  @override
  int get hashCode =>
      Object.hash(title.trim(), subtitle.trim(), description.trim());
}

class NotificationService {
  static final String _scriptUrl = AppConfig.notificationApi;
  static const String _notificationsKey = 'notifications_data';
  static const int _maxNotifications = 15;

  static List<AppNotification> _cachedNotifications = [];
  static bool _initialFetchDone = false;

  static Future<List<AppNotification>> fetchNotifications() async {
    // Return cached notifications if initial fetch is done
    if (_initialFetchDone) {
      return _cachedNotifications;
    }

    try {
      final response = await http.get(Uri.parse(_scriptUrl));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<AppNotification> apiNotifications = [];

        // Load existing notifications to preserve seen status
        final existingNotifications = await _loadStoredNotifications();
        final existingMap = {for (var n in existingNotifications) n.id: n.seen};

        for (var n in data['notifications'] as List) {
          final notification = AppNotification(
            id: n['id'] ?? DateTime.now().toString(),
            title: n['title'],
            subtitle: n['subtitle'],
            description: n['description'] ?? '',
            timestamp: n['timestamp'] != null
                ? DateTime.parse(n['timestamp'])
                : DateTime.now(),
            seen: existingMap[n['id']] ?? false,
          );
          apiNotifications.add(notification);
        }

        await _storeNotifications(apiNotifications);
        _initialFetchDone = true; // Mark initial fetch as complete
        return _cachedNotifications;
      }
    } catch (e) {
      debugPrint('API fetch error: $e');
    }

    // Load from storage and mark initial fetch as done
    final stored = await _loadStoredNotifications();
    _initialFetchDone = true;
    return stored;
  }

  static Future<void> _storeNotifications(
      List<AppNotification> notifications) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Convert to set to remove duplicates while preserving seen status
      final uniqueNotifications = notifications.toSet().toList();

      // Sort by timestamp
      uniqueNotifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      // Take only the maximum allowed
      final limitedNotifications =
          uniqueNotifications.take(_maxNotifications).toList();

      // Store as single JSON string
      final notificationsMap = {
        'notifications': limitedNotifications.map((n) => n.toJson()).toList(),
        'lastUpdated': DateTime.now().toIso8601String(),
      };

      await prefs.setString(_notificationsKey, jsonEncode(notificationsMap));
      _cachedNotifications = limitedNotifications;
    } catch (e) {
      debugPrint('Storage error: $e');
    }
  }

  static Future<List<AppNotification>> _loadStoredNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedData = prefs.getString(_notificationsKey);

      if (storedData != null) {
        final data = jsonDecode(storedData) as Map<String, dynamic>;
        final notifications = (data['notifications'] as List)
            .map((n) => AppNotification.fromJson(n as Map<String, dynamic>))
            .toList();
        _cachedNotifications = notifications;
        return notifications;
      }
    } catch (e) {
      debugPrint('Load error: $e');
    }
    return [];
  }

  static Future<void> markNotificationAsSeen(
      AppNotification notification) async {
    notification.seen = true;
    await _storeNotifications(_cachedNotifications);
  }

  static Future<void> markAllAsSeen() async {
    for (var notification in _cachedNotifications) {
      notification.seen = true;
    }
    await _storeNotifications(_cachedNotifications);
  }

  static bool isNotificationUnseen(AppNotification notification) {
    return !notification.seen;
  }

  static Future<bool> hasUnseenNotifications() async {
    final notifications = await _loadStoredNotifications();
    return notifications.any((notification) => !notification.seen);
  }

  // Add method to reset fetch state if needed
  static void resetFetchState() {
    _initialFetchDone = false;
  }
}
