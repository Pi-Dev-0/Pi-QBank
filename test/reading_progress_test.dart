import 'package:flutter_test/flutter_test.dart';
import 'package:pi_qbank/services/reading_progress_service.dart';

void main() {
  group('ReadingProgress model and range calculations', () {
    test('defaults startPage to 1 when not specified', () {
      final book = ReadingProgress(
        id: '1',
        title: 'Book A',
        currentPage: 25,
        totalPages: 100,
        lastReadAt: DateTime.now(),
      );

      expect(book.startPage, 1);
      expect(book.progress, 0.25);
    });

    test('calculates progress accurately with custom page range', () {
      final bookAtStart = ReadingProgress(
        id: '2',
        title: 'Volume 2',
        startPage: 150,
        currentPage: 150,
        totalPages: 350,
        lastReadAt: DateTime.now(),
      );
      // At start page: 0% of range
      expect(bookAtStart.progress, 0.0);

      final bookMidway = ReadingProgress(
        id: '2',
        title: 'Volume 2',
        startPage: 150,
        currentPage: 250,
        totalPages: 350,
        lastReadAt: DateTime.now(),
      );
      // (250 - 150) / (350 - 150) = 100 / 200 = 0.5 (50%)
      expect(bookMidway.progress, 0.5);

      final bookComplete = ReadingProgress(
        id: '2',
        title: 'Volume 2',
        startPage: 150,
        currentPage: 350,
        totalPages: 350,
        lastReadAt: DateTime.now(),
      );
      expect(bookComplete.progress, 1.0);
    });

    test('handles null and edge case total pages', () {
      final bookWithoutTotal = ReadingProgress(
        id: '3',
        title: 'Infinite Book',
        startPage: 50,
        currentPage: 60,
        totalPages: null,
        lastReadAt: DateTime.now(),
      );
      expect(bookWithoutTotal.progress, isNull);

      final bookEqualStartAndEnd = ReadingProgress(
        id: '4',
        title: 'Single Page Excerpt',
        startPage: 100,
        currentPage: 100,
        totalPages: 100,
        lastReadAt: DateTime.now(),
      );
      expect(bookEqualStartAndEnd.progress, 1.0);
    });

    test('serializes and deserializes startPage with JSON', () {
      final now = DateTime(2026, 10, 6, 16, 0);
      final original = ReadingProgress(
        id: '5',
        title: 'Advanced Calculus',
        startPage: 80,
        currentPage: 120,
        totalPages: 400,
        lastReadAt: now,
      );

      final json = original.toJson();
      expect(json['startPage'], 80);

      final parsed = ReadingProgress.fromJson(json);
      expect(parsed.startPage, 80);
      expect(parsed.currentPage, 120);
      expect(parsed.totalPages, 400);
      expect(parsed.title, 'Advanced Calculus');
    });

    test('backward compatibility: handles JSON without startPage field', () {
      final legacyJson = {
        'id': 'legacy-1',
        'title': 'Old Book',
        'currentPage': 42,
        'totalPages': 200,
        'lastReadAt': '2026-10-06T12:00:00.000Z',
      };

      final parsed = ReadingProgress.fromJson(legacyJson);
      expect(parsed.startPage, 1);
      expect(parsed.currentPage, 42);
      expect(parsed.totalPages, 200);
      expect(parsed.progress, 0.21);
    });
  });
}
