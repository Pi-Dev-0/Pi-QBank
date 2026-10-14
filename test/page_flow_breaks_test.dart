import 'package:flutter_test/flutter_test.dart';

import 'package:pi_qbank/utils/pdf_column_layout.dart';

/// How [PdfPageFlow] reports that it moved to a fresh page.
///
/// `used` alone cannot reveal a break: after one it reads the same as it would
/// on a single page. That matters because callers reason about the page as a
/// whole — a two-set paper once inserted a gap sized from the remainder, on the
/// strength of a `used` that silently described only the last sheet, and pushed
/// the second set onto a page of its own.
void main() {
  group('the flow reports a break honestly', () {
    test('pageBreaks counts each overflow from consume', () {
      final flow = PdfPageFlow(contentHeight: 100, margin: 0);
      flow.consume(60);
      expect(flow.pageBreaks, 0);
      flow.consume(60); // does not fit
      expect(flow.pageBreaks, 1);
      flow.consume(60);
      expect(flow.pageBreaks, 2);
    });

    test('used describes the current page, not the whole run', () {
      final flow = PdfPageFlow(contentHeight: 100, margin: 0);
      flow.consume(90);
      flow.consume(90);
      expect(flow.used, 90, reason: 'reset by the break');
      expect(flow.pageBreaks, 1);
    });

    test('a break inside layoutFragments is counted too', () {
      // Regression. `layoutFragments` started a fresh page by resetting the
      // used height directly instead of going through `consume`, so the counter
      // stayed at zero for a document that had already spilled onto a second
      // sheet — and a caller checking only that concluded it was one page.
      final flow = PdfPageFlow(contentHeight: 100, margin: 0);
      final rows = flow.layoutFragments(
        fragments: [
          for (var i = 0; i < 3; i++)
            PdfFlowFragment(
              height: 60,
              question: i,
              indexInQuestion: 0,
              isFirst: true,
              isLast: true,
            ),
        ],
        columns: 1,
      );

      expect(rows, hasLength(3), reason: 'three questions, one per page');
      expect(flow.pageBreaks, greaterThan(0));
    });

    test('a full page breaks the same way whether filled or forced', () {
      // `layoutFragments` fills a page exactly, then breaks for the next block.
      final filled = PdfPageFlow(contentHeight: 100, margin: 0);
      filled.layoutFragments(
        fragments: [
          for (var i = 0; i < 2; i++)
            PdfFlowFragment(
              height: 100,
              question: i,
              indexInQuestion: 0,
              isFirst: true,
              isLast: true,
            ),
        ],
        columns: 1,
      );

      final forced = PdfPageFlow(contentHeight: 100, margin: 0);
      forced.breakPage();

      // Both routes through a page boundary are counted. The counts need not
      // match — a block that fills its page exactly also breaks at the end of
      // it, which a forced break has no equivalent of.
      expect(filled.pageBreaks, greaterThan(0));
      expect(forced.pageBreaks, greaterThan(0));
    });
  });

  group('a deliberate break', () {
    test('clears the used height and counts itself', () {
      final flow = PdfPageFlow(contentHeight: 100, margin: 0);
      flow.consume(90);
      expect(flow.used, 90);

      flow.breakPage();
      expect(flow.used, 0);
      expect(flow.pageBreaks, 1);
    });

    test('leaves the next block a full page to work with', () {
      // The reason `breakPage` is paired with `pw.NewPage` in the export: the
      // estimator has to stop packing against the sheet it has just left, or
      // the two halves of the document disagree about where the page ended.
      final flow = PdfPageFlow(contentHeight: 100, margin: 0);
      flow.consume(95);
      flow.breakPage();

      // A whole page's worth of content now fits again.
      final rows = flow.layoutFragments(
        fragments: [
          PdfFlowFragment(
            height: 100,
            question: 0,
            indexInQuestion: 0,
            isFirst: true,
            isLast: true,
          ),
        ],
        columns: 1,
      );
      expect(rows, hasLength(1),
          reason: 'a whole page fits again after the deliberate break');
    });
  });
}
