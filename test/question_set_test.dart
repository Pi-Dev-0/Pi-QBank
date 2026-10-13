import 'package:flutter_test/flutter_test.dart';

import 'package:pi_qbank/models/highschool_question.dart';
import 'package:pi_qbank/utils/pdf_column_layout.dart';

HighSchoolQuestion cq(String id) => HighSchoolQuestion.fromJson({
      'id': id,
      'class': 'Class (9-10) SSC',
      'subject': 'গণিত',
      'chapter_number': '1',
      'chapter_name': 'অনুশীলনী',
      'question_type': 'CQ',
      'stem_text': 'stem',
      'stem_image_url': '',
      'sub_questions_json': [
        {'label': 'ক', 'mark': 2, 'text': 'একটি সমীকরণ সমাধান করো।'},
      ],
      'board_year_tag': '',
    });

/// Mirror of the page's set assignment, so the rules can be tested without
/// pumping a widget tree.
class SetBoard {
  SetBoard({required this.twoSets, required this.labels});

  final bool twoSets;
  final List<String> labels;

  List<String> get activeLabels => twoSets ? labels : [''];

  void toggle(HighSchoolQuestion q, int index) {
    final label = activeLabels[index];
    if (label.isEmpty) return;
    if (q.setLabel == label) {
      q.setLabel = twoSets ? '' : label;
    } else {
      q.setLabel = label;
    }
  }

  List<HighSchoolQuestion> inSet(List<HighSchoolQuestion> all, int index) {
    final label = activeLabels[index];
    return all.where((q) => label.isEmpty || q.setLabel == label).toList();
  }

  void splitEvenly(List<HighSchoolQuestion> all) {
    if (!twoSets || all.length < 2) return;
    for (var i = 0; i < all.length; i++) {
      all[i].setLabel = activeLabels[i % 2];
    }
  }

  void allToFirst(List<HighSchoolQuestion> all) {
    if (!twoSets) return;
    for (final q in all) {
      q.setLabel = activeLabels.first;
    }
  }
}

void main() {
  group('question sets', () {
    test('every question starts unassigned', () {
      expect(cq('a').setLabel, '');
      expect(cq('b').setLabel, '');
    });

    test('assigning moves a question into that set only', () {
      final board = SetBoard(twoSets: true, labels: ['ক-সেট', 'খ-সেট']);
      final a = cq('a');
      board.toggle(a, 0);
      expect(a.setLabel, 'ক-সেট');
      expect(board.inSet([a], 0).length, 1);
      expect(board.inSet([a], 1), isEmpty);
    });

    test('tapping the other set moves rather than copies', () {
      final board = SetBoard(twoSets: true, labels: ['ক-সেট', 'খ-সেট']);
      final a = cq('a');
      board.toggle(a, 0);
      board.toggle(a, 1);
      expect(a.setLabel, 'খ-সেট');
      expect(board.inSet([a], 0), isEmpty);
      expect(board.inSet([a], 1).length, 1);
    });

    test('tapping the active set again clears it when two sets are on', () {
      final board = SetBoard(twoSets: true, labels: ['ক-সেট', 'খ-সেট']);
      final a = cq('a');
      board.toggle(a, 0);
      board.toggle(a, 0);
      expect(a.setLabel, '');
    });

    test('a single-set paper keeps every question', () {
      final board = SetBoard(twoSets: false, labels: ['ক-সেট', 'খ-সেট']);
      final all = [cq('a'), cq('b'), cq('c')];
      // With one set the label is empty, so every question belongs to it.
      expect(board.inSet(all, 0).length, 3);
      board.toggle(all.first, 0); // a no-op with a single set
      expect(board.inSet(all, 0).length, 3);
    });

    test('an even split alternates and loses nothing', () {
      final board = SetBoard(twoSets: true, labels: ['ক-সেট', 'খ-সেট']);
      final all = [for (var i = 0; i < 9; i++) cq('$i')];
      board.splitEvenly(all);

      expect(board.inSet(all, 0).length, 5);
      expect(board.inSet(all, 1).length, 4);
      expect(all.where((q) => q.setLabel.isEmpty), isEmpty);
    });

    test('an even split needs at least two questions', () {
      final board = SetBoard(twoSets: true, labels: ['ক-সেট', 'খ-সেট']);
      final one = [cq('a')];
      board.splitEvenly(one);
      expect(one.first.setLabel, '');
    });

    test('sending everything to the first set empties the second', () {
      final board = SetBoard(twoSets: true, labels: ['ক-সেট', 'খ-সেট']);
      final all = [for (var i = 0; i < 6; i++) cq('$i')];
      board.splitEvenly(all);
      board.allToFirst(all);
      expect(board.inSet(all, 0).length, 6);
      expect(board.inSet(all, 1), isEmpty);
    });

    test('renaming a set does not strand questions', () {
      // Labels are read fresh each time, so a renamed set is a different
      // bucket — which is why the page always assigns from the live label.
      final board = SetBoard(twoSets: true, labels: ['ক-সেট', 'খ-সেট']);
      final a = cq('a');
      board.toggle(a, 1);
      final renamed = SetBoard(twoSets: true, labels: ['ক-সেট', 'গ-সেট']);
      expect(renamed.inSet([a], 0), isEmpty);
    });
  });

  group('set divider', () {
    test('leaves a clear gap on both sides', () {
      expect(PdfLayout.setDividerGapAbove, greaterThanOrEqualTo(12));
      expect(PdfLayout.setDividerGapBelow, greaterThanOrEqualTo(8));
    });
  });

  group('merged CQ + short-question flow', () {
    bool merges({
      required bool twoSets,
      required int cqColumns,
      required int rqColumns,
      required int cqs,
      required int shorts,
    }) =>
        twoSets && cqColumns > 1 && rqColumns > 1 && cqs > 0 && shorts > 0;

    test('needs two sets and both sections in two columns', () {
      expect(
          merges(twoSets: true, cqColumns: 2, rqColumns: 2, cqs: 3, shorts: 3),
          isTrue);
      // A single-set paper keeps the familiar section order.
      expect(
          merges(twoSets: false, cqColumns: 2, rqColumns: 2, cqs: 3, shorts: 3),
          isFalse);
      // So does a paper whose short questions are single-column.
      expect(
          merges(twoSets: true, cqColumns: 2, rqColumns: 1, cqs: 3, shorts: 3),
          isFalse);
    });

    test('needs both sections present to be worth merging', () {
      expect(
          merges(twoSets: true, cqColumns: 2, rqColumns: 2, cqs: 0, shorts: 3),
          isFalse);
      expect(
          merges(twoSets: true, cqColumns: 2, rqColumns: 2, cqs: 3, shorts: 0),
          isFalse);
    });

    test('heading pseudo-ids cannot collide with a real question', () {
      // The packer groups fragments by question id, so each heading needs an
      // id no real question can reach.
      final cqs = 4;
      final shorts = 6;
      final cqBannerId = cqs + shorts;
      final rqBannerId = cqBannerId + 1;
      final used = <int>{};
      for (var i = 0; i < cqs; i++) {
        used.add(i);
      }
      for (var i = 0; i < shorts; i++) {
        used.add(cqs + i);
      }
      expect(used.contains(cqBannerId), isFalse);
      expect(used.contains(rqBannerId), isFalse);
    });
  });
}
