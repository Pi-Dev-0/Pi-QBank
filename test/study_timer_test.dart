import 'package:flutter_test/flutter_test.dart';
import 'package:pi_qbank/services/study_timer_service.dart';

void main() {
  group('StudyTimerRecord', () {
    test('serialization and deserialization work correctly', () {
      final start = DateTime(2026, 10, 8, 10, 0);
      final end = DateTime(2026, 10, 8, 11, 30);
      final record = StudyTimerRecord(
        id: 'rec_1',
        startedAt: start,
        endedAt: end,
        subject: 'Mathematics',
        note: 'Chapter 2 Trigonometry',
      );

      final json = record.toJson();
      expect(json['id'], 'rec_1');
      expect(json['startedAt'], start.millisecondsSinceEpoch);
      expect(json['endedAt'], end.millisecondsSinceEpoch);
      expect(json['subject'], 'Mathematics');
      expect(json['note'], 'Chapter 2 Trigonometry');

      final deserialized = StudyTimerRecord.fromJson(json);
      expect(deserialized.id, 'rec_1');
      expect(deserialized.startedAt, start);
      expect(deserialized.endedAt, end);
      expect(deserialized.duration, const Duration(minutes: 90));
      expect(deserialized.subject, 'Mathematics');
      expect(deserialized.note, 'Chapter 2 Trigonometry');
    });

    test('handles legacy JSON without id or note', () {
      final json = {
        'startedAt': 1760000000000,
        'endedAt': 1760003600000,
      };
      final record = StudyTimerRecord.fromJson(json);
      expect(record.id, '1760000000000');
      expect(record.subject, isNull);
      expect(record.note, isNull);
      expect(record.duration, const Duration(seconds: 3600));
    });
  });

  group('StudyTimerService analytics', () {
    test('formatDuration formats appropriately', () {
      expect(StudyTimerService.formatDuration(const Duration(seconds: 45)), '45s');
      expect(StudyTimerService.formatDuration(const Duration(minutes: 25)), '25m');
      expect(StudyTimerService.formatDuration(const Duration(hours: 2, minutes: 15)), '2h 15m');
      expect(StudyTimerService.formatDuration(const Duration(hours: 3)), '3h');
    });

    test('formatStopwatch formats HH:MM:SS', () {
      expect(
        StudyTimerService.formatStopwatch(const Duration(hours: 1, minutes: 5, seconds: 9)),
        '01:05:09',
      );
    });

    test('calculateCurrentStreak detects today and prior consecutive days', () {
      final now = DateTime(2026, 10, 8, 15, 0); // Thursday
      final records = [
        // Today (Oct 8)
        StudyTimerRecord(
          id: '1',
          startedAt: DateTime(2026, 10, 8, 9, 0),
          endedAt: DateTime(2026, 10, 8, 10, 0),
        ),
        // Yesterday (Oct 7)
        StudyTimerRecord(
          id: '2',
          startedAt: DateTime(2026, 10, 7, 9, 0),
          endedAt: DateTime(2026, 10, 7, 10, 0),
        ),
        // Oct 6
        StudyTimerRecord(
          id: '3',
          startedAt: DateTime(2026, 10, 6, 9, 0),
          endedAt: DateTime(2026, 10, 6, 10, 0),
        ),
        // Oct 4 (gap on Oct 5)
        StudyTimerRecord(
          id: '4',
          startedAt: DateTime(2026, 10, 4, 9, 0),
          endedAt: DateTime(2026, 10, 4, 10, 0),
        ),
      ];

      final streak = StudyTimerService.calculateCurrentStreak(records, now);
      expect(streak, 3); // Oct 8, 7, 6
    });

    test('calculateCurrentStreak counts yesterday if today has not studied yet', () {
      final now = DateTime(2026, 10, 8, 8, 0); // Thursday morning, no study yet today
      final records = [
        // Yesterday (Oct 7)
        StudyTimerRecord(
          id: '1',
          startedAt: DateTime(2026, 10, 7, 14, 0),
          endedAt: DateTime(2026, 10, 7, 15, 0),
        ),
        // Day before (Oct 6)
        StudyTimerRecord(
          id: '2',
          startedAt: DateTime(2026, 10, 6, 14, 0),
          endedAt: DateTime(2026, 10, 6, 15, 0),
        ),
      ];

      final streak = StudyTimerService.calculateCurrentStreak(records, now);
      expect(streak, 2);
    });

    test('calculateLongestStreak finds historical maximum streak', () {
      final records = [
        // 4 day run
        StudyTimerRecord(id: '1', startedAt: DateTime(2026, 9, 1), endedAt: DateTime(2026, 9, 1, 1)),
        StudyTimerRecord(id: '2', startedAt: DateTime(2026, 9, 2), endedAt: DateTime(2026, 9, 2, 1)),
        StudyTimerRecord(id: '3', startedAt: DateTime(2026, 9, 3), endedAt: DateTime(2026, 9, 3, 1)),
        StudyTimerRecord(id: '4', startedAt: DateTime(2026, 9, 4), endedAt: DateTime(2026, 9, 4, 1)),
        // Gap
        StudyTimerRecord(id: '5', startedAt: DateTime(2026, 9, 10), endedAt: DateTime(2026, 9, 10, 1)),
        StudyTimerRecord(id: '6', startedAt: DateTime(2026, 9, 11), endedAt: DateTime(2026, 9, 11, 1)),
      ];

      expect(StudyTimerService.calculateLongestStreak(records), 4);
    });

    test('getTimeOfDayBreakdown partitions hours accurately', () {
      final records = [
        // Morning (08:00)
        StudyTimerRecord(
          id: '1',
          startedAt: DateTime(2026, 10, 8, 8, 0),
          endedAt: DateTime(2026, 10, 8, 9, 0),
        ),
        // Afternoon (14:00)
        StudyTimerRecord(
          id: '2',
          startedAt: DateTime(2026, 10, 8, 14, 0),
          endedAt: DateTime(2026, 10, 8, 14, 30),
        ),
        // Evening (19:00)
        StudyTimerRecord(
          id: '3',
          startedAt: DateTime(2026, 10, 8, 19, 0),
          endedAt: DateTime(2026, 10, 8, 20, 0),
        ),
        // Night (22:00)
        StudyTimerRecord(
          id: '4',
          startedAt: DateTime(2026, 10, 8, 22, 0),
          endedAt: DateTime(2026, 10, 8, 23, 0),
        ),
      ];

      final breakdown = StudyTimerService.getTimeOfDayBreakdown(records);
      expect(breakdown['Morning'], const Duration(hours: 1));
      expect(breakdown['Afternoon'], const Duration(minutes: 30));
      expect(breakdown['Evening'], const Duration(hours: 1));
      expect(breakdown['Night'], const Duration(hours: 1));
    });
  });
}
