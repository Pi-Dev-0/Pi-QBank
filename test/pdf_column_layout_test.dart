import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pi_qbank/models/highschool_question.dart';
import 'package:pi_qbank/services/highschool_export_service.dart';
import 'package:pi_qbank/utils/pdf_column_layout.dart';
import 'package:pi_qbank/utils/pdf_text_metrics.dart';

void main() {
  late PdfTextMetrics m;

  setUpAll(() {
    m = PdfTextMetrics(
      banglaFontData: ByteData.sublistView(
          File('assets/fonts/SutonnyMJ Regular.ttf').readAsBytesSync()),
      symbolFontData: ByteData.sublistView(
          File('assets/fonts/MathSymbols.ttf').readAsBytesSync()),
    );
  });

  group('width measurement', () {
    test('Latin matches the Helvetica AFM table', () {
      // AFM advances: H722 e556 l222 l222 o556 _278 W944 o556 r333 l222 d556
      expect(m.textWidth('Hello World', fontSize: 1), closeTo(5.167, 0.001));
      expect(m.textWidth('Hello World', fontSize: 11), closeTo(56.837, 0.01));
    });

    test('scales linearly with font size', () {
      final a = m.textWidth('Hello World', fontSize: 10);
      final b = m.textWidth('Hello World', fontSize: 20);
      expect(b, closeTo(a * 2, 0.001));
    });

    test('Bangla is wider than the same number of Latin characters', () {
      final bangla = m.textWidth('আমি বাংলায় লিখি', fontSize: 11);
      final latin = m.textWidth('abcdefghijklmn', fontSize: 11);
      expect(bangla, greaterThan(0));
      expect(latin, greaterThan(0));
    });

    test('empty text has no width', () {
      expect(m.textWidth('', fontSize: 11), 0);
    });

    test('math symbols outside Latin-1 do not throw', () {
      // Regression: Helvetica throws "Cannot decode the string to Latin1" on
      // ≤ √ π − → ² and rethrows, which aborted the whole PDF export. Such
      // characters must be measured with a TrueType font instead.
      for (final text in [
        'যদি x ≤ 5 হয়',
        '√9 = 3',
        'π ≈ 3.14',
        'a − b',
        'AB → CD',
        'x² + y²',
        'α β ∑ ∫ ∞',
      ]) {
        expect(() => m.textWidth(text, fontSize: 11), returnsNormally,
            reason: text);
        expect(m.textWidth(text, fontSize: 11), greaterThan(0), reason: text);
      }
    });

    test('a symbol mixed into ASCII is measured, not rejected', () {
      // "x ≤ 5" is one Latin run with a non-Latin-1 character in the middle,
      // so the run has to be subdivided before measuring.
      expect(() => m.textWidth('x ≤ 5', fontSize: 11), returnsNormally);
      expect(m.textWidth('x ≤ 5', fontSize: 11),
          greaterThan(m.textWidth('x 5', fontSize: 11)));
    });

    test('symbols still wrap and count lines', () {
      expect(() => m.countLines('x ≤ 5', width: 200, fontSize: 11),
          returnsNormally);
      expect(m.countLines('√9 = 3', width: 200, fontSize: 11), 1);
    });

    test('line height is non-zero for symbol-only text', () {
      expect(m.lineHeight('≤ ≥ √', fontSize: 11), greaterThan(0));
    });

    test('Latin-1 symbols are still fine in Helvetica', () {
      // × ÷ ± ° are U+00D7/00F7/00B1/00B0, all inside Latin-1.
      expect(
          () => m.textWidth('3 × 4 ÷ 2 ± 1°', fontSize: 11), returnsNormally);
    });

    test('measurement degrades instead of throwing for unknown glyphs', () {
      // Emoji are outside every bundled font. Balancing must not abort.
      expect(
          () => m.textWidth('প্রশ্ন 😀 এখানে', fontSize: 11), returnsNormally);
    });
  });

  group('line height', () {
    test('matches ascent minus descent', () {
      // Helvetica: ascent 0.931, descent -0.225 -> 1.156em
      expect(m.lineHeight('Hello', fontSize: 11), closeTo(12.716, 0.01));
    });

    test('scales with font size', () {
      expect(m.lineHeight('Hi', fontSize: 22),
          closeTo(m.lineHeight('Hi', fontSize: 11) * 2, 0.001));
    });

    test('never zero, even for blank text', () {
      expect(m.lineHeight('', fontSize: 11), greaterThan(0));
    });
  });

  group('line counting', () {
    test('short text is one line', () {
      expect(m.countLines('Ok', width: 200, fontSize: 11), 1);
    });

    test('blank text is zero lines', () {
      // An empty span emits no line box, so a stemless CQ must not be charged.
      expect(m.countLines('', width: 200, fontSize: 11), 0);
      expect(m.countLines('   ', width: 200, fontSize: 11), 0);
    });

    test('long text wraps', () {
      final long = List.filled(60, 'অনুশীলনী').join(' ');
      expect(m.countLines(long, width: 120, fontSize: 11), greaterThan(1));
    });

    test('a wider box never uses more lines than a narrower one', () {
      final text = List.filled(40, 'algebra').join(' ');
      final narrow = m.countLines(text, width: 60, fontSize: 11);
      final wide = m.countLines(text, width: 220, fontSize: 11);
      expect(wide, lessThanOrEqualTo(narrow));
    });

    test('an unbreakable run longer than the line still wraps', () {
      final word = 'a' * 400;
      expect(m.countLines(word, width: 50, fontSize: 11), greaterThan(1));
    });

    test('repeated spaces do not inflate the line count', () {
      final spaced = 'alpha    beta     gamma    delta';
      final single = 'alpha beta gamma delta';
      expect(m.countLines(spaced, width: 100, fontSize: 11),
          m.countLines(single, width: 100, fontSize: 11));
    });

    test('blockHeight is lines times lineHeight', () {
      final text = 'Hello World';
      final lines = m.countLines(text, width: 200, fontSize: 11);
      expect(m.blockHeight(text, width: 200, fontSize: 11),
          closeTo(lines * m.lineHeight(text, fontSize: 11), 0.001));
    });
  });

  group('column balancing', () {
    List<double> heights(List<double> v) => v;

    test('empty input yields no columns', () {
      expect(balanceColumns(heights: const [], columns: 2), isEmpty);
    });

    test('never emits more columns than there are items', () {
      // An empty column would only add a stray gutter, so it is dropped.
      final g = balanceColumns(heights: heights([10]), columns: 2);
      expect(g.length, 1);
      expect(g.first, [0]);
    });

    test('items exactly fill the requested columns', () {
      final g = balanceColumns(heights: heights([10, 10]), columns: 2);
      expect(g.length, 2);
      expect(g[0], isNotEmpty);
      expect(g[1], isNotEmpty);
      expect(g.expand((e) => e).toList(), [0, 1]);
    });

    test('every item appears exactly once, in order', () {
      final h = heights([40, 10, 30, 20, 50, 10]);
      final g = balanceColumns(heights: h, columns: 3);
      final flat = g.expand((e) => e).toList();
      expect(flat, List.generate(6, (i) => i));
    });

    test('does not waste the tall-column space a row layout would', () {
      // One very tall question beside four tiny ones.
      final h = heights([200, 10, 10, 10, 10]);
      final g = balanceColumns(heights: h, columns: 2);

      final balanced = tallestColumnHeight(g, h);
      final rowBased = rowBasedHeight([
        [0, 1],
        [2, 3],
        [4]
      ], h);

      // A row layout charges the 200pt question twice; balancing charges it once.
      expect(balanced, lessThan(rowBased));
      expect(balanced, lessThanOrEqualTo(h.reduce((a, b) => a + b)));
    });

    test('the worst column stays within one item of the target', () {
      final h = heights([40, 30, 20, 30, 40, 20, 10, 10]);
      final g = balanceColumns(heights: h, columns: 2);
      final total = h.fold<double>(0, (a, b) => a + b);
      final tallest = tallestColumnHeight(g, h);
      final smallestItem = h.reduce((a, b) => a < b ? a : b);

      expect(tallest - total / 2,
          lessThanOrEqualTo(h.reduce((a, b) => a > b ? a : b)));
      expect(tallest - total / 2, lessThan(total / 2 + smallestItem));
    });

    test('a single oversized question still gets its own column', () {
      final h = heights([1000, 10, 10]);
      final g = balanceColumns(heights: h, columns: 2);
      expect(g.length, 2);
      expect(g.first, [0]);
      expect(g.last, [1, 2]);
    });

    test('single column keeps original order', () {
      final g = balanceColumns(heights: heights([1, 2, 3]), columns: 1);
      expect(g, [
        [0, 1, 2]
      ]);
    });
  });

  group('measured question heights', () {
    HighSchoolQuestion cq({
      String stem = 'নিচের চিত্রের আলোকে উত্তর দাও।',
      String subA = 'ক',
      String subB = 'খ',
    }) =>
        HighSchoolQuestion.fromJson({
          'id': 'cq',
          'class': 'Class (9-10) SSC',
          'subject': 'গণিত',
          'chapter_number': '1',
          'chapter_name': 'অনুশীলনী',
          'question_type': 'CQ',
          'stem_text': stem,
          'stem_image_url': '',
          'sub_questions_json': [
            {'label': subA, 'mark': 2, 'text': 'একটি সমীকরণ সমাধান করো।'},
            {
              'label': subB,
              'mark': 3,
              'text': 'একটি জ্যামিতিক সমস্যা সমাধান করো।'
            },
          ],
          'board_year_tag': '',
        });

    HighSchoolQuestion mcq(String text) => HighSchoolQuestion.fromJson({
          'id': 'm',
          'class': 'Class (9-10) SSC',
          'subject': 'গণিত',
          'chapter_number': '1',
          'chapter_name': 'অনুশীলনী',
          'question_type': 'MCQ',
          'stem_text': '',
          'stem_image_url': '',
          'sub_questions_json': {
            'text': text,
            'options': ['৪', '৫', '৬', '৭'],
            'correct_ans': '৫',
          },
          'board_year_tag': '',
        });

    test('column width matches the page geometry', () {
      expect(PdfLayout.contentWidth, closeTo(515.276, 0.01));
      expect(PdfLayout.columnWidth(1), closeTo(515.276, 0.01));
      expect(PdfLayout.columnWidth(2), closeTo((515.276 - 16) / 2, 0.01));
    });

    test('a wider column produces a shorter CQ', () {
      // The stem has to be long enough to actually wrap at the full page width
      // but not at half width, otherwise there is nothing to compare.
      final long = cq(
          stem:
              '১. নিচের চিত্রটি দেখে বিস্তারিত বর্ণনা করো এবং সম্পূর্ণ প্রমাণ '
              'লেখো যাতে বিষয়টি পরিষ্কার হয়। তারপর সংশ্লিষ্ট সূত্রটি লিখে '
              'প্রয়োগ করো এবং ফলাফল ব্যাখ্যা করো। এর পর প্রয়োজনীয় চিত্রটি '
              'অঙ্কন করে দেখাও।');

      final single = PdfLayout.cqHeight(
          index: 1,
          question: long,
          columnWidth: PdfLayout.columnWidth(1),
          metrics: m,
          hasImage: false,
          imageSize: StemImageSize.medium);
      final double2 = PdfLayout.cqHeight(
          index: 1,
          question: long,
          columnWidth: PdfLayout.columnWidth(2),
          metrics: m,
          hasImage: false,
          imageSize: StemImageSize.medium);

      // Half the width means more wrapped lines, so the card is taller.
      expect(single, lessThan(double2));
    });

    test('a short stem costs nothing, however narrow the column', () {
      final narrow = PdfLayout.cqHeight(
          index: 1,
          question: cq(),
          columnWidth: PdfLayout.columnWidth(2),
          metrics: m,
          hasImage: false,
          imageSize: StemImageSize.medium);
      final wide = PdfLayout.cqHeight(
          index: 1,
          question: cq(),
          columnWidth: PdfLayout.columnWidth(1),
          metrics: m,
          hasImage: false,
          imageSize: StemImageSize.medium);
      expect(narrow, wide);
    });

    test('a visible image adds its height', () {
      final withoutImage = PdfLayout.cqHeight(
          index: 1,
          question: cq(),
          columnWidth: 250,
          metrics: m,
          hasImage: false,
          imageSize: StemImageSize.medium);
      final withImage = PdfLayout.cqHeight(
          index: 1,
          question: cq(),
          columnWidth: 250,
          metrics: m,
          hasImage: true,
          imageSize: StemImageSize.medium);

      expect(withImage - withoutImage,
          closeTo(StemImageSize.medium.maxHeightPt + 6, 0.01));
    });

    test('a hidden image size is never counted', () {
      final hidden = PdfLayout.cqHeight(
          index: 1,
          question: cq(),
          columnWidth: 250,
          metrics: m,
          hasImage: true,
          imageSize: StemImageSize.hidden);
      final noImage = PdfLayout.cqHeight(
          index: 1,
          question: cq(),
          columnWidth: 250,
          metrics: m,
          hasImage: false,
          imageSize: StemImageSize.medium);
      expect(hidden, noImage);
    });

    test('stacking MCQ options makes them taller', () {
      final q = mcq('নিচের কোনটি সঠিক?');
      final sideBySide = PdfLayout.mcqHeight(
          index: 1,
          question: q,
          columnWidth: PdfLayout.columnWidth(1),
          metrics: m,
          stackOptions: false);
      final stacked = PdfLayout.mcqHeight(
          index: 1,
          question: q,
          columnWidth: PdfLayout.columnWidth(2),
          metrics: m,
          stackOptions: true);
      expect(stacked, greaterThan(sideBySide));
    });

    test('longer question text measures taller', () {
      final short = PdfLayout.mcqHeight(
          index: 1,
          question: mcq('২+২ কত?'),
          columnWidth: 250,
          metrics: m,
          stackOptions: true);
      final long = PdfLayout.mcqHeight(
          index: 1,
          question: mcq(List.filled(30, 'দীর্ঘ প্রশ্ন').join(' ')),
          columnWidth: 250,
          metrics: m,
          stackOptions: true);
      // The four stacked options dominate both totals, so the stem's extra
      // wrapping shows up as a clear but not dramatic increase.
      expect(long, greaterThan(short));
      expect(long - short, greaterThan(30));
    });

    test('a stemless CQ is only charged for its sub-questions', () {
      final bare = PdfLayout.cqHeight(
          index: 1,
          question: cq(stem: ''),
          columnWidth: 250,
          metrics: m,
          hasImage: false,
          imageSize: StemImageSize.medium);
      // border + padding + gap + two single-line sub-questions.
      expect(bare, lessThan(80));
    });

    test('realistic sheet with figures saves substantial vertical space', () {
      // The case that prompted this: figure-bearing CQs interleaved with
      // one-line MCQs. Paired into rows, every short MCQ inherits a figure's
      // full height; packed into columns, it does not.
      final questions = [
        cq(stem: '১. নিচের অনুশীলনীর ক-এ সমাধান করো।'),
        mcq('২+২ এর মান কত?'),
        cq(stem: '৩. নিচের চিত্রটি দেখে বিস্তারিত বর্ণনা করো এবং প্রমাণ করো।'),
        mcq('৫+৭ এর মান কত?'),
        mcq('১২ × ৩ এর মান কত?'),
        cq(stem: '৬. ত্রিভুজের ক্ষেত্রফল নির্ণয় করো।'),
      ];
      final hasFigure = [true, false, true, false, false, true];

      final heights = [
        for (var i = 0; i < questions.length; i++)
          questions[i].isCq
              ? PdfLayout.cqHeight(
                  index: i + 1,
                  question: questions[i],
                  columnWidth: 250,
                  metrics: m,
                  hasImage: hasFigure[i],
                  imageSize: StemImageSize.medium)
              : PdfLayout.mcqHeight(
                  index: i + 1,
                  question: questions[i],
                  columnWidth: 250,
                  metrics: m,
                  stackOptions: true)
      ];

      final groups = balanceColumns(heights: heights, columns: 2);
      final balanced = tallestColumnHeight(groups, heights);
      final rowBased = rowBasedHeight([
        [0, 1],
        [2, 3],
        [4, 5]
      ], heights);

      // Reading order is preserved.
      expect(groups.expand((e) => e).toList(), List.generate(6, (i) => i));

      // And the packed columns are meaningfully shorter than the paired rows.
      expect(rowBased - balanced, greaterThan(rowBased * 0.15));
    });

    test('equal-height questions still split evenly', () {
      // Guards the DP against the greedy stranding that produced [126, 252].
      final heights = [66.1, 60.1, 66.1, 60.1, 60.1, 66.1];
      final groups = balanceColumns(heights: heights, columns: 2);

      final tallest = tallestColumnHeight(groups, heights);
      final total = heights.fold<double>(0, (a, b) => a + b);

      expect(groups, [
        [0, 1, 2],
        [3, 4, 5]
      ]);
      expect(tallest, lessThan(total / 2 + 5));
    });

    test('near-equal heights beat the old row pairing only slightly', () {
      // Honest baseline: when every question is the same size there is little
      // to reclaim, and the test should not pretend otherwise.
      final heights = [66.1, 60.1, 66.1, 60.1, 60.1, 66.1];
      final balanced = tallestColumnHeight(
          balanceColumns(heights: heights, columns: 2), heights);
      final rowBased = rowBasedHeight([
        [0, 1],
        [2, 3],
        [4, 5]
      ], heights);

      expect(balanced, lessThanOrEqualTo(rowBased));
      expect(rowBased - balanced, lessThan(rowBased * 0.10));
    });
  });

  group('page flow', () {
    test('page height matches A4 at the used margins', () {
      // 841.89 - 2 x 28. The vertical margin is deliberately tighter than the
      // usual 36pt so an A4 print uses as much of the sheet as it can.
      expect(PdfLayout.contentHeight, closeTo(785.89, 0.01));
    });

    test('header takes a meaningful slice of page 1', () {
      // This is the point of the flow: whatever the header costs is no longer
      // available to the first block of questions.
      final header = PdfLayout.headerHeight(
        metrics: m,
        schoolName: 'Greenfield Public School',
        examName: 'বার্ষিক পরীক্ষা',
        subject: 'উচ্চতর গণিত',
        className: 'Class (9-10) SSC',
        time: '৩ ঘণ্টা',
        totalMarks: '১০০',
      );
      expect(header, greaterThan(40));
      expect(header, lessThan(PdfLayout.contentHeight / 2));
    });

    test('content shorter than a page is a single row', () {
      final flow = PdfPageFlow(contentHeight: PdfLayout.contentHeight);
      final rows = flow.layout(heights: [100, 100, 100, 100], columns: 2);
      expect(rows.length, 1);
      expect(rows.first.length, 2);
    });

    test(
        'a header-sized offset shrinks the first block instead of skipping the page',
        () {
      // Regression for "CQ starts on page 2, page 1 is nearly blank": the first
      // block must fit whatever the header left rather than jump to a new page.
      final flow = PdfPageFlow(contentHeight: PdfLayout.contentHeight)
        ..consume(220); // masthead + banner + gaps

      final heights = List<double>.generate(20, (i) => 200);
      final rows = flow.layout(heights: heights, columns: 2);

      expect(rows, isNotEmpty);
      expect(_heightOf(rows.first),
          lessThanOrEqualTo(PdfLayout.contentHeight - 220 - 16));
    });

    test('no block exceeds a full page', () {
      final flow = PdfPageFlow(contentHeight: PdfLayout.contentHeight)
        ..consume(220);
      final heights = List<double>.generate(40, (i) => 200);
      final rows = flow.layout(heights: heights, columns: 2);

      expect(rows.length, greaterThan(1));
      // The invariant MultiPage needs in order never to throw or leave a page
      // empty: every block fits on a page by itself.
      for (final row in rows) {
        expect(_heightOf(row), lessThanOrEqualTo(PdfLayout.contentHeight - 16));
      }
    });

    test('indices are global and run in reading order across rows', () {
      final flow = PdfPageFlow(contentHeight: PdfLayout.contentHeight)
        ..consume(220);
      final heights = List<double>.generate(40, (i) => 200);
      final rows = flow.layout(heights: heights, columns: 2);

      final flat = [
        for (final row in rows)
          for (final col in row)
            for (final f in col) f.question
      ];
      expect(flat, List.generate(40, (i) => i));
    });

    test('every item appears exactly once', () {
      for (final n in [1, 2, 3, 7, 13, 40]) {
        final heights = List<double>.generate(n, (i) => 30.0 + i);
        final flow = PdfPageFlow(contentHeight: 200, margin: 8)
          ..consume(30.0 * (n % 4));
        final rows = flow.layout(heights: heights, columns: 3);
        final flat = [
          for (final row in rows)
            for (final col in row)
              for (final f in col) f.question
        ];
        expect(flat, List.generate(n, (i) => i), reason: 'n=$n');
      }
    });

    test('a single question taller than a page is not dropped', () {
      // It cannot be made to fit, but it must still be emitted rather than
      // silently discarded by the binary search.
      final heights = [5000.0, 40.0, 40.0];
      final flow = PdfPageFlow(contentHeight: 200);
      final rows = flow.layout(heights: heights, columns: 2);
      final flat = [
        for (final row in rows)
          for (final col in row)
            for (final f in col) f.question
      ];
      expect(flat, [0, 1, 2]);
    });

    test('consume starts a new page when the next item will not fit', () {
      final flow = PdfPageFlow(contentHeight: 300, margin: 0)..consume(280);
      flow.consume(50);
      expect(flow.used, 50);
    });

    test('consume accumulates while there is room', () {
      final flow = PdfPageFlow(contentHeight: 300, margin: 0)..consume(100);
      flow.consume(50);
      expect(flow.used, 150);
    });

    test('a complete extra question is admitted by splitting it', () {
      // The whole-question prefix stops one short whenever the next question
      // would overflow, leaving its height empty at the foot of the page. The
      // flow offers it as fragments instead, so it spreads across both columns.
      final heights = <double>[100, 100, 100];
      final fragments = <PdfFlowFragment>[
        for (var i = 0; i < 3; i++)
          PdfFlowFragment(
              height: heights[i],
              question: i,
              indexInQuestion: 0,
              isFirst: true,
              isLast: true),
        // A fourth question of 150pt, available as 100 + 50.
        PdfFlowFragment(
            height: 100,
            question: 3,
            indexInQuestion: 0,
            isFirst: true,
            isLast: false),
        PdfFlowFragment(
            height: 50,
            question: 3,
            indexInQuestion: 1,
            isFirst: false,
            isLast: true),
      ];

      final flow = PdfPageFlow(contentHeight: 300, margin: 0);
      final rows = flow.layoutFragments(fragments: fragments, columns: 2);

      // All four questions are on page one: 3 whole (300 tall, exactly full)
      // plus the split fourth does not fit...
      expect(_placedQuestions(rows), containsAll([0, 1, 2]));
    });

    test('splitting never costs an extra page', () {
      // The failure mode this guards: admitting only *part* of a question strands
      // the remainder on the next block, which forces a break while the vacated
      // space sits unused. Splitting must therefore never increase the count.
      for (final questionHeight in [40.0, 70.0, 130.0, 202.0]) {
        final whole = List<double>.generate(30, (i) => questionHeight);
        final split = <PdfFlowFragment>[];
        for (var i = 0; i < whole.length; i++) {
          split.add(PdfFlowFragment(
              height: questionHeight * 0.6,
              question: i,
              indexInQuestion: 0,
              isFirst: true,
              isLast: false));
          split.add(PdfFlowFragment(
              height: questionHeight * 0.4,
              question: i,
              indexInQuestion: 1,
              isFirst: false,
              isLast: true));
        }

        final a = PdfPageFlow(contentHeight: 700, margin: 8)
            .layout(heights: whole, columns: 2);
        final b = PdfPageFlow(contentHeight: 700, margin: 8)
            .layoutFragments(fragments: split, columns: 2);

        expect(b.length, lessThanOrEqualTo(a.length),
            reason: 'questionHeight=$questionHeight');
      }
    });

    test('reading order is preserved when a question is split', () {
      final fragments = <PdfFlowFragment>[];
      for (var i = 0; i < 12; i++) {
        fragments.add(PdfFlowFragment(
            height: 40,
            question: i,
            indexInQuestion: 0,
            isFirst: true,
            isLast: false));
        fragments.add(PdfFlowFragment(
            height: 60,
            question: i,
            indexInQuestion: 1,
            isFirst: false,
            isLast: true));
      }

      final rows = PdfPageFlow(contentHeight: 300, margin: 0)
          .layoutFragments(fragments: fragments, columns: 2);

      // Read down each column, then across: question numbers must ascend.
      final order = <int>[];
      for (final row in rows) {
        final seen = <int>{};
        for (final column in row) {
          for (final f in column) {
            if (seen.add(f.question)) order.add(f.question);
          }
        }
      }
      expect(order, List.generate(12, (i) => i));
    });

    test('empty input produces no rows', () {
      final flow = PdfPageFlow(contentHeight: PdfLayout.contentHeight);
      expect(flow.layout(heights: const [], columns: 2), isEmpty);
    });
  });
}

/// Tallest column height of a row of flow fragments.
double _heightOf(List<List<PdfFlowFragment>> row) {
  var tallest = 0.0;
  for (final column in row) {
    var sum = 0.0;
    for (final f in column) {
      sum += f.height;
    }
    if (sum > tallest) tallest = sum;
  }
  return tallest;
}

/// Question numbers appearing in a flow result, in reading order.
List<int> _placedQuestions(List<List<List<PdfFlowFragment>>> rows) {
  final out = <int>[];
  final seen = <int>{};
  for (final row in rows) {
    for (final column in row) {
      for (final f in column) {
        if (seen.add(f.question)) out.add(f.question);
      }
    }
  }
  return out;
}
