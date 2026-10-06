import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StudySession {
  const StudySession({
    required this.id,
    required this.subject,
    required this.startMinute,
    required this.endMinute,
    required this.weekdays,
  });

  final String id;
  final String subject;
  final int startMinute;
  final int endMinute;
  final List<int> weekdays;

  Map<String, dynamic> toJson() => {
        'id': id,
        'subject': subject,
        'startMinute': startMinute,
        'endMinute': endMinute,
        'weekdays': weekdays,
      };

  factory StudySession.fromJson(Map<String, dynamic> json) => StudySession(
        id: json['id'] as String,
        subject: json['subject'] as String,
        startMinute: json['startMinute'] as int,
        endMinute: json['endMinute'] as int,
        weekdays: (json['weekdays'] as List).cast<int>(),
      );
}

class StudyRoutineService {
  static const routineKey = 'study_routine_v1';
  static const _channel = MethodChannel('com.pi.mathematics/study_routine');

  static int compareByCurrentTime(
    StudySession first,
    StudySession second, [
    DateTime? referenceTime,
  ]) {
    final now = referenceTime ?? DateTime.now();
    final firstActive = _isActive(first, now);
    final secondActive = _isActive(second, now);
    if (firstActive != secondActive) return firstActive ? -1 : 1;
    if (firstActive) {
      final byStart = first.startMinute.compareTo(second.startMinute);
      if (byStart != 0) return byStart;
    }

    final firstNext = _nextStart(first, now);
    final secondNext = _nextStart(second, now);
    final byNextStart =
        (firstNext?.millisecondsSinceEpoch ?? 0x7fffffffffffffff).compareTo(
      secondNext?.millisecondsSinceEpoch ?? 0x7fffffffffffffff,
    );
    if (byNextStart != 0) return byNextStart;
    final byStart = first.startMinute.compareTo(second.startMinute);
    return byStart != 0 ? byStart : first.id.compareTo(second.id);
  }

  static bool isSessionActive(StudySession session, [DateTime? referenceTime]) {
    return _isActive(session, referenceTime ?? DateTime.now());
  }

  static Future<void> refreshWidget() async {
    try {
      await _channel.invokeMethod<void>('refreshWidget');
    } on MissingPluginException {
      // Android handles the home-screen widget.
    } on PlatformException {
      // Ignored
    }
  }

  static bool _isActive(StudySession session, DateTime now) {
    final start = session.startMinute;
    final end = session.endMinute;
    if (start < 0 || start > 1439 || end < 0 || end > 1439 || start == end) {
      return false;
    }
    final minute = now.hour * 60 + now.minute;
    final yesterday =
        now.weekday == DateTime.monday ? DateTime.sunday : now.weekday - 1;
    if (end > start) {
      return session.weekdays.contains(now.weekday) &&
          minute >= start &&
          minute < end;
    }
    return (session.weekdays.contains(now.weekday) && minute >= start) ||
        (session.weekdays.contains(yesterday) && minute < end);
  }

  static DateTime? _nextStart(StudySession session, DateTime now) {
    final start = session.startMinute;
    if (start < 0 || start > 1439) return null;
    for (var offset = 0; offset <= 7; offset++) {
      final day = DateTime(now.year, now.month, now.day + offset);
      final occursOnDay = session.weekdays.isEmpty
          ? offset == 0
          : session.weekdays.contains(day.weekday);
      if (!occursOnDay) continue;
      final candidate = DateTime(
        day.year,
        day.month,
        day.day,
        start ~/ 60,
        start % 60,
      );
      if (candidate.isAfter(now)) return candidate;
    }
    return null;
  }

  static Future<List<StudySession>> loadRoutine() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(routineKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((item) => StudySession.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<bool> saveRoutine(List<StudySession> sessions) async {
    final encoded =
        jsonEncode(sessions.map((session) => session.toJson()).toList());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(routineKey, encoded);
    try {
      await _channel.invokeMethod<void>('syncRoutine', encoded);
      if (sessions.isNotEmpty) {
        var overlayAllowed = false;
        try {
          overlayAllowed =
              await _channel.invokeMethod<bool>('requestOverlayPermission') ??
                  false;
        } on PlatformException {
          // Standard notification reminders remain available as a fallback.
        }
        try {
          await _channel.invokeMethod<void>('requestNotificationPermission');
        } on PlatformException {
          // The routine remains saved if notification access is denied.
        }
        return overlayAllowed;
      }
      return true;
    } on MissingPluginException {
      // Android handles the home-screen widget and scheduled notifications.
      return false;
    } on PlatformException {
      // Saving the routine remains available if notification access is denied.
      return false;
    }
  }
}
