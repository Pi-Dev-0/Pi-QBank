import 'package:flutter_test/flutter_test.dart';
import 'package:pi_qbank/models/highschool_question.dart';

/// Mirrors readExistingIds() in google_apps_script/HighSchool_QBank_Script.js.
Set<String> readExistingIds(List<String?> columnA) {
  final ids = <String>{};
  for (final cell in columnA) {
    final v = (cell ?? '').trim();
    if (v.isNotEmpty) ids.add(v.toLowerCase());
  }
  return ids;
}

/// Mirrors the duplicate-id check in doPost: returns the offending ids.
List<String> findDuplicates(
  List<Map<String, dynamic>> questions,
  List<String?> sheetIds,
) {
  final existing = readExistingIds(sheetIds);
  final seen = <String, bool>{};
  final duplicates = <String>[];

  for (final q in questions) {
    final raw = ((q['id'] ?? '') as String).trim();
    if (raw.isEmpty) continue; // server generates one

    final key = raw.toLowerCase();
    if (seen.containsKey(key)) {
      duplicates.add('$raw (repeated in this upload)');
      continue;
    }
    seen[key] = true;
    if (existing.contains(key)) duplicates.add('$raw (already in sheet)');
  }
  return duplicates;
}

Map<String, dynamic> q({String id = ''}) => {
      'id': id,
      'class': 'Class (9-10) SSC',
      'subject': 'উচ্চতর গণিত',
      'chapter_number': '1',
      'chapter_name': 'সেট',
      'question_type': 'CQ',
      'stem_text': 'A = {1,2,3}',
      'stem_image_url': '',
      'sub_questions_json': [
        {'label': 'ক', 'mark': 1, 'text': 'a'}
      ],
      'board_year_tag': '',
    };

void main() {
  group('question id handling', () {
    final sheet = ['id-1', 'id-2', 'a3b4c5d6-1111-2222-3333-444455556666'];

    test('a fresh batch is accepted', () {
      expect(findDuplicates([q(id: 'new-a'), q(id: 'new-b')], sheet), isEmpty);
    });

    test('re-uploading the same queue is rejected', () {
      // This is the case the whole change is about: a double-click or a
      // retried request must not create duplicate rows.
      final d = findDuplicates([q(id: 'id-1'), q(id: 'new-a')], sheet);
      expect(d, hasLength(1));
      expect(d.first, contains('already in sheet'));
    });

    test('an id repeated inside one batch is rejected', () {
      final d = findDuplicates([q(id: 'dup'), q(id: 'DUP')], sheet);
      expect(d, hasLength(1));
      expect(d.first, contains('repeated in this upload'));
    });

    test('collision detection is case-insensitive', () {
      expect(findDuplicates([q(id: 'ID-1')], sheet), hasLength(1));
    });

    test('omitted or blank ids are left for the server to generate', () {
      expect(findDuplicates([q(), q(id: '   '), q(id: 'fresh')], sheet), isEmpty);
    });

    test('a blank sheet has no ids to collide with', () {
      expect(findDuplicates([q(id: 'id-1')], const []), isEmpty);
    });

    test('empty cells in the sheet are ignored', () {
      expect(readExistingIds([null, '', '  ', 'x']), {'x'});
    });
  });

  group('duplicate ids cannot merge two questions in the UI', () {
    // _expandedCards is keyed per question; a shared key would make tapping one
    // row toggle another. These rows are hand-editable in the Sheet, so the
    // client has to cope with ids that are not unique.
    HighSchoolQuestion row(String id, String stem) =>
        HighSchoolQuestion.fromJson({
          'id': id,
          'class': 'Class (9-10) SSC',
          'subject': 'উচ্চতর গণিত',
          'chapter_number': '1',
          'chapter_name': 'সেট',
          'question_type': 'CQ',
          'stem_text': stem,
          'stem_image_url': '',
          'sub_questions_json': [
            {'label': 'ক', 'mark': 1, 'text': 'a'}
          ],
          'board_year_tag': '',
        });

    test('two questions sharing an id stay distinct', () {
      final a = row('same-id', 'প্রথম প্রশ্ন');
      final b = row('same-id', 'দ্বিতীয় প্রশ্ন');
      expect(a.id, b.id);

      // Mirrors _cardKey(): fall back to a composite when the id repeats.
      final counts = <String, int>{};
      for (final r in [a, b]) {
        counts[r.id] = (counts[r.id] ?? 0) + 1;
      }
      final dupes = {
        for (final e in counts.entries)
          if (e.value > 1) e.key
      };
      String cardKey(HighSchoolQuestion r, int i) =>
          r.id.isNotEmpty && !dupes.contains(r.id)
              ? r.id
              : '~${r.className}|${r.subject}|${r.chapterNumber}|'
                  '${r.chapterName}|${r.questionType}|${r.stemText}|$i';

      final keyA = cardKey(a, 0);
      final keyB = cardKey(b, 1);
      expect(keyA, isNot(keyB));
    });

    test('unique ids are used directly', () {
      final a = row('a', 'প্রথম');
      final b = row('b', 'দ্বিতীয়');
      expect(a.id, isNot(b.id));
    });
  });
}
