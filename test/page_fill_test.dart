import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pi_qbank/utils/pdf_column_layout.dart';

/// The packer on its own: does a page come out full, or does the layout leave a
/// band of blank space?
///
/// Everything else in the export — headers, banners, the gap after a block — is
/// outside this file and outside this test. So a block that is correct here and
/// still wrong on the page means the drift is being introduced by the page, not
/// by the packing.
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

  test('a page comes out full, not half empty', () {
    const pageHeight = 785.89;
    final flow = PdfPageFlow(contentHeight: pageHeight);

    final rows = flow.layoutFragments(
      fragments: makeFragments(40, 60, 35),
      columns: 2,
      trailingGap: 16,
      trace: debugPrint,
    );

    // How tall is each block? That is how much of the page it occupies.
    final heights = [
      for (final row in rows)
        row
                .map((c) => c.fold<double>(0, (m, f) => m + f.height))
                .reduce((a, b) => a > b ? a : b) +
            16
    ];

    debugPrint(
        'blocks=${heights.length} heights=${heights.map((h) => h.toStringAsFixed(0)).join(",")}');

    expect(heights.length, greaterThan(1), reason: 'more than one page');

    // Every block except the last must fill its page, or the blank band the
    // user is seeing is coming from the packer itself.
    for (final h in heights.take(heights.length - 1)) {
      expect(h, greaterThan((pageHeight - PdfPageFlow.defaultMargin) * 0.9),
          reason: 'a block should fill the page it sits on, not leave a band');
    }
  });

  test('the same holds for one column', () {
    const pageHeight = 785.89;
    final flow = PdfPageFlow(contentHeight: pageHeight);
    final rows = flow.layoutFragments(
      fragments: makeFragments(40, 60, 35),
      columns: 1,
      trailingGap: 16,
    );
    final heights = [
      for (final row in rows)
        row
                .map((c) => c.fold<double>(0, (m, f) => m + f.height))
                .reduce((a, b) => a > b ? a : b) +
            16
    ];
    debugPrint(
        '1col heights=${heights.map((h) => h.toStringAsFixed(0)).join(",")}');

    for (final h in heights.take(heights.length - 1)) {
      expect(h, greaterThan((pageHeight - PdfPageFlow.defaultMargin) * 0.9));
    }
  });

  test('and for three columns', () {
    const pageHeight = 785.89;
    final flow = PdfPageFlow(contentHeight: pageHeight);
    final rows = flow.layoutFragments(
      fragments: makeFragments(60, 50, 30),
      columns: 3,
      trailingGap: 16,
    );
    final heights = [
      for (final row in rows)
        row
                .map((c) => c.fold<double>(0, (m, f) => m + f.height))
                .reduce((a, b) => a > b ? a : b) +
            16
    ];
    debugPrint(
        '3col heights=${heights.map((h) => h.toStringAsFixed(0)).join(",")}');

    for (final h in heights.take(heights.length - 1)) {
      expect(h, greaterThan((pageHeight - PdfPageFlow.defaultMargin) * 0.9));
    }
  });
}
