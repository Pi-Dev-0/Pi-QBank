import 'package:flutter_test/flutter_test.dart';

import 'package:pi_qbank/utils/pdf_column_layout.dart';

/// A question must not be torn across a column boundary.
///
/// Balancing individual fragments is optimal for height, but it puts the last
/// sub-part of a question at the top of the next column. The reader then sees
/// `1. (ক) … (খ) …` at the foot of one column and a bare `(গ)` starting the
/// next, which reads as a question of its own.
void main() {
  List<PdfFlowFragment> makeFragments(int count, double stem, double part) {
    final out = <PdfFlowFragment>[];
    for (var q = 0; q < count; q++) {
      out.add(PdfFlowFragment(
        height: stem,
        question: q,
        indexInQuestion: 0,
        isFirst: true,
        isLast: false,
      ));
      for (var p = 1; p <= 3; p++) {
        out.add(PdfFlowFragment(
          height: part,
          question: q,
          indexInQuestion: p,
          isFirst: false,
          isLast: p == 3,
        ));
      }
    }
    return out;
  }

  group('a question stays whole within a column', () {
    test('no column boundary falls inside a question', () {
      for (final columns in [2, 3, 4]) {
        for (final stem in [40.0, 90.0, 160.0]) {
          for (final part in [20.0, 55.0]) {
            final fragments = makeFragments(11, stem, part);
            final groups =
                balanceQuestions(fragments: fragments, columns: columns);

            // A column holds several questions — that is the point of
            // columns. What it must not do is hold *part* of one.
            for (final column in groups) {
              final questions =
                  column.map((i) => fragments[i].question).toList();
              // Non-decreasing: a question's own fragments sit together, so
              // equal neighbours are expected and a smaller one is not.
              for (var i = 1; i < questions.length; i++) {
                expect(questions[i], greaterThanOrEqualTo(questions[i - 1]),
                    reason: '$columns cols, stem $stem, part $part: '
                        'questions out of order in a column');
              }
            }

            // Every question lands wholly in one column.
            final where = <int, int>{};
            for (var c = 0; c < groups.length; c++) {
              for (final i in groups[c]) {
                final q = fragments[i].question;
                expect(where.putIfAbsent(q, () => c), c,
                    reason: 'question $q is split across columns');
              }
            }
            expect(where.length, 11,
                reason: 'columns=$columns stem=$stem part=$part');
          }
        }
      }
    });

    test('every fragment is placed exactly once, in order', () {
      final fragments = makeFragments(11, 90, 55);
      final groups = balanceQuestions(fragments: fragments, columns: 2);
      final flat = [for (final c in groups) ...c];

      expect(flat, List.generate(fragments.length, (i) => i));
    });

    test('questions still run top to bottom within a column', () {
      final fragments = makeFragments(11, 90, 55);
      final groups = balanceQuestions(fragments: fragments, columns: 2);

      // Column 0 must carry earlier questions than column 1.
      final firstInColumn = groups
          .where((c) => c.isNotEmpty)
          .map((c) => fragments[c.first].question);
      final seen = firstInColumn.toList();
      for (var i = 1; i < seen.length; i++) {
        expect(seen[i], greaterThan(seen[i - 1]),
            reason: 'a later question cannot start above an earlier one');
      }
    });

    test('a single question uses one column, not one fragment per column', () {
      final fragments = makeFragments(1, 40, 20);
      final groups = balanceQuestions(fragments: fragments, columns: 3);
      expect(groups.where((c) => c.isNotEmpty), hasLength(1));
    });

    test('columns are still balanced', () {
      final fragments = makeFragments(12, 90, 55);
      final heights = [for (final f in fragments) f.height];
      final groups = balanceQuestions(fragments: fragments, columns: 2);

      final totals = [
        for (final c in groups) c.fold<double>(0, (m, i) => m + heights[i])
      ];
      final tallest = totals.reduce((a, b) => a > b ? a : b);
      final shortest = totals.reduce((a, b) => a < b ? a : b);

      // Whole questions cannot be shared, so the two columns need not be equal,
      // but they must not drift apart either.
      expect(tallest - shortest, lessThan(tallest * 0.5));
    });

    test('the packer splits questions across pages, not across columns', () {
      final flow = PdfPageFlow(contentHeight: 300, margin: 0);
      final rows = flow.layoutFragments(
        fragments: makeFragments(14, 60, 35),
        columns: 2,
      );

      // Within a page, no question is torn between its two columns. A column
      // may hold several questions — that is what columns are for.
      for (final row in rows) {
        final where = <int, int>{};
        for (var c = 0; c < row.length; c++) {
          for (final f in row[c]) {
            expect(where.putIfAbsent(f.question, () => c), c,
                reason: 'question ${f.question} spans two columns');
          }
        }
      }
    });
  });
}
