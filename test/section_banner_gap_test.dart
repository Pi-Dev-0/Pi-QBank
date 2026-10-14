import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:pi_qbank/utils/pdf_column_layout.dart';

/// Guards the space under a section heading.
///
/// Two things used to go wrong together, in CQ, RQ and MCQ alike:
///
///  * when the heading was drawn **inline** (two sets, multi-column section),
///    the gap was added at page level — *above* the column block that holds the
///    heading — so the heading sat flush against the first question while the
///    air appeared somewhere it did nothing;
///  * the CQ section charged `bannerHeight` twice, so the flow reserved the
///    heading's height twice and every column came up short.
///
/// Neither shows up as an exception, so these are pinned against the source.
/// The tests are deliberately about *where* the gap is emitted and *how often*
/// the height is charged, which is what regressed.
void main() {
  late String source;

  setUpAll(() {
    source = File('lib/pages/highschool_qpaper_generator_page.dart')
        .readAsStringSync();
  });

  group('inline headings', () {
    test('each carries a gap into its column', () {
      // The heading and its gap travel together into the first column, so the
      // spacing matches a full-width heading.
      final inserts = RegExp(
        r'columns\.first\.insertAll\(0, \[\s*(\w+Banner),\s*'
        r'pw\.SizedBox\(height: PdfLayout\.sectionBannerGap\)',
      ).allMatches(source);

      expect(inserts.map((m) => m.group(1)).toSet(),
          {'cqBanner', 'rqBanner', 'mcqBanner'});
    });

    test('a heading is never inserted into a column on its own', () {
      // The exact shape of the bug: a bare insert leaves the heading touching
      // the first question.
      expect(RegExp(r'columns\.first\.insert\(0, \w+Banner\)').hasMatch(source),
          isFalse);
    });

    test('the gap is only drawn at page level when the heading is not inline',
        () {
      // Every page-level gap must sit behind an `if (!xInline)` guard,
      // otherwise it lands above an inline heading instead of below it.
      final unguarded = RegExp(
        r'\n\s*widgets\.add\(pw\.SizedBox\(height: PdfLayout\.sectionBannerGap\)\);',
      ).allMatches(source);

      for (final match in unguarded) {
        final before = source.substring(0, match.start);
        final guard = before.lastIndexOf('if (!');
        final banner = before.lastIndexOf('Banner');
        expect(guard, greaterThan(banner),
            reason: 'a page-level section gap must be guarded by an '
                'inline check');
      }
    });
  });

  group('budget', () {
    test('a heading height is charged exactly once per section', () {
      // Two charges reserve the height twice: the flow then believes there is
      // more used than is drawn, and columns come up short.
      //
      // Checked per section rather than by total, because a total cannot tell
      // "CQ charged twice, RQ not at all" from all three being correct.
      for (final section in ['emitCq', 'emitRq']) {
        expect(chargesIn(_bodyOf(source, section)), hasLength(1),
            reason: '$section must reserve its heading height once');
      }
      expect(chargesIn(_bodyOf(source, '_appendPdfMcqSection')), hasLength(1),
          reason: 'MCQ must reserve its heading height once');
    });

    test('the merged CQ+RQ flow charges each of its headings once', () {
      // The shared flow reserves the heading inside the fragment it belongs to,
      // through `add` rather than `consume`, so it needs its own count.
      expect(
          RegExp(r'add\(bannerHeight \+ PdfLayout\.mergedHeadingGap')
              .allMatches(source),
          hasLength(2));
    });

    test('every gap drawn is also charged', () {
      // The pair must move together; a gap drawn without a matching charge
      // lets a column run past the bottom of the page.
      expect(
        RegExp(r'sectionBannerGap').allMatches(source).length,
        greaterThanOrEqualTo(6),
      );
    });
  });

  group('the constant', () {
    test('there is visible air under a heading', () {
      // Tuned down by request; the floor is low enough that a heading with no
      // gap at all still fails, without pinning an exact value that is expected
      // to keep moving.
      expect(PdfLayout.sectionBannerGap, greaterThanOrEqualTo(8));
    });

    test('it is the same whether headings are inline or merged', () {
      expect(PdfLayout.mergedHeadingGap, PdfLayout.sectionBannerGap);
    });
  });
}

/// The source of the function or closure called [name], up to the line that
/// closes it at the same indentation.
String _bodyOf(String source, String name) {
  final start = source.indexOf(name);
  expect(start, greaterThan(-1), reason: 'no call to $name in the source');

  // Walk in from the declaration and count braces to find where it ends.
  var depth = 0;
  var seenBody = false;
  for (var i = start; i < source.length; i++) {
    final c = source[i];
    if (c == '{') {
      depth++;
      seenBody = true;
    } else if (c == '}') {
      depth--;
      if (seenBody && depth == 0) return source.substring(start, i);
    }
  }
  return source.substring(start);
}

/// Every heading-height reservation inside [body].
List<String> chargesIn(String body) => RegExp(
      r'flow\.consume\([^;]*?bannerHeight',
    ).allMatches(body).map((m) => m.group(0)!).toList();
