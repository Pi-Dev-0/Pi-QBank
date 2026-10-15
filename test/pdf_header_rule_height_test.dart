import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

/// `pw.Divider` defaults to **16pt** tall and centres the rule inside that, so a
/// divider written as `pw.Divider(thickness: 1.2)` is not a 1.2pt-tall widget —
/// it is a 16pt-tall one with a hairline in the middle.
///
/// The masthead has two of them. [PdfLayout.headerHeight] charges
/// `headerDivider` for each, so the drawn header used to stand ~30pt taller than
/// the flow believed. That is the kind of drift that makes dart_pdf move a whole
/// block to the next sheet and leave a band of blank paper at the foot of the
/// page — and it also simply looked like too much air around the meta row.
///
/// These are pinned against the source because `_buildPdfHeader` assembles its
/// widgets from private state and cannot be called from a test; see also
/// `section_banner_gap_test.dart`, which guards the same file the same way.
void main() {
  late String source;

  setUpAll(() {
    source = File('lib/pages/highschool_qpaper_generator_page.dart')
        .readAsStringSync();
  });

  test('the default really is the trap this test exists for', () {
    // If a future pdf package made Divider tighten to its thickness, the guard
    // below would be pointless and this test should be deleted rather than
    // silently kept.
    final loose = pw.Divider(thickness: 1.2);

    expect(loose.height, isNull,
        reason: 'the hazard is a null height, which builds as 16pt');
  });

  test('every masthead rule is given an explicit height', () {
    final rules = RegExp(r'pw\.Divider\(([^)]*)\)', multiLine: true)
        .allMatches(source)
        .map((m) => m.group(1)!)
        .toList();

    expect(rules, isNotEmpty, reason: 'the masthead rules vanished');

    for (final args in rules) {
      expect(args.contains('height:'), isTrue,
          reason: 'a masthead rule without an explicit height is 16pt tall and '
              'the layout model counts it as '
              '${1.2}pt — got: pw.Divider($args)');
    }
  });
}
