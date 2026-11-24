import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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

  /// Stable identity used to deduplicate notifications that come back from
  /// the API with a different (or missing) id but the same content.
  String get contentKey =>
      '${title.trim()}|${subtitle.trim()}|${description.trim()}';

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
        id: (json['id'] ?? '').toString(),
        title: (json['title'] ?? 'Notification').toString(),
        subtitle: (json['subtitle'] ?? '').toString(),
        description: (json['description'] ?? '').toString(),
        timestamp: DateTime.tryParse((json['timestamp'] ?? '').toString()) ??
            DateTime.now(),
        seen: json['seen'] == true,
      );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppNotification && contentKey == other.contentKey;
  }

  @override
  int get hashCode => contentKey.hashCode;
}

class NotificationService {
  static final String _scriptUrl = AppConfig.notificationApi;
  static const String _notificationsKey = 'notifications_data';
  static const int _maxNotifications = 15;
  static const Duration _requestTimeout = Duration(seconds: 12);

  static List<AppNotification> _cachedNotifications = [];
  static bool _initialFetchDone = false;
  static Future<List<AppNotification>>? _inFlightFetch;

  /// Rebuilds listeners whenever the notification list changes. Both the bell
  /// badge and the open notification sheet listen to this.
  static final ValueNotifier<List<AppNotification>> notificationsListenable =
      ValueNotifier<List<AppNotification>>(const <AppNotification>[]);

  /// Number of notifications that have not been opened yet.
  static final ValueNotifier<int> unreadCountListenable = ValueNotifier<int>(0);

  static List<AppNotification> get notifications =>
      List<AppNotification>.unmodifiable(_cachedNotifications);

  static int get unreadCount =>
      _cachedNotifications.where((notification) => !notification.seen).length;

  /// Loads notifications from the API (or local storage as a fallback).
  ///
  /// Pass [forceRefresh] to bypass the in-memory cache. Concurrent calls share
  /// the same request so several app bars can never fire duplicate fetches.
  static Future<List<AppNotification>> fetchNotifications({
    bool forceRefresh = false,
  }) {
    if (_initialFetchDone && !forceRefresh) {
      _syncNotifiers();
      return Future<List<AppNotification>>.value(_cachedNotifications);
    }

    final inFlight = _inFlightFetch;
    if (inFlight != null) {
      return inFlight;
    }

    final future = _fetchNotifications();
    _inFlightFetch = future;
    future.then<void>(
      (_) {
        if (identical(_inFlightFetch, future)) {
          _inFlightFetch = null;
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (identical(_inFlightFetch, future)) {
          _inFlightFetch = null;
        }
      },
    );
    return future;
  }

  static Future<List<AppNotification>> _fetchNotifications() async {
    if (_scriptUrl.trim().isEmpty) {
      return _finishWithStoredNotifications();
    }

    try {
      final uri = Uri.tryParse(_scriptUrl);
      if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
        return _finishWithStoredNotifications();
      }

      final response = await http.get(uri).timeout(_requestTimeout);
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final rawNotifications =
            decoded is Map<String, dynamic> ? decoded['notifications'] : null;

        if (rawNotifications is List) {
          final existing = await _loadStoredNotifications();
          final seenById = <String, bool>{
            for (final notification in existing)
              notification.id: notification.seen,
          };
          final seenByContent = <String, bool>{
            for (final notification in existing)
              if (notification.seen) notification.contentKey: true,
          };

          final apiNotifications = <AppNotification>[];
          for (final item in rawNotifications) {
            if (item is! Map) continue;
            final map = Map<String, dynamic>.from(item);

            final title = (map['title'] ?? '').toString().trim();
            final subtitle = (map['subtitle'] ?? '').toString().trim();
            final description = (map['description'] ?? '').toString().trim();
            if (title.isEmpty && subtitle.isEmpty && description.isEmpty) {
              continue;
            }

            final rawId = (map['id'] ?? '').toString().trim();
            final id = rawId.isNotEmpty
                ? rawId
                : DateTime.now().microsecondsSinceEpoch.toString();
            final contentKey = '$title|$subtitle|$description';

            apiNotifications.add(
              AppNotification(
                id: id,
                title: title.isEmpty ? 'Notification' : title,
                subtitle: subtitle,
                description: description,
                timestamp:
                    DateTime.tryParse((map['timestamp'] ?? '').toString()) ??
                        DateTime.now(),
                // Preserve read state across refreshes, even when the API
                // changes the id of an existing notification.
                seen: seenById[id] ?? seenByContent[contentKey] ?? false,
              ),
            );
          }

          await _storeNotifications(apiNotifications);
          _initialFetchDone = true;
          _syncNotifiers();
          return _cachedNotifications;
        }
      }

      debugPrint(
        'Notification API returned ${response.statusCode}; using stored notifications.',
      );
    } catch (e) {
      debugPrint('API fetch error: $e');
    }

    return _finishWithStoredNotifications();
  }

  static Future<List<AppNotification>> _finishWithStoredNotifications() async {
    _cachedNotifications = await _loadStoredNotifications();
    _initialFetchDone = true;
    _syncNotifiers();
    return _cachedNotifications;
  }

  static Future<void> _storeNotifications(
    List<AppNotification> notifications,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Keep one entry per content and never lose a read state when a
      // duplicate arrives unread.
      final byContent = <String, AppNotification>{};
      for (final notification in notifications) {
        final existing = byContent[notification.contentKey];
        if (existing == null || (!existing.seen && notification.seen)) {
          byContent[notification.contentKey] = notification;
        }
      }

      final uniqueNotifications = byContent.values.toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      final limitedNotifications =
          uniqueNotifications.take(_maxNotifications).toList();

      final notificationsMap = {
        'notifications': limitedNotifications.map((n) => n.toJson()).toList(),
        'lastUpdated': DateTime.now().toIso8601String(),
      };

      await prefs.setString(_notificationsKey, jsonEncode(notificationsMap));
      _cachedNotifications = limitedNotifications;
      _syncNotifiers();
    } catch (e) {
      debugPrint('Storage error: $e');
    }
  }

  static Future<List<AppNotification>> _loadStoredNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedData = prefs.getString(_notificationsKey);

      if (storedData != null) {
        final decoded = jsonDecode(storedData);
        final rawNotifications =
            decoded is Map<String, dynamic> ? decoded['notifications'] : null;

        if (rawNotifications is List) {
          final notifications = <AppNotification>[];
          for (final item in rawNotifications) {
            if (item is! Map) continue;
            try {
              notifications.add(
                AppNotification.fromJson(Map<String, dynamic>.from(item)),
              );
            } catch (e) {
              debugPrint('Skipping invalid stored notification: $e');
            }
          }
          _cachedNotifications = notifications;
          return notifications;
        }
      }
    } catch (e) {
      debugPrint('Load error: $e');
    }

    _cachedNotifications = [];
    return const <AppNotification>[];
  }

  static Future<void> markNotificationAsSeen(
    AppNotification notification,
  ) async {
    var changed = !notification.seen;
    notification.seen = true;

    final matches = _cachedNotifications
        .where(
          (cached) =>
              cached.id == notification.id ||
              cached.contentKey == notification.contentKey,
        )
        .toList();

    for (final cached in matches) {
      if (!cached.seen) {
        cached.seen = true;
        changed = true;
      }
    }

    if (matches.isEmpty) {
      _cachedNotifications = [..._cachedNotifications, notification];
      changed = true;
    }

    if (!changed) {
      _syncNotifiers();
      return;
    }

    // Reflect the new read state immediately; persisting can happen after.
    _syncNotifiers();
    await _storeNotifications(_cachedNotifications);
  }

  static Future<void> markAllAsSeen() async {
    var changed = false;
    for (final notification in _cachedNotifications) {
      if (!notification.seen) {
        notification.seen = true;
        changed = true;
      }
    }

    if (!changed) return;

    // Reflect the new read state immediately; persisting can happen after.
    _syncNotifiers();
    await _storeNotifications(_cachedNotifications);
  }

  static bool isNotificationUnseen(AppNotification notification) {
    return !notification.seen;
  }

  static Future<bool> hasUnseenNotifications() async {
    if (!_initialFetchDone) {
      await fetchNotifications();
    }
    return _cachedNotifications.any((notification) => !notification.seen);
  }

  /// Allows the next [fetchNotifications] call to hit the API again.
  static void resetFetchState() {
    _initialFetchDone = false;
    _inFlightFetch = null;
  }

  static void _syncNotifiers() {
    notificationsListenable.value =
        List<AppNotification>.unmodifiable(_cachedNotifications);
    unreadCountListenable.value = unreadCount;
  }
}
