import 'package:flutter_test/flutter_test.dart';
import 'package:pi_qbank/services/study_routine_service.dart';

void main() {
  test('compareByCurrentTime sorts active first then upcoming', () {
    final now = DateTime(2026, 10, 6, 14, 25); // Tuesday 14:25
    final s1 = const StudySession(
      id: "1",
      subject: "Math",
      startMinute: 14 * 60,
      endMinute: 15 * 60,
      weekdays: [2],
    ); // Active now
    final s2 = const StudySession(
      id: "2",
      subject: "Physics",
      startMinute: 15 * 60,
      endMinute: 16 * 60,
      weekdays: [2],
    ); // Later today
    final s3 = const StudySession(
      id: "3",
      subject: "Chem",
      startMinute: 10 * 60,
      endMinute: 11 * 60,
      weekdays: [2],
    ); // Ended earlier today

    final list = [s3, s2, s1];
    list.sort((a, b) => StudyRoutineService.compareByCurrentTime(a, b, now));
    expect(list.map((s) => s.subject).toList(), ['Math', 'Physics', 'Chem']);

    final nowLater = DateTime(2026, 10, 6, 15, 30); // Tuesday 15:30
    list.sort((a, b) => StudyRoutineService.compareByCurrentTime(a, b, nowLater));
    expect(list.map((s) => s.subject).toList(), ['Physics', 'Chem', 'Math']);
  });
}
