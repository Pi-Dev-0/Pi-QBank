// The paper's font-size controls: a general step moves every text size in the
// paper by one point per step, and CQ/SQ/MCQ each have an extra step of their
// own. The general step is shared by the PDF and the HTML sheet; the family
// steps are HTML-only, where the separate section sizes are chosen.
//
// Two things have to hold. The general step must move *every* size, including
// the ones it leaves to be inherited (an MCQ stem), or a paper grows unevenly as
// the step is turned up. And a family step must move only its own text. The
// general step also has to reach the layout's height estimators as well as the
// styles it draws with: an estimator that keeps budgeting room for 11pt text
// while 13pt text is drawn under-estimates the paper, and a column overflows the
// allowance the flow gave it. Hence one guard per estimator.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:pi_qbank/models/highschool_question.dart';
import 'package:pi_qbank/services/highschool_export_service.dart';
import 'package:pi_qbank/utils/pdf_column_layout.dart';
import 'package:pi_qbank/utils/pdf_text_metrics.dart';

HighSchoolQuestion cqTest(String stem) => HighSchoolQuestion.fromJson({
      'id': stem,
      'class': 'Class (9-10) SSC',
      'subject': 'গণিত',
      'chapter_number': '1',
      'chapter_name': 'অনুশীলনী',
      'question_type': 'CQ',
      'stem_text': stem,
      'stem_image_url': '',
      'sub_questions_json': [
        {'label': 'ক', 'mark': 2, 'text': 'সমাধান করো।'},
      ],
      'board_year_tag': '',
    });

HighSchoolQuestion rqTest(String text) => HighSchoolQuestion.fromJson({
      'id': text,
      'class': 'Class (9-10) SSC',
      'subject': 'গণিত',
      'chapter_number': '1',
      'chapter_name': 'অনুশীলনী',
      'question_type': 'RQ',
      'stem_text': text,
      'stem_image_url': '',
      'sub_questions_json': <Object>[],
      'board_year_tag': '',
      'short_mark': 1,
    });

HighSchoolQuestion mcqTest(String text) => HighSchoolQuestion.fromJson({
      'id': text,
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

/// A paper with one block of each kind, generated at [fontStep] plus the
/// optional per-family steps.
String generate(
  double fontStep, {
  double cqFontStep = 0,
  double rqFontStep = 0,
  double mcqFontStep = 0,
}) =>
    HighSchoolExportService.generateHtml(
      schoolName: 'S',
      examName: 'E',
      subject: 'গণিত',
      className: 'C',
      time: 'T',
      totalMarks: '10',
      questions: [
        cqTest('উদ্দীপক পাঠ করে নিচের প্রশ্নগুলোর উত্তর দাও।'),
        mcqTest('নিচের কোনটি সঠিক?'),
        rqTest('সংক্ষেপে উত্তর দাও।'),
      ],
      fontStep: fontStep,
      cqFontStep: cqFontStep,
      rqFontStep: rqFontStep,
      mcqFontStep: mcqFontStep,
    );

/// The stylesheet of a generated paper.
String cssOf(String html) => html.split('<style>')[1].split('</style>')[0];

/// The declarations inside one CSS rule, by selector, exactly as written.
String rule(String css, String selector) {
  final match =
      RegExp('${RegExp.escape(selector)}\\s*\\{([^}]*)\\}', multiLine: true)
          .firstMatch(css);
  return match == null ? '' : match.group(1)!;
}

/// One declaration's value inside a rule body, or null when it is not set.
String? decl(String body, String property) {
  final match = RegExp('(?:^|;)\\s*${RegExp.escape(property)}\\s*:([^;]*)',
          multiLine: true)
      .firstMatch(body);
  return match?.group(1)?.trim();
}

void main() {
  group('the HTML sheet', () {
    test('prints the tuned size when nothing is stepped', () {
      final css = cssOf(generate(0));

      // No `calc()` at 0: a paper that has never been stepped has to come out
      // exactly as it did before the control existed.
      expect(decl(rule(css, '.cq-stem'), 'font-size'), '15px');
      expect(decl(rule(css, '.rq-item'), 'font-size'), '15px');
      expect(decl(rule(css, '.mcq-question'), 'font-size'), '15px');
      expect(decl(rule(css, '.mcq-options'), 'font-size'), '15px');
      expect(decl(rule(css, '.school-title'), 'font-size'), '24px');
      expect(decl(rule(css, '.paper-sheet'), 'font-size'), '16px');
    });

    test('moves every size by the step, in points', () {
      final css = cssOf(generate(2));

      // Points, not pixels: the PDF moves its own sizes by one point a step, so
      // the sheet has to grow by a point too or the two exports drift apart.
      const expected = {
        '.school-title': 'calc(24px + 2pt)',
        '.exam-title': 'calc(18px + 2pt)',
        '.meta-bar': 'calc(15px + 2pt)',
        '.section-banner': 'calc(14px + 2pt)',
        '.cq-stem': 'calc(15px + 2pt)',
        '.cq-sub-item': 'calc(14px + 2pt)',
        '.mcq-question': 'calc(15px + 2pt)',
        '.mcq-options': 'calc(15px + 2pt)',
        '.rq-item': 'calc(15px + 2pt)',
        // The sheet's own size: what an MCQ stem, which sets no size of its
        // own, inherits.
        '.paper-sheet': 'calc(16px + 2pt)',
      };

      for (final entry in expected.entries) {
        expect(decl(rule(css, entry.key), 'font-size'), entry.value,
            reason: entry.key);
      }
    });

    test('each question family can take its own extra step', () {
      final css = cssOf(generate(
        1,
        cqFontStep: 2,
        rqFontStep: -1,
        mcqFontStep: 3,
      ));

      // CQ: general +1 and CQ +2.
      expect(decl(rule(css, '.cq-stem'), 'font-size'), 'calc(15px + 3pt)');
      expect(decl(rule(css, '.cq-sub-item'), 'font-size'), 'calc(14px + 3pt)');
      // SQ: +1 and −1 cancel, so the rule keeps the plain tuned size.
      expect(decl(rule(css, '.rq-item'), 'font-size'), '15px');
      // MCQ: general +1 and MCQ +3.
      expect(decl(rule(css, '.mcq-question'), 'font-size'), 'calc(15px + 4pt)');
      expect(decl(rule(css, '.mcq-stem'), 'font-size'), 'calc(15px + 4pt)');
      expect(decl(rule(css, '.mcq-options'), 'font-size'), 'calc(15px + 4pt)');
      // The families must not drag the masthead or each other along.
      expect(decl(rule(css, '.school-title'), 'font-size'), 'calc(24px + 1pt)');
      expect(decl(rule(css, '.exam-title'), 'font-size'), 'calc(18px + 1pt)');
    });

    test('a family step on its own leaves the other families alone', () {
      final css = cssOf(generate(0, cqFontStep: 2));

      expect(decl(rule(css, '.cq-stem'), 'font-size'), 'calc(15px + 2pt)');
      expect(decl(rule(css, '.rq-item'), 'font-size'), '15px');
      expect(decl(rule(css, '.mcq-question'), 'font-size'), '15px');
    });

    test('a negative step subtracts instead of adding a signed value', () {
      final css = cssOf(generate(-2));

      expect(decl(rule(css, '.cq-stem'), 'font-size'), 'calc(15px - 2pt)');
      expect(decl(rule(css, '.paper-sheet'), 'font-size'), 'calc(16px - 2pt)');
    });

    test('the canvas and the text column stay put', () {
      final small = rule(cssOf(generate(-3)), '.paper-sheet');
      final big = rule(cssOf(generate(6)), '.paper-sheet');

      // Text grows into the same A4 page: only the sizes move, never the page or
      // the side margins, which is what keeps a line wrapping in the same place
      // as in the PDF. The head padding lives on `.masthead` so an author strip
      // can start at the very top of the sheet.
      for (final sheet in [small, big]) {
        expect(decl(sheet, 'width'), '210mm');
        expect(decl(sheet, 'min-height'), '297mm');
        expect(decl(sheet, 'padding'), '0 40pt 18px');
      }
    });
  });

  group('the PDF layout', () {
    late PdfTextMetrics metrics;

    setUpAll(() {
      metrics = PdfTextMetrics(
        banglaFontData: ByteData.sublistView(
            File('assets/fonts/SutonnyMJ Regular.ttf').readAsBytesSync()),
        symbolFontData: ByteData.sublistView(
            File('assets/fonts/MathSymbols.ttf').readAsBytesSync()),
      );
    });

    test('every height estimator grows with the step', () {
      final cq = cqTest('উদ্দীপক পাঠ করে নিচের প্রশ্নগুলোর উত্তর দাও।');
      final rq = rqTest('সংক্ষেপে উত্তর দাও।');
      final mcq = mcqTest('নিচের কোনটি সঠিক?');

      double rqHeight({double fontStep = 0}) => PdfLayout.rqHeight(
          index: 1,
          question: rq,
          columnWidth: 260,
          metrics: metrics,
          fontStep: fontStep);
      double cqHeight({double fontStep = 0}) => PdfLayout.cqHeight(
            index: 1,
            question: cq,
            columnWidth: 260,
            metrics: metrics,
            hasImage: false,
            imageSize: StemImageSize.medium,
            fontStep: fontStep,
          );
      double mcqHeight({double fontStep = 0}) => PdfLayout.mcqHeight(
            index: 1,
            question: mcq,
            columnWidth: 260,
            metrics: metrics,
            fontStep: fontStep,
          );

      final grew = {
        'rqHeight': rqHeight(fontStep: 4) > rqHeight(),
        'cqHeight': cqHeight(fontStep: 4) > cqHeight(),
        'mcqHeight': mcqHeight(fontStep: 4) > mcqHeight(),
        'headerHeight': PdfLayout.headerHeight(
              metrics: metrics,
              schoolName: 'S',
              examName: 'E',
              subject: 'গণিত',
              className: 'C',
              time: 'T',
              totalMarks: '10',
              fontStep: 4,
            ) >
            PdfLayout.headerHeight(
              metrics: metrics,
              schoolName: 'S',
              examName: 'E',
              subject: 'গণিত',
              className: 'C',
              time: 'T',
              totalMarks: '10',
            ),
        'sectionBannerHeight':
            PdfLayout.sectionBannerHeight(metrics, fontStep: 4) >
                PdfLayout.sectionBannerHeight(metrics),
      };

      for (final entry in grew.entries) {
        expect(entry.value, isTrue,
            reason: '${entry.key} ignores the font step');
      }
    });

    test('a stepped row grows by more when it wraps', () {
      // A narrow column forces the same text onto more lines as it grows, so the
      // estimator has to follow the metrics rather than just add the step: this
      // catches a `fontSize + fontStep` that never reached the line estimate.
      final rq = rqTest('সংক্ষেপে উত্তর দাও এবং যুক্তি দাও।');
      final base = PdfLayout.rqHeight(
          index: 1, question: rq, columnWidth: 90, metrics: metrics);
      final up = PdfLayout.rqHeight(
          index: 1,
          question: rq,
          columnWidth: 90,
          metrics: metrics,
          fontStep: 6);

      expect(up, greaterThan(base));
      expect(up - base, greaterThan(PdfLayout.rqGap));
    });
  });
}
