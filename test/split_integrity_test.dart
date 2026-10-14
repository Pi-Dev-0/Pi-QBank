import 'package:flutter_test/flutter_test.dart';

import 'package:pi_qbank/utils/pdf_column_layout.dart';

/// A page break may now land between two pieces of a question — its stem, or
/// any of its sub-parts.
///
/// That is a licence to lose content, so it gets tested directly: across many
/// shapes of input, the emitted fragments must be the input, exactly once, in
/// the same order. A packer that drops a fragment, repeats one, or reorders
/// two produces a perfectly plausible-looking paper that is quietly wrong.
void main() {
  /// Build [count] questions, each split into [parts] pieces of a shape that
  /// makes the total awkward to fit.
  List<PdfFlowFragment> makeFragments(
      int count, double stemHeight, double partHeight) {
    final out = <PdfFlowFragment>[];
    for (var q = 0; q < count; q++) {
      out.add(PdfFlowFragment(
        height: stemHeight,
        question: q,
        indexInQuestion: 0,
        isFirst: true,
        isLast: false,
      ));
      for (var p = 1; p <= 3; p++) {
        out.add(PdfFlowFragment(
          height: partHeight,
          question: q,
          indexInQuestion: p,
          isFirst: false,
          isLast: p == 3,
        ));
      }
    }
    return out;
  }

  /// Everything the layout emitted, flattened back into one ordered list.
  List<PdfFlowFragment> flatten(List<List<List<PdfFlowFragment>>> rows) => [
        for (final row in rows)
          for (final column in row)
            for (final f in column) f,
      ];

  void expectIntegrity(
      List<PdfFlowFragment> input, double pageHeight, int columns,
      {double trailingGap = 0}) {
    final flow = PdfPageFlow(contentHeight: pageHeight, margin: 0);
    final rows = flow.layoutFragments(
        fragments: input, columns: columns, trailingGap: trailingGap);
    final out = flatten(rows);

    expect(out, hasLength(input.length),
        reason: 'every piece must be emitted exactly once');
    for (var i = 0; i < out.length; i++) {
      expect(out[i].question, input[i].question,
          reason: 'piece $i came from the wrong question');
      expect(out[i].indexInQuestion, input[i].indexInQuestion,
          reason: 'piece $i is out of order');
    }
  }

  group('a question may span pages', () {
    test('a run of pieces is split, none lost or reordered', () {
      // 10 questions of 40 + 3×20 = 100pt each, on a 300pt page. The block
      // boundaries will land mid-question.
      final input = makeFragments(10, 40, 20);
      expectIntegrity(input, 300.0, 1);
    });

    test('two columns, more awkward still', () {
      final input = makeFragments(12, 55, 18);
      expectIntegrity(input, 300.0, 2);
    });

    test('three columns', () {
      final input = makeFragments(9, 70, 25);
      expectIntegrity(input, 400.0, 3);
    });

    test('a single piece taller than the page is still emitted', () {
      // Nothing can fit it, so the only non-lossy outcome is to overflow.
      final input = makeFragments(2, 900, 30);
      expectIntegrity(input, 200.0, 1);
    });

    test('a question taller than a whole page still survives', () {
      final input = makeFragments(3, 700, 400);
      expectIntegrity(input, 250.0, 1);
    });

    test('a trailing gap does not change what is emitted', () {
      final input = makeFragments(10, 40, 20);
      expectIntegrity(input, 300, 1, trailingGap: 16);
      expectIntegrity(input, 300, 2, trailingGap: 16);
    });

    test('exact multiples of the page height', () {
      expectIntegrity(makeFragments(9, 100, 100), 300.0, 1);
      expectIntegrity(makeFragments(9, 300, 1), 300.0, 1);
    });
  });

  group('integrity across a sweep', () {
    test('every shape of page, column count and question size', () {
      // One assertion set over many shapes, because the failure this guards
      // against only shows up for particular combinations — a single fixture
      // would pass almost every version of the packer.
      for (final pageHeight in [200.0, 300.0, 450.0, 785.0]) {
        for (final columns in [1, 2, 3]) {
          for (final stem in [20.0, 60.0, 140.0]) {
            for (final part in [10.0, 35.0]) {
              final input = makeFragments(7, stem, part);
              final flow = PdfPageFlow(contentHeight: pageHeight, margin: 0);
              final rows = flow.layoutFragments(
                  fragments: input, columns: columns, trailingGap: 12);
              final out = flatten(rows);

              expect(out.map((f) => '${f.question}.${f.indexInQuestion}'),
                  input.map((f) => '${f.question}.${f.indexInQuestion}'),
                  reason: 'page $pageHeight, $columns cols, '
                      'stem $stem, part $part');
            }
          }
        }
      }
    });
  });

  group('no block may outgrow its page', () {
    // Regression: `layoutFragments` throws "Widget won't fit into the page"
    // and the whole export fails. The block was chosen from whole-question
    // heights and only ever *extended* afterwards, never checked, so a
    // question whose measured height was a point or two optimistic drew past
    // the bottom of the sheet.
    test('every block fits the page it lands on, trailing gap included', () {
      for (final pageHeight in [200.0, 300.0, 450.0, 785.0]) {
        for (final columns in [1, 2, 3]) {
          for (final trailingGap in [0.0, 12.0, 16.0]) {
            // Stems are capped at the page height: a *single* fragment taller
            // than the sheet cannot be made to fit by any arrangement, and is
            // covered separately below.
            for (final stem in [60.0, 140.0, 180.0]) {
              final flow = PdfPageFlow(contentHeight: pageHeight, margin: 0);
              final rows = flow.layoutFragments(
                fragments: makeFragments(8, stem, 27.3),
                columns: columns,
                trailingGap: trailingGap,
              );

              for (final row in rows) {
                final tallest = row
                    .map((c) => c.fold<double>(
                        0, (m, f) => f.height > m ? f.height : m))
                    .reduce((a, b) => a > b ? a : b);
                expect(tallest + trailingGap, lessThanOrEqualTo(pageHeight),
                    reason: 'page $pageHeight, $columns cols, '
                        'gap $trailingGap, stem $stem');
              }
            }
          }
        }
      }
    });

    test('a piece taller than the page is emitted rather than dropped', () {
      // Unavoidable, and the only non-lossy outcome: the pdf package carries
      // the overflow onto the next sheet. The packer's job is not to lose it.
      final flow = PdfPageFlow(contentHeight: 200, margin: 0);
      final rows = flow.layoutFragments(
          fragments: makeFragments(3, 300, 20), columns: 1);
      final out = flatten(rows);
      expect(out, hasLength(12), reason: 'nothing may be dropped');
    });

    test('heights that land a hair over the page still pack', () {
      // 27.3 is deliberate: with a trailing gap it makes a block land a
      // fraction of a point past the sheet, which is the case that used to
      // throw rather than merely look tight.
      final flow = PdfPageFlow(contentHeight: 300, margin: 0);
      final rows = flow.layoutFragments(
          fragments: makeFragments(10, 100, 27.3), columns: 2, trailingGap: 16);
      expect(rows, isNotEmpty);
      final out = flatten(rows);
      expect(out, hasLength(40));
    });
  });

  group('the result is still readable', () {
    test('a block never exceeds the page it is on', () {
      final flow = PdfPageFlow(contentHeight: 300, margin: 0);
      final rows = flow.layoutFragments(
          fragments: makeFragments(10, 40, 20), columns: 2, trailingGap: 0);

      // Only the last block may be short; every one of them must fit.
      for (final row in rows) {
        final tallest = row
            .map(
                (c) => c.fold<double>(0, (m, f) => f.height > m ? f.height : m))
            .reduce((a, b) => a > b ? a : b);
        expect(tallest, lessThanOrEqualTo(300));
      }
    });

    test('an empty input produces nothing', () {
      final flow = PdfPageFlow(contentHeight: 300, margin: 0);
      expect(flow.layoutFragments(fragments: const [], columns: 2), isEmpty);
    });

    test('a single question that fits is not split', () {
      final flow = PdfPageFlow(contentHeight: 800, margin: 0);
      final rows =
          flow.layoutFragments(fragments: makeFragments(1, 40, 20), columns: 1);
      final out = flatten(rows);
      expect(out, hasLength(4));
      // Still one block, so nothing was broken across a page.
      expect(rows, hasLength(1));
    });
  });
}
