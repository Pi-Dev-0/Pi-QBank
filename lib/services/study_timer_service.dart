import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StudyTimerRecord {
  const StudyTimerRecord({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    this.subject,
    this.note,
  });

  final String id;
  final DateTime startedAt;
  final DateTime endedAt;
  final String? subject;
  final String? note;

  Duration get duration => endedAt.difference(startedAt);

  Map<String, dynamic> toJson() => {
        'id': id,
        'startedAt': startedAt.millisecondsSinceEpoch,
        'endedAt': endedAt.millisecondsSinceEpoch,
        'durationMs': duration.inMilliseconds,
        if (subject != null && subject!.trim().isNotEmpty)
          'subject': subject!.trim(),
        if (note != null && note!.trim().isNotEmpty) 'note': note!.trim(),
      };

  factory StudyTimerRecord.fromJson(Map<String, dynamic> json) {
    final startedAtEpoch = json['startedAt'] as int;
    final endedAtEpoch = json['endedAt'] as int;
    return StudyTimerRecord(
      id: json['id'] as String? ?? startedAtEpoch.toString(),
      startedAt: DateTime.fromMillisecondsSinceEpoch(startedAtEpoch),
      endedAt: DateTime.fromMillisecondsSinceEpoch(endedAtEpoch),
      subject: json['subject'] as String?,
      note: json['note'] as String?,
    );
  }
}

class DailyStudyTotal {
  const DailyStudyTotal({
    required this.date,
    required this.total,
    required this.sessionCount,
  });

  final DateTime date;
  final Duration total;
  final int sessionCount;
}

class StudyTimerSnapshot {
  const StudyTimerSnapshot({
    required this.isRunning,
    required this.todayElapsed,
    required this.segmentStart,
    required this.activeSubject,
    required this.dailyGoalMinutes,
    required this.history,
  });

  final bool isRunning;
  final Duration todayElapsed;
  final DateTime? segmentStart;
  final String activeSubject;
  final int dailyGoalMinutes;
  final List<StudyTimerRecord> history;

  Duration computeCurrentDuration([DateTime? now]) {
    final current = now ?? DateTime.now();
    if (!isRunning || segmentStart == null) {
      return todayElapsed;
    }
    final segment = current.isAfter(segmentStart!)
        ? current.difference(segmentStart!)
        : Duration.zero;
    return todayElapsed + segment;
  }
}

class StudyTimerService {
  static const historyKey = 'study_timer_history_v1';
  static const runningKey = 'study_timer_running';
  static const elapsedKey = 'study_timer_elapsed_ms';
  static const segmentStartKey = 'study_timer_segment_start_epoch';
  static const runStartKey = 'study_timer_run_start_epoch';
  static const dayKey = 'study_timer_day_key';
  static const dailyGoalKey = 'study_timer_daily_goal_minutes';
  static const activeSubjectKey = 'study_timer_active_subject';

  static const int defaultDailyGoalMinutes = 120; // 2 hours default
  static const String defaultSubject = 'General Study';

  static const List<String> suggestedSubjects = [
    'General Study',
    'Mathematics',
    'Higher Math',
    'Physics',
    'Chemistry',
    'Biology',
    'English',
    'Bangla',
    'ICT',
    'Exam Prep',
    'Revision',
  ];

  static const _channel =
      MethodChannel('com.pi.mathematics/study_timer_widget');

  static Future<void> refreshWidget() async {
    try {
      await _channel.invokeMethod<void>('refresh');
    } on MissingPluginException {
      // Android home screen widget refresh is optional on non-Android platforms.
    } on PlatformException {
      // Ignore platform exceptions
    }
  }

  static String formatDayKey(DateTime time) =>
      DateFormat('yyyy-MM-dd').format(time);

  static Future<void> _ensureCurrentDay(
      SharedPreferences prefs, DateTime now) async {
    final todayKey = formatDayKey(now);
    final storedKey = prefs.getString(dayKey);
    if (storedKey == null) {
      await prefs.setString(dayKey, todayKey);
      return;
    }
    if (storedKey == todayKey) return;

    // Day rollover: if running, archive segment to midnight of stored day
    final running = prefs.getBool(runningKey) ?? false;
    if (running) {
      final startEpoch = prefs.getInt(segmentStartKey) ?? now.millisecondsSinceEpoch;
      final start = DateTime.fromMillisecondsSinceEpoch(startEpoch);
      final midnight = DateTime(start.year, start.month, start.day + 1);
      final segmentEnd = midnight.isBefore(now) ? midnight : now;
      if (segmentEnd.isAfter(start)) {
        await _appendRecord(
          prefs,
          StudyTimerRecord(
            id: startEpoch.toString(),
            startedAt: start,
            endedAt: segmentEnd,
            subject: prefs.getString(activeSubjectKey) ?? defaultSubject,
          ),
        );
      }
    }

    await prefs.setBool(runningKey, false);
    await prefs.setInt(elapsedKey, 0);
    await prefs.setString(dayKey, todayKey);
    await prefs.remove(segmentStartKey);
    await prefs.remove(runStartKey);
  }

  static Future<StudyTimerSnapshot> loadSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    await _ensureCurrentDay(prefs, now);

    final isRunning = prefs.getBool(runningKey) ?? false;
    final elapsedMs = prefs.getInt(elapsedKey) ?? 0;
    final segmentStartEpoch = prefs.getInt(segmentStartKey);
    final segmentStart = segmentStartEpoch != null
        ? DateTime.fromMillisecondsSinceEpoch(segmentStartEpoch)
        : null;
    final activeSubject =
        prefs.getString(activeSubjectKey) ?? defaultSubject;
    final dailyGoalMinutes =
        prefs.getInt(dailyGoalKey) ?? defaultDailyGoalMinutes;

    final history = await loadHistory(prefs: prefs);

    return StudyTimerSnapshot(
      isRunning: isRunning,
      todayElapsed: Duration(milliseconds: elapsedMs < 0 ? 0 : elapsedMs),
      segmentStart: segmentStart,
      activeSubject: activeSubject,
      dailyGoalMinutes: dailyGoalMinutes,
      history: history,
    );
  }

  static Future<List<StudyTimerRecord>> loadHistory({
    SharedPreferences? prefs,
  }) async {
    final p = prefs ?? await SharedPreferences.getInstance();
    final raw = p.getString(historyKey) ?? '[]';
    final records = <StudyTimerRecord>[];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          records.add(StudyTimerRecord.fromJson(item));
        }
      }
    } catch (_) {
      // Fallback for malformed history
    }
    records.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return records;
  }

  static Future<void> _appendRecord(
      SharedPreferences prefs, StudyTimerRecord record) async {
    final history = await loadHistory(prefs: prefs);
    // Avoid exact duplicate IDs
    history.removeWhere((r) => r.id == record.id);
    history.insert(0, record);
    // Cap at last 500 records
    final capped = history.take(500).map((r) => r.toJson()).toList();
    await prefs.setString(historyKey, jsonEncode(capped));
  }

  static Future<void> startTimer({String? subject}) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    await _ensureCurrentDay(prefs, now);

    final wasRunning = prefs.getBool(runningKey) ?? false;
    if (wasRunning) return;

    final nowMs = now.millisecondsSinceEpoch;
    final currentElapsed = prefs.getInt(elapsedKey) ?? 0;

    await prefs.setBool(runningKey, true);
    await prefs.setInt(segmentStartKey, nowMs);
    await prefs.setString(dayKey, formatDayKey(now));
    if (currentElapsed == 0) {
      await prefs.setInt(runStartKey, nowMs);
    }
    if (subject != null && subject.trim().isNotEmpty) {
      await prefs.setString(activeSubjectKey, subject.trim());
    }

    await refreshWidget();
  }

  static Future<void> pauseTimer() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    await _ensureCurrentDay(prefs, now);

    final wasRunning = prefs.getBool(runningKey) ?? false;
    if (!wasRunning) return;

    final nowMs = now.millisecondsSinceEpoch;
    final segmentStartMs = prefs.getInt(segmentStartKey) ?? nowMs;
    final segmentEndMs = nowMs >= segmentStartMs ? nowMs : segmentStartMs;
    final segmentDurationMs = segmentEndMs - segmentStartMs;

    if (segmentDurationMs > 0) {
      final subject = prefs.getString(activeSubjectKey) ?? defaultSubject;
      final record = StudyTimerRecord(
        id: segmentStartMs.toString(),
        startedAt: DateTime.fromMillisecondsSinceEpoch(segmentStartMs),
        endedAt: DateTime.fromMillisecondsSinceEpoch(segmentEndMs),
        subject: subject,
      );
      await _appendRecord(prefs, record);
    }

    final currentElapsed = prefs.getInt(elapsedKey) ?? 0;
    await prefs.setBool(runningKey, false);
    await prefs.setInt(elapsedKey, currentElapsed + segmentDurationMs);
    await prefs.remove(segmentStartKey);

    await refreshWidget();
  }

  static Future<void> resetTodayTimer() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final wasRunning = prefs.getBool(runningKey) ?? false;

    if (wasRunning) {
      await pauseTimer();
    }

    await prefs.setInt(elapsedKey, 0);
    await prefs.remove(runStartKey);
    await prefs.setString(dayKey, formatDayKey(now));

    await refreshWidget();
  }

  static Future<void> addManualSession({
    required DateTime startedAt,
    required DateTime endedAt,
    String? subject,
    String? note,
  }) async {
    if (!endedAt.isAfter(startedAt)) return;
    final prefs = await SharedPreferences.getInstance();
    final record = StudyTimerRecord(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      startedAt: startedAt,
      endedAt: endedAt,
      subject: (subject != null && subject.trim().isNotEmpty)
          ? subject.trim()
          : defaultSubject,
      note: note,
    );

    await _appendRecord(prefs, record);

    // If recorded today, update today's elapsed time as well
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    if (startedAt.isAfter(todayStart) && startedAt.isBefore(todayEnd)) {
      final currentElapsed = prefs.getInt(elapsedKey) ?? 0;
      await prefs.setInt(
          elapsedKey, currentElapsed + record.duration.inMilliseconds);
    }

    await refreshWidget();
  }

  static Future<void> deleteSession(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final history = await loadHistory(prefs: prefs);
    final targetIndex = history.indexWhere((r) => r.id == id);
    if (targetIndex == -1) return;

    final target = history.removeAt(targetIndex);
    final capped = history.take(500).map((r) => r.toJson()).toList();
    await prefs.setString(historyKey, jsonEncode(capped));

    // If session was from today, decrement today's elapsed time
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    if (target.startedAt.isAfter(todayStart) &&
        target.startedAt.isBefore(todayEnd)) {
      final currentElapsed = prefs.getInt(elapsedKey) ?? 0;
      final newElapsed =
          (currentElapsed - target.duration.inMilliseconds).clamp(0, 0x7fffffffffffffff);
      await prefs.setInt(elapsedKey, newElapsed);
    }

    await refreshWidget();
  }

  static Future<void> clearAllHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(historyKey, '[]');
    await prefs.setInt(elapsedKey, 0);
    await prefs.setBool(runningKey, false);
    await prefs.remove(segmentStartKey);
    await prefs.remove(runStartKey);

    await refreshWidget();
  }

  static Future<void> setDailyGoalMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(dailyGoalKey, minutes);
  }

  static Future<void> setActiveSubject(String subject) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(activeSubjectKey, subject.trim());
  }

  // --- Analytics & Statistics Calculations ---

  static Duration totalDuration(Iterable<StudyTimerRecord> records) =>
      records.fold(
        Duration.zero,
        (total, record) => total + record.duration,
      );

  static Duration totalInRange(
    Iterable<StudyTimerRecord> records,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) {
    return records.fold(Duration.zero, (total, record) {
      final start = record.startedAt.isAfter(rangeStart)
          ? record.startedAt
          : rangeStart;
      final end =
          record.endedAt.isBefore(rangeEnd) ? record.endedAt : rangeEnd;
      return end.isAfter(start) ? total + end.difference(start) : total;
    });
  }

  static int calculateCurrentStreak(
    List<StudyTimerRecord> records, [
    DateTime? referenceDate,
  ]) {
    final now = referenceDate ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Group study durations by day date string
    final dayTotals = <String, int>{};
    for (final r in records) {
      final key = formatDayKey(r.startedAt);
      dayTotals[key] = (dayTotals[key] ?? 0) + r.duration.inSeconds;
    }

    int streak = 0;
    DateTime checkDay = today;

    // If today hasn't recorded study yet, check if yesterday had a streak
    final todayKey = formatDayKey(today);
    final todaySeconds = dayTotals[todayKey] ?? 0;

    if (todaySeconds > 0) {
      streak++;
      checkDay = today.subtract(const Duration(days: 1));
    } else {
      // Check yesterday
      checkDay = today.subtract(const Duration(days: 1));
    }

    while (true) {
      final key = formatDayKey(checkDay);
      final seconds = dayTotals[key] ?? 0;
      if (seconds > 0) {
        streak++;
        checkDay = checkDay.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }

    return streak;
  }

  static int calculateLongestStreak(List<StudyTimerRecord> records) {
    if (records.isEmpty) return 0;
    final dayTotals = <DateTime, int>{};
    for (final r in records) {
      final day = DateTime(r.startedAt.year, r.startedAt.month, r.startedAt.day);
      dayTotals[day] = (dayTotals[day] ?? 0) + r.duration.inSeconds;
    }

    final activeDays = dayTotals.entries
        .where((e) => e.value > 0)
        .map((e) => e.key)
        .toList()
      ..sort();

    if (activeDays.isEmpty) return 0;

    int maxStreak = 1;
    int currentStreak = 1;

    for (int i = 1; i < activeDays.length; i++) {
      final prev = activeDays[i - 1];
      final curr = activeDays[i];
      if (curr.difference(prev).inDays == 1) {
        currentStreak++;
        if (currentStreak > maxStreak) {
          maxStreak = currentStreak;
        }
      } else if (curr.difference(prev).inDays > 1) {
        currentStreak = 1;
      }
    }

    return maxStreak;
  }

  static List<DailyStudyTotal> getDailyTotals(
    Iterable<StudyTimerRecord> records,
    DateTime startDate,
    int daysCount,
  ) {
    final now = DateTime.now();
    return List.generate(daysCount, (index) {
      final date = startDate.add(Duration(days: index));
      final dayStart = DateTime(date.year, date.month, date.day);
      final nextDay = dayStart.add(const Duration(days: 1));
      final rangeEnd = nextDay.isBefore(now) ? nextDay : now;

      final dayRecords = records.where((r) =>
          r.startedAt.isAfter(dayStart.subtract(const Duration(seconds: 1))) &&
          r.startedAt.isBefore(nextDay));

      return DailyStudyTotal(
        date: dayStart,
        total: totalInRange(records, dayStart, rangeEnd),
        sessionCount: dayRecords.length,
      );
    });
  }

  static Map<String, Duration> getTimeOfDayBreakdown(
    Iterable<StudyTimerRecord> records,
  ) {
    int morningSeconds = 0; // 06:00 - 12:00
    int afternoonSeconds = 0; // 12:00 - 17:00
    int eveningSeconds = 0; // 17:00 - 21:00
    int nightSeconds = 0; // 21:00 - 06:00

    for (final record in records) {
      final hour = record.startedAt.hour;
      final sec = record.duration.inSeconds;
      if (hour >= 6 && hour < 12) {
        morningSeconds += sec;
      } else if (hour >= 12 && hour < 17) {
        afternoonSeconds += sec;
      } else if (hour >= 17 && hour < 21) {
        eveningSeconds += sec;
      } else {
        nightSeconds += sec;
      }
    }

    return {
      'Morning': Duration(seconds: morningSeconds),
      'Afternoon': Duration(seconds: afternoonSeconds),
      'Evening': Duration(seconds: eveningSeconds),
      'Night': Duration(seconds: nightSeconds),
    };
  }

  static Map<String, Duration> getSubjectBreakdown(
    Iterable<StudyTimerRecord> records,
  ) {
    final map = <String, Duration>{};
    for (final r in records) {
      final subj = (r.subject != null && r.subject!.isNotEmpty)
          ? r.subject!
          : defaultSubject;
      map[subj] = (map[subj] ?? Duration.zero) + r.duration;
    }
    return map;
  }

  static String formatDuration(
    Duration duration, {
    bool showSeconds = false,
  }) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      if (minutes > 0) {
        return '${hours}h ${minutes}m';
      }
      return '${hours}h';
    }
    if (minutes > 0) {
      if (showSeconds && seconds > 0) {
        return '${minutes}m ${seconds}s';
      }
      return '${minutes}m';
    }
    return '${seconds}s';
  }

  static String formatStopwatch(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes.remainder(60)).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds.remainder(60)).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }
}
