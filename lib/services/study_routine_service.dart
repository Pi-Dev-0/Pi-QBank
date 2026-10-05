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

  static Future<void> saveRoutine(List<StudySession> sessions) async {
    final encoded =
        jsonEncode(sessions.map((session) => session.toJson()).toList());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(routineKey, encoded);
    try {
      await _channel.invokeMethod<void>('syncRoutine', encoded);
      if (sessions.isNotEmpty) {
        await _channel.invokeMethod<void>('requestNotificationPermission');
      }
    } on MissingPluginException {
      // Android handles the home-screen widget and scheduled notifications.
    } on PlatformException {
      // Saving the routine remains available if notification access is denied.
    }
  }
}
